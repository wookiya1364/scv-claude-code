---
name: update
description: "Update the installed SCV plugin — and every installed SCV mod — to the latest release, from a terminal session or the Claude app alike. Reads the latest version with git (no gh needed) and updates through the claude plugin command line. Never modifies project files. Use whenever the user asks to update SCV or asks whether SCV is current — not only when they type /scv:update."
argument-hint: ""
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/update.sh:*)"]
---

# /scv:update

Bring the installed SCV plugin and every installed SCV mod up to date with one command. It works the
same in a terminal session and in the Claude app: the engine calls the `claude plugin` command line
itself, so the user types no other command.

## Language preference

Resolve the user's preferred language with this priority, then use it for the report:

1. `~/.claude/settings.json` (or project `.claude/settings.json` / `.claude/settings.local.json`) — `language` key.
2. Project `.env` — `SCV_LANG`.
3. Auto-detect from the user's most recent message language.
4. Default to English.

Technical identifiers (command names, plugin/marketplace names, version tags) stay as-is in every language.

## Which run

**Update** — the user typed `/scv:update` or asked to update. Run it without asking first: an update
only moves installed versions forward.

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/update.sh" apply
```

**Check only** — the user only asked whether SCV is current. Run it with no argument; it changes
nothing and touches no mod:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/update.sh"
```

## What the engine prints

Five diagnostic lines, in both runs:

- `INSTALLED_VERSION:` — the running plugin's version
- `MARKETPLACE_NAME:` · `PLUGIN_NAME:` — `scv-claude-code` · `scv`
- `LATEST_VERSION:` — the highest release tag, read with git; or `(unavailable — <reason>)`
- `UP_TO_DATE:` — `yes` / `no` / `unknown`

Then, for an update:

- `CHANNEL:` — `prod`, or `dev` / `stage` / `other:<branch>`
- `STEP: <claude plugin arguments> ok|fail` — one per command the engine ran; `DETAIL:` lines carry a failed command's own error text
- `RESULT: scv …` — one line per install scope (`[user]`, `[project]`): `updated <old> -> <new>`,
  `up-to-date <version>`, `unchanged <version>` (a newer tag exists but the marketplace does not serve it yet),
  `failed <step>`, `skipped channel <name>`, or `not-installed`
- the mods part, as `/scv:mods` prints it: `MODS_MARKETPLACE:`, its own `STEP:` lines, one `RESULT:` per mod
  (per scope when a mod is installed in more than one), or `RESULT: none` when no mod is installed
- `NEXT:` — one line per thing left to do

## Report

In plain words, in the user's language — the versions are named on purpose (the user acts on them;
where that differs from the always-on plain-language text, the resolution order in `scv/SCV.md`
Top-level rules applies):

1. SCV itself first: "0.85.2 → 0.94.0", or "already up to date"; name the scope only when there is more than one.
2. Then each mod, the same way.
3. Relay every `NEXT:` line as it is. Quote the `DETAIL:` text of a failed step. Never report a failed
   step as done, and never let one side hide the other: SCV updated and a mod failed are two results.
4. When `LATEST_VERSION:` is unavailable, say the reason from that line. An update still runs — the
   command line decides, and the result is told from the versions before and after.
5. Only when something changed: it takes effect in a **new session** (an open terminal session can
   run `/reload-plugins` instead). This command cannot do that step itself.

The project's workflow docs (`scv/SCV.md`, `scv/PROMOTE.md`, etc.) close their own gap: in the new
session, the first Core-scripted action compares the project's stamped template against the payload's
and refreshes the docs when they differ — and reports that it did, in that turn's output. Nothing to
run by hand. `/scv:update` itself never touches project files; `/scv:sync` remains the by-hand re-run
and the interactive path for pre-2.x projects, which the automatic refresh deliberately skips.

## Never

- Modify project files, or run the template sync from here.
- Edit Claude Code's plugin folders or list files by hand — plugins change only through the `claude plugin` command line, which the engine calls.
- Switch channels: a dev or stage install is skipped on purpose — point the user to `/scv:channel`.
- Install or remove a mod here — `/scv:mods-install` and `/scv:mods-remove` do that.
- Fall back silently when `LATEST_VERSION:` is unavailable — surface the reason from the engine's output.
