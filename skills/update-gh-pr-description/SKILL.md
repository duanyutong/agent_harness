---
name: update-gh-pr-description
description: "Update PR description based on the diff, using repo template while preserving automation blocks. Fills out motivation, summary, and template fields from actual code changes."
argument-hint: "Specify PR number"
---

# Update PR Description

Update a PR description based on the diff: apply the repo's PR template, fill it out from the code changes, and preserve any automation-generated sections.

## Formatting

Take into consideration how GitHub renders markdown when formatting your markdown content.
For example, to avoid spurious forced line breaks in the rendered PR description, do not hard-wrap paragraphs or bullet items at any column.
Each paragraph and each bullet should be a single line, regardless of line length.

## Procedure

### 1. Gather Context and Backup

Fetch these in parallel:

- PR diff: get the full diff using a github tool or `gh pr diff` CLI.
  Make sure to avoid alternative buffer issues (e.g. due to pagers like `less`) by using `export GH_PAGER=cat && gh ...`.
- PR template: look for template in repo in standard locations.
  If none found, use a sensible default (summary, motivation, changes, testing).
- Existing description: fetch current PR body save it as a backup markdown file.
  - Prefer writing to a pre-approved session memory location if available.
  - Otherwise, write to `.git/pr-reviews/pr-<number>-<timestamp>.md`.
    Use ISO timestamp.
    Create directory if it does not exist.

Next, identify in the existing description:

- User content area (top section, before automation blocks) - may be empty or partially filled
- Automation blocks (stack managers, summary bots, CI status, etc.)
  - Automation blocks are typically delimited by `---` or HTML comments, contain bot signatures or tool markers, and sit at the bottom.
  - If unsure whether a section is automation or user content, err on the side of preserving it.

### 2. Analyze Diff

From the diff, extract:

- Files changed and their purpose
- Nature of changes (feature, fix, refactor, docs, etc.)
- Key modifications (new functions, changed behavior, config updates)
- Any obvious motivation (infer from code context)

### 3. Prepare Description Update

PR Description Template:

- If a template is defined, follow it verbatim, filling out the sections with the extracted information from the diff.
- If no template, use the following structure.
- In either case, the following information should be included in the updated description, in this order (unless otherwise specified by the repo template):
  - Motivation: concise explanation of why this change is needed
  - Summary of changes: concise list of changes at a high-level
  - Testing: how it was tested, if evident
  - Ticket reference: link if known, otherwise leave placeholder (e.g., `[TICKET-XXX]`)

Automation Blocks:

- Never modify any existing automation blocks—preserve them exactly as found in addition to the template (e.g. auto-generated PR summary, list of stacked PRs, etc.).
- Don't remove content the user may have intentionally added.

### 4. Update the PR

Use `gh pr edit <PR> --body "<updated>"` or equivalent tool to update the description.

The original description is already backed up to `.git/pr-descriptions/` from step 1, so no inline backup is needed.
