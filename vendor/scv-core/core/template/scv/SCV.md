# scv/SCV.md — SCV workflow index

> **This file is the index and rules for the SCV workflow.** Project-root
> instruction files are **never touched by SCV** and remain user-owned.
> Everything SCV needs is under `scv/`.

## Hydrate — one path

- `bash hydrate.sh init .`
- Seeds only the SCV workflow files (this index, `PROMOTE.md`, `REPORTING.md`, `raw/`, `promote/`, `archive/`). There is no standard-doc scaffolding step — `action:promote` and `action:work` are usable immediately, on new and existing projects alike.
- Hook to external docs (Confluence etc.) via `refs:` in PLAN.md frontmatter — no need to rewrite their content into SCV.
- Facts the model can derive from the codebase are not pre-documented. Decisions worth keeping belong in version-controlled team notes (e.g. `DECISIONS.md` / a journal), not in snapshot docs.

## Top-level rules (immutable)

1. **No speculation**: never fill a plan section without an explicit user answer.
2. **One at a time**: complete one section → user confirms → next.

## Relationship with project-root instructions

- Any project-root instruction file is the user's **project-wide rules**.
  SCV **never modifies it**.
- SCV's skills, sync, and hydrate routines reference **only this
  `scv/SCV.md` and other docs under `scv/`**.
- To make the host agent aware of SCV in casual conversations too, optionally
  add this line to the instruction file supported by your wrapper:
  ```
  > This project uses SCV — see `scv/SCV.md` for workflow details.
  ```

## Workflow documents

All SCV documents live under the `scv/` directory.

| Document | Role |
|---|---|
| `scv/PROMOTE.md` | raw → promote → archive promotion convention. Folder names, PLAN/TESTS, Related Documents. |
| `scv/REPORTING.md` | Collab-tool mapping (Slack/Discord) convention — read by `action:report`. |

## Project directory layout

```
project-root/
├── <project instructions>        # User-owned (SCV doesn't touch) — optional
├── scv/                          # All SCV workflow docs and state live here
│   ├── SCV.md                 # this file (SCV index)
│   ├── PROMOTE.md                # promotion convention
│   ├── REPORTING.md              # collab-tool report mapping
│   ├── readpath.json             # raw change-tracking + ref_docs provenance (auto-updated by action:promote)
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
│       ├── README.md
│       └── stale/                # Consumed docs — moved here by action:promote; ref_docs records which slugs used each
├── .env, .env.example, .gitignore
└── (project-specific code: src/, packages/, apps/, etc.)
```

**The big picture**: drop material into `scv/raw/` → `action:promote` refines it into `scv/promote/<slug>/` → `action:work <slug>` implements + tests → on pass, moves to `scv/archive/`.

## Work procedure

1. Understand the requirement → read the plan docs under `scv/promote/` (and their Related Documents).
2. Implement → test → fix loop (`action:work <slug>` or an external loop harness).
3. On Phase completion, call `action:report "<phase>" <status>` → send to collab tool.

## Promoted documents

<!-- This section points to documents under `scv/promote/`. Add manual links as needed. -->

## Project-specific — SCV-scope rules

<!-- PROJECT:LOCAL START -->
<!-- This block is never overwritten by action:sync. -->
<!-- Put project-specific rules tailored to the SCV workflow here -->
<!-- (e.g., promote slug prefix policy, mandatory TESTS.md sections, Phase naming, etc.). -->
<!-- Project-wide rules belong in the root instruction file — not here. -->
<!-- PROJECT:LOCAL END -->

## SCV workspace (multi-repo nesting)

<!-- SCV:WORKSPACE START -->
<!-- EMPTY = single-repo mode (default). SCV behaves exactly as standalone. -->
<!-- A child repo joins a workspace via:  action:sync --join <root-scv-git-url>  (fills the fields below). -->
<!-- Detaching = clearing `root:` (or removing this block) restores single-repo behavior with zero migration. -->
```yaml
repo_id:
role:
root:
workspace:
```
<!-- SCV:WORKSPACE END -->

## SCV template metadata

- Template version: <!-- STANDARD:VERSION -->2.0.0<!-- /STANDARD:VERSION -->
- Last sync: <!-- STANDARD:SYNCED_AT -->UNSET<!-- /STANDARD:SYNCED_AT -->
- Collab tool: `.env`'s `NOTIFIER_PROVIDER` (slack | discord)
