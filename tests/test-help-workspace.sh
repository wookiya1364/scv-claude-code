#!/usr/bin/env bash
# test-help-workspace.sh — /scv:help is workspace-aware (CHILD/ROOT), silent for single.
# Run: bash tests/test-help-workspace.sh

set -uo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
HYDRATE="$REPO_ROOT/scripts/hydrate.sh"
WH="$REPO_ROOT/scripts/workspace-helper.sh"
HANDOFF="$REPO_ROOT/scripts/handoff.sh"
HELP="$REPO_ROOT/scripts/help.sh"

PASS=0; FAIL=0
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
has()  { if echo "$2" | grep -q "$3"; then ok "$1"; else fail "$1 — missing [$3]"; fi; }
hasnt(){ if echo "$2" | grep -q "$3"; then fail "$1 — unexpectedly has [$3]"; else ok "$1"; fi; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
export SCV_CACHE_DIR="$WORK/cache"
giti(){ git -C "$1" init -q; git -C "$1" config user.email d@d.d; git -C "$1" config user.name X; }

echo "── /scv:help workspace-awareness ──"

# root + child(be) + incoming handoff
bash "$HYDRATE" init "$WORK/root" --root >/dev/null 2>&1; giti "$WORK/root" L
git -C "$WORK/root" add -A >/dev/null; git -C "$WORK/root" commit -qm init
bash "$HYDRATE" init "$WORK/be" >/dev/null 2>&1; giti "$WORK/be" B
( cd "$WORK/be" && bash "$WH" join --root "$WORK/root" --id be --role backend --workspace acme >/dev/null 2>&1 )
( cd "$WORK/be" && bash "$HANDOFF" write --to be --slug fix-it --title "BE corresponding work" >/dev/null 2>&1 )

CHILD_OUT="$( cd "$WORK/be" && bash "$HELP" 2>/dev/null )"
has  "CHILD: Workspace diagnosis line"        "$CHILD_OUT" "Workspace: CHILD"
has  "CHILD: incoming count shown"            "$CHILD_OUT" "incoming handoffs addressed to this repo: 1"
has  "CHILD: recommended action surfaces"     "$CHILD_OUT" "incoming handoff(s)"
has  "CHILD: recommends /scv:promote"         "$CHILD_OUT" "/scv:promote"

# ROOT
ROOT_OUT="$( cd "$WORK/root" && bash "$HELP" 2>/dev/null )"
has  "ROOT: umbrella diagnosis line"          "$ROOT_OUT" "Workspace: ROOT (umbrella)"
has  "ROOT: member count"                     "$ROOT_OUT" "members: 3"

# SINGLE — no workspace noise (byte-identical guarantee)
bash "$HYDRATE" init "$WORK/solo" >/dev/null 2>&1
SOLO_OUT="$( cd "$WORK/solo" && bash "$HELP" 2>/dev/null )"
hasnt "SINGLE: no Workspace diagnosis line"   "$SOLO_OUT" "Workspace:"
hasnt "SINGLE: no incoming-handoff block"     "$SOLO_OUT" "incoming handoff"
# sanity: single help still works (has the normal recommended action box)
has  "SINGLE: normal help still renders"      "$SOLO_OUT" "Recommended next action"

# CHILD but root unreachable → notice, no count crash
bash "$HYDRATE" init "$WORK/degr" >/dev/null 2>&1
( cd "$WORK/degr" && bash "$WH" join --root "/no/such/root" --id be --role backend --workspace gone >/dev/null 2>&1 )
DEGR_OUT="$( cd "$WORK/degr" && bash "$HELP" 2>/dev/null )"
has  "CHILD unreachable: still shows Workspace line" "$DEGR_OUT" "Workspace: CHILD"
has  "CHILD unreachable: sync notice"          "$DEGR_OUT" "not synced locally"

echo ""
echo "── result: $PASS passed, $FAIL failed ──"
[[ "$FAIL" -eq 0 ]]
