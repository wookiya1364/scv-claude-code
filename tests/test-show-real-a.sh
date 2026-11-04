#!/usr/bin/env bash
# (a) — test-show-real.sh 를 나눈 조각 1/2 (CI 가장 느린 조각 줄이기). 묶어 돌리기: test-show-real.sh
# test-show-real.sh — 실체 보여 주기 안내 · 실사용 보고 검사 (v0.66.0+).
#
# 왜 있나: 결과물이 바뀌는 일이면 처음 돌아가는 순간 실제 결과를 보여 주고 짧게 묻게 하는 안내가 매 턴 블록에 실린다. 막는 검사
# 없이 안내만 하고, 설정으로 끄면 매 턴 출력이 이 기능 전과 바이트 단위로 같아야 하며, 확인 창 보기는 2개 이상이어야 한다.
# 실사용 보고는 세션 기록에서 기간마다 세 숫자를 세고, 숫자 · 날짜만 낸다. 규칙은 contracts/show-real.md 한 곳뿐이다.
#
# Covers TESTS.md T1~T8 · T11 of 20261007-wookiya1364-show-real-early
#   (T5 의 규칙 일치 검사 전체는 test-rule-constitution, T9 · T10 · T12 는 설치본 · 실사용, T13 은 기존 검사 전부).
# 픽스처는 중립 도구 이름(PickTool · Writer · Runner …)만 쓴다 — 코어에는 호스트 도구 이름을 적지 않는다.
# Run: bash core/tests/test-show-real.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE=""
for up in "$HERE/.." "$HERE/../.."; do
  for sub in core vendor/scv-core/core plugins/scv/vendor/scv-core/core; do
    if [[ -f "$up/$sub/scripts/lib/settings.sh" ]]; then CORE="$(cd "$up/$sub" && pwd)"; break 2; fi
  done
done
[[ -n "$CORE" ]] || { echo "test-show-real: payload not found from $HERE" >&2; exit 1; }
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
LIB="$CORE/scripts/lib/show-real.sh"; SR="$CORE/scripts/show-real.sh"; REPORT="$CORE/scripts/show-real-report.sh"
RULE="$CORE/contracts/show-real.md"; PROMPT_HOOK="$CORE/template/hooks/on-user-prompt.sh"; STOP_HOOK="$CORE/template/hooks/on-stop.sh"
EXAMPLE="$CORE/template/scv/scv_settings.example.json"; FIXP="$CORE/tests/fixtures/model-prompting/profile.env"
FIX="$CORE/tests/fixtures/show-real"
for f in "$LIB" "$SR" "$REPORT" "$RULE" "$PROMPT_HOOK" "$STOP_HOOK" "$EXAMPLE" "$FIXP" "$FIX/a.jsonl"; do
  [[ -f "$f" ]] || { echo "✖ 없음: $f"; exit 1; }
