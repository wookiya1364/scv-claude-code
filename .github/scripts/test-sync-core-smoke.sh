#!/usr/bin/env bash
# Fast maintainer-updater smoke for the two-minute CI contract.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
WORK="$(mktemp -d)"
WORK="$(cd "$WORK" && pwd -P)"
FIXTURE="$WORK/wrapper"
SOURCE_CORE="$REPO_ROOT/vendor/scv-core"
PASS=0
FAIL=0

ok() {
  printf 'PASS: %s\n' "$1"
  PASS=$((PASS + 1))
}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  FAIL=$((FAIL + 1))
}

cleanup() {
  git -C "$REPO_ROOT" worktree remove --force "$FIXTURE" >/dev/null 2>&1 || true
  rm -rf "$WORK"
}

trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

git -C "$REPO_ROOT" worktree add --detach --quiet "$FIXTURE" HEAD

initial_status="$(git -C "$FIXTURE" status --porcelain=v1 --untracked-files=all)"
if [[ -z "$initial_status" ]]; then
  ok "linked fixture starts clean"
else
  fail "linked fixture starts dirty"
fi

mkdir -p \
  "$FIXTURE/DeckUI/node_modules" \
  "$FIXTURE/DeckUI/dist-deck"
printf 'runtime dependency sentinel\n' \
  >"$FIXTURE/DeckUI/node_modules/.scv-ci-smoke"
printf 'runtime build sentinel\n' \
  >"$FIXTURE/DeckUI/dist-deck/.scv-ci-smoke"
printf 'wrapper vendor sibling sentinel\n' \
  >"$FIXTURE/vendor/wrapper-ci-smoke.txt"
git -C "$FIXTURE" add vendor/wrapper-ci-smoke.txt
git -C "$FIXTURE" \
  -c user.name="SCV CI Smoke" \
  -c user.email="scv-ci-smoke@example.invalid" \
  commit -qm "test fixture: wrapper vendor sibling"
before_head="$(git -C "$FIXTURE" rev-parse HEAD)"
before_status="$(git -C "$FIXTURE" status --porcelain=v1 --untracked-files=all)"

dry_run_output="$WORK/dry-run.out"
set +e
SCV_DECK_CACHE_DIR="$WORK/deck-cache" \
  bash "$FIXTURE/scripts/sync-core.sh" \
    --source "$SOURCE_CORE" \
    --dry-run >"$dry_run_output" 2>&1
dry_run_rc=$?
set -e

if [[ "$dry_run_rc" -eq 0 ]] &&
    grep -Fq "CORE_SYNC_DRY_RUN: yes" "$dry_run_output"; then
  ok "source-mode dry-run reaches the verified projection"
else
  fail "source-mode dry-run did not finish"
  sed -n '1,80p' "$dry_run_output" >&2
fi

after_dry_run_status="$(git -C "$FIXTURE" status --porcelain=v1 --untracked-files=all)"
if [[ "$after_dry_run_status" == "$before_status" ]]; then
  ok "source-mode dry-run is mutation-free"
else
  fail "source-mode dry-run changed the fixture"
fi

rollback_output="$WORK/rollback.out"
set +e
SCV_DECK_CACHE_DIR="$WORK/deck-cache" \
SCV_CORE_SYNC_FAILPOINT="after-swap:scripts" \
  bash "$FIXTURE/scripts/sync-core.sh" \
    --source "$SOURCE_CORE" >"$rollback_output" 2>&1
rollback_rc=$?
set -e

if [[ "$rollback_rc" -ne 0 ]] &&
    grep -Fq \
      "injected core sync failure at after-swap:scripts" \
      "$rollback_output"; then
  ok "injected live-swap failure is propagated"
else
  fail "injected live-swap failure was not propagated"
fi

after_rollback_status="$(git -C "$FIXTURE" status --porcelain=v1 --untracked-files=all)"
after_rollback_head="$(git -C "$FIXTURE" rev-parse HEAD)"
if [[ "$after_rollback_status" == "$before_status" &&
      "$after_rollback_head" == "$before_head" ]]; then
  ok "rollback restores the exact tracked worktree state"
else
  fail "rollback left tracked worktree changes"
fi

transaction_debris=
for candidate in "$FIXTURE"/.scv-core-transaction.*; do
  if [[ -e "$candidate" || -L "$candidate" ]]; then
    transaction_debris=$candidate
    break
  fi
done
if [[ -z "$transaction_debris" ]]; then
  ok "rollback removes transaction debris"
else
  fail "rollback left transaction debris"
fi

success_output="$WORK/success.out"
set +e
SCV_DECK_CACHE_DIR="$WORK/deck-cache" \
  bash "$FIXTURE/scripts/sync-core.sh" \
    --source "$SOURCE_CORE" >"$success_output" 2>&1
success_rc=$?
set -e
if [[ "$success_rc" -eq 0 ]] &&
    grep -Fq "CORE_SYNCED: yes" "$success_output"; then
  ok "successful source-mode sync completes"
else
  fail "successful source-mode sync did not complete"
  sed -n '1,80p' "$success_output" >&2
fi

if bash "$FIXTURE/scripts/verify-core.sh" >/dev/null 2>&1; then
  ok "successful sync leaves a verified wrapper"
else
  fail "successful sync leaves an invalid wrapper"
fi

if git -C "$FIXTURE" diff --quiet HEAD -- \
    VERSION \
    .claude-plugin \
    scripts/sync.sh \
    vendor/wrapper-ci-smoke.txt; then
  ok "successful sync preserves wrapper-owned tracked files"
else
  fail "successful sync changed wrapper-owned tracked files"
fi

if [[ -f "$FIXTURE/DeckUI/node_modules/.scv-ci-smoke" &&
      -f "$FIXTURE/DeckUI/dist-deck/.scv-ci-smoke" &&
      -f "$FIXTURE/vendor/wrapper-ci-smoke.txt" ]]; then
  ok "successful sync preserves wrapper-owned and runtime data"
else
  fail "successful sync lost wrapper-owned or runtime data"
fi

transaction_debris=
for candidate in "$FIXTURE"/.scv-core-transaction.*; do
  if [[ -e "$candidate" || -L "$candidate" ]]; then
    transaction_debris=$candidate
    break
  fi
done
if [[ -z "$transaction_debris" ]]; then
  ok "successful sync removes transaction debris"
else
  fail "successful sync left transaction debris"
fi

printf 'PASS: %d  FAIL: %d\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
