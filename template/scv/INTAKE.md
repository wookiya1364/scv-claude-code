---
name: intake
version: 1.0.0
status: active
last_updated: 2026-04-17
applies_to: []
owners: ["@team"]
tags: [standard, core, process, protocol]
standard_version: 1.0.0
merge_policy: overwrite
---

# INTAKE — Project interview protocol

> **This document is process. The content does not change between projects.**
> Each project follows this order, talking with Claude, to fill the other standard documents (DOMAIN, ARCHITECTURE, DESIGN, …) from zero base.

## 0. Immutable principles

1. **No speculation** — Don't fill any section without an explicit user answer. Don't write "this is probably how it is".
2. **One at a time** — Complete one section → user confirms → next section. No batch fills.
3. **If ambiguous, keep asking** — Follow up until you get a yes/no or concrete value.
4. **Stop on cross-reference conflict** — If newly agreed content conflicts with an existing doc, decide which side to revise first.
5. **Every draft lift goes through user confirmation** — Claude must NOT auto-flip `status: draft` → `active`.
6. **Implementation gate** — If any standard doc has `status: draft`, do NOT start feature work in that doc's scope. Run this INTAKE for the relevant doc first.
7. **Respect existing progress (resume rule)** — Even if asked to "start" INTAKE, **first check every standard doc's `status`**. Treat `active` or `N/A` docs as already done (or documentation not adopted — adoption mode) and **skip those steps**. **Resume only from `draft` docs.** Step 0 (project overview) is also skipped if DOMAIN and ARCHITECTURE are `active` or `N/A`. **Never restart from step 0 unless the user explicitly says "start over from scratch".**

## 1. Overall flow (by step)

| Step | Target | Required/Optional | Estimated time | Completion check (resume-skip threshold) |
|---|---|---|---|---|
| **-1 (Pre)** | Drop **existing material** into `scv/raw/` | Recommended | Variable | — (always optional) |
| 0 | Project overview gathering | Required | ~15 min | Done if DOMAIN AND ARCHITECTURE are both `status: active` or `N/A` |
| 1 | `DOMAIN.md` | Required | 30–60 min | `status: active` or `N/A` (documentation not adopted in adoption mode) |
| 2 | `ARCHITECTURE.md` | Required | 30–60 min | `status: active` or `N/A` |
| 3 | `DESIGN.md` | Required if UI exists | 30–60 min | `status: active` or `N/A` (no UI, or adoption) |
| 4 | `AGENTS.md` | Required if AI components | 30–60 min | `status: active` or `N/A` (no AI, or adoption) |
| 5 | `TESTING.md` | Required | 20–40 min | `status: active` or `N/A` |
| 6 | `REPORTING.md` | Required | 10 min | `status: active` or `N/A` |

> **What `N/A` means**: in adoption mode, every standard doc is seeded `N/A` right after hydrate. The INTAKE resume check interprets `N/A` as "documentation not adopted for this project" and **skips that step**. When the user decides to document a specific subsystem and lifts it `N/A → draft` themselves, INTAKE will then guide filling that doc.

At each step, Claude **follows the target doc's `How to elicit` section literally**. This INTAKE only defines the top-level order.

### What Claude does first (resume check)

1. Read the frontmatter `status` of `scv/{DOMAIN,ARCHITECTURE,DESIGN,AGENTS,TESTING,REPORTING}.md`.
2. Classify Steps 0–6 by the "completion check" above → split into `done_steps` / `pending_steps`.
3. **Present the user an explicit A/B choice** (no auto-resume):

   ```
   I checked the current INTAKE progress:
     active (done)         : <names of active docs>
     N/A    (not adopted)  : <names of N/A docs — adoption-mode default>
     draft  (pending)      : <names of draft docs>

   How would you like to proceed?
     [A] Resume — start from the first <draft> doc. Don't touch active/N/A
         docs. (Usually this is the right answer.)
     [B] Start over — reconsider every doc from Step 0. Re-question existing
         active docs too. Pick this only when the project's direction has
         shifted significantly.
   ```

