---
name: update-gh-pr-description
description: "Update PR description based on the diff, using the repository template while preserving automation blocks. Completes the motivation, summary, and template fields from actual code changes."
argument-hint: "Specify PR number"
---

# Update PR Description

Update a PR description based on the diff: apply the repository's PR template, complete it using the code changes, and preserve any automation-generated sections.

## Formatting

Account for GitHub Markdown rendering when formatting content.
For example, to avoid unintended forced line breaks in the rendered PR description, do not hard-wrap paragraphs or bullet items at any column.
Each paragraph and each bullet should be a single line, regardless of line length.

## Procedure

### 1. Gather Context and Backup

Fetch these in parallel:

- PR diff: get the full diff using a GitHub tool or `gh pr diff` CLI.
  Avoid alternate-buffer issues, for example those caused by pagers such as `less`, by using `export GH_PAGER=cat && gh ...` when needed.
- PR template: look for a template in the repository's standard locations.
- Existing description: fetch and back up the existing PR description.
- Write to `.agents/pr-descriptions/pr-<number>-<timestamp>-backup.md` relative to the target repository root.
  Always use a path-safe ISO timestamp in `Z` format.
  Create the directory if it does not exist.

Next, identify in the existing description:

- User content area (as opposed to automation blocks): may be empty or partially filled, for example from commit messages.
  This is the part we want to update.
- Automation blocks (stack managers, summary bots, CI status, etc.)
  - Automation blocks are typically delimited by `---` or HTML comments, contain bot signatures or tool markers, and sit at the bottom.
  - These sections are to be preserved verbatim and left unchanged.

Do not remove any content the user may have intentionally added.

### 2. Analyse Diff

From the diff, determine:

- Motivation of the change
- Files changed and their purpose
- High-level summary of material behavioural changes, new features, or fixes

### 3. Prepare Description Update

If a template is defined, follow it verbatim, filling out the sections with the extracted information.

The following information should be included in the updated description, in this order, unless otherwise specified by the repository template:

- Motivation
- Summary of changes: concise, high-level, no more than 150 words
- Testing: how it should be tested, each test item as a markdown checkbox
- Ticket reference: include ticket link if known from the existing description or user input, otherwise leave placeholder (e.g., `[TICKET-XXX]`)

Write the new description to `.agents/pr-descriptions/pr-<number>-<timestamp>-new.md`, same timestamp as the backup file earlier.

### 4. Post the Update

Use `gh pr edit <PR> --body "<updated>"` or equivalent tool to update the description.
