#!/usr/bin/env bash
# test-run-focused.sh — 집중 시험 실행 도구가 시험을 동시에 돌리고, 실패를 숨기지 않으며,
# '# scv-test: serial' 표시가 붙은 시험은 다른 시험이 다 끝난 뒤 혼자 돌리는지 본다.
# 가짜 시험 폴더만 쓴다 — 실제 시험은 돌리지 않는다.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUNNER="$HERE/run-focused.sh"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-run-focused.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

now() { python3 -c 'import time; print("%.3f" % time.time())' 2>/dev/null || date +%s; }
mk() {  # <dir> <name> <body>  — 가짜 시험 하나
  mkdir -p "$1"; printf '#!/usr/bin/env bash\n%s\n' "$3" > "$1/test-$2.sh"
}
stamp() {  # <name> — 시작 · 끝 시각을 남기고 잠깐 쉬는 시험 몸통
  printf 'echo "%s start $(%s)" >> "%s"; sleep 1; echo "%s end $(%s)" >> "%s"' \
    "$1" "python3 -c 'import time; print(\"%.3f\" % time.time())'" "$WORK/stamps" \
    "$1" "python3 -c 'import time; print(\"%.3f\" % time.time())'" "$WORK/stamps"
}
run() { local b="$1"; shift; "$b" "$RUNNER" "$@" 2>&1; }

for BASH_BIN in bash /bin/bash; do
  [[ -x "$(command -v "$BASH_BIN")" ]] || continue
  v="$("$BASH_BIN" -c 'echo ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}')"
  echo "── $BASH_BIN ($v) ──"

  # T1 — 모두 통과하면 0
  D="$WORK/t1-$v"; for n in a b c; do mk "$D" "$n" "echo ok-$n"; done
  out="$(run "$BASH_BIN" --dir "$D" --jobs 3)"; rc=$?
  [[ $rc -eq 0 && "$(grep -c '^PASS' <<< "$out")" == 3 && "$out" == *"pass=3 fail=0"* ]] \
    && ok "T1 모두 통과 → 종료 0, 통과 줄 3" || fail "T1 rc=$rc: $out"

  # T2 — 하나라도 실패하면 1, 이름과 로그 전문
  D="$WORK/t2-$v"; mk "$D" a "echo ok"; mk "$D" b "echo ok"
  mk "$D" boom "echo first-line; echo UNIQUE-FAILURE-TEXT-42; exit 3"
  out="$(run "$BASH_BIN" --dir "$D" --jobs 3)"; rc=$?
  [[ $rc -ne 0 ]] && ok "T2 실패가 있으면 종료 코드 0 아님 ($rc)" || fail "T2 종료 코드 0"
  grep -Eq '^FAIL .*test-boom(\.sh)?$' <<< "$out" && grep -q 'FAIL test-boom' <<< "$out" \
    && ok "T2 실패한 시험 이름이 표와 로그 머리에 있다" || fail "T2 이름 없음: $out"
  grep -q 'first-line' <<< "$out" && grep -q 'UNIQUE-FAILURE-TEXT-42' <<< "$out" \
    && ok "T2 실패 로그 전문이 보인다" || fail "T2 로그 없음: $out"

  # T3 — serial 표시 시험은 다른 시험이 모두 끝난 뒤에 시작
  D="$WORK/t3-$v"; : > "$WORK/stamps"
  for n in p1 p2 p3; do mk "$D" "$n" "$(stamp "$n")"; done
  mk "$D" "a-serial" "# scv-test: serial
