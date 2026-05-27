from __future__ import annotations

import json
import os
import re
from datetime import UTC, datetime, timedelta
from pathlib import Path
from typing import Any, Literal

from pydantic import BaseModel, ConfigDict, field_validator

from pr_review_poller.github import PullRequestDetails

DecisionKind = Literal["not_ready", "agent_run", "skipped", "marked_reviewed"]

_ATTEMPT_SAFE = re.compile(r"[^A-Za-z0-9_.-]+")


class LatestState(BaseModel):
    model_config = ConfigDict(extra="allow", validate_default=True)

    repo: str
    pr_number: int
    url: str
    latest_attempt_id: str | None = None
    latest_decision_path: Path | None = None
    first_seen_published_at: datetime | None = None
    last_candidate_seen_at: datetime | None = None
    last_eligibility_check_at: datetime | None = None
    last_processed_diff_fingerprint: str | None = None
    awaiting_user_review_diff_fingerprint: str | None = None
    last_agent_run_attempt: str | None = None
    latest_report_path: Path | None = None
    cooldown_until: datetime | None = None

    @field_validator(
        "first_seen_published_at",
        "last_candidate_seen_at",
        "last_eligibility_check_at",
        "cooldown_until",
        mode="before",
    )
    @classmethod
    def _parse_datetime(cls, value: str | datetime | None) -> datetime | None:
        if value is None or isinstance(value, datetime):
            return value
        return datetime.fromisoformat(value.replace("Z", "+00:00"))

    @field_validator("latest_decision_path", "latest_report_path", mode="before")
    @classmethod
    def _parse_path(cls, value: str | Path | None) -> Path | None:
        if value is None or isinstance(value, Path):
            return value
        return Path(value)


class Decision(BaseModel):
    model_config = ConfigDict(extra="forbid", validate_default=True)

    repo: str
    pr_number: int
    url: str
    attempt_id: str
    decision: DecisionKind
    base_ref_oid: str
    head_ref_oid: str
    diff_fingerprint: str
    updated_at: datetime | None
    checked_at: datetime
    ready: bool
    reason: str | None
    review_state: str | None = None
    report_path: Path | None = None
    agent_exit_code: int | None = None
    command: tuple[str, ...] = ()
    message: str | None = None

    @field_validator("updated_at", "checked_at", mode="before")
    @classmethod
    def _parse_datetime(cls, value: str | datetime | None) -> datetime | None:
        if value is None or isinstance(value, datetime):
            return value
        return datetime.fromisoformat(value.replace("Z", "+00:00"))

    @field_validator("report_path", mode="before")
    @classmethod
    def _parse_path(cls, value: str | Path | None) -> Path | None:
        if value is None or isinstance(value, Path):
            return value
        return Path(value)


class PrPaths(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, validate_default=True)

    root: Path
    latest: Path
    attempts: Path


class StateStore:
    def __init__(self, *, storage_dir: Path) -> None:
        self._storage_dir = storage_dir.expanduser()

    def paths_for(self, repo: str, pr_number: int) -> PrPaths:
        owner, repo_name = repo.split("/", maxsplit=1)
        root = self._storage_dir / owner / repo_name / str(pr_number)
        return PrPaths(root=root, latest=root / "latest.json", attempts=root / "attempts")

    def read_latest(self, repo: str, pr_number: int) -> LatestState | None:
        path = self.paths_for(repo, pr_number).latest
        if not path.exists():
            return None
        with path.open("r", encoding="utf-8") as file:
            return LatestState.model_validate(json.load(file))

    def ensure_latest(self, repo: str, pr: PullRequestDetails, *, now: datetime) -> LatestState:
        latest = self.read_latest(repo, pr.number)
        if latest is not None:
            return latest
        first_seen = now if not pr.is_draft else None
        return LatestState(
            repo=repo,
            pr_number=pr.number,
            url=pr.url,
            first_seen_published_at=first_seen,
            last_candidate_seen_at=now,
        )

    def note_published_seen(
        self,
        latest: LatestState,
        *,
        pr: PullRequestDetails,
        now: datetime,
    ) -> LatestState:
        data = latest.model_dump()
        data["url"] = pr.url
        data["last_candidate_seen_at"] = now
        if data.get("first_seen_published_at") is None and not pr.is_draft:
            data["first_seen_published_at"] = now
        return LatestState.model_validate(data)

    def create_attempt_dir(
        self, repo: str, pr_number: int, *, checked_at: datetime, kind: str
    ) -> Path:
        paths = self.paths_for(repo, pr_number)
        paths.attempts.mkdir(parents=True, exist_ok=True)
        base = f"{_format_attempt_time(checked_at)}-{_safe_name(kind)}"
        attempt = paths.attempts / base
        counter = 1
        while attempt.exists():
            counter += 1
            attempt = paths.attempts / f"{base}-{counter}"
        attempt.mkdir()
        return attempt

    def write_decision(self, attempt_dir: Path, decision: Decision) -> Path:
        path = attempt_dir / "decision.json"
        _atomic_write_json(path, decision.model_dump(mode="json"))
        return path

    def write_latest(self, latest: LatestState) -> None:
        paths = self.paths_for(latest.repo, latest.pr_number)
        paths.root.mkdir(parents=True, exist_ok=True)
        _atomic_write_json(paths.latest, latest.model_dump(mode="json"))

    def update_latest_from_decision(
        self,
        latest: LatestState,
        *,
        decision: Decision,
        decision_path: Path,
        not_ready_cooldown_seconds: int,
        agent_run_cooldown_seconds: int,
    ) -> LatestState:
        data = latest.model_dump()
        data.update(
            {
                "repo": decision.repo,
                "pr_number": decision.pr_number,
                "url": decision.url,
                "latest_attempt_id": decision.attempt_id,
                "latest_decision_path": decision_path,
                "last_eligibility_check_at": decision.checked_at,
                "base_ref_oid": decision.base_ref_oid,
                "head_ref_oid": decision.head_ref_oid,
                "diff_fingerprint": decision.diff_fingerprint,
                "updated_at": (
                    decision.updated_at.isoformat() if decision.updated_at is not None else None
                ),
            },
        )
        if decision.decision == "agent_run":
            data["last_processed_diff_fingerprint"] = decision.diff_fingerprint
            data["awaiting_user_review_diff_fingerprint"] = decision.diff_fingerprint
            data["last_agent_run_attempt"] = decision.attempt_id
            data["latest_report_path"] = decision.report_path
            data["cooldown_until"] = decision.checked_at + timedelta(
                seconds=agent_run_cooldown_seconds
            )
        elif decision.decision == "not_ready":
            data["cooldown_until"] = decision.checked_at + timedelta(
                seconds=not_ready_cooldown_seconds
            )
        elif decision.decision == "marked_reviewed":
            data["awaiting_user_review_diff_fingerprint"] = None
            data["cooldown_until"] = None
        return LatestState.model_validate(data)

    def list_attempts(self, repo: str, pr_number: int) -> list[Path]:
        attempts = self.paths_for(repo, pr_number).attempts
        if not attempts.exists():
            return []
        return sorted(path for path in attempts.iterdir() if path.is_dir())


