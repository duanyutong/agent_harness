from __future__ import annotations

import json
import random
import time
from pathlib import Path
from typing import Annotated

from cyclopts import App, Parameter

from pr_review_poller.config import example_config, load_config
from pr_review_poller.service import Poller
from pr_review_poller.state import StateStore

app = App(help="Poll GitHub review requests and run a local agent for ready pull requests.")
DEFAULT_CONFIG = Path("~/.config/pr-review-poller.toml").expanduser()


@app.command
def init_config() -> None:
    """Print an example configuration file."""
    print(example_config(), end="")


@app.command
def poll(config: Annotated[Path, Parameter(["--config", "-c"])] = DEFAULT_CONFIG) -> None:
    """Run one polling cycle."""
    poller = Poller(config=load_config(config))
    summary = poller.poll_once()
    print(summary.model_dump_json(indent=2))


@app.command
def watch(config: Annotated[Path, Parameter(["--config", "-c"])] = DEFAULT_CONFIG) -> None:
    """Run polling cycles continuously in the foreground."""
    loaded = load_config(config)
    poller = Poller(config=loaded)
    while True:
        summary = poller.poll_once()
        print(summary.model_dump_json(indent=2), flush=True)
        time.sleep(_jittered_sleep(loaded.poll_interval_seconds, loaded.poll_jitter_percent))


@app.command
def check_pr(
    repo: str,
    pr_number: int,
    config: Annotated[Path, Parameter(["--config", "-c"])] = DEFAULT_CONFIG,
    *,
    run_agent: bool = False,
) -> None:
    """Check one pull request's readiness, optionally invoking the agent."""
    poller = Poller(config=load_config(config))
    summary = poller.check_pr(repo, pr_number, run_agent=run_agent)
    print(summary.model_dump_json(indent=2))


@app.command
def history(
    repo: str,
    pr_number: int,
    config: Annotated[Path, Parameter(["--config", "-c"])] = DEFAULT_CONFIG,
) -> None:
    """List attempt directories for one pull request."""
    loaded = load_config(config)
    store = StateStore(storage_dir=loaded.storage_dir)
    for attempt in store.list_attempts(repo, pr_number):
        print(attempt)


@app.command
def show_run(
    repo: str,
    pr_number: int,
    run_id: str,
    config: Annotated[Path, Parameter(["--config", "-c"])] = DEFAULT_CONFIG,
) -> None:
    """Print metadata for a specific run or attempt."""
    loaded = load_config(config)
    store = StateStore(storage_dir=loaded.storage_dir)
    decision_path = store.paths_for(repo, pr_number).attempts / run_id / "decision.json"
    with decision_path.open("r", encoding="utf-8") as file:
        print(json.dumps(json.load(file), indent=2, sort_keys=True))


@app.command
def mark_reviewed(
    repo: str,
    pr_number: int,
    config: Annotated[Path, Parameter(["--config", "-c"])] = DEFAULT_CONFIG,
) -> None:
    """Mark the current prepared report as reviewed locally."""
    poller = Poller(config=load_config(config))
    path = poller.mark_reviewed(repo, pr_number)
    print(path)


def _jittered_sleep(interval_seconds: int, jitter_percent: int) -> float:
    spread = interval_seconds * (jitter_percent / 100)
    return random.uniform(interval_seconds - spread, interval_seconds + spread)


if __name__ == "__main__":
    app()
