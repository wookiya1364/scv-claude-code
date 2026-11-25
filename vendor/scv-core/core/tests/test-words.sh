#!/usr/bin/env bash
# test-words.sh — 낱말 사전(계획 20261125-wookiya1364-words · TESTS.md T1 ~ T17).
#
# 사전에 넣은 피할 말이 (1) 대화 첫머리의 안내 묶음으로 맥락마다 한 번 실리는지, (2) 답에 나오면 다음 턴에 한 줄로 알려지는지,
# (3) 사전이 없는 프로젝트에서는 매 턴 훅의 출력이 한 글자도 달라지지 않는지 본다. 사전 파일을 읽고 쓰는 명령의 출력 줄은
# 대시보드와 맞춘 약속이라 한 줄씩 그대로 견준다. 찾기는 바이트 단위라 맥 기본 셸(3.2) · 새 셸 · 글자 설정 C 에서 같아야 한다.
# 픽스처는 중립 id 만 쓴다 — 코어 payload 에 제공자 · 모델 이름을 넣지 않는다(tests/test-host-neutral.sh).
#
# Run: bash core/tests/test-words.sh
set -uo pipefail
unset SCV_WORDS SCV_WORDS_FILE SCV_RULES_ONCE SCV_JOURNAL_DIR SCV_SETTINGS_FILE SCV_SETTINGS_SECRET_FILE SCV_DIR 2>/dev/null || true

CORE="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
HOOK="$CORE/template/hooks/on-user-prompt.sh"; STOP="$CORE/template/hooks/on-stop.sh"; START="$CORE/template/hooks/on-session-start.sh"
W="$CORE/scripts/words.sh"; MP="$CORE/scripts/model-prompting.sh"; FIX="$CORE/tests/fixtures/model-prompting"
command -v jq >/dev/null 2>&1 || { echo "jq 없음 — 이 검사는 jq 가 필요하다" >&2; exit 1; }
# shellcheck source=../scripts/lib/words.sh
source "$CORE/scripts/lib/words.sh"

fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }
skipped=0
skip() { echo "skip $1"; skipped=$(( skipped + 1 )); }   # 건너뛴 항목 — 통과로 세지 않는다

WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-words.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
cp -R "$FIX/guides" "$WORK/guides"
{ cat "$FIX/profile.env"; printf 'SCV_PROMPTING_GUIDES=%s\nSCV_AUTO_PROMPT_TAGS=machine-event\n' "$WORK/guides"; } > "$WORK/profile.env"
export SCV_HOST_PROFILE="$WORK/profile.env" SCV_GUARD_STATE="$WORK/gs"

T=$'\t'
KOREAN='{"SCV_LANG":"korean"}'
QUIET='{"SCV_LANG":"korean","SCV_MODEL_PROMPTING":"off","SCV_REWRITE_PRINCIPLE":"off","SCV_SHOW_REAL":"off","SCV_FINISH_REPORT":"off"}'
FORMS="잰, 재서, 재 본, 재 봤, 쟀다, 재는"
E1="재다${T}측정하다${T}${FORMS}${T}"
E3="$E1"$'\n'"유저${T}사용자${T}${T}"$'\n'"utilize${T}use${T}${T}"
mkproj() {  # <이름> [설정 JSON] → 프로젝트 경로
  local p="$WORK/$1"; mkdir -p "$p/scv/journal"
  printf '%s\n' "${2:-$KOREAN}" > "$p/scv/scv_settings.json"; printf '%s' "$p"
}
words() { local p="$1"; shift; ( cd "$p" && bash "$W" "$@" ); }   # <프로젝트> <명령> … → 명령 출력(종료 코드 그대로)
seed() {  # <프로젝트> — 시험용 사전(항목 둘)
  words "$1" add --avoid 재다 --use 측정하다 --forms "$FORMS" >/dev/null && words "$1" add --avoid 유저 --use 사용자 >/dev/null \
    || { echo "✖ 시험용 사전을 만들지 못함: $1" >&2; exit 1; }
}
turn() {  # <프로젝트> <요청 글> [세션] [훅 파일] → 매 턴 훅 출력
  ( cd "$1" && jq -cn --arg p "$2" --arg s "${3:-s1}" '{prompt:$p,session_id:$s}' | CLAUDE_PLUGIN_ROOT="$CORE" bash "${4:-$HOOK}" 2>/dev/null )
}
heads() { grep -c '^\[SCV 낱말\] 아래 왼쪽 말' <<<"$1" || true; }
notes() { grep -c '^\[SCV 낱말\] 직전 답에 피할 말이 있었다' <<<"$1" || true; }
lines() { if [[ -n "$1" ]]; then printf '%s\n' "$1" | grep -c . || true; else echo 0; fi; }

