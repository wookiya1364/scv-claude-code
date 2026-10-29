## Summary

<!-- What & why, in 1–3 lines. -->

## Changes

-

## Tests

- [ ] `bash tests/run-dry.sh` green
- [ ] `bash tests/test-scvroot.sh` green (if scv path resolution touched)
- [ ] relevant scenario / regression updated

## Deck (only if `/scv:deck` / `vendor/scv-core/core/DeckUI` touched)

- [ ] `d=$(bash scripts/deck-runtime.sh ensure) && pnpm -C "$d" install && pnpm -C "$d" typecheck && pnpm -C "$d" build:deck` green — run it in the deck runtime cache, never inside `vendor/` (installing there breaks `scripts/verify-core.sh`)

## Checklist

- [ ] Follows the branch flow (`feat|fix|docs|chore|refactor|test/*` → `develop`) — see [`.github/BRANCHING.md`](./BRANCHING.md)
- [ ] Code change declares `[no-plan: <reason>]` in the title (this repo has no `scv/` workspace, so the plan lives in scv-core) — an empty `[no-plan]` is refused
- [ ] `vendor/scv-core/` untouched, or the title declares `[manual-vendor: <reason>]` — an empty `[manual-vendor]` is refused
- [ ] No secrets / customer data
- [ ] Docs (README / command md) updated if user-facing
