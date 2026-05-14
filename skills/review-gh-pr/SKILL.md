---
name: review-gh-pr
description: "Perform comprehensive code review and post review to the GitHub PR"
argument-hint: "Optionally specify PR number or link"
---

# Review PR

Perform comprehensive code review with language-agnostic best practices and language-specific guidelines.

## When to Use this Skill

Use this skill when the user asks to:

- Review a GitHub pull request by number, link, or current branch
- Produce or post a GitHub PR review decision: approve, request changes, or comment
- Review existing open PR review threads as part of a full PR review

If repo-local instructions define another PR review workflow, follow this skill's procedure and use repo guidance only for project-specific standards not covered by this skill.

Do not use this skill when the user asks to:

- Address, implement, or reply to existing PR review comments; use `address-gh-pr-comments`
- Update only the PR description; use `update-gh-pr-description`
- Review non-PR local changes unless the user wants a GitHub PR review

## Workflow

### 1. Gather Context

- Fetch PR Details: Get the PR description, linked issues, diff, existing review comments.
  Make sure to avoid alternative buffer issues (e.g. due to pagers like `less`) by using `export GH_PAGER=cat && gh ...`.
- Identify Language(s): Determine which programming languages are involved

#### Worktree

- Avoid modifying the user's active checkout (or default worktree).
- If already in a dedicated review checkout, feel free to check out the PR branch when it makes review easier.
- If not in a dedicated review checkout, create a temporary linked worktree with `git worktree add` when full code navigation, local tooling, or tests would materially improve the review.
- For small or straightforward PRs, reviewing the PR diff and metadata via `gh` without creating a worktree is sufficient
- Even when using a worktree, still use GitHub PR metadata, existing comments, etc. for accurate review publication.

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

Review everything, apply the guidelines, and generate a Markdown document (the “Plan”).
Keep comments polite, appreciative, collegial, and concise—avoid excessive verbosity.

For guidance on writing review body and inline comments, see [./standards/code-review.md](./standards/code-review.md).

Present the location of the Plan to the user for approval or iteration.
Format the file path as a link to enable one-click view.
Stop here and wait for manual approval.
Do not repeat the file content in your response.

#### Plan Structure

- For human reviewer:
  - Summary of changes: PR title, number (with link), purpose, and changes made
- Open threads: each item in the numbered list should include:
  - GraphQL review thread node ID, link, summary
    - If only a REST review comment ID is available, fetch the GraphQL review thread node ID before publishing
  - Draft of reply if applicable
    - Participate in every open thread where we haven't weighed in or need to respond again
    - Keep it simple when appropriate—a brief "+1" with one sentence suffices if there's nothing more to add
    - Provide a more detailed response when it adds value to the discussion
- Review draft:
  - Decision: Approve, Request Changes, or Comment
  - Body
  - A numbered list of inline comments

#### Inline Comments Format

In addition to the guidance in code-review.md, each inline comment in the Plan must:

- Cite the file path and line numbers (this will be used for posting the review, so please ensure accuracy)
- Cite the diff side—LEFT for deletions, RIGHT for additions (required and protected—always preserve this part when modifying the comment text)
- Include a block quote of the relevant code snippet (for human review only; do not post this part)

#### Plan Location

- Write to `.agents/pr-reviews/pr-<number>-<timestamp>.md` relative to the target repository root.
  Always use a path-safe ISO timestamp in `Z` format.
  Create the directory if it does not exist.
- When iterating, update the Plan without creating a new one.
- If upstream code changes require another review pass, append to the document and clearly label Round 1, Round 2, etc.
  Do not create a new document for each round.

### 4. Publish Review to GitHub

Once approved, take the latest state of the Plan (possibly modified by user) and post via CLI using raw `export GH_PAGER=cat && gh api graphql`.
Make sure to avoid duplicate publications; only retry when the call has failed due to a network or server error.

Use one pending review for the entire publication whenever the review includes replies to existing threads, or when publishing mixed existing-thread replies and new inline comments. Do not use `gh pr review` for this case: it cannot attach replies to existing review threads. Do not use the REST create-review endpoint for this case either: REST replies use a separate endpoint, which publishes them outside the final review.

