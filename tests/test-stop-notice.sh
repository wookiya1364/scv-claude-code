#!/usr/bin/env bash
# test-stop-notice.sh — 0.83.0 종료 검사 기본 방식(notice): 막지 않고 다음 턴 안내로 넘겨 같은 답이 두 번 보이지 않게.
#
# 배경: 실제 세션(slay 8개 + 개발 세션 1개) 186턴 중 78턴에서 종료 검사가 답을 막아 다시 쓰게 했고(114번, 한 턴 최대 4번),
# 다시 쓴 답 114개 중 82개가 '다시 쓴 요청' 인용을, 66개가 확인 범위 세 줄을 되풀이해 같은 답이 두 번 보였다.
# N1 기본은 막지 않음 + 다음 턴 안내 파일 · N2 다음 턴 매 턴 훅이 싣고 지움 · N3 SCV_STOP_MODE=block 이면 예전처럼 막음 ·
# N4 지킨 답은 안내 없음 · N5 제목형 확인 범위(쌍점 없는 '**확인한 것**' 아래 목록)는 빠진 줄이 아님 · N6 순수부.
set -euo pipefail
unset SCV_STOP_MODE

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROMPT_HOOK="$CORE/template/hooks/on-user-prompt.sh"; STOP_HOOK="$CORE/template/hooks/on-stop.sh"
fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-stopnotice.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT

new_repo() {  # <이름> [종료 방식] → 저장소 경로. 등록 · 원칙 · 실체 보여 주기 검사는 꺼서 언어 · 확인 범위만 남긴다.
  local r="$WORK/$1"; mkdir -p "$r/scv/journal"
  jq -n --arg m "${2:-}" '{SCV_LANG:"korean", SCV_MODEL_PROMPTING:"off", SCV_REWRITE_PRINCIPLE:"off", SCV_SHOW_REAL:"off"}
    + (if $m == "" then {} else {SCV_STOP_MODE:$m} end)' > "$r/scv/scv_settings.json"
  printf '%s' "$r"
}
jl_user() { jq -cn --arg t "$1" '{type:"user",message:{content:$t}}'; }
jl_call() { jq -cn --arg id "$1" --argjson i "$2" '{type:"assistant",uuid:("u-"+$id),message:{content:[{type:"tool_use",id:$id,name:"T",input:$i}]}}'; }
jl_res() { jq -cn --arg id "$1" --arg t "$2" '{type:"user",sourceToolUseID:$id,message:{content:[{type:"tool_result",tool_use_id:$id,content:$t,is_error:false}]}}'; }
stop_hook() {  # <저장소> <원본> <마지막 답> → 종료 훅 stdout
  (cd "$1" && jq -cn --arg p "$2" --arg a "$3" '{transcript_path:$p,last_assistant_message:$a,stop_hook_active:false}' \
     | CLAUDE_PLUGIN_ROOT="$CORE" GIT_AUTHOR_NAME="Hook User" bash "$STOP_HOOK" 2>/dev/null)
}
prompt_hook() { (cd "$1" && printf '{"prompt":"x"}' | CLAUDE_PLUGIN_ROOT="$CORE" bash "$PROMPT_HOOK" 2>/dev/null || true); }
work_turn() {
  { jl_user "고쳐 줘"
    jl_call e1 '{"file_path":"/w/src/app.sh","old_string":"a","new_string":"b"}'; jl_res e1 "ok"
    jl_call r1 '{"command":"ls src","description":"목록 보기"}'; jl_res r1 "app.sh"
  } > "$1"
}
warnf() { cat "$1/scv/journal/.help-warn" 2>/dev/null || true; }
BADA=$'**결과**\n- Statuses are wired in now.'
GOOD=$'**고쳤음**\n- 앱 줄을 바꿈\n\n- 확인한 것: 목록 보기 → app.sh 있음\n- 확인 못 한 것: 실제 실행은 안 해 봄\n- 제가 대신 정한 것: 바꿀 줄을 하나로 정함'
HEAD=$'**고쳤음**\n- 앱 줄을 바꿈\n\n**확인한 것**\n- 목록 보기 → app.sh 있음\n\n**확인 못 한 것**\n- 실제 실행은 안 해 봄\n\n**제가 대신 정한 것**\n- 바꿀 줄을 하나로 정함'

