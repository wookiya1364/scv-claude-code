# scv/SCV.md — SCV workflow index

> **This file is the index and rules for the SCV workflow.** Project-root
> instruction files are **never touched by SCV** and remain user-owned.
> Everything SCV needs is under `scv/`.

## Hydrate — one path

- `bash hydrate.sh init .`
- Seeds only the SCV workflow files (this index, `PROMOTE.md`, `REPORTING.md`, `raw/`, `promote/`, `archive/`). There is no standard-doc scaffolding step — `action:promote` and `action:work` are usable immediately, on new and existing projects alike.
- External docs (Confluence etc.) hook in via `refs:` in PLAN.md frontmatter. Facts the model can derive from the codebase are not pre-documented; decisions worth keeping go to `scv/DECISIONS.md`.

## Top-level rules (immutable)

1. **No speculation**: never fill a plan section without an explicit user answer.
2. **One at a time**: complete one section → user confirms → next.

## How SCV talks to you

- **You don't have to type commands.** With `scv/scv_settings.json`
  `SCV_ALWAYS_ON` absent or `on` (default), a per-turn hook routes free
  conversation through the help action — a plain message gets the same Mode
  decision (diagnosis / conversation / archive search) as an explicit command.
  `off` limits SCV to explicit commands. A turn already running an SCV action
  is never hijacked. Two more switches on the same hook: `SCV_FORCE_HELP`
  (default `on`, carries the project diagnosis each turn) and
  `SCV_DELEGATE_EFFORT` (default `off`; `on` sends deep questions to a
  background investigator when the host ships one — the session's effort is
  never changed).
- **Answers lead plain.** First 1–2 sentences of what you get, then one
  example, code values only when asked. Switch: `SCV_PLAIN_LANGUAGE=off`;
  sentence cap: `SCV_PLAIN_MAX_SENTENCES=<n>`.
- Hosts without that hook: add this line to your project-root instruction file
  so casual conversation still finds SCV:
  ```
  > This project uses SCV — see `scv/SCV.md` for workflow details.
  ```

## Workflow documents

| Document | Role |
|---|---|
| `scv/PROMOTE.md` | raw → promote → archive convention. Folder names, PLAN/TESTS, Related Documents. |
| `scv/REPORTING.md` | Collab-tool mapping (Slack/Discord) — read by `action:report`. |

## Project directory layout

```
project-root/
├── <project instructions>        # User-owned (SCV doesn't touch) — optional
├── scv/
│   ├── SCV.md PROMOTE.md REPORTING.md
│   ├── readpath.json             # raw change-tracking (auto-updated)
│   ├── promote/<YYYYMMDD>-<author>-<slug>/   # PLAN.md + TESTS.md + extras
│   ├── archive/<slug>/           # done work + ARCHIVED_AT.md (auto)
│   ├── raw/                      # free-input space; consumed → raw/stale/
│   ├── scv_settings.json         # settings (auto-created, committed)
│   └── scv_settings.secret.json  # tokens (auto-created, git-ignored)
└── (project code: src/, apps/, …)
```

**The big picture**: drop material into `scv/raw/` (or just talk) →
`action:promote` refines it into `scv/promote/<slug>/` → `action:work <slug>`
implements + tests → on pass, moves to `scv/archive/` and joins regression.

## Settings

Two files under `scv/`, and nowhere else — the project's `.env` is **not read**.

| File | Holds | Committed? |
|---|---|---|
| `scv/scv_settings.json` | language, always-on / plain-language switches, notifier, PR platform, attachment and GIF options — 27 keys | yes |
| `scv/scv_settings.secret.json` | bot tokens, repo tokens, channel IDs — 13 keys | **no** (git-ignored) |

**The file creates itself.** When an action starts and the file is missing,
SCV writes it with every key present — real defaults and a `_doc` description
per key. The secret file is created only where its git-ignore is guaranteed.
Nothing breaks without a settings file — SCV runs on defaults.

**Always write settings through the script** — it routes each key to the right
file, so a token cannot land in the committed one:

```bash
bash "<core>/scripts/settings-set.sh" SCV_LANG=korean
bash "<core>/scripts/settings-set.sh" SLACK_BOT_TOKEN=xoxb-...   # → secret file
```

Coming from `.env`? `bash "<core>/scripts/settings-migrate.sh"` once — it
copies only the keys SCV knows and never touches your `.env`. SCV warns once
only when a `.env` SCV value differs from the settings file.

**Updates never overwrite your values** — sync adds only missing keys.

## Four places things get written — and which is which

| Where | What lives there | Who writes it |
|---|---|---|
| `scv/conversations/` | An idea still being shaped; grows across turns, becomes a plan. | you, deliberately |
| `scv/promote/` · `scv/archive/` | The plan itself, and what actually happened. | the promote and work actions |
| `scv/DECISIONS.md` | The decision — what won, why, what was discarded. Append-only. | **automatic**, at plan approval / archive / obsolete |
| `scv/journal/` | Every turn, verbatim (redaction-filtered). | the hooks, always |

One line: **a conversation is a draft of something not yet decided; a decision
is the thing once it is.** The journal is the raw tape underneath both.

Useful commands on top of these records:

```bash
bash "<core>/scripts/record-read.sh" --key <name>     # read one decision back
bash "<core>/scripts/recap.sh"                        # after clearing context: in-flight, recent decisions, blockers — writes nothing
bash "<core>/scripts/journal-append.sh" --mark blocker --key <name> "…"   # mark a turn yourself (blocker | pivot | plan)
```

## Work procedure

1. Understand the requirement → read the plan under `scv/promote/` (and its Related Documents).
2. Implement → test → fix loop (`action:work <slug>`, or `action:codegen <slug>` for TDD-first).
3. On phase completion, `action:report "<phase>" <status>` → send to the collab tool.

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
