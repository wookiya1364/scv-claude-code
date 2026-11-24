#!/usr/bin/env bash
# test-gear-turn.sh — 기어 턴의 가벼운 길(계획 20261124-wookiya1364-gear-direct-light-turn T1–T6).
#
# 요청이 저장해 둔 기어를 돌리라는 것이면(기어 액션 꼴 · 창이 붙인 "[SCV 기어]" 줄) 매 턴 훅은 세 줄 안내만 싣고, 턴 끝 훅은
# 인용 · 끝 보고 · 계획 기록을 요구하지 않는다. 보통 턴은 그대로이고, 가벼운 길이 쓰기 전 검사를 풀지 않는다.
# T1 가리기(순수부) · T2 짧은 안내와 표시 · T3 보통 턴은 그대로 · T4 첫 도구가 무엇이든 통과 · T5 쓰기는 지금처럼 거절 ·
# T6 턴 끝은 막지도 알리지도 않고, 실행기가 저널에 한 줄을 남긴다.
set -euo pipefail
unset SCV_STOP_MODE SCV_GEARS_DIR SCV_JOURNAL_DIR SCV_GEAR_STATE_DIR 2>/dev/null || true

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$CORE/template/hooks/guard.sh"; PROMPT_HOOK="$CORE/template/hooks/on-user-prompt.sh"
STOP_HOOK="$CORE/template/hooks/on-stop.sh"; FIX="$CORE/tests/fixtures/model-prompting"; G="$CORE/scripts/gear.sh"
for f in "$GUARD" "$PROMPT_HOOK" "$STOP_HOOK" "$G" "$CORE/scripts/lib/gear.sh" "$FIX/profile.env"; do
  [[ -f "$f" ]] || { echo "✖ 없음: $f"; exit 1; }
done
command -v jq >/dev/null 2>&1 || { echo "jq 없음 — 이 검사는 jq 가 필요하다" >&2; exit 1; }
fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-gearturn.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
cp -R "$FIX/guides" "$WORK/guides-cl"
printf '# source: common.md\ngoal\tState the goal\tfixture quote a\n' > "$WORK/guides-cl/checklist-common.tsv"
{ cat "$FIX/profile.env"; printf 'SCV_PROMPTING_GUIDES=%s\nSCV_AUTO_PROMPT_TAGS=machine-event\nSCV_CHOICE_TOOL=PickTool\n' "$WORK/guides-cl"; } > "$WORK/profile.env"
export SCV_HOST_PROFILE="$WORK/profile.env" SCV_GUARD_STATE="$WORK/guard-state"

# @effect new_repo
# 이유: 임시 폴더에 시험용 프로젝트를 만든다 — 톱니 둘 · 기어 둘(make-list · other-gear), 설정 조각은 인자로
new_repo() {
  local d="$WORK/$1" x="${2:-}"; mkdir -p "$d/scv/journal" "$d/scv/archive"
  [[ -n "$x" ]] || x='{}'
  printf '%s\n' "$x" > "$d/scv/scv_settings.json"
  ( cd "$d" && export SCV_GEAR_STATE_DIR="$d/.gear-state"
    bash "$G" new upper --kind tooth --mark pure --in text --out text --does "대문자로 바꾼다" --example '"ab" → "AB"' >/dev/null
    printf '#!/usr/bin/env bash\ntr a-z A-Z\n' > scv/gears/teeth/upper.sh
    bash "$G" new make-list --kind gear --flow "upper" --does "목록을 만든다" >/dev/null
    bash "$G" new other-gear --kind gear --flow "upper" --does "다른 일을 한다" >/dev/null
    bash "$G" index >/dev/null ) || { echo "✖ 시험용 프로젝트를 만들지 못함: $1" >&2; exit 1; }
  printf '%s' "$d"
}
# @effect turn
# 이유: 사람 턴을 연다 — 매 턴 훅에 요청 글과 세션 번호를 넣고 훅이 낸 글을 돌려준다
turn() {
  (cd "$1" && jq -cn --arg p "$2" --arg s "${3:-s1}" '{prompt:$p,session_id:$s}' \
     | CLAUDE_PLUGIN_ROOT="$CORE" bash "$PROMPT_HOOK" 2>/dev/null)
}
# @effect gate
# 이유: 가드를 정한 방식으로 부른다 — 훅 입력 조각을 넣고 가드가 낸 글을 돌려준다
gate() {
  (cd "$1" && jq -cn --arg c "$1" --argjson x "$3" '{session_id:"s1",cwd:$c} + $x' \
     | SCV_GUARD_MODE="$2" SCV_GUARD_SCRIPTS="$CORE/scripts" SCV_HELP_FIRST_ALLOW="" bash "$GUARD" 2>/dev/null)
}
denied() { [[ "$1" == *'"permissionDecision":"deny"'* ]]; }
LINE_OF() { printf '[SCV 기어] 이 요청에 맞는 저장해 둔 방법이 있음: %s — 이 기어로 해 주세요(action:gear run %s). 값은 위 요청에서 읽고, 없는 값은 물어 주세요.' "$1" "$1"; }
NAMES=$'make-list\nother-gear'

