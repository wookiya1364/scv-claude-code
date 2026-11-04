#!/usr/bin/env bash
# test-lang-enforce.sh — 설정 언어 강제(계획 20261103-wookiya1364-lang-enforce-079 T1–T6).
#
# 매 턴 언어 줄 · 도구 뒤 교정 · 같은 글 다시 교정 안 함 · 최종 답 막기(한 번만) · 통과해야 하는 경우 · 실패와 속도.
set -euo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROMPT_HOOK="$CORE/template/hooks/on-user-prompt.sh"; STOP_HOOK="$CORE/template/hooks/on-stop.sh"
LANG_HOOK="$CORE/template/hooks/on-lang-check.sh"
# shellcheck source=../scripts/lib/lang-enforce.sh
source "$CORE/scripts/lib/lang-enforce.sh"
fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-lang.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
EN1="Statuses, moods and enemy statuses are wired in for the next battle step now."
EN2="All fourteen new unit tests pass, so I will remove two stray lines from the test."
EN3="Card table done. Now wiring statuses, moods and the new card effects into the rules."

new_repo() {  # <이름> <언어> → 저장소 경로. 등록 · 원칙 검사는 꺼서 언어 검사만 남긴다.
  local r="$WORK/$1"; mkdir -p "$r/scv/journal"
  jq -n --arg l "$2" '{SCV_LANG:$l, SCV_MODEL_PROMPTING:"off", SCV_REWRITE_PRINCIPLE:"off", SCV_SHOW_REAL:"off"}' > "$r/scv/scv_settings.json"
  printf '%s' "$r"
}
jl_user() { jq -cn --arg t "$1" '{type:"user",message:{content:[{type:"text",text:$t}]}}'; }
jl_asst() { jq -cn --arg t "$1" --arg u "$2" '{type:"assistant",uuid:$u,message:{content:[{type:"text",text:$t}]}}'; }
jl_tool() { printf '%s\n' '{"type":"assistant","uuid":"tu","message":{"content":[{"type":"tool_use","name":"Bash"}]}}' '{"type":"user","sourceToolUseID":"x","message":{"content":[{"type":"tool_result","content":"x"}]}}'; }
lang_hook() {  # <저장소> <원본> → 도구 뒤 훅 stdout
  (cd "$1" && jq -cn --arg p "$2" '{transcript_path:$p,session_id:"s1",tool_name:"Bash"}' \
     | CLAUDE_PLUGIN_ROOT="$CORE" bash "$LANG_HOOK" 2>/dev/null)
}
stop_hook() {  # <저장소> <원본> <마지막 답> <계속 중 true|false> → 종료 훅 stdout
  (cd "$1" && jq -cn --arg p "$2" --arg a "$3" --argjson s "$4" '{transcript_path:$p,session_id:"s1",last_assistant_message:$a,stop_hook_active:$s}' \
     | CLAUDE_PLUGIN_ROOT="$CORE" GIT_AUTHOR_NAME="Hook User" bash "$STOP_HOOK" 2>/dev/null)
}

# T1 — 매 턴 언어 줄: korean 이면 한 줄, 비면 없음
R="$(new_repo t1 korean)"; o1="$(cd "$R" && printf '{"prompt":"x"}' | CLAUDE_PLUGIN_ROOT="$CORE" bash "$PROMPT_HOOK" 2>/dev/null || true)"
R="$(new_repo t1b "")"; o2="$(cd "$R" && printf '{"prompt":"x"}' | CLAUDE_PLUGIN_ROOT="$CORE" bash "$PROMPT_HOOK" 2>/dev/null || true)"
n1="$(grep -c '^\[SCV 언어\].*중간 보고' <<<"$o1" || true)"; n2="$(grep -c '^\[SCV 언어\]' <<<"$o2" || true)"
[[ "$n1" == 1 && "$n2" == 0 && "$(head -1 <<<"$o1")" == "[SCV 언어]"* ]] && ok "T1 매 턴 맨 앞 언어 줄(korean 1 · 빈 값 0)" || bad "T1 [$n1] [$n2] [$(head -1 <<<"$o1")]"

