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
- **You don't have to type commands to reach SCV (0.35.0+).** With
  `SCV_ALWAYS_ON` absent or `on` (default), the same per-turn hook routes free
  conversation through the help action — a plain message gets the same Mode
  decision (diagnosis / conversation / archive search) as an explicit command.
  `off` limits SCV to explicit commands. A turn already running an SCV action
  is never hijacked.
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
| `scv/scv_settings.json` | language, plain-language / always-on switches, notifier provider, PR platform, attachment and GIF options — 27 keys | yes |
| `scv/scv_settings.secret.json` | bot tokens, repo tokens, channel IDs — 13 keys | **no** (git-ignored) |

**The file creates itself (0.34.0+).** When an action starts and the file is
missing, SCV writes it with every key present — real defaults filled in and a
`_doc` description per key, so you can see what is settable by opening the
file. The secret file is created only where its git-ignore is guaranteed.
Nothing breaks without a settings file — SCV runs on defaults.

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

SCV warns once only when a `.env` SCV value differs from the settings file.

**Updates never overwrite your values.** When SCV ships a new setting, sync adds
only the missing key. A value you set — or deliberately left empty — stays as it is.

## Four places things get written — and which is which

They overlap enough to be confusing, so here is the split. Only one of them
asks anything of you.

| Where | What lives there | Who writes it |
|---|---|---|
| `scv/conversations/` | An idea still being shaped. It grows across turns and gets promoted into a plan. | you, deliberately |
| `scv/promote/` · `scv/archive/` | The plan itself, and what actually happened. | the promote and work actions |
| `scv/DECISIONS.md` | The decision — what won, why, what was discarded. Append-only. | **automatic**, at three moments |
| `scv/journal/` | Every turn, verbatim. | the hooks, always |

One line: **a conversation is a draft of something not yet decided; a decision
is the thing once it is.** The journal is the raw tape underneath both.

### Decisions write themselves

Three moments already decide something, so those are the three that record it:
a plan is approved, a plan is archived, a scenario is ruled obsolete. Nothing
there is a judgement call — the actions call the script:

```bash
bash "<core>/scripts/decisions-append.sh" --title "…" --verdict adopted --why "…"
```

The script keeps the format identical across all three and records **where** the
entry sits, so one decision can be read back without opening a log that is
already hundreds of lines:

```bash
bash "<core>/scripts/record-read.sh" --key <name>
```

### After clearing context

```bash
bash "<core>/scripts/recap.sh"
```

What is in flight, the last few decisions, what is blocked, what is still open —
assembled from what is already on disk. **It writes nothing.** Under 40 lines by
design: a recap you skim is a recap you read.

Reach for the status action instead when you want the full picture, including
raw-material changes.

### Marking a journal turn yourself

Decisions cover the moments that go through the actions. For the ones that do
not — you got unstuck, or you dropped an approach mid-conversation — mark the
turn as you write it:

```bash
bash "<core>/scripts/journal-append.sh" --mark blocker --key <name> "…"
```

`blocker`, `pivot`, `plan`. This is the one part that asks something of you, and
it is optional: the journal records the turn either way.

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
