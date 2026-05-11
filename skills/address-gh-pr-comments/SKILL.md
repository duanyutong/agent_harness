---
name: address-gh-pr-comments
description: "Address unresolved PR review comments with a structured approval workflow. Pull comments, create a plan for approval, implement changes, run CI checks, amend the branch, and reply to reviewers."
argument-hint: "Specify PR number"
---

# Address PR Review Comments with Lint/Test

Structured workflow: pull comments → create plan → get approval → implement → validate → update branch → reply to reviewers.

## Procedure

### Phase 1: Gather and Plan

1. Get PR details: use a github tool or the `gh pr view` CLI
   Make sure to avoid alternative buffer issues (e.g. due to pagers like `less`) by using `export GH_PAGER=cat && gh ...`.
2. Fetch unresolved threads: filter for `isResolved: false` and where author hasn't replied yet
3. Go through the threads and make a plan
4. Present the plan file to the user for review and approval before proceeding  (format the file path as a link to enable one-click view).

Plan structure:

- For each thread: check file/line, context, reviewer comment, make assessment, discuss the issue and rationale, propose action, and draft reply
  - Reply should be concise, clear, and natural-sounding.

Plan location:

- Write to `~/.local/share/agent-skill-pr-comments/repo_owner/repo_name/pr-<number>-<request_timestamp>.plan.md`.
  Use ISO timestamp.
  Create directory if it does not exist.

### Phase 2: Implement

- Once plan is approved, apply changes that address each approved item
- Do not make excessive change beyond the plan
- Update applicable tests and docs if they are affected

### Phase 3: Validate

Discover and run the repo's lint/test setup:

- Check for config files (Makefile, .pre-commit-config.yaml, pyproject.toml, package.json, etc.)
- Run lint/test commands the repo uses (may limit to only the affected files if appropriate)
- Loop: fix failures → re-run until passing
- Review final diff before committing

### Phase 4: Update Branch

1. Stage changes: `git add ...`
2. Update:
   - Single commit: amend, e.g. `git amend` (branchless) or `gt m` (graphite)
   - Multi-commit: `git commit --fixup=<sha>` then `git rebase -i --autosquash <base>`
   - Stacked PR: if amend did not work fully, run the restack command to rebase the stack and fix any conflicts in the upstack.

### Phase 5: Reply and Resolve

1. Post the approved replies from the plan to each thread explaining how it was addressed
   - Use a github tool or the `gh api` CLI to reply to specific threads, e.g.

   ```sh
   gh api -X POST repos/{owner}/{repo}/pulls/{pr_number}/comments \
      -f body="$REPLY_TEXT" \
      -F in_reply_to=$COMMENT_ID
   ```

2. Update PR description if scope changed, using CLI: `gh pr edit <PR> --body "<updated>"`

Never resolve reviewer threads.
Leave that to the reviewer who posted the comment.

### Phase 6: Cleanup

Provide user with a summary:

- Code and PR description changes made
- Threads addressed
- Any skipped items with reasons
- Any local changes ready for push
- PR link for human review if comments/changes were posted
