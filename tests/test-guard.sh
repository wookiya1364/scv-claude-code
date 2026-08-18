#!/usr/bin/env bash
# Workspace guard — T1..T19, T21..T28 from the plan's TESTS.md.
#
# The guard's whole value rests on two properties that pull against each other:
# it must deny the bypasses, and it must never deny an SCV action's own work.
# The second is the one that kills the feature in the field — a guard users
# switch off is worth less than no guard at all — so the allow cases here are as
# load-bearing as the deny cases.

set -uo pipefail

# This file ships in two layouts and must find its subject in both. In the
# Core repository it sits at core/tests/, two levels below the repo root, and
# the payload is core/. A wrapper projects it to repo-root tests/, one level
# down, with the payload vendored at vendor/scv-core/core/. The old
# "two levels up, then core/" arithmetic was right for exactly one of those —
# on the wrapper it resolved to the PARENT of the repository and 13 cases
# failed there, unseen, because no wrapper CI ran this file. Search the
# plausible (root, payload) pairs and take the one where the guard exists.
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="" CORE=""
for up in "$HERE/.." "$HERE/../.."; do
  for sub in core vendor/scv-core/core plugins/scv/vendor/scv-core/core; do
    if [[ -f "$up/$sub/template/hooks/guard.sh" ]]; then
      ROOT="$(cd "$up" && pwd)"
      CORE="$(cd "$up/$sub" && pwd)"
      break 2
    fi
  done
done
if [[ -z "$CORE" ]]; then
  echo "test-guard: could not locate the guard payload from $HERE" >&2
  exit 1
fi
GUARD="$CORE/template/hooks/guard.sh"
CONTRACT="$CORE/contracts/guard.md"
ACTIONS_JSON="$CORE/actions.json"

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

# T15 — an unusable receipt store fails CLOSED, and says so. The old case here
# asserted the opposite ("fails open") against README.md — a file the exempt
# list allows regardless of receipts, so it passed no matter what the guard
# did, and the wrong claim survived into the contract. The target must be
# non-exempt or this case judges nothing; the sanity check below enforces that.
T15_TARGET="src/x.ts"
case "$T15_TARGET" in
  *.md|.gitignore|.gitattributes|LICENSE) fail "T15 self-check: target is exempt — the case would be vacuous" ;;
esac
P="$(mk_project g)"
out="$(env SCV_GUARD_STATE=/proc/nope SCV_GUARD_MODE=gate-write \
  bash "$GUARD" <<<"$(payload "$P" s1 "$T15_TARGET")" 2>/dev/null)"
denied "$out" && pass "T15 an unusable receipt store fails closed" \
              || fail "T15 a broken store allowed a non-exempt write"
grep -q "receipt store" <<<"$out" && grep -q "SCV_GUARD_STATE" <<<"$out" \
  && pass "T15 the deny reason names the store, not the workflow" \
  || fail "T15 the deny reason does not explain the broken store" "$out"
# Minting into the broken store is best-effort but no longer silent.
merr="$(printf '{"cwd":"%s","session_id":"s1","tool_input":{"skill":"promote"}}' "$P" \
  | env SCV_GUARD_STATE=/proc/nope SCV_GUARD_MODE=mint bash "$GUARD" 2>&1 >/dev/null)"
grep -q "receipt store" <<<"$merr" \
  && pass "T15 a failed mint warns on stderr" \
  || fail "T15 a failed mint is silent" "$merr"

P="$(mk_project h)"                                                          # opt-out
out="$(run "$P" gate-write "$(payload "$P" s1 "src/x.ts")" SCV_GUARD=off)"
[[ -z "$out" ]] && pass "SCV_GUARD=off disables the guard" || fail "SCV_GUARD=off was ignored"
out="$(run "$P" gate-write "$(payload "$P" s1 "src/x.ts")" SCV_GUARD_RULE_B=off)"
[[ -z "$out" ]] && pass "SCV_GUARD_RULE_B=off keeps Rule A only" || fail "Rule B ran while disabled"
out="$(run "$P" gate-write "$(payload "$P" s1 "scv/promote/z/PLAN.md")" SCV_GUARD_RULE_B=off)"
denied "$out" && pass "Rule A survives SCV_GUARD_RULE_B=off" || fail "Rule A was disabled with Rule B"

