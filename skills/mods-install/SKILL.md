---
name: mods-install
description: "Install one SCV mod (e.g. scv-hello, the SCV pane in the desktop app) — pick it from the mods marketplace; adds the marketplace first when it is missing. No arguments. Use whenever the user wants to install or add an SCV mod — not only when they type /scv:mods-install."
argument-hint: ""
allowed-tools:
  - "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/mods.sh:*)"
  - "AskUserQuestion"
---

# /scv:mods-install

No argument. First list what can be installed (this adds the mods marketplace when it is missing):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/mods.sh" candidates
```

- `MOD: <name> available` lines → ask with `AskUserQuestion` which one to install: one option per mod
  (up to four; more → two steps), the first marked recommended, plus "none for now". If the user
  named a mod in plain words and it is in the list, still confirm it in one question. Picking is the
  confirmation.
- No `MOD:` line → say every mod is already installed (or the marketplace offers none) and stop.
- A `STEP: … fail` line → relay the `NEXT:` lines (private marketplace: `gh auth login`, then
  `gh auth setup-git`, or an SSH key) and stop.

Then install the picked mod:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/mods.sh" install "<picked mod>"
```

Report `RESULT:` in plain words ("scv-hello installed, 745b604") and every `NEXT:` line as it is —
the user runs `/reload-plugins` (or opens a new session) to start the mod. Never report a failed step
as installed. Never edit `~/.claude/plugins` by hand or touch project files.
