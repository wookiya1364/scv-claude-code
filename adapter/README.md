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
- read-only state resolution and explicit migration in
  `adapter/scripts/state-index.sh`

Core-owned behavior:

- action protocols other than the update and model-policy adapters
- workflow shell helpers, templates, DeckUI, and assets
- shared fixtures and regression behavior

New hydrate output is host-neutral: it contains `scv/SCV.md` and no
`scv/CLAUDE.md` or `scv/CODEX.md`. A compatibility pointer is created only
when an approved sync migrates an already-existing legacy index, and only at
that file's existing path.

`scripts/sync-core.sh` materializes a checksummed immutable core release with
`adapter/claude-code.env`, pins it in `core.lock`, and refreshes the legacy
root paths used by existing Claude commands plus the test-facing `protocols/`
projection. Those root paths are generated compatibility projections, not
independent sources of truth. Wrapper and core releases are lockstep: the sync
also updates root `VERSION`, the Claude plugin manifest, and the marketplace
catalog entry. `TEMPLATE_VERSION` is independently versioned project-state
schema.

SCV never fetches core at plugin runtime. Network access is limited to the
maintainer-only sync workflow or an explicit `scripts/sync-core.sh --version`
invocation.
