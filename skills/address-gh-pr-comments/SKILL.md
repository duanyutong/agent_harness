---
name: address-gh-pr-comments
description: "Address unresolved PR review comments with a structured approval workflow. Pull comments, create a plan for approval, implement changes, run CI checks, amend the branch, and reply to reviewers."
argument-hint: "Specify PR number"
---

# Address PR Review Comments with Lint/Test

Structured workflow: pull comments → create plan → get approval → implement → validate → update branch → reply to reviewers.

## Procedure

### Phase 1: Gather and Plan

1. Get PR details: use a GitHub tool or the `gh pr view` CLI.
   Prefer `--json` / `--jq` for machine-readable output. Do not force `GH_PAGER=cat`
   by default; current `gh` behavior streams normal PR view and diff output without
   opening a pager. If a command does open a pager or appears stuck in an
   alternate-screen buffer, rerun that command with `GH_PAGER=cat gh ...` rather
   than exporting a global pager override.
2. Fetch unresolved threads: filter for `isResolved: false` and threads where the author has not replied yet.
3. Review the threads and create a plan.
4. Present the plan file to the user for review and approval before proceeding (format the file path as a link to enable one-click view).

Plan structure:

- For each thread: check the file/line, context, and reviewer comment; make an assessment; discuss the issue and rationale; propose an action; and draft a reply.
  - Reply should be concise, clear, and natural-sounding.

Plan location:

- Write to `.agents/pr-comments/pr-<number>-<request_timestamp>.md` relative to the target repository root.
  Always use a path-safe ISO timestamp in `Z` format.
  Create the directory if it does not exist.

### Phase 2: Implement

- Once the plan is approved, apply changes that address each approved item.
- Do not make excessive changes beyond the plan.
- Update applicable tests and docs if they are affected.

### Phase 3: Validate

Discover and run the repo's lint/test setup:

- Check for config files (Makefile, .pre-commit-config.yaml, pyproject.toml, package.json, etc.).
- Run lint/test commands the repo uses (may limit to only the affected files if appropriate).
- Loop: fix failures → re-run until passing.
- Review the final diff before committing.

### Phase 4: Update Branch

1. Stage changes: `git add ...`
2. Update:
   - Single commit: amend, e.g. `git amend` (branchless) or `gt m` (graphite).
   - Multi-commit: `git commit --fixup=<sha>` then `git rebase -i --autosquash <base>`.
   - Stacked PR: if the amend did not work fully, run the restack command to rebase the stack and fix any conflicts in the upstack.

### Phase 5: Reply and Resolve

1. Post the approved replies from the plan to each thread explaining how it was addressed.
   - Use a GitHub tool or the `gh api` CLI to reply to specific threads, e.g.

   ```sh
   gh api -X POST repos/{owner}/{repo}/pulls/{pr_number}/comments \
      -f body="$REPLY_TEXT" \
      -F in_reply_to=$COMMENT_ID
   ```

   - Default to the REST reply endpoint for a small number of replies (roughly 1-5).
     It is explicit, maps directly to review-comment `databaseId` values, and keeps
     retry and failure handling straightforward.
   - For many independent replies, especially when GraphQL review thread IDs are
     already available from the gather step, prefer one GraphQL request with aliased
     `addPullRequestReviewThreadReply` mutations. This reduces HTTP round trips and
     can be more efficient for secondary request-point rate limits. Content-creation
     limits still apply, so do not use batching to post large volumes too quickly.
   - When batching GraphQL replies, inspect the response for per-mutation errors and
     retry only the failed replies. Do not resolve reviewer threads.
   - If posting many mutating requests individually, keep them serial and pause
     between requests. On `403`/`429` rate-limit responses, honor `retry-after` or
     `x-ratelimit-reset`; otherwise back off before retrying.

2. Update the PR description if the scope changed, using the CLI: `gh pr edit <PR> --body "<updated>"`

Never resolve reviewer threads.
Leave that to the reviewer who posted the comment.

### Phase 6: Cleanup

Provide the user with a summary:

- Code and PR description changes made.
- Threads addressed.
- Any skipped items with reasons.
- Any local changes ready for push.
- PR link for human review if comments/changes were posted.