# T1 — 기어 요청을 가린다: 액션 꼴과 창이 붙인 줄만. 낱말만 있거나 없는 이름이면 아니다
pick() { bash -c 'source "$1/scripts/lib/gear.sh"; scv_gear_turn "$2" "$3"' _ "$CORE" "$1" "$NAMES"; }
a="$(pick "action:gear run make-list count=3")"
b="$(pick "목록을 만들어 줘"$'\n\n'"$(LINE_OF other-gear)")"
c="$(pick "목록을 만들어 줘")"
d="$(pick "기어가 뭐야? gear run make-list 는 어떻게 쓰는 거야?")"
e="$(pick "$(LINE_OF nope)")"
f="$(pick '$scv-gear run other-gear')"
[[ "$a" == make-list && "$b" == other-gear && -z "$c" && -z "$d" && -z "$e" && "$f" == other-gear ]] \
  && ok "T1 액션 꼴 · 창이 붙인 줄만 기어 턴(낱말만 · 없는 이름은 아님)" || bad "T1 [$a] [$b] [$c] [$d] [$e] [$f]"

# T2 — 기어 턴에는 세 줄 안내만 실리고, 턴 상태에 표시가 남는다. 보통 턴의 절반 이하
R="$(new_repo t2)"
normal="$(turn "$R" "목록을 만들어 줘")"
gear="$(turn "$R" "목록을 만들어 줘"$'\n\n'"$(LINE_OF make-list)")"
mark="$(cat "$R/scv/journal/.help-turns/s1/.gear-turn" 2>/dev/null || true)"
nb="$(printf '%s' "$normal" | wc -c | tr -d ' ')"; gb="$(printf '%s' "$gear" | wc -c | tr -d ' ')"
if [[ "$gear" == *"[SCV 기어 턴] 이 요청은 저장해 둔 기어 make-list"* && "$gear" == *"넣을 자료는 표준 입력으로(text)"* && "$gear" == *"PickTool 로 한 번에 묻는다"* && "$gear" == *"| bash "*"gear.sh run make-list"* \
   && "$gear" != *"SCV: 이 턴의 첫 행동"* && "$gear" != *"[SCV plain language]"* && "$gear" != *"[SCV 확인 범위]"* && "$gear" != *"[SCV choices"* \
   && "$mark" == make-list && "$gb" -gt 0 && $((gb * 2)) -le "$nb" ]]; then ok "T2 기어 턴 안내 ${gb}B(보통 턴 ${nb}B) · 표시 있음"
else bad "T2 gear=${gb}B normal=${nb}B mark=[$mark]"; printf '%s\n' "$gear" | head -8 >&2; fi

# T3 — 보통 턴은 그대로: 기어가 있는 프로젝트에서도 보통 요청의 글은 이 기능을 끈 것과 같다. 기어 턴은 규칙 글을 '실었다'고 적지
#      않아 다음 보통 턴이 전문을 받고, 지난 표시는 지워진다. 끄면 기어 요청도 보통 턴이다
R="$(new_repo t3)"; R2="$(new_repo t3off '{"SCV_GEAR_TURN":"off"}')"
on="$(turn "$R" "기어가 뭐야? gear run 은 어떻게 써?" s2)"; off="$(turn "$R2" "기어가 뭐야? gear run 은 어떻게 써?" s2)"
turn "$R" "action:gear run make-list" >/dev/null; had=no; [[ -f "$R/scv/journal/.help-turns/s1/.gear-turn" ]] && had=yes
after="$(turn "$R" "목록은 어디에 생겨?")"
offg="$(turn "$R2" "action:gear run make-list")"
norm() { sed -E -e 's#/[^[:space:])]*/t3(off)?([/)[:space:]]|$)#/R\\2#g' -e 's/[0-9]{2}:[0-9]{2}/HH:MM/g' <<< "$1"; }
if [[ "$(norm "$on")" == "$(norm "$off")" && "$on" == *"SCV: 이 턴의 첫 행동"* && "$had" == yes && ! -e "$R/scv/journal/.help-turns/s1/.gear-turn" \
   && "$after" == *"[SCV plain language]"* && "$offg" != *"[SCV 기어 턴]"* ]]; then
  ok "T3 보통 턴은 끈 것과 같은 글 · 기어 턴 뒤 보통 턴은 규칙 전문 · 지난 표시 지움 · 끄면 보통 턴"
else bad "T3 had=$had"; diff <(norm "$on") <(norm "$off") | head -6 >&2 || true; fi

