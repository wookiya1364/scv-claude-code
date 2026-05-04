---
name: promote-protocol
version: 1.0.0
status: active
last_updated: 2026-04-20
applies_to: []
owners: ["@team"]
tags: [promote, protocol, process]
standard_version: 1.0.0
merge_policy: overwrite
---

# PROMOTE — Promotion document convention

> **This document is process.** It does not change between projects.
> It defines the full convention for refining material in `scv/raw/` into `scv/promote/<slug>/`, and after implementation moving to `scv/archive/<slug>/`.

---

## 1. One-page summary

```
Drop into scv/raw/ → /scv:promote (Claude refines via dialogue)
                  → scv/promote/<YYYYMMDD>-<author>-<slug>/
                      ├── PLAN.md    (required)
                      ├── TESTS.md   (required)
                      └── free additional files (optional)
                  → /scv:work <slug> (implement + test)
                  → scv/archive/<YYYYMMDD>-<author>-<slug>/ (moved on completion)
```

---

## 1.5. Adoption mode usage (default mode)

If hydrated with `hydrate.sh init .` (default), you're in this mode. Standard docs (DOMAIN, ARCHITECTURE, etc.) seed at `status: N/A` and **INTAKE is not forced**. The promote loop still works:

1. For the **subsystem unit** you'll work on, drop material (meeting notes, specs, external specs) into `scv/raw/`.
2. `/scv:promote` → creates `scv/promote/<YYYYMMDD>-<author>-<slug>/`.
3. State the **scope** of this plan in PLAN.md's `Summary` / `Goals` (e.g., "Payment v2 subsystem only. Logistics / promotions are out of scope").
4. Existing Confluence specs or Jira tickets connect via `refs:` — **no need to rewrite the body**.
5. `/scv:work <slug>` to implement → test → archive.

If you decide to formally document a specific subsystem, lift just that section in `scv/DOMAIN.md` (etc.) by tightening the scope: `N/A → draft → active`. You don't need to fill everything at once.

> **Realistic path for large legacy adoption** — scope in just 1 subsystem (e.g., payment refactor) for a month, confirm value, then expand to other teams / subsystems. Project-wide INTAKE is unrealistic and only causes drift.

---

## 1.6. Fast-path — direct PR without promote (small changes only)

**Not every change needs a promote folder.** Small changes meeting the criteria below may skip the SCV loop and go straight to GitHub PR. Fast-path balances "ceremony cost vs verification value" — we don't want a 5-minute typo fix to require an 18-minute PLAN write-up.

### Fast-path criteria (all must be true)

