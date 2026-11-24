#!/usr/bin/env bash
# test-choice-block.sh — 0.102.0 가드 Rule S: 닫는 요약 도구에 질문을 넣은 호출은 거절하고 선택 도구부터 부르게 한다.
#
# 배경: 실제 세션 134턴 중 12턴이 선택 도구 없이 글로 물으며 끝나 사용자가 채팅으로 답했다. 그 12턴 중 10턴은 모델이 호스트의
# 닫는 요약 도구에 질문과 버튼을 넣은 턴이었다. 턴 끝에서 잡으면 선택 창이 10~40초 늦게 떠서, 닫는 글이 나오기 전인 도구 호출
# 자리에서 잡는다(계획 dashboard-gears-ask-block). 턴 끝 검사는 0.101.0 그대로다 — 막지 않고 다음 턴 안내만.
# S1 질문이 실리면 거절 · S2 질문이 없으면 통과 · S3 다른 도구는 통과 · S4 래퍼가 이름을 주지 않으면 그대로 ·
# S5 선택 도구가 없는 실행(호스트에 없음 · 스위치 off · 사람 없는 실행) · S6 틀린 모양의 값 · S7 help 통과 목록보다 먼저 ·
# S8 턴 끝 검사는 그대로(알림만) · S9 순수부.
set -euo pipefail
unset SCV_STOP_MODE SCV_CHOICE_GATE SCV_SUMMARY_ASK

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; CORE="$(cd "$HERE/.." && pwd)"
GUARD="$CORE/template/hooks/guard.sh"; PROMPT_HOOK="$CORE/template/hooks/on-user-prompt.sh"
STOP_HOOK="$CORE/template/hooks/on-stop.sh"; FIX="$CORE/tests/fixtures/model-prompting"
for f in "$GUARD" "$PROMPT_HOOK" "$STOP_HOOK" "$CORE/scripts/choice-gate.sh" "$CORE/scripts/lib/choices.sh" "$FIX/profile.env"; do
  [[ -f "$f" ]] || { echo "✖ 없음: $f"; exit 1; }
done
command -v jq >/dev/null 2>&1 || { echo "jq 없음 — 이 검사는 jq 가 필요하다" >&2; exit 1; }
fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-choiceblock.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
{ cat "$FIX/profile.env"; printf 'SCV_CHOICE_TOOL=PickTool\n'; } > "$WORK/pick.env"
cp "$FIX/profile.env" "$WORK/none.env"
{ cat "$FIX/profile.env"; printf 'SCV_CHOICE_TOOL=PickTool\nSCV_CHOICE_OFF_WHEN=SCV_TEST_HEADLESS=1\n'; } > "$WORK/offwhen.env"
export SCV_GUARD_STATE="$WORK/guard-state"

new_repo() {  # <이름> [설정 조각 JSON] → 저장소 경로
  local r="$WORK/$1" x="${2:-}"; mkdir -p "$r/scv/journal" "$r/scv/archive"
  [[ -n "$x" ]] || x='{}'
  jq -n --argjson x "$x" '{SCV_LANG:"korean", SCV_MODEL_PROMPTING:"off", SCV_REWRITE_PRINCIPLE:"off", SCV_SHOW_REAL:"off"} + $x' > "$r/scv/scv_settings.json"
  printf '%s' "$r"
}
gate() {  # <저장소> <프로필> <훅 입력 JSON 조각> [요약 도구 값] [help 통과 목록] → 가드 stdout
  (cd "$1" && jq -cn --arg c "$1" --argjson x "$3" '{session_id:"s1",cwd:$c} + $x' \
     | SCV_GUARD_MODE=gate-any SCV_GUARD_SCRIPTS="$CORE/scripts" SCV_HOST_PROFILE="$2" SCV_SUMMARY_ASK="${4-SumTool=ask}" \
       SCV_HELP_FIRST_ALLOW="${5:-SumTool}" bash "$GUARD" 2>/dev/null)
}
denied() { [[ "$1" == *'"permissionDecision":"deny"'* ]]; }
SUM_ASK='{"tool_name":"SumTool","tool_input":{"recap":"두 화면을 고쳤음.","ask":"이대로 둘까요?","actions":[{"label":"이대로"},{"label":"더 고침"}]}}'
SUM_PLAIN='{"tool_name":"SumTool","tool_input":{"recap":"두 화면을 고쳤음."}}'
SUM_BLANK='{"tool_name":"SumTool","tool_input":{"recap":"두 화면을 고쳤음.","ask":"   "}}'
OTHER_ASK='{"tool_name":"OtherTool","tool_input":{"ask":"이대로 둘까요?"}}'

# S1 — 요약 도구에 질문이 실리면 거절하고, 이유가 선택 도구를 먼저 부르라고 말한다
R="$(new_repo s1)"; o="$(gate "$R" "$WORK/pick.env" "$SUM_ASK")"
denied "$o" && [[ "$o" == *"[SCV 선택지]"* && "$o" == *"PickTool 을 먼저 불러라"* && "$o" == *"질문 없이 다시 불러라"* ]] \
  && ok "S1 질문이 실린 요약 도구 호출은 거절" || bad "S1 [$o]"

# S2 — 질문이 없거나 빈 칸뿐이면 통과
o1="$(gate "$R" "$WORK/pick.env" "$SUM_PLAIN")"; o2="$(gate "$R" "$WORK/pick.env" "$SUM_BLANK")"
! denied "$o1" && ! denied "$o2" && ok "S2 질문이 없는 요약은 통과" || bad "S2 [$o1] [$o2]"

