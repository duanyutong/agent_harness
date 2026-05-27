from __future__ import annotations

import json
import subprocess
from datetime import UTC, datetime
from enum import StrEnum
from typing import Any, cast

from pydantic import BaseModel, ConfigDict, Field, field_validator


class ReadinessReason(StrEnum):
    READY = "ready"
    DRAFT = "draft"
    NOT_OPEN = "not_open"
    REVIEW_NOT_REQUESTED = "review_not_requested"
    MERGE_CONFLICT = "merge_conflict"
    CI_PENDING = "ci_pending"
    CI_FAILED = "ci_failed"
    ZERO_CHECKS_GRACE = "zero_checks_grace"


class PullRequestSummary(BaseModel):
    model_config = ConfigDict(extra="allow", frozen=True, validate_default=True)

    number: int
    url: str
    title: str = ""
    base_ref_oid: str = Field(default="", alias="baseRefOid")
    head_ref_oid: str = Field(default="", alias="headRefOid")
    is_draft: bool = Field(default=False, alias="isDraft")
    review_requests: tuple[dict[str, Any], ...] = Field(default=(), alias="reviewRequests")
    created_at: datetime | None = Field(default=None, alias="createdAt")
    updated_at: datetime | None = Field(default=None, alias="updatedAt")

    @field_validator("created_at", "updated_at", mode="before")
    @classmethod
    def _parse_datetime(cls, value: str | datetime | None) -> datetime | None:
        if value is None or isinstance(value, datetime):
            return value
        return datetime.fromisoformat(value.replace("Z", "+00:00"))


class PullRequestDetails(PullRequestSummary):
    state: str = "OPEN"
    mergeable: str | None = None
    merge_state_status: str | None = Field(default=None, alias="mergeStateStatus")
    status_check_rollup: tuple[dict[str, Any], ...] = Field(
        default=(),
        alias="statusCheckRollup",
    )

    @property
    def diff_fingerprint(self) -> str:
        return f"{self.base_ref_oid}:{self.head_ref_oid}"


class Readiness(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, validate_default=True)

    ready: bool
    reason: ReadinessReason
    message: str


class GhClient:
    def __init__(self, *, executable: str = "gh") -> None:
        self._executable = executable

    def current_login(self) -> str:
        return self._run_text(("api", "user", "--jq", ".login")).strip()

    def rate_limit_remaining(self) -> int | None:
        data = self._run_json(("api", "rate_limit"))
        core = data.get("resources", {}).get("core", {})
        remaining = core.get("remaining")
        return remaining if isinstance(remaining, int) else None

    def list_review_requested_prs(
        self,
        repo: str,
        extra_queries: tuple[str, ...],
    ) -> list[PullRequestSummary]:
        queries = ["is:pr is:open review-requested:@me -is:draft", *extra_queries]
        by_key: dict[tuple[str, int], PullRequestSummary] = {}
        for query in queries:
            data = self._run_json(
                (
                    "pr",
                    "list",
                    "--repo",
                    repo,
                    "--state",
                    "open",
                    "--search",
                    query,
                    "--limit",
                    "50",
                    "--json",
                    "number,url,title,baseRefOid,headRefOid,isDraft,reviewRequests,createdAt,updatedAt",
                ),
            )
            for item in data:
                summary = PullRequestSummary.model_validate(item)
                by_key[(repo, summary.number)] = summary
        return list(by_key.values())

    def view_pr(self, repo: str, number: int) -> PullRequestDetails:
        data = self._run_json(
            (
                "pr",
                "view",
                str(number),
                "--repo",
                repo,
                "--json",
                (
                    "number,url,title,state,isDraft,baseRefOid,headRefOid,mergeable,"
                    "mergeStateStatus,reviewRequests,statusCheckRollup,createdAt,updatedAt"
                ),
            ),
        )
        return PullRequestDetails.model_validate(data)

    def _run_json(self, args: tuple[str, ...]) -> Any:
        output = self._run_text(args)
        if output.strip() == "":
            return None
        return json.loads(output)

    def _run_text(self, args: tuple[str, ...]) -> str:
        completed = subprocess.run(
            (self._executable, *args),
            check=True,
            capture_output=True,
            text=True,
        )
        return completed.stdout