If any publish request fails after creating the pending review, do not blindly rerun the same request. Inspect the pending review or delete and recreate it before retrying so replies or inline threads are not duplicated.

#### GraphQL Pending Review Workflow

1. Fetch the pull request node ID and any GraphQL review thread node IDs needed for replies.
2. Create one pending review with `addPullRequestReview` and no `event`; capture `pullRequestReview.id`.
3. In one subsequent GraphQL request, add every existing-thread reply and every new inline review thread to that pending review, then submit it with `submitPullRequestReview`. Put `submitPullRequestReview` last; top-level GraphQL mutation fields run serially.

Fetch IDs:

```sh
gh api graphql \
  -f owner="{owner}" \
  -f repo="{repo}" \
  -F number={pull_number} \
  -f query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      id
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          comments(first: 20) {
            nodes {
              id
              databaseId
              url
              body
              author { login }
            }
          }
        }
      }
    }
  }
}'
```

Paginate `reviewThreads` or thread `comments` when the PR has more than the requested `first` count.

Create the pending review:

```sh
gh api graphql \
  -f pullRequestId="{pull_request_node_id}" \
  -f query='
mutation($pullRequestId: ID!) {
  addPullRequestReview(input: { pullRequestId: $pullRequestId }) {
    pullRequestReview { id }
  }
}'
```

Publish all review content into that pending review and submit it. Generate one aliased mutation field per reply or new inline thread, then submit last:

```sh
gh api graphql \
  -f reviewId="{pending_review_node_id}" \
  -f existingThreadId1="{review_thread_node_id}" \
  -f replyBody1="Reply to an existing thread" \
  -f newPath1="src/utils.py" \
  -F newLine1=42 \
  -f newSide1="RIGHT" \
  -f newBody1="New inline review comment" \
  -f event="APPROVE" \
  -f body="Review body" \
  -f query='
mutation(
  $reviewId: ID!
  $existingThreadId1: ID!
  $replyBody1: String!
  $newPath1: String!
  $newLine1: Int!
  $newSide1: DiffSide!
  $newBody1: String!
  $event: PullRequestReviewEvent!
  $body: String
) {
  reply1: addPullRequestReviewThreadReply(input: {
    pullRequestReviewId: $reviewId
    pullRequestReviewThreadId: $existingThreadId1
    body: $replyBody1
  }) {
    comment { id url }
  }
  inline1: addPullRequestReviewThread(input: {
    pullRequestReviewId: $reviewId
    path: $newPath1
    line: $newLine1
    side: $newSide1
    body: $newBody1
  }) {
    thread { id }
  }
  submit: submitPullRequestReview(input: {
    pullRequestReviewId: $reviewId
    event: $event
    body: $body
  }) {
    pullRequestReview { id url state }
  }
}'
```

Parameters:

- `pullRequestReviewId`: The pending review node ID returned by `addPullRequestReview`
- `pullRequestReviewThreadId`: The GraphQL node ID of the existing review thread to reply to
- `event`: `APPROVE`, `REQUEST_CHANGES`, or `COMMENT`
- New inline thread fields:
  - `path`: File path relative to repo root
  - `line`: Line number; for multi-line comments, the end line
  - `side`: `LEFT` for deletions or `RIGHT` for additions
  - `startLine` and `startSide`: Include for multi-line comments

For reviews with no existing-thread replies, the REST create-review endpoint remains acceptable. Prefer GraphQL for consistency when the Plan contains both new inline comments and existing-thread replies.

References:

- [GitHub GraphQL `addPullRequestReview`](https://docs.github.com/en/graphql/reference/mutations#addpullrequestreview)
- [GitHub GraphQL `addPullRequestReviewThreadReply`](https://docs.github.com/en/graphql/reference/mutations#addpullrequestreviewthreadreply)
- [GitHub GraphQL `submitPullRequestReview`](https://docs.github.com/en/graphql/reference/mutations#submitpullrequestreview)
- [GitHub REST review comment replies](https://docs.github.com/en/rest/pulls/comments#create-a-reply-for-a-review-comment)

### 5. Finalise

Clean up any temporary worktree or branch you have created only after the review has been completed.
Do not preemptively clean up when iteration may still be needed.

Provide the PR link back to the user for verification.
Do not repeat the review content that has been posted in your response.
