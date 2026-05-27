from __future__ import annotations

import json
from datetime import UTC, datetime, timedelta
from pathlib import Path

from pr_review_poller.github import PullRequestDetails
from pr_review_poller.state import (
    StateStore,
    make_decision,
    should_skip_awaiting_review,
    should_skip_cooldown,
)


def make_pr() -> PullRequestDetails:
    return PullRequestDetails.model_validate(
        {
            "number": 1,
            "url": "https://github.com/owner/repo/pull/1",
            "title": "Title",
            "state": "OPEN",
            "isDraft": False,
            "baseRefOid": "base",
            "headRefOid": "head",
            "mergeable": "MERGEABLE",
            "mergeStateStatus": "CLEAN",
            "reviewRequests": [{"login": "reviewer"}],
            "statusCheckRollup": [{"status": "COMPLETED", "conclusion": "SUCCESS"}],
        },
    )


class TestStateStore:
    @staticmethod
    def test_agent_run_writes_attempt_and_latest(tmp_path: Path) -> None:
        store = StateStore(storage_dir=tmp_path)
        pr = make_pr()
        now = datetime.now(UTC)
        latest = store.ensure_latest("owner/repo", pr, now=now)
        attempt = store.create_attempt_dir(
            "owner/repo", pr.number, checked_at=now, kind="agent-run"
        )
        decision = make_decision(
            repo="owner/repo",
            pr=pr,
            attempt_id=attempt.name,
            decision="agent_run",
            checked_at=now,
            ready=True,
            reason=None,
            report_path=attempt / "report.md",
            agent_exit_code=0,
        )

        decision_path = store.write_decision(attempt, decision)
        latest = store.update_latest_from_decision(
            latest,
            decision=decision,
            decision_path=decision_path,
            not_ready_cooldown_seconds=900,
            agent_run_cooldown_seconds=3600,
        )
        store.write_latest(latest)

        assert decision_path.exists()
        assert store.paths_for("owner/repo", 1).latest.exists()
        assert should_skip_awaiting_review(store.read_latest("owner/repo", 1), "base:head")
        with decision_path.open("r", encoding="utf-8") as file:
            data = json.load(file)
        assert data["diff_fingerprint"] == "base:head"

    @staticmethod
    def test_cooldown_suppresses_same_pr(tmp_path: Path) -> None:
        store = StateStore(storage_dir=tmp_path)
        pr = make_pr()
        now = datetime.now(UTC)
        latest = store.ensure_latest("owner/repo", pr, now=now)
        attempt = store.create_attempt_dir(
            "owner/repo", pr.number, checked_at=now, kind="not-ready"
        )
        decision = make_decision(
            repo="owner/repo",
            pr=pr,
            attempt_id=attempt.name,
            decision="not_ready",
            checked_at=now,
            ready=False,
            reason="ci_pending",
        )

        decision_path = store.write_decision(attempt, decision)
        latest = store.update_latest_from_decision(
            latest,
            decision=decision,
            decision_path=decision_path,
            not_ready_cooldown_seconds=900,
            agent_run_cooldown_seconds=3600,
        )

        assert should_skip_cooldown(latest, now + timedelta(seconds=10))
        assert not should_skip_cooldown(latest, now + timedelta(seconds=901))
