---
name: review-gh-pr
description: "Perform comprehensive code review and post a review to the GitHub PR"
argument-hint: "Optionally specify PR number or link"
---

# Review PR

Perform comprehensive code review with language-agnostic best practices and language-specific guidelines.

## When to Use this Skill

Use this skill when the user asks to:

- Review a GitHub pull request by number, link, or current branch
- Produce or post a GitHub PR review decision: approve, request changes, or comment
- Review existing open PR review threads as part of a full PR review

If repository-local instructions define another PR review workflow, follow this skill's procedure and use repository guidance only for project-specific standards not covered by this skill.

Do not use this skill when the user asks to:

- Address, implement, or reply to existing PR review comments; use `address-gh-pr-comments`
- Update only the PR description; use `update-gh-pr-description`
- Review non-PR local changes unless the user wants a GitHub PR review

## Workflow

### 1. Gather Context

- Fetch PR details: retrieve the PR description, linked issues, and diff.
- Fetch existing reviews and comments, including their status (open or resolved), authorship, and content.
  - Preserve the identifiers needed to publish replies to existing threads; consult [the gathering operations](references/github-operations.md#gather-context) when the available interface omits them.
- Identify languages: determine which programming languages are involved.
- Locate any prior review rounds we conducted by checking the repository's `.agents/pr-reviews/pr-<number>-<timestamp>.md` files.

Use the best available PR and issue access mechanism in the execution environment. Read [the gathering operations](references/github-operations.md#gather-context) when using the CLI.

If fetching fails (e.g. due to auth errors), stop here immediately and alert the user.

#### Worktree

- Avoid modifying the user's active checkout (or default worktree).
- Before creating or switching to a temporary linked worktree, record the current repository root as the artefact root.
- If already in a dedicated review checkout, check out the PR branch when doing so materially improves the review.
- If not in a dedicated review checkout, create a temporary linked worktree when full code navigation, local tooling, or tests would materially improve the review. Read [the worktree operations](references/github-operations.md#review-worktrees) before creating it.
- Use the temporary linked worktree only for inspecting code, running tools, and checking out PR branches.
- Always write the Plan under the artefact root's `.agents/...` directory, even if code review happens in a temporary linked worktree.
- If the agent starts inside a dedicated review checkout and no stable artefact root is known, write the Plan to the current checkout's `.agents/...` directory.
- For small or straightforward PRs, reviewing the PR diff and metadata through the available GitHub access mechanism without creating a worktree is sufficient.
- Even when using a worktree, still use GitHub PR metadata, existing comments, and related review data for accurate publication.

### 2. Load Guidelines

First check whether the repository provides its own guidelines.
Prefer these repository-specific guidelines if they conflict with general best practices.

Read the [coding-standards skill](../coding-standards/SKILL.md) and follow its instructions to load the general principles and relevant language-specific standards. Resolve its resource paths relative to that skill's directory. The `coding-standards` skill must be installed alongside this skill.

Then load the [code review guidelines](./standards/code-review.md), resolving this path relative to the current skill's directory.

### 3. Conduct Review

Review all materials gathered, apply the guidelines, and generate a Markdown document (the “Plan”).
If prior review rounds exist, link to each earlier plan and summarise what changed since the most recent round.

After drafting is complete, present the Plan location to the user for approval or iteration.
Format the file path as a link to enable one-click view.
Stop here and wait for manual approval.
Do not repeat the file content in your response.

#### Tone

- Keep review comments polite, appreciative, collegial, and concise.
  Make sure to use a friendly voice and be gentle in all comments.
  Do not demand changes (i.e. avoid "please change this"); when a change is needed, explain the impact and requested action clearly and courteously.
- Ask questions and request changes courteously, particularly where the issue is minor, judgement-dependent, or exploratory.
- Avoid categorical language unless the evidence is conclusive.
  If confidence is below certainty, qualify the concern; e.g. `This seems like a bug because ...`, `If I understand correctly...`.
- Use abbreviations, shorthands, and mix in some common colloquial expressions with variations to make the comments sound natural and not robotic (e.g. `docs`, `perf`, `What if we...`, `Suggestion is to...`, `I guess this should be fine but it'd be best if ...`)
- For routine cleanup or housekeeping work, acknowledge the author's effort where appropriate.
- If our previous comments has been acknowledged or addressed by the author, thank them briefly in the final approval body (not repetitively in each inline comment).

#### Plan Structure

- PR information: title and number (with link), author, base branch, head branch, and reviewed commit
- For human reviewer:
  - Summary of PR: purpose and changes made
- Review draft:
  - Existing review threads
  - Decision (Approve, Request Changes, or Comment)
  - Review body
  - Proposed new inline comments

#### Plan Formatting

- Use blank lines between logical paragraphs.
  Do not rely on a single newline for visual separation.
- When using numbered lists for repeated items, fully indent all subordinate content within each item.

#### Writing Review

For general guidance on writing review body and comments, see [./standards/code-review.md](./standards/code-review.md).

Clarity: When bringing up an issue, it must be clearly explained.
Concise and precise language is good, but it mustn't be cryptic.
The comment must inform the reader of the issue in a clearly understandable way.

Decision: Only use "Request Changes" if the PR has serious defects and has already been approved by other reviews and could be merged at any minute.

Relationship with CI checks:

- For issues already caught by CI
  - If they are straightforward with clear remedy to follow, no need to add inline comments for them.
    Simply mention in the review body that issues X, Y, and Z are captured in CI.
  - Only add inline comments if they add distinct diagnostic or design value.
- Do not cite CI being green as the basis for approval in the review body.
- The review decision may be `Approve` if the blocking CI failure is the only outstanding issue and the PR is otherwise substantively sound.

#### Mandatory comment formatting

For every inline comment and thread reply:

- Never cram everything into one single paragraph in a comment.
  - The first paragraph describes the issue clearly.
  - The second paragraph suggests the solution(s), or ask clarifying questions.
    Include a code snippet when useful to make it clear what the suggestion is.
- Before presenting the Plan, audit every comment.
  Any comment containing multiple logical components without paragraph breaks fails the audit and should be reformatted.

#### Requirements for the Review Body

Use the review body only to state the overall impression and/or concrete next steps.
Keep it concise.
Do not repeat or summarize details that are already covered by inline comments.
Do not write about whether you found blocking issues; the review decision already communicates that.

Good examples:

- "LGTM."
- "Overall LGTM; one minor comment."
- "Thanks for addressing all previous comments. LGTM."

Bad examples:

- "I have not found any blocking issues in this round." or "I found one edge case in...around..."
  - Just avoid "I found".
- "There is an issue when A happens triggering B in C ways leading to D edge case. I added an inline comment below with more details."
  - Too much repetition and verbosity.

Thank the author when both of the following are true:

- This is an approving review that concludes the overall process.
- The author thoughtfully addressed prior feedback, or the PR is a strong improvement or cleanup.
- We have not thanked the author in the review body of a previous approval.

Repeated thanks sound formulaic rather than genuine.
So only thank them once in the review body, not each inline thread.

#### Requirements for the "Existing Review Threads" Section

In this section, review every existing PR review thread.
If there are no existing review threads to include, write `None.`.

Use a numbered list for included threads.
For each thread, use one numbered list item with all subordinate content fully indented within that item.
Each item must include the following fields in this order:

- Status (Open or Resolved)
- Original poster
- Location (file and line numbers)
- Concern: summarise the primary concern raised by the original comment.
- Resolution: if the thread is resolved, summarise how it was resolved; if it remains open, write `Pending`
- Draft reply: exact reply body to publish, or `None` with a concise reason

Example item:

```markdown
1. [Open] thread `[PRRT_kwDOPQThtM6Cgh_F]`(http://link-to-thread)
   - Status: Open
   - Original poster: @user-reviewer_x
   - Location: `src/random_utils.py:42`
   - Concern: The variable name contains a typographical error.
   - Resolution: Pending.
   - Draft reply or action: None; the thread is awaiting author action.
```

Apply the following policy when deciding whether to draft replies to existing threads:

- If the thread is resolved:
  - If it has been addressed satisfactorily by new revisions, no reply is needed.
  - If it appears to have been resolved without being addressed, draft a concise reply that records the remaining concern. For minor non-blocking issues, state that the concern remains but does not block approval. For potentially substantive issues, ask the author to confirm whether the concern has merit or is a false positive and, if it has merit, whether it is being intentionally left unaddressed or will be addressed.
- If the thread is open:
  - If it is still awaiting PR author action or response, and no additional review input would advance the discussion, do not draft a reply.
  - If a prior reviewer has raised a concern with which we agree, draft a brief `+1` reply only when explicit concurrence would clarify the review position, or when we have independently reproduced the issue raised.
  - If clarification, additional evidence, or a distinct technical perspective would advance the discussion, draft an informative reply rather than restating prior comments.
  - If the thread was opened by us and has been addressed, draft a concise reply acknowledging it and resolve the thread as you publish the review.

#### Requirements for the "Proposed New Inline Comments" Section

If there are no proposed new inline comments, write `None.`.
Do not include existing-thread replies in this section.

Use a numbered list for proposed new inline comments.
For each proposed comment, use one numbered list item with all subordinate content fully indented within that item.
Each item must include the following fields in this order:

- File path: relative path to the repository root
- Location in file: target line number, or line range (this will be used for posting the review, so please ensure accuracy)
- Side: `LEFT` for deletions or `RIGHT` for additions
- Block quote of the relevant code snippet
- Comment: exact comment body to publish

Example item:

````markdown
1. `src/package/example.py`, lines 42-45, RIGHT

   > ```
   > code snippet quote
   > ```

   Comment: Minor (readability): ...
````

#### Plan Location

- Write to `.agents/pr-reviews/pr-<number>-<timestamp>.md` relative to the artefact root.
  Always use a path-safe ISO timestamp in `Z` format, for example `2024-06-01T12-00-00Z`.
  Create the directory if it does not exist.
- When iterating the same round, update the same Plan without creating a new one.

### 4. Publish Review to GitHub

Once approved, take the latest state of the Plan (possibly modified by the user) and publish it through the available GitHub API mechanism.
The latest state of the plan must be checked to take into edits made by the user before publishing.
Never post a review from memory without inspecting the Plan file.

Read [the review-publication operations](references/github-operations.md#publication-tool-selection) before publishing. The reference contains API selection, identifier retrieval, pending-review construction, parameter syntax and retry procedures.

- Use one pending review for the entire publication whenever it includes replies to existing threads, including mixed replies and new inline comments.
- Create that pending review without submitting it, attach the approved replies and new inline threads, then submit it. When using one GraphQL mutation for content and submission, place submission last.
- For a review with no existing-thread replies, the REST create-review endpoint remains acceptable.
- Inspect failed or partial publication before retrying; avoid duplicate replies, threads or reviews.
- Audit successful responses against the approved Plan. A successful submission does not guarantee that every inline comment was created; verify completeness and correct rendering of newlines.

### 5. Finalise

Clean up any temporary worktree or branch you have created after the review has been completed.
Do not preemptively clean up when iteration may still be needed.

Provide the PR link back to the user for verification.
Do not repeat the review content that has been posted in your response.