def evaluate_readiness(
    pr: PullRequestDetails,
    *,
    reviewer: str,
    team_reviewers: tuple[str, ...],
    first_seen_published_at: datetime,
    now: datetime,
    zero_checks_grace_seconds: int,
) -> Readiness:
    if pr.is_draft:
        return _not_ready(ReadinessReason.DRAFT, "pull request is still a draft")
    if pr.state.upper() != "OPEN":
        return _not_ready(ReadinessReason.NOT_OPEN, f"pull request state is {pr.state}")
    if not is_review_requested(
        pr.review_requests, reviewer=reviewer, team_reviewers=team_reviewers
    ):
        return _not_ready(ReadinessReason.REVIEW_NOT_REQUESTED, "review is no longer requested")
    if has_merge_conflict(pr):
        return _not_ready(ReadinessReason.MERGE_CONFLICT, "pull request has a merge conflict")

    check_result = evaluate_checks(
        pr.status_check_rollup,
        first_seen_published_at=first_seen_published_at,
        now=now,
        zero_checks_grace_seconds=zero_checks_grace_seconds,
    )
    if check_result is not ReadinessReason.READY:
        message = (
            "status checks are pending"
            if check_result is ReadinessReason.CI_PENDING
            else check_result.value
        )
        return _not_ready(check_result, message)

    return Readiness(ready=True, reason=ReadinessReason.READY, message="pull request is ready")


def is_review_requested(
    review_requests: tuple[dict[str, Any], ...],
    *,
    reviewer: str,
    team_reviewers: tuple[str, ...],
) -> bool:
    reviewers = {reviewer, *team_reviewers}
    for request in review_requests:
        login = _request_login(request)
        if login in reviewers:
            return True
    return False


def has_merge_conflict(pr: PullRequestDetails) -> bool:
    mergeable = (pr.mergeable or "").upper()
    merge_state_status = (pr.merge_state_status or "").upper()
    conflict_states = {"CONFLICTING", "DIRTY", "UNKNOWN"}
    return mergeable in conflict_states or merge_state_status in conflict_states


def evaluate_checks(
    rollup: tuple[dict[str, Any], ...],
    *,
    first_seen_published_at: datetime,
    now: datetime,
    zero_checks_grace_seconds: int,
) -> ReadinessReason:
    if not rollup:
        age_seconds = (now - first_seen_published_at).total_seconds()
        if age_seconds < zero_checks_grace_seconds:
            return ReadinessReason.ZERO_CHECKS_GRACE
        return ReadinessReason.READY

    saw_pending = False
    for check in rollup:
        state = _check_state(check)
        if state == "success":
            continue
        if state == "pending":
            saw_pending = True
            continue
        return ReadinessReason.CI_FAILED
    return ReadinessReason.CI_PENDING if saw_pending else ReadinessReason.READY


def _request_login(request: dict[str, Any]) -> str | None:
    for key in ("login", "slug", "name"):
        value = request.get(key)
        if isinstance(value, str):
            return value
    for nested_key in ("requestedReviewer", "reviewer", "team"):
        nested = request.get(nested_key)
        if isinstance(nested, dict):
            nested_login = _request_login(cast("dict[str, Any]", nested))
            if nested_login is not None:
                return nested_login
    return None


def _check_state(check: dict[str, Any]) -> str:
    status = str(check.get("status", "")).upper()
    conclusion = str(check.get("conclusion", "")).upper()
    state = str(check.get("state", "")).upper()

    if conclusion in {"SUCCESS", "NEUTRAL", "SKIPPED"} or state == "SUCCESS":
        return "success"
    if conclusion in {"FAILURE", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED"}:
        return "failed"
    if state in {"FAILURE", "ERROR"}:
        return "failed"
    if status in {"QUEUED", "IN_PROGRESS", "PENDING", "REQUESTED", "WAITING"}:
        return "pending"
    if state in {"PENDING", "EXPECTED"}:
        return "pending"
    if conclusion == "":
        return "pending"
    return "failed"


def _not_ready(reason: ReadinessReason, message: str) -> Readiness:
    return Readiness(ready=False, reason=reason, message=message)


def now_utc() -> datetime:
    return datetime.now(UTC)