# ---------- T1 — 사전 파일 글을 항목으로 읽는다 ----------
src=$'# 낱말 사전\n\n'"재다${T}측정하다${T}잰, 재서${T}수치 얘기"$'\n'"  # 들여 쓴 주석"$'\n'"유저${T}사용자"$'\r\n'"재다${T}계측하다${T}${T}"$'\n'"쓸 말 없음"$'\n'"${T}측정하다"
want="재다${T}측정하다${T}잰, 재서${T}수치 얘기"$'\n'"유저${T}사용자${T}${T}"
got="$(scv_words_parse "$src")"
[[ "$got" == "$want" && -z "$(scv_words_parse "")" ]] && ok "T1 주석 · 빈 줄 · 모자란 줄을 빼고 네 칸으로, 같은 피할 말은 앞의 것만" || bad "T1 [$got]"

# ---------- T2 — 넣기: 갈아 끼우고, 꼴을 주지 않으면 있던 꼴을 지킨다 ----------
base="재다${T}측정하다${T}${FORMS}${T}수치 얘기"$'\n'"유저${T}사용자${T}${T}"
a="$(scv_words_upsert "$base" 재다 계측하다 "" 0 "" 0)"
b="$(scv_words_upsert "$base" 재다 측정하다 "쟀다" 1 "" 1)"
c="$(scv_words_upsert "$base" 로그 기록 "로그들" 1 "" 0)"
if [[ "$a" == "재다${T}계측하다${T}${FORMS}${T}수치 얘기"$'\n'"유저${T}사용자${T}${T}" && "$b" == "재다${T}측정하다${T}쟀다${T}"$'\n'"유저${T}사용자${T}${T}" \
   && "$c" == "$base"$'\n'"로그${T}기록${T}로그들${T}" && "$(scv_words_forms "잰,재서 ,  재 본,, 잰")" == "잰, 재서, 재 본" ]]; then
  ok "T2 쓸 말만 바꾸면 꼴 · 메모 그대로, 꼴을 주면 바뀜, 새 말은 맨 뒤 — 자리는 그대로"
else bad "T2 [$a] [$b] [$c]"; fi

# ---------- T3 — 빼기 ----------
r1="$(scv_words_remove "$base" 재다)"; rc1=$?; r2="$(scv_words_remove "$base" 없는말)"; rc2=$?
[[ "$r1" == "유저${T}사용자${T}${T}" && $rc1 == 0 && "$r2" == "$base" && $rc2 == 1 ]] && ok "T3 있는 말은 그 줄만 빠짐(0), 없는 말은 그대로(1)" || bad "T3 rc=$rc1,$rc2 [$r1]"

# ---------- T4 — 낱말 첫머리에서만 센다 ----------
h0="$(scv_words_hits "지금이 현재다. 어제잰 것, 실재는 다르다" "$E1")"
h1="$(scv_words_hits "잰 값은 3초다" "$E1")"; h2="$(scv_words_hits "결과(잰 값)를 본다" "$E1")"; h3="$(scv_words_hits "값은 재 봤을 때 3초였다" "$E1")"
h4="$(scv_words_hits "“잰 값” · 속도—쟀다" "$E1")"; h5="$(scv_words_hits $'첫 줄\n재서 보니 빠르다' "$E1")"
if [[ -z "$h0" && "$h1" == "잰 → 측정하다" && "$h2" == "잰 → 측정하다" && "$h3" == "재 봤 → 측정하다" && "$h4" == "잰 → 측정하다" && "$h5" == "재서 → 측정하다" ]]; then
  ok "T4 낱말 안(현재다 · 어제잰 · 실재는)은 0건, 글 처음 · 괄호 · 빈칸 · 따옴표 · 줄 처음 뒤는 찾음"
else bad "T4 [$h0] [$h1] [$h2] [$h3] [$h4] [$h5]"; fi

