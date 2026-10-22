---
name: mods
description: "Bring every installed SCV mod (e.g. scv-hello, the SCV pane in the desktop app) up to date and list the mods — installed with version, and available. No arguments. Use whenever the user asks to update or check their SCV mods — not only when they type /scv:mods."
argument-hint: ""
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/mods.sh:*)"]
---

# /scv:mods

SCV mods are Claude Code plugins from a separate marketplace (default `wookiya1364/scv-mods`, private;
`SCV_MODS_MARKETPLACE` overrides it). This command takes no argument and runs without asking — an
update only moves installed mods forward, and the list changes nothing:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/mods.sh"
```

The helper prints `MODS_MARKETPLACE:`, one `STEP:` per `claude plugin` call, `RESULT:` per mod, then
`MOD:` lines (installed with version, or available), and `NEXT:` when there is something to do.

Report it in plain words, in the user's language: each mod's result first ("scv-hello 745b604 →
9a1c2d3", or "already up to date"), then the list. Relay every `NEXT:` line as it is — a failed
private-marketplace read prints the sign-in steps (`gh auth login`, then `gh auth setup-git`, or an
SSH key); never report a failed step as done. When a mod changed, the user runs `/reload-plugins`
(or opens a new session) — this command cannot run it. To add a mod: `/scv:mods-install`; to remove
one: `/scv:mods-remove`.

Never edit `~/.claude/plugins` by hand or touch project files.