# T2 — 도구 뒤 교정: 영어 3줄 → 교정 문구
R="$(new_repo t2 korean)"; TR="$WORK/t2.jsonl"
{ jl_user "만들어 줘"; jl_asst "$EN1" a1; jl_tool; jl_asst "$EN2"$'\n'"$EN3" a2; jl_tool; } > "$TR"
o="$(lang_hook "$R" "$TR")"
c="$(jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$o" 2>/dev/null)"
[[ "$c" == *"3줄이 한국어가 아니다"*"한국어로 써라"* ]] && ok "T2 도구 뒤 교정 문구(3줄 · 한국어)" || bad "T2 [$o]"

# T3 — 같은 글은 다시 교정하지 않고, 새 영어 글만 센다
o="$(lang_hook "$R" "$TR")"
{ jl_asst "$EN1" a3; jl_tool; } >> "$TR"; o2="$(lang_hook "$R" "$TR")"
c2="$(jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$o2" 2>/dev/null)"
[[ -z "$o" && "$c2" == *"1줄이"* ]] && ok "T3 본 글은 다시 안 봄 · 새 글 1줄만" || bad "T3 [$o] [$o2]"

# T4 — 최종 답이 어긋나면 막는다, 한 턴에 한 번만
R="$(new_repo t4 korean)"; TR="$WORK/t4.jsonl"; FINAL="**결과**"$'\n'"- $EN1"$'\n'"- $EN2"$'\n'"- $EN3"
{ jl_user "만들어 줘"; jl_asst "$FINAL" b1; } > "$TR"
o="$(stop_hook "$R" "$TR" "$FINAL" false)"
r="$(jq -r '.reason // empty' <<<"$o" 2>/dev/null)"
o2="$(stop_hook "$R" "$TR" "$FINAL" true)"
[[ "$(jq -r .decision <<<"$o" 2>/dev/null)" == block && "$r" == *"최종 답 중 3줄이 한국어가 아니다"* && "$r" == *"고친 부분만"* && "$o2" != *"[SCV 언어]"* ]] \
  && ok "T4 최종 답 막기(언어 · 고친 부분만) · 두 번째 멈춤은 안 막음" || bad "T4 [$o] / [$o2]"
w="$(cat "$R/scv/journal/.help-warn" 2>/dev/null || true)"
[[ "$w" == *"한국어로 써라"* ]] && ok "T4 다음 턴 경고에 언어 이름" || bad "T4 경고 [$w]"

# T5 — 통과해야 하는 경우: 한국어 답 · 코드 블록만 영어 · 언어 비어 있음 · 중간만 영어
pass=0
R="$(new_repo t5a korean)"; TR="$WORK/t5a.jsonl"; A=$'**결과**\n- 모두 통과함\n- 다음은 릴리스임'
{ jl_user "x"; jl_asst "$A" c1; } > "$TR"; [[ "$(stop_hook "$R" "$TR" "$A" false)" != *'"block"'* ]] && pass=$((pass + 1))
R="$(new_repo t5b korean)"; TR="$WORK/t5b.jsonl"; A=$'**결과**\n- 통과함\n```\n'"$EN1"$'\n```\n- `core/tests/some-long-english-file-name-here.sh` 를 돌림'
{ jl_user "x"; jl_asst "$A" c2; } > "$TR"; [[ "$(stop_hook "$R" "$TR" "$A" false)" != *'"block"'* ]] && pass=$((pass + 1))
R="$(new_repo t5c "")"; TR="$WORK/t5c.jsonl"; A="$EN1"
{ jl_user "x"; jl_asst "$A" c3; } > "$TR"; [[ "$(stop_hook "$R" "$TR" "$A" false)" != *'"block"'* && -z "$(lang_hook "$R" "$TR")" ]] && pass=$((pass + 1))
R="$(new_repo t5d korean)"; TR="$WORK/t5d.jsonl"; A=$'**결과**\n- 모두 통과함'
{ jl_user "x"; jl_asst "$EN1" c4; jl_tool; jl_asst "$A" c5; } > "$TR"; [[ "$(stop_hook "$R" "$TR" "$A" false)" != *'"block"'* ]] && pass=$((pass + 1))
[[ "$pass" == 4 ]] && ok "T5 통과해야 하는 경우 4/4" || bad "T5 통과 $pass/4"

