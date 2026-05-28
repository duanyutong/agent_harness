# AGENTS.md

Subprojects keep their own `AGENTS.md` with project-specific commands,
toolchains, and critical paths.

This file contains general rules for the repo.

## Workflow — after **every** set of changes

1. Run `prek run --all-files` (or `prek run <project>` for project-scoped
   work). Fix everything red. Do not paper over lint failures with skips.
2. Run the test suites for whatever you touched.
3. A task is "done" only when both prek and the relevant test suites are green
   AND the new code carries its own tests (happy path + every error branch +
   every observable state transition).

## Modernity — zero tolerance for tech debt

- **Always** use current state-of-the-art tooling, libraries, syntaxes, and
  idioms.
  Before adding a dependency, do a fresh online search.
  Plan docs and prior decisions are starting points, not answers.
- Refuse deprecated APIs.
- Avoid unmaintained dependencies (no commits in ~12 months, dead issue
  tracker).
