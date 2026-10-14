---
name: ci-resolution-loop
description: "Iteratively resolve GitHub CI failures and Cursor Bugbot findings for a PR or PR stack: monitor, batch fixes, amend/restack, push and repeat until passing. Use for failed checks or builds, making a stack green, Bugbot loops, and CI repair or resolution loops."
---

# CI Resolution Loop

Repeat stack-wide observation, local repair and batched publication until considered CI checks pass and participating Bugbot reviews are clear, subject only to the evidenced outage exception. Verify actual merge requirements separately from human approval.

Read [GitHub operations](references/github-operations.md) for check interpretation, paginated review discovery, replies, triggers and protected stack publication.

## Scope and Authorisation

A request to execute the loop authorises scoped fixes, validation, amendments, restacking, publication, Bugbot replies, thread resolution and `bugbot run` comments without per-round approval. Inspection requests or automatic skill selection alone do not authorise mutations. Handle ordinary Bugbot feedback here without importing a separate review-approval workflow.

Preserve unrelated work, PR identities and stack relationships. Do not merge, mark drafts ready, change protections, suppress failures or resolve human review threads. Retain recoverable original refs; use an isolated worktree where appropriate.

## Bugbot Participation

- Determine participation per PR. Include Bugbot by default when its check is listed or required, or identifiable reviews or findings exist. Otherwise, require only ordinary CI; reassess when new evidence appears.
- An explicit “Bugbot loop”, “run Bugbot” or “include Bugbot” request includes every selected PR unless narrowed by the user, even without a listed check or prior run. Require a fresh completed review: reuse an applicable pending run or trigger once. A previously completed all-clear cannot satisfy this request. Address known findings before rerunning.
- Require affirmative completed all-clear evidence, independently of check success; a green check may contain findings. Preserve its source review and revision. Silence, resolved threads, incomplete/skipped/cancelled reviews and outage exclusions are not all-clear.
- Carry all-clear through later repair rounds without redundant manual reruns. New findings reopen repair. Defer stale or non-passing Bugbot checks, including missing expected checks, to the final gate while repairing other failures; await applicable pending reviews normally.
- Without a listed or required check, completed review output suffices. Do not create a missing-check blocker or final rerun merely because an optional check is absent. Required checks remain merge requirements.
- Record triggers against head/base revisions, run/review IDs and timestamps. Reconcile existing triggers before retrying; reuse applicable pending runs. Replies and resolutions do not justify another trigger.

## Establish Scope and State

Read repository instructions and inspect the worktree, remotes and stack tooling; use `git ls` in branchless repositories. Map local branches to existing PRs, bases and verified push destinations.

Use the requested PR or stack. Otherwise, select the connected stack containing the target, including ancestors and descendants; shared default-branch ancestry alone does not establish membership. Clarify ambiguous paths or mappings while continuing read-only inspection. Obtain authorisation before rewriting descendants outside the selected scope.

Maintain `<repo>/.agents/plans/ci-resolution-loop-<timestamp>.md`, or the instructed alternative, as execution state rather than another approval plan. Record ordered branches/PRs, local and remote head/base SHAs, expected remote refs, checks and attempts, failures, findings/dispositions, validation, published revisions, reply/trigger IDs and times, Bugbot participation and any outstanding fresh-review requirement. Include descendants changed solely by restacking.

## Each Round

### 1. Observe and Collect

Snapshot every PR's head/base, all checks including optional ones, and Bugbot reviews. Before ordinary CI polling, trigger any needed initial Bugbot review unless an applicable run is pending or an outage applies. Completed reviews with findings proceed to repair first.

Poll the entire stack together, ordinarily every 30–60 seconds, until all considered scheduled checks and applicable reviews finish. Collect logs while waiting; begin one complete repair set after observation closes. Deferred Bugbot checks do not delay ordinary repairs. Allow checks to register and match results to current revisions and latest attempts, including synthetic merge commits. Empty responses, missing expected checks, API errors and old successes cannot establish completion.

Collect every failure, timeout, cancellation, action-required result, missing required check and merge conflict. Retrieve Bugbot inline threads, review bodies and PR comments, including applicable older findings; outdated lines alone do not establish resolution. Classify findings as valid, false positive, already addressed or blocked, preserving evidence and individual reply targets. Deduplicate shared causes. Retry a demonstrated transient infrastructure failure once and await its new attempt; avoid repeatedly rerunning deterministic failures.

Refresh the stack before closing observation. Reconcile changed remote revisions and discard stale snapshots; newly registered checks or findings reopen observation.

### 2. Repair and Validate

