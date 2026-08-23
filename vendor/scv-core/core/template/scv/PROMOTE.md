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
Drop into scv/raw/ → action:promote (refines via dialogue)
                  → scv/promote/<YYYYMMDD>-<author>-<slug>/
                      ├── PLAN.md    (required)
                      ├── TESTS.md   (required)
                      └── free additional files (optional)
                  → action:work <slug> (implement + test)
                  → scv/archive/<YYYYMMDD>-<author>-<slug>/ (moved on completion)
```

---

## 1.4. Idea-first entry — `action:help "..."` (v0.9.0+, no raw needed)

**You don't need files in `scv/raw/` to start.** If you have an idea but no concrete materials yet:

```
action:help "I want to add a refund button to checkout"
```

This enters **conversation mode** — SCV refines your idea with you (asking goal / scope / acceptance questions), persists every turn to `scv/conversations/<timestamp>-<slug>.md` (committed, redaction-filtered — v0.22.0+), and offers to draft `PLAN.md + TESTS.md` when there's enough information. You can:

- **Quit anytime** — the conversation file is saved turn-by-turn. Run `action:help "<continue idea>"` later to resume.
- **Promote without `scv/raw/`** — choice [1] in the conversation's "ready?" prompt creates the plan directly. Conversation stays in `scv/conversations/` (committed).
- **Promote with team traceability** — choice [2] also copies the conversation to `scv/raw/<YYYYMMDD>-<author>-<slug>.md` (committable). Pick this when teammates value the raw-thinking history.

If you already have files in `scv/raw/`, the classic flow (§1.5 below) still works — `action:help "..."` is the *additional* entry, not a replacement.

---

## 1.5. Everyday usage (single path)

Hydrate seeds only the workflow files — there is no scaffolding to fill before the promote loop works:

1. For the **subsystem unit** you'll work on, drop material (meeting notes, specs, external specs) into `scv/raw/`.
2. `action:promote` → creates `scv/promote/<YYYYMMDD>-<author>-<slug>/`.
3. State the **scope** of this plan in PLAN.md's `Summary` / `Goals` (e.g., "Payment v2 subsystem only. Logistics / promotions are out of scope").
4. Existing Confluence specs or Jira tickets connect via `refs:` — **no need to rewrite the body**.
5. `action:work <slug>` to implement → test → archive.

> **Realistic path for large legacy adoption** — scope in just 1 subsystem (e.g., payment refactor) for a month, confirm value, then expand to other teams / subsystems. Facts the model can derive from the codebase need no pre-documentation; decisions worth keeping belong in version-controlled team notes (e.g. `DECISIONS.md` / a journal).

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

### Declare it first — `action:work --fast "<intent>"`

Before making a fast-path change, run:

```bash
action:work --fast "<one line: what you are changing and why it qualifies>"
```

It writes nothing. It prints the five criteria and the team's current line ceiling so the exception is checked rather than assumed, and it records that this session took the fast-path deliberately instead of skipping SCV by accident. **A fast-path change without this declaration is not a fast-path change — it is an undeclared edit**, and the workspace guard treats it as one.

This is the whole difference between the sanctioned exception and the failure mode it resembles: both produce a small commit with no promote folder, and only the declaration distinguishes them.

### Team override — `SCV_FAST_PATH_LINE_THRESHOLD`

The 5-line ceiling is a default, not dogma. Teams shipping mostly to mature codebases can raise it; teams in security-sensitive domains can lower it. Set in `scv/scv_settings.json`:

```bash
// scv/scv_settings.json
SCV_FAST_PATH_LINE_THRESHOLD=3   # stricter — only ≤3 lines qualify
# or
SCV_FAST_PATH_LINE_THRESHOLD=10  # looser — ≤10 lines OK if other 4 criteria still hold
```

Locking the threshold per team in the settings file removes the per-PR negotiation ("is this 6-line change really fast-path-able?"). When unset, default is 5. The single-function/block rule is **not** overridable — multi-function changes always take the formal loop regardless of line count.

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
2. **`action:regression` archived TESTS** — Auto-runs nightly or at the next archive. If fast-path breaks an archived feature, it shows up here → triage flow (regression / obsolete / flaky).
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

**Why include author by default**: avoids slug collisions across team members. `action:promote` automatically prefixes date + author when proposing a slug.

---

## 2.5. 순수부와 효과부 — 기능을 쪼개는 규칙

기능은 **순수함수와 파이프의 조합**으로 만든다. 파일을 만지고 명령을 실행하는 일은
바깥의 얇은 층이 맡는다. 계약 전문은 `core/contracts/purity.md`.

세 가지가 한 뿌리에서 나온다.

1. **변경의 영향을 독립적으로 판단할 수 있다.** 함수가 입력만 보고 출력만 내면,
   고쳤을 때 무엇이 달라지는지 그 함수만 보면 된다.
2. **작업 단위가 작아진다.** 한 번에 만들 것이 "문자열 넷 → 문자열 하나" 면
   설계할 것이 거의 없다.
3. **완료를 사람이나 모델이 판정하지 않는다.** 고정 입력에 고정 출력이면 테스트가
   결정적이다. "잘 된 것 같다" 가 낄 자리가 없다.

**목표는 판단을 없애는 것이 아니라, 판단을 검증에서 빼는 것이다.** 무엇을 어떻게
쪼갤지는 여전히 사람이나 모델이 정한다. 그 결과가 맞는지는 기계가 본다.

### 계획에 무엇을 적나

`PLAN.md` 는 **어떤 함수가 어느 층인지** 밝힌다. 이름·층·입출력을 한 줄씩이면 된다.

```
settings_resolve      @pure           네 후보 → 하나          우선순위가 여기에만 있다
settings_lookup_json  @deterministic  JSON 텍스트 + 키 → 값   디스크를 안 만진다
settings_get          효과            파일을 읽어 위 둘에 넘긴다
```

코드에는 함수 바로 위에 표식을 적는다 — `# @pure` 또는 `# @deterministic`.
`core/scripts/check-purity.sh` 가 그것을 찾아 검사한다.

