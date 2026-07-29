# SCV Core integration

`scv-claude-code` is the Claude Code adapter for the host-neutral
[`scv-core`](https://github.com/wookiya1364/scv-core) workflow engine.

## Release flow

```text
scv-core vX.Y.Z release
        │
        ▼
scheduled/manual core-sync workflow
        │  verify release SHA-256
        │  materialize adapter/claude-code.env
        ▼
chore/core-vX.Y.Z → develop PR
        │  core lock + adapter + regression checks
        ▼
develop → stage → main
```

The wrapper vendors an immutable payload rather than resolving `main` or
downloading code when a command runs. `core.lock` records both the original
source payload digest and the Claude-materialized payload digest.

Wrapper and Core versions advance independently. Root `VERSION`,
`.claude-plugin/plugin.json`, and the `scv` marketplace entry are one
adapter-release unit and must agree with each other; Core sync never rewrites
them. The vendored `VERSION` and `core.lock` identify the independent Core pin.
`TEMPLATE_VERSION` follows Core because it tracks the schema stamped into
hydrated project state. The wrapper and the Core pin recorded in `core.lock`
can therefore advance on different release schedules.

The digest fields are intentionally distinct:

- `source_payload_sha256`: canonical, host-neutral exported payload
- `payload_sha256`: payload after the Claude profile is materialized
- `artifact_sha256`: downloaded release tarball (`null` for a local checkout)
- `source_commit`: exact commit from which core was exported

## Ownership boundary

Core owns workflow semantics, shared helpers, templates, DeckUI, assets, and
common tests. The Claude adapter owns command discovery/frontmatter, slash
syntax, tools and questions, per-command model metadata, plugin installation,
self-update guidance, and host-specific paths.

Core protocols use neutral argument tokens. The Claude profile declares
`SCV_ARGUMENT_STYLE=template-string`, so user text is exposed to the model as
Claude Code's `$ARGUMENTS`; Codex uses its argv-array style in the sibling
wrapper. Materialized Claude protocols never place `$ARGUMENTS` inside a
pre-model ```` ```! ```` shell block. Claude first parses the prompt data, then
calls an allowed helper through the Bash tool with separately quoted arguments.
The wrapper contract scans every generated command and protocol for violations.

Newly hydrated projects keep canonical workflow state only in `scv/SCV.md`;
Claude and Codex hydrate the same byte-identical tree. Readers accept legacy
`scv/CLAUDE.md` or `scv/CODEX.md` state without mutating it, so an existing
project is immediately usable when Claude Code and Codex alternate on the same
repo. Migration is an explicit sync operation. Only a legacy file that already
exists is backed up and replaced by a small pointer to `SCV.md`; absent host
pointers are never created. Conflicting canonical and legacy state must stop
instead of silently choosing one.

State inspection and migration are resolved once in the pinned Core
`core/scripts/state-index.sh`; wrapper adapters only preserve argv and delegate.
Pointers are recognized solely by the exact line
`<!-- SCV:HOST-POINTER target=SCV.md -->`, independent of host-specific header
prose. A readable canonical or active legacy index together with `INTAKE.md`
remains hydrated even when divergent active indexes cause an rc 4 conflict.
A pointer without its canonical target remains broken and unhydrated.

Root-level `scripts/`, `template/`, `DeckUI/`, and `assets/` remain for
backwards compatibility with existing `${CLAUDE_PLUGIN_ROOT}` command paths.
`protocols/` and the common portion of `tests/` are projected for shared
regression. They are regenerated from `vendor/scv-core/core/` and checked by
`scripts/verify-core.sh`; edits belong in `scv-core`, not in the projection.

## Transaction and local-data boundary

`scripts/sync-core.sh` takes a repository-local owner lock, rejects unfinished
transactions, validates the worktree, and verifies all provenance before its
first live rename. Release sync binds the requested tag to payload `VERSION`,
repository, exact source commit, artifact SHA-256, and both canonical and
materialized manifest/payload digests.

The candidate and backup are staged on the repository filesystem so every
install step is a rename. An EXIT/error/signal handler restores paths in
reverse order. If any restore fails, the transaction directory is retained
and its recovery path is printed instead of deleting the only backup.

Before replacing the legacy in-tree DeckUI, the candidate Core
`deck-runtime.sh migrate` command copies known mutable runtime entries into
the external, source-payload-namespaced cache. Migration is additive while the
destination has no conflicting entry. When another host already populated the
same cache with different data, the persistent legacy migration treats that
cache as authoritative and skips the entire legacy source, including equal
and missing entries, so two hosts are never partially mixed. The old DeckUI
is never modified; a later wrapper rollback therefore never depends on
undoing cache writes.

Core-owned dirty files and local-only files under wholesale replacement paths
fail closed. DeckUI is the explicit exception: every ignored or untracked
runtime path is inventoried from Git and moved across the swap, provided it
does not collide with the new Core payload. The projection writer itself can
write only to an authorized transaction-stage descendant; direct writes to
the live wrapper are rejected, as are symlinks anywhere in that stage tree.
Core-owned live files are compared directly with stage-0 index blobs using
Git's clean-filter semantics, so stat-cache/racy-clean shortcuts cannot hide
content changes. Repository-relocating Git environment variables and Deck
cache paths overlapping the repository, temporary download, transaction, or
legacy migration tree fail closed. The transaction suite runs on Linux and
macOS.

## Maintainer commands

```bash
# Test a local core checkout without changing the pin
./scripts/sync-core.sh --source ../scv-core --dry-run

# Pin and project a local core checkout
./scripts/sync-core.sh --source ../scv-core

# Pin an immutable public release
./scripts/sync-core.sh --version X.Y.Z

# Verify lock, checksums, API compatibility, profile, and projection
./scripts/verify-core.sh
```

The workflow runs nightly, can be started manually, and accepts a
`scv-core-released` repository dispatch whose `client_payload.version` is the
released version. The nightly schedule remains the secret-free fallback if
the core repository cannot send dispatch events.

The workflow uses the built-in `GITHUB_TOKEN` by default. Repository settings
must allow GitHub Actions to create pull requests. A fine-grained
`SCV_CORE_SYNC_TOKEN` with repository **Contents: write** and **Pull requests:
write** access can be configured instead; it also allows the pushed branch and
PR events to trigger normal downstream workflows. The workflow emits an
actionable error when branch push or PR creation is denied. It runs the full
cross-platform smoke preflight before proposing a change; the downstream PR
is the single source of merge-gating checks.

## CI lanes

Normal pull requests run the same fast contract, shell, state-adapter, and
shared regression smoke on Ubuntu and macOS. The 2,000-line sync atomicity
suite is additionally enabled on Ubuntu only at the entry PR into `develop`
and only when updater, projection, atomic-swap, or atomicity-test files
changed. Promotion PRs from `develop` to `stage` and `stage` to `main` run
smoke only, and their merge pushes do not repeat the PR suite.

The main-branch push is the release gate: one full macOS job runs smoke plus
the complete atomicity suite. This retains coverage for BSD utilities,
filesystem modes, and macOS rename/copy behavior without executing the same
expensive suite four times for every promotion. Concurrency cancels stale
runs when a PR head changes. The model-policy cross-OS workflow likewise runs
on its PR once instead of repeating after the main merge.
