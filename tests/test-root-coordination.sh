#!/usr/bin/env bash
# test-root-coordination.sh — the ROOT (umbrella) repo surfaces its OWN handoffs
# (coordination view) in handoff.sh list / status [7] / help. Run from the umbrella.
# Run: bash tests/test-root-coordination.sh

set -uo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
HYDRATE="$REPO_ROOT/scripts/hydrate.sh"
WH="$REPO_ROOT/scripts/workspace-helper.sh"
HANDOFF="$REPO_ROOT/scripts/handoff.sh"
STATUS="$REPO_ROOT/scripts/status.sh"
HELP="$REPO_ROOT/scripts/help.sh"

PASS=0; FAIL=0
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
has()  { if echo "$2" | grep -q "$3"; then ok "$1"; else fail "$1 — missing [$3]"; fi; }
hasnt(){ if echo "$2" | grep -q "$3"; then fail "$1 — unexpectedly has [$3]"; else ok "$1"; fi; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
export SCV_CACHE_DIR="$WORK/cache"
giti(){ git -C "$1" init -q; git -C "$1" config user.email d@d.d; git -C "$1" config user.name X; }

echo "── ROOT (umbrella) coordination view ──"

# umbrella + a child that pushes 2 handoffs (to ai, to be)
bash "$HYDRATE" init "$WORK/root" --root >/dev/null 2>&1; giti "$WORK/root" L
git -C "$WORK/root" add -A >/dev/null; git -C "$WORK/root" commit -qm init
bash "$HYDRATE" init "$WORK/be" >/dev/null 2>&1; giti "$WORK/be" B
( cd "$WORK/be" && bash "$WH" join --root "$WORK/root" --id be --role backend --workspace acme >/dev/null 2>&1 )
( cd "$WORK/be" && bash "$HANDOFF" write --to ai --slug emit-risk --title "AI: emit risk score" >/dev/null 2>&1 )
( cd "$WORK/be" && bash "$HANDOFF" write --to be --slug self-x   --title "BE: internal change"  >/dev/null 2>&1 )

# 1. handoff.sh list (from the umbrella, no --to) reads local handoffs
LIST="$( cd "$WORK/root" && bash "$HANDOFF" list 2>/dev/null )"
LN=$(printf '%s\n' "$LIST" | grep -c .)
[[ "$LN" -eq 2 ]] && ok "umbrella list shows 2 local handoffs" || { fail "expected 2, got $LN"; echo "$LIST"; }

# 2. status [7] in the umbrella → coordination overview, NOT the 'not synced' bug
SOUT="$( cd "$WORK/root" && bash "$STATUS" 2>/dev/null )"
has   "status: ROOT umbrella header"      "$SOUT" "ROOT (umbrella)"
has   "status: open handoffs (2)"         "$SOUT" "open handoffs (2)"
has   "status: per-target ai: 1"          "$SOUT" "→ ai: 1"
has   "status: per-target be: 1"          "$SOUT" "→ be: 1"
has   "status: shows a handoff title"     "$SOUT" "AI: emit risk score"
hasnt "status: NOT the 'not synced' bug"  "$SOUT" "not synced locally"

# 3. help in the umbrella → coordination recommendation
HOUT="$( cd "$WORK/root" && bash "$HELP" 2>/dev/null )"
has   "help: umbrella open-handoff count" "$HOUT" "open handoffs: 2"
has   "help: umbrella recommendation"     "$HOUT" "open handoff(s) coordinating across repos"

echo ""
echo "── result: $PASS passed, $FAIL failed ──"
[[ "$FAIL" -eq 0 ]]