### 테스트에 무엇을 넣나

- **순수부의 전수 검사.** 입력 조합이 유한하면 표본이 아니라 전부를 본다.
  조합이 열여섯 가지면 열여섯 가지를 다 본다.
- **반복 가능성.** 같은 입력을 여러 번 넣어 같은 출력이 나오는지. 이것이 깨지면
  나머지 검사가 전부 의미를 잃는다.
- **순수성 검사.** `bash core/scripts/check-purity.sh` 가 통과하는지.
- **판정은 문자열 비교.** `OK [T1] 16/16` 처럼 찍히거나 안 찍히거나여야 한다.

### 효과층에도 지킬 것이 있다

- **비결정성을 주입받는다.** 시각과 무작위는 함수 안에서 읽지 말고 밖에서 받는다.
- **실패해도 죽지 않는다.** 없거나 깨져 있으면 기본값으로 계속 간다.
- **조용히 실패하지 않는다.** 못 한 일이 있으면 무엇이 왜 안 됐는지 말한다.
  다만 정상일 때는 아무 말도 하지 않는다 — 매번 떠들면 금방 무시하게 된다.

### 이 규칙이 적용되지 않는 곳

문서만 바꾸는 계획, 설정값 하나 바꾸는 계획에는 순수부가 없을 수 있다. 그때는
계획에 그렇게 적으면 된다 — 없는 것을 지어내지 않는다.

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

Start small → when PLAN.md's Approach Overview exceeds 50 lines, `action:work` will auto-suggest "split into ARCH.md?".

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
# Optional — file-path globs this plan is allowed to touch (used by action:codegen as a guard).
# If omitted, the natural scope from PLAN.md Suggested path (legacy: Steps) applies (current action:work behavior).
scope:
  - "src/auth/**"
  - "tests/auth/**"
