# scv/CLAUDE.md — SCV workflow index

> **This file is the index and rules for the SCV workflow.** The project root's `CLAUDE.md` is **never touched by SCV** and remains user-owned. Everything SCV needs is under `scv/`.

## Two hydrate modes

SCV supports two modes at hydrate time. **The default (adoption) mode is enough for most cases.**

### Default — adoption (recommended · existing project)

- `bash hydrate.sh init .` (no flag)
- Standard docs (`DOMAIN`, `ARCHITECTURE`, `DESIGN`, `AGENTS`, `TESTING`, `REPORTING`, `RALPH_PROMPT`) are all seeded with `status: N/A`.
- **No INTAKE forced.** `/scv:promote` and `/scv:work` are usable immediately.
- When needed, document only specific subsystems by walking them `draft → active`.
- Hook to external docs (Confluence etc.) via `refs:`.

### `--new` — greenfield (new project)

- `bash hydrate.sh init . --new`
- Standard docs are seeded with `status: draft`.
- `/scv:help` walks you through `scv/INTAKE.md`'s dialogue protocol to fill every standard doc one by one.
- Use this only when truly starting from zero.

## Top-level rules (immutable)

1. **If a standard doc is `status: draft`, do NOT start implementation work in that doc's scope.** Run the corresponding INTAKE step first to fill the doc through user dialogue.
   - **In adoption mode this rule does not fire** (docs are `N/A`). It only applies once you've decided to document a specific subsystem and lifted it to `draft`.
2. **No speculation**: never fill a section without an explicit user answer.
3. **One at a time**: complete one section → user confirms → next.

## Relationship with the root CLAUDE.md

- The project root's `CLAUDE.md` (if any) is the user's **project-wide rules**. SCV **never modifies it**.
- SCV's routines (slash commands, sync, hydrate) reference **only this `scv/CLAUDE.md` and other docs under `scv/`**.
- To make Claude aware of SCV in casual conversations too, optionally add this one line to your root `CLAUDE.md`:
  ```
  > This project uses SCV — see `scv/CLAUDE.md` for workflow details.
  ```

## Standard documents

All SCV documents live under the `scv/` directory.

### Process docs (read and follow — don't fill in)

| Document | Role |
|---|---|
| `scv/INTAKE.md` | Interview protocol at project start. Order in which other docs are filled. |
| `scv/PROMOTE.md` | raw → promote → archive promotion convention. Folder names, PLAN/TESTS, Related Documents. |

### Required (every project)

| Document | One-line purpose |
|---|---|
| `scv/DOMAIN.md` | Terminology, entities, invariants, use cases |
| `scv/ARCHITECTURE.md` | Service boundaries, data stores, environments, NFRs |
| `scv/TESTING.md` | Test pyramid, E2E scenarios, artifact-path contract |
| `scv/REPORTING.md` | Collab-tool mapping (Slack/Discord) convention |

### Conditionally required

| Document | Condition |
|---|---|
| `scv/DESIGN.md` | Required when there's a user-facing UI (web/app). Otherwise `status: N/A`. |

### Optional

| Document | Condition |
|---|---|
| `scv/AGENTS.md` | Only when the system has **probabilistic components** (LLM/STT/TTS/classifier). |

### Configuration entry point

| File | Role |
|---|---|
| `scv/RALPH_PROMPT.md` | Project-specific config read by Ralph Loop (focus_phase, commands, etc.). |

## Routing — which doc to read first per task type

- Project bootstrap / requirements → `scv/INTAKE.md`
- Architecture / service boundaries → `scv/ARCHITECTURE.md`
- Domain rules / terminology confusion → `scv/DOMAIN.md`
- UI/UX → `scv/DESIGN.md` (if applicable)
- AI agent behavior / probabilistic responses → `scv/AGENTS.md` (if applicable)
- Test failure analysis / E2E authoring → `scv/TESTING.md`
- Collab-tool notifications / report format → `scv/REPORTING.md`

## Project directory layout

```
project-root/
├── CLAUDE.md                     # User-owned (SCV doesn't touch) — optional
├── scv/                          # All SCV workflow docs and state live here
│   ├── CLAUDE.md                 # this file (SCV index)
│   ├── INTAKE.md                 # dialogue protocol
│   ├── PROMOTE.md                # promotion convention
│   ├── DOMAIN.md ARCHITECTURE.md DESIGN.md AGENTS.md
│   ├── TESTING.md REPORTING.md
│   ├── RALPH_PROMPT.md
│   ├── readpath.json             # raw change-tracking snapshot (auto-updated by /scv:promote)
│   ├── promote/                  # Promoted topic / plan documents
│   │   └── <YYYYMMDD>-<author>-<slug>/
│   │       ├── PLAN.md
│   │       ├── TESTS.md
│   │       └── (free additional files)
│   ├── archive/                  # Implementations done (token efficiency)
│   │   └── <YYYYMMDD>-<author>-<slug>/
│   │       ├── PLAN.md TESTS.md ...
│   │       └── ARCHIVED_AT.md    # completion record (auto-generated)
│   └── raw/                      # Free-input space (notes, sketches, PDFs, recordings)
│       └── README.md
├── .env, .env.example, .gitignore
└── (project-specific code: src/, packages/, apps/, etc.)
```

**The big picture**: drop material into `scv/raw/` → `/scv:promote` refines it into `scv/promote/<slug>/` → `/scv:work <slug>` implements + tests → on pass, moves to `scv/archive/`.

## Work procedure

1. **INTAKE complete?** — Check that every required doc has `status: active`. If any is `draft`, start with the corresponding INTAKE step.
2. Understand the requirement → read related standard docs → if needed, read plan docs under `scv/promote/`.
3. Implement → test → fix loop (`/scv:work <slug>` or Ralph Loop).
4. On Phase completion, call `/scv:report "<phase>" <status>` → send to collab tool.

## Promoted documents

<!-- This section points to documents under `scv/promote/`. Add manual links as needed. -->

## Project-specific — SCV-scope rules

<!-- PROJECT:LOCAL START -->
<!-- This block is never overwritten by /scv:sync. -->
<!-- Put project-specific rules tailored to the SCV workflow here -->
<!-- (e.g., promote slug prefix policy, mandatory TESTS.md sections, Phase naming, etc.). -->
<!-- Project-wide rules belong in the root CLAUDE.md — not this file. -->
<!-- PROJECT:LOCAL END -->

## SCV template metadata

- Template version: <!-- STANDARD:VERSION -->1.0.0<!-- /STANDARD:VERSION -->
- Last sync: <!-- STANDARD:SYNCED_AT -->UNSET<!-- /STANDARD:SYNCED_AT -->
- Collab tool: `.env`'s `NOTIFIER_PROVIDER` (slack | discord)
