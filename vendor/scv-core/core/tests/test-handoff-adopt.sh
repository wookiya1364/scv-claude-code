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
root_files() { ( cd "$ROOT" && find . -type f -not -path './.git/*' | LC_ALL=C sort ); }
ROOT_BEFORE="$(root_files)"
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

# wrap-up report (0.93.1): an adopted plan gets the report skeleton too, and PLAN.md points at it —
# so the archive checks the report instead of passing the plan as one written before the report existed.
WRAPUP_CMD="$REPO_ROOT/scripts/wrapup.sh"
PDIR="$CHILD/scv/promote/$SLUG"
WRAP="$PDIR/WRAPUP.md"
[[ -f "$WRAP" ]] && ok "WRAPUP.md scaffolded" || fail "WRAPUP.md missing"
eq "promote folder holds three files" "3" "$(find "$PDIR" -type f | wc -l | tr -d '[:space:]')"
eq "WRAPUP has seven groups" "7" "$(grep -c '^## [1-7]\. ' "$WRAP" 2>/dev/null | tr -d '[:space:]')"
eq "PLAN points at the wrap-up once" "1" "$(grep -c '^- Wrap-up: .*WRAPUP\.md' "$PLAN" | tr -d '[:space:]')"
eq "PLAN keeps the wrap-up line under Links" "## Links" "$(awk '/^## /{h=$0} /^- Wrap-up: /{print h; exit}' "$PLAN")"

WOUT="$(bash "$WRAPUP_CMD" check "$PDIR" 2>&1)"; WRC=$?
eq "unfilled adopted plan is blocked at the report check" "1" "$WRC"
grep -q 'WRAPUP: block' <<<"$WOUT" && ok "report check says block" || fail "report check did not block: $WOUT"
grep -q 'legacy' <<<"$WOUT" && fail "adopted plan still counted as a plan without a report" || ok "adopted plan is not counted as legacy"

# what adopt did before stays: nothing written to the workspace root, and a second adopt is refused
eq "workspace root untouched by adopt" "$ROOT_BEFORE" "$(root_files)"
BEFORE_SUM="$(cat "$PLAN" "$TESTS" "$WRAP" 2>/dev/null | cksum)"
( cd "$CHILD" && bash "$HANDOFF" adopt "$HID" --author bob >/dev/null 2>&1 ) && fail "second adopt should be refused" || ok "second adopt refused"
eq "second adopt leaves the three files as they were" "$BEFORE_SUM" "$(cat "$PLAN" "$TESTS" "$WRAP" 2>/dev/null | cksum)"
eq "still three files after the refused adopt" "3" "$(find "$PDIR" -type f | wc -l | tr -d '[:space:]')"

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
