#!/usr/bin/env bash
# test-resume-tail.sh — 비운 뒤에는 기록의 끝부분만 싣는다.
#
# 대화를 비운(clear) 직후 세션 시작 훅은 진행 중 대화 기록을 전체가 아니라 끝부분(12,000자, 턴 머리 줄에서 시작)으로
# 싣고, 전체 기록 파일의 자리를 한 줄로 알린다. 요약 · 재개 · 종류를 모르는 시작은 전과 같이 전체를 싣는다.
# 두 가지를 본다: 끝부분을 자르는 함수(scv_resume_tail)가 글자 수로 — 바이트가 아니라 — 자르는가 /
# 훅이 비운 뒤에만 그 함수를 쓰고, 자르지 못하면 전체를 싣는가.
#
# Covers TESTS.md T1–T5 of 20261125-wookiya1364-clear-lighten (T6–T10 은 대시보드 · 실제 앱).
#
# Run: bash core/tests/test-resume-tail.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE=""
for up in "$HERE/.." "$HERE/../.."; do
  for sub in core vendor/scv-core/core plugins/scv/vendor/scv-core/core; do
    if [[ -f "$up/$sub/scripts/lib/settings.sh" ]]; then CORE="$(cd "$up/$sub" && pwd)"; break 2; fi
  done
done
[[ -n "$CORE" ]] || { echo "test-resume-tail: payload not found from $HERE" >&2; exit 1; }

HOOK="$CORE/template/hooks/on-session-start.sh"
LIB="$CORE/scripts/lib/resume-recap.sh"
MAX=12000
PLACE="[SCV resume] full record: "

PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null

# shellcheck disable=SC1090
source "$LIB"
declare -F scv_resume_tail >/dev/null 2>&1 || scv_resume_tail() { return 127; }   # 함수가 아직 없으면 아래 시험이 실패로 보인다

# 글자 수 — 셸의 언어 설정과 상관없이 센다: 이어지는 바이트(0x80 ~ 0xBF)를 뺀 바이트 수가 글자 수다.
nchars() { printf '%s' "$1" | LC_ALL=C tr -d '\200-\277' | wc -c | tr -d '[:space:]'; }
# 글 B 가 글 A 의 끝과 바이트까지 같은가 — 큰 글을 셸 무늬로 견주면 옛 셸에서 느려서 파일로 견준다.
ends_with() {  # <A> <B>
  printf '%s' "$1" > "$WORK/ew-a"; printf '%s' "$2" > "$WORK/ew-b"
  [[ -s "$WORK/ew-b" ]] || return 1
  tail -c "$(wc -c < "$WORK/ew-b" | tr -d '[:space:]')" "$WORK/ew-a" | cmp -s - "$WORK/ew-b"
}
# 두 언어 설정에서 함수를 돌린다 — 결과는 같아야 한다.
tail_in() {  # <LC_ALL 값> <글> <최대 글자 수>
  ( export LC_ALL="$1"; scv_resume_tail "$2" "$3" ) 2>/dev/null
}

# 턴 머리가 있는 기록 글 — 턴마다 머리 줄 하나와 한글 줄 다섯. 첫 턴과 마지막 턴에 표식이 있다.
FILL="가나다라마바사아자차카타파하"; FILL="$FILL$FILL$FILL$FILL$FILL$FILL"   # 84자
record() {  # <턴 수>
  local n="$1" i j out=""
  for (( i = 1; i <= n; i++ )); do
    out+="## Turn $i"$'\n'
    (( i == 1 )) && out+="FIRST-TURN-MARK 첫 턴의 표식"$'\n'
    (( i == n )) && out+="LAST-TURN-MARK 마지막 턴의 표식"$'\n'
    for j in 1 2 3 4 5; do out+="턴 $i 의 줄 $j — $FILL"$'\n'; done
    out+=$'\n'
  done
  printf '%s' "${out%$'\n'$'\n'}"
}

echo "test-resume-tail: $CORE"

