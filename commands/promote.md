---
description: "Refine scv/raw/ material into a scv/promote/<YYYYMMDD>-<author>-<slug>/ folder with PLAN.md + TESTS.md. Optionally updates the docs knowledge graph. Interactive; no files written without user approval."
argument-hint: ""
allowed-tools:
  - "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/promote-helper.sh:*)"
  - "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/readpath.sh:*)"
  - "Skill(graphify)"
  - "AskUserQuestion"
  - "Read"
  - "Glob"
  - "Grep"
  - "Write"
  - "Edit"
---

# /scv:promote

You — Claude — will help the user refine material from `scv/raw/` into a structured promote folder at `scv/promote/<YYYYMMDD>-<author>-<slug>/` with `PLAN.md` + `TESTS.md`. See the full convention in `scv/PROMOTE.md`.

## Language preference

Resolve the user's preferred language with this priority, then use it for ALL user-facing output (AskUserQuestion text, status messages, summaries):

1. `~/.claude/settings.json` (or project `.claude/settings.json` / `.claude/settings.local.json`) — `language` key (Claude Code official).
2. Project `.env` — `SCV_LANG` (set by `/scv:help`'s first-time setup).
3. Auto-detect from the user's most recent message language.
4. Default to English.

Technical identifiers stay as-is: file paths, slash command names, frontmatter keys (`status`, `kind`, `epic`, `supersedes`), env var names, SCV terms (`promote`, `archive`, `orphan branch`, `epic`). If both `settings.json language` and `.env SCV_LANG` are unset, suggest `/scv:help` once to lock the preference (don't block — fall back to auto-detect / English for now).

**Non-negotiable rules:**
- Never create / move / delete files without the user's explicit per-candidate approval.
- Raw originals under `scv/raw/` are **never** deleted or moved.
- `status: active` is never set by you — leave every new scaffold as `planned` so the user reviews first.

First, gather context:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/promote-helper.sh" $ARGUMENTS
```

Parse the helper output — the lines `MODE:`, `TODAY:`, `AUTHOR:`, `STANDARD_VERSION:`, `GRAPHIFY_SKILL:`, `GRAPH_STATUS:`, `RAW_FILE_COUNT:`, `RAW_TOPIC_CLUSTERS:`, `SUGGEST_SPLIT:`, `SPLIT_REASON:` are the primary signals; section blocks (`=== scv/raw inventory ===` etc.) give you the content to work with.

## Protocol

### Step 1 — Graph freshness (run before dialog)

Based on the helper header:

| GRAPHIFY_SKILL | GRAPH_STATUS | Action |
|---|---|---|
| `available` | `stale` or `missing` | Invoke the `graphify` skill to build / refresh the docs graph **before** proceeding with dialog. Tool: `Skill` with `skill: "graphify"` and args: `scope=docs`, `src=scv/raw`, `update=true` (or equivalent the skill expects). Then move the output into `.graphify/docs/` if the skill wrote `graphify-out/` at cwd. |
| `available` | `built` | Skip graph update. |
| `missing` | anything | Print a **short one-line warning**: "graphify skill not found — proceeding without token-efficient graph queries. Install guide: [link from user's environment]". Continue. |

If `MODE: graph-only`: after handling the graph (or warning if skill missing), **stop here**. Do not proceed to dialog or file creation. Print a one-line summary of what you did.

### Step 2 — Plan summary (before dialog)

Summarize to the user:
- How many raws changed (from `added=N modified=N removed=N`).
- Whether the graph was updated.
- What existing promote folders / archive folders already exist.

### Step 3 — Dialog (for each candidate promote folder)

#### Step 3.0 — Split suggestion (epic 묶음)

Heuristic 결정 트리:

| Helper signal | LLM 판단 | 대응 |
|---|---|---|
| `SUGGEST_SPLIT: yes` (raw 파일 > 7 또는 토픽 클러스터 ≥ 3) | raw 본문도 다양한 책임 (auth + payment + UI 등) 으로 보임 | **분할 강력 추천** |
| `SUGGEST_SPLIT: yes` | LLM 보기에 사실 한 주제 (큰 회의록 1개 등) | 분할은 제안하되 "묶어 가도 됩니다" 도 옵션으로 |
| `SUGGEST_SPLIT: no` | LLM 보기에 본문이 5+ 주제 혼재 | 분할 제안 (LLM 우선) |
| `SUGGEST_SPLIT: no` | LLM 도 단일 주제 | 분할 안 제안. Step 3.1 의 단일 폴더 흐름으로 |

분할 추천 조건이면 `AskUserQuestion`:

```
Question: "raw 자료를 분석해 보니 여러 feature 로 쪼갤 만한 규모입니다 (현재 raw 가 N 토픽 클러스터). 어떻게 진행할까요?"
options:
[1] "여러 feature 로 분할 (권장) — epic 으로 묶음"
    description:
    "raw 자료를 토픽별로 묶어 적절한 갯수의 promote 폴더를 만들고 같은
     epic: <epic-slug> 으로 묶습니다. **분할 갯수는 raw 의 실제 내용에 맞춰
     결정** — 작은 자료라면 2~3 개, 큰 자료라면 더 많이. Claude 가 후보 분할
     안 (각 폴더의 slug + 어느 raw 가 어느 폴더에 들어갈지) 을 제시하면
     사용자가 조정 가능.

     장점: 각 feature 가 작고 명확하게 떨어져서 테스트 범위가 좁아지고,
     리뷰가 쉬워짐. 모든 feature archive 후 SCV 가 통합 refactor PLAN 도
     자동 안내 (PROMOTE.md §8d, §8e 참조).

     **예시 (꼭 이 갯수일 필요 없음)**: '결제 v2 전면 개편' → 약 7개 feature
       - 20260424-sspark-pay-overhaul-auth-v2
       - 20260424-sspark-pay-overhaul-charge-flow
       - 20260424-sspark-pay-overhaul-refund-flow
       - ... (모두 epic: 20260424-pay-overhaul)
       - 20260430-sspark-pay-overhaul-refactor (kind: refactor, 마지막)

     실제 갯수는 사용자 도메인과 raw 양에 따라 달라짐."

[2] "단일 promote 로 진행"
    description:
    "한 폴더로 받습니다. 라벨이 작거나 사실상 한 가지 주제일 때만 권장.
     단일 폴더로 가면 epic 묶음 효과 (브랜치 전략 · refactor 자동 안내) 는
     없습니다."
```

User 선택 후:

- **[1] 분할**: `AskUserQuestion` 한 번 더 — "epic slug 는 무엇으로 할까요? (예: `20260424-pay-overhaul`)". 그 후 raw 토픽 클러스터별로 슬러그 제안 → 사용자 승인 → N 개 폴더 생성, 모두 동일 `epic` frontmatter.
- **[2] 단일**: 아래 Step 3.1 로.

#### Step 3.1 — Single-folder dialog (분할 안 한 경우)

Use `AskUserQuestion` to confirm with the user. Typical batch:

1. **Scope**: "Do you want a single promote folder covering all N changed raws, or separate folders per topic?"
2. **Slug(s)**: For each folder, ask: "Slug for this promote folder? (kebab-case, 3~5 words)". Combine with `TODAY` and `AUTHOR` from the helper to produce `<YYYYMMDD>-<AUTHOR>-<slug>/`.
3. **Title**: "One-line title for `<folder>`?" (will go in PLAN.md frontmatter `title`).
4. **Raw sources**: For each folder, confirm which raw file paths belong to it (default: all changed raws; user may split).

### Step 4 — Collision check

For each proposed folder name, check the helper's `=== existing promote folders ===` and `=== existing archive folders ===` output. If the full name (`<YYYYMMDD>-<AUTHOR>-<slug>`) exists:

- Suggest `<slug>-v2` (or `-v3`, `-v4` as needed) and re-confirm with user via AskUserQuestion.
- Never silently overwrite.

### Step 5 — Write scaffolds (only after user approval per folder)

For each approved folder, create the directory and write **two files**:

**`scv/promote/<folder>/PLAN.md`**:

```markdown
---
title: <TITLE>
slug: <FOLDER_NAME>
author: <AUTHOR>
created_at: <TODAY>
status: planned
kind: feature                          # feature | refactor | retirement (기본 feature, 분할 시 추가)
# epic: <EPIC_SLUG>                    # 분할로 만든 여러 promote 모두에 동일하게. 단일 폴더면 생략 가능
tags: []
raw_sources:
  - <RAW_SOURCE_1>
  - <RAW_SOURCE_2>
refs: []
# Add vendor-agnostic external refs as needed (Jira/Linear/Confluence/PR etc.):
# refs:
#   - type: jira
#     id: <TICKET_ID>
#   - type: confluence
#     url: https://...
# (Same type may repeat. See scv/PROMOTE.md §4 for full spec.)
---

# <TITLE>

## Summary

<TODO: 1~3 sentences — what & why>

## Goals / Non-Goals

- **Goals**
  - <TODO>
- **Non-Goals**
  - <TODO>

## Approach Overview

<TODO: 5~15 lines. If this grows beyond ~50 lines, `/scv:work` will suggest splitting into ARCH.md.>

## Steps

1. <TODO>
2. <TODO>

## Related Documents

<!-- If the plan grows, link supporting files here.
     /scv:work only loads Related-Documents entries by default (token guard). -->

## Risks / Open Questions

- <TODO>

## Links

- raw 원본: (listed in frontmatter)
- 관련 PR:
```

**`scv/promote/<folder>/TESTS.md`**:

```markdown
# Test Plan — <TITLE>

## 개요

<TODO: one paragraph — what you're verifying and why>

## 테스트 시나리오

### T1. <Scenario name>

- **전제**: <TODO>
- **실행**: <TODO>
- **기대**: <TODO>
- **Pass 기준**: <observable condition>

## 실행 방법

<!-- concrete command(s) like `npm run test:auth` or `pnpm test -- --grep X` -->
```bash
<TODO>
```

## 통과 판정

- <TODO: DONE criteria — when do we declare the whole plan done?>

## Related Documents

<!-- e.g.:
- [`tests/e2e-scenarios.md`](./tests/e2e-scenarios.md)
-->
```

### Step 6 — Update readpath baseline

After all approved folders are created, run:

```
!${CLAUDE_PLUGIN_ROOT}/scripts/readpath.sh update
```

This marks the current raw state as the new baseline so future `/scv:help` / `/scv:status` won't keep flagging the consumed files.

### Step 7 — Report to user

Summarize:
- Created folders (list paths to PLAN.md + TESTS.md)
- Graph update status
- Baseline updated? (yes)
- Next suggested command: `/scv:work <slug>` for the first new plan.
- Reminder: PLAN.md and TESTS.md are **starting skeletons** — user fills the `<TODO>` spots. Run `/scv:status` any time to see pending changes.

## Flag semantics

- `--dry-run` — Emit inventory + diff + plan without calling the graphify skill, writing scaffolds, or updating readpath.json. Safe "what would happen" preview.
- `--graph-only` — Only refresh the docs graph (if possible); skip dialog, scaffolds, and readpath update.
- `--topic SLUG` — Pre-fills the slug suggestion for a single-folder scenario (still requires user confirmation).

## Never

- Delete / move / rename files under `scv/raw/`
- Promote without per-folder approval
- Overwrite an existing promote or archive folder
- Set `status: active` — leave scaffolds as `planned`
- Commit or push — leave version control to the user
