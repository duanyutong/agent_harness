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

The installer creates an independent `~/.agents/skills/` directory and links each repository skill into it individually.
Other installers may add skills from separate repositories to the same discovery directory without modifying this checkout.
Existing unrelated skills are preserved, and repeated runs add newly introduced repository skills without replacing existing entries.
If the `claude` command is available on `PATH`, the installer also creates an independent `~/.claude/skills/` directory if absent; otherwise, it leaves Claude paths untouched.
The script checks for conflicts before making changes and never deletes, moves, or overwrites existing data.
Use `./setup.sh --home /absolute/path` to configure a different existing home directory.

The source `skills/` directory contains public, repository-maintained skills only.
Private skills must reside outside this checkout and may be linked directly into the independent discovery directory by their own installer.
Codex discovers the installed links through `~/.agents/skills/`; its bundled system skills remain in `~/.codex/skills/.system/`.

Keep `~/.agents/skills/` and `~/.claude/skills/` as independent physical directories.
Neither directory may be a symbolic link to a repository or to the other discovery directory.
Claude-managed downloads belong in `~/.claude/skills/synced/`.
This configuration does not install the repository's skills for Claude.

Conflicting entries for a repository skill name, symbolic links at discovery directories, invalid source skill directories, and a source `skills/synced/` entry prevent installation before any changes are made.
Source-directory checks apply even when Claude is absent.
Resolve conflicts manually before rerunning the installer.
For a legacy `~/.agents/skills` link to this repository, remove only that symbolic link, then rerun `./setup.sh` to create the directory and individual skill links.
For a legacy `~/.claude/skills` link, remove only that symbolic link, create an independent directory at the same path, and move any shared `synced/` directory into `~/.claude/skills/synced/` after confirming that the destination is absent.
Preserve the downloaded files during migration.

These home-directory links and directories are local configuration and are not stored in Git.
The ignore rules for `/.agents/` and `/skills/synced/` prevent local artefacts from being committed; they do not control skill discovery.

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