# S3 — 이름이 다른 도구는 같은 칸이 있어도 보지 않는다(help 통과 목록에 넣어 Rule H 와 가른다)
o="$(gate "$R" "$WORK/pick.env" "$OTHER_ASK" "SumTool=ask" "SumTool|OtherTool")"
! denied "$o" && ok "S3 다른 도구는 통과" || bad "S3 [$o]"

# S4 — 래퍼가 요약 도구를 알려 주지 않으면 0.101.0 과 같다
o="$(gate "$R" "$WORK/pick.env" "$SUM_ASK" "")"
! denied "$o" && ok "S4 값이 없으면 그대로 통과" || bad "S4 [$o]"

# S5 — 선택 도구가 없는 실행: 호스트에 없음 · 스위치 off · 사람 없는 실행
o1="$(gate "$R" "$WORK/none.env" "$SUM_ASK")"
R2="$(new_repo s5off '{"SCV_CHOICE_GATE":"off"}')"; o2="$(gate "$R2" "$WORK/pick.env" "$SUM_ASK")"
o3="$(SCV_TEST_HEADLESS=1 gate "$R" "$WORK/offwhen.env" "$SUM_ASK")"; o4="$(gate "$R" "$WORK/offwhen.env" "$SUM_ASK")"
! denied "$o1" && ! denied "$o2" && ! denied "$o3" && denied "$o4" \
  && ok "S5 선택 도구가 없는 실행은 통과(있으면 거절)" || bad "S5 [$o1] [$o2] [$o3] [$o4]"

# S6 — 틀린 모양의 값(칸 이름에 점 · 공백, 도구 이름만)은 아무것도 하지 않는다
n=0
for v in 'SumTool=a.b' 'SumTool=a b' 'SumTool' 'SumTool=' '=ask' 'SumToolX=ask'; do
  n=$((n + 1)); o="$(gate "$R" "$WORK/pick.env" "$SUM_ASK" "$v")"; ! denied "$o" || bad "S6-$n [$v] [$o]"
done
(( fail )) || ok "S6 틀린 모양의 값은 통과"

# S7 — help 를 아직 부르지 않은 사람 턴에서도, help 통과 목록에 있는 요약 도구의 질문은 거절한다(목록보다 먼저 본다)
{ cat "$WORK/pick.env"; printf 'SCV_AUTO_PROMPT_TAGS=machine-event\n'; } > "$WORK/pick-turn.env"
R="$(new_repo s7)"
(cd "$R" && jq -cn '{prompt:"화면 고쳐",session_id:"s1"}' | CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="$WORK/pick-turn.env" bash "$PROMPT_HOOK" >/dev/null 2>&1 || true)
o1="$(gate "$R" "$WORK/pick-turn.env" "$SUM_ASK")"; o2="$(gate "$R" "$WORK/pick-turn.env" "$SUM_PLAIN")"
denied "$o1" && [[ "$o1" == *"[SCV 선택지]"* ]] && ! denied "$o2" && ok "S7 help 통과 목록보다 먼저 봄" || bad "S7 [$o1] [$o2]"

# S8 — 턴 끝 검사는 0.101.0 그대로: 글로 물으며 끝나도 막지 않고 다음 턴 안내만 남긴다
R="$(new_repo s8)"; mkdir -p "$R/scv/journal/.help-turns/s1"; printf 'tok\n' > "$R/scv/journal/.help-turns/s1/.help-turn"
printf '{"session":"s1","protocol":1,"turn":3,"diag":"","diag_at":"","nonce":"abcd1234"}\n' > "$R/scv/journal/.help-state"
tr="$WORK/s8.jsonl"; A=$'**정리했음**\n- 두 가지 방법이 있음\n\n지금 바로 고칠까요, 아니면 한 번 더 잰 뒤에 고칠까요?'
printf '{"type":"user","message":{"content":[{"type":"text","text":"q"}]}}\n' > "$tr"
jq -cn --arg t "$A" '{type:"assistant",message:{model:"vendor-model-a",content:[{type:"text",text:$t}]}}' >> "$tr"
o="$(cd "$R" && jq -cn --arg p "$tr" --arg a "$A" '{session_id:"s1",transcript_path:$p,last_assistant_message:$a,stop_hook_active:false}' \
     | CLAUDE_PLUGIN_ROOT="$CORE" SCV_HOST_PROFILE="$WORK/pick.env" GIT_AUTHOR_NAME="Hook User" bash "$STOP_HOOK" 2>/dev/null)"
w="$(cat "$R/scv/journal/.help-turns/s1/.help-warn" "$R/scv/journal/.help-warn" 2>/dev/null || true)"
[[ "$o" != *'"decision"'* && "$w" == *"[SCV 직전 답] [SCV 선택지]"* ]] && ok "S8 턴 끝은 그대로 — 막지 않고 알림" || bad "S8 [$o] [$w]"

# S9 — 순수부: 이유 글이 도구 이름을 담고 한 줄이다
out="$(bash -c 'source "$1/scripts/lib/choices.sh"; scv_summary_ask_reason PickTool' _ "$CORE")"
[[ "$out" == "[SCV 선택지] 요약 도구에 질문을 넣었다"* && "$out" == *"PickTool 로 한다"* && "$out" != *$'\n'* ]] \
  && ok "S9 순수부(거절 이유 한 줄)" || bad "S9 [$out]"

if (( fail )); then echo "── test-choice-block: FAIL"; exit 1; fi
echo "── test-choice-block: 9 passed"