# N1 — 기본: 막지 않고, 어긋난 점을 다음 턴 안내 파일에 남긴다
R="$(new_repo n1)"; TR="$WORK/n1.jsonl"; work_turn "$TR"
o="$(stop_hook "$R" "$TR" "$BADA")"; w="$(warnf "$R")"
[[ "$o" != *'"decision"'* && "$w" == *"[SCV 직전 답] [SCV 언어]"* && "$w" == *"[SCV 직전 답] [SCV 확인 범위]"* \
   && "$w" == *"직전 답을 다시 쓰거나 고쳐 쓰지 말 것"* && "$w" != *"앞 답은 이미 사용자 화면에 있다"* ]] \
  && ok "N1 기본: 막지 않음 · 언어 · 확인 범위 이유가 다음 턴 안내로" || bad "N1 [$o] [$w]"

# N2 — 다음 사람 턴의 매 턴 훅이 안내를 한 번 싣고 지운다
p="$(prompt_hook "$R")"; p2="$(prompt_hook "$R")"
[[ "$p" == *"[SCV 직전 답] [SCV 언어]"* && ! -e "$R/scv/journal/.help-warn" && "$p2" != *"[SCV 직전 답]"* ]] \
  && ok "N2 다음 턴에 한 번 싣고 지움" || bad "N2 [$(grep -F '[SCV 직전 답]' <<<"$p" | head -2)] [$(grep -cF '[SCV 직전 답]' <<<"$p2" || true)]"

# N3 — SCV_STOP_MODE=block: 예전처럼 막고, 안내 파일은 만들지 않는다
R="$(new_repo n3 block)"; TR="$WORK/n3.jsonl"; work_turn "$TR"
o="$(stop_hook "$R" "$TR" "$BADA")"
[[ "$o" == *'"decision":"block"'* && "$o" == *"앞 답은 이미 사용자 화면에 있다"* && -z "$(warnf "$R")" ]] \
  && ok "N3 block 이면 예전처럼 막음" || bad "N3 [$o] [$(warnf "$R")]"

# N4 — 지킨 답: 막지도 안내하지도 않는다
R="$(new_repo n4)"; TR="$WORK/n4.jsonl"; work_turn "$TR"
o="$(stop_hook "$R" "$TR" "$GOOD")"
[[ "$o" != *'"decision"'* && -z "$(warnf "$R")" ]] && ok "N4 지킨 답은 안내 없음" || bad "N4 [$o] [$(warnf "$R")]"

# N5 — 제목형 확인 범위는 빠진 줄이 아니다(실제 오탐 31건의 모양)
R="$(new_repo n5)"; TR="$WORK/n5.jsonl"; work_turn "$TR"
o="$(stop_hook "$R" "$TR" "$HEAD")"; w="$(warnf "$R")"
[[ "$o" != *'"decision"'* && "$w" != *"[SCV 확인 범위]"* ]] && ok "N5 제목형 세 줄 인정" || bad "N5 [$o] [$w]"

# N6 — 순수부
out="$(bash -c 'source "'"$CORE"'/scripts/lib/stop-gates.sh"
  printf "%s|%s|%s|%s\n" "$(scv_stop_mode "")" "$(scv_stop_mode block)" "$(scv_stop_mode " BLOCK ")" "$(scv_stop_mode off)"
  printf "%s\n" "$(scv_stop_notice $'"'"'a\n\nb'"'"')"; printf "[%s]\n" "$(scv_stop_notice "")"')"
want=$'notice|block|block|notice\n[SCV 직전 답] a\n[SCV 직전 답] b\n[SCV 직전 답] 이번 답부터 지켜라 — 직전 답을 다시 쓰거나 고쳐 쓰지 말 것.\n[]'
[[ "$out" == "$want" ]] && ok "N6 순수부(방식 판정 · 안내 줄)" || bad "N6 [$out]"

if (( fail )); then echo "── test-stop-notice: FAIL"; exit 1; fi
echo "── test-stop-notice: 6 passed"
