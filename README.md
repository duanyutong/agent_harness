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

```sh
mkdir -p ~/.agents && ln -s "$(pwd)/skills" ~/.agents/skills
```

## Validation

Every change must pass:

```sh
prek run --all-files
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
