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

The wrapper release is lockstep with the pinned core release. A successful
sync updates root `VERSION`, `.claude-plugin/plugin.json`, and the `scv`
marketplace entry together. `TEMPLATE_VERSION` remains independent because it
tracks the schema stamped into hydrated project state.

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

Root-level `scripts/`, `template/`, `DeckUI/`, and `assets/` remain for
backwards compatibility with existing `${CLAUDE_PLUGIN_ROOT}` command paths.
`protocols/` and the common portion of `tests/` are projected for shared
regression. They are regenerated from `vendor/scv-core/core/` and checked by
`scripts/verify-core.sh`; edits belong in `scv-core`, not in the projection.

## Maintainer commands

```bash
# Test a local core checkout without changing the pin
./scripts/sync-core.sh --source ../scv-core --dry-run

# Pin and project a local core checkout
./scripts/sync-core.sh --source ../scv-core

# Pin an immutable public release
./scripts/sync-core.sh --version 0.20.0

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
actionable error when branch push or PR creation is denied, and it always runs
the complete validation suite before proposing a change.
