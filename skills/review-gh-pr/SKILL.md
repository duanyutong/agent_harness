---
name: review-gh-pr
description: "Perform comprehensive code review and post review to the GitHub PR"
argument-hint: "Optionally specify PR number or link"
---

# Review PR

Perform comprehensive code review with language-agnostic best practices and language-specific guidelines.

## When to Use this Skill

- Reviewing a pull request
- Providing feedback on code changes, or validating code quality standards
- When user asks: "review this PR", "check this code", "code review", "review my changes"

## Workflow

### 1. Gather Context

- Fetch PR Details: Get the PR description, linked issues, diff, existing review comments.
  Make sure to avoid alternative buffer issues (e.g. due to pagers like `less`) by using `export GH_PAGER=cat && gh ...`.
- Review Diff: Examine all changed files and the scope of modifications
- Identify Language(s): Determine which programming languages are involved

### 2. Load Guidelines

First check if there are guidelines available in the repo.
Prefer these repo-specific guidelines if there are conflicts with general best practices.

Use a read_file tool to load guideline files from the `./standards/` directory next to this skill file:

- Always load the general, language-agnostic guidelines first from [./standards/principles.md](./standards/principles.md).
- Always load the code review guidelines from [./standards/code-review.md](./standards/code-review.md).
- For each detected language, attempt to load the corresponding language-specific guideline file from `./standards/{language}.md`. Available guidelines include:
  - Python: [./standards/python.md](./standards/python.md)
  - More to be added

If guidelines for the detected language don't exist, use your best effort to apply known best modern practices and standards for this language.

### 3. Conduct Review

Review everything, apply the guidelines, and generate a report in markdown format.
Keep comments polite, appreciative, collegial, and concise—avoid excessive verbosity.

For guidance on writing review body and inline comments, see [./standards/code-review.md](./standards/code-review.md).

Present this report file to the user for approval or iteration.
Do not repeat the file content in your response.

#### Report Structure

- For human reviewer:
  - Summary of changes: PR title, number (with link), purpose, and changes made
- Open threads: each item in the numbered list should include:
  - Thread ID, link, summary
  - Draft of reply if applicable
    - Participate in every open thread where we haven't weighed in or need to respond again
    - Keep it simple when appropriate—a brief "+1" with one sentence suffices if there's nothing more to add
    - Provide a more detailed response when it adds value to the discussion
- Review draft:
  - Decision: Approve, Request Changes, or Comment
  - Body
  - A numbered list of inline comments

#### Inline Comments Format

In addition to the guidance in code-review.md, each inline comment in the report must:

- Cite the file path and line numbers (this will be used for posting the review, so please ensure accuracy)
- Cite the diff side—LEFT for deletions, RIGHT for additions (required and protected—always preserve this part when modifying the comment text)
- Include a block quote of the relevant code snippet (for human review only; do not post this part)

#### Report Location

- Write to `~/.agents/pr-reviews/repo_owner/repo_name/pr-<number>-<timestamp>.md`.
  Create directory if it does not exist.
- Use ISO timestamp if applicable.
- When iterating, update this report file without creating a new one.

### 4. Publish Review to GitHub

Once approved, take the report document and post new comments via CLI using `export GH_PAGER=cat && gh api`.
Make sure to avoid duplicate publications; only retry when the call has failed due to a network or server error.

Replies to existing threads and new reviews have to be posted separately using the appropriate API endpoints.

#### Reply to an Existing Thread

Use the following to respond to existing review comment threads, if applicable.

```sh
gh api repos/{owner}/{repo}/pulls/{pull_number}/comments/{comment_id}/replies \
  -f body="Your reply text"
```

Parameters:

- `comment_id`: ID of the top-level comment in the thread to reply to

#### Posting a new Review (including body and inline comments)

```sh
gh api repos/{owner}/{repo}/pulls/{pull_number}/reviews \
  -X POST \
  --input <(cat <<'EOF'
{
  "event": "REQUEST_CHANGES",
  "body": "High-level summary (optional)",
  "comments": [
    {
      "path": "src/utils.py",
      "line": 42,
      "body": "Single-line comment",
      "side": "LEFT"
    },
    {
      "path": "src/utils.py",
      "start_line": 10,
      "line": 15,
      "body": "Multi-line comment spanning lines 10-15"
    }
  ]
}
EOF
)
```

Parameters:

- `event`: `APPROVE`, `REQUEST_CHANGES`, or `COMMENT`
- `body`: Optional summary shown at the top of the review
- `comments`: Array of inline comments
  - `path`: File path relative to repo root
  - `line`: Line number (end line for multi-line)
  - `start_line`: Start line for multi-line comments
  - `side`: Optional; `LEFT` (deletions) or `RIGHT` (additions, default)

### 5. Finalise

Clean up any temporary worktree or branch you have created during the review.

Provide the PR link back to the user for verification.
Do not repeat the review content that has been posted in your response.
