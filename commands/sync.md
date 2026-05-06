---
description: "Sync the SCV template into this project, honoring frontmatter merge_policy. PROJECT:LOCAL blocks are always preserved."
argument-hint: ""
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/sync.sh:*)"]
---

# /scv:sync

Run sync. Use `--dry-run` first to preview what will change.

## Language preference

Resolve the user's preferred language with this priority, then use it for any user-facing summary or warnings you print:

1. `~/.claude/settings.json` (or project `.claude/settings.json` / `.claude/settings.local.json`) — `language` key (Claude Code official).
2. Project `.env` — `SCV_LANG` (set by `/scv:help`'s first-time setup).
3. Auto-detect from the user's most recent message language.
4. Default to English.

Technical identifiers (file paths, frontmatter keys like `merge_policy`, slash command names, marker tokens like `PROJECT:LOCAL`) stay as-is.

To run:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/sync.sh" --project-dir "$(pwd)" $ARGUMENTS
```

Semantics:
- Files with `merge_policy: overwrite` → replaced
- Files with `merge_policy: preserve` → skipped unless `--force FILE` is passed
- Files with `merge_policy: merge-on-markers` (incl. scv/CLAUDE.md, scv/TESTING.md, scv/REPORTING.md) → template replaces file, but the `PROJECT:LOCAL` block is restored from the local copy
- `scv/promote/*.md` → never touched
- All modified files are backed up to `.scv-backup/<timestamp>/` before changes