# ---------- T5 — 코드와 인용한 사용자 글은 건너뛴다 ----------
quote=$'\x3e'
skip=$'값은 `잰` 것이다\n```\n잰 값\n```\n~~~\n재서\n~~~\n'"  $quote 잰 값을 알려 줘"
s0="$(scv_words_hits "$skip" "$E1")"; s1="$(scv_words_hits "$skip"$'\n'"그래서 잰 값은 3초다" "$E1")"
[[ -z "$s0" && "$s1" == "잰 → 측정하다" ]] && ok "T5 울타리 블록 · 백틱 안 · 인용 줄은 0건, 그 밖의 줄은 찾음" || bad "T5 [$s0] [$s1]"

# ---------- T6 — 꼴이 빈 항목: 피할 말 그대로와 두 글자 이상의 어간만 ----------
EMPTY="사용하다${T}쓰다${T}${T}"$'\n'"재다${T}측정하다${T}${T}"
e1="$(scv_words_hits "사용하는 값" "$EMPTY")"; e2="$(scv_words_hits "재는 값 · 잰 값" "$EMPTY")"; e3="$(scv_words_hits "길이를 재다" "$EMPTY")"
e4="$(scv_words_hits "We Utilized it. 사용자 수" "utilize${T}use${T}${T}"$'\n'"사용${T}사용자${T}${T}")"
if [[ "$e1" == "사용하 → 쓰다" && -z "$e2" && "$e3" == "재다 → 측정하다" && "$e4" == "Utilize → use" ]]; then
  ok "T6 어간 두 글자 이상만(사용하), 한 글자 어간(재)은 그대로만 · 영문은 대소문자 무관 · 쓸 말로 시작하는 자리는 세지 않음"
else bad "T6 [$e1] [$e2] [$e3] [$e4]"; fi

# ---------- T7 — 끄기: 안내도 검사도 하지 않는다 ----------
P="$(mkproj t7 '{"SCV_LANG":"korean","SCV_WORDS":"off"}')"; seed "$P"; Q="$(mkproj t7env)"; seed "$Q"
t_off="$(words "$P" text | wc -c | tr -d ' ')"; c_off="$(printf '잰 값' | words "$P" check)"; rc_off=$?
t_env="$( cd "$Q" && SCV_WORDS=off bash "$W" text | wc -c | tr -d ' ' )"; c_env="$( cd "$Q" && printf '잰 값' | SCV_WORDS=OFF bash "$W" check )"; rc_env=$?
hk_off="$(turn "$P" "로그인 흐름을 설명해 줘")"
if [[ "$t_off" == 0 && -z "$c_off" && $rc_off == 0 && "$t_env" == 0 && -z "$c_env" && $rc_env == 0 && "$(lines "$(words "$P" list)")" == 2 && "$(heads "$hk_off")" == 0 ]]; then
  ok "T7 끈 설정 · 끈 환경 변수: 안내 0바이트 · 검사 0줄(0) · 훅 묶음 0, 목록은 그대로 2줄"
else bad "T7 text=$t_off,$t_env check=[$c_off][$c_env] rc=$rc_off,$rc_env"; fi

# ---------- T8 — 명령 list ----------
P="$(mkproj t8)"; l0="$(words "$P" list)"; rc0=$?; seed "$P"; l2="$(words "$P" list)"
[[ "$l0" == "WORDS: none" && $rc0 == 0 && "$l2" == "$E1"$'\n'"유저${T}사용자${T}${T}" ]] && ok "T8 없으면 WORDS: none(0), 있으면 저장된 줄 그대로(탭 네 칸)" || bad "T8 [$l0] rc=$rc0 [$l2]"

