from __future__ import annotations

from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path

from pydantic import BaseModel, ConfigDict

from pr_review_poller.agent import AgentRunner
from pr_review_poller.config import PollerConfig
from pr_review_poller.github import (
    GhClient,
    PullRequestDetails,
    PullRequestSummary,
    evaluate_readiness,
    now_utc,
)
from pr_review_poller.state import (
    LatestState,
    StateStore,
    make_decision,
    should_skip_awaiting_review,
    should_skip_cooldown,
    should_skip_stale_detail,
)


class PollSummary(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, validate_default=True)

    candidates: int = 0
    checked: int = 0
    not_ready: int = 0
    skipped: int = 0
    agent_runs: int = 0
    throttled: bool = False


class Poller:
    def __init__(
        self,
        *,
        config: PollerConfig,
        gh: GhClient | None = None,
        store: StateStore | None = None,
        agent_runner: AgentRunner | None = None,
    ) -> None:
        self._config = config
        self._gh = gh or GhClient()
        self._store = store or StateStore(storage_dir=config.storage_dir)
        self._agent_runner = agent_runner or AgentRunner(config=config)

    def poll_once(self) -> PollSummary:
        now = now_utc()
        remaining = self._gh.rate_limit_remaining()
        if remaining is not None and remaining < self._config.min_rate_limit_remaining:
            return PollSummary(throttled=True)

        reviewer = self._config.reviewer or self._gh.current_login()
        candidates: list[tuple[str, PullRequestSummary]] = []
        for repo in self._config.repos:
            for candidate in self._gh.list_review_requested_prs(
                repo, self._config.extra_search_queries
            ):
                candidates.append((repo, candidate))

        checked = 0
        not_ready = 0
        skipped = 0
        ready: list[tuple[str, PullRequestDetails, LatestState]] = []

        for repo, candidate in candidates:
            latest = self._store.read_latest(repo, candidate.number)
            candidate_fingerprint = f"{candidate.base_ref_oid}:{candidate.head_ref_oid}"
            if should_skip_awaiting_review(latest, candidate_fingerprint):
                skipped += self._record_skip_once(
                    repo=repo,
                    candidate=candidate,
                    latest=latest,
                    now=now,
                    reason="awaiting_user_review",
                )
                continue
            if _same_diff(latest, candidate_fingerprint) and should_skip_cooldown(latest, now):
                continue
            if should_skip_stale_detail(
                latest,
                candidate_updated_at=candidate.updated_at,
                candidate_head_ref_oid=candidate.head_ref_oid,
                now=now,
                stale_check_seconds=self._config.stale_check_seconds,
            ):
                continue

            pr = self._gh.view_pr(repo, candidate.number)
            checked += 1
            latest = self._store.ensure_latest(repo, pr, now=now)
            latest = self._store.note_published_seen(latest, pr=pr, now=now)
            first_seen = latest.first_seen_published_at or now
            readiness = evaluate_readiness(
                pr,
                reviewer=reviewer,
                team_reviewers=self._config.team_reviewers,
                first_seen_published_at=first_seen,
                now=now,
                zero_checks_grace_seconds=self._config.zero_checks_grace_seconds,
            )
            if not readiness.ready:
                not_ready += 1
                self._record_not_ready(
                    repo=repo, pr=pr, latest=latest, now=now, reason=readiness.reason
                )
                continue
            if should_skip_awaiting_review(latest, pr.diff_fingerprint):
                skipped += self._record_skip_once(
                    repo=repo,
                    candidate=pr,
                    latest=latest,
                    now=now,
                    reason="awaiting_user_review",
                )
                continue
            ready.append((repo, pr, latest))

        agent_runs = self._run_agents(ready)
        return PollSummary(
            candidates=len(candidates),
            checked=checked,
            not_ready=not_ready,
            skipped=skipped,
            agent_runs=agent_runs,
        )

    def check_pr(self, repo: str, pr_number: int, *, run_agent: bool) -> PollSummary:
        now = now_utc()
        reviewer = self._config.reviewer or self._gh.current_login()
        pr = self._gh.view_pr(repo, pr_number)
        latest = self._store.ensure_latest(repo, pr, now=now)
        latest = self._store.note_published_seen(latest, pr=pr, now=now)
        readiness = evaluate_readiness(
            pr,
            reviewer=reviewer,
            team_reviewers=self._config.team_reviewers,
            first_seen_published_at=latest.first_seen_published_at or now,
            now=now,
            zero_checks_grace_seconds=self._config.zero_checks_grace_seconds,
        )
        if not readiness.ready:
            self._record_not_ready(
                repo=repo, pr=pr, latest=latest, now=now, reason=readiness.reason
            )
            return PollSummary(candidates=1, checked=1, not_ready=1)
        if not run_agent:
            return PollSummary(candidates=1, checked=1)
        return PollSummary(
            candidates=1, checked=1, agent_runs=self._run_agents([(repo, pr, latest)])
        )

    def mark_reviewed(self, repo: str, pr_number: int) -> Path:
        now = now_utc()
        latest = self._store.read_latest(repo, pr_number)
        if latest is None:
            msg = f"no state found for {repo}#{pr_number}"
            raise FileNotFoundError(msg)
        pr = self._gh.view_pr(repo, pr_number)
        attempt_dir = self._store.create_attempt_dir(
            repo,
            pr_number,
            checked_at=now,
            kind="marked-reviewed",
        )
        decision = make_decision(
            repo=repo,
            pr=pr,
            attempt_id=attempt_dir.name,
            decision="marked_reviewed",
            checked_at=now,
            ready=True,
            reason=None,
            message="marked as reviewed locally",
        )
        decision_path = self._store.write_decision(attempt_dir, decision)
        latest = self._store.update_latest_from_decision(
            latest,
            decision=decision,
            decision_path=decision_path,
            not_ready_cooldown_seconds=self._config.not_ready_cooldown_seconds,
            agent_run_cooldown_seconds=self._config.agent_run_cooldown_seconds,
        )
        self._store.write_latest(latest)
        return decision_path

    def _run_agents(self, ready: list[tuple[str, PullRequestDetails, LatestState]]) -> int:
        if not ready:
            return 0
        max_workers = min(self._config.max_concurrent_agents, len(ready))
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = [
                executor.submit(self._run_one_agent, repo, pr, latest) for repo, pr, latest in ready
            ]
        return sum(1 for future in futures if future.result())

    def _run_one_agent(self, repo: str, pr: PullRequestDetails, latest: LatestState) -> bool:
        now = now_utc()
        attempt_dir = self._store.create_attempt_dir(
            repo,
            pr.number,
            checked_at=now,
            kind="agent-run",
        )
        result = self._agent_runner.run(repo=repo, pr=pr, attempt_dir=attempt_dir)
        decision = make_decision(
            repo=repo,
            pr=pr,
            attempt_id=attempt_dir.name,
            decision="agent_run",
            checked_at=now,
            ready=result.exit_code == 0,
            reason=None if result.exit_code == 0 else "agent_failed",
            report_path=result.report_path,
            agent_exit_code=result.exit_code,
            command=result.command,
        )
        decision_path = self._store.write_decision(attempt_dir, decision)
        latest = self._store.update_latest_from_decision(
            latest,
            decision=decision,
            decision_path=decision_path,
            not_ready_cooldown_seconds=self._config.not_ready_cooldown_seconds,
            agent_run_cooldown_seconds=self._config.agent_run_cooldown_seconds,
        )
        self._store.write_latest(latest)
        return True

    def _record_not_ready(
        self,
        *,
        repo: str,
        pr: PullRequestDetails,
        latest: LatestState,
        now: datetime,
        reason: object,
    ) -> None:
        attempt_dir = self._store.create_attempt_dir(
            repo,
            pr.number,
            checked_at=now,
            kind="not-ready",
        )
        decision = make_decision(
            repo=repo,
            pr=pr,
            attempt_id=attempt_dir.name,
            decision="not_ready",
            checked_at=now,
            ready=False,
            reason=str(reason),
        )
        decision_path = self._store.write_decision(attempt_dir, decision)
        latest = self._store.update_latest_from_decision(
            latest,
            decision=decision,
            decision_path=decision_path,
            not_ready_cooldown_seconds=self._config.not_ready_cooldown_seconds,
            agent_run_cooldown_seconds=self._config.agent_run_cooldown_seconds,
        )
        self._store.write_latest(latest)

    def _record_skip_once(
        self,
        *,
        repo: str,
        candidate: PullRequestSummary,
        latest: LatestState | None,
        now: datetime,
        reason: str,
    ) -> int:
        if (
            latest is not None
            and latest.latest_attempt_id is not None
            and latest.latest_attempt_id.endswith(
                "-skipped",
            )
        ):
            return 0
        pr = _details_from_summary(candidate)
        if latest is None:
            latest = self._store.ensure_latest(repo, pr, now=now)
        attempt_dir = self._store.create_attempt_dir(
            repo, pr.number, checked_at=now, kind="skipped"
        )
        decision = make_decision(
            repo=repo,
            pr=pr,
            attempt_id=attempt_dir.name,
            decision="skipped",
            checked_at=now,
            ready=False,
            reason=reason,
        )
        decision_path = self._store.write_decision(attempt_dir, decision)
        latest = self._store.update_latest_from_decision(
            latest,
            decision=decision,
            decision_path=decision_path,
            not_ready_cooldown_seconds=self._config.not_ready_cooldown_seconds,
            agent_run_cooldown_seconds=self._config.agent_run_cooldown_seconds,
        )
        self._store.write_latest(latest)
        return 1


def _same_diff(latest: LatestState | None, diff_fingerprint: str) -> bool:
    if latest is None:
        return False
    latest_diff = latest.model_extra.get("diff_fingerprint") if latest.model_extra else None
    return latest_diff == diff_fingerprint


def _details_from_summary(summary: PullRequestSummary) -> PullRequestDetails:
    data = summary.model_dump(by_alias=True)
    data.update(
        {
            "state": "OPEN",
            "mergeable": None,
            "mergeStateStatus": None,
            "statusCheckRollup": [],
        },
    )
    return PullRequestDetails.model_validate(data)
