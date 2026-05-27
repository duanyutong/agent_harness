from __future__ import annotations

import string
import tomllib
from pathlib import Path
from typing import Self

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


class PollerConfig(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, validate_default=True)

    skill_name: str = "review-gh-pr"
    storage_dir: Path = Path("~/.local/share/pr-review-poller")
    poll_interval_seconds: int = Field(default=120, ge=1)
    poll_jitter_percent: int = Field(default=15, ge=0, le=100)
    zero_checks_grace_seconds: int = Field(default=60, ge=0)
    max_concurrent_agents: int = Field(default=1, ge=1)
    stale_check_seconds: int = Field(default=300, ge=0)
    not_ready_cooldown_seconds: int = Field(default=900, ge=0)
    agent_run_cooldown_seconds: int = Field(default=3600, ge=0)
    min_rate_limit_remaining: int = Field(default=100, ge=0)
    repos: tuple[str, ...] = ()
    extra_search_queries: tuple[str, ...] = ()
    agent_command: tuple[str, ...] = (
        "cursor-agent",
        "--skill",
        "{skill_name}",
        "--prompt-file",
        "{prompt_file}",
    )
    reviewer: str | None = None
    team_reviewers: tuple[str, ...] = ()

    @field_validator("storage_dir", mode="before")
    @classmethod
    def _expand_storage_dir(cls, value: str | Path) -> Path:
        return Path(value).expanduser()

    @field_validator("repos")
    @classmethod
    def _validate_repos(cls, value: tuple[str, ...]) -> tuple[str, ...]:
        for repo in value:
            if repo.count("/") != 1 or not all(repo.split("/", maxsplit=1)):
                msg = f"repository must use OWNER/REPO format: {repo!r}"
                raise ValueError(msg)
        return value

    @field_validator("agent_command")
    @classmethod
    def _validate_agent_command(cls, value: tuple[str, ...]) -> tuple[str, ...]:
        if not value:
            msg = "agent_command must contain at least one argument"
            raise ValueError(msg)
        if any(not part for part in value):
            msg = "agent_command entries must be non-empty strings"
            raise ValueError(msg)
        return value

    @model_validator(mode="after")
    def _validate_search_targets(self) -> Self:
        if not self.repos and not self.extra_search_queries:
            msg = "configure at least one repository or extra_search_queries entry"
            raise ValueError(msg)
        return self


class TemplateContext(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True, validate_default=True)

    skill_name: str
    prompt_file: Path
    repo: str
    owner: str
    repo_name: str
    pr_number: int
    pr_url: str
    base_ref_oid: str
    head_ref_oid: str
    diff_fingerprint: str
    storage_dir: Path
    report_path: Path

    def as_strings(self) -> dict[str, str]:
        return {
            "skill_name": self.skill_name,
            "prompt_file": str(self.prompt_file),
            "repo": self.repo,
            "owner": self.owner,
            "repo_name": self.repo_name,
            "pr_number": str(self.pr_number),
            "pr_url": self.pr_url,
            "base_ref_oid": self.base_ref_oid,
            "head_ref_oid": self.head_ref_oid,
            "diff_fingerprint": self.diff_fingerprint,
            "storage_dir": str(self.storage_dir),
            "report_path": str(self.report_path),
        }


def load_config(path: Path) -> PollerConfig:
    with path.expanduser().open("rb") as file:
        data = tomllib.load(file)
    return PollerConfig.model_validate(data)


def render_command(command: tuple[str, ...], context: TemplateContext) -> list[str]:
    values = context.as_strings()
    return [_render_template_part(part, values) for part in command]


def _render_template_part(template: str, values: dict[str, str]) -> str:
    names = {
        field_name
        for _, field_name, _, _ in string.Formatter().parse(template)
        if field_name is not None
    }
    unknown = names - values.keys()
    if unknown:
        msg = f"unknown template variables: {', '.join(sorted(unknown))}"
        raise ValueError(msg)
    return template.format(**values)


def example_config() -> str:
    default_storage = Path("~/.local/share/pr-review-poller").expanduser()
    return f"""skill_name = "review-gh-pr"
storage_dir = "{default_storage}"
poll_interval_seconds = 120
poll_jitter_percent = 15
zero_checks_grace_seconds = 60
max_concurrent_agents = 1

repos = ["OWNER/REPO"]
extra_search_queries = []

agent_command = [
  "cursor-agent",
  "--skill",
  "{{skill_name}}",
  "--prompt-file",
  "{{prompt_file}}",
]
"""
