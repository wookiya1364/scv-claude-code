# Changelog

All notable changes to SCV Core are documented here.

## [0.21.0] - 2026-08-04

### Added

- Offline-ready 기획서 decks: after the doc build, `deck.sh` bakes every
  mermaid diagram into the HTML as inline SVG via a locally installed headless
  Chrome (`deckdoc/static-mermaid.mjs` + render.mjs's `?scv-static` build
  mode), so the deck opens fully rendered with no CDN at view time.
  Best-effort by contract — without Chrome or network the deck keeps the
  existing CDN + text-fallback rendering; opt out with `--no-static` or
  `SCV_DECK_STATIC=0`.

- Raw-doc lifecycle: `action:promote` Step 8 now runs `readpath.sh consume`,
  which moves consumed originals (content unchanged) into `scv/raw/stale/` and
  records which promote slugs used each doc in `scv/readpath.json`'s new
  `ref_docs` map (schema v2; a doc reused by several features accumulates all
  their slugs plus `ref_commit`/`consumed_at`). Files still directly under
  `scv/raw/` are therefore exactly the never-promoted **unused** docs.
- New `readpath.sh` subcommands: `consume`, `unused`, `refs`,
  `lifecycle-counts`, and `outdated` — a content-staleness heuristic that flags
  consumed docs mentioning repo files changed since their `ref_commit`
  (`OUTDATED-CANDIDATE`), with semantic verification delegated to the host
  agent in `action:promote` / `action:status`.
- `action:status` shows the unused/consumed split, per-doc `ref_docs` slugs,
  and outdated candidates; `action:help`'s banner surfaces the unused count;
  `promote-helper.sh` emits `RAW_STALE_COUNT` / `RAW_OUTDATED_COUNT` and no
  longer counts consumed docs toward the split heuristic.
- `action:status` documents a one-time legacy backfill: retro-consuming raw
  docs referenced by `raw_sources:` of existing promote/archive plans.

### Fixed

- Deck mermaid diagrams were near-invisible (white init-palette edges on the
  renderer's light card). The doc renderer now emits the
  `scv-mermaid-contrast` overrides (transparent diagram card, theme-variable
  edges and edge labels) and the promote protocol's `%%{init}%%` template
  aligns with the deck's own theme tokens (`#9096a8`/`#e7e9f0`/`#171922`), so
  architecture diagrams stay readable in both light and dark themes.

### Changed

- readpath schema is now v2 (`files` + `ref_docs`, each entry also recording
  its pre-move `origin`). v1 state files remain readable, `update` preserves
  `ref_docs`, and v1 readers ignore the new block. Caveat: a **v1** `update`
  rewrites the file without `ref_docs` — mixed-version teams should upgrade
  wrappers together.
- `consume` is fail-closed: preflight validates every path (normalization of
  `//`·`/./` variants, raw-dir prefix, no `..`, no symlinked leaf **or path
  component**, no duplicate arguments, README excluded, no
  quote/backslash/control characters) before any file moves. A shared source
  that an earlier promote folder already moved is remapped via its recorded
  `origin` (`REMAPPED` output) instead of failing.
- The ref_docs parser tolerates pretty-printed state files (e.g. after
  `jq .`) via brace-depth tracking, and empty TSV fields use a `-` placeholder
  so IFS tab-collapsing can no longer shift columns (previously an empty
  `ref_commit` silently corrupted the state on the next `update`).
- `diff`/`status-counts` no longer crash on filenames containing spaces
  (pre-existing `compute_diff` word-splitting bug); filenames with quotes,
  backslashes, tabs, or newlines are skipped by `scan`/`diff` with a warning
  and rejected by `consume` (the narrow no-jq schema cannot represent them).
- `action:sync` now propagates `scv/raw/README.md` (merge_policy `overwrite`)
  so existing projects receive the raw lifecycle guide instead of keeping the
  old "raw files are never moved" text that contradicts Step 8's stale-move.

## [0.20.6] - 2026-07-29

### Fixed

- Centralized canonical, legacy, conflict, and broken-pointer state resolution
  in one host-neutral Core entrypoint so Claude Code and Codex cannot classify
  the same project differently.
- Standardized compatibility pointers on the exact
  `SCV:HOST-POINTER target=SCV.md` marker and made both host directions share
  the same inspect, preview, backup, and pointer-finalization behavior.
- Kept projects with readable state and `scv/INTAKE.md` classified as hydrated
  during a fail-closed conflict, preventing a conflict from being mistaken for
  an unhydrated project.

### Security

- Made canonical seeding no-replace and revalidated every active legacy file
  against its recoverable backup before publishing any pointer.
- Preserved read-only and dry-run trees byte-for-byte across the full
  canonical/legacy/pointer conflict matrix.

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
