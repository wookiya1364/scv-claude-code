---
description: "Choose a model policy and apply it to every SCV command's frontmatter. Persists the choice in scv/scv_settings.json so /scv:sync can reapply it after a plugin update. The shipped default is the session model — no per-command model selection until you turn one on. Use whenever the user wants to change which model SCV commands run on — not only when they type /scv:set-models."
argument-hint: "[recommended|all-opus|all-sonnet|all-haiku|session-default]"
allowed-tools:
  - "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/apply-model-policy.sh:*)"
  - "Bash"
  - "AskUserQuestion"
  - "Read"
  - "Edit"
  - "Write"
---

# /scv:set-models

Apply a model policy to all SCV commands and remember the choice in `scv/scv_settings.json`. The shipped default is the session model.

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

Otherwise, fire **AskUserQuestion** with these 5 options (the first is the shipped default — put it first in the list):

```
Question: "Which model policy do you want for SCV commands?"
options:
[1] "session-default (Recommended — the shipped default)"
    description: "No model: lines at all. Every SCV command runs on the model your Claude Code session already uses — pick Fable, Opus, or anything else once, and SCV never changes it. This is what a fresh install does."
[2] "recommended"
    description: "Per-command mapping to save cost: status/report/update/install-deps run on haiku; sync/help/promote/codegen/regression/work run on opus. Note: help runs every turn, so this switches your session to opus on nearly every turn."
[3] "all-opus"
    description: "Every SCV command uses opus. Highest quality, significantly higher cost."
[4] "all-sonnet"
    description: "Every SCV command uses sonnet. A middle ground if you want one fixed model for SCV."
[5] "all-haiku"
    description: "Every SCV command uses haiku. Lowest cost; reasoning-heavy commands (work, codegen, promote) may degrade."
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

## Step 3 — Persist the choice in the settings file

The choice must survive `/scv:sync` and plugin updates (a fresh plugin cache carries
no `model:` lines; sync re-applies your policy from the settings file). Persist it with
the Core script — it creates the settings file when absent and leaves every unrelated
line byte for byte:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/vendor/scv-core/core/scripts/settings-set.sh" SCV_MODEL_POLICY=<POLICY>
```

Do not hand-edit the settings file with Write or Edit — the script is what keeps this
write legible to the workspace guard. The value MUST be the literal policy identifier
(e.g., `recommended`), never quoted, never with spaces. Projects that stored the key in
`.env` before settings moved keep working: sync reads the settings file first and falls
back to `.env`.

## Step 4 — User notice

Print a short final summary in the resolved language. Include:

- Which policy was applied.
- How many files changed (from Step 2 output).
- A reminder: "Restart Claude Code or run `/reload-plugins` so the new model frontmatter takes effect."
- A note: "Whenever `/scv:sync` runs after a plugin update, this policy is re-applied from `scv/scv_settings.json`. If you never set one, commands simply follow your session model."

Example summary (English):

> Applied model policy: **all-haiku**.
> 4 files updated.
> Run `/reload-plugins` (or restart Claude Code) for the change to take effect.
> Saved `SCV_MODEL_POLICY=all-haiku` in `scv/scv_settings.json` — `/scv:sync` will re-apply it after future plugin updates.

## Non-negotiable rules

- **Never use `<chosen>` / `<POLICY>` style placeholder strings inside a shell command that will actually execute.** When generating the Bash call in Step 2, the resolved policy identifier must be inlined as a real literal (e.g., `--policy all-haiku`). The `<POLICY>` notation in this file is documentation only.
- **Never run `apply-model-policy.sh` without first resolving `POLICY` from Step 1.** If Step 1 cannot resolve a valid policy (e.g., AskUserQuestion was cancelled), stop and report — do not guess.
- **Never modify command files directly.** All frontmatter updates go through the helper script for idempotence and validation.
- **Never write `SCV_MODEL_POLICY=` with an empty value to the settings file.** If the user picks `session-default`, the value is the literal string `session-default`, not empty.
