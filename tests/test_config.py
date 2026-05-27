from __future__ import annotations

from pathlib import Path

import pytest

from pr_review_poller.config import PollerConfig, TemplateContext, render_command


class TestConfig:
    @staticmethod
    def test_render_command_uses_argv_safe_template_values(tmp_path: Path) -> None:
        context = TemplateContext(
            skill_name="review-gh-pr",
            prompt_file=tmp_path / "prompt.txt",
            repo="owner/repo",
            owner="owner",
            repo_name="repo",
            pr_number=123,
            pr_url="https://github.com/owner/repo/pull/123",
            base_ref_oid="base",
            head_ref_oid="head",
            diff_fingerprint="base:head",
            storage_dir=tmp_path,
            report_path=tmp_path / "report.md",
        )

        command = render_command(
            ("agent", "--skill={skill_name}", "--prompt-file", "{prompt_file}"),
            context,
        )

        assert command == [
            "agent",
            "--skill=review-gh-pr",
            "--prompt-file",
            str(tmp_path / "prompt.txt"),
        ]

    @staticmethod
    def test_unknown_template_variable_fails(tmp_path: Path) -> None:
        context = TemplateContext(
            skill_name="review-gh-pr",
            prompt_file=tmp_path / "prompt.txt",
            repo="owner/repo",
            owner="owner",
            repo_name="repo",
            pr_number=123,
            pr_url="https://github.com/owner/repo/pull/123",
            base_ref_oid="base",
            head_ref_oid="head",
            diff_fingerprint="base:head",
            storage_dir=tmp_path,
            report_path=tmp_path / "report.md",
        )

        with pytest.raises(ValueError, match="unknown template variables"):
            render_command(("{missing}",), context)

    @staticmethod
    def test_config_requires_search_target() -> None:
        with pytest.raises(ValueError, match="at least one repo"):
            PollerConfig(repos=())
