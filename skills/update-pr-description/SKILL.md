---
name: update-pr-description
description: "Update PR description based on the diff, using repo template while preserving automation blocks. Fills out motivation, summary, and template fields from actual code changes."
argument-hint: "Optionally specify PR number"
---

# Update PR Description

Update a PR description based on the diff: apply the repo's PR template, fill it out from the code changes, and preserve any automation-generated sections.

## Procedure

### 1. Gather Context (parallelizable)

Fetch these in parallel:

a. PR diff: get the full diff using a github tool or `gh pr diff` CLI

b. PR template: look for template in repo in standard locations.
If none found, use a sensible default (summary, motivation, changes, testing).

c. Existing description: fetch current PR body and identify:

- User content area (top section, before automation blocks) - may be empty or partially filled
- Automation blocks (stack managers, summary bots, CI status, etc.)

Automation blocks are typically delimited by `---` or HTML comments, contain bot signatures or tool markers, and sit at the bottom. If unsure whether a section is automation or user content, err on the side of preserving it.

### 2. Analyze Diff

From the diff, extract:

- Files changed and their purpose
- Nature of changes (feature, fix, refactor, docs, etc.)
- Key modifications (new functions, changed behavior, config updates)
- Any obvious motivation (infer from code context)

### 3. Apply Template and Fill Content

Merge template with existing content:

- Insert/update template sections in user content area only
- Never modify automation blocks—preserve them exactly as found
- Don't remove content the user may have intentionally added

Fill in based on diff analysis:

- Summary: concise description of what the PR does
- Motivation: why this change is needed
- Changes: what was modified, key files/components
- Testing: how it was tested, if evident
- Ticket reference: link if known, otherwise leave placeholder (e.g., `[TICKET-XXX]`)

Result structure:

```markdown
[PR template filled out from diff]

[automation blocks preserved as-is]
```

### 4. Update the PR

Backup the old description by appending it as a hidden HTML comment at the end of the new body:

```html
<!-- pr-description-backup
[old description here]
-->
```

Then use `gh pr edit <PR> --body "<updated>"` or equivalent tool to update.
