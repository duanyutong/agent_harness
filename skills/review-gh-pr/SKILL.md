---
name: review-gh-pr
description: "Perform comprehensive code review and post review to the GitHub PR"
argument-hint: "Optionally specify PR number"
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

Use the read_file tool to load guideline files from the `./guidelines/` directory next to this skill file.
Always load the general, language-agnostic guidelines first from [./guidelines/general.md](./guidelines/general.md).

In addition, for each detected language, attempt to load the corresponding language-specific guideline file from `./guidelines/{language}.md`. Available guidelines include:

- Python: [./guidelines/python.md](./guidelines/python.md)
- More to be added

If guidelines for the detected language don't exist, use your best effort to apply known best modern practices and standards for this language.

### 3. Conduct Review

Review the diff and relevant code, applying the loaded guidelines, and generate a report.
The report consists of content for human review as well as a draft for the final review to be posted.
Always be polite and not excessively verbose.

#### Report Structure

- For human reviewer:
  - Summary of changes: the purpose of the PR and the changes made
- Review draft:
  - Decision: Approve, Request Changes, or Comment
  - Body
    - Any high-level issues about architecture, design, code organisation etc. not tied to specific files or lines.
    - Leave blank unless there are high-level issues; do not repeat the inline comments here
  - Inline comments

#### Inline Comments Section

This section is a numbered list of line-by-line review comments.
Each item in the list should:

- Cite the file path, line number(s), and diff side—LEFT for deletions, RIGHT for additions (required).
- Include a block quote of the relevant code snippet (just for human review; do not post this part).
- Begin with one of the standard review disposition indicators plus the issue type, e.g. "FYI (perf): ...", "Minor (readability): ..." without emphasis in bold.
- Describe the issue clearly and concisely, no more than one or two sentences.
  - If clearly a bug, state it directly.
  - If it is uncertain (could be intentional), ask clarifying questions instead of assuming.
- Include a well-written code example when suggesting improvements if possible, in a new paragraph.
- Consider the scope and size of the PR and, if addressing the issue can be deferred to a follow-up, mention that at the end of the comment (only mention this if the change would be large or significantly out of scope for the current PR).

Use the following table of standard disposition indicators in the beginning of each comment to indicate the severity and nature of the issue:

| Indicator        | Disposition | Blocking? |
| ---------------- | ----------- | --------- |
| FYI              | Informing   | No        |
| Typo, Minor, Nit | Discussing  | No        |
| LGTM             | Satisfied   | No        |
| Major, Bug       | Blocking    | Yes       |
| ???              | Pondering   | No        |

Only use "LGTM" when replying to an existing, open thread that has been fully addressed.
Do not add new inline comments that are simply LGTM.

### 4. Write the Report

Write the review draft in markdown format to the following location.

```text
.git/pr-reviews/pr-<number>-<timestamp>.md
```

Simply present this report file to the user for approval or iteration, without repeating the file content in your response.

### 5. Publish Review to GitHub

Once approved, post the review via `export GH_PAGER=cat && gh api`, using file paths and line numbers as written in the draft—do not rederive them.

Make each API call exactly once to avoid duplicate publications, unless the call failed due to a network or server error.

After posting, provide the PR link back to the user for verification.

#### Reply to an Existing Thread

Use the following to respond to existing review comment threads, if applicable.

```sh
gh api repos/{owner}/{repo}/pulls/{pull_number}/comments/{comment_id}/replies \
  -f body="Your reply text"
```

Parameters:

- `comment_id`: ID of the top-level comment in the thread to reply to

#### Posting a new Review

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
      "body": "Single-line comment"
      "side": "LEFT",
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
