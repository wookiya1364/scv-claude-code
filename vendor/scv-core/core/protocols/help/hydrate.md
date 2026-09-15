# help — Mode A — hydrate offer and diagnosis re-presentation

Read from `/scv:help` at "Step A0 — Auto-hydrate on first run". Follow it, then return to the protocol where you left off.

> `<plugin root>` below means the directory two levels above this file (this file lives at
> `<plugin root>/protocols/help/`; the helper scripts live at `<plugin root>/scripts/`). Branch
> files are read as plain text, so no path placeholder is expanded here — derive the absolute
> path from where you read this file.

#### Step A0 — Auto-hydrate on first run (v0.10.0+)

If the helper output contains the line `This directory is not hydrated yet.`, the project hasn't been initialized. Don't just relay the script's instructions — offer to hydrate now.

**Legacy-index guard:** the helper resolves the shared `scv/SCV.md` first and
then any legacy index names declared by the wrapper profile. If any resolved
index exists together with `scv/PROMOTE.md`, the project is hydrated. Continue
with diagnosis. Never infer "not hydrated" merely because one host-specific
filename is absent.

The help action is read-only unless the user explicitly accepts one of the
hydrate choices below. It must never run `sync`, migrate or rename an index,
create `scv/SCV.md`, or turn a legacy index into a pointer. Do not hand off to
`sync` as a side effect of diagnosis. Cross-wrapper migration requires a
separately invoked sync action and its preview/confirmation gate.

If the helper emits `STATE_INDEX_CONFLICT:`, report the listed files and
continue only with read-only diagnosis. Do not choose a winner or offer an
automatic rewrite.

Ask the user for confirmation:

```
Question: "This project isn't hydrated yet. Set it up now?"
options:
[1] "Yes — set it up (recommended)"
    description: "Seeds only the SCV workflow files (scv/SCV.md, scv/PROMOTE.md, scv/REPORTING.md, scv/raw/, promote/, archive/). /scv:promote and /scv:work are usable immediately, on new and existing projects alike."
[2] "Not now — show me the manual command"
    description: "Skip automatic setup. I'll print the bash command and you can run it yourself when ready."
```

On choice [1]: run `bash "<plugin root>/scripts/hydrate.sh" init .`. After
hydrate completes, re-run `bash "<plugin root>/scripts/help.sh"` and present
the new diagnosis. On [2]: re-present the manual command from the helper
output and stop.

#### Step A1 — Re-present diagnosis

If hydrate is already complete (or just completed in Step A0), re-present the rest of the script's output in the resolved language: translate descriptions, recommended next-step explanations, and section headers. Keep skill invocation names (`/scv:help`, `/scv:promote`, …), file paths, and SCV technical terms (`promote`, `archive`, `orphan branch`, `epic`, `supersedes`) as-is. **If `UNFINISHED_CONVERSATIONS:` is non-empty**, also list them in your output: "You have N unfinished conversation(s). Run `/scv:help` with an idea (e.g., `/scv:help \"continue the refund button\"`) to resume — or start a new one."

**Mention `/scv:codegen` when applicable**: if the recommended next step is `/scv:work <slug>` AND that slug's `TESTS.md` already contains concrete acceptance criteria (i.e., not just placeholders), append one line: "Or, if you trust the tests to define behavior, try `/scv:codegen <slug>` — TDD-first variant (v0.11.0+, experimental): TESTS drives code Red→Green per case, archive/PR is handed off to `/scv:work`." Skip this line if TESTS.md is empty/placeholder or if the slug is UI-heavy (where TDD-first is awkward).

**Multi-repo workspace (when present)**: if the script output contains a `Workspace:` diagnosis line (this repo is a `CHILD` or `ROOT`), relay it. If it shows a `⮕ Workspace: N incoming handoff(s)` block, treat that as a **top recommended next action** in the resolved language: another repo declared this repo needs corresponding dev — guide the user to `/scv:status` to review, then `/scv:promote` (scaffolds PLAN+TESTS from the handoff) and `/scv:codegen <slug>` to implement. If the line says the root is *not synced locally*, tell them to `git pull` the umbrella repo first. For a plain single repo (no `Workspace:` line) say nothing about workspaces.
