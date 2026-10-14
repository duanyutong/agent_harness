# GitHub Operations for CI Resolution

Use the repository's authenticated GitHub tools or `gh`. Set `repo`, `pr`, `owner`, `name` and other variables from verified repository metadata; never infer a push destination solely from the PR's display branch name. Read operations across PRs may run concurrently. Serialise mutations and honour rate-limit responses.

## Revision and Check Discovery

```sh
gh pr view "$pr" --repo "$repo" \
  --json number,url,state,isDraft,headRefName,headRefOid,headRepository,headRepositoryOwner,baseRefName,baseRefOid,mergeable,mergeStateStatus,reviewDecision,statusCheckRollup

gh pr checks "$pr" --repo "$repo" \
  --json name,state,bucket,workflow,link,startedAt,completedAt

gh pr checks "$pr" --repo "$repo" --required \
  --json name,state,bucket,workflow,link,startedAt,completedAt
```

The [GitHub CLI check reference](https://cli.github.com/manual/gh_pr_checks) distinguishes pending checks with exit code `8`. Preserve structured output even when the command exits unsuccessfully; distinguish a reported failing check from an API or authentication failure. Do not use `--fail-fast` or let a shell's `set -e` discard the remaining PR results. Polling all PRs with structured reads supports a common round boundary better than watching one PR at a time.

The CLI buckets are summaries. Inspect underlying conclusions and provider output: `cancel`, `skipping`, neutral and timed-out results are not interchangeable with success. GitHub may accept successful, neutral or skipped required checks under its rules; a Bugbot all-clear still requires affirmative review evidence. A missing expected required check remains unresolved even when all returned checks pass. Inspect branch protection and applicable rulesets for the actual target branch, using available repository permissions. If those rules cannot be read and another authoritative interface does not establish eligibility, report that verification gap.

Apply the skill's service-outage exception only to affected Bugbot results when evidence establishes service unavailability. Preserve the raw pending, missing or failing state; record the exclusion separately rather than rewriting the result as success. Unavailable review completion and a passing Bugbot comment are then unnecessary for this loop, while every other check and every known finding remains in scope. A stall or missing comment alone is insufficient evidence. Use available provider incident information or explicit service errors to investigate; installation, billing and access failures remain blockers.

When the rollup omits evidence or contains ambiguous duplicates, query the [check runs](https://docs.github.com/en/rest/checks/runs) and legacy statuses directly:

```sh
gh api --paginate "repos/$repo/commits/$head_sha/check-runs?per_page=100"
gh api --paginate "repos/$repo/commits/$head_sha/statuses?per_page=100"
```

Reconcile by revision, check name, producing app/workflow and latest run attempt; a historical failure must not override its completed successful rerun. Record base revisions as well as heads. For pull-request workflows using a synthetic merge SHA, verify association with the target PR/head/base through workflow-run metadata rather than rejecting or accepting the result on SHA equality alone. Follow pagination for every collection, including checks, statuses, runs, reviews, comments and threads.

## Failure Evidence

```sh
gh run view "$run_id" --repo "$repo" \
  --json databaseId,headSha,event,status,conclusion,attempt,url,jobs
gh run view "$run_id" --repo "$repo" --attempt "$attempt" --log-failed
gh api --paginate "repos/$repo/check-runs/$check_id/annotations?per_page=100"
```

Use details links for external CI providers and collect their logs through an available authorised interface. If a read is denied or logs expired, report the missing evidence; do not invent a cause. Cancelled or incomplete jobs may require available full logs rather than `--log-failed`.

A diagnosed transient GitHub Actions failure can be retried with `gh run rerun "$run_id" --repo "$repo" --failed`. Record the new attempt and await completion before closing observation. Rerunning Actions is not a substitute for a Bugbot trigger.

## Bugbot Review Discovery

```sh
gh api --paginate "repos/$repo/pulls/$pr/reviews?per_page=100"
gh api --paginate "repos/$repo/pulls/$pr/comments?per_page=100"
gh api --paginate "repos/$repo/issues/$pr/comments?per_page=100"
```

Use GraphQL for review-thread IDs and resolution state. Paginate both `reviewThreads` and each thread's `comments`; the following query exposes cursors but requires subsequent requests when `hasNextPage` is true:

```graphql
query ($owner: String!, $name: String!, $pr: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $pr) {
      reviewThreads(first: 100, after: $after) {
        pageInfo {
          hasNextPage
          endCursor
        }
        nodes {
          id
          isResolved
          isOutdated
          path
          line
          comments(first: 100) {
            pageInfo {
              hasNextPage
              endCursor
            }
            nodes {
              id
              databaseId
              body
              url
              createdAt
              author {
                login
              }
              originalCommit {
                oid
              }
              pullRequestReview {
                id
                submittedAt
                commit {
                  oid
                }
              }
            }
          }
        }
      }
    }
  }
}
```

Preserve the review-thread GraphQL ID for resolution and the original review-comment `databaseId` for REST replies. Associate review output with its recorded run/review ID, revision and timestamps. Comments may be edited in place: compare `updated_at` or equivalent fields and the content, rather than relying solely on newly created IDs. Identify Bugbot through observed author/app metadata; similar-looking account names or success wording in somebody else's comment are insufficient.

Inspect checks and review output independently when applying the participation policy. An absent check rollup does not establish that Bugbot has never reviewed the PR; conversely, an explicitly requested review may complete through review output without creating a status check. Associate the fresh review with the recorded pending run or new trigger, rather than accepting a previously completed all-clear. Require a missing status check only when repository rules or current-run evidence establish that it is expected.

Check the full completed review for findings and affirmative all-clear evidence. A zero finding count in an incomplete response, a resolved thread, a cancelled run, or a review whose coverage was skipped cannot establish that Bugbot found no issues. Reconcile older unresolved findings against subsequent fixes and reviews. A newer review reporting findings supersedes a previous all-clear.

## Replies, Resolutions and Triggers

Write exact reply text to a temporary file and pass the file content through the tool's structured body parameter or `gh api`'s file input. Do not interpolate generated text into executable shell source.

```sh
gh api --method POST "repos/$repo/pulls/$pr/comments" \
  -F body=@"$reply_file" -F in_reply_to="$comment_id"

gh api graphql \
  -f query='mutation($thread: ID!) { resolveReviewThread(input: {threadId: $thread}) { thread { id isResolved } } }' \
  -f thread="$thread_id"

gh pr comment "$pr" --repo "$repo" --body 'bugbot run'
```

Resolve only the addressed Bugbot thread, after confirming the reply succeeded. For a finding in a review body or ordinary PR comment, use `gh pr comment --body-file "$reply_file"` with a link to the original finding. Record returned IDs or URLs to prevent duplicate replies on retries. Resolve a thread only when all findings within it have been addressed.

Cursor documents [manual Bugbot triggers and review behaviour](https://cursor.com/docs/bugbot). Follow the requested literal `bugbot run` trigger. For each eligible PR, post it immediately after the complete stack push succeeds and the published revision is verified, before CI polling or finding replies and resolutions. Capture the current run state once; reuse an applicable automatic run or pending recorded trigger rather than posting a duplicate, but do not delay an otherwise needed trigger while waiting for ordinary CI or possible automatic-run registration. Initial missing reviews are likewise triggered before waiting for ordinary CI; rounds without a push trigger promptly after the finding's disposition.

A successful comment POST proves only that the trigger was posted. Record the PR head/base, trigger comment, posting time and pre-trigger review IDs so earlier successes cannot satisfy the new trigger. Then monitor the corresponding new or updated run/review alongside ordinary CI until it completes. Posting finding replies or resolving threads afterwards must not generate another trigger for the same scheduled review.

During an evidenced Bugbot service outage, omit additional triggers and waiting for unavailable results. Continue replies and resolutions for existing addressed findings where GitHub is accessible. If recovery is observed before completion, remove the exclusion and resume the normal trigger and verification rules.

## Publication of Multiple Rewritten Branches

For branches sharing one push remote, construct one command with explicit refspecs and one expected-old-SHA lease per changed ref. This example represents a verified two-branch stack; construct the actual set from the round record:

```sh
git push --atomic \
  --force-with-lease="refs/heads/$lower_remote_branch:$lower_expected_sha" \
  --force-with-lease="refs/heads/$upper_remote_branch:$upper_expected_sha" \
  "$push_remote" \
  "refs/heads/$lower_local_branch:refs/heads/$lower_remote_branch" \
  "refs/heads/$upper_local_branch:refs/heads/$upper_remote_branch"
```

The [Git push reference](https://git-scm.com/docs/git-push) specifies atomic publication and explicit leases. Explicit expected SHAs prevent a background fetch from silently widening a lease. If atomic pushes are unsupported, remove only `--atomic` and inspect every ref after the multi-ref push; a non-atomic push can partially succeed. For different push remotes, publish once per remote after all local work is complete and record partial progress. Git cannot make publication atomic across separate remotes.

Branchless [amendments restack descendants](https://github.com/arxanas/git-branchless/wiki/Command:-git-amend). Inspect installed command help and repository conventions before using tool-specific synchronisation or submission commands. A submission helper is suitable only if it preserves existing PRs, publishes exactly the selected refs once, and provides equivalent lease protection. Do not assume a submission command has these properties.

## Final Merge Requirements

Refresh the PR metadata, all checks, required checks, applicable branch rules and unresolved conversations. The [GitHub protection reference](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches) describes required checks, conversation resolution, base freshness and merge queues. A mergeability field may be unknown while GitHub recomputes it; poll rather than interpreting that as success. A blocked aggregate merge state may reflect missing review approval, draft state or another requirement: identify its cause instead of attributing it automatically to CI.

Report CI eligibility at the observed head/base SHAs. Passing PR checks cannot guarantee that later merge-queue checks will pass before the PR enters the queue; report required queue admission separately and do not enqueue or merge without authorisation.

If Bugbot is excluded due to an evidenced outage, the loop may complete after all considered checks pass and all known findings are addressed, even without a Bugbot passing comment. Report any still-pending required Bugbot check as an actual GitHub merge blocker. Do not remove that requirement, fabricate a passing result or claim full merge eligibility.
