---
name: address-gh-pr-comments
description: "Address unresolved PR review comments with a structured approval workflow. Pull comments, create a plan for approval, implement changes, run CI checks, amend the branch, and reply to reviewers."
argument-hint: "Specify PR number"
---

# Address PR Review Comments with Lint/Test

Structured workflow: pull comments → create plan → get approval → implement → validate → update branch → reply to reviewers.

## Procedure

### Phase 1: Gather and Plan

1. Get PR details through the available GitHub interface. Read [the gathering operations](references/github-operations.md#gather-pr-and-review-data) when using the CLI or retrieving review-thread identifiers.
2. Fetch existing review comments (including both review bodies and open threads): filter for `isResolved: false` and threads where the author has not replied yet.
   For threads, preserve both identifiers needed for later replies:
   - the review-thread GraphQL node ID;
   - the review-comment `databaseId`.
     Retrieve missing identifiers during gathering rather than rediscovering threads during publication.
3. Review the review comments and create a plan.
4. Present the plan file to the user for review and approval before proceeding (format the file path as a link to enable one-click view).

Plan structure:

- For each thread: check the file/line, context, reviewer comment, review-thread GraphQL node ID, and review-comment `databaseId`; make an assessment; discuss the issue and rationale; propose an action; and draft a reply.
  - Reply should be concise, clear, and natural.
- For issues raised outside of inline threads and in review bodies: take them into account and draft applicable reply, too.

Plan location:

- Write to `.agents/pr-comments/pr-<number>-<request_timestamp>.md` relative to the target repository root.
  Always use a path-safe ISO timestamp in `Z` format.
  Create the directory if it does not exist.

### Phase 2: Implement

- Once the plan is approved, apply changes that address each approved item.
- Do not make excessive changes beyond the plan.
- Update applicable tests and docs if they are affected.
- Use a separate, temporary worktree if asked; default to the local worktree where the active branch can be switched as needed.

### Phase 3: Validate

Discover and run the repository lint and test configuration:

- Check for configuration files, such as Makefile, `.pre-commit-config.yaml`, `pyproject.toml`, and `package.json`.
- Run the lint and test commands used by the repository; limit them to affected files when appropriate.
- Loop: fix failures → re-run until passing.
- Review the final diff before committing.

### Phase 4: Update Branch

Read [the branch-update operations](references/github-operations.md#amend-and-restack-branches) before amending or restacking.

1. Stage the validated changes.
2. Before rewriting history, determine whether the branch is part of a stack.
   - Inspect the local graph with the repository's established stack tooling.
   - If any upstack branches or descendant commits depend on the commit being rewritten, treat the branch as stacked.
3. Update:
   - Single non-stacked commit: amend the owning commit.
   - Multi-commit non-stacked branch: create a fixup for the owning commit and autosquash it into the branch.
   - Stacked branch: amend the target commit and expect it to automatically restack
     - Use the stack manager's amendment and restacking operations.
     - Do not leave abandoned commits, unrestacked upstack branches, or restack conflicts behind.
       If a conflict cannot be resolved safely, stop and report.
   - Before pushing, use a sync command to ensure the stack/commit is up-to-date with remote main.

### Phase 5: Reply and Update Description

1. Post the approved replies from the plan to each thread explaining how it was addressed.
   - Read [the reply-publication operations](references/github-operations.md#publish-thread-replies) for endpoint selection, batching and request construction.
   - Do not use multiple agents, background jobs, or parallel shell commands to post
     review replies concurrently. If batching is not available, post serially and
     honour rate-limit headers.
   - Verify each reply's result and retry only failed replies. Respect provider rate limits and backoff requirements.

2. Update the PR description if the scope changed, using [the description-publication operation](references/github-operations.md#update-the-pr-description).

Never resolve reviewer threads.
Leave that to the reviewer who posted the comment.

### Phase 6: Clean-Up

Provide the user with a summary:

- Code and PR description changes made.
- Threads addressed.
- Any skipped items with reasons.
- Any local changes ready for push.
- PR link for human review if comments/changes were posted.