# ---------- T9 — 명령 add ----------
P="$(mkproj t9)"
o1="$(words "$P" add --avoid 재다 --use 측정하다 --forms "잰,재서" --note "수치 얘기")"; rc1=$?
o2="$(words "$P" add --avoid 재다 --use 계측하다)"; f2="$(words "$P" list)"
before="$(cksum < "$P/scv/words/WORDS.tsv")"
x1="$(words "$P" add --avoid "" --use 측정 2>&1)"; rx1=$?; x2="$(words "$P" add --avoid 재다 --use "  " 2>&1)"; rx2=$?; x3="$(words "$P" add --avoid 같다 --use 같다 2>&1)"; rx3=$?
after="$(cksum < "$P/scv/words/WORDS.tsv")"
o3="$(words "$P" add --avoid $'탭\t든 말' --use $'줄\n바꿈' --forms $'가\t나, 다')"; f3="$(words "$P" list | tail -n 1)"
if [[ "$o1" == "WORDS_SAVED: 재다 → 측정하다" && $rc1 == 0 && "$o2" == "WORDS_SAVED: 재다 → 계측하다" && "$f2" == "재다${T}계측하다${T}잰, 재서${T}수치 얘기" \
   && $rx1 == 2 && $rx2 == 2 && $rx3 == 2 && "$x1" == "WORDS_ERROR: "* && "$x2" == "WORDS_ERROR: "* && "$x3" == "WORDS_ERROR: "* && "$before" == "$after" \
   && "$o3" == "WORDS_SAVED: 탭 든 말 → 줄 바꿈" && "$f3" == "탭 든 말${T}줄 바꿈${T}가 나, 다${T}" ]]; then
  ok "T9 넣기 · 갈아 끼우기(꼴 · 메모 유지) · 잘못된 값 셋은 WORDS_ERROR(2)이고 파일 그대로 · 칸 안의 탭 · 줄바꿈은 빈칸"
else bad "T9 [$o1][$o2][$f2] rc=$rx1,$rx2,$rx3 [$x1][$x2][$x3] [$o3][$f3]"; fi

# ---------- T10 — 명령 remove ----------
P="$(mkproj t10)"; seed "$P"
d1="$(words "$P" remove 재다)"; rd1=$?; d2="$(words "$P" remove 재다 2>&1)"; rd2=$?
[[ "$d1" == "WORDS_REMOVED: 재다" && $rd1 == 0 && "$d2" == "WORDS_ERROR: "* && $rd2 == 1 && "$(words "$P" list)" == "유저${T}사용자${T}${T}" ]] \
  && ok "T10 빼면 WORDS_REMOVED(0), 없는 말은 WORDS_ERROR(1)" || bad "T10 [$d1] $rd1 [$d2] $rd2"

# ---------- T11 — 명령 check ----------
P="$(mkproj t11)"; seed "$P"
k1="$(printf '%s' "잰 값을 보니 유저가 늘었다. 다시 재 봤을 때도 같았다." | words "$P" check)"; rk1=$?
k2="$(printf '%s' "측정한 값을 보니 사용자가 늘었다." | words "$P" check)"; rk2=$?
[[ "$k1" == "WORDS_HIT: 잰 → 측정하다"$'\n'"WORDS_HIT: 유저 → 사용자" && $rk1 == 1 && -z "$k2" && $rk2 == 0 ]] \
  && ok "T11 항목마다 WORDS_HIT 한 줄(1), 없으면 출력 없음(0)" || bad "T11 [$k1] $rk1 [$k2] $rk2"

# ---------- T12 — 명령 text ----------
P="$(mkproj t12)"; seed "$P"; Q="$(mkproj t12en '{"SCV_LANG":"english"}')"; seed "$Q"; R="$(mkproj t12none)"
x="$(words "$P" text)"; y="$(words "$Q" text)"; z="$(words "$R" text | wc -c | tr -d ' ')"
if [[ "$(lines "$x")" == 3 && "$(heads "$x")" == 1 && "$x" == *"괄호 안의 꼴은 예일 뿐 전부가 아니다"* && "$x" == *"코드 · 파일 이름 · 인용한 사용자 글 · 명령에는 적용하지 않는다"* \
   && "$x" == *"- 재다($FORMS) → 측정하다"* && "$x" == *"- 유저 → 사용자"* \
   && "$(lines "$y")" == 3 && "$y" == "[SCV words] "* && "$y" == *"examples, not the whole list"* && "$y" == *"not to code, file names, quoted user text or commands"* && "$z" == 0 ]]; then
  ok "T12 머리 한 줄 + 항목마다 한 줄(한국어 · 영어), 항목이 없으면 0바이트"
else bad "T12 줄=$(lines "$x"),$(lines "$y") 빈=$z"; fi

