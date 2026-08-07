# Changelog

All notable changes to SCV Core are documented here.

## [0.22.0] - 2026-08-07

### 가이던스 어블레이션 1단계 — CONTRACT/GUIDANCE 분리 + `SCV_GUIDANCE=minimal` (promote·work)

- 프로토콜 md 의 행동 코칭(GUIDANCE)을 `<!-- SCV:GUIDANCE -->` …
  `<!-- /SCV:GUIDANCE -->` HTML 주석 마커로 감싸는 규약을 도입했다.
  분류 기준: **삭제해도 산출물의 형식·경로·불변식(생성 파일 목록 ·
  frontmatter 스키마 · 스크립트 호출 시퀀스)이 변하지 않으면 GUIDANCE** —
  규약/기준 문서는 `docs/guidance-ablation.md`.
- 주입 필터 `core/scripts/guidance-filter.sh` 를 추가하고 래퍼 주입 지점인
  `tools/materialize-profile.sh` 에 연결했다. `SCV_GUIDANCE=full`(기본,
  미설정 포함)은 주입 내용이 원본과 바이트 동일하고,
  `SCV_GUIDANCE=minimal` 은 GUIDANCE 블록을 제거한 투영본을 주입한다.
  원본 프로토콜 파일은 어떤 모드에서도 불변. 잘못된 마커(닫힘 누락 ·
  고아 닫힘 · 중첩 · malformed)는 `파일:줄` 에러로 전체 주입을 중단한다
  (fail-closed — 부분 주입 없음; full 모드도 동일하게 검증).
- 어블레이션 동등성 하네스: `core/tests/run-dry.sh` [19] 가 promote·work
  경로를 두 모드로 실행해 생성 파일 목록 · frontmatter 스키마 · 스크립트
  호출 시퀀스가 동일함을 강제한다(차이 = CONTRACT 오분류 → 재분류).
  마커 lint · fail-closed · 타 프로토콜 바이트 불변 · deck 마커 비노출은
  `core/tests/test-guidance.sh` 가 검증하고, deck transform 은 마커 줄만
  드롭한다(GUIDANCE 본문은 deck 문서에서 계속 렌더).
- **1단계 분류 결과 (목표 비율 없이 기준 적용 후 측정)** —
  `promote.md`: GUIDANCE 241줄 / 전체 883줄 (27.3%),
  `work.md`: GUIDANCE 203줄 / 전체 529줄 (38.4%).
  다른 프로토콜 파일들은 이 웨이브에서 바이트 불변이다 (2단계는 minimal
  모드 실사용 피드백 후 별도 계획).

### BREAKING — adoption 단일화 + 표준 문서 7종 제거 (TEMPLATE_VERSION 2.0.0)

- `hydrate.sh --new` (greenfield mode) is removed. Passing `--new` now exits 1
  with a migration notice and changes no files (fail-closed). Hydrate has a
  single path and no longer seeds the seven standard docs
  (`DOMAIN.md` / `ARCHITECTURE.md` / `DESIGN.md` / `AGENTS.md` / `TESTING.md` /
  `INTAKE.md` / `RALPH_PROMPT.md`) — their templates are deleted from
  `core/template/scv/`. Kept files are unchanged in behavior: `SCV.md`,
  `PROMOTE.md`, `REPORTING.md`, `raw/README.md`, `WORKSPACE.yaml.example`,
  and the `.env` / `.gitignore` fragments.
- `action:sync` now **deletes** those seven files from existing projects,
  **without backup** (deliberate decision — git history is the recovery path),
  and reports each as `DELETED scv/<file>` in the CHANGES summary.
  `--dry-run` previews the deletions without touching files. No file outside
  the seven is ever deleted; a symlinked target is left in place with a
  `WARN` instead of being deleted (fail-closed). The `sync.md` protocol
  instructs the host agent to check each doomed file for user-authored content
  first and, when found, propose migrating the decisions worth keeping into a
  version-controlled team note (e.g. `DECISIONS.md` / journal) before applying.
