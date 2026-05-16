---
name: upgrade-vulnerable-dependency
description: "Use when the user asks to fix, remediate, or investigate a vulnerable dependency package, dependency security alert, CVE, GHSA, Dependabot/Snyk/GitHub advisory, or affected package version. Investigate package-manager constraints, choose a safe fixed version, validate in a temporary worktree, open a draft PR, and handle clean-up."
---

# Upgrade Vulnerable Dependency

Use this workflow when asked to upgrade, fix, or analyse a vulnerable dependency package.

## Inputs To Establish

Establish these before changing files:

- Package name and ecosystem/package manager, if not inferable from the repository.
- Alert or advisory identifier/link, such as CVE, GHSA, Dependabot alert, Snyk advisory, or affected/fixed version range.
- Target repository and base branch, if ambiguous.

If an input can be inferred from manifests, lockfiles, or the alert, proceed and state the inference. Ask only when the repository, base branch, package, or advisory cannot be identified safely.

## Procedure

### 1. Inspect Local Dependency Management

- Start from the target repository root and read repository guidance such as `AGENTS.md`, contributor docs, CI config, manifests, and lockfiles.
- Identify the package manager and dependency files, such as `package.json`, lockfiles, `Gemfile`, `pyproject.toml`, `uv.lock`, `poetry.lock`, `requirements*.txt`, `Cargo.toml`, `go.mod`, `pom.xml`, or Gradle files.
- Determine whether the package is direct or transitive, its declared constraint, and its resolved version.
- For transitive packages, inspect the dependency path and prefer upgrading the parent package or resolver output. Use overrides/resolutions only when necessary, and state the tactical risk.
- Find the package-manager-native bump command, for example `npm update`, `pnpm up`, `yarn up`, `bundle update`, `uv lock --upgrade-package`, `poetry update`, `cargo update -p`, or `go get`.
- Note blockers such as manifest pins, runtime/engine constraints, peer dependencies, platform constraints, or major-version compatibility risks.

### 2. Select a Safe Target Version

- Use current package-index, upstream release, and advisory sources for the latest stable version and the version range that fixes the alert. Do not rely on memory for security status.
- Record source URLs for the advisory, fixed range, and selected version so they can be cited in the PR.
- Compare the latest version against local constraints and compatibility requirements.
- Prefer the latest compatible fixed version. If the latest version is not feasible, choose the smallest fixed upgrade that satisfies the advisory and the repository constraints.
- If no compatible fixed version is available, stop before broad refactoring and present findings: current version, affected range, fixed range, blocker, risk, and a concrete proposal such as a major-version migration plan, dependency replacement, upstream issue, temporary mitigation, or risk acceptance.

### 3. Use a Temporary Worktree

- Create a new temporary worktree from the correct base branch.
- Use a branch name in the form `<user>/dep-update-<package>-<version-or-advisory>`. Sanitise scoped or namespaced packages by lowercasing and replacing separators such as `@`, `/`, and spaces with `-`.
- Use the package manager to bump manifests and lockfiles. Avoid hand-editing lockfiles unless no reliable package-manager command can express the change.
- If the resolver changes unrelated packages, verify whether each change is required and call out resolver-caused changes in the PR.
- Keep compatibility changes minimal and directly tied to the dependency update.

### 4. Validate Locally

- Run repository-required validation, including any instructions from `AGENTS.md`.
- Discover and run relevant lint, build, tests, and dependency audit/security checks from docs, package scripts, Makefiles, CI config, or project conventions.
- If validation fails, fix scoped failures and rerun. If a failure is unrelated or environmental, capture the exact command and result.
- Review the final diff before committing.

### 5. Commit and Open a Draft PR

- Review the diff, then commit from the temporary worktree branch.
- Use a conventional commit subject, keep it under 72 characters, and keep it within Git/GitHub title limits. Example: `fix(deps): update <package> to <version>`.
- Push the branch and open a draft PR.
- Follow repository PR guidelines and templates. Include the alert/advisory link, source URLs, current-to-target version change, why the target was chosen, compatibility notes, resolver-caused changes, and validation results.

If the repository has no PR template, use this structure:

```markdown
## Summary

- Upgrade <package> from <current-version> to <target-version>
- Address <advisory> / <CVE-or-GHSA> via <fixed-range-source>

## Notes

- Selection rationale:
- Compatibility:
- Resolver-caused changes:

## Validation

- [ ] <command>
```

### 6. Report and Clean-Up Confirmation

In the response to the user, use this shape:

- Worktree:
- Branch:
- Draft PR:
- Selected version:
- Security result:
- Validation:
- Risks/blockers:

Ask one yes/no question: "Should I clean up the local worktree and branch now?"

If the user answers yes, remove the temporary worktree and local branch after confirming the PR branch was pushed. Do not delete the remote PR branch unless the user explicitly asks. If the user answers no, leave the local worktree and branch in place and state what remains.

## Guardrails

- Do not perform the bump in the user's main working tree.
- Do not rely on stale model knowledge for latest versions, fixed ranges, or advisory status.
- Do not upgrade unrelated dependencies except when the resolver requires it; call out any resolver-caused changes.
- Do not force a risky major upgrade without first presenting blocker analysis and a proposal.
- Respect existing uncommitted changes and never revert user work.
- Cite or record upstream/package/advisory sources in the PR body when security status depends on them.