# ---------- T1 긴 기록은 끝부분만 남고 턴 머리에서 시작한다 ----------
REC="$(record 62)"; N="$(nchars "$REC")"
(( N >= 30000 )) && ok "T1 준비: 턴 머리가 여럿인 기록 ${N}자" || fail "T1 준비: 기록이 ${N}자뿐 (30,000자 이상이어야 한다)"
OUT="$(scv_resume_tail "$REC" "$MAX")"; RC=$?; n="$(nchars "$OUT")"
(( RC == 0 && n > 0 && n <= MAX )) && ok "T1 끝부분은 ${n}자 — 한도 ${MAX}자 이하" || fail "T1 길이 ${n}자 / rc=$RC"
[[ "${OUT%%$'\n'*}" == "## Turn "* ]] && ok "T1 첫 줄이 턴 머리 줄이다 (${OUT%%$'\n'*})" || fail "T1 첫 줄이 턴 머리가 아니다: [$(printf '%s' "${OUT%%$'\n'*}" | cut -c1-40)]"
[[ -n "$OUT" && "${OUT##*$'\n'}" == "${REC##*$'\n'}" ]] && ok "T1 마지막 줄이 원래 글의 마지막 줄과 같다" || fail "T1 마지막 줄이 다르다"
ends_with "$REC" "$OUT" && ok "T1 끝부분은 원래 글의 끝과 바이트까지 같다" || fail "T1 끝부분이 원래 글의 끝이 아니다"
# 한도 안의 '첫' 머리에서 시작한다 — 한 턴(약 500자)보다 많이 버리지 않는다.
(( n > MAX - 600 )) && ok "T1 한도 안의 첫 턴 머리에서 시작한다 (버린 것 $(( MAX - n ))자)" || fail "T1 너무 많이 버렸다: ${n}자"
[[ "$OUT" != *"FIRST-TURN-MARK"* && "$OUT" == *"LAST-TURN-MARK"* ]] && ok "T1 첫 턴은 없고 마지막 턴은 있다" || fail "T1 표식이 어긋난다"
A="$(tail_in C "$REC" "$MAX")"; B="$(tail_in en_US.UTF-8 "$REC" "$MAX")"
[[ -n "$A" && "$A" == "$OUT" && "$B" == "$OUT" ]] && ok "T1 언어 설정이 달라도 같은 글이 나온다 (C · UTF-8)" || fail "T1 언어 설정에 따라 결과가 다르다 (C $(nchars "$A")자 · UTF-8 $(nchars "$B")자)"
# 자른 자리가 줄의 첫 글자에 딱 맞으면 그 줄도 머리 줄로 친다.
EDGE=$'앞 글\n## Turn 1\n가나다\n## Turn 2\n라마바'
[[ "$(scv_resume_tail "$EDGE" 27)" == $'## Turn 1\n가나다\n## Turn 2\n라마바' ]] && ok "T1 자른 자리가 머리 줄의 처음이면 그 줄에서 시작한다" || fail "T1 경계의 머리 줄: [$(scv_resume_tail "$EDGE" 27)]"
[[ "$(scv_resume_tail "$EDGE" 26)" == $'## Turn 2\n라마바' ]] && ok "T1 머리 줄이 한 글자라도 잘리면 다음 머리 줄에서 시작한다" || fail "T1 잘린 머리 줄: [$(scv_resume_tail "$EDGE" 26)]"

# ---------- T2 짧은 기록은 그대로다 ----------
SHORT="$(record 6)"; N="$(nchars "$SHORT")"
(( N >= 2900 && N <= 3100 )) && ok "T2 준비: 기록 ${N}자" || fail "T2 준비: 기록이 ${N}자 (3,000자쯤이어야 한다)"
[[ "$(scv_resume_tail "$SHORT" "$MAX")" == "$SHORT" ]] && ok "T2 짧은 기록은 받은 글 그대로다" || fail "T2 짧은 기록이 바뀌었다"
# 한글 5,000자는 바이트로는 한도를 넘지만 글자로는 넘지 않는다 — 바이트로 세면 여기서 잘린다.
KO=""; for (( i = 0; i < 100; i++ )); do KO+="가나다라마바사아자차카타파하가나다라마바사아자차카타파하가나다라마바사아자차카타파하가나다라마바사아"$'\n'; done
KO="${KO%$'\n'}"; N="$(nchars "$KO")"
A="$(tail_in C "$KO" "$MAX")"; B="$(tail_in en_US.UTF-8 "$KO" "$MAX")"
[[ "$A" == "$KO" && "$B" == "$KO" ]] && ok "T2 한글 ${N}자($(printf '%s' "$KO" | wc -c | tr -d '[:space:]')바이트)는 글자로 세어 그대로다 (C · UTF-8)" || fail "T2 한글을 바이트로 셌다 (C $(nchars "$A")자 · UTF-8 $(nchars "$B")자)"
[[ "$(scv_resume_tail "가나다" 3)" == "가나다" && "$(scv_resume_tail "" 5)" == "" ]] && ok "T2 한도와 같은 길이 · 빈 글도 그대로다" || fail "T2 경계 길이"
[[ "$(scv_resume_tail "가나다라" 0)" == "가나다라" && "$(scv_resume_tail "가나다라" x)" == "가나다라" && "$(scv_resume_tail "가나다라")" == "가나다라" ]] \
  && ok "T2 한도가 0 · 숫자가 아님 · 없음이면 자르지 않는다" || fail "T2 잘못된 한도에서 글이 바뀌었다"

