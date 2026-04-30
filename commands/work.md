---
description: "Implement a scv/promote/<slug>/ plan. Reads PLAN.md + TESTS.md, proposes/loads Related Documents as needed, runs the tests, and optionally archives on success."
argument-hint: "[<slug>]"
allowed-tools:
  - "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/work.sh:*)"
  - "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/readpath.sh:*)"
  - "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/pr-helper.sh:*)"
  - "Bash"
  - "Skill(graphify)"
  - "AskUserQuestion"
  - "Read"
  - "Glob"
  - "Grep"
  - "Write"
  - "Edit"
---

# /scv:work

You — Claude — drive a promote plan to completion: **read PLAN.md + TESTS.md → implement → run tests → archive on success**. Full protocol in `scv/PROMOTE.md`.

## Language preference

Resolve the user's preferred language with this priority, then use it for ALL user-facing output (AskUserQuestion text, status messages, summaries, the non-Playwright notice in Step 5b, etc.):

1. `~/.claude/settings.json` (or project `.claude/settings.json` / `.claude/settings.local.json`) — `language` key (Claude Code official, e.g. `"korean"`, `"english"`).
2. Project `.env` — `SCV_LANG` (set by `/scv:help`'s first-time setup).
3. Auto-detect from the user's most recent message language.
4. Default to English.

Technical identifiers stay as-is in every language: file paths, slash command names (`/scv:work`), frontmatter keys (`status`, `kind`, `epic`, `supersedes`), env var names (`SCV_LANG`, `SCV_ATTACHMENTS_*`), and SCV terms (`promote`, `archive`, `orphan branch`, `epic`).

If both `settings.json language` and `.env SCV_LANG` are unset, you may suggest the user run `/scv:help` once to lock the preference (don't block the current task on it — fall back to auto-detect / English for now).

**Non-negotiable rules:**
- Never delete or move files outside the scope of this plan.
- Never archive without either (a) tests passing AND user approval in this conversation, or (b) the user's earlier declarative pre-approval (e.g., "auto-archive when tests pass" / "tests 통과하면 알아서 archive 해").
- When implementing, respect the user's document-split guidance (see Step 3 below).
- Always run the tests — do not declare "done" based on reasoning alone.
- **Never modify the body of an archived TESTS.md.** Obsolete marking is done only via 3 frontmatter fields on that archived folder's PLAN.md (`status: obsolete`, `obsoleted_at`, `obsoleted_by`).
- **Never auto-mark on supersede propagation** — always go through Step 9c's AskUserQuestion (default Yes pre-selected).

First, gather context:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/work.sh" $ARGUMENTS
```

Parse the header (`MODE:`, `TARGET_SLUG:`, `PLAN_FILE:`, `TESTS_FILE:`, `GRAPHIFY_SKILL:`, `GRAPH_STATUS:`) and the three content blocks (`=== active promote plans ===`, `=== related documents (from PLAN.md) ===`, `=== external refs (from PLAN.md frontmatter refs:) ===`).

## Protocol

> **Dependency note** — If the helper emits warnings about missing external CLI
> (`gh` / `glab` / `ffmpeg` / etc.) or missing `graphify` skill, suggest running
> `/scv:install-deps` once to get OS-specific install commands. Don't auto-run
> it. graphify install: https://github.com/safishamsi/graphify

### Step 0 — Archive short-circuit

If `MODE: archive`: the helper already moved the folder and wrote `ARCHIVED_AT.md`. Just report the `ARCHIVED:` line and stop. Do not continue with Steps 1+.

### Step 1 — Select target

- If `TARGET_SLUG: (none …)` → use `AskUserQuestion` to ask the user which plan from the list to work on. Re-invoke the helper with the chosen slug.
- If ambiguous (helper exit 2): show the matches, ask user to pick one via `AskUserQuestion`.

### Step 2 — Graph freshness check

Based on `GRAPHIFY_SKILL` + `GRAPH_STATUS`:

| GRAPHIFY_SKILL | GRAPH_STATUS | Action |
|---|---|---|
| `available` | `stale` | Ask user via `AskUserQuestion`: "docs graph is stale — refresh it first via `/scv:promote --graph-only`?" Default: **yes**. If yes, tell user the command (do NOT invoke `/scv:promote` yourself from here — they run it). If no, continue. |
| `available` | `missing` or `built` | Continue. |
| `missing` (skill) | any | Continue. Mention once (one line): "graphify skill not installed — see https://github.com/safishamsi/graphify or run `/scv:install-deps` for the full deps list." Don't repeat on subsequent runs. |

### Step 3 — Load PLAN.md (required)

`Read` the `PLAN_FILE` path emitted by the helper. Summarize `Summary`, `Goals / Non-Goals`, `Steps` to the user in 3–5 bullets so they can confirm scope.

Also surface any **external refs** from the helper's `=== external refs ===` block (grouped by `type`, e.g. `[jira] 2`, `[pr] 1`). One line per type is enough — the user can follow links without Claude reading them.

**Document split judgment** (applied from now on, through implementation):

| Signal | Claude's action |
|---|---|
| User explicit: "split it" / "split into ARCH.md" / "extract into REQUIREMENTS.md" (or any-language equivalent like 분리해 / REQUIREMENTS.md 로 빼줘) | **Always split** — write the new file and trim PLAN.md accordingly. Ask before the actual write. |
| User explicit: "don't split" / "keep it in one file" / "no split" (or 분리 마) | **Do not propose split**. Continue in PLAN.md even if it grows. |
| Neither (default) | Claude judges. If `Approach Overview` > ~50 lines, `Steps` > ~15, or implementation reveals a dense sub-topic (ARCH / REQUIREMENTS / API / MIGRATION / tests) — **propose** split via `AskUserQuestion`. User accepts or declines. |

### Step 4 — Load Related Documents (as needed)

Look at the helper's `=== related documents (from PLAN.md) ===` list.

- If empty → skip.
- If listed: **don't read them all by default** (token guard).
- Read individual entries only when:
  1. The user explicitly requests (e.g., "also read ARCH.md when implementing" / "ARCH.md 도 보고 구현해"), **or**
  2. Claude judges the content of the current step needs that context (e.g., Step says "per API.md contract" — then Read API.md).
- Any file marked `(MISSING)` by the helper → note it in summary; ask user if they want it created.

### Step 5 — Load TESTS.md (required)

`Read` the `TESTS_FILE`. Extract:
- The `## How to run` (or legacy `## 실행 방법`) section — actual test command(s).
- The `## Pass criteria` (or legacy `## 통과 판정`) section — pass/fail rules.

If TESTS.md is missing or the run section is empty / ambiguous → **stop and ask**. Do not guess a test command.

#### Step 5b — Playwright video auto-setup (SCV's standard E2E framework, v0.3+)

After loading TESTS.md, decide whether to set up E2E video recording. **SCV's standard E2E framework is Playwright** — automatic detection, auto video config, and PR auto-attach are guaranteed only for Playwright.

1. Use `Glob` to look for `playwright.config.{ts,js,mjs,cjs}` at project root.
2. **If `playwright.config.*` found**: continue with the Playwright video config flow below.
3. **If `playwright.config.*` not found, but other E2E indicators are present** (any of: `cypress.config.{ts,js,mjs}` exists, or `package.json`'s `dependencies` / `devDependencies` contains `cypress` or `puppeteer`): emit the **non-Playwright notice** (see end of this step) **once**, then proceed to Step 6 without modifying any config.
4. **If neither**: skip this step entirely (non-E2E project — proceed to Step 6).

##### Playwright video config flow (only when `playwright.config.*` found)

`Read` the config file and check for `video:` configuration inside the `use:` block.

If `video:` is **missing** or set to `'off'`:

   ```
   AskUserQuestion (default Yes):
     Question: "Playwright video recording is off. Should SCV turn it on automatically?"
     options:
     [1] "Yes — auto-add video: 'on' (recommended)"
         description:
         "Adds a single `video: 'on'` line into the `use:` block of playwright.config.
          From then on, every Playwright test produces .webm under test-results/, and
          /scv:work Step 9d's PR creation auto-embeds those videos into the PR body
          (via the scv-attachments orphan branch — zero impact on the working branch's
          git history).

          Videos are auto-deleted N days after PR merge (default 3, configurable)."

     [2] "No — proceed without video"
         description:
         "Leaves playwright.config alone. Only screenshots will be attached to the PR."
   ```

If user picks **[1] Yes**: use `Edit` to insert `video: 'on'` into the `use:` block.
   - If `use:` block exists: insert `video: 'on'` line.
   - If no `use:` block: add `use: { video: 'on' },` at top-level config object.
   - Confirm the edit is consistent with file's TypeScript/JavaScript syntax.

If user picks **[2] No**: continue without modifying config.

If `video:` is already `'on'` / `'retain-on-failure'` / `'retry-with-video'`: skip silently (already configured).

This flow runs **once per project** in practice — after first Yes, video config is permanent.

##### Non-Playwright notice (Cypress / Puppeteer / others)

When emitted, print this as a single info block (not an AskUserQuestion — work proceeds normally):

> ⚠ **SCV's standard E2E framework is Playwright.**
>
> This project shows signs of Cypress / Puppeteer / another tool. SCV guarantees automatic detection, auto video config, and PR auto-attach only for Playwright. Other tools still get PR attachment if their `.webm` / `.mp4` outputs land in `test-results/`, but auto video config (Step 5b) does not apply.
>
> Recommended migration to Playwright:
> - Cypress → Playwright: https://playwright.dev/docs/migrating-from-cypress
> - Puppeteer → Playwright: https://playwright.dev/docs/puppeteer
>
> (SCV work continues as normal — this is a notice only.)

### Step 6 — Implement

Follow `PLAN.md` `Steps` in order. For each step:
1. Describe the change to the user briefly (one sentence).
2. Use `Read` / `Edit` / `Write` as needed.
3. After each significant change, surface any document-split proposal per Step 3.

Update `PLAN.md` frontmatter `status:` as you progress:
- `planned` → `in_progress` when you start implementation
- `in_progress` → `testing` when code is complete and you're about to run TESTS

### Step 7 — Run TESTS

Execute the command(s) from the TESTS.md run section via the `Bash` tool. Capture output. Evaluate against pass criteria.

- All scenarios pass + criteria met → proceed to Step 8.
- Any scenario fails → loop back to Step 6 to fix. **Do not archive.** Set frontmatter `status:` back to `in_progress`.

### Step 8 — Report results to the user

Summarize:
- Implementation: what changed (files, key decisions).
- Test results: each scenario pass/fail + overall verdict.
- Plan's `status:` now `testing` (or back to `in_progress` if failures).

### Step 9a — Regression pre-flight (optional)

Condition: All TESTS passed in Step 7 and not in pre-declared archive mode.

`AskUserQuestion`: "Run accumulated regression (entire `scv/archive/`) before archiving? Slugs declared in PLAN's `supersedes:` are auto-skipped."

Options:
- **Yes, run `/scv:regression` now** (default) — invoke the command immediately
- **Skip — just archive** — go straight to Step 9b
- **Let me review first** — pause (stop the command flow)

If Yes:

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/regression.sh --quiet
```

Result handling:
- `FAILED_SLUGS: 0` → one-line "regression green" report, then Step 9b.
- `FAILED_SLUGS: >0` → report failure count + slug list to the user first, then **re-ask whether to proceed to Step 9b**:
  - "Regression failed. Halt archive and triage with `/scv:regression` first" (recommended)
  - "Ignore failures and archive" (risky — only if user explicitly approves)
  - "Hold off on archiving for now"

**Pre-declared mode** (e.g., user said earlier "auto-archive when tests pass" / "tests 통과하면 알아서 archive 해"): pre-flight still runs automatically, but if `FAILED_SLUGS: 0` it proceeds to Step 9b without asking.

### Step 9b — Archive decision

Only if tests fully passed in Step 7 (and Step 9a passed or was skipped):

| User posture | Action |
|---|---|
| Pre-declared (e.g., "auto-archive when tests pass" / "tests 통과하면 알아서 archive 해", spoken earlier in this conversation) | Auto-invoke: `bash ${CLAUDE_PLUGIN_ROOT}/scripts/work.sh <slug> --archive --reason="tests passed"`. Report the ARCHIVED: line. |
| No pre-declaration | Use `AskUserQuestion`: "All tests passed. Archive `<slug>` now?" with options: **Archive now** / **Keep in promote** / **Let me review first**. Proceed per answer. |
| User says no (keep in promote) | Update PLAN.md frontmatter `status: done` but leave the folder in `scv/promote/`. |

After a successful archive, remind the user:
- `scv/archive/<slug>/ARCHIVED_AT.md` has the archive record.
- Future `/scv:status` will no longer flag this plan.

### Step 9c — supersede propagation (new · adopts A's `supersedes` declaration)

Condition: archive **actually happened** in Step 9b, and the just-archived PLAN.md's `supersedes:` array is non-empty.

Procedure:
1. `Read` `scv/archive/<A-slug>/PLAN.md` frontmatter. Parse the `supersedes:` array.
2. For each B-slug, **process sequentially**:
   - Verify `scv/archive/<B-slug>/PLAN.md` exists. If not, warn to stderr and skip.
   - If already `status: obsolete`, skip (avoid double-marking).
   - Otherwise, **one AskUserQuestion** (per slug, default Yes):

**AskUserQuestion template (use as-is)**

```
Question: "The plan you just archived ('<A-slug>') declared '<B-slug>' in its supersedes.
           Mark '<B-slug>' as obsolete?"

Options:
[1] "Yes — mark as obsolete (recommended)"
    description:
    "Records that '<B-slug>' is no longer an actively maintained feature and was replaced
     by the just-archived '<A-slug>'.

     What exactly changes?
     - Only 3 fields are added to scv/archive/<B-slug>/PLAN.md frontmatter:
         status: done → obsolete
         obsoleted_at: <today's date>
         obsoleted_by: <A-slug>
     - TESTS.md, ARCHIVED_AT.md, and other files are never touched (immutable archive principle).

     Why is this needed?
     - /scv:regression will permanently skip '<B-slug>'s TESTS from now on (excluded from
       the regression suite).
     - A year later, even when browsing the archive, the 'why isn't B running anymore?'
       answer remains in PLAN's body, traceable without git history.
     - If status stays 'done', it could be misread as 'completed and still live' — this
       marking clarifies the lifecycle.

     When NOT to pick Yes?
     - If the supersedes declaration was a mistake, pick [2] Skip and remove '<B-slug>'
       from <A-slug>.PLAN.md's supersedes array."

[2] "Skip — runtime skip only"
    description:
    "Don't touch '<B-slug>'s files at all. /scv:regression still reads <A-slug>.supersedes
     and skips '<B-slug>', but '<B-slug>'.status stays 'done', so in archive listings it
     looks like a 'live feature'. Pick this if the supersedes declaration was a mistake or
     you want to decide later."

[3] "Let me review archive/<B-slug>/ first"
    description:
    "Defer this propagation decision. /scv:work does NOT stop here — it continues to the
     next supersede target. You can manually mark this slug later, or re-enter via
     /scv:regression triage."

Default: [1] Yes (pre-selected)
```

Answer handling:
- **[1] Yes**: `Read` → `Edit` `scv/archive/<B-slug>/PLAN.md` frontmatter:
  - `status: done` → `status: obsolete`
  - Add `obsoleted_at: <TODAY>` if missing
  - Add `obsoleted_by: <A-slug>` if missing
  - Don't touch any other field. Never touch TESTS.md, ARCHIVED_AT.md, or any other file.
- **[2] Skip**: Modify nothing. Move to the next slug.
- **[3] Review**: Defer this slug. Move to the next slug.

After processing all supersede targets, summarize to the user:
```
Propagated obsolete marking:
  ✓ <B-slug>    (marked obsolete, obsoleted_by: <A-slug>)
  — <C-slug>    (user chose Skip)
  ? <D-slug>    (user chose Review — not marked)
```

### Step 9d — PR auto-creation (optional, v0.3+)

Condition: archive actually happened in Step 9b.

#### Step 9d-prep — Video retention period (one-time)

When `/scv:work` is creating its first PR and `.env` does not have `SCV_ATTACHMENTS_RETENTION_DAYS`, fire **one** AskUserQuestion (and never again):

```
Question: "How long to keep video attachments after PR merge?
           (Auto-deleted from the scv-attachments orphan branch.)"
options:
[1] "3 days (default · recommended)"
    description:
    "Quick cleanup after merge. Just enough buffer for a brief post-merge review.
     Usually sufficient. Minimum storage accumulation."
[2] "7 days"
    description:
    "One week. Referenceable through the next sprint after merge. Slightly more
     conservative."
[3] "30 days"
    description:
    "One month. Retained through quarterly retros. Video storage accumulates more
     but supports long-term traceability."
[4] "Never — don't delete"
    description:
    "Permanent retention. The orphan branch's storage will keep growing — choose
     this only if you want a long-term archive."
```

After the answer, Claude uses `Edit` to append one line to `.env` (creating `.env` if absent):
```
SCV_ATTACHMENTS_RETENTION_DAYS=<N>   # or 'never'
```

#### Step 9d-main — PR creation AskUserQuestion

**AskUserQuestion** (default Yes):

```
Question: "Open a PR for the just-archived '<slug>' now?"
options:
[1] "Yes — auto-create PR (recommended)"
    description:
    "The following happens automatically:
    - Assemble PR body from key sections of PLAN.md / TESTS.md / ARCHIVED_AT.md
    - Move test-results/ screenshots (PNG/JPG) into .scv-pr-artifacts/<slug>/
      (cleared from test-results/ to keep disk clean). Commit them on the PR branch.
    - Push test-results/ videos (.webm/.mp4) via lib/attachments.sh's git-orphan
      backend onto the scv-attachments orphan branch (zero impact on the PR
      branch's git history). Local video files are deleted right after push.
    - PR body embeds video markdown via GitHub raw URL → inline playback in the
      PR page. Manifest updated.
    - Auto-deletion N days after PR merge (self-amortizing — runs on next
      pr-helper invocation).
    - If the plan has an epic, base branch = epic/<epic-slug> (otherwise main).
      If the epic branch doesn't exist on origin, it's auto-created from origin/main.
    - Push current feature branch + gh pr create + attachments_upload + gh api
      PATCH to replace the placeholder.
    - Print PR URL.

    Prerequisites:
    - Current git branch is a feature branch (not main).
    - gh CLI authenticated (gh auth status).
    - test-results/ screenshots and videos prepared by your test tooling
      (Playwright video: 'on' auto-config recommended — Step 5b).
    - GitHub-only for video attachments (GitLab etc. coming in v0.5)."

[2] "Skip — I'll open the PR manually"
    description:
    "SCV doesn't open a PR. You can create it later via git/gh, or re-enter
     this step by re-invoking /scv:work."
```

**On [1] Yes**:

```
bash ${CLAUDE_PLUGIN_ROOT}/scripts/pr-helper.sh <slug>
```

The helper reads `archive/<slug>/PLAN.md`'s `epic:` / `kind:` to determine the base branch and performs commit + push + gh pr create. The last line of the output should be `PR created: <URL>` — report that URL to the user.

Failure cases:
- Current branch equals the base branch (e.g., invoked on main) → tell the user to switch to a feature branch. SCV does NOT auto-switch (preserves the user's working context).
- gh CLI not authenticated → tell the user to run `gh auth login`.
- No changes to commit (already committed/pushed) → just runs gh pr create.

**On [2] Skip**: terminate quietly. Continue to Step 9e (epic refactor notice).

### Step 9e — Epic completion refactor notice (optional)

Only when the just-archived PLAN has `epic:` and `kind: feature`. Check whether all features of this epic are archived:

```bash
# Glob scv/promote/*/PLAN.md and scv/archive/*/PLAN.md, count epic match + kind=feature
remaining_features_in_promote=$(grep -l "^epic: <epic-slug>$" scv/promote/*/PLAN.md 2>/dev/null | xargs -I{} grep -L "^kind: refactor$" {} 2>/dev/null | wc -l)
existing_refactor=$(grep -l "^epic: <epic-slug>$" scv/{archive,promote}/*/PLAN.md 2>/dev/null | xargs grep -l "^kind: refactor$" 2>/dev/null | wc -l)
```

If both:
- `remaining_features_in_promote == 0` (all features of the epic are archived)
- `existing_refactor == 0` (no refactor PLAN exists yet)

→ One-line user notice + AskUserQuestion:

```
"All features of epic <epic-slug> are archived.
 Per PROMOTE.md §8e, it's time to create the integration refactor PLAN.

 Question: "Create the refactor PLAN scaffold now?"
 options:
 [1] "Yes — create refactor PLAN (recommended)"
     description:
     "Generates scv/promote/<TODAY>-<author>-<epic-slug>-refactor/ with PLAN.md +
      TESTS.md scaffold. PLAN.md has frontmatter pre-set:
        kind: refactor
        epic: <epic-slug>
        status: planned
      Summary section auto-lists every archived feature slug of the epic (any count).
      Fill in cleanup items observed during integration via the user dialogue."

 [2] "Later — next time"
     description:
     "Don't create now. You can create it later via /scv:promote or by hand. The epic
      is shown as 'refactor pending' in /scv:status."
```

**On [1] Yes**: Claude directly creates the folder + PLAN.md + TESTS.md scaffold via `Write`. Auto-include the epic's archived feature slugs in the PLAN.md Summary section.

**On [2] Later**: Terminate quietly.

## Flag semantics

- `<slug>` — required for actual work; optional when you just want to list plans. Partial match supported (helper fuzzy-resolves suffixes).
- `--archive` — Skip implementation; move `promote/<slug>/` → `archive/<slug>/` and write `ARCHIVED_AT.md`. Useful for manually archiving plans whose tests passed outside `/scv:work`.
- `--reason="..."` — Used only with `--archive`; goes into `ARCHIVED_AT.md` body.

## Never

- Archive without tests passing (or without explicit user override).
- Read Related Documents beyond what the step needs.
- Skip the test execution and declare done.
- Silently split or merge documents — always confirm with the user.