$(stamp serial)"
  run "$BASH_BIN" --dir "$D" --jobs 3 >/dev/null
  s_start="$(awk '$1=="serial" && $2=="start" {print $3}' "$WORK/stamps")"
  last_end="$(awk '$1!="serial" && $2=="end" {print $3}' "$WORK/stamps" | sort -n | tail -1)"
  [[ -n "$s_start" && -n "$last_end" ]] && awk -v s="$s_start" -v e="$last_end" 'BEGIN { exit !(s >= e) }' \
    && ok "T3 혼자 시험은 다른 시험이 다 끝난 뒤 시작 (겹침 0)" || fail "T3 겹침: serial=$s_start last_end=$last_end"

  # T4 · T5 — 동시에 돈다 / --jobs 1 이면 차례로
  D="$WORK/t4-$v"; for n in a b c d; do mk "$D" "$n" "sleep 2"; done
  t0="$(now)"; run "$BASH_BIN" --dir "$D" --jobs 4 >/dev/null; t1="$(now)"
  awk -v a="$t0" -v b="$t1" 'BEGIN { exit !(b - a < 7.5) }' \
    && ok "T4 2초 시험 4개를 동시 4로 7.5초 안에(차례로면 8초)" || fail "T4 느림: $t0 → $t1"
  t0="$(now)"; out="$(run "$BASH_BIN" --dir "$D" --jobs 1)"; t1="$(now)"
  awk -v a="$t0" -v b="$t1" 'BEGIN { exit !(b - a >= 8) }' && [[ "$out" == *"pass=4 fail=0 jobs=1"* ]] \
    && ok "T5 --jobs 1 이면 차례로(8초 이상), 통과 4" || fail "T5: $t0 → $t1 $out"

  # 잘못된 인자는 시험을 돌리지 않고 2
  run "$BASH_BIN" --jobs 0 >/dev/null; rc=$?
  [[ $rc -eq 2 ]] && ok "--jobs 0 은 거절(2)" || fail "--jobs 0 rc=$rc"
  out="$(run "$BASH_BIN" --dir "$WORK/empty-$v")"; rc=$?
  [[ $rc -ne 0 ]] && ok "없는 폴더는 실패로 끝난다" || fail "없는 폴더 rc=0"
done

# T6 — classify · summarize 는 순수: 같은 입력 → 같은 출력, 파일을 만들지 않는다
echo "── T6 순수 함수 ──"
P="$WORK/pure"; mkdir -p "$P"
pure() { (cd "$P" && source "$RUNNER" && "$@"); }
IN="$(printf 'x/test-a.sh\t\nx/test-b.sh\tserial\n')"
a="$(pure rf_classify <<< "$IN")"; b="$(pure rf_classify <<< "$IN")"
[[ "$a" == "$b" && "$a" == "$(printf 'parallel\tx/test-a.sh\nserial\tx/test-b.sh')" ]] \
  && ok "T6 classify: 같은 입력 → 같은 출력" || fail "T6 classify: [$a]"
R="$(printf 'test-a\t0\t3\ntest-b\t1\t9\ntest-c\t0\t12\n')"
a="$(pure rf_summarize <<< "$R")"; b="$(pure rf_summarize <<< "$R")"
want="$(printf 'ROW\tPASS\t12\ttest-c\nROW\tFAIL\t9\ttest-b\nROW\tPASS\t3\ttest-a\nFAILED\ttest-b\nTOTAL\t2\t1')"
[[ "$a" == "$b" && "$a" == "$want" ]] && ok "T6 summarize: 오래 걸린 순 표 · 실패 목록 · 합계" || fail "T6 summarize: [$a]"
[[ -z "$(ls -A "$P")" ]] && ok "T6 두 함수는 파일을 만들지 않는다" || fail "T6 파일 생김: $(ls -A "$P")"

