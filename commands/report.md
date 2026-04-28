---
description: "Post a phase/status report to the team channel per REPORTING.md. Reads .env NOTIFIER_PROVIDER (slack|discord) and uploads E2E artifacts from test-results/."
argument-hint: "\"<phase-name>\" <status>"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/report.sh:*)"]
---

# /scv:report

Run the reporter for the given phase and status. `phase-name` should be quoted if it contains spaces. `status` is one of `passed`, `failed`, `info`.

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/report.sh" $ARGUMENTS
```

On success prints `OK <thread_ref>` (Slack `ts` or Discord message id). On failure prints `ERROR <reason>` and exits non-zero.

After calling this, continue your Ralph iteration. Do not call Slack/Discord APIs directly from the loop — always go through this command so REPORTING.md and .env remain the single source of truth.