# T6 — 실패해도 막지 않음 · 속도
R="$(new_repo t6 korean)"; e=0
o="$(cd "$R" && printf 'not json' | CLAUDE_PLUGIN_ROOT="$CORE" bash "$LANG_HOOK" 2>/dev/null)" || e=1
o2="$(lang_hook "$R" "$WORK/none.jsonl")" || e=1
TR="$WORK/t6.jsonl"; { jl_user "x"; for i in $(seq 1 3000); do jl_asst "진행 중 메시지 $i 번째임 — 한국어로 쓴 중간 보고" "id$i"; jl_tool; done; } > "$TR"
sz="$(wc -c < "$TR" | tr -d ' ')"
t0=$(date +%s); o3="$(lang_hook "$R" "$TR")" || e=1; t1=$(date +%s)
[[ "$e" == 0 && -z "$o$o2$o3" && $((t1 - t0)) -le 1 ]] && ok "T6 깨진 입력 · 원본 없음 → 조용히 통과, ${sz}B 원본 $((t1 - t0))s" || bad "T6 e=$e [$o$o2$o3] $((t1 - t0))s"

# T8 — 사용자가 다른 언어를 요청하면 강제하지 않는다(Top-level rules 7조): 교정 없음 · 막지 않음 · 언어 경고 없음
R="$(new_repo t8 korean)"; TR="$WORK/t8.jsonl"; A="$EN1"$'\n'"$EN2"
{ jl_user "이번 답은 영어로 써 줘"; jl_asst "$EN3" d1; jl_tool; jl_asst "$A" d2; } > "$TR"
o="$(lang_hook "$R" "$TR")"; o2="$(stop_hook "$R" "$TR" "$A" false)"
w="$(cat "$R/scv/journal/.help-warn" 2>/dev/null || true)"
R2="$(new_repo t8b korean)"; TR2="$WORK/t8b.jsonl"
{ jl_user "Please write the summary in plain English for the team."; jl_asst "$A" d3; } > "$TR2"
o3="$(stop_hook "$R2" "$TR2" "$A" false)"
[[ -z "$o" && "$o2" != *"[SCV 언어]"* && "$w" != *"한국어로 써라"* && "$o3" != *"[SCV 언어]"* ]] \
  && ok "T8 다른 언어 요청 · 다른 언어로 쓴 요청이면 교정 · 막기 · 경고 없음" || bad "T8 [$o] [$o2] [$w] [$o3]"

# T9 — 긴 턴(0.81.2): 사용자 메시지가 원본 끝 400줄 밖이어도 새 글을 검사하고, 다른 언어 요청도 찾는다
R="$(new_repo t9 korean)"; TR="$WORK/t9.jsonl"
{ jl_user "만들어 줘"; for _i in $(seq 1 250); do jl_tool; done; jl_asst "$EN1" e1; jl_tool; } > "$TR"
o="$(lang_hook "$R" "$TR")"
c="$(jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$o" 2>/dev/null)"
R2="$(new_repo t9b korean)"; TR2="$WORK/t9b.jsonl"
{ jl_user "이번 답은 영어로 써 줘"; for _i in $(seq 1 250); do jl_tool; done; jl_asst "$EN1" e2; jl_tool; jl_asst "$EN2"$'\n'"$EN3" e3; } > "$TR2"
o2="$(lang_hook "$R2" "$TR2")"; o3="$(stop_hook "$R2" "$TR2" "$EN2"$'\n'"$EN3" false)"
[[ "$c" == *"1줄이 한국어가 아니다"* && -z "$o2" && "$o3" != *"[SCV 언어]"* ]] \
  && ok "T9 긴 턴: 400줄 밖 요청이어도 새 글 교정 · 다른 언어 요청은 그대로 존중" || bad "T9 [$o] [$o2] [$o3]"

# 순수 함수 직접 확인
[[ "$(scv_lang_stop_decide 2 0)" == block && "$(scv_lang_stop_decide 2 1)" == ok && -z "$(scv_lang_rule_line english)" ]] \
  && ok "판정 함수(막기 한 번 · english 무동작)" || bad "판정 함수"

exit "$fail"
