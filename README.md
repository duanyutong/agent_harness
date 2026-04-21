# Agent Harness

General harness-level tools for agentic coding.

Written in agent-agnostic ways to promote reusablity across different agent frameworks.

## Local Setup

Example commands

```sh
# assume cloning to ~/
mkdir -p ~/.agents && ln -s ~/agent_harness/skills ~/.agents/skills
```

## Pre-commit Hooks

Pre-commit hooks are managed by [prek](https://github.com/j178/prek).

1. Install `prek` and make it available in your `PATH`.
2. Install git hooks in the repo with `prek install`.

To run it on all files, use

```sh
prek run --all-files
```
