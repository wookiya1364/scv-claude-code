#!/usr/bin/env bash
# test-regression-dedupe.sh — 회귀 시험: 같은 시험은 한 번만, 여러 개를 동시에 (2026-11-01).
#
# 계획: scv/archive/20261101-wookiya1364-regression-dedupe-parallel/TESTS.md
#   R1. 세 계획이 같은 시험 줄 → 한 번만 돈다, 셋 다 통과
#   R2. 2초짜리 서로 다른 시험 넷 → 동시에 돌아 5초 안
#   R3. 공유 시험이 실패하면 그것을 적은 계획만 실패
#   R4. serial 표시 시험은 다른 시험과 겹치지 않는다
#   R5. --no-memo 는 계획마다 돈다
#   R6. 시험 줄이 아닌 줄은 그 계획 안에서 돌아 판정에 반영된다
#   R6b. 다른 폴더로 옮겨 가는(cd) 계획은 공유 결과를 쓰지 않는다
set -uo pipefail
HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CORE="$HERE/.."
RUNNER="$CORE/scripts/regression.sh"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL+1)); }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-regression-dedupe.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT

mk_project() {  # mk_project <name> — 빈 git 저장소 + scv/archive + t/
  local p="$WORK/$1"
  mkdir -p "$p/scv/archive" "$p/t"
  ( cd "$p" && git init -q && git config user.name t && git config user.email t@x )
  printf '%s\n' "$p"
}
mk_test() {  # mk_test <project> <name> <body…> — t/<name>.sh
  local p="$1" n="$2"; shift 2
  { printf '#!/usr/bin/env bash\n'; printf '%s\n' "$@"; } > "$p/t/$n.sh"
}
mk_slug() {  # mk_slug <project> <slug> <block…>
  local p="$1" s="$2"; shift 2
  mkdir -p "$p/scv/archive/$s"
  printf -- '---\ntitle: %s\nslug: %s\nauthor: tester\ncreated_at: 2026-11-01\nstatus: done\nkind: feature\nlang: korean\n---\n\n# %s\n' "$s" "$s" "$s" > "$p/scv/archive/$s/PLAN.md"
  { printf '# Test Plan — %s\n\n## How to run\n\n```bash\n' "$s"; printf '%s\n' "$@"; printf '```\n\n## Pass criteria\n\n- exit 0\n'; } > "$p/scv/archive/$s/TESTS.md"
}
count() { [[ -f "$1" ]] && wc -l < "$1" | tr -d ' ' || echo 0; }
run() { OUT="$(cd "$1" && shift && SCV_TEST_JOBS=4 bash "$RUNNER" --quiet "$@" 2>&1)"; }

echo "R1. 같은 시험 줄은 한 번만"
P="$(mk_project r1)"
mk_test "$P" count "echo x >> \"$P/counter\""
for s in a b c; do mk_slug "$P" "20261101-tester-$s" "bash t/count.sh >/dev/null || exit 1"; done
run "$P"
[[ "$(count "$P/counter")" == 1 ]] && ok "세 계획에 한 번" || fail "R1 횟수 $(count "$P/counter")"
grep -q 'FAILED_SLUGS: 0' <<<"$OUT" && grep -q 'PASSED_SLUGS: 3' <<<"$OUT" && ok "셋 다 통과" || fail "R1 판정: $(grep -E 'PASSED|FAILED' <<<"$OUT" | tr '\n' ' ')"

echo "R1b. 한 줄에 이은 시험들도 하나씩 공유"
P="$(mk_project r1b)"
mk_test "$P" count "echo x >> \"$P/counter\""; mk_test "$P" ok "exit 0"
for s in a b c; do mk_slug "$P" "20261101-tester-$s" "bash t/ok.sh && bash t/count.sh >/dev/null || exit 1"; done
run "$P"
[[ "$(count "$P/counter")" == 1 ]] && ok "이은 줄의 두 번째 시험도 한 번" || fail "R1b 횟수 $(count "$P/counter")"
grep -q 'PASSED_SLUGS: 3' <<<"$OUT" && ok "셋 다 통과" || fail "R1b 판정"

echo "R2. 서로 다른 시험 넷이 동시에"
P="$(mk_project r2)"
for n in w1 w2 w3 w4; do mk_test "$P" "$n" "sleep 2"; mk_slug "$P" "20261101-tester-$n" "bash t/$n.sh"; done
t0=$(date +%s); run "$P"; t1=$(date +%s)
el=$((t1 - t0))
[[ $el -lt 5 ]] && ok "8초 분량을 ${el}초에" || fail "R2 ${el}초 — 동시에 돌지 않았다"
grep -q 'PASSED_SLUGS: 4' <<<"$OUT" && ok "넷 다 통과" || fail "R2 판정"

