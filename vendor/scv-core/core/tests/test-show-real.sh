#!/usr/bin/env bash
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

echo "── [T6] 막는 검사 없음 — 종료 훅 출력이 바뀌지 않는다 ──"
! grep -qE 'show-real|SCV_SHOW_REAL' "$STOP_HOOK" "$CORE/template/hooks/guard.sh" \
  && ok "종료 훅 · 쓰기 검사는 이 기능을 부르지도 읽지도 않는다" || fail "T6 종료 훅 · 쓰기 검사가 이 기능을 안다"
# 이 기능이 없는 코어를 만든다: 기능 파일을 지우고 매 턴 훅의 표식 구간을 지운다(화면 묶음 DeckUI 는 훅과 무관해 복사하지 않는다).
# 같은 턴을 두 코어로 돌려 종료 훅의 출력과 남긴 저널을 견준다 — 출력이 비는 경우만 보면 늘 같아 아무것도 못 잡는다(독립 검토).
BASE_CORE="$WORK/core-base"; mkdir -p "$BASE_CORE"
for _e in "$CORE"/*; do [[ "${_e##*/}" == DeckUI ]] || cp -R "$_e" "$BASE_CORE/"; done
rm -f "$BASE_CORE/scripts/show-real.sh" "$BASE_CORE/scripts/show-real-report.sh" "$BASE_CORE/scripts/lib/show-real.sh" "$BASE_CORE/contracts/show-real.md"
cp "$BASE_HOOK" "$BASE_CORE/template/hooks/on-user-prompt.sh"
stop_run() {  # <코어> <마지막 답> → "출력<RS>저널"(설정 on, 사람 메시지로 연 턴: 코드 편집 → 실제 결과 표시 없음)
  local R tr; R="$(new_repo t6)"; printf '{"SCV_SHOW_REAL": "on"}\n' > "$R/scv/scv_settings.json"; tr="$WORK/tr6.jsonl"
  { jq -cn '{type:"user",message:{content:"로그인 버튼 만들어 줘"}}'
    jq -cn '{type:"assistant",message:{content:[{type:"tool_use",name:"Writer",input:{file_path:"src/btn.js",content:"x"}}]}}'
    jq -cn --arg t "$2" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}'; } > "$tr"
  hook_with "$1/template/hooks/on-user-prompt.sh" "$R" "$WORK/pick.env" "로그인 버튼 만들어 줘" "$1" >/dev/null
  (cd "$R" && jq -cn --arg p "$tr" --arg a "$2" '{session_id:"s1",transcript_path:$p,last_assistant_message:$a,stop_hook_active:false}' \
     | CLAUDE_PLUGIN_ROOT="$1" SCV_HOST_PROFILE="$WORK/pick.env" GIT_AUTHOR_NAME="Hook User" bash "$1/template/hooks/on-stop.sh" 2>/dev/null) | _norm
  printf '\036'; cat "$R"/scv/journal/*.md 2>/dev/null | _norm
}
A_DONE="구현했습니다. 버튼 파일을 만들었습니다."; A_ASK="구현했습니다. 이대로 둘까요?"; RS6=$'\036'
S_NEW="$(stop_run "$CORE" "$A_DONE")"; S_BASE="$(stop_run "$BASE_CORE" "$A_DONE")"
[[ "$S_NEW" == "$S_BASE" ]] && grep -qF "$A_DONE" <<<"${S_NEW#*"$RS6"}" \
  && ok "확인 질문 없이 끝난 턴: 종료 훅 출력 · 남긴 저널이 이 기능 없는 코어와 같다(저널에 답이 남아 훅이 끝까지 돌았다)" \
  || { fail "T6 끝난 턴 차이"; diff <(printf '%s\n' "$S_BASE") <(printf '%s\n' "$S_NEW") | head -6 | sed 's/^/        /'; }
! grep -q '"decision"[[:space:]]*:[[:space:]]*"block"' <<<"${S_NEW%%"$RS6"*}" && ok "막음 0번(편집 · 실제 결과 표시 없음 · 확인 질문 없음인 턴)" || fail "T6 막았다: [${S_NEW%%"$RS6"*}]"
Q_NEW="$(stop_run "$CORE" "$A_ASK")"; Q_BASE="$(stop_run "$BASE_CORE" "$A_ASK")"
[[ "$Q_NEW" == "$Q_BASE" ]] && grep -q '"decision"[[:space:]]*:[[:space:]]*"block"' <<<"${Q_NEW%%"$RS6"*}" && ! grep -qF '실체' <<<"$Q_NEW" \
  && ok "글로 묻고 끝난 턴: 고르게 할 때 규칙의 막음은 그대로 같고, 실체 보여 주기 사유는 더해지지 않는다" \
  || { fail "T6 묻고 끝난 턴"; diff <(printf '%s\n' "$Q_BASE") <(printf '%s\n' "$Q_NEW") | head -6 | sed 's/^/        /'; }

echo "── [T7] 보기 2개 이상 ──"
grep -qF '보기는 2개 이상' <<<"$B1" && grep -qF '보기는 2개 이상' "$RULE" && ok "안내와 계약이 보기 2개 이상을 말한다" || fail "T7 2개 이상 지시"
single="$(cat "$LIB" "$RULE" "$EXAMPLE" | grep -E '보기는[^.。]*하나로|보기 하나로|보기를 하나만 두|single option|only one option' || true)"
[[ -z "$single" ]] && ok "보기 하나짜리 창을 만들게 하는 문구 0개" || fail "T7 하나짜리 지시: [$single]"

echo "── [T8] 결과물이 안 바뀌는 일에는 질문을 더하지 않음 ──"
grep -qF '보여 주지도 묻지도' <<<"$B1" && grep -qF "'결과물 변화 없음'" <<<"$B1" && ok "안내: 보여 주지도 묻지도 말고 '결과물 변화 없음'" || fail "T8 안내"
grep -qF '보여 주지도 묻지도 않고' "$RULE" && grep -qF '"결과물 변화 없음"' "$RULE" && ok "계약: 같은 지시" || fail "T8 계약"

echo "── [T11] 실사용 보고 집계 — 고정 기록 단위 검사 ──"
PIPE_SCRIPT='
source "$1/scripts/lib/show-real.sh"; source "$1/scripts/lib/model-prompting.sh"; source "$1/scripts/lib/choices.sh"
rows=""
for f in a b c d e f g h i j; do
  e="$(scv_show_real_entries PickTool < "$2/$f.jsonl")"
  t="$(scv_show_real_split "$f" "$e" "machine-event peer-note" "Another session says:" "")"
  r="$(scv_show_real_classify "$t")"; printf "%s\n" "$r"; rows+="$r"$'"'"'\n'"'"'
done
printf -- "--\n"; scv_show_real_count "$rows" 540 "20261001 20261006" "20261008 20261012"
printf -- "--\n"; scv_show_real_count "$rows" 0 "20261001 20261006" "20261008 20261012"
'
# 손으로 센 값 — 턴마다 바뀜 · 보여 줌 · 완료 · 수정 요구 · 확인 질문. 픽스처(core/tests/fixtures/show-real):
#   a 보여 주고 확인 창 → 완료 → 수정 요구 → 자동 알림 → 고마워 · 메타 · 하위 에이전트 · 압축 요약 · 깨진 끝 줄
#   b 글 질문으로 확인 → 답 → 완료 → 명령 줄(빈 턴) → 수정 요구 · 다른 결정 창(보기 설명에만 '계속')
#   c 다른 세션 메시지(자동) → 영어 확인 창 · 다른 결정 창 → 완료    d 날짜 경계(UTC 10-07 23:30)    e 두 기간 밖
#   f 완료 → 모델이 답하지 않은 명령 출력 줄(Error) → 고쳐 줘(한 번만)   g 편집 · 실행 중 끊긴 턴(+09:00 시각) → 아니 그거 말고(아님)
#   h 질문 둘인 창의 둘째가 확인 → 완료 → 창에서 끝난 턴(닫음) → 색이 틀렸어(아님)
#   i 구조 정리(결과물 변화 없음 — 바뀐 턴 아님) → 읽기만 하고 끊긴 턴(첫 답) → 중단 표시 → 아니 그게 아니라(아님)
#   j 일하는 중 입력한 메시지(첨부)가 새 턴 · 자동 알림 첨부는 아님 → 코드 블록 중간에서 잘리는 6천 자 답 끝의 확인 질문
#   (모델이 아무것도 하지 않은 턴 — 명령 출력 줄 · 중단 표시 — 은 줄을 내지 않는다)
EXPECT_PIPE="a	2026-10-02T01:00:00Z	1	1	1	0	1
a	2026-10-02T02:00:00Z	1	0	1	1	0
a	2026-10-02T03:00:00Z	0	0	0	0	0
b	2026-10-03T05:00:00Z	1	1	0	0	1
b	2026-10-03T05:10:00Z	1	0	1	0	0
b	2026-10-03T05:21:00Z	1	0	1	1	1
c	2026-10-09T01:00:00Z	1	1	1	0	2
c	2026-10-09T01:30:00Z	0	0	0	0	0
d	2026-10-07T23:30:00Z	1	0	0	0	1
e	2026-09-20T01:00:00Z	1	0	1	0	0
f	2026-10-10T01:00:00Z	1	0	1	0	0
f	2026-10-10T01:06:00Z	1	0	1	1	0
g	2026-10-10T10:00:00+09:00	1	0	0	0	0
g	2026-10-10T10:01:00+09:00	1	0	1	0	0
h	2026-10-11T01:00:00Z	1	1	1	0	1
h	2026-10-11T01:10:00Z	1	0	0	0	1
h	2026-10-11T01:11:00Z	1	0	1	0	0
i	2026-10-12T01:00:00Z	0	0	1	0	0
i	2026-10-12T01:10:00Z	0	0	0	0	0
i	2026-10-12T01:11:00Z	1	0	1	0	0
j	2026-10-12T02:00:00Z	1	0	0	0	0
j	2026-10-12T02:00:25Z	1	0	1	0	0
j	2026-10-12T02:10:00Z	1	1	0	0	1
--
before	2	6	5	2	2	3
after	7	16	13	3	1	6
--
before	2	6	5	2	2	3
after	6	15	12	3	1	5"
P_NOW="$(bash -c "$PIPE_SCRIPT" _ "$CORE" "$FIX" 2>&1)"
[[ "$P_NOW" == "$EXPECT_PIPE" ]] && ok "턴마다 다섯 표시 · 기간별 셈이 손으로 센 값과 같다(지역 오프셋 +540 · 0, 픽스처 10개)" \
  || { fail "T11 집계"; diff <(printf '%s\n' "$EXPECT_PIPE") <(printf '%s\n' "$P_NOW") | head -10 | sed 's/^/        /'; }
if [[ -x /bin/bash ]]; then
  P_SYS="$(/bin/bash -c "$PIPE_SCRIPT" _ "$CORE" "$FIX" 2>&1)"
  [[ "$P_SYS" == "$P_NOW" ]] && ok "시스템 bash 와 바이트로 같다" || { fail "T11 시스템 bash 차이"; diff <(printf '%s\n' "$P_NOW") <(printf '%s\n' "$P_SYS") | head -6 | sed 's/^/        /'; }
fi
# 로캘 — 글 자르기를 jq(글자 단위)에서 끝내므로 C 로캘(바이트 단위)에서도 같은 셈이어야 한다(독립 검토 2026-10-07: 갈렸다).
P_C="$(LC_ALL=C bash -c "$PIPE_SCRIPT" _ "$CORE" "$FIX" 2>&1)"
[[ "$P_C" == "$P_NOW" ]] && ok "C 로캘에서도 바이트로 같다" || { fail "T11 로캘 차이"; diff <(printf '%s\n' "$P_NOW") <(printf '%s\n' "$P_C") | head -6 | sed 's/^/        /'; }
# 효과부까지: 픽스처를 새로 만든 파일로 복사해 스크립트를 돌린다(지역 오프셋은 TZ 로 고정 — 시간대 자료 없이 되는 POSIX 꼴).
mkdir -p "$WORK/records"; cp "$FIX"/*.jsonl "$WORK/records/"; touch "$WORK/records"/*.jsonl
{ cat "$FIXP"; printf 'SCV_CHOICE_TOOL=PickTool\nSCV_AUTO_PROMPT_TAGS=machine-event peer-note\nSCV_AUTO_PROMPT_PREFIX=Another session says:\n'; } > "$WORK/rep.env"
report() {  # <SCV_LANG> <켜기 전> <켠 뒤> [인자…] → RP(출력) · rc(종료 코드)
  local lang="$1" b="$2" a="$3"; shift 3
  RP="$(cd "$WORK" && TZ=KST-9 SCV_HOST_PROFILE="${REP_PROFILE:-$WORK/rep.env}" SCV_LANG="$lang" bash "$REPORT" --before "$b" --after "$a" "$@" 2>&1)"; rc=$?
}
ROW_B='| 켜기 전 2026-10-01..2026-10-06 | 2 | 5 | 40% (2) | 1.00 (2) | 1.50 (3) |'
ROW_A='| 켠 뒤 2026-10-08..2026-10-12 | 7 | 13 | 23% (3) | 0.14 (1) | 0.85 (6) |'
report korean 2026-10-01..2026-10-06 2026-10-08..2026-10-12 --dir "$WORK/records"
grep -qF "$ROW_B" <<<"$RP" && grep -qF "$ROW_A" <<<"$RP" && grep -qF '읽은 세션 기록 파일: 10개' <<<"$RP" && ! grep -qF '읽지 못한' <<<"$RP" \
  && ok "보고 스크립트: 표 한 장이 손으로 센 값으로 나온다" || fail "T11 보고: [$RP]"
leak="$(grep -E '로그인|README|버튼|\.jsonl|records|PickTool|machine-event|scv-show-real' <<<"$RP" || true)"
[[ -z "$leak" ]] && ok "보고에 대화 내용 · 경로 · 도구 이름이 없다(숫자 · 날짜만)" || fail "T11 새는 것: [$leak]"
report english 2026-10-01..2026-10-06 2026-10-08..2026-10-12 --dir "$WORK/records"
grep -qF '| Before 2026-10-01..2026-10-06 | 2 | 5 | 40% (2) | 1.00 (2) | 1.50 (3) |' <<<"$RP" && ok "언어 설정(english)을 따른다" || fail "T11 영어: [$RP]"
report korean 2026-10-01..2026-10-06 2026-10-08..2026-10-12 --dir "$WORK/records" --dir "$WORK/records/" --dir "$WORK/./records"
grep -qF "$ROW_B" <<<"$RP" && grep -qF '읽은 세션 기록 파일: 10개' <<<"$RP" && ok "같은 폴더를 여러 번 줘도 한 번만 센다" || fail "T11 폴더 중복: [$RP]"
mkdir -p "$WORK/records2"; cp "$FIX/a.jsonl" "$WORK/records2/"; printf '{"type":"session_meta","payload":{"id":"x"}}\n' > "$WORK/records2/z.jsonl"
report korean 2026-10-01..2026-10-06 2026-10-08..2026-10-12 --dir "$WORK/records" --dir "$WORK/records2"
grep -qF '| 켜기 전 2026-10-01..2026-10-06 | 3 | 7 | 42% (3) | 1.00 (3) | 1.33 (4) |' <<<"$RP" \
  && ok "다른 폴더의 같은 이름 파일은 다른 세션이다" || fail "T11 같은 이름 파일: [$RP]"
grep -qF '대화 항목이 없거나 읽지 못한 파일(권한 · 기록 모양): 1개' <<<"$RP" && ok "모양을 읽지 못한 파일은 수를 알린다(0 으로 조용히 넘어가지 않는다)" || fail "T11 못 읽은 파일: [$RP]"
bad_ok=1
for bad in "2026-10-06..2026-10-01 2026-10-08..2026-10-12" "2026-10-01..2026-10-09 2026-10-08..2026-10-12" "2026-10-08..2026-10-12 2026-10-01..2026-10-06" "2026-02-30..2026-03-01 2026-10-08..2026-10-12"; do
  set -- $bad; report korean "$1" "$2" --dir "$WORK/records"
  [[ "$rc" == 2 ]] || { bad_ok=0; fail "T11 기간 오류 코드 [$bad]: $rc"; }
done
(( bad_ok )) && ok "거꾸로 · 겹치는 · 순서가 바뀐 기간 · 없는 날은 사용법 오류(종료 코드 2)"
REP_PROFILE="$WORK/no-such-profile.env" report korean 2026-10-01..2026-10-06 2026-10-08..2026-10-12 --dir "$WORK/records"
[[ "$rc" == 1 ]] && grep -qF 'host profile not found' <<<"$RP" && ! grep -qF "$WORK" <<<"$RP" \
  && ok "호스트 설정이 없으면 멈춘다(종료 코드 1, 경로 없이) — 틀린 숫자를 내지 않는다" || fail "T11 호스트 설정 없음: $rc [$RP]"
report korean 2026-10-01..2026-10-06 2026-10-08..2026-10-12 --dir "$WORK/no-such-folder"
[[ "$rc" == 1 ]] && ! grep -qF 'no-such-folder' <<<"$RP" && ok "없는 --dir 는 종료 코드 1(경로 없이)" || fail "T11 없는 폴더: $rc [$RP]"
(cd "$WORK/t1" && TZ=KST-9 SCV_HOST_PROFILE="$WORK/rep.env" bash "$REPORT" --before 2026-10-01..2026-10-06 --after 2026-10-08..2026-10-12 >/dev/null 2>&1); rc=$?
[[ "$rc" == 1 ]] && ok "기록 폴더를 못 찾으면 종료 코드 1(지어내지 않는다)" || fail "T11 폴더 없음 코드: $rc"
R="$(new_repo t11j)"; mkdir -p "$R/scv/journal/.help-turns/s1"; printf '%s\n' "$WORK/records/a.jsonl" > "$R/scv/journal/.help-turns/s1/.help-transcript"
RJ="$(cd "$R" && TZ=KST-9 SCV_HOST_PROFILE="$WORK/rep.env" SCV_LANG=korean bash "$REPORT" --before 2026-10-01..2026-10-06 --after 2026-10-08..2026-10-12 2>&1)"
grep -qF '읽은 세션 기록 파일: 10개' <<<"$RJ" && ok "기본 폴더: SCV 가 세션마다 남긴 대화 기록 경로의 폴더" || fail "T11 기본 폴더: [$RJ]"
# 속도 — 맥 기본 bash 3.2 에서 긴 한글 메시지(6만 자 · 여러 줄)와 긴 모델 글이 든 기록. 글자 단위 치환을 쓰던 판은 이 크기의 기록
# 하나에 336초가 걸렸다(독립 검토 2026-10-07). 상한 30초로 지킨다.
mkdir -p "$WORK/big"
python3 - "$WORK/big/s.jsonl" <<'PYBIG'
import json, sys
long_msg = ("가나다라마바사 한글 문장입니다 고쳐 줘\n" * 3000)[:63000]
long_txt = "결과를 보여 드립니다 한 줄\n" * 4000
rows = [
  {"type": "user", "message": {"content": long_msg}, "timestamp": "2026-10-09T01:00:00Z"},
  {"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Writer", "input": {"file_path": "a", "content": "x"}}]}},
  {"type": "assistant", "message": {"content": [{"type": "text", "text": long_txt + "이대로 계속할까요, 고칠 점이 있나요?"}]}},
]
open(sys.argv[1], "w", encoding="utf-8").write("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows))
PYBIG
# 턴이 많은 세션 — 턴과 줄을 모아 붙이던 판 · jq 에서 줄마다 정규식을 돌리던 판은 턴 수에 제곱으로 느려졌다(300턴 27초 ·
# 1,500턴 211초, 맥 bash 3.2 — 독립 검토 2026-10-07). 지금 판은 턴 수에 비례(600턴 몇 초) — 상한 60초로 지킨다.
mkdir -p "$WORK/many"
python3 - "$WORK/many/m.jsonl" <<'PYMANY'
import json, sys
rows = []
for k in range(600):
    ts = "2026-10-09T%02d:%02d:00Z" % ((k // 60) % 24, k % 60)
    rows.append({"type": "user", "message": {"content": "작업 %d 해 줘 — 한글 문장 조금 길게 써 봅니다" % k}, "timestamp": ts})
    rows.append({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Writer", "input": {"file_path": "a%d" % k, "content": "x"}}]}})
    rows.append({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Runner", "input": {"command": "run"}}]}})
    rows.append({"type": "assistant", "message": {"content": [{"type": "text", "text": ("결과 줄입니다\n" * 200) + "끝났습니다."}]}})
open(sys.argv[1], "w", encoding="utf-8").write("".join(json.dumps(r, ensure_ascii=False) + "\n" for r in rows))
PYMANY
for B in bash /bin/bash; do
  command -v "$B" >/dev/null 2>&1 || continue
  _bv="$("$B" -c 'echo ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}')"
  t0=$(date +%s)
  RB="$(cd "$WORK" && TZ=KST-9 SCV_HOST_PROFILE="$WORK/rep.env" SCV_LANG=korean "$B" "$REPORT" --before 2026-10-01..2026-10-06 --after 2026-10-08..2026-10-12 --dir "$WORK/big" 2>&1)"
  t1=$(date +%s)
  grep -qF '| 켠 뒤 2026-10-08..2026-10-12 | 1 | 1 |' <<<"$RB" && (( t1 - t0 <= 30 )) \
    && ok "긴 한글 기록(6만 자) — $B $_bv 로 $((t1 - t0))s" || fail "T11 속도 $B $((t1 - t0))s: [$RB]"
  t0=$(date +%s)
  RB="$(cd "$WORK" && TZ=KST-9 SCV_HOST_PROFILE="$WORK/rep.env" SCV_LANG=korean "$B" "$REPORT" --before 2026-10-01..2026-10-06 --after 2026-10-08..2026-10-12 --dir "$WORK/many" 2>&1)"
  t1=$(date +%s)
  grep -qF '| 켠 뒤 2026-10-08..2026-10-12 | 1 | 600 |' <<<"$RB" && (( t1 - t0 <= 60 )) \
    && ok "턴 600개 세션 — $B $_bv 로 $((t1 - t0))s" || fail "T11 많은 턴 $B $((t1 - t0))s: [$RB]"
done

echo "── 설정 예시 ──"
python3 - "$EXAMPLE" <<'PY' && ok "예시 파일에 SCV_SHOW_REAL=on + 설명" || fail "예시 파일에 키 · 기본값 · 설명 중 빠진 것이 있다"
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
assert d.get("SCV_SHOW_REAL") == "on", d.get("SCV_SHOW_REAL")
doc = d.get("_doc", {}).get("SCV_SHOW_REAL", "")
assert "on" in doc and "off" in doc and "show-real.md" in doc, doc
PY

echo "─────────────────────────────"
echo "  통과 $PASS · 실패 $FAIL"
[[ $FAIL -eq 0 ]] && { echo "  ALL SHOW-REAL CHECKS OK"; exit 0; } || exit 1