Apply all fixes locally, bottom upwards, in the earliest appropriate owning commits. Use native amendment/restacking tooling; ordinary `git commit --amend` does not preserve descendants automatically.

After every amendment, fetch relevant remote refs, synchronise with the latest target base and genuine incoming branch changes, and restack descendants. Preserve local amendments; do not reintroduce superseded remote commits or overwrite others' work. Resolve all merge/rebase conflicts and inspect the stack before continuing.

Run required lint, formatting, build and tests, including `prek` where instructed, with meaningful regression coverage. Validate changed PRs at their own revisions when CI does so; stack-tip success alone is insufficient. Repeat affected validation after synchronisation or conflict changes; reuse unaffected results where justified.

Review the complete diff and graph, with no abandoned descendants or unresolved conflicts. Record final SHAs and changed refs. Omit edits and publication when dispositions or provider retries suffice; do not create empty amendments to restart CI.

### 3. Publish and Trigger Immediately

Immediately before pushing, fetch again and verify stack synchronisation. If relevant refs advanced since validation, reconcile, restack, resolve conflicts and repeat affected checks. Update expected remote values only after reconciliation; never refresh a lease merely to overwrite incoming work.

Publish the complete changed-ref set once per remote, with explicit refspecs and expected-SHA leases; prefer atomic publication. Fall back to a non-atomic multi-ref push only for unsupported atomic capability, never for lease/protection rejection. No intermediate pushes, unrestricted force pushes, `--all` or `git-pr`.

For failed or partial publication, inspect every ref, record accepted changes and reconcile before retrying only unpublished changes. Verify all intended PR heads and bases before scheduling reviews.

Immediately after complete verified publication, post needed `bugbot run` triggers for participating PRs with addressed findings or outstanding reviews, before replies, resolutions or CI waiting. Read run state once and reuse applicable pending runs/triggers; do not delay for possible automatic-run registration. Preserve carried all-clear and outage rules. Bugbot and ordinary CI then run concurrently.

### 4. Reply and Repeat

Reply concisely to each addressed finding with its published SHA, fix and validation, or evidence supporting a false positive/existing fix. If no push is needed, post the disposition directly, then trigger any needed review before CI polling.

Resolve a Bugbot thread only after its reply succeeds and every finding within it is addressed. Leave blocked findings and human threads unresolved; link replies to non-thread findings. Record successful mutations and retry only missing replies/resolutions.

Return to stack-wide observation. New failures or findings enter another complete repair round.

## Final Gate

Once ordinary failures and actionable findings are cleared, refresh the entire stack and actual merge requirements, including missing checks, conversations, conflicts, base freshness and merge queues. Every considered required check must satisfy repository rules on current revisions.

For participating PRs with carried all-clear but a listed/required Bugbot check still stale, failing, missing when expected or otherwise blocking CI, trigger one final review unless a run is pending or an outage applies. Verify acceptable checks and explicit all-clear; new failures/findings restart the loop.

Complete only with a stable snapshot: published local/PR heads agree, considered checks and reviews finish, considered required checks pass, participating Bugbot reviews are clear or explicitly outage-excluded, and addressed findings have successful replies/resolutions. Report PR links, final SHAs, fixes/dispositions, validation, exclusions and remaining merge prerequisites. Human approval, draft state and queue admission need not complete for this CI task; do not claim unconditional merge eligibility.

## Outages and Blockers

Exclude affected Bugbot checks and unavailable reviews only with evidence of a service outage: provider incident notice, explicit service-unavailable output or user confirmation. Pending status, absent comments or time alone are insufficient; installation, billing, authentication and permission failures remain blockers.

Record evidence, affected PRs/checks and assessment time. During the outage, omit Bugbot waiting, triggers and final refreshes; continue other CI and address known findings, including replies/resolutions where GitHub remains accessible. Resume normal requirements if recovery is observed before completion. Report “Bugbot unavailable; excluded due to service outage”, never passing/all-clear, and identify any actual required-check merge blocker without changing protections.

Continue while substantive progress is possible. Report a concrete blocker for inaccessible evidence, permissions, unsafe conflicts or unavailable infrastructure, or three consecutive completed rounds repeating the same issue without progress. A persistent evidenced false positive still blocks all-clear.

Investigate stalled checks/triggers using documented timeouts and observed progress; absent provider guidance, investigate after 30 minutes without a run, status, log or review update. Allow legitimate longer waits. Apply an established outage immediately; otherwise report an unresolved stall rather than posting repeated triggers. Respect user time/cost limits.

When blocked, preserve execution state and distinguish published fixes from unpublished work; identify the exact action or external change needed to resume.
