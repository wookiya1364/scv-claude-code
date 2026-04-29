---
name: reporting
version: 1.0.0
status: draft
last_updated: 2026-04-17
applies_to: []
owners: ["@team"]
tags: [standard, core, reporting]
standard_version: 1.0.0
merge_policy: merge-on-markers
---

# REPORTING — Collab tool reporting convention

> This document is closer to **configuration**. Claude confirms the user's collab tool and channels in `INTAKE.md` Step 6, then records them in the `PROJECT:LOCAL` block.

## How to elicit (order of questions)

1. **Pick the collab tool**: "Which collab tool does the team use — Slack or Discord?"
2. **Bot existence**: "Does a Bot App already exist? If not, you'll need to create and invite it first."
3. **Channel mapping**: "How would you like to use these per-event channels?"
   - `phase-complete` — Phase completion report
   - `e2e-failure` — E2E failure
   - `daily-summary` — (optional) daily summary
   - `error-alert` — (optional) critical errors
4. **Message format specifics**: "Beyond the default format, any extra fields, icons, or mention rules?"

## Completion criteria

- [ ] `NOTIFIER_PROVIDER` decided (slack | discord)
- [ ] Bot token issued and bot invited to channels
- [ ] At least `phase-complete` and `e2e-failure` channel IDs captured
- [ ] Tokens and channel IDs filled in `.env`
- [ ] `/scv:report` dry-run succeeded once
- [ ] User confirmation

## Reporting principles (template-fixed)

- Ralph Loop must NOT call HTTP directly. Always go through the `/scv:report <phase> <status>` slash command.
- Every report attaches **at least 1 visual artifact** (if none, summary must explicitly note `[no artifact: reason]`).
- Success / failure / progress reports are bundled into the **same thread**.

## Event → channel mapping (template convention)

| Event | Trigger | Env var (primary channel) |
|---|---|---|
| `phase-complete` | `passed` | `<PROVIDER>_CHANNEL_ID_PHASE_COMPLETE` |
| `e2e-failure` | `failed` | `<PROVIDER>_CHANNEL_ID_E2E_FAILURE` |
| `daily-summary` | `--event daily-summary` | `<PROVIDER>_CHANNEL_ID_DAILY_SUMMARY` |
| `error-alert` | `--event error-alert` | `<PROVIDER>_CHANNEL_ID_ERROR_ALERT` |
| `regression-summary` | `--event regression-summary` (periodic regression-pass notice) | `<PROVIDER>_CHANNEL_ID_REGRESSION_SUMMARY` |
| `regression-failure` | `--event regression-failure` (some archived TESTS broke — triage needed) | `<PROVIDER>_CHANNEL_ID_REGRESSION_FAILURE` |
| `info` | `info` | `<PROVIDER>_CHANNEL_ID_PHASE_COMPLETE` (reused) |

If the env var is missing, fall back to `<PROVIDER>_CHANNEL_ID` (primary).

## Attachment rules (template-fixed)

| Status | Attachment |
|---|---|
| `passed` | Screenshot + video (if available) |
| `failed` | Screenshot + video + log tail (20KB) |
| `info` | Screenshot (only if available) |
| `regression-summary` | `test-results/regression-summary.json` + human-readable summary text (no screenshot/video) |
| `regression-failure` | Same JSON + per-failed-slug log tail (up to 20KB) |

All attachments thread under the main message.

## Variable substitution (template-fixed)

Substituted by `render-template.sh`:

| Variable | Source |
|---|---|
| `{project}` | `.env` `PROJECT_NAME` |
| `{phase}` · `{status}` | Command arguments |
| `{git_short}` | `git rev-parse --short HEAD` |
| `{attempt}` · `{summary}` | Command arguments |
| `{duration}` | `test-results/results.json` |

## This project's configuration

<!-- PROJECT:LOCAL START -->
<!-- This block is preserved on sync. Put real channel IDs and any custom rules here. -->

**Collab tool**: <TODO: slack | discord>

**Slack workspace / Discord server**: <TODO>

**Bot name**: <TODO>

**Channel ID mapping** (actual values go in `.env`; here is for reference):

| Event | Channel name | Channel ID |
|---|---|---|
| phase-complete | <TODO> | <TODO> |
| e2e-failure | <TODO> | <TODO> |

<!-- PROJECT:LOCAL END -->