# T12 — 조각 나누기: 빠짐 · 겹침 0, 고르게, 같은 입력 → 같은 출력
echo "── T12 조각 나누기 ──"
IN="$(for n in a b c d e f g h i j; do printf 'parallel\tx/core/tests/test-%s.sh\n' "$n"; done)"
TM="$(printf '# 주석 줄\ncore/tests/test-a.sh\t100\ncore/tests/test-b.sh\t40\ncore/tests/test-c.sh\t35\ncore/tests/test-d.sh\t30\ncore/tests/test-e.sh\t20\ncore/tests/test-f.sh\t10\ncore/tests/test-g.sh\t8\ncore/tests/test-h.sh\t6\ncore/tests/test-i.sh\t4\n')"
s1="$(pure rf_partition "$TM" 1 3 <<< "$IN")"; s2="$(pure rf_partition "$TM" 2 3 <<< "$IN")"; s3="$(pure rf_partition "$TM" 3 3 <<< "$IN")"
all="$(printf '%s\n%s\n%s\n' "$s1" "$s2" "$s3" | grep . | LC_ALL=C sort)"
[[ "$all" == "$(printf '%s\n' "$IN" | grep . | LC_ALL=C sort)" && -z "$(printf '%s\n' "$all" | uniq -d)" ]] \
  && ok "T12 세 조각을 합치면 원래 목록 — 빠짐 0 · 겹침 0" || fail "T12 합집합/겹침: [$all]"
[[ "$s1" == "$(printf 'parallel\tx/core/tests/test-a.sh')" ]] && ok "T12 가장 긴 시험(100초)은 혼자 첫 조각" || fail "T12 첫 조각: [$s1]"
load() { printf '%s\n' "$1" | TM="$TM" awk -F'\t' 'BEGIN{n=split(ENVIRON["TM"],L,"\n");for(i=1;i<=n;i++){split(L[i],f,"\t");w[f[1]]=f[2]}} NF>=2{k=$2; sub(/^.*\/core\//,"core/",k); s+=(k in w)?w[k]:5} END{print s+0}'; }
l2="$(load "$s2")"; l3="$(load "$s3")"; d=$(( l2 > l3 ? l2 - l3 : l3 - l2 ))
[[ -n "$l2" && -n "$l3" && "$l2" != 0 ]] && (( d <= 100 )) && ok "T12 나머지 두 조각 합 ${l2}초 · ${l3}초 — 차이 ≤ 가장 긴 시험" || fail "T12 고르지 않음: $l2 / $l3"
[[ "$(pure rf_partition "$TM" 2 3 <<< "$IN")" == "$s2" ]] && ok "T12 같은 입력 → 같은 조각" || fail "T12 결과가 바뀜"
[[ "$(pure rf_key /a/b/core/tests/test-x.sh)" == "core/tests/test-x.sh" && "$(pure rf_key repo/tests/test-y.sh)" == "tests/test-y.sh" ]] \
  && ok "T12 이름표: 어느 폴더에서 돌려도 core/tests/… · tests/…" || fail "T12 이름표"

# 조각 실행: 두 조각이 모든 시험을 한 번씩 돌린다(빈 시간 기록 — 모두 5초로 침)
D="$WORK/shard"; for n in a b c d e; do mk "$D" "$n" "echo ran-$n"; done
o1="$(bash "$RUNNER" --dir "$D" --shard 1/2 --timings /dev/null)"; r1=$?; o2="$(bash "$RUNNER" --dir "$D" --shard 2/2 --timings /dev/null)"; r2=$?
c1="$(grep -c '^PASS' <<< "$o1")"; c2="$(grep -c '^PASS' <<< "$o2")"
[[ $r1 -eq 0 && $r2 -eq 0 && $((c1 + c2)) -eq 5 && "$o1" == *"jobs=1 shard=1/2"* ]] \
  && ok "T12 조각 1/2 · 2/2 가 다섯 시험을 한 번씩 (${c1}+${c2}), 조각 안은 동시 1" || fail "T12 조각 실행: $o1 / $o2"
bash "$RUNNER" --dir "$D" --shard 3/2 >/dev/null 2>&1; [[ $? -eq 2 ]] && ok "T12 --shard 3/2 는 거절(2)" || fail "T12 3/2 허용"

echo "test-run-focused: PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
