# SCV Core

[한국어](README.ko.md) · [日本語](README.ja.md)

SCV Core is the host-neutral source of truth shared by the SCV wrappers for
Claude Code and Codex. It contains the workflow protocols, scripts, project
template, DeckUI, assets, and shared regression suite. A wrapper pins an
immutable Core release, materializes a validated host profile, and adds only
the runtime-specific adapter.

Current versions:

| Contract | Version | Meaning |
|---|---:|---|
| SCV Core | `0.27.0` | Shared behavior and release payload |
| Core API | `1` | Wrapper/core integration contract |
| Template | `2.1.0` | Hydrated project-template schema |

The installable plugins live in:

- [SCV for Claude Code](https://github.com/wookiya1364/scv-claude-code)
- [SCV for Codex](https://github.com/wookiya1364/scv-codex)

## Design

```text
scv-core release (immutable tarball + SHA-256)
                 │
                 ├── pinned and materialized by scv-claude-code
                 └── pinned and materialized by scv-codex
                                      │
                                      └── runs locally; no runtime fetch
```

Core owns 13 of the 15 SCV actions. `update` and `set-models` are deliberately
adapter-owned because installation and model selection depend on the host.
Canonical protocols use `action:<name>` and `{{SCV_ARGS}}`; wrapper syntax and
argument transport are supplied only through a validated host profile.

The shared state index is always `scv/SCV.md`. During the transition from older
wrappers, readers may fall back to `CLAUDE.md` or `CODEX.md` only when
`SCV.md` is absent. A mutating sync fails closed if independent state indexes
diverge. Core owns the single resolver and pointer finalizer used by both
wrappers; compatibility pointers are recognized only by the exact
`SCV:HOST-POINTER target=SCV.md` marker.

DeckUI source is immutable in installed wrappers. Dependencies, generated
decks, and build output live in a cache keyed by the canonical Core payload
hash, so Claude Code and Codex reuse the same runtime without writing into
either plugin. `SCV_DECK_CACHE_DIR` may override the default user cache.
Cache initialization and legacy migration never replace a destination that
appears concurrently, never follow destination-ancestor links, and reject
cache/legacy overlap before writing.
The cache base, payload namespace, runtime target, lock, staging, installation,
and cleanup all remain anchored to verified open directory descriptors. A
concurrent path or ancestor replacement therefore fails closed without
redirecting writes or deletions.

Legacy migration is strict by default: a pre-existing cached value that
differs from its source is a collision. Persistent legacy sources may
explicitly use `migrate --from PATH --reuse-existing`. After preflighting every
eligible entry, one differing pre-existing destination makes the current cache
authoritative and skips the whole legacy source—equal and missing entries are
not copied. With no mismatch, migration remains additive; a late collision
still fails closed. Ephemeral existing-vendor recovery must remain strict
because that source may be removed after a wrapper swap.

Core also ships the checks that keep this workflow honest. A workspace guard
runs as a `PreToolUse` hook and refuses two things: creating a plan file, and
writing outside the workflow directory — unless the host has reported, anywhere
in this session, that an SCV action is running. That report is the one signal
the model cannot fabricate, which is why the guard keys on it. It fails open on
an empty payload and where no JSON reader exists, rather than blocking every
project; a receipt store it cannot write is the one failure that closes. It
stays inert where SCV was never adopted. Registering it is the wrapper's job: the wrapper
passes `SCV_GUARD_MODE` per hook entry, so the script never names a host. The
rules live in [the guard contract](core/contracts/guard.md).

Two merge-time gates cover what a hook cannot see.
`core/scripts/check-provenance.sh` denies a pull request that changes code but
adds no archived plan under `scv/archive/<slug>/PLAN.md`; a diff that touches
nothing but prose and the workflow directory is not a code change.
`core/scripts/check-vendor-provenance.sh` denies a pull request that rewrites a
wrapper's `vendor/scv-core/` on a branch that is not the sync bot's — the bot
resolves the published release artifact and records both the canonical and the
materialized hash, while a hand copy records whatever the working tree happened
to hold. Both exempt the release chain into `stage` and `main` and the bot's own
`chore/core-*` branch, and both accept a declared exception in the pull request
title: `[no-plan: <reason>]` and `[manual-vendor: <reason>]`. The reason is
required; an empty marker is refused. Core's own CI runs the provenance gate;
the vendor gate ships for the wrappers, which are the repositories that carry a
vendored Core.

See [Architecture](docs/architecture.md) and
[Wrapper integration](docs/wrapper-integration.md) for the complete boundary.

## Verify and test

```bash
bash tests/run.sh
bash core/tests/run-dry.sh
for test_file in core/tests/test-*.sh; do bash "$test_file"; done
```

DeckUI source-checkout development additionally requires Node.js and pnpm:

```bash
pnpm -C core/DeckUI install --frozen-lockfile
pnpm -C core/DeckUI typecheck
pnpm -C core/DeckUI build:deck
```

## Export and vendor

Create a verified host-neutral export:

```bash
tools/export-core.sh --output /tmp/scv-core-export
```

Materialize it for a wrapper from a local checkout:

```bash
tools/vendor-core.sh \
  --source /path/to/scv-core \
  --target /path/to/wrapper/vendor/scv-core \
  --profile /path/to/wrapper/adapter/host-profile.env
```

Vendoring records source and materialized hashes in `core.lock.json`.
Development dependencies, build output, caches, links, and special files are
excluded from exports.

## Release

```bash
tools/release-artifact.sh --output-dir dist
```

For version `X.Y.Z`, this creates:

- `scv-core-vX.Y.Z.tar.gz`
- `scv-core-vX.Y.Z.tar.gz.sha256`

A `vX.Y.Z` tag publishes those files and then notifies both wrappers with a
Core-sync event. The cross-repository token is required: a release that cannot
notify them is marked failed, though the published assets are unaffected. Both
wrappers also poll daily, so a failed notification delays propagation rather
than losing it. Wrapper automation verifies the checksum, regenerates its
host-specific projection, runs regression tests, and opens a PR to `develop`.
See [Release and integrity](docs/release.md).

## Contributing

Permanent branches are `develop`, `stage`, and `main`. Work branches merge into
`develop`; promotion then proceeds `develop → stage → main`. See
[the branch policy](.github/BRANCHING.md).