- [ ] Change has a single simple intent (typo fix / null-guard hotfix / patch-version dep bump / one-paragraph doc tweak)
- [ ] **Touches ≤ 5 lines and stays inside a single function or block** (default — see "Team override" below)
- [ ] No new behavior, API, or feature — preservation of existing behavior is obvious
- [ ] Within scope of existing regression TESTS (so archived TESTS won't break post-merge — reasonably expected)
- [ ] PR description fits in one paragraph (PLAN.md's Goals / Non-Goals / Steps would compress to one line)

If even one of the five is suspect, take the formal promote loop. **The default decision is "formal promote loop"** — fast-path is a deliberate exception for obvious cases.

### Team override — `SCV_FAST_PATH_LINE_THRESHOLD`

The 5-line ceiling is a default, not dogma. Teams shipping mostly to mature codebases can raise it; teams in security-sensitive domains can lower it. Set in the project's `.env`:

```bash
# .env
SCV_FAST_PATH_LINE_THRESHOLD=3   # stricter — only ≤3 lines qualify
# or
SCV_FAST_PATH_LINE_THRESHOLD=10  # looser — ≤10 lines OK if other 4 criteria still hold
```

Locking the threshold per team in `.env` removes the per-PR negotiation ("is this 6-line change really fast-path-able?"). When unset, default is 5. The single-function/block rule is **not** overridable — multi-function changes always take the formal loop regardless of line count.

### Fast-path examples

| ✅ Fast-path OK | ❌ NOT OK — formal promote loop |
|---|---|
| README / code comment typo fix | New feature (even if 1-hour) |
| Patch-version dep bump (security advisory response) | Bug fix that needs spec change ("was this behavior intentional?" — anything needing review) |
| ≤5 line null-guard / off-by-one hotfix in a single function | Refactor (even single-file — rename, helper extraction, signature changes) |
| Linter / formatter auto-cleanup | DB schema change / API compat impact |
| Comment / doc paragraph addition | "Looks small but I'm not sure" change — when in doubt, promote |

### Fast-path PR safety nets (verification is NOT skipped)

Fast-path skips **PLAN/TESTS authoring**, NOT verification. These safety nets stay in place:

1. **GitHub PR review** — Normal code review process. SCV doesn't bypass the PR itself.
2. **`/scv:regression` archived TESTS** — Auto-runs nightly or at the next archive. If fast-path breaks an archived feature, it shows up here → triage flow (regression / obsolete / flaky).
3. **Project's general CI test suite** — pytest / jest / etc. run as usual. If gated on PR merge, that gate still applies.
4. **Git blame / `git log -p`** — Fast-path PRs land in git history, traceable 6 months later when asking "why was this line added?".

So fast-path **reduces ceremony cost**, NOT verification.

### When in doubt, promote

The default principle of this guide is **"when in doubt, formal promote loop"**. Fast-path is for clearly small changes only; if the boundary is fuzzy, even at slightly more cost it's right long-term to take the promote loop. The most dangerous task is the 1-hour task you thought was 5 minutes — that goes through the formal loop.

---

## 2. Folder name convention (absolute rule)

```
<YYYYMMDD>-<author>-<slug>/
```

- **YYYYMMDD** — Plan creation date (ISO date)
- **author** — Author identifier (default: `git config user.name`, lower-case + hyphens)
- **slug** — Topic identifier (kebab-case, 3–5 words)

**Examples**:
- `20260420-sspark-user-auth-refactor/`
- `20260421-kmlee-payment-api-v2/`
- `20260422-team-infra-migration/`

**Why include author by default**: avoids slug collisions across team members. `/scv:promote` automatically prefixes date + author when proposing a slug.

---

## 3. Two required files + free extension

Every promotion folder must contain **PLAN.md and TESTS.md**. Add any others as needed.

```
20260420-sspark-user-auth/
├── PLAN.md                   # required — plan body + frontmatter
├── TESTS.md                  # required — test scenarios + pass criteria
├── FEATURE_ARCHITECTURE.md   # optional — two Mermaid diagrams (see §5b)
├── REQUIREMENTS.md           # optional — detailed requirements (split if large)
├── ARCH.md                   # optional — architecture design (deeper than the two diagrams)
├── MIGRATION.md              # optional — migration strategy
├── notes.md                  # optional — work notes / decision records
├── diagrams/                 # optional — extra diagrams / screenshots
└── attachments/              # optional — external PDFs, references
```

### Recommended structure by size

| Scale | Structure |
|---|---|
| ≤ 1 day | `PLAN.md` + `TESTS.md` only |
| 2 ~ 5 days | Above + one of `ARCH.md` or `REQUIREMENTS.md` |
| Multi-week | Free further split as needed (ARCH, REQUIREMENTS, API, MIGRATION, assets/, etc.) |

Start small → when PLAN.md's Approach Overview exceeds 50 lines, `/scv:work` will auto-suggest "split into ARCH.md?".

---

## 4. PLAN.md template (copy and use)

```markdown
---
title: User authentication flow refactor
slug: 20260420-sspark-user-auth-refactor
author: sspark
created_at: 2026-04-20
status: planned          # planned | in_progress | testing | done
tags: [auth, security]
raw_sources:
  - scv/raw/2026-04-18-auth-review/notes.md
refs:
  - type: jira
    id: PAY-1234
  - type: jira
    id: PAY-1235
  - type: confluence
    url: https://confluence.example.com/x/design-v2
  - type: pr
    url: https://github.com/org/repo/pull/567
# Group multiple split features into the same epic (count is content-driven; see §8d)
epic: 20260424-payment-overhaul
kind: feature                          # feature | refactor | retirement (default: feature)
# Slugs / scenarios this plan retires from regression (see §8b)
supersedes:
  - 20260115-sspark-user-auth-v1      # Replaces all of v1 → v1's TESTS skipped permanently in regression
supersedes_scenarios:
  - 20251201-kmlee-legacy-login:T3    # Only T3 of legacy-login is retired; other T's still run
---

# {{title}}

## Summary

1–3 sentences summarizing "what & why".

## Goals / Non-Goals

- **Goals**
  - ...
- **Non-Goals**
  - ...

## Approach Overview

5–15 lines of full design summary. If this section exceeds 50 lines → split into `ARCH.md` recommended.

## Steps

1. ...
2. ...
3. ...

## Related Documents

<!-- For larger plans, link supporting files here. Keep the section as an empty heading if none. -->
<!-- Examples:
- [`REQUIREMENTS.md`](./REQUIREMENTS.md) — detailed requirements
- [`ARCH.md`](./ARCH.md) — architecture design
- [`MIGRATION.md`](./MIGRATION.md) — migration strategy
-->

## Risks / Open Questions

- ...

## Links

- Raw originals: `scv/raw/...` (consumed by readpath.json)
- Related PR: (if any)
```

### Frontmatter fields

| Field | Required | Description |
|---|:-:|---|
| `title` | ✓ | Human-readable title (one line) |
| `slug` | ✓ | Must match folder name exactly |
| `author` | ✓ | Author (`git config user.name` based) |
| `created_at` | ✓ | ISO date |
| `status` | ✓ | `planned` / `in_progress` / `testing` / `done` |
| `tags` | ✓ | Keyword array (search/filter) |
| `raw_sources` | — | Array of related raw file paths (for traceability) |
| `refs` | — | Array of external references (Jira / Linear / Confluence / PR, etc.). See spec below |
| `supersedes` | — | Array of **past slugs** this plan retires (supersedes). `/scv:regression` permanently skips those archived TESTS. See §8b |
| `supersedes_scenarios` | — | **Scenario-level** retirement. Array of `<slug>:T<n>` strings, e.g., `["20260115-sspark-auth-v1:T2"]` |
| `epic` | — | When splitting a large user request into multiple features, group them under the same epic slug (count is content-driven — Claude proposes + user adjusts). `/scv:status` shows epic progress; `/scv:work`'s PR auto-creation uses the epic branch as base. See §8d |
| `kind` | — | `feature` (default) / `refactor` (epic-closing integration cleanup) / `retirement` (pure removal — §8c). Used by Claude for epic flow / refactor guidance |

### `refs:` spec — vendor-neutral external references

Instead of hard-coding vendor-specific frontmatter keys, use a **typed array** that scales:

```yaml
refs:
  - type: jira          # Free-form type string (jira / linear / asana / notion / confluence / pr / slack-thread / ...)
    id: PAY-1234        # Ticket ID — `.env`'s <TYPE>_BASE_URL infers URL
  - type: jira
    id: PAY-1235        # Multiple of the same type are fine
  - type: confluence
    url: https://confluence.example.com/x/design-v2  # Direct URL also works
  - type: pr
    url: https://github.com/org/repo/pull/567
```

**Conventions:**

- **No constraints between array elements** — multiple of the same `type`, any order.
- Each element can have **`id` only, `url` only, or both**.
  - `id` only with no `url` → infer URL by combining with `.env`'s `<TYPE>_BASE_URL` (if unset, just show ID).
  - `url` present → use as-is.
- `type` is free-form. SCV provides rendering hints for known types; unknown types pass through as plain links.
- **On archive, `refs:` is preserved verbatim in `ARCHIVED_AT.md`** (audit trail).

**`.env` base URL configuration example:**

```bash
JIRA_BASE_URL=https://company.atlassian.net
LINEAR_BASE_URL=https://linear.app/company
CONFLUENCE_BASE_URL=https://confluence.example.com
```

`/scv:work` output groups by `type` for human readability:

```
[jira] 2 tickets
  · PAY-1234 → https://company.atlassian.net/browse/PAY-1234
  · PAY-1235 → https://company.atlassian.net/browse/PAY-1235
[confluence] 1 doc
  · https://confluence.example.com/x/design-v2
[pr] 1 PR
  · #567 → https://github.com/org/repo/pull/567
```

---

## 5. TESTS.md template

```markdown
# Test Plan — {{title}}

## Overview

One-paragraph summary: what behavior we verify, how, and why.

## Test scenarios

### T1. Basic login success

- **Setup**: 1 registered user account, valid password
- **Run**: `POST /api/login` with valid credentials
- **Expected**: 200 OK + JWT token returned
- **Pass criterion**: Token signature valid, exp within 1 hour

### T2. 401 on wrong password

- **Setup**: registered account
- **Run**: login with wrong password
- **Expected**: 401 Unauthorized
- **Pass criterion**: No token returned, fixed error message string

## How to run

```bash
npm run test:auth
```

## Pass criteria

- All scenarios meet their pass criteria
- Code coverage ≥ 80%
- E2E (`npm run test:e2e -- auth`) all pass

## Related Documents

<!-- For tests split out further:
- [`tests/e2e-scenarios.md`](./tests/e2e-scenarios.md) — E2E scenario detail
- [`tests/load.md`](./tests/load.md) — Load tests
-->
```

### TESTS.md minimum requirements (for pass judgment)

- [ ] **How to run** is written as a clear command (`bash` / `npm` / `pnpm` / etc.)
- [ ] **Pass criterion** for each scenario is stated as an observable form
- [ ] **Pass criteria** block contains the "overall done declaration condition"

If any of those is ambiguous, `/scv:work` will ask the user before starting implementation.

### Auto video evidence attachment (v0.3+)

If Playwright (`video: 'on'`) or an equivalent tool produces .webm/.mp4 under `test-results/`, `/scv:work` Step 9d's PR creation **auto-embeds** them inline into the PR body. Videos are pushed to a separate `scv-attachments` orphan branch (so the working branch's git history stays clean), and auto-deleted N days after PR merge. See `TESTING.md §3.3` for details.

### Authoring guide for regression re-runs

TESTS.md is used both for `/scv:work` initial verification AND, **after archive, by `/scv:regression` for accumulated regression**. Two authoring patterns:

1. **Single command** (default) — One `## How to run` block runs all scenarios.
   ```bash
   npm run test:auth        # Verifies T1~T5 collectively
   ```
2. **Scenario dispatch** (recommended for partial-skip support) — Filter via `T=$T_FILTER` env var.
   ```bash
   if [[ "${T_FILTER:-all}" == "all" ]]; then
     npm run test:auth
   else
     npm run test:auth -- --grep "$T_FILTER"
   fi
   ```
   With this pattern, a follow-up plan can `supersedes_scenarios: ["<slug>:T2"]` to skip just T2 while keeping the rest in regression. Without dispatch, `/scv:regression` can't support scenario-level skip and falls back (with a warning) to skipping the whole slug.

---

## 5b. FEATURE_ARCHITECTURE.md (optional, prompted on every promote)

After PLAN.md / TESTS.md, `/scv:promote` asks **per folder** whether to also write `FEATURE_ARCHITECTURE.md` — two Mermaid diagrams that describe the feature's design before implementation.

**Why two diagrams (minimum):**

| Diagram | Purpose |
|---|---|
| 1. Component data flow | How this feature's components combine, what data / parameters flow between them. Helps the implementer (you or a teammate or `/scv:work`) understand the design before touching code. |
| 2. Position in whole architecture | Where this feature sits in the system at a coarse grain. Helps stakeholders see the change scope at a glance and reduces "what is this connected to?" review questions. |

The document may include more diagrams (sequence, state, deployment) when the feature genuinely needs them. Two is the floor, not the ceiling.

**Why this is optional:**

Trivial changes (typo fix, single-line null guard, patch dep bump) get no value from a diagram. The default `/scv:promote` flow asks every time so the user picks per folder. Pick "skip" once for trivial work, "yes" once for non-trivial work — there is no flag to remember.

**Diagram 2's data source:**

```
scv/ARCHITECTURE.md status?
  ├─ active or draft → use it as the layout reference
  └─ N/A → check graphify
      ├─ skill installed + graph fresh → use .graphify/docs/graphify-out/
      ├─ skill installed + graph stale/missing → ask user (run graphify? skip? other?)
      └─ skill missing → ask user (skip? other?)
```

`/scv:promote` decides this branching automatically. The user only sees the resulting `AskUserQuestion` when there is a real decision to make (graphify run-or-skip when ARCHITECTURE.md is `N/A`).

**File location and frontmatter:**

```
scv/promote/<YYYYMMDD>-<author>-<slug>/
├── PLAN.md                       # required
├── TESTS.md                      # required
└── FEATURE_ARCHITECTURE.md       # optional — generated when user opts in
```

```yaml
---
title: <same as PLAN.md>
slug: <same as folder>
created_at: <ISO date>
status: planned
---
```

**Body skeleton:**

```markdown
# Architecture — <title>

> Two-diagram view of this feature. Review and edit before `/scv:work`.

## 1. Component data flow

```mermaid
flowchart LR
  ...
```

## 2. Position in whole architecture

> Source: <ARCHITECTURE.md | graphify graph (built YYYY-MM-DD) | skipped>

```mermaid
flowchart TB
  ...
  classDef new fill:#FFE082,stroke:#F57C00,stroke-width:2px
```
```

**Convention:**

- New components introduced by this feature are highlighted with the `new` class (yellow fill, orange stroke).
- The "Source:" line in section 2 is mandatory when section 2 is present — it makes the diagram's accuracy basis auditable.
- If diagram 2 is skipped (graphify missing AND ARCHITECTURE.md `N/A`), section 2 is replaced by a one-line note pointing at how to enable it (lift ARCHITECTURE.md or run `/graphify`).
- LLM-generated Mermaid may have syntax errors or wrong labels. Treat the file like PLAN.md / TESTS.md — review and edit before `/scv:work`.
- The file is **not enforced** by `/scv:work` or `/scv:regression`. Its value is human comprehension, not gating.

---

## 6. Related Documents convention

- Both PLAN.md and TESTS.md must include a `## Related Documents` section, **even if empty**.
- Links are **relative paths** (within the same folder): `[ARCH.md](./ARCH.md) — one-line description`.
- `/scv:work` does NOT load files outside this section by default (token guard).
- The user's explicit instruction (e.g., "also read ARCH.md when implementing") triggers extra loading.

### When to split (Claude's judgment criteria)

| Signal | Suggestion |
|---|---|
| Approach Overview > 50 lines | → `ARCH.md` |
| Requirements > 20 bullets | → `REQUIREMENTS.md` |
| API spec > 10 endpoints | → `API.md` |
| Migration steps > 5 | → `MIGRATION.md` |
| Test scenarios > 15 | → split under `tests/` |

If the user explicitly says **"split it"**, ignore the criteria and split. If **"don't split"**, Claude stops proposing splits.

---

## 7. Responsibility split between `/scv:promote` and `/scv:work`

| Step | Command | Responsibility |
|---|---|---|
| 1. Refine raw | `/scv:promote` | Confirm slug/title via dialogue → create folder + PLAN + TESTS scaffold → update `scv/readpath.json` |
| 2. Implement / verify | `/scv:work <slug>` | Read PLAN + TESTS, implement, run TESTS, report result, ask about archive |
| 3. Archive | `/scv:work` or manual | On tests pass + user approval: move `promote/<slug>/` → `archive/<slug>/` + create `ARCHIVED_AT.md` |

---

## 8. Archive convention

Completed plans must move to `scv/archive/` (**token efficiency** — `/scv:work` reads only active plans).

```
scv/archive/
└── 20260420-sspark-user-auth/
    ├── PLAN.md
    ├── TESTS.md
    ├── REQUIREMENTS.md        # (any free-extension files preserved verbatim)
    └── ARCHIVED_AT.md          # ⭐ auto-generated on archive
```

### ARCHIVED_AT.md (auto-generated)

```markdown
---
archived_at: 2026-04-25
archived_by: sspark
reason: tests passed
---

# Archive record

This plan was archived on 2026-04-25.

## Reason

- All TESTS scenarios passed
```

`reason` can be passed via `/scv:work <slug> --archive --reason="..."` argument; if omitted, defaults to `tests passed`. The body's reason block is also filled with the `--reason` value (default "All TESTS scenarios passed").

### Archive move decision

| Situation | Action |
|---|---|
| Tests passed + user explicit ("archive it") | Auto mv |
| Tests passed + user pre-declared allow ("auto-archive when tests pass") | Auto mv + report |
| Tests passed + no user direction | Claude asks "archive now?" and waits for answer |
| Tests failed | Archive forbidden, return to fix loop |

---

## 8b. Obsolete convention (permanently exclude from regression)

An archived plan's TESTS.md **must never be modified**. Instead, declare "this feature need not run anymore" via 3 paths:

| Path | Mechanism | When to use |
|---|---|---|
| **Pre-declaration** | New PLAN.md frontmatter has `supersedes: [<old-slug>, ...]` or `supersedes_scenarios: ["<slug>:T<n>", ...]` | When you know what you're replacing at authoring time |
| **Auto-propagation** | When A is archived via `/scv:work`, Claude fires `AskUserQuestion` (default Yes) "mark B as obsolete?" — on approval, modifies B's PLAN.md frontmatter only | Default path triggered when supersedes is declared |
| **Runtime triage** | On `/scv:regression` failure, fire 3-way `AskUserQuestion`: regression (fix code) / obsolete (mark now) / flaky (retry) | When supersede declaration was missed, or when env changes force deprecation |

### What `obsolete` means — terminology

- **Meaning**: "The feature this plan represents is no longer in operation. Permanently excluded from the regression suite." It was either replaced by another plan (A) (`obsoleted_by: <A-slug>`) or removed without a successor (`obsoleted_by: manual`).
- **Difference from `done`**: `done` = "implementation finished, **live** feature"; `obsolete` = "once existed, but no longer does".
- **Effect on `/scv:regression`**: Slugs with `status: obsolete` are excluded from execution by default (include with `--include-obsolete` for audit purposes).
- **Why files remain in archive**: historical record + audit trail. Even after marking obsolete, the folder, TESTS.md, and ARCHIVED_AT.md stay verbatim.

### Marking spec (common to all 3 paths)

In archived `scv/archive/<slug>/PLAN.md` frontmatter, **only 3 fields** are added:

```yaml
---
# Existing fields (preserved as-is)
status: obsolete              # done → obsolete (overwrite)
obsoleted_at: 2026-04-25
obsoleted_by: 20260425-sspark-user-auth-v2   # Auto-prop: replacer slug. Runtime triage: 'manual'
---
```

TESTS.md / ARCHIVED_AT.md / other files are **never modified** (immutable archive principle). `/scv:regression` reads these 3 fields at runtime to skip the slug.

---

## 8c. Retirement-only plan pattern (pure removal without successor)

When you're **just removing an existing feature** without a new one — express via the existing promote/archive loop without a new command:

```yaml
# scv/promote/20260424-sspark-retire-payment-v1/PLAN.md
---
title: Retire payment-v1 endpoints
slug: 20260424-sspark-retire-payment-v1
author: sspark
created_at: 2026-04-24
status: planned
kind: retirement                       # NOT feature, but retirement
tags: [retirement]
supersedes:
  - 20240101-kmlee-payment-v1
---

## Summary
Remove payment-v1 (`/api/v1/pay/*`) endpoints and return 410 Gone.
Clients have completed migration to payment-v2.

## Steps
1. Delete /api/v1/pay/* route handlers
2. Add catch-all returning 410 Gone
3. Monitor access logs for residual calls 24h post-deploy
```

**TESTS.md** verifies "removed":

```markdown
## How to run
```bash
curl -sf -o /dev/null -w "%{http_code}" "$API/api/v1/pay/charge" | grep -q 410
```

## Pass criteria
- All /api/v1/pay/* calls return 410 Gone
```

When `/scv:work` archives this retirement plan, Step 9c will guide marking `payment-v1` as obsolete. No new command needed.

---

## 8d. Epic branch strategy (when a large request is split into multiple features)

Receiving a user's large request in a single promote folder produces **chaos and abrupt change**. SCV analyzes raw material in the `/scv:promote` step and proposes a split when "this is sized for multiple features" (auto-split forbidden — always confirm with user).

**Split count is not fixed.** Claude proposes an appropriate count (e.g., 2, 4, 8) and candidate slugs based on the actual content / topic diversity of the raw, and the user does the final adjustment. The §8e example below is split into 7, but **that's just one example, not a recommended standard**.

Split features are grouped under the same **`epic: <epic-slug>`** frontmatter.

### Working flow

```
Large request (raw input)
   │
   ▼  /scv:promote proposes split → user approves
Multiple promote folders (count matches raw content), all sharing the same epic
   │
   ▼  /scv:work <slug> for each
feature 1 → archive → PR (base = epic/<epic-slug>)
feature 2 → archive → PR (base = epic/<epic-slug>)
...
feature N → archive → PR (base = epic/<epic-slug>)
   │
   ▼  (When all features in epic are archived, SCV auto-prompts)
"All features of epic <slug> done. Create the integration refactor PLAN?"
   │
   ▼  Refactor PLAN scaffold (kind: refactor) → /scv:work
   │
   ▼  archive → PR (base = epic/<epic-slug>)
   │
   ▼  User merges epic/<epic-slug> → main
```

### Key conventions

- **PR base branch is `epic/<epic-slug>`, not `main`.** All PRs of the epic (any count) gather into one integration branch. Direct main/stg/dev forbidden — prevents the "good in unit branches but not great when combined" failure mode.
- The `epic/<epic-slug>` branch is auto-created on the first feature's PR (`gh api` or `git push origin main:epic/<slug>`). Subsequent PRs use this branch as base.
- The **last item of the epic is always a refactor PLAN** (`kind: refactor`). It's the cleanup / dedup / naming-unification phase after integrating all units. Only when this is archived is the epic considered complete.
- The refactor PLAN's TESTS usually consists of "existing regression still green" + "any new integration scenarios (if any)".

### `/scv:status` epic progress

```
[epics]
  epic 20260424-payment-overhaul: 4/7 archived, 2 in promote, refactor pending
  epic 20260415-search-revamp:    7/7 archived + refactor done → ready to merge
```

### When the user manually epic-groups

Even if `/scv:promote` didn't propose a split, the user can explicitly say "these promotes share an epic" — then add `epic: <slug>` to each PLAN.md frontmatter directly. From then on, SCV recognizes them as an epic.

---

## 8e. Refactor PLAN pattern

After every feature in an epic is archived, you **must** create a refactor PLAN at the end (epic completion condition).

```yaml
# scv/promote/20260430-sspark-payment-overhaul-refactor/PLAN.md
---
title: Payment overhaul — integration refactor
slug: 20260430-sspark-payment-overhaul-refactor
author: sspark
created_at: 2026-04-30
status: planned
kind: refactor                          # Key — NOT a feature
epic: 20260424-payment-overhaul         # Last item of the same epic
tags: [refactor, integration]
---

## Summary

Cleanup phase after integrating all features of epic `payment-overhaul`
(in this example: auth-v2, charge-flow, refund-flow, webhook-relay,
audit-log, settlement-batch, partner-callback — N items; actual count
varies per epic). Each unit PR was OK in isolation, but post-integration
these items surfaced.

## Steps

1. Consolidate duplicate helpers across features (`utils/payment.ts`)
2. Naming consistency (`charge_id` vs `paymentId` unified)
3. Extract a shared error-code enum
4. Fix one race condition discovered during integration
5. Integration regression run (`/scv:regression --include-promote`)

## Related Documents

<!-- All 7 epic feature PLAN.md files can be referenced -->
```

**TESTS.md** is usually simple — "existing regression + 1–2 integration scenarios":

```markdown
## How to run
\`\`\`bash
bash $CLAUDE_PLUGIN_ROOT/scripts/regression.sh --tag payment
npm run test:integration -- payment
\`\`\`
```

The epic is considered "done" only when this refactor is archived. After archive, the user merges the `epic/<slug>` branch into main.

---

## 9. frontmatter `status` transitions

```
planned → in_progress → testing → done → obsolete
              ↑                      │       ↑
              └──────────────────────┘       │  (new plan's supersedes or manual triage)
           (revert on test failure)
```

- `/scv:work` start → `planned` → `in_progress`.
- Right before completing implementation → `testing`.
- All TESTS pass + archive move → `done` (note: PLAN.md is now in archive).
- `done → obsolete` transition: 3 paths in §8b (auto-propagation / pre-declaration + auto / runtime triage). NOT transitioned from `in_progress` / `testing` (incomplete plans don't have an archive).

---

## 10. Related modules

<!-- MODULES:AUTO START applies_to=promote -->
<!-- MODULES:AUTO END -->
