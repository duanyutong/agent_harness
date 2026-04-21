---
name: address-pr-comments-with-lint-test
description: "Address unresolved PR review comments with a structured approval workflow. Pull comments, create a plan for approval, implement changes, run CI checks, amend the branch, and reply to reviewers."
argument-hint: "Optionally specify PR number, reviewer name, or file to focus on"
---

# Address PR Review Comments

Structured workflow: pull comments → create plan → get approval → implement → validate → amend branch → reply to reviewers.

## Procedure

### Phase 1: Gather and Plan

1. Get PR details: use a github tool or the `gh pr view` CLI
2. Fetch unresolved threads: filter for `isResolved: false` and where author hasn't replied yet
3. Go through the threads and make a plan
   - For each thread: check file/line, context, reviewer comment, make assessment, propose action, draft reply
     - Reply should be concise, clear, and natural-sounding.
4. If the solution is clear with high-confidence, proceed to next steps.
   Otherwise, check with human for approval or iteration.

### Phase 2: Implement

- Apply changes that address each approved item
- Do not make excessive change beyond the plan
- Update applicable tests and docs if they are affected

### Phase 3: Validate

Discover and run the repo's lint/test setup:
- Check for config files (Makefile, .pre-commit-config.yaml, pyproject.toml, package.json, etc.)
- Run lint/test commands the repo uses (may limit to only the affected files if appropriate)
- Loop: fix failures → re-run until passing
- Review final diff before committing

### Phase 4: Amend Branch

1. Stage changes: `git add ...`
2. Amend:
   - Single commit: amend, e.g. `git amend` (branchless) or `gt m` (graphite)
   - Multi-commit: `git commit --fixup=<sha>` then `git rebase -i --autosquash <base>`
   - Stacked PR: if amend did not work fully, run the restack command to rebase the stack and fix any conflicts

### Phase 5: Reply and Resolve

1. Post approved replies to each thread explaining how it was addressed
   - Use a github tool or the `gh api` CLI to reply to specific threads, e.g.
   ```sh
   gh api -X POST repos/{owner}/{repo}/pulls/{pr_number}/comments \
      -f body="$REPLY_TEXT" \
      -F in_reply_to=$COMMENT_ID
   ```
3. Update PR description if scope changed: `gh pr edit <PR> --body "<updated>"`

Never resolve reviewer threads.
Leave that to the reviewer who posted the comment.

### Phase 6: Cleanup

- Delete the ephemeral `plan.md`
- Provide user with a summary: code and PR description changes made, threads addressed, any skipped items with reasons, local changes ready for push.
