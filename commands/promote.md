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

#### Step 3.0 — Split suggestion (epic grouping)

Heuristic decision tree:

| Helper signal | LLM judgment | Action |
|---|---|---|
| `SUGGEST_SPLIT: yes` (raw files > 7 or topic clusters ≥ 3) | Raw content also looks multi-responsibility (auth + payment + UI etc.) | **Strongly recommend split** |
| `SUGGEST_SPLIT: yes` | LLM sees it as a single topic in practice (e.g., one large meeting log) | Suggest split but offer "single is fine" as an option |
| `SUGGEST_SPLIT: no` | LLM sees 5+ topics mixed in the body | Suggest split (LLM judgment wins) |
| `SUGGEST_SPLIT: no` | LLM also sees a single topic | Don't suggest split. Flow to Step 3.1 single-folder dialog |

If split is recommended, fire `AskUserQuestion`:

```
Question: "Looking at the raw material, this seems sized for multiple features (current raw spans N topic clusters). How would you like to proceed?"
options:
[1] "Split into multiple features (recommended) — group as an epic"
    description:
    "Group the raw material by topic into an appropriate number of promote folders, all
     sharing the same epic: <epic-slug>. **The number of splits is content-driven** —
     small material may need 2–3, larger material more. Claude proposes a candidate split
     (each folder's slug + which raw goes where), and you can adjust.

     Benefits: each feature is small and well-scoped, narrowing test scope and easing
     review. After all features are archived, SCV auto-suggests an integration refactor
     PLAN (see PROMOTE.md §8d, §8e).

     **Example (the count is illustrative, not prescriptive)**: 'Payment v2 overhaul' →
       roughly 7 features
       - 20260424-sspark-pay-overhaul-auth-v2
       - 20260424-sspark-pay-overhaul-charge-flow
       - 20260424-sspark-pay-overhaul-refund-flow
       - ... (all sharing epic: 20260424-pay-overhaul)
       - 20260430-sspark-pay-overhaul-refactor (kind: refactor, last)

     Real count varies with your domain and raw volume."

[2] "Proceed as a single promote"
    description:
    "Take it as one folder. Recommended only when the scope is small or genuinely
     single-topic. With a single folder, you lose epic grouping benefits (branch strategy,
     auto-suggested refactor)."
```

After user picks:

- **[1] Split**: One more `AskUserQuestion` — "What epic slug should we use? (e.g., `20260424-pay-overhaul`)". Then propose slugs per topic cluster from the raw → user approves → create N folders, all with the same `epic` frontmatter.
- **[2] Single**: proceed to Step 3.1 below.

#### Step 3.1 — Single-folder dialog (no split)

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
kind: feature                          # feature | refactor | retirement (default feature; specify when splitting)
# epic: <EPIC_SLUG>                    # Same value across all folders of a split. Omit for single-folder.
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

<TODO: 1–3 sentences — what & why>

## Goals / Non-Goals

- **Goals**
  - <TODO>
- **Non-Goals**
  - <TODO>

## Approach Overview

<TODO: 5–15 lines. If this grows beyond ~50 lines, `/scv:work` will suggest splitting into ARCH.md.>

## Steps

1. <TODO>
2. <TODO>

## Related Documents

<!-- If the plan grows, link supporting files here.
     /scv:work only loads Related-Documents entries on demand (token guard). -->

## Risks / Open Questions

- <TODO>

## Links

- Raw originals: (listed in frontmatter)
- Related PRs:
```

**`scv/promote/<folder>/TESTS.md`**:

```markdown
# Test Plan — <TITLE>

## Overview

<TODO: one paragraph — what you're verifying and why>

## Test scenarios

### T1. <Scenario name>

- **Setup**: <TODO>
- **Run**: <TODO>
- **Expected**: <TODO>
- **Pass criterion**: <observable condition>

## How to run

<!-- concrete command(s) like `npm run test:auth` or `pnpm test -- --grep X` -->
```bash
<TODO>
```

## Pass criteria

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
- Reminder: PLAN.md and TESTS.md are **starting skeletons** — fill in the `<TODO>` spots. Run `/scv:status` any time to see pending changes.

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
