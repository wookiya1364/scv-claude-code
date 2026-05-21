---
description: "Check installed SCV plugin version vs latest release, and guide the user through /plugin marketplace update + /reload-plugins. Read-only — does not modify project files. (v0.11.2+)"
argument-hint: ""
allowed-tools:
  - "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/update.sh:*)"
  - "AskUserQuestion"
model: haiku
---

# /scv:update

Update the installed SCV plugin to the latest release.

Claude Code's slash commands cannot self-update the host plugin directly — this command runs a version diagnostic and walks the user through the two built-in commands required: `/plugin marketplace update <name>` and `/reload-plugins`.

## Language preference

Resolve the user's preferred language with this priority, then use it for status messages and questions:

1. `~/.claude/settings.json` (or project `.claude/settings.json` / `.claude/settings.local.json`) — `language` key.
2. Project `.env` — `SCV_LANG`.
3. Auto-detect from the user's most recent message language.
4. Default to English.

Technical identifiers (slash command names like `/plugin marketplace update`, plugin/marketplace names, version tags) stay as-is in every language.

## Protocol

### Step 1 — Run the diagnostic

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/update.sh"
```

Parse the output keys:
- `INSTALLED_VERSION:` — current plugin.json version
- `MARKETPLACE_NAME:` — marketplace.json root name (`scv-claude-code`)
- `PLUGIN_NAME:` — plugin.json name (`scv`)
- `LATEST_VERSION:` — latest GitHub release tag (gh CLI), or `(unavailable — ...)` with reason
- `UP_TO_DATE:` — `yes` / `no` / `unknown`

### Step 2 — Report + guide based on UP_TO_DATE

Branch by `UP_TO_DATE` value:

| Value | Action |
|---|---|
| **`yes`** | Report: "Already on latest (`<INSTALLED_VERSION>`). No action needed." Stop. |
| **`no`** | Report: "Installed `<INSTALLED_VERSION>` → latest `<LATEST_VERSION>`." Then proceed to Step 3 (guide commands). |
| **`unknown`** | Report the unavailability reason (from `LATEST_VERSION:` line). Then ask via `AskUserQuestion` whether to proceed with manual update commands anyway (Step 3) or stop. |

### Step 3 — Guide the two built-in commands

Print to the user, in the resolved language:

> To update, run these two commands in this Claude Code session:
>
> ```
> /plugin marketplace update <MARKETPLACE_NAME>
> /reload-plugins
> ```
>
> The first refreshes the marketplace's local copy. The second activates the updated plugin without restarting Claude Code.
>
> After both run, re-invoke `/scv:update` to verify the new version is detected.

Substitute `<MARKETPLACE_NAME>` with the actual value from Step 1 (e.g., `scv-claude-code`).

### Step 4 — Verification (optional reminder)

After the user reports running both commands, suggest re-invoking `/scv:update`. Do not auto-rerun — the user's session needs to pick up the reloaded plugin's `scripts/update.sh`, which only happens on next invocation.

## Why not auto-update?

Claude Code slash commands run in a sandboxed protocol — they cannot programmatically invoke other slash commands (`/plugin marketplace update`, `/reload-plugins`) on behalf of the user. `/scv:update` therefore acts as a *diagnostic + guide*, not an automatic updater.

For the project-level template re-sync (`scv/CLAUDE.md`, `scv/TESTING.md`, etc. after a plugin update bumps the template), run `/scv:sync` separately. `/scv:update` does not touch project files.

## Never

- Modify project files. This command is read-only on plugin metadata + an optional `gh` API call.
- Auto-invoke `/plugin marketplace update` or `/reload-plugins` — guide the user only.
- Fall back silently when `LATEST_VERSION:` is unavailable — surface the reason from the helper output.
