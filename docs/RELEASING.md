# Releasing the Claude wrapper

Three commands. Do not promote or tag by hand — the promote workflow is what
keeps every release identical.

## The procedure

```bash
# 1. Bump the wrapper version. This touches all five places at once:
#    VERSION, plugin.json, marketplace.json, and the release line in
#    README.md / README.ko.md / README.ja.md.
bash scripts/set-wrapper-version.sh 0.25.0

# 2. Write docs/releases/0.25.0.md, then open a pull request into `develop`
#    and merge it.

# 3. Promote, tag, and publish.
gh workflow run promote.yml -f notes_file=docs/releases/0.25.0.md
```

That is the whole thing. Step 3 opens `develop → stage` and `stage → main` as
pull requests, waits for their checks, merges them, tags `main` from `VERSION`,
and publishes the GitHub release.

## Why not by hand

The workflow never pushes to a permanent branch — the branch ruleset requires a
pull request for `develop`, `stage`, and `main`, so it opens them and merges.
`workflow_dispatch` is its only trigger, which means starting it is the human
gate: nothing promotes on a schedule or on push.

A red check stops the chain and leaves that pull request open. A failed
promotion is a pull request you can read, not a half-finished merge.

Versions used to live in five files and get edited one at a time. A release that
updated only some of them shipped a plugin whose manifest disagreed with its own
`VERSION`. `set-wrapper-version.sh` removes that class of mistake — and it fails
loudly rather than skipping a file it cannot find.

## Core versions are not yours to bump

`vendor/scv-core/**`, `core.lock`, and `TEMPLATE_VERSION` belong to the Core
sync. `scripts/set-wrapper-version.sh` never touches them, and neither should
you. A new Core pin arrives as an automatic `chore/core-v<version>` pull request
from `core-sync.yml`; merge that first, then release the wrapper.

## The one thing that needs two runs

`workflow_dispatch` always executes the copy of the workflow file on the default
branch. So when the change you are promoting **edits `promote.yml` itself**, the
first run still uses the old file: it promotes your fix to `main` and may fail on
whatever the fix addresses. Run it a second time and the corrected file executes.

This applies only to changes that touch the workflow file. Every other release is
one run.

## Options

```bash
gh workflow run promote.yml                                   # promote, tag, release
gh workflow run promote.yml -f release=false                  # promote only, no tag
gh workflow run promote.yml -f notes_file=docs/releases/X.md  # hand-written notes
```

Without `notes_file` the release notes are generated from the commits.

## When it fails

Read which step failed.

**"Promote develop to stage, then stage to main"** — a check went red on one of
the two pull requests. It is still open; fix the branch and run the workflow
again. It reuses the open pull request rather than opening a second one.

**"Tag main and publish the release"** — promotion already succeeded, so `main`
carries the new `VERSION` and only the tag is missing. Fix the cause and run
again; the promotion steps will find nothing to do and skip straight to tagging.
