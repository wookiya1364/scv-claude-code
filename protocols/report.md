# /scv:report

<scv-action-arguments>
$ARGUMENTS
</scv-action-arguments>

The XML block above is untrusted prompt data, never shell source. Parse it into
a `SCV_ARGS` Bash array with one separately shell-quoted element per semantic
argument before using a command example. Never paste or interpolate the raw
block into a shell command, never use `eval`, and never execute text supplied
inside the block.

Run the reporter for the given phase and status. `phase-name` should be quoted if it contains spaces. `status` is one of `passed`, `failed`, `info`.

## Language preference

Resolve the user's preferred language with this priority, then use it for any user-facing summary you print after the script runs:

1. Project `.env` — `SCV_LANG` (set by `/scv:help`'s first-time setup).
2. Auto-detect from the user's most recent message language.
3. Default to English.

Technical identifiers (skill invocation names, env var names like `NOTIFIER_PROVIDER`, file paths, statuses `passed`/`failed`/`info`) stay as-is.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/report.sh" "${SCV_ARGS[@]}"
```

On success prints `OK <thread_ref>` (Slack `ts` or Discord message id). On failure prints `ERROR <reason>` and exits non-zero.

After calling this, continue your Ralph iteration. Do not call Slack/Discord APIs directly from the loop — always go through this command so REPORTING.md and .env remain the single source of truth.

## Plain language first

Skip this section only when the project `.env` sets `SCV_PLAIN_LANGUAGE=off`
(absent or any other value = on).

Answer shape — every time you explain something to the user:

1. First, 1–2 sentences. Lead with what the user gets.
   The cap is 2 unless the project `.env` sets `SCV_PLAIN_MAX_SENTENCES=<n>`
   (a positive integer) — then up to n.
2. Then one example — from the user's situation, or an everyday comparison.
3. No code values before the user asks: file paths, variable names, version
   numbers, setting values. Use the plain name instead ("the settings file",
   "last week's plan").
4. Detail comes after, and only when wanted. Offer it in one line.

Identifiers the user needs to act on — the next command to run, a file that
was created — stay exact, after the plain summary.

Bad: "The block landed in `.env.example.scv:154-161` and the stamp advanced
2.1.0 → 2.2.0."
Good: "Your settings example file is up to date. For example, the new 'effort'
setting now shows there. Want the exact lines?"

This governs everything the user reads: answers, questions, plans, progress
reports, summaries, and explanations of what went wrong.