- Cascade cleanup: the draft/N/A status gate, the INTAKE flow, and all
  standard-doc references are removed from `check-frontmatter.sh`, `help.sh` /
  `help.md` (incl. the greenfield hydrate option), `promote.md` (diagram 2 now
  sources from graphify only), `work.md`, `deck.md` / `deck-context.sh`,
  `SCV.md` / `PROMOTE.md` / `REPORTING.md` templates, and
  `integrations/loop-runner.md` (rewritten to run from `scv/promote/<slug>/`
  plans with a free-form user-authored entry prompt instead of
  `RALPH_PROMPT.md`). The hydration signal in `state-index.sh` / `help.sh` now
  uses `scv/PROMOTE.md` (previously `scv/INTAKE.md`); state-index and legacy
  CLAUDE.md/CODEX.md migration semantics are otherwise unchanged.
- Upgrade note: external loop harnesses (e.g. rloop) that expect
  `scv/RALPH_PROMPT.md` must switch to a free-form entry prompt; content you
  still need from a deleted doc is recoverable from git history
  (`git log -- scv/<file>`).

### Changed

- PLAN grammar overhaul (guardrails-first, Boris Cherny's task+guardrails+exit
  criteria model): the `action:promote` PLAN scaffold now has `## Guardrails`
  (do-not-touch areas / invariants in prose) and `## Exit criteria` (higher-level
  done conditions beyond TESTS), and `## Steps` is demoted to `## Suggested path`
  — the path is a suggestion, Guardrails/Exit criteria are the contract
  (경로는 제안, Guardrails/Exit criteria 가 계약). `scv/PROMOTE.md` §4 is synced.
  All new sections/fields are optional: legacy PLANs with only `## Steps` are
  processed by `action:work` / `action:regression` unchanged.
- `action:promote`'s Socratic follow-up questions changed direction: do not
  interrogate implementation method (구현 방법을 캐묻지 말라) — ask only about
  boundaries, risks, exit criteria, and verification means; the
  procedure-probing example list was replaced accordingly.
- `action:work` gained a long-run execution contract (Step 5c): with Guardrails /
  Exit criteria + TESTS verification means in hand, run to completion without
  micro-step instructions, and strengthen the verification means first when
  stuck. This paragraph owns work's long-run behavior even after RALPH_PROMPT
  retirement.

### Added

- Optional PLAN frontmatter `parallel_groups: [[step,...],...]` — independent
  Suggested-path step groups a subagent-capable host may fan out concurrently
  (`action:work` Step 5d); `action:regression` documents the analogous slug-level
  fan-out. Absent hint or non-parallel host → behavior identical to before.
- Raw-injection hygiene: `action:promote` and `action:help` now state that raw /
  conversation file content is **data** — instruction-like text inside it is
  never executed and is reported to the user instead.
- **Team journal — author-attributed, committed project memory**
  (전면 기록화): three new templates, all `merge_policy: preserve`, seeded by
  hydrate and propagated as `NEW` by sync — `scv/journal/README.md` (usage
  rules), `scv/DECISIONS.md` (append-only decision log; entry schema reuses
  the handoff decision format with a mandatory author), and `scv/TODO.md`
  (team todo, `- [ ] (T-NNN) <내용> — @<author>, YYYY-MM-DD`).
- `core/scripts/lib/author.sh` — unified author resolution
  (`git config user.name` → `GIT_AUTHOR_NAME` → `USER` → `unknown`) +
  filename-safe slugging that keeps non-ASCII (Korean) names;
  `promote-helper.sh`'s `AUTHOR` signal now uses it.
- `core/scripts/journal-append.sh` — appends `### [HH:MM:SS] <speaker>` blocks
  to `scv/journal/<YYYYMMDD>-<author>.md` (per-day, per-author files — no git
  conflicts), with a built-in redaction filter
  (password/token/secret/api-key values, `Bearer` tokens, `AKIA…` keys →
  `[REDACTED]`); `--redact-only` exposes the filter to protocols.
