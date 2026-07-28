#!/usr/bin/env bash
# test-handoff-lifecycle.sh — handoff.sh mark (open→claimed→done) reflected in the root.
# Run: bash tests/test-handoff-lifecycle.sh

set -uo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
HYDRATE="$REPO_ROOT/scripts/hydrate.sh"
WH="$REPO_ROOT/scripts/workspace-helper.sh"
HANDOFF="$REPO_ROOT/scripts/handoff.sh"
STATUS="$REPO_ROOT/scripts/status.sh"
source "$REPO_ROOT/scripts/lib/yaml.sh"

PASS=0; FAIL=0
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
eq()   { if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1 — expected [$2], got [$3]"; fi; }
has()  { if echo "$2" | grep -q "$3"; then ok "$1"; else fail "$1 — missing [$3]"; fi; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
export SCV_CACHE_DIR="$WORK/cache"
DATE="$(date +%Y%m%d)"
giti(){ git -C "$1" init -q; git -C "$1" config user.email d@d.d; git -C "$1" config user.name X; }

echo "── handoff lifecycle (mark open→claimed→done) ──"

bash "$HYDRATE" init "$WORK/root" --root >/dev/null 2>&1; giti "$WORK/root" L
git -C "$WORK/root" add -A >/dev/null; git -C "$WORK/root" commit -qm init
bash "$HYDRATE" init "$WORK/be" >/dev/null 2>&1; giti "$WORK/be" B
( cd "$WORK/be" && bash "$WH" join --root "$WORK/root" --id be --role backend --workspace acme >/dev/null 2>&1 )
( cd "$WORK/be" && bash "$HANDOFF" write --to be --slug do-thing --title "BE do thing" >/dev/null 2>&1 )

HID="${DATE}-be-do-thing__to-be"
HF="$WORK/root/scv/handoffs/raw/HANDOFF-$HID.md"
eq "initial status open" "open" "$(yaml_get "$HF" status)"

# mark claimed (from the child)
( cd "$WORK/be" && bash "$HANDOFF" mark "$HID" claimed >/dev/null 2>&1 )
eq "after mark claimed" "claimed" "$(yaml_get "$HF" status)"
git -C "$WORK/root" log --oneline -1 | grep -q "status → claimed" && ok "root committed claimed" || fail "no claimed commit"

# status [7] in umbrella reflects claimed
SOUT="$( cd "$WORK/root" && bash "$STATUS" 2>/dev/null )"
has "status summary shows claimed 1" "$SOUT" "open 0 · claimed 1 · done 0"
has "per-item shows [claimed → be]"  "$SOUT" "claimed → be"

# mark done
( cd "$WORK/be" && bash "$HANDOFF" mark "$HID" done >/dev/null 2>&1 )
eq "after mark done" "done" "$(yaml_get "$HF" status)"

# invalid state rejected
( cd "$WORK/be" && bash "$HANDOFF" mark "$HID" bogus >/dev/null 2>&1 ) && fail "should reject invalid state" || ok "rejects invalid state"

# single repo: mark refused
bash "$HYDRATE" init "$WORK/solo" >/dev/null 2>&1
( cd "$WORK/solo" && bash "$HANDOFF" mark x claimed >/dev/null 2>&1 ) && fail "should refuse mark in single" || ok "refuses mark in single mode"

echo ""
echo "── result: $PASS passed, $FAIL failed ──"
[[ "$FAIL" -eq 0 ]]
