# Changelog

All notable changes to SCV Core are documented here.

## [0.20.5] - 2026-07-29

### Changed

- Kept legacy Deck runtime migration strict by default and added the explicit
  `migrate --from LEGACY_DECKUI --reuse-existing` opt-in for persistent legacy
  sources.
- Made cache reuse authoritative and all-or-none: if preflight finds any
  pre-existing destination that differs from its legacy source, the entire
  legacy source is skipped, including equal and missing destinations. With no
  mismatch, migration retains its existing additive behavior.
- Required ephemeral existing-vendor recovery to remain strict so a wrapper
  cannot discard runtime data when that vendor is removed after a successful
  swap. Core API remains `1`.

### Security

- Preflight now evaluates every eligible runtime entry before any copy or
  authoritative-reuse decision. A destination collision that appears after
  preflight still fails closed instead of changing policy mid-transaction.

## [0.20.4] - 2026-07-28

### Security

- Anchored the Deck runtime cache base, payload namespace, target, staging,
  migration destinations, installation, and cleanup to verified directory
  descriptors opened with no-follow semantics.
- Made lock acquisition install a complete owner record through an atomic
  no-replace rename, and bound stale quarantine and release to the original
  lock inode and owner token.
- Added deterministic late-symlink, ancestor-replacement, quarantine-collision,
  and release-race regressions that assert external sentinels remain unchanged.

## [0.20.3] - 2026-07-28

### Fixed

- Made first-use and migration installs in the shared DeckUI cache use
  platform-native atomic no-replace renames on Linux and macOS.
- Rejected cache/legacy overlap before initialization and opened every
  migration destination ancestor without following links.
- Limited stale lock reclamation to a valid dead-owner record with no
  unexpected lock data; malformed or surprising state is preserved and fails
  closed.

## [0.20.2] - 2026-07-28

### Fixed

- Moved mutable DeckUI dependencies, build output, and generated deck data out
  of the immutable Core/plugin tree into a payload-keyed external cache.
- Added an idempotent legacy DeckUI migration that preserves pnpm links,
  generated decks, and build output without deleting or rewriting the source.
- Prevented wrapper Core replacement from treating DeckUI runtime data as
  distributable payload and removed excluded empty deck directories from
  exports.
- Expanded the cross-host state matrix to cover approved `CLAUDE.md` and
  `CODEX.md` migrations, both supported readpath encodings, workspace markers,
  and mutating conflict failure with byte-for-byte preservation.

### Security

- Added atomic cache initialization, per-payload locking, collision detection,
  unsafe target rejection, and link/special-file checks for immutable DeckUI
  inputs.

## [0.20.1] - 2026-07-28

### Fixed

- Materialized source-checkout metadata links as regular files in exported and
  released payloads so strict wrapper archive validation can reject every link
  and special-file entry consistently.
- Added export, vendoring, and release hygiene checks that fail if any
  non-regular entry is present.

## [0.20.0] - 2026-07-28

### Added

- Extracted the shared SCV protocols, scripts, template, DeckUI, assets, docs,
  and regression tests into a host-neutral Core payload.
- Added a strict Core API v1 host-profile contract and deterministic
  materialization for template-string and argv-array hosts.
- Added verified export, vendoring, lock generation, deterministic release
  artifacts, and SHA-256 integrity metadata.
- Added legacy `CLAUDE.md`/`CODEX.md` read compatibility with explicit,
  non-destructive migration to `SCV.md`.
- Added CI for contracts, host-neutrality, state migration, shared regression,
  DeckUI, cross-platform shell behavior, deterministic artifacts, and branch
  flow.

### Changed

- Made `scv/SCV.md` the canonical shared state index.
- Moved host installation (`update`) and model selection (`set-models`) behind
  adapter-owned boundaries.
- Made sync fail closed when independent state indexes diverge and preserve
  project-local metadata and existing lifecycle status during migration.

### Security

- Host profiles are parsed as data without `source` or `eval`.
- Exports reject escaping or directory symlinks and exclude development
  dependencies, build outputs, caches, and temporary files.
