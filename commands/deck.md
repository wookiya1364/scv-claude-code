---
description: "Turn a markdown planning doc into a spec-grade single-HTML deck (DeckUI). Deterministic md→deck transform + a quality/gap lint; the raw markdown stays visible in a side panel."
argument-hint: "[<path-to-markdown>]"
allowed-tools:
  - "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/deck.sh:*)"
  - "AskUserQuestion"
  - "Read"
  - "Glob"
  - "Grep"
  - "Edit"
model: opus
---

# /scv:deck — markdown → 기획서 덱

Turn a plain markdown doc into a deck that reads like a **real planning document
(기획서)** — headings become slides, GFM tables become data tables, ```mermaid
fences become diagrams, `> [!NOTE]`/`[!WARNING]` become callouts — and the **raw
markdown stays visible in a side panel** (the slide and the source always agree).

**Division of labor (deterministic + LLM-assist):**
- The **transform is deterministic** (`scripts/deck.sh` → `DeckUI/scripts/md-to-deck.mjs`, remark-based). It never invents content: every rendered value comes from the source md.
- **You (Claude)** assist around it: pick the input, surface the lint/gap report, and *offer* to improve the **source markdown** (never the generated deck) when sections are missing — always with user approval.

## Step 0 — Resolve the input markdown

`$ARGUMENTS` is a path to a markdown file. If empty:
- Use `Glob` to find likely docs (`docs/**/*.md`, `**/PRD*.md`, `**/기획*.md`, or a `scv/promote/<slug>/PLAN.md`).
- If several, ask via `AskUserQuestion` which one. If none, tell the user to pass a path: `/scv:deck docs/prd.md`.

Do **not** fabricate a doc. `/scv:deck` renders what exists.

## Step 0.5 — Compose a planner-grade structure (act like a 기획자)

A deck is only as good as its source. A real 기획서 does **not** just list features
— it opens with the **whole picture**, locates the change **inside** it, states the
**delta**, and explains **why**. A flat feature list produces the reaction "그래서
이게 어디에 붙는 건데?". Before building, make the source have this shape — pulling
context from the project's own docs, **never inventing** a system it can't see.

**Big-picture sources (priority):**
1. `scv/promote/<slug>/FEATURE_ARCHITECTURE.md` — if this is a promote plan, it already has a "position in whole" diagram with `:::new` nodes.
2. `scv/ARCHITECTURE.md` + the graphify docs graph (`.graphify/docs/`) — the existing system structure (the As-Is whole).
3. The feature's `PLAN.md` (problem, goals/non-goals, steps) — the delta + the why.

**Target section order** (compose into the source, or a `*-deck.md` working copy, with user approval):
1. **배경 / 왜 지금인가** — problem, impact, why-now (from PLAN / problem statement).
2. **전체 구조 (As-Is)** — a mermaid diagram of the existing system (from ARCHITECTURE / graphify).
3. **이 기능의 위치 (To-Be)** — the same diagram with **new/changed nodes highlighted** (`classDef new/changed` + `:::new` / `:::changed`) so "이 부분이 바뀐다"가 한눈에 보인다.
4. **변경점 (As-Is → To-Be)** — a per-area table of what changes.
5. Details — 목표/비목표, 요구사항, 화면, 데이터, 성공지표, 예외처리.

**Faithfulness (non-negotiable):** the big picture must come from real docs. If no `ARCHITECTURE.md` / graphify graph / `FEATURE_ARCHITECTURE.md` exists, do **not** invent a system diagram — tell the user the deck can't show the whole until one exists (offer to draft `ARCHITECTURE.md`, or run `/scv:promote` which generates `FEATURE_ARCHITECTURE.md`), and proceed with what's available plus a lint warning. Use `AskUserQuestion` before rewriting the user's source.

## Step 1 — Build the deck

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/deck.sh" $ARGUMENTS
```

Parse the emitted lines:
- `DECK_SLUG:` — the deck id.
- `LINT: <n> warning(s)` + each `  ⚠ ...` — missing canonical sections.
- `DECK_HTML:` — absolute path to the built self-contained HTML.

If the helper errors (missing Node/pnpm), relay it and suggest `/scv:install-deps` (Node + pnpm are `/scv:deck`-only deps). Do not auto-install globally.

## Step 2 — Report + quality coaching

1. Tell the user the deck is built and **where**: `DECK_HTML`. One-line how-to-open (`open <path>` / double-click). Mention the raw markdown is in the side panel (toggle `S`).
2. If `LINT` > 0, surface the warnings plainly. These are the sections a professional 기획서 usually has but this doc lacks (비목표 / 성공지표 / 인수기준 / 예외처리, etc.).
3. **Offer** (via `AskUserQuestion`, default: just report) to help draft the missing sections **into the source markdown** — then the user re-runs `/scv:deck`. Never write invented specifics; propose structure + `<TODO>` placeholders and let the user fill real values.

## Never
- Never invent content that isn't in the source markdown (the deck and the side-panel source must agree).
- Never edit the generated `deck.json` by hand — edit the source md and re-run.
- Never modify files outside the deck flow without asking.
