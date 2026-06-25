#!/usr/bin/env bash
# test-handoff-adopt.sh — consumer side: handoff.sh adopt scaffolds a local promote.
# Run: bash tests/test-handoff-adopt.sh

set -uo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
HYDRATE="$REPO_ROOT/scripts/hydrate.sh"
SYNC="$REPO_ROOT/scripts/sync.sh"
HANDOFF="$REPO_ROOT/scripts/handoff.sh"
source "$REPO_ROOT/scripts/lib/yaml.sh"

PASS=0; FAIL=0
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
eq()   { if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1 — expected [$2], got [$3]"; fi; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export SCV_CACHE_DIR="$WORK/cache"
DATE="$(date +%Y%m%d)"

echo "── handoff.sh adopt (consumer scaffold) tests ──"

# root + child(be) joined to local path; write a handoff to be
ROOT="$WORK/root"
bash "$HYDRATE" init "$ROOT" --root >/dev/null 2>&1
git -C "$ROOT" init -q; git -C "$ROOT" config user.email t@t.t; git -C "$ROOT" config user.name T
git -C "$ROOT" add -A >/dev/null 2>&1; git -C "$ROOT" commit -qm init >/dev/null 2>&1

CHILD="$WORK/be"
bash "$HYDRATE" init "$CHILD" >/dev/null 2>&1
git -C "$CHILD" init -q; git -C "$CHILD" config user.email t@t.t; git -C "$CHILD" config user.name T
bash "$SYNC" --project-dir "$CHILD" --join "$ROOT" --id be --role backend --workspace acme >/dev/null 2>&1

cat > "$WORK/body.md" <<'EOF'
## What be must build
A POST /api/refunds endpoint with idempotency.

## Acceptance for the receiving repo
- POST /api/refunds {orderId, amount} -> 200 {refundId}
- duplicate request -> 409
EOF
( cd "$CHILD" && bash "$HANDOFF" write --to be --slug refund-button \
    --title "BE needs POST /api/refunds" \
    --body-file "$WORK/body.md" >/dev/null 2>&1 ) || true
# from defaults to this repo's repo_id (be) → handoff_id uses from=be
HID="${DATE}-be-refund-button__to-be"

# adopt
AOUT="$( cd "$CHILD" && bash "$HANDOFF" adopt "$HID" --author bob 2>&1 )"; ARC=$?
eq "adopt exit 0" "0" "$ARC"
SLUG="${DATE}-bob-refund-button"
PLAN="$CHILD/scv/promote/$SLUG/PLAN.md"
TESTS="$CHILD/scv/promote/$SLUG/TESTS.md"
[[ -f "$PLAN" ]]  && ok "PLAN.md scaffolded"  || { fail "PLAN.md missing"; echo "$AOUT"; }
[[ -f "$TESTS" ]] && ok "TESTS.md scaffolded" || fail "TESTS.md missing"

eq "PLAN slug"   "$SLUG"                       "$(yaml_get "$PLAN" slug)"
eq "PLAN title"  "BE needs POST /api/refunds"  "$(yaml_get "$PLAN" title)"
eq "PLAN author" "bob"                         "$(yaml_get "$PLAN" author)"
grep -q "$HID" "$PLAN" && ok "PLAN back-refs handoff_id" || fail "PLAN missing handoff back-ref"
grep -q "POST /api/refunds" "$PLAN" && ok "PLAN carries 'what to build'" || fail "PLAN missing what-to-build"

grep -q "409" "$TESTS" && ok "TESTS carries acceptance criteria" || fail "TESTS missing acceptance"
grep -q "exit 1" "$TESTS" && ok "TESTS starts failing (TDD Red placeholder)" || fail "TESTS missing red placeholder"

# adopt addressed to another repo → refuse
cat > "$WORK/b2.md" <<'EOF'
## What ai must build
something
## Acceptance for the receiving repo
- x
EOF
( cd "$CHILD" && bash "$HANDOFF" write --to ai --slug other --title T --body-file "$WORK/b2.md" >/dev/null 2>&1 ) || true
HID_AI="${DATE}-be-other__to-ai"
( cd "$CHILD" && bash "$HANDOFF" adopt "$HID_AI" >/dev/null 2>&1 ) && fail "should refuse adopting a handoff addressed to 'ai'" || ok "refuses handoff not addressed to this repo"

# adopt in SINGLE → refuse
SOLO="$WORK/solo"; bash "$HYDRATE" init "$SOLO" >/dev/null 2>&1
( cd "$SOLO" && bash "$HANDOFF" adopt whatever >/dev/null 2>&1 ) && fail "should refuse adopt in single mode" || ok "refuses adopt in single mode"

echo ""
echo "── result: $PASS passed, $FAIL failed ──"
[[ "$FAIL" -eq 0 ]]