echo "R3. 공유 시험 실패는 그것을 적은 계획만"
P="$(mk_project r3)"
mk_test "$P" bad "exit 1"; mk_test "$P" good "exit 0"
mk_slug "$P" "20261101-tester-a" "bash t/bad.sh"
mk_slug "$P" "20261101-tester-b" "bash t/bad.sh || exit 1"
mk_slug "$P" "20261101-tester-c" "bash t/good.sh"
run "$P"
grep -q 'FAILED_SLUGS: 2' <<<"$OUT" && grep -q 'failed_slugs: 20261101-tester-a 20261101-tester-b' <<<"$OUT" && ok "a · b 만 실패" || fail "R3: $(grep -E 'FAILED|failed_slugs' <<<"$OUT" | tr '\n' ' ')"
grep -q 'shared test: bash t/bad.sh (exit 1)' <<<"$OUT" || true

echo "R3b. 동시에 돌 때만 실패하는 시험은 혼자 다시 돌아 통과"
P="$(mk_project r3b)"
for n in q1 q2; do mk_test "$P" "$n" "touch \"$P/busy.$n\"; sleep 1; rm -f \"$P/busy.$n\""; mk_slug "$P" "20261101-tester-$n" "bash t/$n.sh"; done
mk_test "$P" alone "sleep 0.3; ls \"$P\"/busy.* >/dev/null 2>&1 && exit 1; exit 0"
mk_slug "$P" "20261101-tester-alone" "bash t/alone.sh"
OUT="$(cd "$P" && SCV_TEST_JOBS=4 bash "$RUNNER" 2>&1)"
grep -q 'PASSED_SLUGS: 3' <<<"$OUT" && grep -q 'reran 1 failed shared test(s) alone' <<<"$OUT" && ok "혼자 다시 돌아 통과(1개)" || fail "R3b: $(grep -E 'PASSED|FAILED|reran' <<<"$OUT" | tr '\n' ' ')"

echo "R4. serial 표시 시험은 혼자"
P="$(mk_project r4)"
for n in p1 p2 p3; do mk_test "$P" "$n" "touch \"$P/running.$n\"; sleep 1; rm -f \"$P/running.$n\""; mk_slug "$P" "20261101-tester-$n" "bash t/$n.sh"; done
mk_test "$P" s1 "# scv-test: serial" "ls \"$P\"/running.* >/dev/null 2>&1 && echo overlap >> \"$P/overlap\"; exit 0"
mk_slug "$P" "20261101-tester-s1" "bash t/s1.sh"
run "$P"
[[ "$(count "$P/overlap")" == 0 ]] && ok "겹침 없음" || fail "R4 겹침 $(count "$P/overlap")"

echo "R5. --no-memo 는 계획마다"
P="$(mk_project r5)"
mk_test "$P" count "echo x >> \"$P/counter\""
for s in a b c; do mk_slug "$P" "20261101-tester-$s" "bash t/count.sh"; done
run "$P" --no-memo
[[ "$(count "$P/counter")" == 3 ]] && ok "세 번" || fail "R5 횟수 $(count "$P/counter")"

echo "R6. 시험 줄이 아닌 줄은 계획 안에서"
P="$(mk_project r6)"
mk_test "$P" good "exit 0"
echo x > "$P/has-x"; echo y > "$P/no-x"
mk_slug "$P" "20261101-tester-a" "bash t/good.sh" "grep -q x has-x"
mk_slug "$P" "20261101-tester-b" "bash t/good.sh" "grep -q x no-x"
run "$P"
grep -q 'FAILED_SLUGS: 1' <<<"$OUT" && grep -q 'failed_slugs: 20261101-tester-b' <<<"$OUT" && ok "grep 이 틀린 b 만 실패" || fail "R6: $(grep -E 'FAILED|failed_slugs' <<<"$OUT" | tr '\n' ' ')"

echo "R6b. 다른 폴더로 옮겨 가는 계획은 공유 결과를 쓰지 않는다"
P="$(mk_project r6b)"
mk_test "$P" count "echo x >> \"$P/counter\""
mkdir -p "$P/sub/t"; printf '#!/usr/bin/env bash\necho sub >> "%s/sub-counter"\n' "$P" > "$P/sub/t/count.sh"
mk_slug "$P" "20261101-tester-a" "bash t/count.sh"
mk_slug "$P" "20261101-tester-b" "cd sub && bash t/count.sh"
run "$P"
[[ "$(count "$P/counter")" == 1 && "$(count "$P/sub-counter")" == 1 ]] && ok "각자 제 시험을 돈다" || fail "R6b counter=$(count "$P/counter") sub=$(count "$P/sub-counter")"

echo
echo "── result: PASS=$PASS FAIL=$FAIL ──"
[[ $FAIL -eq 0 ]]
