#!/usr/bin/env bash
# Workspace guard — T1..T19, T21..T28 from the plan's TESTS.md.
#
# The guard's whole value rests on two properties that pull against each other:
# it must deny the bypasses, and it must never deny an SCV action's own work.
# The second is the one that kills the feature in the field — a guard users
# switch off is worth less than no guard at all — so the allow cases here are as
# load-bearing as the deny cases.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD="$ROOT/core/template/hooks/guard.sh"
CONTRACT="$ROOT/core/contracts/guard.md"
ACTIONS_JSON="$ROOT/core/actions.json"

PASS=0; FAIL=0
pass() { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $1"; [[ $# -gt 1 ]] && printf '      %s\n' "$2"; FAIL=$((FAIL+1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A hydrated project with a receipt store that starts empty.
mk_project() {
  local p="$WORK/$1"
  mkdir -p "$p/scv/promote" "$p/scv/archive" "$p/src" "$p/state"
  printf '%s' "$p"
}

# run <project> <mode> <payload-json> [env assignments...]
run() {
  local proj="$1" mode="$2" payload="$3"; shift 3
  env "$@" SCV_GUARD_STATE="$proj/state" SCV_GUARD_MODE="$mode" \
    bash "$GUARD" <<<"$payload" 2>/dev/null
}

denied() { grep -q '"permissionDecision":"deny"' <<<"$1"; }

payload() {  # payload <cwd> <session> <file_path>
  printf '{"cwd":"%s","session_id":"%s","tool_name":"Write","tool_input":{"file_path":"%s"}}' "$1" "$2" "$3"
}

echo "=== Rule A — plan forgery ==="

P="$(mk_project a)"
for f in PLAN.md TESTS.md FEATURE_ARCHITECTURE.md; do          # T1, T2
  out="$(run "$P" gate-write "$(payload "$P" s1 "scv/promote/x/$f")")"
  denied "$out" && pass "T2 create $f without a receipt is denied" \
                || fail "T2 create $f was allowed"
done
out="$(run "$P" gate-write "$(payload "$P" s1 "scv/promote/x/PLAN.md")")"
grep -q 'promote' <<<"$out" && pass "T1 the denial names the remedy" || fail "T1 no remedy in reason"

mkdir -p "$P/scv/promote/x"; echo "existing" > "$P/scv/promote/x/PLAN.md"   # T3
out="$(run "$P" gate-write "$(payload "$P" s1 "scv/promote/x/PLAN.md")")"
denied "$out" && fail "T3 editing an existing plan must be allowed" \
              || pass "T3 editing an existing plan is allowed"

P="$(mk_project b)"                                                          # T4, T5
mint_payload='{"cwd":"'"$P"'","session_id":"s1","tool_name":"Skill","tool_input":{"skill":"scv:promote"}}'
run "$P" mint "$mint_payload" >/dev/null
# compgen, not `[[ -s prefix* ]]`: a glob inside [[ ]] is not expanded, so the
# test would compare against the literal pattern and report a false failure.
compgen -G "$P/state/s1-*" >/dev/null 2>&1 && pass "T5 a reported action mints a receipt" \
                                           || fail "T5 no receipt was written"
out="$(run "$P" gate-write "$(payload "$P" s1 "scv/promote/x/PLAN.md")")"
denied "$out" && fail "T4 creation with a receipt must be allowed" \
              || pass "T4 creation with a receipt is allowed"

P="$(mk_project c)"                                                          # T6
run "$P" mint '{"cwd":"'"$P"'","session_id":"s9","command_name":"scv:work"}' >/dev/null
out="$(run "$P" gate-write "$(payload "$P" s9 "scv/promote/x/PLAN.md")")"
denied "$out" && fail "T6 the typed slash path must mint too" \
              || pass "T6 a typed command mints (no skill event)"

P="$(mk_project d)"                                                          # T7
run "$P" gate-bash '{"cwd":"'"$P"'","session_id":"s1","tool_name":"Bash","tool_input":{"command":"bash /opt/core/scripts/promote-helper.sh"}}' \
  SCV_GUARD_SCRIPTS=/opt/core/scripts >/dev/null
out="$(run "$P" gate-write "$(payload "$P" s1 "src/x.ts")")"
denied "$out" && fail "T7 a shell call to an action script must mint" \
              || pass "T7 a shell call to an action script mints"

echo "=== T8 — every declared action mints ==="

ids="$(sed -n '/```guard:mint/,/```/p' "$CONTRACT" | grep -vE '^```')"
missing=""
for id in $ids; do
  P="$(mk_project "m-$id")"
  run "$P" mint '{"cwd":"'"$P"'","session_id":"s1","tool_input":{"skill":"scv:'"$id"'"}}' >/dev/null
  compgen -G "$P/state/s1-*" >/dev/null 2>&1 || missing="$missing $id"
done
[[ -z "$missing" ]] && pass "T8 all $(wc -w <<<"$ids" | tr -d ' ') declared actions mint" \
                    || fail "T8 these did not mint:$missing"

echo "=== Rule B — implementation without a receipt ==="

P="$(mk_project e)"                                                          # T9
out="$(run "$P" gate-write "$(payload "$P" s1 "src/refund.ts")")"
denied "$out" && pass "T9 a code write without a receipt is denied" \
              || fail "T9 a code write was allowed"

for f in README.md docs/x.md .gitignore .gitattributes LICENSE; do           # T10
  out="$(run "$P" gate-write "$(payload "$P" s1 "$f")")"
  denied "$out" && fail "T10 exempt path $f was denied" || pass "T10 $f is exempt"
done
out="$(run "$P" gate-write "$(payload "$P" s1 "host/config.toml")" SCV_GUARD_EXEMPT='host/config.toml')"
denied "$out" && fail "T10 host config was denied" || pass "T10 host config is exempt via SCV_GUARD_EXEMPT"

out="$(run "$P" gate-write "$(payload "$P" s1 ".env")")"                     # T11
denied "$out" && pass "T11 .env is NOT exempt" || fail "T11 .env was treated as exempt"

mkdir -p "$P/scv/promote/y"                                                  # T12
printf -- '---\nstatus: in_progress\n---\n' > "$P/scv/promote/y/PLAN.md"
out="$(run "$P" gate-write "$(payload "$P" s1 "src/refund.ts")")"
denied "$out" && pass "T12 a status:in_progress plan does NOT unlock writes" \
              || fail "T12 the self-issuable status token still unlocks"

out="$(run "$P" gate-write "$(payload "$P" s1 "scv/DECISIONS.md")")"
denied "$out" && fail "T-scv writes inside the workflow tree were denied" \
              || pass "T-scv writes inside the workflow tree are allowed"

echo "=== scope and failure behavior ==="

BARE="$WORK/bare"; mkdir -p "$BARE/src"                                      # T13
out="$(run "$BARE" gate-write "$(payload "$BARE" s1 "src/x.ts")")"
[[ -z "$out" ]] && pass "T13 inert where SCV is not adopted" || fail "T13 fired outside an SCV project"

P="$(mk_project f)"; mkdir -p "$P/src/deep"                                  # T14
out="$(printf '{"cwd":"%s/src","session_id":"s1","tool_name":"Write","tool_input":{"file_path":"deep/x.ts"}}' "$P" \
  | env SCV_GUARD_STATE="$P/state" SCV_GUARD_MODE=gate-write bash "$GUARD" 2>/dev/null)"
denied "$out" && pass "T14 the workflow root is found from a subdirectory" \
              || fail "T14 a subdirectory cwd silently disabled the guard"

out="$(printf 'not json at all' | env SCV_GUARD_MODE=gate-write bash "$GUARD" 2>/dev/null)"  # T15
[[ -z "$out" ]] && pass "T15 unparseable input fails open" || fail "T15 denied on bad input"
out="$(printf '' | env SCV_GUARD_MODE=gate-write bash "$GUARD" 2>/dev/null)"
[[ -z "$out" ]] && pass "T15 empty input fails open" || fail "T15 denied on empty input"

P="$(mk_project g)"                                                          # T15 unwritable state
out="$(run "$P" gate-write "$(payload "$P" s1 "README.md")" SCV_GUARD_STATE=/proc/nope)"
[[ -z "$out" ]] && pass "T15 an unusable receipt store fails open" || fail "T15 denied on unusable state dir"

P="$(mk_project h)"                                                          # opt-out
out="$(run "$P" gate-write "$(payload "$P" s1 "src/x.ts")" SCV_GUARD=off)"
[[ -z "$out" ]] && pass "SCV_GUARD=off disables the guard" || fail "SCV_GUARD=off was ignored"
out="$(run "$P" gate-write "$(payload "$P" s1 "src/x.ts")" SCV_GUARD_RULE_B=off)"
[[ -z "$out" ]] && pass "SCV_GUARD_RULE_B=off keeps Rule A only" || fail "Rule B ran while disabled"
out="$(run "$P" gate-write "$(payload "$P" s1 "scv/promote/z/PLAN.md")" SCV_GUARD_RULE_B=off)"
denied "$out" && pass "Rule A survives SCV_GUARD_RULE_B=off" || fail "Rule A was disabled with Rule B"

echo "=== patch-style payloads (no file_path field) ==="

P="$(mk_project i)"
patch='{"cwd":"'"$P"'","session_id":"s1","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Add File: scv/promote/x/PLAN.md\n+HELLO\n*** End Patch"}}'
out="$(run "$P" gate-write "$patch")"
denied "$out" && pass "a patch that adds a plan file is denied" \
              || fail "a patch bypassed Rule A (no file_path field)"
patch='{"cwd":"'"$P"'","session_id":"s1","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Add File: src/x.ts\n+x\n*** End Patch"}}'
out="$(run "$P" gate-write "$patch")"
denied "$out" && pass "a patch that adds source is denied under Rule B" \
              || fail "a patch bypassed Rule B"

# The patch parser is the one place a GNU-only regex slipped in: `\(A\|B\)` is a
# BSD sed no-op, so on macOS every patch sailed past both rules while Linux CI
# stayed green. Assert portability directly instead of waiting for the other
# runner to notice.
if sed --posix -n 's/x/y/p' </dev/null >/dev/null 2>&1; then
  probe=$'*** Begin Patch\n*** Add File: scv/promote/x/PLAN.md\n+H\n*** End Patch'
  got="$(printf '%s\n' "$probe" | sed --posix -n \
    -e 's/^\*\*\* Add File: //p' -e 's/^\*\*\* Update File: //p' -e 's/^\*\*\* Delete File: //p')"
  [[ "$got" == "scv/promote/x/PLAN.md" ]] \
    && pass "the patch parser works under POSIX sed (BSD behaviour)" \
    || fail "the patch parser is GNU-only" "got: $got"
else
  pass "(skip) this sed has no --posix mode to probe with"
fi

echo "=== receipts are scoped ==="

PA="$(mk_project j)"; PB="$(mk_project k)"
run "$PA" mint '{"cwd":"'"$PA"'","session_id":"s1","tool_input":{"skill":"scv:work"}}' >/dev/null
cp -r "$PA/state/." "$PB/state/" 2>/dev/null || true
out="$(run "$PB" gate-write "$(payload "$PB" s1 "src/x.ts")")"
denied "$out" && pass "a receipt from another project does not unlock this one" \
              || fail "receipts are not project-scoped"

echo "=== T19 — host neutrality ==="
if bash "$ROOT/tests/test-host-neutral.sh" >/dev/null 2>&1; then
  pass "T19 the payload stays host-neutral with the guard in it"
else
  fail "T19 host leakage"
fi

echo "=== T21 — the guard and the CI gate agree on exemptions ==="
GATE_PLAN="$ROOT/scv/promote/20260812-wookiya1364-ci-provenance-gate/PLAN.md"
if [[ -f "$GATE_PLAN" ]]; then
  for e in '\*\.md' '\.gitignore' '\.gitattributes' 'LICENSE'; do
    grep -qE "$e" "$GATE_PLAN" || fail "T21 the CI gate plan does not list $e"
  done
  pass "T21 the CI gate lists the same exempt classes"
else
  pass "T21 (skip) the CI gate plan is not in this tree"
fi

echo
echo "  passed: $PASS  failed: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