# T4 — 기어 턴은 도움말 · 등록 없이 첫 도구를 쓸 수 있다(실행기 · 읽기 모두). 보통 턴의 읽기는 거절
R="$(new_repo t4)"; turn "$R" "action:gear run make-list" >/dev/null
o1="$(gate "$R" gate-any '{"tool_name":"Read","tool_input":{"file_path":"a.txt"}}')"
o2="$(gate "$R" gate-any "$(jq -cn --arg c "bash \"$G\" run make-list" '{tool_name:"Bash",tool_input:{command:$c}}')")"
R2="$(new_repo t4n)"; turn "$R2" "목록을 만들어 줘" >/dev/null
o3="$(gate "$R2" gate-any '{"tool_name":"Read","tool_input":{"file_path":"a.txt"}}')"
[[ -z "$o1$o2" ]] && denied "$o3" && ok "T4 기어 턴의 첫 도구는 통과(보통 턴은 거절)" || bad "T4 [$o1] [$o2] [$o3]"

# T5 — 기어 턴에서도 파일 쓰기는 지금처럼 본다: 등록 없는 쓰기는 거절
R="$(new_repo t5)"; turn "$R" "action:gear run make-list" >/dev/null
o="$(gate "$R" gate-write "$(jq -cn --arg p "$R/src/a.sh" '{tool_name:"Write",tool_input:{file_path:$p,content:"echo x"}}')")"
denied "$o" && ok "T5 기어 턴의 파일 쓰기는 거절" || bad "T5 [$o]"

# T6 — 턴 끝: 결과 두 줄뿐인 답(인용 · 세 줄 끝 보고 없음)을 막지도 알리지도 않는다. 같은 답이 보통 턴이면 알림이 남는다.
#      실행기는 저널에 기어 이름 · 인자 · 종료 코드가 든 한 줄을 남긴다
stop_of() {  # <저장소> → 종료 훅 stdout
  local tr="$WORK/$(basename "$1").jsonl" A=$'make-list 를 돌렸음.\n결과: AB'
  printf '{"type":"user","message":{"content":[{"type":"text","text":"q"}]}}\n' > "$tr"
  jq -cn --arg c "bash $G run make-list" '{type:"assistant",message:{model:"vendor-model-a",content:[{type:"tool_use",id:"t1",name:"Bash",input:{command:$c}}]}}' >> "$tr"
  jq -cn '{type:"user",message:{content:[{type:"tool_result",tool_use_id:"t1",content:"AB"}]}}' >> "$tr"
  jq -cn --arg t "$A" '{type:"assistant",message:{model:"vendor-model-a",content:[{type:"text",text:$t}]}}' >> "$tr"
  (cd "$1" && jq -cn --arg p "$tr" --arg a "$A" '{session_id:"s1",transcript_path:$p,last_assistant_message:$a,stop_hook_active:false}' \
     | CLAUDE_PLUGIN_ROOT="$CORE" GIT_AUTHOR_NAME="Hook User" bash "$STOP_HOOK" 2>/dev/null)
}
warn_of() { cat "$1/scv/journal/.help-turns/s1/.help-warn" "$1/scv/journal/.help-warn" 2>/dev/null || true; }
R="$(new_repo t6)"; turn "$R" "action:gear run make-list" >/dev/null
gate "$R" gate-any "$(jq -cn --arg c "bash \"$G\" run make-list" '{tool_name:"Bash",tool_input:{command:$c}}')" >/dev/null
out="$(cd "$R" && printf 'ab' | SCV_GEAR_STATE_DIR="$R/.gear-state" GIT_AUTHOR_NAME="Hook User" bash "$G" run make-list 2>/dev/null)"
o="$(stop_of "$R")"; w="$(warn_of "$R")"
R2="$(new_repo t6n)"; turn "$R2" "목록을 만들어 줘" >/dev/null
gate "$R2" gate-any '{"tool_name":"Skill","tool_input":{"skill":"scv:help"}}' >/dev/null
o2="$(stop_of "$R2")"; w2="$(warn_of "$R2")"
jl="$(cat "$R"/scv/journal/*.md 2>/dev/null | grep -c '기어 make-list .*종료 코드 0' || true)"
if [[ "$out" == AB && "$o" != *'"decision"'* && -z "${w//[[:space:]]/}" && -n "${w2//[[:space:]]/}" && "$jl" == 1 ]]; then
  ok "T6 기어 턴의 끝 — 막힘 0 · 알림 0줄(보통 턴이면 알림), 저널 줄 1개"
else bad "T6 out=[$out] stop=[$o] warn=[$w] normal-warn=[${w2:0:80}] journal=$jl"; fi

[[ "$fail" == 0 ]] && echo "test-gear-turn: all passed" || { echo "test-gear-turn: FAIL"; exit 1; }