# Optional — existing behaviors this plan must NOT break (used by action:codegen as a self-check).
# Capture only the invariants that are easy to violate during a focused change (T5 logic-skip).
invariants:
  - "기존 비밀번호 정책 (8자 이상, 특수문자 1개) 유지"
  - "session token 저장 위치 변경 금지"
# Optional (v0.22.0+) — independent Suggested-path step groups that MAY run in parallel.
# Each inner array lists step numbers with no dependency on each other; groups run in
# declaration order. Hosts without subagent/workflow support ignore this entirely.
parallel_groups: [[1, 2], [3]]
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

## Guardrails

What must NOT be done: untouchable areas, forbidden approaches, and the invariants
to protect (cross-reference frontmatter `invariants:` — restate them here in prose
when they need context or scope).

- ...

## Exit criteria

When is this plan DONE beyond "TESTS pass"? Higher-level, observable end conditions
("what being true means we can stop").

- All TESTS.md scenarios pass
- ...

## Suggested path

The path is a suggestion — Guardrails and Exit criteria are the contract
(경로는 제안, Guardrails/Exit criteria 가 계약). The implementing model may follow
a better path when it finds one. (Legacy PLANs titled `## Steps` remain valid —
`action:work` / `action:regression` process both forms.)

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
| `supersedes` | — | Array of **past slugs** this plan retires (supersedes). `action:regression` permanently skips those archived TESTS. See §8b |
| `supersedes_scenarios` | — | **Scenario-level** retirement. Array of `<slug>:T<n>` strings, e.g., `["20260115-sspark-auth-v1:T2"]` |
| `epic` | — | When splitting a large user request into multiple features, group them under the same epic slug (count is content-driven — SCV proposes + user adjusts). `action:status` shows epic progress; `action:work`'s PR auto-creation uses the epic branch as base. See §8d |
| `kind` | — | `feature` (default) / `refactor` (epic-closing integration cleanup) / `retirement` (pure removal — §8c). Used by SCV for epic flow / refactor guidance |
| `lang` | — | (v0.7.3+) The resolved language for this promote's content + diagrams + commit/PR text. Set by `action:promote` Step 0 — auto-resolved from `settings.json language` and `scv/scv_settings.json SCV_LANG`, or via user confirmation when those mismatch. Read by `action:work` Step 9d and `pr-helper.sh` for full localization (PR title, body labels like `## Summary` / `## 요약` / `## 概要`, footer `🗂 Archived` / `🗂 보관됨` / `🗂 アーカイブ済み`). Values: `english` / `korean` / `japanese` / free-form. Empty / unknown → English fallback. |
| `scope` | — | (v0.11.0+) Optional file-path glob array this plan is allowed to touch. Used by `action:codegen` Step 7 as a guard — Edit/Write outside these globs emits a warning (does not block). If omitted, the natural scope from PLAN.md Suggested path (legacy: Steps) applies (current `action:work` behavior, unchanged). Example: `["src/auth/**", "tests/auth/**"]`. |
| `invariants` | — | (v0.11.0+) Optional string array of *existing behaviors this plan must NOT break*. Used by `action:codegen` Step 7 as a per-iteration self-check (LLM re-reads each item after every Green iteration; user confirmation if unsure). Targets T5 logic-skip — the cheat pattern where a focused change silently omits an unrelated invariant. Capture only what's easy to violate; not a general regression list. Example: `["기존 결제 한도 체크 유지", "음수 환불 금지"]`. `action:work` does not enforce this field. |
| `parallel_groups` | — | (v0.22.0+) Optional array of arrays of `## Suggested path` step numbers — each inner array is a group of mutually independent steps a subagent-capable host MAY run concurrently (groups run in declaration order; each TESTS scenario is still verified independently — see `action:work` Step 5d, `action:regression` allows the analogous slug-level fan-out). Absent field, or a host without parallel capability → behavior identical to sequential execution. Example: `[[1, 2], [3]]`. |

### `refs:` spec — vendor-neutral external references

Instead of hard-coding vendor-specific frontmatter keys, use a **typed array** that scales:

