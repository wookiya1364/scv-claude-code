#!/usr/bin/env bash
# test-handoff-notify.sh — best-effort team notification on handoff push.
# Uses a bare remote (so push works) + NOTIFIER_DRY_RUN to avoid real network.
# Run: bash tests/test-handoff-notify.sh

set -uo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
HYDRATE="$REPO_ROOT/scripts/hydrate.sh"
WH="$REPO_ROOT/scripts/workspace-helper.sh"
HANDOFF="$REPO_ROOT/scripts/handoff.sh"

PASS=0; FAIL=0
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
has()  { if echo "$2" | grep -q "$3"; then ok "$1"; else fail "$1 — missing [$3]"; fi; }
hasnt(){ if echo "$2" | grep -q "$3"; then fail "$1 — unexpectedly has [$3]"; else ok "$1"; fi; }

command -v jq >/dev/null 2>&1   || { echo "(skip: jq not available)"; exit 0; }
command -v curl >/dev/null 2>&1 || { echo "(skip: curl not available)"; exit 0; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
export SCV_CACHE_DIR="$WORK/cache"
giti(){ git -C "$1" init -q; git -C "$1" config user.email d@d.d; git -C "$1" config user.name X; }

echo "── handoff push notification (best-effort) ──"

# bare remote + root that tracks it (so 'git push' works)
git init --bare -q "$WORK/remote.git"
bash "$HYDRATE" init "$WORK/root" --root >/dev/null 2>&1; giti "$WORK/root"
git -C "$WORK/root" remote add origin "$WORK/remote.git"
git -C "$WORK/root" add -A >/dev/null; git -C "$WORK/root" commit -qm init
git -C "$WORK/root" push -q -u origin HEAD 2>/dev/null

# child joined via local path to root
bash "$HYDRATE" init "$WORK/be" >/dev/null 2>&1; giti "$WORK/be"
( cd "$WORK/be" && bash "$WH" join --root "$WORK/root" --id be --role backend --workspace acme >/dev/null 2>&1 )

# 1. push WITH a (dry-run) notifier configured → team pinged
( cd "$WORK/be" && bash "$HANDOFF" write --to be --slug one --title "first" >/dev/null 2>&1 )
OUT1="$( cd "$WORK/be" && NOTIFIER_PROVIDER=slack NOTIFIER_DRY_RUN=1 \
        SLACK_BOT_TOKEN=xoxb-test SLACK_CHANNEL_ID=C123 \
        bash "$HANDOFF" push 2>&1 )"
has "push succeeded"                "$OUT1" "pushed workspace root"
has "notifier attempted (dry-run)"  "$OUT1" "DRY_RUN: slack:chat.postMessage"
has "team notified line"            "$OUT1" "team notified via slack"

# 2. push with NO notifier configured → silent (push still works)
( cd "$WORK/be" && bash "$HANDOFF" write --to be --slug two --title "second" >/dev/null 2>&1 )
OUT2="$( cd "$WORK/be" && bash "$HANDOFF" push 2>&1 )"
has   "push succeeded (no notifier)" "$OUT2" "pushed workspace root"
hasnt "no dry-run marker"            "$OUT2" "DRY_RUN"
hasnt "no team-notified line"        "$OUT2" "team notified"

# 3. notifier set but env incomplete (no token) → skip notice, push still ok
( cd "$WORK/be" && bash "$HANDOFF" write --to be --slug three --title "third" >/dev/null 2>&1 )
OUT3="$( cd "$WORK/be" && NOTIFIER_PROVIDER=slack bash "$HANDOFF" push 2>&1 )"
has "push ok despite incomplete notifier" "$OUT3" "pushed workspace root"
has "incomplete-env skip notice"          "$OUT3" "env incomplete"

echo ""
echo "── result: $PASS passed, $FAIL failed ──"
[[ "$FAIL" -eq 0 ]]
