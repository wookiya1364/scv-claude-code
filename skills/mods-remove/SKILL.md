---
name: mods-remove
description: "Remove one installed SCV mod — pick it from the installed list. No arguments. Use whenever the user wants to uninstall or remove an SCV mod — not only when they type /scv:mods-remove."
argument-hint: ""
allowed-tools:
  - "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/mods.sh:*)"
  - "AskUserQuestion"
---

# /scv:mods-remove

No argument. First list the installed mods (changes nothing):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/mods.sh" list
```

- `MOD: <name> installed <version>` lines → ask with `AskUserQuestion` which one to remove: first
  option (recommended) "keep everything", then one option per installed mod. Picking a mod is the
  confirmation.
- No installed mod → say so in one line and stop.

Then remove the picked mod:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/mods.sh" remove "<picked mod>"
```

Report `RESULT:` in plain words ("scv-hello removed") and every `NEXT:` line as it is — the user runs
`/reload-plugins` (or opens a new session). A `failed` result is reported as failed, never as removed.
Never edit `~/.claude/plugins` by hand or touch project files.
