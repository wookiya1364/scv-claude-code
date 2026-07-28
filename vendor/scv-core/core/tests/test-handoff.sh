#!/usr/bin/env bash
# test-handoff.sh — integration tests for the /scv:handoff producer.
# Sets up a local root repo + a child, exercises handoff.sh write/list, SINGLE
# no-op, and graceful degrade. No network (root is a local git repo).
# Run: bash tests/test-handoff.sh

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
export SCV_CACHE_DIR="$WORK/cache"   # never touch the real ~/.cache

DATE="$(date +%Y%m%d)"

echo "── /scv:handoff producer tests ──"

# --- set up ROOT repo (umbrella) as a real local git repo ---
ROOT="$WORK/root"
bash "$HYDRATE" init "$ROOT" --root >/dev/null 2>&1
git -C "$ROOT" init -q
git -C "$ROOT" config user.email t@t.t
git -C "$ROOT" config user.name "Tester"
git -C "$ROOT" add -A >/dev/null 2>&1
git -C "$ROOT" commit -qm "init root" >/dev/null 2>&1

# --- set up CHILD (fe) joined to the local root path ---
CHILD="$WORK/fe"
bash "$HYDRATE" init "$CHILD" >/dev/null 2>&1
git -C "$CHILD" init -q
git -C "$CHILD" config user.email t@t.t
git -C "$CHILD" config user.name "FE Dev"
bash "$SYNC" --project-dir "$CHILD" --join "$ROOT" --id fe --role frontend --workspace acme >/dev/null 2>&1

# --- write a handoff from the child ---
cat > "$WORK/body.md" <<'EOF'
## What be must build
A POST /api/refunds endpoint.

## Acceptance for the receiving repo
- POST /api/refunds {orderId, amount} -> 200 {refundId}; 409 on duplicate.
EOF
cat > "$WORK/why.md" <<'EOF'
Chose server-side idempotency over client retry.
EOF

OUT="$( cd "$CHILD" && SCV_CACHE_DIR="$WORK/cache" bash "$HANDOFF" write \
  --to be --slug refund-button --title "BE needs POST /api/refunds" \
  --from-slug 20260624-fe-refund-button --ref-pr "https://github.com/org/fe/pull/812" \
  --body-file "$WORK/body.md" --why-file "$WORK/why.md" 2>&1 )"

HID="${DATE}-fe-refund-button__to-be"
DID="${DATE}-refund-button"
HF="$ROOT/scv/handoffs/raw/HANDOFF-$HID.md"

[[ -f "$HF" ]] && ok "handoff file written to root" || { fail "handoff file missing"; echo "$OUT"; }
[[ -f "$ROOT/scv/decisions/$DID.md" ]] && ok "decision file written" || fail "decision file missing"
[[ -f "$ROOT/scv/conversations/$DID.md" ]] && ok "conversation file written" || fail "conversation file missing"

eq "frontmatter to_repo"   "be"   "$(yaml_get "$HF" to_repo)"
eq "frontmatter from_repo" "fe"   "$(yaml_get "$HF" from_repo)"
eq "frontmatter status"    "open" "$(yaml_get "$HF" status)"
eq "frontmatter decision"  "needed" "$(yaml_get "$HF" decision)"
grep -q "POST /api/refunds" "$HF" && ok "body content embedded" || fail "body content missing"
grep -q "409 on duplicate" "$HF" && ok "acceptance criteria embedded" || fail "acceptance missing"

# commit happened in root
git -C "$ROOT" log --oneline -1 2>/dev/null | grep -q "handoff($HID)" \
  && ok "root committed the handoff" || fail "root has no handoff commit"

# list (from child) shows it, filtered by --to
LIST="$( cd "$CHILD" && SCV_CACHE_DIR="$WORK/cache" bash "$HANDOFF" list --to be 2>/dev/null )"
echo "$LIST" | grep -q "$HID|be|open|" && ok "handoff.sh list --to be shows it" || { fail "list missing entry"; echo "[$LIST]"; }
LIST_AI="$( cd "$CHILD" && SCV_CACHE_DIR="$WORK/cache" bash "$HANDOFF" list --to ai 2>/dev/null )"
[[ -z "$LIST_AI" ]] && ok "list --to ai is empty (addressing filter works)" || fail "filter leaked: [$LIST_AI]"

# --- SINGLE no-op ---
SOLO="$WORK/solo"
bash "$HYDRATE" init "$SOLO" >/dev/null 2>&1
SOUT="$( cd "$SOLO" && bash "$HANDOFF" write --to be --slug x --title y 2>&1 )"; SRC=$?
eq "SINGLE write exit 0" "0" "$SRC"
echo "$SOUT" | grep -qi "single-repo" && ok "SINGLE prints skip notice" || fail "no single-repo notice: [$SOUT]"

# --- graceful degrade: root unreachable ---
DCHILD="$WORK/degrade"
bash "$HYDRATE" init "$DCHILD" >/dev/null 2>&1
bash "$SYNC" --project-dir "$DCHILD" --join "/no/such/root/path-xyz" --id be --role backend --workspace missing >/dev/null 2>&1
DOUT="$( cd "$DCHILD" && SCV_CACHE_DIR="$WORK/cache" bash "$HANDOFF" write --to ai --slug z --title q 2>&1 )"; DRC=$?
[[ "$DRC" -ne 0 ]] && ok "unreachable root → non-zero exit" || fail "should fail when root unreachable"
echo "$DOUT" | grep -qi "cannot reach workspace root" && ok "degrade message shown" || fail "no degrade message: [$DOUT]"

echo ""
echo "── result: $PASS passed, $FAIL failed ──"
[[ "$FAIL" -eq 0 ]]
