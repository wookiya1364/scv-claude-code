# Branch flow

Permanent branches: **`main`** · **`stage`** · **`develop`**. They are protected
(PR required, no direct push / no deletion / no force-push) via a GitHub ruleset
(`protect-permanent-branches`) plus the `branch-flow` workflow.

## Allowed merges (enforced by `scripts/check-branch-flow.sh`)

| Target | Allowed sources |
|---|---|
| `develop` | `feat/*` · `fix/*` · `docs/*` · `chore/*` · `refactor/*` · `test/*` |
| `stage`   | `develop` |
| `main`    | `stage` · `fix/*` (hotfix) |

`branch-flow` also runs two vendored gates on a PR into `develop`. A PR that
changes code must add the plan it came from at `scv/archive/<slug>/PLAN.md`
(`check-provenance.sh`) — this repo has no `scv/` workspace, so in practice the
title declares `[no-plan: <reason>]` and names where the plan lives. A PR that
rewrites `vendor/scv-core/` must declare `[manual-vendor: <reason>]`
(`check-vendor-provenance.sh`). An empty marker with no reason is refused by
both. Both exempt the release chain (base `stage` · `main`) and the sync bot's
`chore/core-*`; prose-only diffs are exempt from provenance.

## Flow

1. Branch off `develop` (e.g. `feat/<slug>`), open a PR **→ `develop`**.
2. Promote `develop` → `stage` → `main` via PR.

Pinned SCV Core updates follow the same path. The scheduled, manual, or
release-dispatched `core-sync` workflow opens `chore/core-v<version>`
**→ `develop`** after verifying the release checksum and running the wrapper
regression suite. It never pushes a core update directly to a permanent branch.

Merged head branches are auto-deleted (repo setting `delete_branch_on_merge`).
`/gclean` cleans up the corresponding **local** branches whose remote was deleted.

> This file is the branch-strategy reference. `scripts/check-branch-flow.sh`
> and `gclean` point here.
