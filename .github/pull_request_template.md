## Summary

<!-- What & why, in 1–3 lines. -->

## Changes

-

## Tests

- [ ] `bash tests/run-dry.sh` green
- [ ] `bash tests/test-scvroot.sh` green (if scv path resolution touched)
- [ ] relevant scenario / regression updated

## Deck (only if `/scv:deck` / `DeckUI` touched)

- [ ] `pnpm -C DeckUI typecheck` + `build:deck` green

## Checklist

- [ ] Follows the branch flow (`feat|fix|docs|chore|refactor|test/*` → `develop`) — see [`.github/BRANCHING.md`](./BRANCHING.md)
- [ ] No secrets / customer data
- [ ] Docs (README / command md) updated if user-facing