# ---------- T13 — 매 턴 훅: 맥락마다 한 번, 요약 뒤 다시, 사전이 바뀌면 다시 ----------
P="$(mkproj t13)"; seed "$P"
n1="$(heads "$(turn "$P" "로그인 흐름을 설명해 줘")")"; n2="$(heads "$(turn "$P" "이어서 설명해 줘 다음 부분")")"
( cd "$P" && jq -cn '{session_id:"s1",source:"compact"}' | CLAUDE_PLUGIN_ROOT="$CORE" bash "$START" >/dev/null 2>&1 )
n3="$(heads "$(turn "$P" "요약 뒤의 첫 요청이다")")"; n4="$(heads "$(turn "$P" "그다음 요청이다 계속")")"
words "$P" add --avoid 로그 --use 기록 >/dev/null
o5="$(turn "$P" "사전을 고친 뒤의 요청이다")"; n5="$(heads "$o5")"; n6="$(heads "$(turn "$P" "한 번 더 요청한다")")"
n7="$(heads "$(turn "$P" "다른 세션의 첫 요청이다" s2)")"
( cd "$P" && jq -cn '{session_id:"s3",source:"compact"}' | CLAUDE_PLUGIN_ROOT="$CORE" bash "$START" >/dev/null 2>&1 )
n8="$(heads "$(turn "$P" "<machine-event>done</machine-event>" s3)")"; n9="$(heads "$(turn "$P" "사람이 보낸 요청이다" s3)")"
Q="$(mkproj t13off '{"SCV_LANG":"korean","SCV_RULES_ONCE":"off"}')"; seed "$Q"
m1="$(heads "$(turn "$Q" "로그인 흐름을 설명해 줘")")"; m2="$(heads "$(turn "$Q" "이어서 설명해 줘 다음 부분")")"
if [[ "$n1$n2$n3$n4$n5$n6$n7$n8$n9" == "101010101" && "$o5" == *"- 로그 → 기록"* && "$m1$m2" == "11" ]]; then
  ok "T13 첫 턴 1 · 다음 0 · 요약 뒤 1 · 다음 0 · 사전 바뀜 1 · 다음 0 · 새 세션 1 · 자동 알림 턴 0 · 그 뒤 사람 턴 1 (한 번만 싣기를 끄면 매 턴)"
else bad "T13 $n1$n2$n3$n4$n5$n6$n7$n8$n9 끔=$m1$m2"; fi