done
command -v jq >/dev/null 2>&1 || { echo "jq 없음 — 이 검사는 jq 가 필요하다" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-show-real.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
{ cat "$FIXP"; printf 'SCV_CHOICE_TOOL=PickTool\n'; } > "$WORK/pick.env"
cp "$FIXP" "$WORK/none.env"
{ cat "$WORK/pick.env"; printf 'SCV_CHOICE_OFF_WHEN=SCV_TEST_ATTENDED=0\n'; } > "$WORK/offwhen.env"
{ cat "$WORK/pick.env"; printf 'SCV_AUTO_PROMPT_TAGS=machine-event peer-note\nSCV_AUTO_PROMPT_PREFIX=Another session says:\n'; } > "$WORK/auto.env"
_norm() { sed -E 's/[0-9]{2}:[0-9]{2}(:[0-9]{2})?/HH:MM/g'; }   # 시각(초 포함)은 실행마다 달라 가린다
new_repo() {  # <이름> → 빈 scv 저장소 경로(있으면 지우고 새로)
  local d="$WORK/$1"; rm -rf "$d"; mkdir -p "$d/scv/journal"; printf '%s' "$d"
}
hook_with() {  # <훅> <저장소> <프로필> <프롬프트> [코어] → 매 턴 훅 출력(시각은 HH:MM)
  local core="${5:-$CORE}"
  (cd "$2" && jq -cn --arg p "$4" '{prompt:$p,session_id:"s1"}' \
     | CLAUDE_PLUGIN_ROOT="$core" SCV_HOST_PROFILE="$3" bash "$1" 2>/dev/null) | _norm
}
sr_block() { awk '/^\[SCV 실체 보여 주기\]/{n=3} n>0{print; n--}'; }   # 출력에서 안내 세 줄만

echo "── [T1] 켬 — 매 턴 블록에 실체 보여 주기 안내가 실린다 ──"
R="$(new_repo t1)"; O1="$(hook_with "$PROMPT_HOOK" "$R" "$WORK/pick.env" "로그인 버튼 만들어 줘")"
B1="$(printf '%s\n' "$O1" | sr_block)"
grep -qF '[SCV 실체 보여 주기]' <<<"$B1" && grep -qF '처음 돌아가는 순간' <<<"$B1" && grep -qF '실제로 실행해' <<<"$B1" \
  && grep -qF "'이대로 계속할까요, 고칠 점이 있나요?'" <<<"$B1" && grep -qF '설명은 한두 줄로' <<<"$B1" \
  && ok "안내 문구가 실린다(처음 돌아가는 순간 · 실제 실행 · 확인 질문 · 설명 한두 줄)" || fail "T1 문구: [$B1]"
grep -qF 'contracts/show-real.md' <<<"$B1" && ok "본문 계약 경로를 가리킨다" || fail "T1 계약 경로"
[[ "$(printf '%s\n' "$B1" | grep -c .)" == 3 ]] && ok "안내는 세 줄" || fail "T1 줄 수: $(printf '%s\n' "$B1" | grep -c .)"
_lc="$(printf '%s\n' "$O1" | grep -n '^\[SCV choices\]' | head -1 | cut -d: -f1)"; _ls="$(printf '%s\n' "$O1" | grep -n '^\[SCV 실체 보여 주기\]' | head -1 | cut -d: -f1)"
[[ -n "$_lc" && -n "$_ls" && "$_ls" == "$((_lc + 1))" ]] && ok "고르게 할 때 줄 바로 뒤에 실린다" || fail "T1 자리: choices=$_lc show-real=$_ls"
_bc="$(printf '%s' "$B1" | wc -c | tr -d ' ')"
# 상한 640 → 760B: 검토 시점 문구(계획 20261009-wookiya1364-show-real-at-checkpoint)를 더해 선택 창 블록이 742B — 매 턴 전체 상한
# (12,000B, test-help-budget)은 그대로 지킨다.
(( _bc <= 760 )) && ok "안내 ${_bc}B ≤ 760B (매 턴 스택 상한 — test-help-budget T12 와 함께)" || fail "T1 크기 ${_bc}B"
# 검토 시점 문구 — 사용자가 정한 검토 시점은 앞당기지 않고, 그때 요약 대신 실제 실행 결과를 보이며 묻는다(묻는 통로에만).
grep -qF '검토 시점을 정해 두었으면' <<<"$B1" && grep -qF '앞당기지 말고' <<<"$B1" && grep -qF '요약 대신 실제로 돌린 결과' <<<"$B1" \
  && ok "검토 시점 문구가 실린다(앞당기지 않음 · 요약 대신 실제 실행 결과)" || fail "T1 검토 시점 문구: [$B1]"

echo "── [T2] 끔 — 설정 off 면 이 기능이 없는 훅과 바이트 단위로 같다 ──"
# 기능 전 훅을 이 파일에서 만든다: 표식 사이(show-real 구간)를 지운다. 새 코드끼리만 견주면 끈 출력이 바뀌어도 못 잡는다.
BASE_HOOK="$WORK/hook-base/on-user-prompt.sh"; mkdir -p "$WORK/hook-base"
sed -e '/^# ---------- show-real/,/^# ---------- \/show-real/d' "$PROMPT_HOOK" > "$BASE_HOOK"
grep -q 'show-real' "$BASE_HOOK" && fail "기능 전 훅을 만들지 못했다(표식이 없다)" || ok "기능 전 훅을 만들었다(표식 구간을 지움)"
same_as_base() {  # <설정 JSON 또는 빈 값> <프로필> → 새 훅(그 설정)과 기능 전 훅의 출력이 같으면 0
  local a b R
  R="$(new_repo t2)"; [[ -n "$1" ]] && printf '%s\n' "$1" > "$R/scv/scv_settings.json"
  a="$(hook_with "$PROMPT_HOOK" "$R" "$2" "로그인 버튼 만들어 줘")"
  R="$(new_repo t2)"; [[ -n "$1" ]] && printf '%s\n' "$1" > "$R/scv/scv_settings.json"
  b="$(hook_with "$BASE_HOOK" "$R" "$2" "로그인 버튼 만들어 줘")"
  [[ -n "$a" && "$a" == "$b" ]] || { diff <(printf '%s\n' "$b") <(printf '%s\n' "$a") | head -5 | sed 's/^/        /'; return 1; }
}
for v in off OFF " Off " '\"off\"'; do
  same_as_base "{\"SCV_SHOW_REAL\": \"$v\"}" "$WORK/pick.env" && ok "SCV_SHOW_REAL='$v' — 선택 창 호스트에서 기능 전 훅과 같다" || fail "T2 '$v' (pick)"
done
same_as_base '{"SCV_SHOW_REAL": "off"}' "$WORK/none.env" && ok "선택 창 없는 호스트에서도 같다" || fail "T2 off (none)"
same_as_base '' "$WORK/pick.env" >/dev/null && fail "T2 켬(설정 없음)인데 기능 전 훅과 같다 — 비교가 아무것도 못 잡는다" || ok "켬(설정 없음)은 기능 전 훅과 다르다 — 비교가 실제로 가른다"
R="$(new_repo t2e)"; o="$(cd "$R" && jq -cn '{prompt:"x",session_id:"s1"}' | SCV_SHOW_REAL=off CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="$WORK/pick.env" bash "$PROMPT_HOOK" 2>/dev/null)"
! grep -qF 'SCV 실체' <<<"$o" && ok "환경 변수 SCV_SHOW_REAL=off 도 끈다(설정 읽기 순서 그대로)" || fail "T2 환경 변수"
# 훅은 입력을 이 기능에 넘긴다 — 꺼서 읽지 않고 끝나도(큰 입력이면 쓰기가 끊긴다) 오류 출력이 호스트로 새지 않아야 한다.
BIGP="$(printf '긴 입력 %.0s' $(seq 1 8000))"   # 약 88KB — 파이프 버퍼(64KB)를 넘긴다
for v in off on; do
  R="$(new_repo t2s)"; printf '{"SCV_SHOW_REAL": "%s"}\n' "$v" > "$R/scv/scv_settings.json"
  (cd "$R" && jq -cn --arg p "$BIGP" '{prompt:$p,session_id:"s1"}' | CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="$WORK/pick.env" bash "$PROMPT_HOOK" >/dev/null 2>"$WORK/t2s.err")
  [[ ! -s "$WORK/t2s.err" ]] && ok "큰 입력(${#BIGP}자) · $v — 훅의 오류 출력 없음" || fail "T2 오류 출력($v): $(head -c 200 "$WORK/t2s.err")"
done

echo "── [T3] 선택 창이 없는 호스트 — 글 질문 한 번 · 사람이 없으면 묻지 않음 ──"
R="$(new_repo t3)"; B3="$(hook_with "$PROMPT_HOOK" "$R" "$WORK/none.env" "로그인 버튼 만들어 줘" | sr_block)"
grep -qF '글 질문 한 번으로' <<<"$B3" && ! grep -qF '선택 창' <<<"$B3" && ok "선택 창 문구 없음 · 글 질문 문구 있음" || fail "T3: [$B3]"
grep -qF '검토 시점을 정해 두었으면' <<<"$B3" && ok "글 질문 통로에도 검토 시점 문구" || fail "T3 검토 시점(글): [$B3]"
R="$(new_repo t3c)"; printf '{"SCV_CHOICE_GATE": "off"}\n' > "$R/scv/scv_settings.json"
B3c="$(hook_with "$PROMPT_HOOK" "$R" "$WORK/pick.env" "x" | sr_block)"
grep -qF '글 질문 한 번으로' <<<"$B3c" && ok "고르게 할 때 규칙을 끈 프로젝트도 글 질문" || fail "T3 규칙 off: [$B3c]"
# 계약의 예외 — 사람 없는 실행 · 자동 알림 턴에는 묻지 않는 문구(묻게 하면 무인 실행이 첫 결과에서 멈춘다 — 독립 검토 2026-10-07).
no_ask() { grep -qF '묻지 않는다' <<<"$1" && ! grep -qF '이대로 계속할까요' <<<"$1" && ! grep -qF '선택 창으로' <<<"$1" && ! grep -qF '글 질문' <<<"$1" && ! grep -qF '검토 시점' <<<"$1"; }
R="$(new_repo t3b)"; B3b="$(cd "$R" && jq -cn '{prompt:"x",session_id:"s1"}' | SCV_TEST_ATTENDED=0 CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="$WORK/offwhen.env" bash "$PROMPT_HOOK" 2>/dev/null | sr_block)"
no_ask "$B3b" && [[ "$(printf '%s\n' "$B3b" | grep -c .)" == 3 ]] && ok "사람 없는 실행 조건이면 묻지 않는 문구(세 줄)" || fail "T3 사람 없는 실행: [$B3b]"
R="$(new_repo t3d)"; B3d="$(cd "$R" && jq -cn '{prompt:"x",session_id:"s1"}' | SCV_TEST_ATTENDED=1 CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="$WORK/offwhen.env" bash "$PROMPT_HOOK" 2>/dev/null | sr_block)"
grep -qF '선택 창으로' <<<"$B3d" && ok "같은 설정이라도 사람이 있는 실행이면 선택 창" || fail "T3 사람 있는 실행: [$B3d]"
R="$(new_repo t3e)"; B3e="$(hook_with "$PROMPT_HOOK" "$R" "$WORK/auto.env" "<machine-event>build done</machine-event>" | sr_block)"
no_ask "$B3e" && ok "자동 알림 턴이면 묻지 않는 문구" || fail "T3 자동 알림 턴: [$B3e]"
R="$(new_repo t3f)"; B3f="$(hook_with "$PROMPT_HOOK" "$R" "$WORK/auto.env" "로그인 버튼 만들어 줘" | sr_block)"
grep -qF '선택 창으로' <<<"$B3f" && ok "자동 입력 모양이 있는 호스트에서도 사람 메시지는 선택 창" || fail "T3 사람 메시지: [$B3f]"

echo "── [T4] 순수 함수 단위 — 지금 bash 와 시스템 bash 에서 같은 표 ──"
TABLE_SCRIPT='
source "$1"
for v in "" on off OFF " Off " "\"off\"" maybe "on!"; do printf "switch[%s]=%s\n" "$v" "$(scv_show_real_switch "$v")"; done
for v in ",0,human" " ,0,human" "PickTool,0,human" "PickTool,1,human" "PickTool,0,auto" ",1,human" ",0,auto"; do IFS=, read -r a b c <<<"$v"; printf "channel[%s]=%s\n" "$v" "$(scv_show_real_channel "$a" "$b" "$c")"; done
for s in on off; do for c in choice text none; do r="$(scv_show_real_rule "$s" "$c")"; printf "rule[%s,%s]=%s lines, choice=%s, text=%s, none=%s\n" "$s" "$c" "$(printf "%s" "$r" | grep -c .)" "$(grep -c "선택 창으로" <<<"$r")" "$(grep -c "글 질문 한 번으로" <<<"$r")" "$(grep -c "묻지 않는다" <<<"$r")"; done; done
for v in 2026,02,28 2026,02,29 2024,02,29 1900,02,29 2000,02,29 2026,04,31 2026,13,01 2026,00,10; do IFS=, read -r a b c <<<"$v"; printf "day[%s]=%s\n" "$v" "$(scv_show_real_valid_day "$a" "$b" "$c")"; done
printf "lines=[%s]\n" "$(scv_show_real_lines "$(printf "a\036\036b")")"
for z in +0900 -0530 +0000 x; do printf "offset[%s]=%s\n" "$z" "$(scv_show_real_offset "$z")"; done
for c in "2026-10-07T02:55:00.123Z 540" "2026-12-31T20:00:00Z 540" "2026-03-01T03:00:00Z -300" "2024-03-01T01:00:00Z -120" "2026-10-07T23:30:00Z 540" "2026-10-07T23:30:00Z 0" "2026-10-07T23:30:00+09:00 540" "2026-10-07T23:30:00.5-05:00 540" "2026-10-07T23:30 0" "bad 540"; do set -- $c; printf "date[%s %s]=%s\n" "$1" "$2" "$(scv_show_real_local_date "$1" "$2")"; done
for r in 2026-10-01..2026-10-06 2026-10-06..2026-10-01 2026-13-01..2026-13-02 2026-02-30..2026-03-01 2024-02-29..2024-03-01 2026-10-01; do printf "range[%s]=%s\n" "$r" "$(scv_show_real_range "$r")"; done
for m in "아니 색이 틀렸어" "이거 말고 다른 걸로" "고마워" "A로 할까 아니면 B로 할까" "This is wrong" "prefix only" "違う、直して" "좋아요 다음"; do printf "corr[%s]=%s\n" "$m" "$(scv_show_real_is_correction "$m")"; done
for m in "정리했습니다. 결과물 변화 없음." "No change to the result." "결과물이 바뀌었습니다"; do printf "nochange[%s]=%s\n" "$m" "$(scv_show_real_is_nochange "$m")"; done
for m in "이대로 계속할까요, 고칠 점이 있나요?" "Continue as is, or anything to fix?" "このまま続けますか、直す点はありますか?" "계속 진행할까요?" "어느 판으로 되돌릴까요?" "수정안으로 진행할까요?"; do printf "confirm[%s]=%s\n" "$m" "$(scv_show_real_is_confirm "$m")"; done
'
EXPECT_TABLE='switch[]=on
switch[on]=on
switch[off]=off
switch[OFF]=off
switch[ Off ]=off
switch["off"]=off
switch[maybe]=on
switch[on!]=on
channel[,0,human]=text
channel[ ,0,human]=text
channel[PickTool,0,human]=choice
channel[PickTool,1,human]=none
channel[PickTool,0,auto]=none
channel[,1,human]=none
channel[,0,auto]=none
rule[on,choice]=3 lines, choice=1, text=0, none=0
rule[on,text]=3 lines, choice=0, text=1, none=0
rule[on,none]=3 lines, choice=0, text=0, none=1
rule[off,choice]=0 lines, choice=0, text=0, none=0
rule[off,text]=0 lines, choice=0, text=0, none=0
rule[off,none]=0 lines, choice=0, text=0, none=0
day[2026,02,28]=1
day[2026,02,29]=0
day[2024,02,29]=1
day[1900,02,29]=0
day[2000,02,29]=1
day[2026,04,31]=0
day[2026,13,01]=0
day[2026,00,10]=0
lines=[a

b]
offset[+0900]=540
offset[-0530]=-330
offset[+0000]=0
offset[x]=0
date[2026-10-07T02:55:00.123Z 540]=20261007
date[2026-12-31T20:00:00Z 540]=20270101
date[2026-03-01T03:00:00Z -300]=20260228
date[2024-03-01T01:00:00Z -120]=20240229
date[2026-10-07T23:30:00Z 540]=20261008
date[2026-10-07T23:30:00Z 0]=20261007
date[2026-10-07T23:30:00+09:00 540]=20261007
date[2026-10-07T23:30:00.5-05:00 540]=20261008
date[2026-10-07T23:30 0]=20261007
date[bad 540]=
range[2026-10-01..2026-10-06]=20261001 20261006
range[2026-10-06..2026-10-01]=
range[2026-13-01..2026-13-02]=
range[2026-02-30..2026-03-01]=
range[2024-02-29..2024-03-01]=20240229 20240301
range[2026-10-01]=
corr[아니 색이 틀렸어]=1
corr[이거 말고 다른 걸로]=1
corr[고마워]=0
corr[A로 할까 아니면 B로 할까]=0
corr[This is wrong]=1
corr[prefix only]=0
corr[違う、直して]=1
corr[좋아요 다음]=0
nochange[정리했습니다. 결과물 변화 없음.]=1
nochange[No change to the result.]=1
nochange[결과물이 바뀌었습니다]=0
confirm[이대로 계속할까요, 고칠 점이 있나요?]=1
confirm[Continue as is, or anything to fix?]=1
confirm[このまま続けますか、直す点はありますか?]=1
confirm[계속 진행할까요?]=0
confirm[어느 판으로 되돌릴까요?]=0
confirm[수정안으로 진행할까요?]=0'
T_NOW="$(bash -c "$TABLE_SCRIPT" _ "$LIB" 2>&1)"
[[ "$T_NOW" == "$EXPECT_TABLE" ]] && ok "표의 모든 칸 일치 (지금 bash $(bash -c 'echo ${BASH_VERSINFO[0]}'))" \
  || { fail "T4 표"; diff <(printf '%s\n' "$EXPECT_TABLE") <(printf '%s\n' "$T_NOW") | head -10 | sed 's/^/        /'; }
if [[ -x /bin/bash ]]; then
  T_SYS="$(/bin/bash -c "$TABLE_SCRIPT" _ "$LIB" 2>&1)"
  [[ "$T_SYS" == "$T_NOW" ]] && ok "시스템 bash $(/bin/bash -c 'echo ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}') 와 바이트로 같다" \
    || { fail "T4 시스템 bash 차이"; diff <(printf '%s\n' "$T_NOW") <(printf '%s\n' "$T_SYS") | head -6 | sed 's/^/        /'; }
fi
P="$(bash "$CORE/scripts/check-purity.sh" "$LIB" 2>&1)"
grep -q '^OK  purity' <<<"$P" && ok "순수성 검사 통과 (@pure · @deterministic 표식 $(bash "$CORE/scripts/check-purity.sh" --list "$LIB" 2>/dev/null | grep -c .)개)" \
  || fail "T4 순수성: $(printf '%s' "$P" | head -3)"

echo "── [T5] 규칙 본문은 한 곳에만 ──"
for phrase in '처음 돌아가는 순간' '보여 주지도 묻지도' '보기는 2개 이상'; do
  hits="$(grep -rlF -- "$phrase" "$CORE/protocols" "$CORE/contracts" "$CORE/template" 2>/dev/null | sed "s#^$CORE/##" | LC_ALL=C sort | tr '\n' ' ')"
  [[ "$hits" == "contracts/show-real.md " ]] && ok "'$phrase' — 문서 중 계약에만 있다" || fail "T5 '$phrase' 위치: [$hits]"
done
grep -qF 'contracts/show-real.md' "$PROMPT_HOOK" && grep -qF 'core/contracts/show-real.md' "$EXAMPLE" \
  && ok "매 턴 훅 · 설정 설명은 계약을 가리키기만 한다" || fail "T5 가리킴"

echo "─────────────────────────────"
echo "  통과 $PASS · 실패 $FAIL"
[[ $FAIL -eq 0 ]] && { echo "  ALL SHOW-REAL CHECKS OK"; exit 0; } || exit 1
