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

- PR diff: get the full diff using a GitHub tool or `gh pr diff` CLI.
  Make sure to avoid alternative buffer issues (e.g. due to pagers like `less`) by using `export GH_PAGER=cat && gh ...`.
- PR template: look for template in repo in standard locations.
- Existing description: fetch and back up the existing PR description.
- Write to `~/.local/share/agent-skill-pr-descriptions/repo_owner/repo_name/pr-<number>-<timestamp>-backup.md`.
  Use ISO timestamp.

Next, identify in the existing description:

- User content area (as opposed to automation blocks) - may be empty or partially filled (e.g. from commit messages)
  This is the part we want to update.
- Automation blocks (stack managers, summary bots, CI status, etc.)
  - Automation blocks are typically delimited by `---` or HTML comments, contain bot signatures or tool markers, and sit at the bottom.
  - These sections are to be preserved verbatim and left unchanged.

Don't remove any content the user may have intentionally added.

### 2. Analyze Diff

From the diff, determine:

- Motivation of the change
- Files changed and their purpose
- High-level summary of important changes in behaviour or new features/fixes

### 3. Prepare Description Update

If a template is defined, follow it verbatim, filling out the sections with the extracted information.

The following information should be included in the updated description, in this order (unless otherwise specified by the repo template):

- Motivation
- Summary of changes: concise, high-level, no more than 150 words
- Testing: how it should be tested, each test item as a markdown checkbox
- Ticket reference: include ticket link if known from the existing description or user input, otherwise leave placeholder (e.g., `[TICKET-XXX]`)

Write the new description to `~/.local/share/agent-skill-pr-descriptions/repo_owner/repo_name/pr-<number>-<timestamp>-new.md`, same timestamp as the backup file earlier.

### 4. Post the Update

Use `gh pr edit <PR> --body "<updated>"` or equivalent tool to update the description.
