# Git and GitHub Operations for PR Review

Read only the section needed for gathering, worktree access or publication. The approval, review-decision and thread-resolution policies remain in `SKILL.md`; these operations do not provide additional authorisation.

## Gather Context

Use an available GitHub tool or the `gh` CLI to retrieve PR metadata, the full diff, reviews, comments and linked issues. Prefer structured output when subsequent operations require identifiers.

If a command hangs or buffers output because a pager is active, retry it with a command-scoped `GH_PAGER=cat` prefix. Do not export the override for unrelated operations.

When only a REST review-comment ID is available, retrieve its parent GraphQL review-thread node ID before publication. GraphQL thread replies require the thread ID, not the comment ID. The identifier query in the publication section shows the relevant fields.

## Review Worktrees

Use `git worktree add` to create a temporary linked worktree when the workflow calls for a dedicated checkout. Establish the correct PR revision and an unused worktree path before running the command; keep the artefact root recorded before switching checkouts.

Use the worktree solely for code inspection, local tooling, tests and PR-branch checkout. After the review is complete and no further iteration is needed, remove the temporary worktree through `git worktree remove` and remove only temporary branches created for this review. Preserve the approved Plan under the original artefact root.

## Publication Tool Selection

The following tool-selection requirements apply when the review contains replies to existing threads.

- When publishing via `gh`, use raw `gh api graphql`.
  Apply a command-scoped pager override only when required.
- Do not use `gh pr review` for this case: it cannot attach replies to existing review threads.
- Do not use the REST create-review endpoint for this case either: REST replies use a separate endpoint, which publishes them outside the final review.
- Ensure that characters are properly escaped (e.g. `\n` should not be double-escaped and posted as raw literals).

Use one pending review for the entire publication whenever the review includes replies to existing threads, or when publishing mixed existing-thread replies and new inline comments.

## GraphQL Pending Review Workflow

The examples below use literal sample strings. For actual Plan content, pass review bodies and replies through structured tool variables or file input, such as `-F body=@"$body_file"`. Preserve actual newlines and never interpolate generated review content into executable shell source.

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
  - `path`: File path relative to the repository root
  - `line`: Line number; for multi-line comments, the end line
  - `side`: `LEFT` for deletions or `RIGHT` for additions
  - `startLine` and `startSide`: Include for multi-line comments

For reviews with no existing-thread replies, the REST create-review endpoint remains acceptable.
Prefer GraphQL for consistency when the Plan contains both new inline comments and existing-thread replies.

## Error Handling

Take care to avoid duplicate publications. For network or server errors, establish which operations succeeded before retrying; for input or permission errors, correct the specific cause before attempting publication again.

If any publish request fails after creating the pending review, do not retry the same request without inspection.

If the review remains pending, inspect its content or delete and recreate that pending review before retrying so replies or inline threads are not duplicated.

If submission already completed, inspect the published review and compare it with the approved Plan. Do not delete or recreate a submitted review, repeat a successful review decision, or replay successful replies and inline comments. Publish only missing approved content through an appropriate follow-up operation; if the provider cannot accommodate that recovery, report the partial publication and missing items.

## Verification

For successful requests, still audit the response to ensure nothing is missing or incorrect (e.g. line break characters should not appear as literal `\n`).
A successful submit does not guarantee that all inline comments were created.

## API References

- [GitHub GraphQL `addPullRequestReview`](https://docs.github.com/en/graphql/reference/mutations#addpullrequestreview)
- [GitHub GraphQL `addPullRequestReviewThreadReply`](https://docs.github.com/en/graphql/reference/mutations#addpullrequestreviewthreadreply)
- [GitHub GraphQL `submitPullRequestReview`](https://docs.github.com/en/graphql/reference/mutations#submitpullrequestreview)
- [GitHub REST review comment replies](https://docs.github.com/en/rest/pulls/comments#create-a-reply-for-a-review-comment)