echo "=== T29 — SCV_GUARD_SCRIPTS accepts a colon-separated list ==="
# One directory was not enough in the field: an adapter's own scripts live
# outside the vendored core/scripts, and with a single fixed string the
# adapter-owned actions could never mint. Each entry keeps the fixed-string
# match; the regression half asserts the second entry actually mints, because
# on the old single-value guard the whole list is one string nothing contains.
P="$(mk_project multi)"
mkdir -p "$WORK/dirA" "$WORK/dirB"
bashpay() { printf '{"cwd":"%s","session_id":"%s","tool_name":"Bash","tool_input":{"command":"bash %s/run.sh"}}' "$1" "$2" "$3"; }
out="$(run "$P" gate-bash "$(bashpay "$P" m1 "$WORK/dirA")" SCV_GUARD_SCRIPTS="$WORK/dirA:$WORK/dirB")"
ls "$P/state" 2>/dev/null | grep -q "^m1-" && pass "T29 the first listed directory mints" \
                                           || fail "T29 the first listed directory did not mint"
out="$(run "$P" gate-bash "$(bashpay "$P" m2 "$WORK/dirB")" SCV_GUARD_SCRIPTS="$WORK/dirA:$WORK/dirB")"
ls "$P/state" 2>/dev/null | grep -q "^m2-" && pass "T29 the second listed directory mints" \
                                           || fail "T29 the second listed directory did not mint (single-string regression)"
out="$(run "$P" gate-bash "$(bashpay "$P" m3 "$WORK/dirC")" SCV_GUARD_SCRIPTS="$WORK/dirA:$WORK/dirB")"
ls "$P/state" 2>/dev/null | grep -q "^m3-" && fail "T29 an unlisted directory minted" \
                                           || pass "T29 an unlisted directory does not mint"
out="$(run "$P" gate-bash "$(bashpay "$P" m4 "$WORK/dirA")" SCV_GUARD_SCRIPTS="$WORK/dirA")"
ls "$P/state" 2>/dev/null | grep -q "^m4-" && pass "T29 the single-value form still mints (compatibility)" \
                                           || fail "T29 the single-value form broke"

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
# The host-neutral checker lives in the Core repository's own tests/, which is
# not part of the shipped payload — a wrapper runs the vendored core/ alone, and
# CI copies just that directory into a scratch dir. Calling it unconditionally
# turned a missing file into a reported host leak on every wrapper.
NEUTRAL="$ROOT/tests/test-host-neutral.sh"
if [[ -f "$NEUTRAL" ]]; then
  if bash "$NEUTRAL" >/dev/null 2>&1; then
    pass "T19 the payload stays host-neutral with the guard in it"
  else
    fail "T19 host leakage"
  fi
else
  # Assert the property directly instead of skipping: the guard is the file this
  # suite is about, and its neutrality is checkable without the repo harness.
  # Assembled at runtime, never written out: this file lives under core/, which
  # the repo-side checker scans, so a literal list here would make the test that
  # asserts neutrality the thing that violates it.
  leak=""
  for token in "Cla""ude" "Co""dex" "CLA""UDE_PLUGIN_ROOT" ".cla""ude" ".co""dex"; do
    grep -qF -- "$token" "$GUARD" && leak="$leak $token"
  done
  [[ -z "$leak" ]] && pass "T19 the guard script names no host (repo harness absent)" \
                   || fail "T19 host leakage in the guard:$leak"
fi

echo "=== T21 — the guard and the CI gate agree on exemptions ==="
# Compared against the two SCRIPTS, not against a plan document. The first
# version of this case keyed on a promote-folder PLAN.md, which the workflow
# later archived — the condition went permanently false and the case reported
# a green skip forever. Both scripts ship in the payload, so the comparison
# has no precondition and always runs.
GATE="$CORE/scripts/check-provenance.sh"
if [[ ! -f "$GATE" ]]; then
  fail "T21 check-provenance.sh is missing from the payload"
else
  for e in '\*\.md' '\.gitignore' '\.gitattributes' 'LICENSE'; do
    grep -qE -- "$e" "$GUARD" || fail "T21 the guard does not exempt $e"
    grep -qE -- "$e" "$GATE"  || fail "T21 the CI gate does not exempt $e"
  done
  pass "T21 the guard and the CI gate carry the same exempt classes"
fi

echo "=== T31 — a hostile path cannot corrupt the deny JSON ==="
# The deny reason embeds the payload's own file path. A control character in
# it would make the output unparseable — and an unparseable hook decision is
# no decision, which is an allow. The attacker names the file, so the guard
# must sanitize.
P="$(mk_project ctl)"
evil="$(printf 'src/x\\u0001b.ts')"
out="$(printf '{"cwd":"%s","session_id":"s1","tool_name":"Write","tool_input":{"file_path":"src/x\\u0001b.ts"}}' "$P" \
  | env SCV_GUARD_STATE="$P/state" SCV_GUARD_MODE=gate-write bash "$GUARD" 2>/dev/null)"