# ---------- T3 잘린 자리에 턴 머리가 없으면 끝에서 글자 수만큼 남긴다 ----------
FLAT=""; for (( i = 1; i <= 320; i++ )); do FLAT+="머리 없는 줄 $i — $FILL"$'\n'; done
FLAT="${FLAT%$'\n'}"; N="$(nchars "$FLAT")"
(( N >= 30000 )) && ok "T3 준비: 턴 머리가 없는 글 ${N}자" || fail "T3 준비: 글이 ${N}자뿐"
OUT="$(scv_resume_tail "$FLAT" "$MAX")"; n="$(nchars "$OUT")"
(( n > 0 && n <= MAX )) && ok "T3 빈 글이 아니고 한도 이하다 (${n}자)" || fail "T3 길이 ${n}자"
(( n == MAX )) && ends_with "$FLAT" "$OUT" && ok "T3 끝에서 정확히 ${MAX}자 — 원래 글의 끝과 같다" || fail "T3 끝 ${MAX}자가 아니다 (${n}자)"
A="$(tail_in C "$FLAT" "$MAX")"; B="$(tail_in en_US.UTF-8 "$FLAT" "$MAX")"
[[ -n "$A" && "$A" == "$OUT" && "$B" == "$OUT" ]] && ok "T3 언어 설정이 달라도 같은 글이 나온다 (C · UTF-8)" || fail "T3 언어 설정에 따라 결과가 다르다 (C $(nchars "$A")자 · UTF-8 $(nchars "$B")자)"
# 줄바꿈이 하나도 없는 한 줄 — 글자 중간(바이트)에서 자르지 않는다.
ONE=""; for (( i = 0; i < 360; i++ )); do ONE+="$FILL"; done
OUT="$(scv_resume_tail "$ONE" "$MAX")"; n="$(nchars "$OUT")"
(( n == MAX )) && ends_with "$ONE" "$OUT" && [[ "$(printf '%s' "$OUT" | wc -c | tr -d '[:space:]')" == "$(( MAX * 3 ))" ]] \
  && ok "T3 한 줄짜리 한글 $(nchars "$ONE")자도 끝 ${MAX}자 — 글자 경계에서 자른다" || fail "T3 한 줄짜리 글: ${n}자"
[[ "$(scv_resume_tail $'abc\ndef\nghi' 5)" == $'f\nghi' && "$(scv_resume_tail "가나다라마바사" 3)" == "마바사" ]] \
  && ok "T3 작은 글도 끝에서 센다 (줄바꿈도 한 글자)" || fail "T3 작은 글: [$(scv_resume_tail $'abc\ndef\nghi' 5)] [$(scv_resume_tail "가나다라마바사" 3)]"

# ---------- 훅 시험의 준비 ----------
mkproj() {  # <이름> — 하이드레이트된 임시 프로젝트
  local p="$WORK/$1"
  mkdir -p "$p"
  ( cd "$p" && git init -q . && git config user.name tester && git config user.email t@example.com \
    && bash "$CORE/scripts/hydrate.sh" init . >/dev/null 2>&1 )
  printf '%s' "$p"
}
conv() {  # <프로젝트> <파일명> <본문> — 진행 중(active) 대화 기록
  mkdir -p "$1/scv/conversations"
  printf -- '---\nslug: %s\nstatus: active\n---\n%s\n' "${2%.md}" "$3" > "$1/scv/conversations/$2"
}
run_hook() {  # <프로젝트> <stdin> [<코어 자리>] — stdout 은 OUT 에, 종료 코드는 RC 에
  OUT="$( cd "$1" && CLAUDE_PLUGIN_ROOT="${3:-$CORE}" bash "$HOOK" 2>"$WORK/err" <<<"$2" )"; RC=$?
  return 0
}
# 훅 출력에서 기록 부분 — 자리 줄 다음부터 끝까지.
record_part() { printf '%s\n' "$1" | LC_ALL=C awk -v p="$PLACE" 'f { print } index($0, p) == 1 { f = 1 }'; }
count() { printf '%s\n' "$1" | grep -cF -- "$2" || true; }

CONV="20261125-000001-long.md"
REC="$(record 62)"$'\n'"마지막 줄 token=abc123secret 끝"
P="$(mkproj hook)"; conv "$P" "$CONV" "$REC"
FULLN="$(nchars "$(cat "$P/scv/conversations/$CONV")")"

