#!/usr/bin/env bash
# test-workspace-helper.sh — tests for the /scv:workspace front-door mechanics.
# Run: bash tests/test-workspace-helper.sh

set -uo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
HYDRATE="$REPO_ROOT/scripts/hydrate.sh"
WH="$REPO_ROOT/scripts/workspace-helper.sh"

PASS=0; FAIL=0
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
eq()   { if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1 — expected [$2], got [$3]"; fi; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

field() { printf '%s\n' "$1" | awk -v k="$2" '$1==k":"{ $1=""; sub(/^ /,""); print; exit }'; }

echo "── workspace-helper.sh tests ──"

# 1. not hydrated
NH="$WORK/raw-dir"; mkdir -p "$NH"
OUT="$( cd "$NH" && bash "$WH" info 2>/dev/null )"
eq "not hydrated → NOT_HYDRATED" "NOT_HYDRATED" "$(field "$OUT" MODE)"

# 2. hydrated single
P="$WORK/fe"
bash "$HYDRATE" init "$P" >/dev/null 2>&1
OUT="$( cd "$P" && bash "$WH" info 2>/dev/null )"
eq "hydrated → SINGLE" "SINGLE" "$(field "$OUT" MODE)"

# 3. join (root is a local path that exists)
ROOTP="$WORK/root"; bash "$HYDRATE" init "$ROOTP" --root >/dev/null 2>&1
( cd "$P" && bash "$WH" join --root "$ROOTP" --id fe --role frontend --workspace acme >/dev/null 2>&1 )
OUT="$( cd "$P" && bash "$WH" info 2>/dev/null )"
eq "after join → CHILD"      "CHILD"     "$(field "$OUT" MODE)"
eq "info REPO_ID"            "fe"        "$(field "$OUT" REPO_ID)"
eq "info ROLE"               "frontend"  "$(field "$OUT" ROLE)"
eq "info ROOT"               "$ROOTP"    "$(field "$OUT" ROOT)"
eq "info ROOT_REACHABLE yes" "yes"       "$(field "$OUT" ROOT_REACHABLE)"

# 4. detach → SINGLE again
( cd "$P" && bash "$WH" detach >/dev/null 2>&1 )
OUT="$( cd "$P" && bash "$WH" info 2>/dev/null )"
eq "after detach → SINGLE" "SINGLE" "$(field "$OUT" MODE)"

# 5. init-root on a fresh single → ROOT
P2="$WORK/umbrella"; bash "$HYDRATE" init "$P2" >/dev/null 2>&1
( cd "$P2" && bash "$WH" init-root >/dev/null 2>&1 )
[[ -f "$P2/scv/WORKSPACE.yaml" ]] && ok "init-root creates WORKSPACE.yaml" || fail "WORKSPACE.yaml missing"
OUT="$( cd "$P2" && bash "$WH" info 2>/dev/null )"
eq "after init-root → ROOT" "ROOT" "$(field "$OUT" MODE)"

echo ""
echo "── result: $PASS passed, $FAIL failed ──"
[[ "$FAIL" -eq 0 ]]
