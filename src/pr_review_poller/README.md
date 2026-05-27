# PR Review Poller

`pr-review-poller` monitors GitHub pull requests for which review has been requested from the authenticated user. When a pull request is published, conflict-free, and has passing CI checks, it invokes a configurable local agent CLI and stores the report locally.

## Install

For local use, install the command on `PATH` with `uv`:

```sh
uv tool install --editable .
uv tool update-shell
```

Restart your shell, then use `pr-review-poller` directly.

For a single-file executable, use a Python packager such as `pex` or `shiv`; the result is a zip-style executable that still requires a compatible Python runtime. Fully standalone binaries via PyInstaller or Nuitka are possible, but they are larger and more brittle on macOS. For this tool, `uv tool install --editable .` is the recommended installation method.

## Usage

Create a config:

```sh
uv run pr-review-poller init-config > ~/.config/pr-review-poller.toml
```

That path is the default, so `--config` is only needed when using a different config file.

Edit the config:

```toml
skill_name = "review-gh-pr"
storage_dir = "~/.local/share/pr-review-poller"
poll_interval_seconds = 120
poll_jitter_percent = 15
zero_checks_grace_seconds = 60
max_concurrent_agents = 1

repos = ["OWNER/REPO"]

agent_command = [
  "your-agent-cli",
  "--skill",
  "{skill_name}",
  "--prompt-file",
  "{prompt_file}",
]
```

Run one polling cycle:

```sh
uv run pr-review-poller poll
```

Run continuously in the foreground:

```sh
uv run pr-review-poller watch
```

Reports are written under:

```text
~/.local/share/pr-review-poller/OWNER/REPO/PR_NUMBER/attempts/
```

Useful commands:

```sh
uv run pr-review-poller history OWNER/REPO 123
uv run pr-review-poller show-run OWNER/REPO 123 RUN_ID
uv run pr-review-poller mark-reviewed OWNER/REPO 123
```

After an agent prepares a report, the same pull request diff is skipped until `mark-reviewed` is run or the upstream diff changes.
