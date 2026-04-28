---
description: "Sync the SCV template into this project, honoring frontmatter merge_policy. PROJECT:LOCAL blocks are always preserved."
argument-hint: ""
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/sync.sh:*)"]
---

# /scv:sync

Run sync. Use `--dry-run` first to preview what will change:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/sync.sh" --project-dir "$(pwd)" $ARGUMENTS
```

Semantics:
- Files with `merge_policy: overwrite` → replaced
- Files with `merge_policy: preserve` → skipped unless `--force FILE` is passed
- Files with `merge_policy: merge-on-markers` (incl. scv/CLAUDE.md, scv/TESTING.md, scv/REPORTING.md) → template replaces file, but the `PROJECT:LOCAL` block is restored from the local copy
- `scv/promote/*.md` → never touched
- All modified files are backed up to `.scv-backup/<timestamp>/` before changes
