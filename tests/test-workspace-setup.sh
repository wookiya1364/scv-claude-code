#!/usr/bin/env bash
# test-workspace-setup.sh — integration tests for workspace join/setup.
# Exercises real hydrate.sh (--root) + sync.sh (--join + SCV:WORKSPACE preservation).
# Run: bash tests/test-workspace-setup.sh

set -uo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
LIB="$REPO_ROOT/scripts/lib/workspace.sh"
HYDRATE="$REPO_ROOT/scripts/hydrate.sh"
SYNC="$REPO_ROOT/scripts/sync.sh"
source "$REPO_ROOT/scripts/lib/merge.sh"

PASS=0; FAIL=0
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
eq()   { if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1 — expected [$2], got [$3]"; fi; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

mode()  { WS_INDEX="$1/scv/SCV.md" WS_MANIFEST="$1/scv/WORKSPACE.yaml" bash -c 'source "'"$LIB"'"; scv_resolve_mode'; }
field() { WS_INDEX="$1/scv/SCV.md" bash -c 'source "'"$LIB"'"; '"$2"; }

echo "── workspace setup (hydrate --root / sync --join / preservation) ──"

# 1. plain hydrate → SINGLE
P1="$WORK/fe"
bash "$HYDRATE" init "$P1" >/dev/null 2>&1
eq "hydrate (plain) → SINGLE" "SINGLE" "$(mode "$P1")"
[[ -f "$P1/scv/SCV.md" ]] && ok "scv/SCV.md created" || fail "scv/SCV.md missing"

# 2. hydrate --root → ROOT (WORKSPACE.yaml created)
PR="$WORK/root"
bash "$HYDRATE" init "$PR" --root >/dev/null 2>&1
[[ -f "$PR/scv/WORKSPACE.yaml" ]] && ok "hydrate --root creates WORKSPACE.yaml" || fail "WORKSPACE.yaml missing"
eq "hydrate --root → ROOT" "ROOT" "$(mode "$PR")"

# 3. sync --join → CHILD + readers correct
bash "$SYNC" --project-dir "$P1" --join "git@github.com:org/root.git" --id be --role backend --workspace acme >/dev/null 2>&1
eq "sync --join → CHILD" "CHILD" "$(mode "$P1")"
eq "joined repo_id"   "be"                        "$(field "$P1" 'scv_repo_id')"
eq "joined role"      "backend"                   "$(field "$P1" 'scv_role')"
eq "joined root"      "git@github.com:org/root.git" "$(field "$P1" 'scv_root')"
eq "joined workspace" "acme"                      "$(field "$P1" 'scv_workspace')"

# 4. PRESERVATION — full sync must keep the joined SCV:WORKSPACE block AND PROJECT:LOCAL
# Inject a custom PROJECT:LOCAL line first.
replace_marker_block "$P1/scv/SCV.md" "PROJECT:LOCAL START" "PROJECT:LOCAL END" "MY-LOCAL-RULE-XYZ"
bash "$SYNC" --project-dir "$P1" >/dev/null 2>&1
eq "after full sync → still CHILD (root preserved)" "CHILD" "$(mode "$P1")"
eq "joined root survives sync" "git@github.com:org/root.git" "$(field "$P1" 'scv_root')"
grep -q "MY-LOCAL-RULE-XYZ" "$P1/scv/SCV.md" && ok "PROJECT:LOCAL survives sync" || fail "PROJECT:LOCAL lost on sync"

# 5. DETACH — clear root → SINGLE again, no migration
replace_marker_block "$P1/scv/SCV.md" "SCV:WORKSPACE START" "SCV:WORKSPACE END" \
  '```yaml
repo_id: be
role: backend
root:
workspace:
```'
eq "detach (clear root) → SINGLE" "SINGLE" "$(mode "$P1")"

echo ""
echo "── result: $PASS passed, $FAIL failed ──"
[[ "$FAIL" -eq 0 ]]
