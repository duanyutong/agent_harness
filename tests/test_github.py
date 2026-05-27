from __future__ import annotations

from datetime import UTC, datetime, timedelta

import pytest

from pr_review_poller.github import (
    PullRequestDetails,
    ReadinessReason,
    evaluate_checks,
    evaluate_readiness,
)


def make_pr(**overrides: object) -> PullRequestDetails:
    data: dict[str, object] = {
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
    }
    data.update(overrides)
    return PullRequestDetails.model_validate(data)


class TestReadiness:
    @staticmethod
    def test_draft_never_ready() -> None:
        readiness = evaluate_readiness(
            make_pr(isDraft=True),
            reviewer="reviewer",
            team_reviewers=(),
            first_seen_published_at=datetime.now(UTC),
            now=datetime.now(UTC),
            zero_checks_grace_seconds=60,
        )

        assert readiness.reason is ReadinessReason.DRAFT

    @staticmethod
    def test_merge_conflict_never_ready() -> None:
        readiness = evaluate_readiness(
            make_pr(mergeable="CONFLICTING"),
            reviewer="reviewer",
            team_reviewers=(),
            first_seen_published_at=datetime.now(UTC),
            now=datetime.now(UTC),
            zero_checks_grace_seconds=60,
        )

        assert readiness.reason is ReadinessReason.MERGE_CONFLICT

    @staticmethod
    def test_pending_checks_never_ready() -> None:
        readiness = evaluate_readiness(
            make_pr(statusCheckRollup=[{"status": "IN_PROGRESS", "conclusion": None}]),
            reviewer="reviewer",
            team_reviewers=(),
            first_seen_published_at=datetime.now(UTC),
            now=datetime.now(UTC),
            zero_checks_grace_seconds=60,
        )

        assert readiness.reason is ReadinessReason.CI_PENDING

    @staticmethod
    def test_team_review_request_counts() -> None:
        readiness = evaluate_readiness(
            make_pr(reviewRequests=[{"slug": "org/team"}]),
            reviewer="reviewer",
            team_reviewers=("org/team",),
            first_seen_published_at=datetime.now(UTC),
            now=datetime.now(UTC),
            zero_checks_grace_seconds=60,
        )

        assert readiness.ready


class TestChecks:
    @staticmethod
    def test_empty_checks_inside_grace_period_are_not_ready() -> None:
        now = datetime.now(UTC)

        result = evaluate_checks(
            (),
            first_seen_published_at=now - timedelta(seconds=30),
            now=now,
            zero_checks_grace_seconds=60,
        )

        assert result is ReadinessReason.ZERO_CHECKS_GRACE

    @staticmethod
    def test_empty_checks_after_grace_period_are_ready() -> None:
        now = datetime.now(UTC)

        result = evaluate_checks(
            (),
            first_seen_published_at=now - timedelta(seconds=90),
            now=now,
            zero_checks_grace_seconds=60,
        )

        assert result is ReadinessReason.READY

    @staticmethod
    @pytest.mark.parametrize(
        ("rollup", "expected"),
        [
            ([{"status": "COMPLETED", "conclusion": "SUCCESS"}], ReadinessReason.READY),
            ([{"status": "COMPLETED", "conclusion": "FAILURE"}], ReadinessReason.CI_FAILED),
            ([{"state": "PENDING"}], ReadinessReason.CI_PENDING),
        ],
    )
    def test_check_rollup_states(
        rollup: list[dict[str, str]],
        expected: ReadinessReason,
    ) -> None:
        now = datetime.now(UTC)

        result = evaluate_checks(
            tuple(rollup),
            first_seen_published_at=now - timedelta(seconds=90),
            now=now,
            zero_checks_grace_seconds=60,
        )

        assert result is expected