def should_skip_awaiting_review(latest: LatestState | None, diff_fingerprint: str) -> bool:
    return latest is not None and latest.awaiting_user_review_diff_fingerprint == diff_fingerprint


def should_skip_cooldown(latest: LatestState | None, now: datetime) -> bool:
    if latest is None or latest.cooldown_until is None:
        return False
    cooldown = latest.cooldown_until
    if cooldown.tzinfo is None:
        cooldown = cooldown.replace(tzinfo=UTC)
    return cooldown > now


def should_skip_stale_detail(
    latest: LatestState | None,
    *,
    candidate_updated_at: datetime | None,
    candidate_head_ref_oid: str,
    now: datetime,
    stale_check_seconds: int,
) -> bool:
    if latest is None or latest.last_eligibility_check_at is None:
        return False
    if latest.awaiting_user_review_diff_fingerprint is not None:
        return False
    last_check = latest.last_eligibility_check_at
    if last_check.tzinfo is None:
        last_check = last_check.replace(tzinfo=UTC)
    if (now - last_check).total_seconds() >= stale_check_seconds:
        return False
    latest_updated_at = latest.model_extra.get("updated_at") if latest.model_extra else None
    if isinstance(latest_updated_at, str) and candidate_updated_at is not None:
        return latest_updated_at == candidate_updated_at.isoformat()
    latest_head = latest.model_extra.get("head_ref_oid") if latest.model_extra else None
    return latest_head == candidate_head_ref_oid


def make_decision(
    *,
    repo: str,
    pr: PullRequestDetails,
    attempt_id: str,
    decision: DecisionKind,
    checked_at: datetime,
    ready: bool,
    reason: str | None,
    report_path: Path | None = None,
    agent_exit_code: int | None = None,
    command: tuple[str, ...] = (),
    message: str | None = None,
) -> Decision:
    return Decision(
        repo=repo,
        pr_number=pr.number,
        url=pr.url,
        attempt_id=attempt_id,
        decision=decision,
        base_ref_oid=pr.base_ref_oid,
        head_ref_oid=pr.head_ref_oid,
        diff_fingerprint=pr.diff_fingerprint,
        updated_at=pr.updated_at,
        checked_at=checked_at,
        ready=ready,
        reason=reason,
        review_state="awaiting_user_review" if decision == "agent_run" else None,
        report_path=report_path,
        agent_exit_code=agent_exit_code,
        command=command,
        message=message,
    )


def _atomic_write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    with temp.open("w", encoding="utf-8") as file:
        json.dump(data, file, indent=2, sort_keys=True)
        file.write("\n")
    temp.replace(path)


def _format_attempt_time(value: datetime) -> str:
    if value.tzinfo is None:
        value = value.replace(tzinfo=UTC)
    value = value.astimezone(UTC).replace(microsecond=0)
    return value.isoformat().replace("+00:00", "Z").replace(":", "-")


def _safe_name(value: str) -> str:
    return _ATTEMPT_SAFE.sub("-", value).strip("-")
