---
description: "Execute one maintenance routine defined in scv/routines/<name>.md (task + guardrails + exit-criteria contract), or list defined routines. SCV never schedules — pair with host features like /loop or cron yourself."
argument-hint: "[<module>] [--list | <name> | --lint <file>]"
allowed-tools:
  - "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/routine.sh:*)"
  - "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/report.sh:*)"
  - "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/pr-helper.sh:*)"
  - "Bash"
  - "AskUserQuestion"
  - "Read"
  - "Glob"
  - "Grep"
  - "Write"
  - "Edit"
model: opus
---

# /scv:routine

Placeholder body — regenerated from the vendored core protocol
(`protocols/routine.md`) by `scripts/project-core.sh` during Core sync.
