---
description: "Show the SCV workflow, commands, current project status, and the recommended next step. Run this first when you don't know what to do."
argument-hint: "[--verbose]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/help.sh:*)"]
---

# /scv:help

Print an overview of SCV, the plugin's commands, a diagnosis of the current project, and what to do next.

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/help.sh" $ARGUMENTS
```
