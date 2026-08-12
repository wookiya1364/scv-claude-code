# Claude Code adapter

This directory is the hand-written Claude Code boundary around the pinned SCV
Core payload in `vendor/scv-core/`.

Adapter-owned behavior:

- `.claude-plugin/` marketplace and plugin manifests
- `commands/*.md` frontmatter, including `allowed-tools` and per-command
  `model:` metadata
- `/scv:<action>` invocation syntax and `CLAUDE_PLUGIN_ROOT`
- Claude Code language, skill-discovery, question, install, reload, and update UX
- `scripts/apply-model-policy.sh`, `scripts/update.sh`, and the thin
  `scripts/hydrate.sh`/`scripts/sync.sh` state adapters
- the `adapter/scripts/state-index.sh` delegation shim
- `hooks/hooks.json` — journal-capture hook registration (Core 0.22.0 hook
  seam, `docs/wrapper-integration.md` §6 in scv-core): binds Claude Code's
  `UserPromptSubmit`/`Stop` events to the vendored templates
  `vendor/scv-core/core/template/hooks/on-user-prompt.sh` /
  `on-stop.sh`, exporting `SCV_CORE_ROOT`. The templates themselves (and
  the `journal-append.sh` redaction path they call) are core-owned;
  the journal registration must stay non-blocking and must never write to
  `scv/journal/` directly. The `PreToolUse` / `UserPromptExpansion`
  registrations are a separate seam and are deliberately blocking: they
  point at `template/hooks/guard.sh`, which denies writes no SCV action
  accounts for. Non-blocking is a property of the journal templates, not of
  hooks as a category — see `vendor/scv-core/core/contracts/guard.md`

Core-owned behavior:

- action protocols other than the update and model-policy adapters
- workflow shell helpers, templates, DeckUI, and assets
- host-neutral state inspection, conflict/hydration reporting, and pointer
  finalization in `core/scripts/state-index.sh`
- shared fixtures and regression behavior

New hydrate output is host-neutral: it contains `scv/SCV.md` and no
`scv/CLAUDE.md` or `scv/CODEX.md`. A compatibility pointer is created only
when an approved sync migrates an already-existing legacy index, and only at
that file's existing path. The Claude shim preserves argv and delegates this
contract directly to the pinned Core resolver; it has no second pointer or
conflict implementation.

`scripts/sync-core.sh` materializes a checksummed immutable core release with
`adapter/claude-code.env`, pins it in `core.lock`, and refreshes the legacy
root paths used by existing Claude commands plus the test-facing `protocols/`
projection. Those root paths are generated compatibility projections, not
independent sources of truth. Wrapper and Core releases are independently
versioned: the sync leaves root `VERSION`, the Claude plugin manifest, and the
marketplace catalog entry unchanged. `TEMPLATE_VERSION` is independently
versioned project-state schema.

SCV never fetches core at plugin runtime. Network access is limited to the
maintainer-only sync workflow or an explicit `scripts/sync-core.sh --version`
invocation.