```yaml
refs:
  - type: jira          # Free-form type string (jira / linear / asana / notion / confluence / pr / slack-thread / ...)
    id: PAY-1234        # Ticket ID — the settings file's <TYPE>_BASE_URL infers URL
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
  - `id` only with no `url` → infer URL by combining with the settings file's `<TYPE>_BASE_URL` (if unset, just show ID).
  - `url` present → use as-is.
- `type` is free-form. SCV provides rendering hints for known types; unknown types pass through as plain links.
- **On archive, `refs:` is preserved verbatim in `ARCHIVED_AT.md`** (audit trail).

**Base URL configuration example:**

```bash
JIRA_BASE_URL=https://company.atlassian.net
LINEAR_BASE_URL=https://linear.app/company
CONFLUENCE_BASE_URL=https://confluence.example.com
```

`action:work` output groups by `type` for human readability:

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

## 4.5. `scv/archive/INDEX.yaml` — frontmatter-only index (v0.11.0+, auto-managed)

`action:work --archive` regenerates `scv/archive/INDEX.yaml` on every archive — a flat YAML index of every archived plan's frontmatter scalars (`slug`, `title`, `kind`, `status`, `epic`, `obsoleted_by`). PLAN.md bodies are not read for this file.

**Purpose**: fast routing without scanning every archived PLAN.md.
- `action:regression` can consult INDEX for the supersede skip graph (`status: obsolete` entries) before opening any PLAN body.
- `action:help` archive search (Mode B') can do a first-pass filter on `tags` / `kind` / `title` via INDEX, opening PLAN bodies only for matches.

**Rules**:
- Auto-managed — never edit manually. `action:work --archive` overwrites it.
- Committable — INDEX moves with the archive folders.
- May lag by *one archive cycle* if a frontmatter field is edited outside `action:work` (e.g., obsolete propagation Step 9c). Re-running any `action:work --archive` (or a future `--regen-index` flag) refreshes it.

Schema (example):

```yaml
generated_at: 2026-05-18T12:34:56Z
archives:
  - slug: 20260420-sspark-user-auth-refactor
    title: "User authentication flow refactor"
    kind: feature
    status: done
    epic: 20260424-payment-overhaul
```

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

### Per-slug E2E spec — video-faithful PRs (v0.16.0+)

When a plan ships or changes **user-facing behavior** (Playwright project), give it
its **own** E2E spec and scope `## How to run` to that spec only — that spec is what
`action:work` / `action:codegen` record into the PR video:

```bash
pnpm exec playwright test e2e/<YYYYMMDD>-<AUTHOR>-<slug>.spec.ts   # this plan's spec ONLY (use your testDir)
```

- The PR video then shows **that feature**, not a shared smoke or the whole suite.
  Feature videos on green PRs require `video: 'on'` in the project's Playwright
  config (`retain-on-failure` would leave a passing feature PR videoless).
- `action:regression` re-runs each *archived* slug's `## How to run`, so the feature is
  re-verified exactly as in its PR; the accumulated per-slug specs are the full suite.
- Keep the block to the **spec only** — don't bundle project-wide `tsc -b` / lint: a
  multi-line block gates on the last command's exit only, and a global typecheck in
  every slug fails all slugs at once on one unrelated error.
- Pure-logic plans keep a unit `## How to run` and no e2e spec (test pyramid).
  Non-Playwright (Cypress/…) projects: SCV auto-attach is Playwright-only.
- `action:promote` offers to scaffold this for UI plans (spec stub + scoped `## How to
  run`, with your approval; it writes into your test tree, e.g. `e2e/`). If you later
  remove a feature's spec, supersede/obsolete its slug so the archived command doesn't dangle.

### TESTS.md minimum requirements (for pass judgment)

**The floor is the user's features.** Every feature / behavior the user described — in
the `action:help` conversation or the `action:promote` dialog — must appear as a concrete,
**detailed** `## Test scenarios` entry. That set is the **minimum requirement**, and it
equals what the PR ships: never drop, merge away, or vaguen a user-stated feature to
make authoring easier. You MAY *add* supplementary tests on top (e.g. unit tests for
pure logic, extra edge cases) — additions are welcome; only falling **below** the
user-stated features is forbidden. For a UI plan, the per-slug E2E spec (above) must
assert these same user-facing features, so the PR video shows what the user asked for.

