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

## How SCV talks to you

SCV answers in a fixed shape, so an answer is easy to read before it is
complete: first 1–2 sentences that say what you get, then one example, no code
values (paths, variable names, versions, settings) before you ask, and detail
only when you want it. Identifiers you need to act on — the next command, a
created file — stay exact, after the plain summary.

- The rule lives in every SCV action, and a per-turn hook reminds the host
  agent of it in SCV projects, commands or not.
- Switch: `scv/scv_settings.json` `SCV_PLAIN_LANGUAGE` — absent or `on` keeps it (default);
  `off` turns both the rule and the reminder off. `scv/scv_settings.json` is committed, so
  each teammate can choose.
- Cap: `scv/scv_settings.json` `SCV_PLAIN_MAX_SENTENCES=<n>` raises the first-answer sentence
  cap from 2 to n (positive integer; anything else means 2).
- Hosts without that hook: add the pointer line from the section above to your
  project-root instruction file, so casual conversation reads this file too.

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
├── .gitignore  (scv/scv_settings.json holds SCV settings)
└── (project-specific code: src/, packages/, apps/, etc.)
```

**The big picture**: drop material into `scv/raw/` → `action:promote` refines it into `scv/promote/<slug>/` → `action:work <slug>` implements + tests → on pass, moves to `scv/archive/`.

## Settings

SCV settings live in two files under `scv/`, and nowhere else. The project's
`.env` is **not read** — that is the point of the split: your app's variables and
SCV's settings stopped sharing one file.

| File | What goes in it | Committed? |
|---|---|---|
| `scv/scv_settings.json` | language, notifier provider, PR platform, attachment and GIF options — 23 keys | yes |
| `scv/scv_settings.secret.json` | bot tokens, repo tokens, channel IDs — 13 keys | **no** (git-ignored) |

Start from `scv/scv_settings.example.json`. Nothing breaks without a settings
file — SCV runs on defaults.

**Always write settings through the script.** It puts each key in the right file
on its own, so a token cannot land in the committed one by accident:

```bash
bash "<core>/scripts/settings-set.sh" SCV_LANG=korean
bash "<core>/scripts/settings-set.sh" SLACK_BOT_TOKEN=xoxb-...   # → secret file
```

**Coming from `.env`?** Run this once. It copies only the keys SCV knows, splits
secrets out, and **does not touch your `.env`**:

```bash
bash "<core>/scripts/settings-migrate.sh"
```

Until you do, SCV runs on defaults and says so once per action.

**Updates never overwrite your values.** When SCV ships a new setting, sync adds
only the missing key. A value you set — or deliberately left empty — stays as it is.

## Journal — mark what matters, read it back cheaply

Every turn lands in `scv/journal/`. That file only grows, so finding an old
decision by reading it costs you the whole file — and the context that goes
with it.

Mark the turns that matter as you write them, and read them back by name:

```bash
# writing — the mark and the name are chosen by whoever writes, not guessed later
bash "<core>/scripts/journal-append.sh" --mark decision --key retry-policy "…"

# reading — the journal itself is never scanned
bash "<core>/scripts/journal-read.sh" --list            # what is marked
bash "<core>/scripts/journal-read.sh" --key retry-policy
```

Four marks: `decision` (a direction was set), `plan` (a plan was made or
archived), `blocker` (something was stuck, and why), `pivot` (something was
dropped or changed). Anything else is ignored — the journal write still happens,
and it says so.

The index (`scv/journal/INDEX.tsv`) stores each marked turn's byte position, so
reading one costs that entry, not the file. Same name twice? The newest wins.

**Nothing depends on it.** No index, a broken index, an unknown mark — the
journal write goes through either way. And if someone edits the journal file
directly, the read says the position no longer lines up instead of handing you
the wrong text.

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
- Template digest: <!-- STANDARD:DIGEST -->UNSET<!-- /STANDARD:DIGEST -->
- Collab tool: `scv/scv_settings.json`'s `NOTIFIER_PROVIDER` (slack | discord)
