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
| SCV Core | `0.20.1` | Shared behavior and release payload |
| Core API | `1` | Wrapper/core integration contract |
| Template | `1.0.0` | Hydrated project-template schema |

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

Core owns 12 of the 14 SCV actions. `update` and `set-models` are deliberately
adapter-owned because installation and model selection depend on the host.
Canonical protocols use `action:<name>` and `{{SCV_ARGS}}`; wrapper syntax and
argument transport are supplied only through a validated host profile.

The shared state index is always `scv/SCV.md`. During the transition from older
wrappers, readers may fall back to `CLAUDE.md` or `CODEX.md` only when
`SCV.md` is absent. A mutating sync fails closed if independent state indexes
diverge.

See [Architecture](docs/architecture.md) and
[Wrapper integration](docs/wrapper-integration.md) for the complete boundary.

## Verify and test

```bash
bash tests/run.sh
bash core/tests/run-dry.sh
for test_file in core/tests/test-*.sh; do bash "$test_file"; done
```

DeckUI additionally requires Node.js and pnpm:

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

A `vX.Y.Z` tag publishes those files. When a cross-repository token is
configured it also sends an immediate Core-sync event; scheduled polling in
both wrappers is the no-secret fallback. Wrapper automation verifies the
checksum, regenerates its host-specific projection, runs regression tests, and
opens a PR to `develop`. See [Release and integrity](docs/release.md).

## Contributing

Permanent branches are `develop`, `stage`, and `main`. Work branches merge into
`develop`; promotion then proceeds `develop → stage → main`. See
[the branch policy](.github/BRANCHING.md).