- [ ] **Every user-stated feature/behavior is a detailed TESTS scenario** (the floor above — this = the PR's shipped features)
- [ ] **How to run** is written as a clear command (`bash` / `npm` / `pnpm` / etc.)
- [ ] **How to run stays true after archiving.** The regression action replays it
      from the archive forever, so it may depend only on tree CONTENT — never on
      commit state. Concretely: no `git diff ... HEAD` scope assertions (true only
      in the uncommitted working tree, permanently false once merged), no
      references to files the PR does not ship, and no re-run of the whole test
      suite inside one slug (CI already runs it; N slugs × full suite is what made
      the regression pass take ten minutes). Four archived plans broke this and
      stayed red, unseen, for a release cycle.
- [ ] **Pass criterion** for each scenario is stated as an observable form
- [ ] **Pass criteria** block contains the "overall done declaration condition"

If any of those is ambiguous, `action:work` will ask the user before starting implementation.

### Auto video evidence attachment (v0.3+)

If Playwright (`video: 'on'`) or an equivalent tool produces .webm/.mp4 under `test-results/`, `action:work` Step 9d's PR creation **auto-embeds** them inline into the PR body. Videos are pushed to a separate `scv-attachments` orphan branch (so the working branch's git history stays clean), and auto-deleted N days after PR merge.

### Authoring guide for regression re-runs

TESTS.md is used both for `action:work` initial verification AND, **after archive, by `action:regression` for accumulated regression**. Two authoring patterns:

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
   With this pattern, a follow-up plan can `supersedes_scenarios: ["<slug>:T2"]` to skip just T2 while keeping the rest in regression. Without dispatch, `action:regression` can't support scenario-level skip and falls back (with a warning) to skipping the whole slug.

---

## 5b. FEATURE_ARCHITECTURE.md (optional, prompted on every promote)

After PLAN.md / TESTS.md, `action:promote` asks **per folder** whether to also write `FEATURE_ARCHITECTURE.md` — two Mermaid diagrams that describe the feature's design before implementation.

**Why two diagrams (minimum):**

| Diagram | Purpose |
|---|---|
| 1. Component data flow | How this feature's components combine, what data / parameters flow between them. Helps the implementer (you or a teammate or `action:work`) understand the design before touching code. |
| 2. Position in whole architecture | Where this feature sits in the system at a coarse grain. Helps stakeholders see the change scope at a glance and reduces "what is this connected to?" review questions. |

The document may include more diagrams (sequence, state, deployment) when the feature genuinely needs them. Two is the floor, not the ceiling.

**Why this is optional:**

Trivial changes (typo fix, single-line null guard, patch dep bump) get no value from a diagram. The default `action:promote` flow asks every time so the user picks per folder. Pick "skip" once for trivial work, "yes" once for non-trivial work — there is no flag to remember.

**Diagram 2's data source:**

```
graphify status?
  ├─ skill installed + graph fresh → use .graphify/docs/graphify-out/
  ├─ skill installed + graph stale/missing → ask user (run graphify? skip? other?)
  └─ skill missing → ask user (skip? other?)
```

`action:promote` decides this branching automatically. The user only sees the resulting user confirmation when there is a real decision to make (graphify run-or-skip).

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
lang: <english | korean | japanese | other>   # (v0.7.3+) inherited from PLAN.md — Mermaid node/edge labels follow this language
---
```

**Body skeleton:**

```markdown
# Architecture — <title>

> Two-diagram view of this feature. Review and edit before `action:work`.

## 1. Component data flow

```mermaid
%%{init: {'theme':'base', 'themeVariables': {'primaryColor':'#1e1e1e','primaryTextColor':'#fff','primaryBorderColor':'#9096a8','lineColor':'#e7e9f0','secondaryColor':'#2d2d2d','tertiaryColor':'#1e1e1e','background':'#171922','edgeLabelBackground':'#171922'}}}%%
flowchart LR
  ...
```