# ---------- T4 비운 뒤에는 훅이 끝부분과 전체 기록의 자리를 찍는다 ----------
run_hook "$P" '{"source":"clear"}'; O="$OUT"
[[ "$RC" == "0" ]] && ok "T4 종료 코드 0" || fail "T4 rc=$RC"
[[ "$(count "$O" "${PLACE}scv/conversations/$CONV")" == "1" ]] && ok "T4 전체 기록의 자리 줄이 한 번 있다" || fail "T4 자리 줄이 $(count "$O" "${PLACE}scv/conversations/$CONV")번"
PART="$(record_part "$O")"; n="$(nchars "$PART")"
(( n > 0 && n <= MAX )) && ok "T4 기록 부분은 ${n}자 — 전체 ${FULLN}자에서 한도 ${MAX}자 이하로" || fail "T4 기록 부분 ${n}자 (전체 ${FULLN}자)"
[[ "${PART%%$'\n'*}" == "## Turn "* ]] && ok "T4 기록 부분이 턴 머리 줄에서 시작한다" || fail "T4 기록 부분의 첫 줄: [$(printf '%s' "${PART%%$'\n'*}" | cut -c1-40)]"
[[ "$O" != *"FIRST-TURN-MARK"* && "$O" == *"LAST-TURN-MARK"* ]] && ok "T4 첫 턴의 글은 없고 마지막 턴의 글은 있다" || fail "T4 첫 턴 $(count "$O" FIRST-TURN-MARK)번 · 마지막 턴 $(count "$O" LAST-TURN-MARK)번"
[[ "$O" != *"abc123secret"* && "$O" == *"[REDACTED]"* ]] && ok "T4 끝부분도 가림 필터를 거친다" || fail "T4 비밀값이 그대로 나간다"
[[ "$O" == *"its last part follows"* && "$O" != *"its full text follows"* ]] && ok "T4 머리 줄이 전체가 아니라 끝부분이라고 적는다" || fail "T4 머리 줄이 전체라고 적는다"
# 짧은 기록은 비운 뒤에도 그대로 — 자르지 않았으니 자리 줄도 없다.
P2="$(mkproj short)"; conv "$P2" 20261125-000002-short.md "$(record 6)"
run_hook "$P2" '{"source":"clear"}'; O="$OUT"
[[ "$RC" == "0" && "$O" == *"FIRST-TURN-MARK"* && "$O" == *"LAST-TURN-MARK"* && "$(count "$O" "$PLACE")" == "0" && "$O" == *"its full text follows"* ]] \
  && ok "T4 짧은 기록은 비운 뒤에도 전체 — 자리 줄 없음" || fail "T4 짧은 기록: rc=$RC 자리 줄 $(count "$O" "$PLACE")번"
# 자르기가 실패하면 전과 같이 전체를 찍는다 — 훅은 세션을 막지 않는다.
BROKEN="$WORK/core-broken"; mkdir -p "$BROKEN/scripts/lib"
for f in "$CORE"/scripts/*; do [[ "${f##*/}" == lib ]] || ln -s "$f" "$BROKEN/scripts/${f##*/}"; done
for f in "$CORE"/scripts/lib/*; do [[ "${f##*/}" == resume-recap.sh ]] || ln -s "$f" "$BROKEN/scripts/lib/${f##*/}"; done
{ cat "$LIB"; printf '\nscv_resume_tail() { return 1; }\n'; } > "$BROKEN/scripts/lib/resume-recap.sh"
run_hook "$P" '{"source":"clear"}' "$BROKEN"; O="$OUT"
[[ "$RC" == "0" && "$O" == *"FIRST-TURN-MARK"* && "$O" == *"LAST-TURN-MARK"* && "$(count "$O" "$PLACE")" == "0" && "$O" != *"abc123secret"* ]] \
  && ok "T4 자르기가 실패하면 전체를 찍는다 (종료 코드 0 · 가림 그대로)" || fail "T4 자르기 실패 때: rc=$RC 첫 턴 $(count "$O" FIRST-TURN-MARK)번"

# ---------- T5 요약 · 재개 뒤에는 지금처럼 전체를 찍는다 ----------
for s in compact resume; do
  run_hook "$P" "{\"source\":\"$s\"}"; O="$OUT"
  [[ "$RC" == "0" && "$O" == *"FIRST-TURN-MARK"* && "$O" == *"LAST-TURN-MARK"* ]] && ok "T5 source=$s → 첫 턴과 마지막 턴이 모두 있다" || fail "T5 source=$s: rc=$RC 첫 턴 $(count "$O" FIRST-TURN-MARK)번 · 마지막 턴 $(count "$O" LAST-TURN-MARK)번"
  [[ "$(count "$O" "$PLACE")" == "0" && "$O" == *"its full text follows"* && "$O" != *"abc123secret"* ]] && ok "T5 source=$s → 자리 줄 없이 전체라고 적는다 (가림 그대로)" || fail "T5 source=$s 에 자리 줄이 있거나 머리 줄이 다르다"
done
run_hook "$P" '{}'; O="$OUT"
[[ "$RC" == "0" && "$O" == *"FIRST-TURN-MARK"* && "$O" == *"LAST-TURN-MARK"* && "$(count "$O" "$PLACE")" == "0" ]] && ok "T5 source 가 없어도 전체를 찍는다" || fail "T5 source 없음: rc=$RC"

echo
echo "test-resume-tail: PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
