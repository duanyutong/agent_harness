from __future__ import annotations

from pathlib import Path

from pr_review_poller.agent import write_prompt


class TestAgentPrompt:
    @staticmethod
    def test_prompt_contains_only_url_and_report_path(tmp_path: Path) -> None:
        prompt = tmp_path / "prompt.txt"
        report = tmp_path / "report.md"

        write_prompt(
            prompt_path=prompt,
            pr_url="https://github.com/owner/repo/pull/1",
            report_path=report,
        )

        assert prompt.read_text(encoding="utf-8") == (
            f"https://github.com/owner/repo/pull/1\nWrite your result to:\n{report}\n"
        )