if command -v jq >/dev/null 2>&1; then
  printf '%s' "$out" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1 \
    && pass "T31 the deny survives a control character as valid JSON" \
    || fail "T31 a control character broke the deny output" "$out"
else
  denied "$out" && pass "T31 (no jq) the deny fired" || fail "T31 no deny" "$out"
fi

echo "=== T32 — malformed SCV_GUARD_SCRIPTS entries are dropped, not matched ==="
# A whitespace-only entry is a fixed string every command contains; a relative
# fragment is nearly as broad. Either would turn the mint hook into
# mint-everything, which unlocks Rule A for free.
P="$(mk_project malformed)"
out="$(run "$P" gate-bash "$(printf '{"cwd":"%s","session_id":"w1","tool_name":"Bash","tool_input":{"command":"echo hello"}}' "$P")" SCV_GUARD_SCRIPTS="$WORK/dirA: :$WORK/dirB")"
ls "$P/state" 2>/dev/null | grep -q "^w1-" && fail "T32 a whitespace entry minted on an arbitrary command" \
                                           || pass "T32 a whitespace-only entry does not mint"
out="$(run "$P" gate-bash "$(printf '{"cwd":"%s","session_id":"w2","tool_name":"Bash","tool_input":{"command":"echo scripts"}}' "$P")" SCV_GUARD_SCRIPTS="scripts")"
ls "$P/state" 2>/dev/null | grep -q "^w2-" && fail "T32 a relative entry minted on an arbitrary command" \
                                           || pass "T32 a relative entry does not mint"
out="$(run "$P" gate-bash "$(bashpay "$P" w3 "$WORK/dirA")" SCV_GUARD_SCRIPTS=" $WORK/dirA : $WORK/dirB ")"
ls "$P/state" 2>/dev/null | grep -q "^w3-" && pass "T32 surrounding whitespace is trimmed, the real entry mints" \
                                           || fail "T32 a hand-wrapped list stopped minting"

echo "=== T33 — an unwritable receipt FILE gets the same honest reason ==="
P="$(mk_project rcpt)"
mkdir -p "$P/state"
# Recreate the receipt name the guard derives: <session>-<project-key>.
printf '{"cwd":"%s","session_id":"s1","tool_input":{"skill":"promote"}}' "$P" \
  | env SCV_GUARD_STATE="$P/state" SCV_GUARD_MODE=mint bash "$GUARD" >/dev/null 2>&1
rf="$(ls "$P/state" | head -1)"
if [[ -n "$rf" ]]; then
  : > "$P/state/$rf"; chmod 444 "$P/state/$rf"
  out="$(run "$P" gate-write "$(payload "$P" s1 "src/x.ts")")"
  grep -q "receipt store" <<<"$out" && pass "T33 the deny names the store when only the FILE is unwritable" \
                                    || fail "T33 the unwritable-file shape got the misleading workflow reason" "$out"
  chmod 644 "$P/state/$rf"
else
  fail "T33 could not derive the receipt path"
fi

if [[ -z "${SCV_TESTGUARD_INNER:-}" ]]; then
  echo "=== T30 — this suite passes from a wrapper-projected layout ==="
  # A wrapper projects this file to repo-root tests/ with the payload vendored
  # at vendor/scv-core/core/. Rebuild that shape and replay the whole suite in
  # it — the one arrangement where the old root arithmetic failed 13 cases,
  # invisibly, because no wrapper CI ran the file. The env guard stops the
  # inner copy from recursing again.
  WRAP="$WORK/wrap"
  mkdir -p "$WRAP/tests" "$WRAP/vendor/scv-core"
  cp -R "$CORE" "$WRAP/vendor/scv-core/core"
  cp "${BASH_SOURCE[0]}" "$WRAP/tests/test-guard.sh"
  if SCV_TESTGUARD_INNER=1 bash "$WRAP/tests/test-guard.sh" >/dev/null 2>&1; then
    pass "T30 the wrapper layout (tests/ + vendor/scv-core/core) passes"
  else
    fail "T30 the wrapper-projected copy fails — root resolution regressed"
  fi
fi

echo
echo "  passed: $PASS  failed: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
