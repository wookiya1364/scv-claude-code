---
description: "Choose a model policy and apply it to every SCV command's frontmatter. Persists the choice in .env so /scv:sync can reapply on template updates. Use whenever the user wants to change which model SCV commands run on — not only when they type /scv:set-models."
argument-hint: "[recommended|all-opus|all-sonnet|all-haiku|session-default]"
allowed-tools:
  - "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/apply-model-policy.sh:*)"
  - "Bash"
  - "AskUserQuestion"
  - "Read"
  - "Edit"
  - "Write"
model: haiku
---

# /scv:set-models

Apply a model policy to all SCV commands and remember the choice in `.env`.

## Language preference

Resolve the user's preferred language with this priority, then use it for ALL user-facing output (AskUserQuestion text, summaries):

1. `~/.claude/settings.json` (or project `.claude/settings.json` / `.claude/settings.local.json`) — `language` key (Claude Code official).
2. Project `.env` — `SCV_LANG`.
3. Auto-detect from the user's most recent message language.
4. Default to English.

Technical identifiers stay as-is: policy names (`recommended`, `all-opus`, `all-sonnet`, `all-haiku`, `session-default`), env var names (`SCV_MODEL_POLICY`, `SCV_LANG`), file paths, model names (`haiku`, `sonnet`, `opus`).

## What each policy does

| Policy | Effect |
|---|---|
| `recommended` | Per-command mapping: `status`/`report`/`update`/`install-deps` → haiku · `sync`/`help`/`promote`/`codegen`/`regression`/`work` → opus. Matches v0.11.5 baseline. **Recommended default.** |
| `all-opus` | Every command uses opus. Highest quality, highest cost. |
| `all-sonnet` | Every command uses sonnet. Balanced. |
| `all-haiku` | Every command uses haiku. Lowest cost; some reasoning-heavy commands may degrade. |
| `session-default` | Removes the `model:` line entirely. Each command runs on whatever model the current Claude Code session is using. |

## Step 1 — Resolve the chosen policy

If `$ARGUMENTS` is exactly one of `recommended`, `all-opus`, `all-sonnet`, `all-haiku`, `session-default`, treat that as the chosen policy and skip to Step 2.

Otherwise, fire **AskUserQuestion** with these 5 options (the first is the recommended default — put it first in the list):

```
Question: "Which model policy do you want for SCV commands?"
options:
[1] "recommended (Recommended)"
    description: "Per-command mapping. status/report/update/install-deps run on haiku (cheap, fast). sync/help/promote/codegen/regression/work run on opus (heavy reasoning). Matches v0.11.5 baseline."
[2] "all-opus"
    description: "Every SCV command uses opus. Highest quality. Significantly higher cost — use only if your team's budget allows."
[3] "all-sonnet"
    description: "Every SCV command uses sonnet. Balanced between cost and quality. Good middle ground if you don't want per-command policy."
[4] "all-haiku"
    description: "Every SCV command uses haiku. Lowest cost. Reasoning-heavy commands (work, codegen, promote) may produce lower-quality output."
[5] "session-default"
    description: "Remove model: lines entirely. Each command inherits the model of the current Claude Code session. Use this if you want full manual control."
```

Map the user's selection to the corresponding lowercase identifier: `recommended` / `all-opus` / `all-sonnet` / `all-haiku` / `session-default`. Call this value **`POLICY`** from now on.

## Step 2 — Apply the policy via the helper script

Run **exactly one** Bash call with the resolved `POLICY` value substituted as a real string (never as a `<placeholder>`):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/apply-model-policy.sh" --policy <POLICY>
```

For example, if the user picked `all-haiku`, the actual call must be:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/apply-model-policy.sh" --policy all-haiku
```

The script will print per-file changes (`status: haiku -> opus` / `report: ok (haiku)` / etc). Capture stdout and surface a short summary to the user — one line per file that changed (skip the `ok` lines).

## Step 3 — Persist the choice in `.env`

The choice must survive `/scv:sync` (which re-renders frontmatter from templates). Persist it:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/vendor/scv-core/core/scripts/env-set.sh" SCV_MODEL_POLICY=<POLICY>
```

It creates `.env` when absent, replaces the key in place when present, and leaves
every unrelated line byte for byte. Do not hand-edit `.env` with Write or Edit —
the script is what keeps this write legible to the workspace guard, and a
hand-rolled sed or an editor call would either be denied or slip past unrecorded.

The value MUST be the literal policy identifier (e.g., `recommended`), never quoted, never with spaces.

## Step 4 — User notice

Print a short final summary in the resolved language. Include:

- Which policy was applied.
- How many files changed (from Step 2 output).
- A reminder: "Restart Claude Code or run `/reload-plugins` so the new model frontmatter takes effect."
- A note: "Whenever `/scv:sync` runs and template frontmatter changes, this policy will be reapplied automatically from `.env`."

Example summary (English):

> Applied model policy: **all-haiku**.
> 4 files updated.
> Run `/reload-plugins` (or restart Claude Code) for the change to take effect.
> Saved `SCV_MODEL_POLICY=all-haiku` in `.env` — `/scv:sync` will keep this in force on future template updates.

## Non-negotiable rules

- **Never use `<chosen>` / `<POLICY>` style placeholder strings inside a shell command that will actually execute.** When generating the Bash call in Step 2, the resolved policy identifier must be inlined as a real literal (e.g., `--policy all-haiku`). The `<POLICY>` notation in this file is documentation only.
- **Never run `apply-model-policy.sh` without first resolving `POLICY` from Step 1.** If Step 1 cannot resolve a valid policy (e.g., AskUserQuestion was cancelled), stop and report — do not guess.
- **Never modify command files directly.** All frontmatter updates go through the helper script for idempotence and validation.
- **Never write `SCV_MODEL_POLICY=` with an empty value to `.env`.** If the user picks `session-default`, the value is the literal string `session-default`, not empty.
