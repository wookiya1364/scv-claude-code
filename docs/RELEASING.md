# Releasing the Claude wrapper

Do not promote or tag by hand — the promote workflow is what keeps every release
identical.

A release is two changes, not one. The Core pin moves in the sync bot's pull
request; the wrapper version moves in yours. Folding both into a single branch is
what went wrong in 0.25.0 and 0.26.0, and a merge-time gate now refuses it.

## 1. Merge the Core sync pull request first

A new Core pin arrives as an automatic `chore/core-v<version>` pull request from
`core-sync.yml`. Merge that one on its own, before you touch the version.

`vendor/scv-core/**`, `core.lock`, and `TEMPLATE_VERSION` belong to it.
`scripts/set-wrapper-version.sh` never touches them, and neither should you.

**Do not vendor Core by hand.** It is tempting during a release, because the
version bump is already open in front of you and copying the tree into that same
branch looks like it saves a round trip. It does not save anything. The bot's
pull request then arrives already satisfied and gets closed as redundant — that
is what happened to #112 in the 0.26.0 release — and the two paths are not
equivalent. The bot resolves the published release artifact and records both the
canonical and the materialized hashes in `core.lock`. A hand copy records
whatever the working tree held at the time. Afterwards nothing distinguishes
them.

`check-vendor-provenance.sh` enforces this at merge time; `branch-flow.yml` runs
it as the "Vendor gate" step. It denies any pull request that rewrites
`vendor/scv-core/` unless the branch is the bot's `chore/core-*`, the pull
request is part of the release chain (into `stage` or `main`), or the title
carries `[manual-vendor: <reason>]` — the same shape as `[no-plan: <reason>]`.

Hand-vendoring stays available, because a Core contract change can genuinely
outrun the bot. It just has to be declared, with a reason.

## 2. Bump the wrapper version

`<version>` below is whatever you are releasing — `0.28.0`, `1.0.0`,
`1.0.0-rc.1`. Nothing here is fixed to a particular number.

```bash
VERSION=<version>       # e.g. VERSION=0.28.0

# Bump the wrapper version. This touches every place that records it at once:
# VERSION, .claude-plugin/plugin.json, .claude-plugin/marketplace.json.
# The READMEs show the release through a badge, so nothing there needs editing.
bash scripts/set-wrapper-version.sh "$VERSION"
```

Write `docs/releases/$VERSION.md`, then open a pull request into `develop` and
merge it. Two things about that pull request:

- **The branch has to be `chore/…`.** `check-branch-flow.sh` accepts only
  `feat/`, `fix/`, `docs/`, `chore/`, `refactor/` and `test/` into `develop`.
  Releases use `chore/release-<version>`.
- **The title has to carry `[no-plan: <reason>]`.** See below.

## The release pull request needs `[no-plan: <reason>]`

The provenance gate — `check-provenance.sh`, run by `branch-flow.yml` — demands
that a pull request changing code add an archived plan under
`scv/archive/<slug>/PLAN.md`. A version bump is code by that definition: only
`scv/**`, `*.md`, `.gitignore`, `.gitattributes` and `LICENSE` are exempt, so
`docs/releases/$VERSION.md` passes but `VERSION` and the two
`.claude-plugin/*.json` files do not. And this repository has no `scv/`
workspace to hold a plan — the plan a wrapper release ships lives in scv-core.

So declare it in the title. The last two releases used these — each one a single
line, wrapped here to fit:

```text
chore: release 0.26.0 — Core 0.26.0, deck redesign
  [no-plan: wrapper release chore; the plan is archived in scv-core]

chore: release 0.27.0 — Core 0.27.0, promote wait and vendor gate
  [no-plan: a release commit bumps VERSION and adds release notes;
   the plan it ships is archived in scv-core]
```

The bracket has to hold text. An empty `[no-plan]` is refused on purpose — the
reason is the entire point of the marker.

The promote workflow's own pull requests need no marker: anything based on
`stage` or `main` is exempt as part of the release chain.

## 3. Promote, tag, and publish

```bash
gh workflow run promote.yml -f notes_file="docs/releases/$VERSION.md"
```

That opens `develop → stage` and `stage → main` as pull requests, waits until
GitHub itself calls each one mergeable, merges them, tags `main` from `VERSION`,
and publishes the GitHub release.

## Why not by hand

The workflow never pushes to a permanent branch — the branch ruleset requires a
pull request for `develop`, `stage`, and `main`, so it opens them and merges.
`workflow_dispatch` is its only trigger, which means starting it is the human
gate: nothing promotes on a schedule or on push.

A red check stops the chain and leaves that pull request open. A failed
promotion is a pull request you can read, not a half-finished merge.

Versions used to live in a handful of files and get edited one at a time. A
release that updated only some of them shipped a plugin whose manifest disagreed
with its own `VERSION`. `set-wrapper-version.sh` removes that class of mistake —
and it fails loudly rather than skipping a file it cannot find.

## The one thing that needs two runs

`workflow_dispatch` always executes the copy of the workflow file on the default
branch. So when the change you are promoting **edits `promote.yml` itself**, the
first run still uses the old file: it promotes your fix to `main` and may fail on
whatever the fix addresses. Run it a second time and the corrected file executes.

This applies only to changes that touch the workflow file. Every other release is
one run. The 0.27.0 promote wait is the current example — it shipped in 0.27.0
and takes effect for the first time on the release after it.

## Options

```bash
gh workflow run promote.yml                       # promote, tag, release
gh workflow run promote.yml -f release=false      # promote only, no tag
gh workflow run promote.yml \
  -f notes_file=docs/releases/<version>.md        # hand-written notes
```

The tag always comes from whatever `VERSION` holds on `main` — the workflow takes
no version argument, so there is nothing to keep in sync by hand.

Without `notes_file` the release notes are generated from the commits.

## When it fails

Read which step failed.

**"Promote develop to stage, then stage to main"** — a check went red on one of
the two pull requests, the branch conflicts with its base, or the pull request
never became mergeable within fifteen minutes. Either way it is still open and
nothing is left half-promoted; fix the branch and run the workflow again. It
reuses the open pull request rather than opening a second one.

The step waits on GitHub's own `mergeStateStatus`, not on a count of checks.
Counting was wrong: `Contract (${{ matrix.os }})` is a matrix job, and when a
path filter skips it, it is reported under that unexpanded name before the real
jobs exist. The count reached one immediately, the wait ended, and the merge was
rejected because the required checks had not started — two hand-merges in the
0.26.0 release. Three facts now have to hold at once: nothing failed, nothing is
still running, and GitHub no longer calls the pull request `BLOCKED`. Requiring
`CLEAN` alone would deadlock on that same placeholder, which holds the rollup at
`UNSTABLE` forever.

**The workflow ran the old logic** — see "The one thing that needs two runs"
above.

**"Tag main and publish the release"** — promotion already succeeded, so `main`
carries the new `VERSION` and only the tag is missing. Fix the cause and run
again; the promotion steps will find nothing to do and skip straight to tagging.
