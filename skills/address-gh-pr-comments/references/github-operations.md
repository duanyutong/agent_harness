# Git and GitHub Operations for Addressing PR Comments

Read the section relevant to the current workflow phase. Obtain repository, PR, branch and commit identifiers from verified metadata. These operations implement the approval and thread policies in `SKILL.md`; they do not provide additional authorisation.

## Gather PR and Review Data

Retrieve PR details through a GitHub tool or `gh pr view`. Prefer structured `--json` or `--jq` output for subsequent processing.

Do not force a pager override by default. If a command opens a pager or appears stuck in an alternate-screen buffer, retry that command with `GH_PAGER=cat gh ...` rather than exporting a global override.

For each review thread, preserve its GraphQL node ID and the original review-comment `databaseId`. GraphQL thread replies use the former; the REST `in_reply_to` endpoint uses the latter. If the available GitHub tool omits thread IDs, retrieve them through `gh api graphql` during gathering.

Follow pagination for review bodies, threads and each thread's comments so later pages are not omitted from the plan.

## Amend and Restack Branches

Stage only the validated changes with `git add`. Inspect stack relationships before rewriting history:

| Stack tooling | Inspection                 |
| ------------- | -------------------------- |
| Branchless    | `git ls` or `git smartlog` |
| Graphite      | `gt ls`                    |

Use the operation appropriate to the branch structure:

| Branch structure                | Amendment procedure                                                                                        |
| ------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| Single non-stacked commit       | Use the repository's amendment command.                                                                    |
| Multi-commit non-stacked branch | Create `git commit --fixup=<sha>`, then run `git rebase -i --autosquash <base>`.                           |
| Branchless stack                | Use `git amend`, which restacks descendants; use `git restack --merge` and resolve conflicts if necessary. |
| Graphite stack                  | Use `gt m`, which restacks descendants; use `gt restack` if necessary.                                     |

Inspect the resulting graph and resolve restacking conflicts before continuing. Synchronise the stack or commit with remote main before publication, using the repository's established synchronisation command. Do not leave abandoned commits or unrestacked descendants.

## Publish Thread Replies

For a small number of replies, ordinarily one to five, prefer the REST reply endpoint. Use the original review-comment `databaseId`. Write the exact reply to a temporary file and pass it as file input:

```sh
gh api --method POST "repos/$repo/pulls/$pr/comments" \
  -F body=@"$reply_file" \
  -F in_reply_to="$comment_id"
```

For more than five independent replies, prefer one GraphQL request with aliased `addPullRequestReviewThreadReply` mutations when the thread IDs were gathered. This reduces HTTP round trips but does not remove content-creation limits. Construct one alias per reply:

```graphql
mutation ($thread0: ID!, $body0: String!, $thread1: ID!, $body1: String!) {
  reply0: addPullRequestReviewThreadReply(
    input: { pullRequestReviewThreadId: $thread0, body: $body0 }
  ) {
    comment {
      id
      url
    }
  }
  reply1: addPullRequestReviewThreadReply(
    input: { pullRequestReviewThreadId: $thread1, body: $body1 }
  ) {
    comment {
      id
      url
    }
  }
}
```

Pass reply bodies through structured tool arguments or file input without interpolating generated content into shell source. Inspect per-mutation errors and retry only failed replies. Keep individual mutations serial; on `403` or `429` rate-limit responses, honour `retry-after` or `x-ratelimit-reset`, otherwise back off before retrying. Never resolve reviewer threads through this skill.

## Update the PR Description

Write the updated description to a temporary file, preserving actual newlines and the intended Markdown. Publish it with the available GitHub tool or:

```sh
gh pr edit "$pr" --repo "$repo" --body-file "$description_file"
```
