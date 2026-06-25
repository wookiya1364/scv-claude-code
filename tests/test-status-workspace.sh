#!/usr/bin/env bash
# test-status-workspace.sh — integration tests for /scv:status section [7].
# Verifies surfacing of incoming handoffs, SINGLE-mode absence (byte-identical),
# and the unreachable-root notice. No network (local path root).
# Run: bash tests/test-status-workspace.sh

set -uo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
HYDRATE="$REPO_ROOT/scripts/hydrate.sh"
SYNC="$REPO_ROOT/scripts/sync.sh"
HANDOFF="$REPO_ROOT/scripts/handoff.sh"
STATUS="$REPO_ROOT/scripts/status.sh"

PASS=0; FAIL=0
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export SCV_CACHE_DIR="$WORK/cache"

echo "── /scv:status [7] workspace tests ──"

# root repo
ROOT="$WORK/root"
bash "$HYDRATE" init "$ROOT" --root >/dev/null 2>&1
git -C "$ROOT" init -q; git -C "$ROOT" config user.email t@t.t; git -C "$ROOT" config user.name T
git -C "$ROOT" add -A >/dev/null 2>&1; git -C "$ROOT" commit -qm init >/dev/null 2>&1

# child joined to local root path + one handoff written
CHILD="$WORK/be"
bash "$HYDRATE" init "$CHILD" >/dev/null 2>&1
git -C "$CHILD" init -q; git -C "$CHILD" config user.email t@t.t; git -C "$CHILD" config user.name T
bash "$SYNC" --project-dir "$CHILD" --join "$ROOT" --id be --role backend --workspace acme >/dev/null 2>&1
( cd "$CHILD" && bash "$HANDOFF" write --to be --slug add-refunds --title "Implement POST /api/refunds" >/dev/null 2>&1 )

# 1. CHILD status shows section [7] + the incoming handoff
OUT="$( cd "$CHILD" && bash "$STATUS" 2>/dev/null )"; RC=$?
[[ "$RC" -eq 0 ]] && ok "status exit 0 (child)" || fail "status non-zero exit ($RC)"
echo "$OUT" | grep -q "cross-repo handoffs" && ok "section [7] present (multi)" || fail "section [7] missing"
echo "$OUT" | grep -q "incoming (1)" && ok "shows incoming count" || fail "incoming count missing"
echo "$OUT" | grep -q "Implement POST /api/refunds" && ok "shows handoff title" || fail "handoff title missing"
echo "$OUT" | grep -q "mode: CHILD" && ok "shows mode CHILD" || fail "mode line missing"

# 2. SINGLE repo: section [7] absent (byte-identical world)
SOLO="$WORK/solo"
bash "$HYDRATE" init "$SOLO" >/dev/null 2>&1
SOUT="$( cd "$SOLO" && bash "$STATUS" 2>/dev/null )"; SRC=$?
[[ "$SRC" -eq 0 ]] && ok "status exit 0 (single)" || fail "single status non-zero ($SRC)"
echo "$SOUT" | grep -q "cross-repo handoffs" && fail "section [7] leaked into single mode" || ok "section [7] absent in single mode"

# 3. unreachable root → notice, no crash
DCHILD="$WORK/degr"
bash "$HYDRATE" init "$DCHILD" >/dev/null 2>&1
bash "$SYNC" --project-dir "$DCHILD" --join "/no/such/root-xyz" --id be --role backend --workspace gone >/dev/null 2>&1
DOUT="$( cd "$DCHILD" && bash "$STATUS" 2>/dev/null )"; DRC=$?
[[ "$DRC" -eq 0 ]] && ok "status exit 0 (unreachable)" || fail "unreachable status non-zero ($DRC)"
echo "$DOUT" | grep -q "not synced locally" && ok "shows unreachable notice" || fail "unreachable notice missing"

echo ""
echo "── result: $PASS passed, $FAIL failed ──"
[[ "$FAIL" -eq 0 ]]