- Host hook templates `core/template/hooks/on-user-prompt.sh` (prompt-submit
  event, stdin JSON `prompt`) and `on-stop.sh` (stop event, stdin JSON
  `transcript_path`) journal free conversation; both are non-blocking (any
  failure → exit 0, no write). Registration is **wrapper-owned** — the seam
  contract is `docs/wrapper-integration.md` §6, hydrate never seeds `hooks/`
  into projects.
- Decision record points in three protocols, appending author-attributed
  entries to `scv/DECISIONS.md`: `action:promote` plan approval (adopted
  direction + **discarded alternatives**), `action:work` archive (the reason
  promoted to a decision summary), `action:regression` obsolete triage (the
  WHY that previously evaporated with the session).
- `action:status` now surfaces the last 5 `DECISIONS.md` entries and the open
  `TODO.md` items counted per author.
- **`scv/routines/` — 한 문장 프롬프트 유지보수 루틴 레이어** (Boris Cherny's
  daily-maintenance-routines practice): one routine = one md file under
  `scv/routines/<name>.md` with a five-key frontmatter contract
  (`name` / `cadence` / `guardrails` / `exit` / `report`) and a task-only body
  (plan-grammar — 과업+가드레일+종료 조건, 절차 나열 금지). hydrate seeds ONLY
  `scv/routines/README.md` (the convention doc, `merge_policy: overwrite`);
  sync propagates it to existing projects the same explicit-line way as
  `raw/README.md`. Routine files themselves are user/agent-authored.
- **`action:routine` — the 15th action** (core-owned): `--list` shows a
  NAME/CADENCE/REPORT table (guidance line when none are defined), `<name>`
  parses the routine md via the new `core/scripts/routine.sh`
  (frontmatter signals + task body + host-scheduling guidance block;
  unknown name → error with the available list, exit 1; `--lint <file>`
  validates the five-key schema). The `routine.md` protocol binds execution
  to the routine's task/guardrails/exit contract, forbids direct writes to
  permanent branches (working branch + PR or report only), makes the
  `report:` summary follow the `action:report` format, and ends with
  host-specific schedule-registration EXAMPLES — **SCV itself never
  schedules**: no cron registration, no daemon, no loop (host-owned, like
  `update` / `set-models` installation ownership). Action-count contracts
  updated 14 → 15 (`tests/test-actions.sh`, `tools/verify-core.sh`, READMEs,
  `docs/wrapper-integration.md`, `docs/core-wrapper-ownership.ko.md`);
  wrappers must register the new command surface (handoff drafts in
  `scv/promote/20260807-wookiya1364-routines/HANDOFF-DRAFTS.md`).
- Seven built-in routine templates under `core/template/scv/routines/examples/`
  (copy into `scv/routines/` to adopt; never auto-seeded): 4 SCV maintenance
  routines — `regression-runner` (run `action:regression`, report failures),
  `outdated-verifier` (semantically verify `readpath.sh outdated`'s
  `OUTDATED-CANDIDATE` docs against current code — completes the 0.21.0
  heuristic), `promote-staleness` (remind about `status: planned` folders
  older than N days), `archive-integrity` (regenerate `INDEX.yaml`, verify
  `supersedes` links) — plus 3 project-agnostic codebase routines imported
  from the Boris interview: `dead-code`, `abstraction-police`,
  `useless-tests`. All pass the routine frontmatter lint
  (`core/tests/test-routines.sh` covers seeding, list/prepare/error paths,
  outdated wiring, the 15-action catalog, and a no-scheduler-code sweep).

### Changed (team journal wave)

- Conversations are now **committed**: `.gitignore.fragment` no longer ignores
  `/scv/.conversations/`; `action:help` persists conversation files to
  `scv/conversations/` through the `journal-append.sh --redact-only` filter,
  and offers a one-time migration when it detects a legacy local
  `scv/.conversations/` (`LEGACY_CONVERSATIONS:` helper line).

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