## 2. Position in whole architecture

> Source: <graphify graph (built YYYY-MM-DD) | skipped>

```mermaid
%%{init: {'theme':'base', 'themeVariables': {'primaryColor':'#1e1e1e','primaryTextColor':'#fff','primaryBorderColor':'#9096a8','lineColor':'#e7e9f0','secondaryColor':'#2d2d2d','tertiaryColor':'#1e1e1e','background':'#171922','edgeLabelBackground':'#171922'}}}%%
flowchart TB
  ...
  classDef new fill:#FFE082,stroke:#F57C00,stroke-width:2px,color:#000
```
```

**Convention:**

- New components introduced by this feature are highlighted with the `new` class (yellow fill, orange stroke).
- The "Source:" line in section 2 is mandatory when section 2 is present — it makes the diagram's accuracy basis auditable.
- If diagram 2 is skipped (no graphify graph available), section 2 is replaced by a one-line note pointing at how to enable it (run `/graphify`).
- LLM-generated Mermaid may have syntax errors or wrong labels. Treat the file like PLAN.md / TESTS.md — review and edit before `action:work`.
- The file is **not enforced** by `action:work` or `action:regression`. Its value is human comprehension, not gating.

---

## 6. Related Documents convention

- Both PLAN.md and TESTS.md must include a `## Related Documents` section, **even if empty**.
- Links are **relative paths** (within the same folder): `[ARCH.md](./ARCH.md) — one-line description`.
- `action:work` does NOT load files outside this section by default (token guard).
- The user's explicit instruction (e.g., "also read ARCH.md when implementing") triggers extra loading.

### When to split (SCV's judgment criteria)

| Signal | Suggestion |
|---|---|
| Approach Overview > 50 lines | → `ARCH.md` |
| Requirements > 20 bullets | → `REQUIREMENTS.md` |
| API spec > 10 endpoints | → `API.md` |
| Migration steps > 5 | → `MIGRATION.md` |
| Test scenarios > 15 | → split under `tests/` |

If the user explicitly says **"split it"**, ignore the criteria and split. If **"don't split"**, SCV stops proposing splits.

---

## 7. Responsibility split between `action:promote` and `action:work`

| Step | Command | Responsibility |
|---|---|---|
| 1. Refine raw | `action:promote` | Confirm slug/title via dialogue → create folder + PLAN + TESTS scaffold → update `scv/readpath.json` |
| 2. Implement / verify | `action:work <slug>` | Read PLAN + TESTS, implement, run TESTS, report result, ask about archive |
| 3. Archive | `action:work --archive` | On tests pass + user approval: move `promote/<slug>/` → `archive/<slug>/` + create `ARCHIVED_AT.md` |

---

## 8. Archive convention

Completed plans must move to `scv/archive/` (**token efficiency** — `action:work` reads only active plans).

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

`reason` can be passed via `action:work <slug> --archive --reason="..."` argument; if omitted, defaults to `tests passed`. The body's reason block is also filled with the `--reason` value (default "All TESTS scenarios passed").

### Archive move decision

| Situation | Action |
|---|---|
| Tests passed + user explicit ("archive it") | Auto mv |
| Tests passed + user pre-declared allow ("auto-archive when tests pass") | Auto mv + report |
| Tests passed + no user direction | SCV asks "archive now?" and waits for answer |
| Tests failed | Archive forbidden, return to fix loop |

---

## 8b. Obsolete convention (permanently exclude from regression)

An archived plan's TESTS.md **must never be modified**. Instead, declare "this feature need not run anymore" via 3 paths:

