from __future__ import annotations

import subprocess
from pathlib import Path

from pydantic import BaseModel, ConfigDict

from pr_review_poller.config import PollerConfig, TemplateContext, render_command
from pr_review_poller.github import PullRequestDetails


class AgentResult(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, validate_default=True)

    command: tuple[str, ...]
    exit_code: int
    prompt_path: Path
    report_path: Path
    stdout_path: Path
    stderr_path: Path


def write_prompt(*, prompt_path: Path, pr_url: str, report_path: Path) -> None:
    prompt_path.write_text(
        f"{pr_url}\nWrite your result to:\n{report_path}\n",
        encoding="utf-8",
    )


class AgentRunner:
    def __init__(self, *, config: PollerConfig) -> None:
        self._config = config

    def run(self, *, repo: str, pr: PullRequestDetails, attempt_dir: Path) -> AgentResult:
        owner, repo_name = repo.split("/", maxsplit=1)
        prompt_path = attempt_dir / "prompt.txt"
        report_path = attempt_dir / "report.md"
        stdout_path = attempt_dir / "stdout.log"
        stderr_path = attempt_dir / "stderr.log"
        write_prompt(prompt_path=prompt_path, pr_url=pr.url, report_path=report_path)

        context = TemplateContext(
            skill_name=self._config.skill_name,
            prompt_file=prompt_path,
            repo=repo,
            owner=owner,
            repo_name=repo_name,
            pr_number=pr.number,
            pr_url=pr.url,
            base_ref_oid=pr.base_ref_oid,
            head_ref_oid=pr.head_ref_oid,
            diff_fingerprint=pr.diff_fingerprint,
            storage_dir=self._config.storage_dir,
            report_path=report_path,
        )
        command = tuple(render_command(self._config.agent_command, context))

        completed = subprocess.run(
            command,
            check=False,
            capture_output=True,
            text=True,
        )
        stdout_path.write_text(completed.stdout, encoding="utf-8")
        stderr_path.write_text(completed.stderr, encoding="utf-8")
        if not report_path.exists():
            report_path.write_text("", encoding="utf-8")

        return AgentResult(
            command=command,
            exit_code=completed.returncode,
            prompt_path=prompt_path,
            report_path=report_path,
            stdout_path=stdout_path,
            stderr_path=stderr_path,
        )
