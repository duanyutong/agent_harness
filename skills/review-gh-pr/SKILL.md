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

- **Fetch PR Details**: Get the PR description, linked issues, diff, existing review comments
- **Review Diff**: Examine all changed files and the scope of modifications
- **Identify Language(s)**: Determine which programming languages are involved

### 2. Load Guidelines

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

Report Structure:

- For human reviewer:
  - Summary of changes: the purpose of the PR and the changes made
- Review draft:
  - Decision: Approve, Request Changes, or Comment
  - Body
    - Any high-level issues about architecture, design, code organisation etc. not tied to specific files or lines.
    - Leave blank unless there are high-level issues; do not repeat the inline comments here
  - Inline comments: a numbered list of line-by-line review comments; each item in the list should
    - Reference a specific file and line(s).
    - Include a block quote of the relevant code snippet (just for human review; do not post this part).
    - Begin with one of the standard review disposition indicators plus the issue type, e.g. "FYI (perf): ...", "Minor (readability): ..." without emphasis in bold.
    - Describe the issue clearly and concisely, no more than one or two sentences.
      - If clearly a bug, state it directly.
      - If it is uncertain (could be intentional), ask clarifying questions instead of assuming.
    - When suggesting improvements, include a well-written code example if possible.

Use the following table of standard disposition indicators for writing the comments.

| Indicator        | Disposition | Blocking? |
| ---------------- | ----------- | --------- |
| FYI              | Informing   | No        |
| Typo, Minor, Nit | Discussing  | No        |
| LGTM             | Satisfied   | No        |
| Major, Bug       | Blocking    | Yes       |
| ???              | Pondering   | No        |

### 4. Write the Report

Write the review draft in markdown format to the following location.

```text
.git/pr-reviews/pr-<number>-<timestamp>.md
```

Simply present this report file to the user for approval or iteration, without repeating the file content in your response.

### 5. Post Review to GitHub

Once approved, use the full-featured `gh api` CLI to post the review to GitHub.

```bash
gh api repos/{owner}/{repo}/pulls/{pr_number}/reviews \
  -X POST \
  --input <(cat <<'EOF'
{
  "event": "<APPROVE|REQUEST_CHANGES|COMMENT>",
  "body": "review summary",
  "comments": [
    {
      "path": "path/to/file.py",
      "line": 10,
      "body": "Single-line comment"
    },
    {
      "path": "path/to/file.py",
      "start_line": 123,
      "line": 456,
      "body": "Multi-line comment spanning lines 123-456"
    }
  ]
}
EOF
)
```

Notes about the CLI:

- Derive `{owner}` and `{repo}` from the PR information
- `event`: One of `APPROVE`, `REQUEST_CHANGES`, or `COMMENT`
- `body`: Summary shown at the top of the review
- `comments`: Array of inline comments; use `line` for single-line, add `start_line` for multi-line ranges

After posting the review, simply provide the PR link back to the user for human review.