# ---------- T14 — 사전이 없는 프로젝트의 훅 출력은 낱말 구간을 지운 훅과 바이트까지 같다 ----------
# 낱말 구간을 지운 훅은 코어를 본뜬 폴더(<본뜬 코어>/template/hooks) 안에 둔다(test-show-real-b 의 기능 없는 코어와 같은 방식) —
# 래퍼에 실린 사본에서는 코어 자리를 넘기는 환경 변수의 이름이 바뀌어 훅에 닿지 않고, 그때 훅은 제 자리에서 코어를 찾는다.
# 훅 말고는 모두 진짜 코어로 가는 링크라 같은 스크립트가 돈다. 출력에 실리는 본뜬 코어의 경로는 samepath 가 진짜 코어의 경로로 바꾼다.
PLAIN="$WORK/plain-core"; mkdir -p "$PLAIN/template/hooks"
PLAIN="$(cd "$PLAIN" && pwd)"   # 훅이 찍는 모양으로 — 임시 폴더 경로에 겹친 빗금이 있으면 글자 그대로는 찾지 못한다
for f in "$CORE"/*; do [[ "${f##*/}" == template ]] || ln -s "$f" "$PLAIN/${f##*/}"; done
for f in "$CORE"/template/*; do [[ "${f##*/}" == hooks ]] || ln -s "$f" "$PLAIN/template/${f##*/}"; done
cp "$CORE/template/hooks/"*.sh "$PLAIN/template/hooks/"
PLAIN_HOOK="$PLAIN/template/hooks/on-user-prompt.sh"
awk '/^# ---------- words -/ { skip = 1 } !skip { print } /^# ---------- \/words -/ { skip = 0 }' "$HOOK" > "$PLAIN_HOOK"
samepath() {  # 진단에 실리는 프로젝트 경로와 본뜬 코어의 경로만 같은 말로 바꾼다
  LC_ALL=C awk -v a="$PLAIN" -v b="$CORE" '{ out = ""; while ((i = index($0, a)) > 0) { out = out substr($0, 1, i - 1) b; $0 = substr($0, i + length(a)) } print out $0 }' \
    | sed -E 's#/[^ ()]*/t14[a-z]*([^A-Za-z0-9]|$)#PROJ\1#g'
}
P="$(mkproj t14new)"; Q="$(mkproj t14old)"; R="$(mkproj t14note)"; mkdir -p "$R/scv/words"; printf '# 주석 줄만 있는 사전\n\n' > "$R/scv/words/WORDS.tsv"
same=0
for q in "로그인 흐름을 설명해 줘" "이어서 설명해 줘 다음 부분"; do
  turn "$P" "$q" s1 "$HOOK" | samepath > "$WORK/t14.new"; turn "$Q" "$q" s1 "$PLAIN_HOOK" | samepath > "$WORK/t14.old"
  turn "$R" "$q" s1 "$HOOK" | samepath > "$WORK/t14.note"
  cmp -s "$WORK/t14.new" "$WORK/t14.old" && cmp -s "$WORK/t14.note" "$WORK/t14.old" && [[ -s "$WORK/t14.new" ]] && same=$(( same + 1 ))
done
cut_ok=no; ! grep -q 'words\.sh\|WORDS\.tsv' "$PLAIN_HOOK" && grep -q 'words\.sh" turn' "$HOOK" && cut_ok=yes
if [[ $same == 2 && $cut_ok == yes && ! -e "$P/scv/words" ]]; then ok "T14 사전 없음 · 주석뿐인 사전: 첫 턴과 둘째 턴의 출력이 낱말 구간 없는 훅과 같음($(wc -c < "$WORK/t14.new" | tr -d ' ') B), 폴더도 만들지 않음"
else bad "T14 같음=$same/2 구간지움=$cut_ok ($(wc -c < "$WORK/t14.new" | tr -d ' ') B · $(wc -c < "$WORK/t14.old" | tr -d ' ') B)"; fi

# ---------- T15 — 턴 끝 훅: 다음 턴 한 줄, 막지 않는다 ----------
jl_user() { jq -cn --arg t "$1" '{type:"user",message:{content:$t}}'; }
stop_hook() {  # <프로젝트> <대화 기록> <마지막 답> [세션] [이어진 멈춤 true|false] → 턴 끝 훅 출력
  ( cd "$1" && jq -cn --arg p "$2" --arg a "$3" --arg s "${4:-s1}" --argjson c "${5:-false}" '{transcript_path:$p,last_assistant_message:$a,session_id:$s,stop_hook_active:$c}' \
      | CLAUDE_PLUGIN_ROOT="$CORE" GIT_AUTHOR_NAME="Hook User" bash "$STOP" 2>/dev/null )
}
warn_all() { find "$1/scv/journal" -name '.help-warn' -exec cat {} + 2>/dev/null || true; }
BADA=$'**결과**\n\n잰 값은 3초였음. 다시 재 봤을 때도 같았음.'; GOODA=$'**결과**\n\n측정한 값은 3초였음.'
P="$(mkproj t15 "$QUIET")"; seed "$P"; TR="$WORK/t15.jsonl"; jl_user "속도를 알려 줘" > "$TR"
turn "$P" "속도를 알려 줘" >/dev/null
so="$(stop_hook "$P" "$TR" "$BADA")"; w1="$(warn_all "$P")"
stop_hook "$P" "$TR" "$BADA" >/dev/null; w1b="$(warn_all "$P")"
p1="$(turn "$P" "그럼 다음 값을 알려 줘")"; p2="$(turn "$P" "하나 더 알려 줘 부탁해")"
Q="$(mkproj t15good "$QUIET")"; seed "$Q"; turn "$Q" "속도를 알려 줘" >/dev/null; stop_hook "$Q" "$TR" "$GOODA" >/dev/null; w2="$(warn_all "$Q")"
R="$(mkproj t15auto "$QUIET")"; seed "$R"; TA="$WORK/t15auto.jsonl"; jl_user "<machine-event>done</machine-event>" > "$TA"
turn "$R" "속도를 알려 줘" >/dev/null; stop_hook "$R" "$TA" "$BADA" >/dev/null; w3="$(warn_all "$R")"
S="$(mkproj t15off '{"SCV_LANG":"korean","SCV_MODEL_PROMPTING":"off","SCV_REWRITE_PRINCIPLE":"off","SCV_SHOW_REAL":"off","SCV_FINISH_REPORT":"off","SCV_WORDS":"off"}')"; seed "$S"
turn "$S" "속도를 알려 줘" >/dev/null; stop_hook "$S" "$TR" "$BADA" >/dev/null; w4="$(warn_all "$S")"
U="$(mkproj t15cont "$QUIET")"; seed "$U"; turn "$U" "속도를 알려 줘" >/dev/null; stop_hook "$U" "$TR" "$BADA" s1 true >/dev/null; w5="$(warn_all "$U")"
want_note="[SCV 낱말] 직전 답에 피할 말이 있었다: 잰 → 측정하다 — 같은 뜻으로 쓴 것이면 이번 답부터 바꿔 말하라(직전 답은 다시 쓰지 않는다)."
if [[ "$so" != *'"decision"'* && "$(notes "$w1")" == 1 && "$(notes "$w1b")" == 1 && "$w1" == *"$want_note"* && "$(notes "$p1")" == 1 && "$(notes "$p2")" == 0 \
   && "$(notes "$w2")" == 0 && "$(notes "$w3")" == 0 && "$(notes "$w4")" == 0 && "$(notes "$w5")" == 0 ]]; then
  ok "T15 막지 않고 다음 턴에 한 줄(같은 줄은 한 번만) · 그다음 턴 0 · 깨끗한 답 · 자동 입력으로 열린 턴 · 끈 설정 · 이어진 멈춤은 0"
else bad "T15 막음=$([[ "$so" == *'"decision"'* ]] && echo y || echo n) 줄=$(notes "$w1"),$(notes "$w1b") 다음=$(notes "$p1"),$(notes "$p2") 그밖=$(notes "$w2"),$(notes "$w3"),$(notes "$w4"),$(notes "$w5")"; fi
# 낱말 알림 한 줄만 남은 턴은 규칙 글 전문을 다시 싣지 않는다(다른 알림이 함께 있으면 전문).
P="$(mkproj t15rules)"; seed "$P"
r1="$( cd "$P" && bash "$MP" rules --session s1 2>/dev/null )"
td="$(find "$P/scv/journal/.help-turns" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n 1)"   # 이 세션의 자리(규칙 판단이 방금 만든 폴더)
r2=""; r3=""
if [[ -n "$td" && -f "$td/.rules-seen" ]]; then
  printf '%s\n' "$want_note" > "$td/.help-warn"; r2="$( cd "$P" && bash "$MP" rules --session s1 2>/dev/null )"
  printf '%s\n' "[SCV 그림] 직전 답이 순서를 글로만 길게 적었다" >> "$td/.help-warn"; r3="$( cd "$P" && bash "$MP" rules --session s1 2>/dev/null )"
fi
[[ "$r1" == full && "$r2" == short && "$r3" == full ]] && ok "T15b 낱말 알림만 있으면 규칙 글은 한 줄 그대로, 다른 알림이 함께 있으면 전문" || bad "T15b [$r1] [$r2] [$r3] 자리=[$td]"

# ---------- T16 — 두 셸 · 글자 설정 C 에서 같은 결과 ----------
cat > "$WORK/pure.sh" <<'DRIVER'
source "$1/scripts/lib/words.sh"
T=$'\t'; q=$'\x3e'
E="재다${T}측정하다${T}잰, 재서, 재 본, 재 봤, 쟀다, 재는${T}"$'\n'"유저${T}사용자${T}${T}"$'\n'"사용하다${T}쓰다${T}${T}"$'\n'"utilize${T}use${T}${T}"
for a in "잰 값은 3초다" "값은 재 봤을 때 3초였다" "지금이 현재다. 어제잰 것" "“잰 값” · 속도—쟀다" "유저가 사용하는 값. We Utilized it" \
         $'값은 `잰` 것\n```\n잰 값\n```\n  '"$q 잰 값" "(재서) [재는] {유저}"; do
  printf '[%s]\n' "$(scv_words_hits "$a" "$E")"
done
printf '[%s]\n' "$(scv_words_parse $'# c\n\n'"재다${T}측정하다"$'\n'"유저${T}사용자${T}유저들${T}메모")"
printf '[%s]\n' "$(scv_words_upsert "$E" 재다 계측하다 "" 0 "" 0)" "$(scv_words_forms " 잰 ,재서,,잰")" "$(scv_words_field $' 가\t나 \n')"
printf '[%s]\n' "$(scv_words_text "$E" korean)" "$(scv_words_text "$E" english)" "$(scv_words_note $'잰 → 측정하다\n유저 → 사용자')" "$(scv_words_due "1 2" "1 2" on)"
DRIVER
new_sum="$(bash "$WORK/pure.sh" "$CORE" 2>&1 | cksum)"; c_sum="$(LC_ALL=C LANG=C bash "$WORK/pure.sh" "$CORE" 2>&1 | cksum)"
hit_n="$(bash "$WORK/pure.sh" "$CORE" 2>/dev/null | grep -c ' → ' || true)"
if [[ -x /bin/bash && "$(/bin/bash -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null)" == 3 ]]; then
  old_sum="$(/bin/bash "$WORK/pure.sh" "$CORE" 2>&1 | cksum)"
  cli_old="$( P="$(mkproj t16)"; cd "$P" && /bin/bash "$W" add --avoid 재다 --use 측정하다 --forms "$FORMS" >/dev/null && printf '잰 값' | /bin/bash "$W" check; /bin/bash "$W" list )"
  cli_new="$( P="$(mkproj t16b)"; cd "$P" && bash "$W" add --avoid 재다 --use 측정하다 --forms "$FORMS" >/dev/null && printf '잰 값' | bash "$W" check; bash "$W" list )"
  [[ "$new_sum" == "$old_sum" && "$new_sum" == "$c_sum" && "$cli_old" == "$cli_new" && "$cli_old" == "WORDS_HIT: 잰 → 측정하다"$'\n'"$E1" && "$hit_n" -ge 8 ]] \
    && ok "T16 기본 셸(3.2) · 새 셸 · 글자 설정 C 의 출력 지문이 같음, 명령도 두 셸에서 같은 줄" || bad "T16 새=[$new_sum] 옛=[$old_sum] C=[$c_sum] 명령=[$cli_old][$cli_new]"
else
  [[ "$new_sum" == "$c_sum" && "$hit_n" -ge 8 ]] && ok "T16 새 셸 · 글자 설정 C 의 출력 지문이 같음(기본 셸 3.2 가 없는 기계 — 그 부분은 건너뜀)" || bad "T16 새=[$new_sum] C=[$c_sum]"
fi

# ---------- T17 — 액션 목록과 순수성 ----------
# 액션 목록(actions.json)은 래퍼에 실린 사본에서는 래퍼 뿌리가 아니라 실어 온 코어 안에만 있다(test-routines.sh 와 같은 찾기).
# 어디에도 없는 사본에서는 목록 항목만 건너뛴다 — 통과로 세지 않는다.
ACTIONS=""
for c in "$CORE" "$CORE/vendor/scv-core/core" "$CORE/plugins/scv/vendor/scv-core/core"; do
  [[ -f "$c/actions.json" ]] && { ACTIONS="$c/actions.json"; break; }
done
if [[ -z "$ACTIONS" ]]; then skip "T17 액션 목록 — actions.json 이 없는 사본"; n="없음"; act=skip
else
  n="$(jq '.actions | length' "$ACTIONS" 2>/dev/null)"; act=bad
  [[ "$n" == 23 ]] && jq -e '.actions[] | select(.id == "words" and .owner == "core" and .protocol == "protocols/words.md" and .entrypoint == "scripts/words.sh")' "$ACTIONS" >/dev/null 2>&1 && act=ok
fi
if [[ "$act" != bad ]] \
   && grep -q 'words.sh" list' "$CORE/protocols/words.md" && grep -q 'words.sh" add ' "$CORE/protocols/words.md" && grep -q 'words.sh" remove ' "$CORE/protocols/words.md" \
   && grep -qE '^ACTIONS_RE=.*\|words\}' "$CORE/template/hooks/guard.sh" && bash "$CORE/scripts/check-purity.sh" "$CORE/scripts/lib/words.sh" "$W" >/dev/null 2>&1; then
  if [[ "$act" == ok ]]; then ok "T17 액션 23개 · words 의 규약과 입구가 맞음 · 가드의 액션 이름 목록에 있음 · 순수성 검사 통과"
  else ok "T17 words 의 규약이 명령을 부름 · 가드의 액션 이름 목록에 있음 · 순수성 검사 통과"; fi
else bad "T17 actions=$n"; fi

(( skipped > 0 )) && echo "건너뜀 $skipped"
exit "$fail"
