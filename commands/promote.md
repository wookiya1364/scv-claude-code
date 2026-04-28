---
description: "Refine scv/raw/ material into a scv/promote/<YYYYMMDD>-<author>-<slug>/ folder with PLAN.md + TESTS.md. Optionally updates the docs knowledge graph. Interactive; no files written without user approval."
argument-hint: "[--dry-run] [--graph-only] [--topic SLUG]"
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

**Non-negotiable rules:**
- Never create / move / delete files without the user's explicit per-candidate approval.
- Raw originals under `scv/raw/` are **never** deleted or moved.
- `status: active` is never set by you — leave every new scaffold as `planned` so the user reviews first.

First, gather context:

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/promote-helper.sh" $ARGUMENTS
```

Parse the helper output — the lines `MODE:`, `TODAY:`, `AUTHOR:`, `STANDARD_VERSION:`, `GRAPHIFY_SKILL:`, `GRAPH_STATUS:` are the primary signals; section blocks (`=== scv/raw inventory ===` etc.) give you the content to work with.

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
