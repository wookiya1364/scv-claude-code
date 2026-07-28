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

## Flow

1. Branch off `develop` (e.g. `feat/<slug>`), open a PR **→ `develop`**.
2. Promote `develop` → `stage` → `main` via PR.

Pinned SCV Core updates follow the same path. The scheduled, manual, or
release-dispatched `core-sync` workflow opens `chore/core-v<version>`
**→ `develop`** after verifying the release checksum and running the wrapper
regression suite. It never pushes a core update directly to a permanent branch.

Merged head branches are auto-deleted (repo setting `delete_branch_on_merge`).
`/gclean` cleans up the corresponding **local** branches whose remote was deleted.

> This file is the branch-strategy reference (equivalent to the "§10" the
> `check-branch-flow.sh` / `gclean` sources point to).
