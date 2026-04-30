---
description: "Run accumulated regression across scv/archive/**/TESTS.md (and optionally promote/) with supersede/obsolete skip graph. On failure, triage each slug via AskUserQuestion (regression / obsolete / flaky)."
argument-hint: "[<slug-prefix>]"
allowed-tools:
  - "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/regression.sh:*)"
  - "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/report.sh:*)"
  - "Bash"
  - "AskUserQuestion"
  - "Read"
  - "Edit"
---

# /scv:regression

You — Claude — drive the accumulated regression: **run every archived TESTS that hasn't been superseded or marked obsolete, then triage any failures with the user**.

## Language preference

Resolve the user's preferred language with this priority, then use it for ALL user-facing output (AskUserQuestion text, triage prompts, summaries):

1. `~/.claude/settings.json` (or project `.claude/settings.json` / `.claude/settings.local.json`) — `language` key (Claude Code official).
2. Project `.env` — `SCV_LANG` (set by `/scv:help`'s first-time setup).
3. Auto-detect from the user's most recent message language.
4. Default to English.

Technical identifiers stay as-is: file paths, slash command names, frontmatter keys (`status`, `obsoleted_at`, `obsoleted_by`, `supersedes`), env var names, SCV terms (`promote`, `archive`, `obsolete`, `flaky`). If both `settings.json language` and `.env SCV_LANG` are unset, suggest `/scv:help` once to lock the preference (don't block — fall back to auto-detect / English for now).

**Non-negotiable rules:**
- **Never modify the body of an archived TESTS.md.** Obsolete marking is done only via 3 frontmatter fields on the archived folder's PLAN.md (`status`, `obsoleted_at`, `obsoleted_by`).
- **Don't force-run a slug declared in another's `supersedes:`** — it's an intentional skip already.
- **`--ci` mode must NOT call AskUserQuestion.** Verdict is via exit code only.
- **Don't bundle multiple failures into one triage** — each slug gets its own AskUserQuestion (triage decisions differ per slug).
- Don't auto-mark a failure as obsolete without explicit user approval if there's no `supersedes` declaration covering it.

## Step 0 — Run

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/regression.sh" $ARGUMENTS
```

Parse the header keys: `MODE:`, `TODAY:`, `SCOPE:`, `TAG_FILTER:`, `TOTAL_SLUGS:`, `SKIPPED_SUPERSEDED:`, `SKIPPED_OBSOLETE:`, `SKIPPED_SCENARIOS:`, `EXECUTED_SLUGS:`, `PASSED_SLUGS:`, `FAILED_SLUGS:`. Blocks: `=== skip list ===`, `=== execution ===`, `=== summary ===`. If failures occur, a `failed_slugs:` line is present.

## Step 1 — All-pass path

If `FAILED_SLUGS: 0`:

1. Give the user a **2–4 line summary** (TOTAL_SLUGS / EXECUTED_SLUGS / PASSED_SLUGS / SKIPPED_*). If skips exist, one line with counts of `[superseded]` · `[obsolete]` · `[scenario-skipped]`.
2. `AskUserQuestion` (optional): "Notify the team about this regression result?"
   - Yes → `bash ${CLAUDE_PLUGIN_ROOT}/scripts/report.sh "accumulated-regression" passed --event regression-summary --summary "<n> slugs passed, <m> skipped (superseded/obsolete)"`
   - No → terminate.

## Step 2 — Failures present → per-slug 3-way triage

For each slug in `failed_slugs`, fire **one independent** AskUserQuestion. Use this template verbatim:

```
Question: "TESTS for '<slug>' failed. How should we handle it?"

Options:
[1] "regression — true regression. I'll fix the current code"
    description:
    "The archived TESTS used to pass and is now broken — likely one of the recent changes
     touched '<slug>'s feature unintentionally.

     Claude's behavior:
     - Won't modify any of this slug's files.
     - If you want, will analyze the failure output and offer 'this line might be the issue'
       suggestions only.
     - Actual code fix is performed by you (/scv:work or direct edit).
     - After fixing, re-run /scv:regression to confirm green."

[2] "obsolete — this TESTS is intentionally broken now"
    description:
    "'<slug>' is no longer an actively maintained feature and should be permanently excluded
     from the regression suite. Use this when a new plan was written without declaring it in
     supersedes, or when environment changes force deprecation.

     What exactly changes?
     - Only 3 fields are added to scv/archive/<slug>/PLAN.md frontmatter:
         status: done → obsolete
         obsoleted_at: <today's date>
         obsoleted_by: manual     (this is the runtime-triage path so 'manual' is fixed)
     - TESTS.md, ARCHIVED_AT.md, and other files are never touched (immutable archive principle).

     Why is this needed?
     - From now on, /scv:regression permanently skips '<slug>'s TESTS.
     - A year later, even when browsing the archive, the 'why isn't this TESTS running?'
       answer remains in PLAN's body, traceable without git history.
     - If status stays 'done', it could be misread as 'completed and still live'."

[3] "flaky — environmental issue. Let me retry"
    description:
    "Test itself is unstable, or external dependencies (network, timezone, shared resources)
     caused the failure. Claude reruns this slug only, up to 2 times:
     bash ${CLAUDE_PLUGIN_ROOT}/scripts/regression.sh --only <slug>
     - Pass within 2 retries → recorded as 'flaky resolved on retry N' and continue.
     - Still failing → re-fire this 3-way dialog."
```

Answer handling:

- **[1] regression**: Don't modify any files. Offer once: "Want me to analyze the failed output tail with you?" (if yes, use `Read`/`Grep` to explore source, suggestions only). Log `[regression] <slug>` to triage log.
- **[2] obsolete**: Modify files per this procedure:
  1. `Read` `scv/archive/<slug>/PLAN.md`
  2. `Edit` frontmatter — adjust 3 fields:
     - `status: done` → `status: obsolete`
     - Add `obsoleted_at: <TODAY>` if missing
     - Add `obsoleted_by: manual` if missing
  3. Never touch TESTS.md or ARCHIVED_AT.md.
  4. Report one line to the user: "Marked `<slug>` as obsolete (PLAN.md frontmatter only)."
  5. Log `[obsolete] <slug>` to triage log.
- **[3] flaky**: Run `bash ${CLAUDE_PLUGIN_ROOT}/scripts/regression.sh --only <slug> --quiet` up to 2 times. On pass, log `[flaky→pass on retry N] <slug>`. If both retries fail, re-fire the 3-way dialog.

## Step 3 — Final summary

Aggregate the triage log and emit a `=== triage log ===` block to the user:

```
=== triage log ===
[regression] 20260301-sspark-payment-bug
[obsolete]   20260115-kmlee-legacy-login
[flaky→pass on retry 1] 20260201-tester-network-test
```

`AskUserQuestion` (optional): "Notify the team about this regression result?"
- Yes + regressions still remain → `--event regression-failure`
- Yes + everything resolved as obsolete/flaky → `--event regression-summary`
- No → terminate.

## Archive scale guidance

When `scv/archive/` accumulates beyond a few dozen slugs, a no-arg `/scv:regression` run can take many minutes. Recommend the user partition the suite with `--tag` (e.g. `core`, `payment`, `auth`) on PLAN.md `tags:` and run `--tag core` for fast pre-merge feedback while saving the full suite for nightly / pre-release. If the user has never set tags, suggest once: "consider tagging recent PLANs with a small set of `tags:` (e.g. `core`, `experimental`) so future regressions can scope by tag."

Do not auto-add tags to existing PLANs. The user owns the tag taxonomy.

## Flag semantics

- `<slug-prefix>` — Substring narrowing across archive + promote. Omit to run all.
- `--tag <x>` — Only slugs whose PLAN.md `tags:` array contains `<x>`. **Recommended for large archives** — see Archive scale guidance above.
- `--include-promote` — Default is archive-only. Adds `scv/promote/**/TESTS.md` to the run set (covers in-flight plans before they're archived).
- `--include-obsolete` — Force-runs slugs with `status: obsolete` (auditing / re-validation).
- `--only <slug>` / `--skip <slug>` — Repeatable. Exact match.
- `--ci` — No AskUserQuestion. Failures exit 2. Auto-writes `test-results/regression-summary.json`.
- `--quiet` — Trims output of passing scenarios. Used by `/scv:work`'s Step 9a pre-flight.
- `--json <path>` — Write JSON summary to a specific path (works outside `--ci` too).
- `--timeout <sec>` — Per-scenario timeout. Default 300.

## Never

- Modify the body of archived TESTS.md or ARCHIVED_AT.md.
- Run a slug already declared in another's `supersedes:` outside the runner.
- Fire AskUserQuestion in `--ci` mode.
- Bundle multiple failures into a single AskUserQuestion.
- Auto-mark an undeclared failure as obsolete without the user's answer.
