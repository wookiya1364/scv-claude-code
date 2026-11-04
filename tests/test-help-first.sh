#!/usr/bin/env bash
# test-help-first.sh — 첫 도구를 help 로 고정(계획 20261104-wookiya1364-help-first-gate-080 T1–T7).
#
# help 전 도구 거절 · help 뒤 통과 · 다음 턴은 다시 · 다른 SCV 액션 · 통과 도구 목록 · 제외 · 도구 없는 턴 · 매 턴 지시.
set -euo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$CORE/template/hooks/guard.sh"; PROMPT_HOOK="$CORE/template/hooks/on-user-prompt.sh"
STOP_HOOK="$CORE/template/hooks/on-stop.sh"; FIX="$CORE/tests/fixtures/model-prompting"
fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-helpfirst.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
cp -R "$FIX/guides" "$WORK/guides-cl"
printf '# source: common.md\ngoal\tState the goal\tfixture quote a\n' > "$WORK/guides-cl/checklist-common.tsv"
{ cat "$FIX/profile.env"; printf 'SCV_PROMPTING_GUIDES=%s\nSCV_AUTO_PROMPT_TAGS=machine-event\n' "$WORK/guides-cl"; } > "$WORK/profile.env"
export SCV_HOST_PROFILE="$WORK/profile.env" SCV_GUARD_STATE="$WORK/guard-state"

new_repo() {  # <이름> [설정 json] → 저장소
  local d="$WORK/$1"; mkdir -p "$d/scv/journal" "$d/scv/archive"
  printf '%s\n' "${2:-{\}}" > "$d/scv/scv_settings.json"; printf '%s' "$d"
}
turn() {  # <저장소> <프롬프트> [세션] — 사람 턴 시작(매 턴 훅)
  (cd "$1" && jq -cn --arg p "$2" --arg s "${3:-s1}" '{prompt:$p,session_id:$s}' \
     | CLAUDE_PLUGIN_ROOT="$CORE" bash "$PROMPT_HOOK" 2>/dev/null)
}
gate() {  # <저장소> <모드> <훅 입력 json 조각> → 가드 stdout
  (cd "$1" && jq -cn --arg c "$1" --argjson x "$3" '{session_id:"s1",cwd:$c} + $x' \
     | SCV_GUARD_MODE="$2" SCV_GUARD_SCRIPTS="$CORE/scripts" SCV_HELP_FIRST_ALLOW="${ALLOW:-}" bash "$GUARD" 2>/dev/null)
}
denied() { [[ "$1" == *'"permissionDecision":"deny"'* ]]; }
READ='{"tool_name":"Read","tool_input":{"file_path":"a.txt"}}'
BASH_LS='{"tool_name":"Bash","tool_input":{"command":"ls"}}'
REG='{"tool_name":"Bash","tool_input":{"command":"bash /x/scv/core/scripts/model-prompting.sh register --model m"}}'

# T1 — help 전 도구 거절(읽기 · 쉘 · 등록 모두), 이유에 help 액션 이름
R="$(new_repo t1)"; turn "$R" "로그인 고쳐" >/dev/null
o1="$(gate "$R" gate-any "$READ")"; o2="$(gate "$R" gate-any "$BASH_LS")"; o3="$(gate "$R" gate-any "$REG")"
denied "$o1" && denied "$o2" && denied "$o3" && [[ "$o1" == *":help 를 이 턴 메시지"* ]] \
  && ok "T1 help 전 읽기 · 쉘 · 등록 거절, 이유에 help 액션 이름" || bad "T1 [$o1] [$o2] [$o3]"

# T2 — help 를 부르면 통과(스킬 호출 / help.sh 를 부르는 쉘), 그 호출 자체도 통과
R="$(new_repo t2)"; turn "$R" "로그인 고쳐" >/dev/null
o0="$(gate "$R" gate-any '{"tool_name":"Skill","tool_input":{"skill":"scv:help","args":"로그인 고쳐"}}')"
o1="$(gate "$R" gate-any "$READ")"
R2="$(new_repo t2b)"; turn "$R2" "로그인 고쳐" >/dev/null
o2="$(gate "$R2" gate-any '{"tool_name":"Bash","tool_input":{"command":"bash \"/p/vendor/scv-core/core/scripts/help.sh\" --with-context"}}')"
o3="$(gate "$R2" gate-any "$BASH_LS")"
[[ -z "$o0$o1$o2$o3" ]] && ok "T2 help 스킬 · help.sh 쉘 뒤 통과(호출 자체도 통과)" || bad "T2 [$o0] [$o1] [$o2] [$o3]"

# T3 — 다음 사람 턴은 다시 help 가 필요하다
turn "$R" "다음 요청" >/dev/null
o="$(gate "$R" gate-any "$READ")"
denied "$o" && ok "T3 다음 턴은 다시 거절" || bad "T3 [$o]"

