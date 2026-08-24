#!/usr/bin/env bash
# test-regression-memo.sh — suite-gate memoization (v0.34.0).
#
# 22 of 28 archived contracts call the whole suite; the runner now runs each
# distinct gate command once per run and lets later blocks reuse its exit code.
# The contract's own assertions still run every time — only the three exact
# gate invocations are memoized.
#   T1. three slugs calling `bash core/tests/run-dry.sh` → the stub runs ONCE, all three pass
#   T2. a failing gate is reused as a failure (all three fail, stub ran once)
#   T3. --no-memo runs the gate per slug (stub runs three times)
#   T4. the core-tests loop is memoized as a unit; a slug's own extra command still runs per slug
#   T5. a block with no gate is untouched (byte-identical rewrite)
set -uo pipefail
HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CORE="$HERE/.."
RUNNER="$CORE/scripts/regression.sh"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL+1)); }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

mk_project() {  # mk_project <name> <gate-exit> — hydrated-looking project with a counting gate stub
  local p="$WORK/$1" rc="$2"
  mkdir -p "$p/scv/archive" "$p/core/tests" "$p/tests"
  ( cd "$p" && git init -q && git config user.name t && git config user.email t@x )
  printf '#!/usr/bin/env bash\necho x >> "%s/counter-rundry"\nexit %s\n' "$p" "$rc" > "$p/core/tests/run-dry.sh"
  printf '#!/usr/bin/env bash\necho x >> "%s/counter-testsrun"\nexit 0\n' "$p" > "$p/tests/run.sh"
  printf '#!/usr/bin/env bash\necho x >> "%s/counter-coretest"\nexit 0\n' "$p" > "$p/core/tests/test-alpha.sh"
  printf '%s\n' "$p"
}
mk_slug() {  # mk_slug <project> <slug> <block...>
  local p="$1" s="$2"; shift 2
  mkdir -p "$p/scv/archive/$s"
  printf -- '---\ntitle: %s\nslug: %s\nauthor: tester\ncreated_at: 2026-08-24\nstatus: done\nkind: feature\nlang: english\n---\n\n# %s\n' "$s" "$s" "$s" > "$p/scv/archive/$s/PLAN.md"
  { printf '# Test Plan — %s\n\n## How to run\n\n```bash\n' "$s"; printf '%s\n' "$@"; printf '```\n\n## Pass criteria\n\n- exit 0\n'; } > "$p/scv/archive/$s/TESTS.md"
}
count() { [[ -f "$1" ]] && wc -l < "$1" | tr -d ' ' || echo 0; }

echo "── T1 passing gate runs once, all slugs pass ──"
P="$(mk_project t1 0)"
for s in a b c; do mk_slug "$P" "20260824-tester-$s" "bash -euo pipefail -c '" "fail() { echo FAIL; exit 1; }" "echo own-assertion-$s >> \"$P/own\"" "bash core/tests/run-dry.sh >/dev/null || fail run-dry" "'"; done
out="$(cd "$P" && bash "$RUNNER" --quiet 2>&1)"
grep -q "PASSED_SLUGS: 3" <<<"$out" && ok "three slugs pass" || fail "T1 not all passed: $(grep -E 'FAILED_SLUGS|✗' <<<"$out" | head -2)"
[[ "$(count "$P/counter-rundry")" == "1" ]] && ok "the gate ran once for three slugs" || fail "T1 gate ran $(count "$P/counter-rundry") times"
[[ "$(count "$P/own")" == "3" ]] && ok "each slug's own assertion still ran" || fail "T1 own assertions ran $(count "$P/own") times"
grep -q "MEMOIZED_GATES: 1 (reused 2 time(s))" <<<"$out" && ok "summary reports 1 gate, 2 reuses" || fail "T1 summary: $(grep MEMOIZED <<<"$out")"

echo "── T2 failing gate is reused as a failure ──"
P="$(mk_project t2 1)"
for s in a b c; do mk_slug "$P" "20260824-tester-$s" "bash -euo pipefail -c '" "bash core/tests/run-dry.sh >/dev/null || { echo FAIL-gate; exit 1; }" "'"; done
out="$(cd "$P" && bash "$RUNNER" --quiet 2>&1)"
grep -q "FAILED_SLUGS: 3" <<<"$out" && ok "all three fail on the shared red gate" || fail "T2: $(grep -E 'PASSED|FAILED' <<<"$out" | head -2)"
[[ "$(count "$P/counter-rundry")" == "1" ]] && ok "the failing gate still ran only once" || fail "T2 gate ran $(count "$P/counter-rundry") times"

echo "── T3 --no-memo runs per slug ──"
P="$(mk_project t3 0)"
for s in a b c; do mk_slug "$P" "20260824-tester-$s" "bash core/tests/run-dry.sh"; done
out="$(cd "$P" && bash "$RUNNER" --quiet --no-memo 2>&1)"
[[ "$(count "$P/counter-rundry")" == "3" ]] && ok "--no-memo: gate ran three times" || fail "T3 gate ran $(count "$P/counter-rundry") times"
grep -q "MEMOIZED_GATES: 0" <<<"$out" && ok "--no-memo reports zero memoized gates" || fail "T3 summary: $(grep MEMOIZED <<<"$out")"

echo "── T4 core-tests loop + tests/run.sh memoized as units ──"
P="$(mk_project t4 0)"
for s in a b; do mk_slug "$P" "20260824-tester-$s" "bash -euo pipefail -c '" "fail() { echo FAIL; exit 1; }" "bash tests/run.sh >/dev/null || fail run" 'for t in core/tests/test-*.sh; do bash "$t" >/dev/null || fail "T $t"; done' "'"; done
out="$(cd "$P" && bash "$RUNNER" --quiet 2>&1)"
grep -q "PASSED_SLUGS: 2" <<<"$out" && ok "both slugs pass" || fail "T4: $(grep -E 'FAILED|✗' <<<"$out" | head -3)"
[[ "$(count "$P/counter-testsrun")" == "1" && "$(count "$P/counter-coretest")" == "1" ]] && ok "tests/run.sh and the core-tests loop each ran once" || fail "T4 counts: run=$(count "$P/counter-testsrun") core=$(count "$P/counter-coretest")"

echo "── T5 a block without gates is left byte-identical ──"
# shellcheck source=/dev/null
src="$(sed -n '/^memo_rewrite_block()/,/^}/p' "$RUNNER")"
[[ -n "$src" ]] && ok "rewrite function present" || fail "T5 rewrite function missing"
blk=$'echo hello\nbash core/tests/test-alpha.sh\nls -la'
res="$(cd "$WORK" && QUIET=1 TIMEOUT=5 bash -c 'source <(sed -n "/^declare -A MEMO_RC/,/^}/p" "'"$RUNNER"'" | head -1); '"$(sed -n '/^memo_rewrite_block()/,/^}/p' "$RUNNER" | sed 's/^/ /')"'; printf "%s\n" "$0" | memo_rewrite_block' "$blk" 2>/dev/null || true)"
[[ "$res" == "$blk" ]] && ok "no gate → unchanged" || fail "T5 rewrite changed a gate-free block: [$res]"

echo
echo "── result: PASS=$PASS FAIL=$FAIL ──"
[[ $FAIL -eq 0 ]] || exit 1