4. User answer:
   - **A** → start from the first `draft` step. Never modify `active` / `N/A` docs. If no `draft` exists, respond "no pending — every doc is active or N/A" and wait.
   - **B** → start at step 0. **Never overwrite existing content without explicit user confirmation.** `status` stays as-is unless the user explicitly approves a change.
   - **Ambiguous answer** → ask again. Don't proceed by guessing.
5. If everything is `active` or `N/A`: respond "Every INTAKE doc is already complete (active) or not adopted (N/A). If you'd like to start documenting a specific doc, lift it to `draft` and tell me the name" and wait.

## 1.5. Pre-step — drop into scv/raw/ (recommended)

If you have **existing material** (meeting notes, external specs, design sketches, competitive analyses, user-interview transcripts, etc.), drop them into `scv/raw/` before Step 0.

1. Read `scv/raw/README.md` for usage (anything goes).
2. Drop in the material → git commit.
3. At the start of Step 0, Claude reads through the raw material first, then begins asking questions.

**Why**: lets Claude scan the team's accumulated context up front, so instead of blindly accepting your answers it can ask **grounded questions** like "you said X in this earlier meeting note — does that still hold?".

## 2. Step 0 — Project overview (do this first)

Claude asks in order:

1. "What does this project do, **in one sentence**?"
2. "Who are the primary users and in what environments do they use it? (up to 3 personas)"
3. "Six months from now, **what must exist** for you to call this a success?" (observable outcomes)
4. "Are there existing similar systems? (If yes, why are we building this from scratch?)"
5. "What are the technical constraints?" (e.g., language/framework lock-in, air-gapped operations, legacy integration)
6. "Does this project include **AI agents (LLM/STT/TTS)**?"
   - YES → Step 4 (`AGENTS.md`) will run
   - NO → skip Step 4
7. "Is there a user-facing **UI / web / app**?"
   - YES → Step 3 (`DESIGN.md`) will run
   - NO → skip Step 3

Recording locations: `DOMAIN.md`'s "Mission / scope", `DESIGN.md`'s personas (if applicable), `ARCHITECTURE.md`'s "Constraints".

**User confirmation**: "Overview agreed. Shall we start with DOMAIN?"

## 3. Entry rule for Steps 1 ~ 6

When entering each step:

1. Open the target doc.
2. Ask the doc's `## How to elicit` section **in order**.
3. Record answers into the empty slots of the doc's `## Structure`.
4. Verify the `## Completion criteria` checklist is complete.
5. When satisfied, ask the user: "Promote this doc's `status` to `active`?" — modify frontmatter **only after explicit user approval**.
6. Move to the next step.

If at any point the user says "wait, let's revisit X", stop immediately. Don't force-progress to the next step even if it's taking long.

## 4. Inter-step dependencies

- 1 (DOMAIN)'s glossary must be in place so 2 (ARCHITECTURE)'s service boundaries can be expressed in domain language.
- 3 (DESIGN) can't proceed without 1–2 (you don't know what to draw).
- 4 (AGENTS) needs 1 (DOMAIN)'s use cases first to define agent responsibilities.
- 5 (TESTING) translates the observable outcomes from 1–4 into E2E scenarios.
- 6 (REPORTING) is **configuration**, not a doc — confirm at the end.

## 5. Completion conditions

For this INTAKE to be "complete":

- [ ] All required docs at `status: active`
- [ ] If the project has AI, `AGENTS.md` also `status: active`
- [ ] Every doc's `## Completion criteria` checklist fully satisfied
- [ ] User explicitly says "**implementation may begin**"

Only then is Ralph Loop (`/ralph-loop` — **external command. NOT provided by the SCV plugin**: copy `ralph-template-scv.md` to `~/.claude/ralph-template.md` to enable it) allowed to run.

## 6. Re-entry

If **requirements change** mid-project:

1. **Reopen** the step relevant to the scope of change (no need to restart INTAKE from the beginning).
2. Optionally lower that doc's `status` from `active` → `in_revision`.
3. Apply the change, then back to `active`.
4. Record in `CHANGELOG.md` (project-local) — "YYYY-MM-DD: <doc> revised, reason".

## 7. Related modules

<!-- MODULES:AUTO START applies_to=intake -->
<!-- MODULES:AUTO END -->