# T4 — 다른 SCV 액션이 실린 턴(사용자가 친 명령의 기록 단계) · 통과 도구 목록 · 프로젝트의 help.sh 는 help 가 아님
R="$(new_repo t4)"; turn "$R" "작업 진행" >/dev/null
gate "$R" mint '{"command_name":"scv:work"}' >/dev/null
o1="$(gate "$R" gate-any "$READ")"
R2="$(new_repo t4b)"; turn "$R2" "x" >/dev/null
o2="$(ALLOW='Plan|Search' gate "$R2" gate-any '{"tool_name":"Plan","tool_input":{}}')"
o3="$(gate "$R2" gate-any '{"tool_name":"Bash","tool_input":{"command":"bash scripts/help.sh"}}')"
[[ -z "$o1$o2" ]] && denied "$o3" && ok "T4 SCV 액션 턴 · 통과 목록은 통과, 프로젝트 help.sh 는 거절" || bad "T4 [$o1] [$o2] [$o3]"

# T5 — 제외: 자동 알림 턴 · 하위 에이전트 · 사람 없는 세션 · SCV_ALWAYS_ON=off · scv/ 없음
pass=0
R="$(new_repo t5a)"; turn "$R" "사람 요청" >/dev/null; gate "$R" gate-any '{"tool_name":"Skill","tool_input":{"skill":"scv:help"}}' >/dev/null
turn "$R" "<machine-event>done</machine-event>" >/dev/null; [[ -z "$(gate "$R" gate-any "$READ")" ]] && pass=$((pass + 1))
R="$(new_repo t5b)"; turn "$R" "x" >/dev/null; [[ -z "$(gate "$R" gate-any '{"tool_name":"Read","agent_id":"a1","tool_input":{"file_path":"a"}}')" ]] && pass=$((pass + 1))
R="$(new_repo t5c)"; turn "$R" "x" >/dev/null; [[ -z "$(cd "$R" && jq -cn --arg c "$R" '{session_id:"other",cwd:$c,tool_name:"Read",tool_input:{file_path:"a"}}' | SCV_GUARD_MODE=gate-any SCV_GUARD_SCRIPTS="$CORE/scripts" bash "$GUARD" 2>/dev/null)" ]] && pass=$((pass + 1))
R="$(new_repo t5d '{"SCV_ALWAYS_ON":"off"}')"; turn "$R" "x" >/dev/null; [[ -z "$(gate "$R" gate-any "$READ")" ]] && pass=$((pass + 1))
mkdir -p "$WORK/plain"; [[ -z "$(cd "$WORK/plain" && jq -cn --arg c "$WORK/plain" '{session_id:"s1",cwd:$c,tool_name:"Read"}' | SCV_GUARD_MODE=gate-any bash "$GUARD" 2>/dev/null)" ]] && pass=$((pass + 1))
[[ "$pass" == 5 ]] && ok "T5 제외 5/5" || bad "T5 제외 $pass/5"

# T6 — 도구 없이 글만 쓴 턴: 종료 훅이 첫 멈춤에서 한 번 막는다
R="$(new_repo t6)"; turn "$R" "질문 하나" >/dev/null; TR="$WORK/t6.jsonl"
{ jq -cn '{type:"user",message:{content:[{type:"text",text:"질문 하나"}]}}'; jq -cn '{type:"assistant",message:{content:[{type:"text",text:"답임"}]}}'; } > "$TR"
st() { (cd "$R" && jq -cn --arg p "$TR" --argjson a "$1" '{transcript_path:$p,session_id:"s1",last_assistant_message:"답임",stop_hook_active:$a}' | CLAUDE_PLUGIN_ROOT="$CORE" GIT_AUTHOR_NAME=x bash "$STOP_HOOK" 2>/dev/null); }
o1="$(st false)"; o2="$(st true)"
[[ "$(jq -r .reason <<<"$o1" 2>/dev/null)" == *"[SCV help 먼저]"* && "$o2" != *"[SCV help 먼저]"* ]] \
  && ok "T6 도구 없는 턴은 첫 멈춤에서 한 번 막음" || bad "T6 [$o1] / [$o2]"
R="$(new_repo t6b)"; turn "$R" "질문 하나" >/dev/null; gate "$R" gate-any '{"tool_name":"Skill","tool_input":{"skill":"scv:help"}}' >/dev/null
o3="$(st false)"; [[ "$o3" != *"[SCV help 먼저]"* ]] && ok "T6 help 를 부른 턴은 막지 않음" || bad "T6b [$o3]"

# T7 — 매 턴 지시는 'help → 등록' 한 순서, 거절된다고 알림
R="$(new_repo t7)"; o="$(turn "$R" "x")"
[[ "$o" == *"help"*"거절"* ]] && grep -q 'help 를 부른 뒤' <<<"$o" && ok "T7 매 턴 지시: help 먼저 · 그다음 등록" || bad "T7 [$(grep -n 'help' <<<"$o" | head -3)]"

exit "$fail"
