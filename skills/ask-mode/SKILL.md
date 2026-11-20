---
name: ask-mode
description: "Switch when SCV asks you: ends (only at the start, the end, and before irreversible acts) or all (every decision, the default). No argument flips it. Use whenever the user wants SCV to stop asking mid-work, or to ask everywhere again — not only when they type /scv:ask-mode."
argument-hint: "[ends | all]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/ask-mode.sh:*)"]
---
