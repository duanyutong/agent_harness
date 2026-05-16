# Agent Harness

General harness-level tooling for agentic coding workflows.

Written in an agent-agnostic manner to support reuse across agent frameworks.

## Local Setup

Example commands:

```sh
# Assumes the repository was cloned to ~/agent_harness.
mkdir -p ~/.agents && ln -s ~/agent_harness/skills ~/.agents/skills
```

## Pre-commit Hooks

Pre-commit hooks are managed by [prek](https://github.com/j178/prek).

1. Install `prek` and make it available in your `PATH`.
2. Install git hooks in the repository with `prek install`.

To run validation on all files, use:

```sh
prek run --all-files
```
