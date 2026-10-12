# Agent Harness

Polyglot monorepo of agent-adjacent tooling.

Each subdirectory is an independent project with its own toolchain. The repo
root owns cross-cutting hygiene (linters, editor config, contributor docs);
projects own their own languages, build systems, and tests.

## Projects

| Path                       | Purpose                                           | Stack   |
| -------------------------- | ------------------------------------------------- | ------- |
| [`local-llm/`](local-llm/) | Benchmark and serving experiments for local LLMs. | Python. |
| [`skills/`](skills/)       | Reusable agent skills (markdown specifications).  | —       |

## Local Setup

Run the following command from the repository root:

```sh
./setup.sh
```

The installer links `~/.agents/skills` to the repository's shared `skills/` directory. If the `claude` command is available on `PATH`, it also creates an independent `~/.claude/skills/` directory if absent; otherwise, it skips Claude-specific checks and leaves all Claude paths untouched. Repeated runs preserve an existing correct setup. The script checks for conflicts before making changes and never deletes, moves, or overwrites existing data. Use `./setup.sh --home /absolute/path` to configure a different existing home directory.

The shared `skills/` directory contains repository-maintained skills. Codex discovers these through `~/.agents/skills`; its bundled system skills remain in `~/.codex/skills/.system/`.

Keep `~/.claude/skills/` as an independent directory. It must not be a symbolic link to `~/.agents/skills` or this repository's `skills/` directory. Claude-managed downloads belong in `~/.claude/skills/synced/`, outside the shared discovery tree. This configuration does not install the repository's skills for Claude.

Existing directories or unrelated links at `~/.agents/skills`, symbolic links at the directories being configured, and a shared `skills/synced/` entry are reported as conflicts. Shared-directory checks apply even when Claude is absent. Resolve conflicts manually before rerunning the installer. For an old installation where `~/.claude/skills` links to the shared directory, remove only that symbolic link, create an independent directory at the same path, and move any shared `synced/` directory into `~/.claude/skills/synced/` after confirming that the destination is absent. Preserve the downloaded files during this migration.

These home-directory links and directories are machine-local configuration and are not stored in Git. The ignore rules for `/.agents/` and `/skills/synced/` prevent local artefacts from being committed; they do not control skill discovery.

## Validation

Every change must pass:

```sh
prek run --all-files
./tests/setup.sh
```

`prek` reads the root [`prek.toml`](prek.toml) for cross-cutting hygiene plus
any project-local `prek.toml` files for project-scoped toolchain hooks. Run
`prek install` once to wire up the git hook. See [`AGENTS.md`](AGENTS.md) for
agent-facing rules.

## Pre-commit hook management

Pre-commit hooks are managed by [prek](https://github.com/j178/prek), a single
binary reimplementation of pre-commit with first-class monorepo support.

```sh
brew install prek      # or: cargo install prek
prek install           # install the git hook
prek run --all-files   # run every hook against every file
```
