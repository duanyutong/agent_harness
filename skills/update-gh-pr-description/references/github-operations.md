# GitHub Operations for Updating PR Descriptions

Read the section relevant to gathering or publication. Establish `repo`, `pr` and the backup and prepared-description paths from the target repository and the workflow record.

## Gather and Back Up Context

Use an authenticated GitHub tool or these CLI operations:

```sh
gh pr diff "$pr" --repo "$repo"
gh pr view "$pr" --repo "$repo" --json body --jq .body > "$backup_file"
```

Create the backup directory before writing the file. Confirm retrieval succeeded before using the backup; an authentication or API failure does not establish that the existing description was empty.

If a command opens a pager, hangs or buffers output, retry it with a command-scoped `GH_PAGER=cat` prefix. Do not export the override for unrelated operations.

Inspect the repository's standard PR-template locations, including `.github/PULL_REQUEST_TEMPLATE.md`, `.github/pull_request_template.md`, root-level equivalents and template directories. Follow the repository's selected template when several are available.

## Publish the Prepared Description

Pass the exact file produced by the preparation phase:

```sh
gh pr edit "$pr" --repo "$repo" --body-file "$description_file"
```

An equivalent GitHub tool is suitable when it accepts the description as a structured string. Preserve actual newlines and automation blocks verbatim; do not interpolate generated description text into executable shell source.
