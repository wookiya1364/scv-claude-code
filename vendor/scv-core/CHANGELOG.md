# Changelog

All notable changes to SCV Core are documented here.

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