| Path | Mechanism | When to use |
|---|---|---|
| **Pre-declaration** | New PLAN.md frontmatter has `supersedes: [<old-slug>, ...]` or `supersedes_scenarios: ["<slug>:T<n>", ...]` | When you know what you're replacing at authoring time |
| **Auto-propagation** | When A is archived via `action:work`, SCV fires user confirmation (default Yes) "mark B as obsolete?" — on approval, modifies B's PLAN.md frontmatter only | Default path triggered when supersedes is declared |
| **Runtime triage** | On `action:regression` failure, fire 3-way user confirmation: regression (fix code) / obsolete (mark now) / flaky (retry) | When supersede declaration was missed, or when env changes force deprecation |

### What `obsolete` means — terminology

- **Meaning**: "The feature this plan represents is no longer in operation. Permanently excluded from the regression suite." It was either replaced by another plan (A) (`obsoleted_by: <A-slug>`) or removed without a successor (`obsoleted_by: manual`).
- **Difference from `done`**: `done` = "implementation finished, **live** feature"; `obsolete` = "once existed, but no longer does".
- **Effect on `action:regression`**: Slugs with `status: obsolete` are excluded from execution by default (include with `--include-obsolete` for audit purposes).
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

TESTS.md / ARCHIVED_AT.md / other files are **never modified** (immutable archive principle). `action:regression` reads these 3 fields at runtime to skip the slug.

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

## Suggested path
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

When `action:work` archives this retirement plan, Step 9c will guide marking `payment-v1` as obsolete. No new command needed.

---

## 8d. Epic branch strategy (when a large request is split into multiple features)

Receiving a user's large request in a single promote folder produces **chaos and abrupt change**. SCV analyzes raw material in the `action:promote` step and proposes a split when "this is sized for multiple features" (auto-split forbidden — always confirm with user).

**Split count is not fixed.** SCV proposes an appropriate count (e.g., 2, 4, 8) and candidate slugs based on the actual content / topic diversity of the raw, and the user does the final adjustment. The §8e example below is split into 7, but **that's just one example, not a recommended standard**.

Split features are grouped under the same **`epic: <epic-slug>`** frontmatter.

### Working flow

```
Large request (raw input)
   │
   ▼  action:promote proposes split → user approves
Multiple promote folders (count matches raw content), all sharing the same epic
   │
   ▼  action:work <slug> for each
feature 1 → archive → PR (base = epic/<epic-slug>)
feature 2 → archive → PR (base = epic/<epic-slug>)
...
feature N → archive → PR (base = epic/<epic-slug>)
   │
   ▼  (When all features in epic are archived, SCV auto-prompts)
"All features of epic <slug> done. Create the integration refactor PLAN?"
   │
   ▼  Refactor PLAN scaffold (kind: refactor) → action:work
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

### `action:status` epic progress

```
[epics]
  epic 20260424-payment-overhaul: 4/7 archived, 2 in promote, refactor pending
  epic 20260415-search-revamp:    7/7 archived + refactor done → ready to merge
```

### When the user manually epic-groups

Even if `action:promote` didn't propose a split, the user can explicitly say "these promotes share an epic" — then add `epic: <slug>` to each PLAN.md frontmatter directly. From then on, SCV recognizes them as an epic.

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

## Suggested path

1. Consolidate duplicate helpers across features (`utils/payment.ts`)
2. Naming consistency (`charge_id` vs `paymentId` unified)
3. Extract a shared error-code enum
4. Fix one race condition discovered during integration
5. Integration regression run (`action:regression --include-promote`)

## Related Documents

<!-- All 7 epic feature PLAN.md files can be referenced -->
```

**TESTS.md** is usually simple — "existing regression + 1–2 integration scenarios":

```markdown
## How to run
\`\`\`bash
bash "$SCV_CORE_ROOT/scripts/regression.sh" --tag payment
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

- `action:work` start → `planned` → `in_progress`.
- Right before completing implementation → `testing`.
- All TESTS pass + archive move → `done` (note: PLAN.md is now in archive).
- `done → obsolete` transition: 3 paths in §8b (auto-propagation / pre-declaration + auto / runtime triage). NOT transitioned from `in_progress` / `testing` (incomplete plans don't have an archive).

---

## 10. Related modules

<!-- MODULES:AUTO START applies_to=promote -->
<!-- MODULES:AUTO END -->
