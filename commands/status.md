---
description: "Show raw changes since last index + list of active promote plans."
argument-hint: ""
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/status.sh:*)"]
---

# /scv:status

Inspects the project's SCV state (four sections):

- **Raw changes**: files under `scv/raw/` added / modified / removed since `scv/readpath.json` was last updated.
- **Active promote plans**: entries under `scv/promote/` waiting for implementation.
- **Docs graph**: graphify skill presence + docs graph freshness (`missing` / `built` / `stale` / skill-not-installed).
- **Archive**: count of completed plans under `scv/archive/`.

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/status.sh" $ARGUMENTS
```

## Flags

- `--ack` — After showing changes, overwrite `scv/readpath.json` with the current state. Use this when you've reviewed the changes but are deferring `/scv:promote`.
- `--verbose` — Show every changed path (default collapses to 10 per bucket).

## Typical flow

1. Team drops new raw materials into `scv/raw/`.
2. Run `/scv:status` to see what changed and what's pending.
3. Either:
   - Run `/scv:promote` to refine into promote plans (recommended — will also update the index), OR
   - Run `/scv:status --ack` to mark current state as baseline and defer.
