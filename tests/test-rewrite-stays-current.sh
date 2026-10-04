#!/usr/bin/env bash
# test-rewrite-stays-current.sh — 다시 쓴 요청이 일 내내 맞게 (v0.65.0+).
#
# 계획: scv/promote/20261003-wookiya1364-rewrite-stays-current/TESTS.md 의 T1~T10 (픽스처로 도는 자동 검사).
#   T1  보이는 곳 — 맨 위 한 줄 + 결론 뒤 전문, 빠진 쪽을 이름으로 말한다
#   T2  설정 설명 · 매 턴 블록 · 경고 · 규약이 같은 위치를 말한다(옛 문구 0)
#   T3  선택 창 답 뒤 첫 편집 전 다시 등록 — 거절 → 재등록 → 허용, 답 없는 턴은 그대로
#   T4  '그대로' 한 줄 등록(register --keep) — 답 뒤에만 받는다
#   T5  범위(scope) 칸의 변경 금지 — 막고, 다른 칸 문장은 판정하지 않는다
#   T6  가이드 다시 읽기 — 대화 기록(마지막 압축 경계 뒤 읽음 표시)으로 판단
#   T7  큰 대화 기록에서의 속도
#   T8  세션별 턴 상태 — 두 세션이 서로 끼어들지 않는다
#   T9  하위 세션 — 사람 메시지를 받지 않은 세션은 막지 않고 리드의 상태를 건드리지 않는다
#   T10 종료 검사의 입력 창 — 64KB 를 넘는 답의 끝 질문 · 한가운데 문제 표
# 픽스처는 중립 id · 중립 도구 이름만 쓴다(코어 payload 에 제공자 · 모델 이름을 넣지 않는다).
#
# Run: bash core/tests/test-rewrite-stays-current.sh
set -uo pipefail

CORE="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
LIB="$CORE/scripts/lib/model-prompting.sh"
MP="$CORE/scripts/model-prompting.sh"
HELP="$CORE/scripts/help.sh"
PROMPT_HOOK="$CORE/template/hooks/on-user-prompt.sh"
STOP_HOOK="$CORE/template/hooks/on-stop.sh"
START_HOOK="$CORE/template/hooks/on-session-start.sh"
ANSWER_HOOK="$CORE/template/hooks/on-choice-answer.sh"
GUARD="$CORE/template/hooks/guard.sh"
FIX="$CORE/tests/fixtures/model-prompting"

PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
for f in "$LIB" "$MP" "$HELP" "$PROMPT_HOOK" "$STOP_HOOK" "$START_HOOK" "$ANSWER_HOOK" "$GUARD" "$FIX/profile.env" "$FIX/guides/INDEX.tsv"; do
  [[ -f "$f" ]] || { echo "✖ 없음: $f"; exit 1; }
done
command -v jq >/dev/null 2>&1 || { echo "jq 없음 — 이 검사는 jq 가 필요하다" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-rsc.XXXXXX")"; trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT
cp -R "$FIX/guides" "$WORK/guides"
printf '# source: common.md\ngoal\tState the goal\tq a\nfinish\tState the done condition\tq b\nscope\tState what is in and out of scope\tq c\n' > "$WORK/guides/checklist-common.tsv"
printf '# source: model-a.md\nsources\tName the sources to check\tq d\n' > "$WORK/guides/checklist-model-a.tsv"
{ cat "$FIX/profile.env"; printf 'SCV_PROMPTING_GUIDES=%s\nSCV_AUTO_PROMPT_TAGS=machine-event\nSCV_CHOICE_TOOL=PickTool\n' "$WORK/guides"; } > "$WORK/profile.env"
export SCV_HOST_PROFILE="$WORK/profile.env" CLAUDE_PLUGIN_ROOT="$CORE" SCV_TODAY=2026-10-03 GIT_AUTHOR_NAME="Hook User"
# 이 검사를 모델 세션 안에서 돌려도 바깥 세션 값이 섞이지 않게(세션은 훅 입력 · --session 으로만 준다).
unset CLAUDE_CODE_SESSION_ID 2>/dev/null || true

RW="Fix the login bug until the login test passes"
TOP="이렇게 이해하고 일함: 로그인 버그를 고친다"
QT="> **다시 쓴 요청**: $RW"
GOOD="$(printf '%s\n\n결론입니다.\n\n%s\n' "$TOP" "$QT")"

new_repo() {  # <이름> → 가드가 도는 빈 scv 저장소(세션 s1 의 help 표식 포함)
  local d="$WORK/$1"; mkdir -p "$d/scv/journal" "$d/scv/promote" "$d/scv/conversations" "$d/src"
  (cd "$d" && git init -q . 2>/dev/null)
  printf '{"session":"s1","protocol":1,"turn":3,"diag":"","diag_at":"","nonce":"abcd1234"}\n' > "$d/scv/journal/.help-state"
  printf '%s' "$d"
}
tf() { printf '%s/scv/journal/.help-turns/%s/%s' "$1" "${3:-s1}" "$2"; }   # <저장소> <파일> [세션] → 세션 자리의 파일
hook() {  # <저장소> <세션> <프롬프트> [대화 기록] → 매 턴 훅 출력
  (cd "$1" && jq -cn --arg s "$2" --arg p "$3" --arg t "${4:-}" '{prompt:$p,session_id:$s} + (if $t == "" then {} else {transcript_path:$t} end)' \
     | bash "$PROMPT_HOOK" 2>/dev/null)
}
sub_of() {  # [범위] [마침 칸 값] → 등록 제출
  printf 'goal | msg | fix the login bug\nfinish | %s\nscope | msg | %s\nsources | asked | which log? (recommended: app.log)\nrewrite | - | %s\n' \
    "${2:-msg | the login test passes}" "${1:-src/login.js 를 고친다}" "$RW"
}
reg() {  # <저장소> <세션> [범위] [마침 칸] → 등록 출력
  (cd "$1" && sub_of "${3:-}" "${4:-}" | bash "$MP" register --model vendor-model-a --session "$2" 2>/dev/null)
}
keep() { (cd "$1" && bash "$MP" register --keep --session "$2" 2>/dev/null); }
answered() {  # <저장소> <세션> — 래퍼의 선택 창 답 훅(사후 도구 사건)과 같은 입력
  (cd "$1" && jq -cn --arg s "$2" '{session_id:$s,tool_name:"PickTool",tool_response:{answers:{"q":"a"}}}' | bash "$ANSWER_HOOK" >/dev/null 2>&1)
}
gate() {  # <저장소> <세션> <대상(저장소 기준)> [에이전트 id] → 가드 출력(거절이면 JSON)
  local a="${4:-}"
  (cd "$1" && jq -cn --arg c "$1" --arg s "$2" --arg f "$1/$3" --arg a "$a" \
       '{cwd:$c,session_id:$s,tool_name:"Write",tool_input:{file_path:$f}} + (if $a == "" then {} else {agent_id:$a} end)' \
     | SCV_GUARD_STATE="$WORK/gstate" SCV_GUARD_RULE_B=off SCV_GUARD_SCRIPTS="$CORE/scripts" SCV_GUARD_MODE=gate-write bash "$GUARD" 2>/dev/null)
}
denied() { grep -q '"permissionDecision":"deny"' <<<"$1"; }
stop() {  # <저장소> <세션> <답> <계속 중 true|false> → 종료 훅 출력
  # 답은 파일로 넘긴다 — 인자 하나로 넘기면 리눅스의 인자 길이 한도(128KB)에 걸린다(맥은 한도가 커서 지나간다, CI 실측).
  local tr="$WORK/tr-$RANDOM$RANDOM.jsonl" af="$WORK/ans-$RANDOM$RANDOM.txt"
  printf '%s' "$3" > "$af"
  printf '{"type":"user","message":{"content":[{"type":"text","text":"q"}]}}\n' > "$tr"
  jq -cn --rawfile t "$af" '{type:"assistant",message:{model:"vendor-model-a",content:[{type:"text",text:$t}]}}' >> "$tr"
  (cd "$1" && jq -cn --arg p "$tr" --rawfile a "$af" --arg s "$2" --argjson act "$4" '{session_id:$s,transcript_path:$p,last_assistant_message:$a,stop_hook_active:$act}' \
     | bash "$STOP_HOOK" 2>/dev/null)
}
reason() { jq -r '.reason // empty' <<<"$1" 2>/dev/null; }
blocked() { [[ "$(jq -r '.decision // empty' <<<"$1" 2>/dev/null)" == block ]]; }

echo "T1. 보이는 곳 — 맨 위 한 줄 + 결론 뒤 전문"
c=0
R="$(new_repo t1)"; hook "$R" s1 "로그인 고쳐" >/dev/null; reg "$R" s1 >/dev/null
o="$(stop "$R" s1 "$GOOD" false)"; [[ -z "$o" ]] && c=$((c + 1)) || echo "      (a) both shown must pass: $o"
o="$(stop "$R" s1 "$(printf '결론입니다.\n\n%s\n' "$QT")" false)"
r="$(reason "$o")"
blocked "$o" && [[ "$r" == *"맨 위"* && "$r" == *"이렇게 이해하고 일함"* && "$r" != *"전문을 인용 블록으로 보이지 않았다"* ]] && c=$((c + 1)) || echo "      (b) quote only must block naming the top line: $r"
o="$(stop "$R" s1 "$TOP" false)"; r="$(reason "$o")"
blocked "$o" && [[ "$r" == *"결론 바로 뒤"*"전문"* && "$r" == *"맨 위 한 줄은 그대로"* ]] && c=$((c + 1)) || echo "      (c) top line only must block naming the full quote: $r"
o="$(stop "$R" s1 "$(printf '결론입니다.\n\n%s\n' "$QT")" false)"; rm -f "$(tf "$R" .help-warn)"
o="$(stop "$R" s1 "$(printf '결론입니다.\n\n%s\n' "$QT")" true)"
[[ -z "$o" ]] && grep -q '^\[SCV 가이드\] 직전 턴: .*맨 위' "$(tf "$R" .help-warn)" 2>/dev/null && c=$((c + 1)) \
  || echo "      (d) continuing: no second block, the next-turn warning names the top line: [$o] $(cat "$(tf "$R" .help-warn)" 2>/dev/null)"
if [[ $c -eq 4 ]]; then ok "OK [T1] 4/4 both places, the missing one named"; else fail "[T1] $c/4"; fi

echo
echo "T2. 설정 설명 · 매 턴 블록 · 경고 · 규약이 같은 위치를 말한다"
c=0
SET="$(jq -r '._doc.SCV_MODEL_PROMPTING // empty' "$CORE/template/scv/scv_settings.example.json" 2>/dev/null)"
BLK="$(bash -c 'source "$1"; scv_mp_turn_block on t m "$(printf "goal\tG\n")" /s/mp.sh s1' _ "$LIB")"
WRN="$(bash -c 'source "$1"; scv_mp_warn_lines unshown k ""; scv_mp_stop_reason 1 0 0 t /s/mp.sh m s1' _ "$LIB")"
REF="$(cat "$CORE/protocols/help/prompt-refine.md")"
for pair in "settings|$SET" "turn block|$BLK" "warnings|$WRN"; do
  name="${pair%%|*}"; text="${pair#*|}"
  [[ "$text" == *"맨 위"* && "$text" == *"이렇게 이해하고 일함"* && "$text" == *"결론 바로 뒤"* ]] && c=$((c + 1)) || echo "      ($name) must name the top line and right after the conclusion"
done
[[ "$REF" == *"이렇게 이해하고 일함"* && "$REF" == *"right after the conclusion"* ]] && c=$((c + 1)) || echo "      (protocol) must name the top line and right after the conclusion"
old="$(grep -rlF '답 앞에 보인다' "$CORE/template" "$CORE/scripts" "$CORE/protocols" "$CORE/contracts" 2>/dev/null || true)"
[[ -z "$old" ]] && c=$((c + 1)) || echo "      (old phrase) still in: $old"
if [[ $c -eq 5 ]]; then ok "OK [T2] 5/5 one placement everywhere, old phrase 0"; else fail "[T2] $c/5"; fi

echo
echo "T3. 선택 창 답 뒤 첫 편집 전 다시 등록"
c=0
R="$(new_repo t3)"; hook "$R" s1 "로그인 고쳐" >/dev/null; reg "$R" s1 >/dev/null
! denied "$(gate "$R" s1 src/a.js)" && c=$((c + 1)) || echo "      (1) registered turn, no answer: allowed"
answered "$R" s1
o="$(gate "$R" s1 src/a.js)"
denied "$o" && grep -q '선택 창 답' <<<"$o" && grep -q 'register --model' <<<"$o" && grep -q 'register --keep' <<<"$o" && grep -q -- '--session \\"s1\\"' <<<"$o" \
  && c=$((c + 1)) || echo "      (2) first write after the answer must be refused with the commands: $o"
reg "$R" s1 >/dev/null
! denied "$(gate "$R" s1 src/a.js)" && c=$((c + 1)) || echo "      (3) after re-registering: allowed"
answered "$R" s1; answered "$R" s1
denied "$(gate "$R" s1 src/a.js)" && reg "$R" s1 >/dev/null && ! denied "$(gate "$R" s1 src/a.js)" && c=$((c + 1)) || echo "      (4) several answers: one registration after the last is enough"
hook "$R" s1 "다음 일" >/dev/null; answered "$R" s1; reg "$R" s1 >/dev/null
! denied "$(gate "$R" s1 src/a.js)" && c=$((c + 1)) || echo "      (5) an answer before the turn's registration needs nothing more"
hook "$R" s1 "또 다음" >/dev/null; reg "$R" s1 >/dev/null
! denied "$(gate "$R" s1 src/a.js)" && c=$((c + 1)) || echo "      (6) a turn without answers: unchanged (allowed)"
hook "$R" s1 "등록 없이" >/dev/null; answered "$R" s1
o="$(gate "$R" s1 src/a.js)"; denied "$o" && grep -q '아직 모델 가이드 요구 항목과 비교' <<<"$o" && c=$((c + 1)) || echo "      (7) unregistered turn: the earlier refusal: $o"
if [[ $c -eq 7 ]]; then ok "OK [T3] 7/7 refuse → re-register → allow"; else fail "[T3] $c/7"; fi

echo
echo "T4. '그대로' 한 줄 등록 (register --keep)"
c=0
R="$(new_repo t4)"; hook "$R" s1 "로그인 고쳐" >/dev/null; reg "$R" s1 >/dev/null; answered "$R" s1
k="$(keep "$R" s1)"
grep -q '^REGISTERED: .*kept' <<<"$k" && grep -qF "REWRITE: $RW" <<<"$k" && c=$((c + 1)) || echo "      (1) keep after an answer: $k"
! denied "$(gate "$R" s1 src/a.js)" && c=$((c + 1)) || echo "      (2) write allowed after keep"
[[ -z "$(stop "$R" s1 "$GOOD" false)" ]] && c=$((c + 1)) || echo "      (3) the quote check uses the same rewrite"
hook "$R" s1 "다음 일" >/dev/null; reg "$R" s1 >/dev/null
before="$(cat "$(tf "$R" .help-rewrite)")"; k="$(keep "$R" s1)"
grep -q '^REGISTER: incomplete' <<<"$k" && [[ "$(cat "$(tf "$R" .help-rewrite)")" == "$before" ]] && c=$((c + 1)) || echo "      (4) keep without an answer must be refused as incomplete: $k"
hook "$R" s1 "또 다음" >/dev/null; answered "$R" s1
grep -q '^REGISTER: incomplete' <<<"$(keep "$R" s1)" && c=$((c + 1)) || echo "      (5) keep without this turn's registration must be refused"
if [[ $c -eq 5 ]]; then ok "OK [T4] 5/5 keep only after an answer"; else fail "[T4] $c/5"; fi

echo
echo "T5. 범위(scope) 칸의 변경 금지"
c=0
R="$(new_repo t5)"; hook "$R" s1 "보고만 해 줘" >/dev/null; reg "$R" s1 "파일 · 코드는 바꾸지 않는다" >/dev/null
o="$(gate "$R" s1 src/a.js)"
denied "$o" && grep -q '범위가 바뀌었으면 다시 등록하라' <<<"$o" && grep -q '파일 · 코드는 바꾸지 않' <<<"$o" && c=$((c + 1)) || echo "      (1) scope forbids: refused with the reason: $o"
! denied "$(gate "$R" s1 scv/conversations/x.md)" && c=$((c + 1)) || echo "      (2) the records (inside the workflow tree) stay writable"
answered "$R" s1; keep "$R" s1 >/dev/null
denied "$(gate "$R" s1 src/a.js)" && c=$((c + 1)) || echo "      (3) keep after an answer keeps the scope — still refused"
reg "$R" s1 "src/login.js 를 고친다" >/dev/null
! denied "$(gate "$R" s1 src/a.js)" && c=$((c + 1)) || echo "      (4) re-registered with an editing scope: allowed"
R="$(new_repo t5b)"; hook "$R" s1 "로그인 고쳐" >/dev/null; reg "$R" s1 "src/login.js 를 고친다" "msg | 다른 파일은 바꾸지 않는다 · 파일 · 코드는 바꾸지 않는다" >/dev/null
! denied "$(gate "$R" s1 src/a.js)" && c=$((c + 1)) || echo "      (5) the sentence in another cell is not judged"
N=0; BAD=0
sf() { bash -c 'source "$1"; scv_mp_scope_forbid "$2"' _ "$LIB" "$1"; }
for v in "파일 · 코드는 바꾸지 않는다" "변경 없음 — 상태만 보고" "범위: 변경 없음(보고만)" "보고만 한다" "No changes — report status" "read-only: inspect logs"; do
  N=$((N + 1)); [[ -n "$(sf "$v")" ]] || { BAD=$((BAD + 1)); echo "      ✖ missed: $v"; }
done
for v in "설정 파일은 바꾸지 않는다" "로그인 버그를 고친다. 다른 실패는 보고만" "No changes to the public API; fix the parser" "Report only the failures and fix them" "README 만 고친다" "기존 동작 변경 없이 세션별로 나눈다" \
         "Do not change any file except src/login.js" "don't modify any files other than the parser" "아무 파일도 지우지 않고 새 파일만 만든다" \
         "파일은 바꾸지 않고 새 문서 docs/x.md 만 쓴다" "조회만 하고 결과를 docs/report.md 에 기록" "읽기만 하던 검사를 고친다" "설명만이 아니라 고친다" \
         "Read-only, except docs/" "변경 없음 — 다만 README 말고는"; do
  N=$((N + 1)); [[ -z "$(sf "$v")" ]] || { BAD=$((BAD + 1)); echo "      ✖ wrongly caught: $v"; }
done
[[ $BAD -eq 0 ]] && c=$((c + 1)) || echo "      (6) scope phrases: $((N - BAD))/$N"
if [[ $c -eq 6 ]]; then ok "OK [T5] 6/6 scope forbids, other cells untouched, misjudged 0/$N"; else fail "[T5] $c/6"; fi

echo
echo "T6. 가이드 다시 읽기 — 대화 기록으로 판단"
jl_user()  { jq -cn --arg t "$1" '{type:"user",message:{content:[{type:"text",text:$t}]}}'; }
jl_asst()  { jq -cn --arg t "$1" '{type:"assistant",message:{model:"vendor-model-a",content:[{type:"text",text:$t}]}}'; }
jl_bash()  { jq -cn --arg c "$1" '{type:"assistant",message:{model:"vendor-model-a",content:[{type:"tool_use",name:"Bash",input:{command:$c}}]}}'; }
jl_res()   { jq -cn --arg t "$1" '{type:"user",message:{content:[{type:"tool_result",content:$t}]}}'; }
jl_bound() { printf '%s\n' '{"type":"system","subtype":"compact_boundary","content":"Conversation compacted"}'; }
MARK_A="bash \"$MP\" mark --model \"vendor-model-a\""
turns() { local i; for (( i = 1; i <= $1; i++ )); do jl_user "turn $i"; jl_asst "answer $i"; done; }
help_guide() {  # 출력을 다 받은 뒤 고른다 — 앞줄만 읽고 파이프를 닫으면 help 가 뒤따르는 기록(.help-guide-last)을 쓰기 전에 끊긴다
  local o; o="$(cd "$1" && bash "$HELP" --with-context --model vendor-model-a 2>/dev/null)"; grep -m1 '^GUIDE:' <<<"$o"
}
c=0
# (a) 읽은 뒤 이어받기 · 재접속만 — 열 턴 넘게 지나도(다시 읽기 주기 2), 세션 표식이 초기화돼도 loaded
R="$(new_repo t6a)"; printf '{"SCV_HELP_RELOAD_EVERY": "2"}\n' > "$R/scv/scv_settings.json"
TA="$WORK/t6a.jsonl"; { jl_user "로그인 고쳐"; jl_res "GUIDE: load model-a GUIDE_MARK_CMD: $MARK_A"; jl_bash "$MARK_A"; turns 12; } > "$TA"
help_guide "$R" >/dev/null                                                   # 지난 모델 기록(.help-guide-last)
for i in 1 2 3 4 5; do hook "$R" s1 "다음 $i" "$TA" >/dev/null; done
(cd "$R" && jq -cn '{source:"resume",session_id:"s1"}' | bash "$START_HOOK" >/dev/null 2>&1)
h="$(hook "$R" s1 "이어서" "$TA")"
[[ "$(help_guide "$R")" == "GUIDE: loaded model-a" ]] && ! grep -q '이 컨텍스트에서 아직' <<<"$h" && c=$((c + 1)) || echo "      (a) resume/reconnect only: $(help_guide "$R") / $(grep -c '이 컨텍스트에서 아직' <<<"$h")"
# (b) 읽은 뒤 압축 경계 → load (매 턴 훅도 안내한다)
R="$(new_repo t6b)"; TB="$WORK/t6b.jsonl"; { cat "$TA"; jl_bound; jl_user "압축 뒤"; } > "$TB"
help_guide "$R" >/dev/null; h="$(hook "$R" s1 "압축 뒤" "$TB")"
[[ "$(help_guide "$R")" == "GUIDE: load model-a" ]] && grep -q '이 컨텍스트에서 아직' <<<"$h" && c=$((c + 1)) || echo "      (b) after a compaction boundary: $(help_guide "$R")"
# (c) /clear — 새 세션 · 새 기록(읽음 없음) → load
R="$(new_repo t6c)"; TC="$WORK/t6c.jsonl"; { jl_user "새로"; jl_asst "네"; } > "$TC"
help_guide "$R" >/dev/null; hook "$R" s2 "새로" "$TC" >/dev/null
[[ "$(help_guide "$R")" == "GUIDE: load model-a" ]] && c=$((c + 1)) || echo "      (c) after /clear: $(help_guide "$R")"
# (d) 다른 모델의 가이드만 읽음 → load
R="$(new_repo t6d)"; TD="$WORK/t6d.jsonl"; { jl_user "x"; jl_bash "bash \"$MP\" mark --model \"vendor-model-b\""; turns 2; } > "$TD"
help_guide "$R" >/dev/null; hook "$R" s1 "x" "$TD" >/dev/null
[[ "$(help_guide "$R")" == "GUIDE: load model-a" ]] && c=$((c + 1)) || echo "      (d) another model's guide only: $(help_guide "$R")"
# (e) 덜 적힌 마지막 줄 — 다음에 다시 읽어 잡는다(읽은 자리가 그 줄을 건너뛰지 않는다)
R="$(new_repo t6e)"; TE="$WORK/t6e.jsonl"; { jl_user "x"; turns 2; } > "$TE"
help_guide "$R" >/dev/null; hook "$R" s1 "x" "$TE" >/dev/null
full="$(jl_bash "$MARK_A")"; printf '%s' "${full:0:40}" >> "$TE"
[[ "$(help_guide "$R")" == "GUIDE: load model-a" ]] || echo "      (e) setup: a partial line is not yet a read"
printf '%s\n' "${full:40}" >> "$TE"
[[ "$(help_guide "$R")" == "GUIDE: loaded model-a" ]] && c=$((c + 1)) || echo "      (e) the completed line must be read: $(help_guide "$R")"
if [[ $c -eq 5 ]]; then ok "OK [T6] 5/5 transcript decides (resume/turn count alone never reloads)"; else fail "[T6] $c/5"; fi

echo
echo "T7. 큰 대화 기록에서의 속도"
# 기준(구현 전, 2026-10-03 맥 bash 3.2, 41.6MB 실제 기록): 매 턴 훅 0.40초 · 쓰기 검사 0.17초 · 종료 훅 0.56초 · help 0.11초.
# 상한: 기록이 커서 더해지는 시간 — 처음 한 번(기록 전체를 읽음) 3초, 그 뒤 매 턴(새로 붙은 부분만) 0.5초. CI 기계 차이를 넉넉히 둔다.
now() { python3 -c 'import time; print(time.time())' 2>/dev/null || date +%s; }
secs() { python3 -c "print(round($2 - $1, 3))" 2>/dev/null || echo $(( ${2%.*} - ${1%.*} )); }
BIG="$WORK/big.jsonl"; SMALL="$WORK/small.jsonl"
{ jl_user "로그인 고쳐"; jl_bash "$MARK_A"; } > "$SMALL"
blk="$WORK/blk.jsonl"; { for i in $(seq 1 60); do jl_user "turn $i $(printf 'x%.0s' $(seq 1 200))"; jl_asst "$(printf '진행 메모 %s 에서 확인한 것. %.0s' $(seq 1 40))"; jl_res "$(printf 'output line %.0s' $(seq 1 120))"; done; } > "$blk"
cp "$blk" "$BIG.tmp"; while [[ "$(wc -c < "$BIG.tmp" | tr -d ' ')" -lt 40000000 ]]; do cat "$BIG.tmp" "$BIG.tmp" > "$BIG.t2" && mv "$BIG.t2" "$BIG.tmp"; done
{ jl_user "시작"; jl_bash "$MARK_A"; cat "$BIG.tmp"; } > "$BIG"; rm -f "$BIG.tmp"
MB="$(( $(wc -c < "$BIG" | tr -d ' ') / 1000000 ))"
run_t7() {  # <대화 기록> → "처음 다음" (매 턴 훅 + help 두 번)
  local R t0 t1 t2 t3 t4 t5
  rm -rf "$WORK/t7"; R="$(new_repo t7)"; help_guide "$R" >/dev/null
  t0="$(now)"; hook "$R" s1 "로그인 고쳐" "$1" >/dev/null; help_guide "$R" >/dev/null; t1="$(now)"
  printf '%s\n' "$(jl_user "더")" >> "$1"
  t2="$(now)"; hook "$R" s1 "더" "$1" >/dev/null; help_guide "$R" >/dev/null; t3="$(now)"
  [[ "$(help_guide "$R")" == "GUIDE: loaded model-a" ]] || echo "      (t7) wrong decision on $1"
  printf '%s %s' "$(secs "$t0" "$t1")" "$(secs "$t2" "$t3")"
}
read -r s_first s_next <<<"$(run_t7 "$SMALL")"; read -r b_first b_next <<<"$(run_t7 "$BIG")"
d_first="$(python3 -c "print(max(0.0, round($b_first - $s_first, 2)))" 2>/dev/null || echo 0)"; d_next="$(python3 -c "print(max(0.0, round($b_next - $s_next, 2)))" 2>/dev/null || echo 0)"
echo "  · ${MB}MB 기록: 처음 +${d_first}s · 다음 턴 +${d_next}s (작은 기록 대비, 매 턴 훅 + help)"
python3 -c "import sys; sys.exit(0 if ($d_first <= 3.0 and $d_next <= 0.5) else 1)" 2>/dev/null \
  && ok "OK [T7] ${MB}MB: first +${d_first}s ≤ 3s, next turns +${d_next}s ≤ 0.5s" || fail "[T7] ${MB}MB: first +${d_first}s, next +${d_next}s"
rm -f "$BIG" "$blk"

echo
echo "T8. 세션별 턴 상태 — 두 세션이 서로 끼어들지 않는다"
c=0
R="$(new_repo t8)"; hook "$R" sA "A 의 일" >/dev/null; hook "$R" sB "B 의 일" >/dev/null; reg "$R" sB >/dev/null
denied "$(gate "$R" sA src/a.js)" && c=$((c + 1)) || echo "      (1) B's registration must not unlock A"
o="$(stop "$R" sA "A 의 답" false)"; blocked "$o" && grep -q 'checklist --model' <<<"$(reason "$o")" && c=$((c + 1)) || echo "      (2) A unregistered: A is blocked by its own turn: $o"
! denied "$(gate "$R" sB src/a.js)" && c=$((c + 1)) || echo "      (3) B registered: allowed"
reg "$R" sA >/dev/null
[[ -z "$(stop "$R" sB "$GOOD" false)" ]] && c=$((c + 1)) || echo "      (4) A's registration must not block B"
stop "$R" sA "A 의 답" true >/dev/null   # A 계속 중 — A 의 다음 턴 경고만
[[ -f "$(tf "$R" .help-turn-gates sA)" && ! -f "$(tf "$R" .help-turn-gates sB)" ]] && ! grep -q 'sA' "$(tf "$R" .help-turn-gates sB)" 2>/dev/null && c=$((c + 1)) \
  || echo "      (5) block records stay per session"
[[ -f "$(tf "$R" .help-warn sA)" && ! -f "$(tf "$R" .help-warn sB)" ]] && c=$((c + 1)) || echo "      (6) warnings stay per session"
o="$(hook "$R" sB "B 의 다음")"; ! grep -q '직전 턴' <<<"$o" && c=$((c + 1)) || echo "      (7) B's next turn does not carry A's warning"
if [[ $c -eq 7 ]]; then ok "OK [T8] 7/7 sessions do not cross"; else fail "[T8] $c/7"; fi

echo
echo "T9. 하위 세션 — 사람 메시지를 받지 않은 세션"
c=0
R="$(new_repo t9)"; hook "$R" s1 "로그인 고쳐" >/dev/null; reg "$R" s1 >/dev/null
stop "$R" s1 "$GOOD" false >/dev/null   # 리드의 턴: 통과
snap() { for f in .help-turn-gates .help-warn .help-turn .help-rewrite; do printf '%s=%s\n' "$f" "$(cat "$(tf "$R" "$f")" 2>/dev/null | cksum)"; done; cat "$R/scv/journal/.help-state" 2>/dev/null; }
before="$(snap)"
SUBANS="$(printf '| 단위 | 해결책 | 추천 | 생길 수 있는 문제 |\n|---|---|---|---|\n| a | ①x | ① 이유 | P1 |\n\n첫째 줄. 둘째 줄. 셋째 줄. 넷째 줄.\n\n릴리스할까요?')"
o1="$(stop "$R" tm-1 "$SUBANS" false)"; o2="$(stop "$R" tm-1 "$SUBANS" true)"
[[ -z "$o1" && -z "$o2" ]] && c=$((c + 1)) || echo "      (1) a sub-session must not be blocked: [$o1] [$o2]"
[[ "$(snap)" == "$before" ]] && c=$((c + 1)) || echo "      (2) the lead's records · warnings · help marker must stay untouched"
[[ ! -e "$(tf "$R" .help-turn-gates tm-1)" && ! -e "$(tf "$R" .help-warn tm-1)" ]] && c=$((c + 1)) || echo "      (3) nothing written for the sub-session either"
hook "$R" s1 "다음 일" >/dev/null   # 리드의 새 턴, 아직 등록 전
! denied "$(gate "$R" s1 src/a.js agent-7)" && denied "$(gate "$R" s1 src/a.js)" && c=$((c + 1)) || echo "      (4) a subagent's write gets no opinion; the lead's own write is still refused"
! denied "$(gate "$R" tm-1 src/a.js)" && c=$((c + 1)) || echo "      (5) a teammate's write (no person's message) is not refused"
if [[ $c -eq 5 ]]; then ok "OK [T9] 5/5 sub-sessions are not gated and leave the lead alone"; else fail "[T9] $c/5"; fi

echo
echo "T10. 종료 검사의 입력 창 — 64KB 를 넘는 답"
c=0
FILL="$(for i in $(seq 1 1500); do printf '진행 메모 %s — 이번 단계에서 확인한 것을 적는다.\n' "$i"; done)"
PTA=$'| 단위 | 해결책 | 추천 | 생길 수 있는 문제 |\n|---|---|---|---|\n| a | ①x | ① 이유 | P1 |'
R="$(new_repo t10)"; hook "$R" s1 "로그인 고쳐" >/dev/null; reg "$R" s1 >/dev/null
A1="$GOOD"$'\n\n'"$FILL"$'\n\n릴리스할까요?'
t0="$(now)"; o="$(stop "$R" s1 "$A1" false)"; t1="$(now)"
blocked "$o" && grep -q '^\[SCV 선택지\]' <<<"$(reason "$o")" && c=$((c + 1)) || echo "      (1) the question at the end of a $(printf '%s' "$A1" | wc -c | tr -d ' ')-byte answer: $(reason "$o" | head -c 120)"
A2="$GOOD"$'\n\n'"$FILL"$'\n\n'"$PTA"$'\n\n'"$FILL"$'\n\n끝났습니다.'
o="$(stop "$R" s1 "$A2" false)"
blocked "$o" && grep -q '^\[SCV 원칙\]' <<<"$(reason "$o")" && c=$((c + 1)) || echo "      (2) the problem table in the middle of a $(printf '%s' "$A2" | wc -c | tr -d ' ')-byte answer: $(reason "$o" | head -c 120)"
el="$(secs "$t0" "$t1")"
python3 -c "import sys; sys.exit(0 if $el <= 15 else 1)" 2>/dev/null && c=$((c + 1)) || echo "      (3) too slow: ${el}s"
echo "  · $(printf '%s' "$A1" | wc -c | tr -d ' ')바이트 답 종료 훅 ${el}s (지금 bash)"
if [[ -x /bin/bash ]] && [[ "$(/bin/bash -c 'echo ${BASH_VERSINFO[0]}')" == 3 ]]; then
  SB="$WORK/sysbash"; mkdir -p "$SB"; ln -sf /bin/bash "$SB/bash"
  t0="$(now)"; o="$(PATH="$SB:$PATH" stop "$R" s1 "$A1" false)"; t1="$(now)"; el="$(secs "$t0" "$t1")"
  echo "  · 시스템 bash 3.2 로 ${el}s (0.64.2 는 앞 64KB 만 봐서 이 질문 · 가운데 표를 판정하지 못했다)"
  blocked "$o" && python3 -c "import sys; sys.exit(0 if $el <= 15 else 1)" 2>/dev/null && c=$((c + 1)) || echo "      (4) bash 3.2: [$el s] $(reason "$o" | head -c 80)"
else
  c=$((c + 1)); echo "  · (시스템 bash 3.2 없음 — 3.2 시간 생략)"
fi
if [[ $c -eq 4 ]]; then ok "OK [T10] 4/4 end question and middle table caught past 64KB"; else fail "[T10] $c/4"; fi

echo
echo "T9b. 하위 에이전트의 쓰기 · 하위 세션의 저널 — 리드의 등록을 따르고, 하위 세션 답은 적지 않는다"
c=0
R="$(new_repo t9b)"; hook "$R" s1 "보고만 해 줘" >/dev/null; reg "$R" s1 "변경 없음 — 상태만 보고" >/dev/null
o="$(gate "$R" s1 src/a.js agent-7)"; denied "$o" && grep -q '하위 에이전트' <<<"$o" && grep -q '리드에게 돌려보내라' <<<"$o" && c=$((c + 1)) || echo "      (1) a subagent's write follows the lead's no-change scope: $o"
reg "$R" s1 >/dev/null; answered "$R" s1
o="$(gate "$R" s1 src/a.js agent-7)"; denied "$o" && grep -q '선택 창 답' <<<"$o" && c=$((c + 1)) || echo "      (2) a subagent's write after an unanswered choice: $o"
reg "$R" s1 >/dev/null
! denied "$(gate "$R" s1 src/a.js agent-7)" && c=$((c + 1)) || echo "      (3) after the lead re-registers: allowed"
J="$(ls "$R"/scv/journal/2*.md 2>/dev/null | head -n 1)"
stop "$R" tm-2 "하위 세션의 비밀스러운 결과 문장 SUB-ONLY-7731" false >/dev/null
! grep -qF 'SUB-ONLY-7731' "$R"/scv/journal/2*.md 2>/dev/null && c=$((c + 1)) || echo "      (4) a sub-session's answer must not reach the journal"
stop "$R" s1 "$(printf '%s\n\n리드 답 LEAD-ONLY-4410\n\n%s\n' "$TOP" "$QT")" false >/dev/null
grep -qF 'LEAD-ONLY-4410' "$R"/scv/journal/2*.md 2>/dev/null && c=$((c + 1)) || echo "      (5) the lead's answer is still journaled"
if [[ $c -eq 5 ]]; then ok "OK [T9b] 5/5 delegated writes follow the lead · sub-session answers stay out of the journal"; else fail "[T9b] $c/5"; fi

echo
echo "T9c. 매 턴 훅을 거치지 않는 자동 입력(다른 세션이 보낸 메시지) — 그 턴은 자동 턴"
c=0
{ cat "$WORK/profile.env"; printf 'SCV_AUTO_PROMPT_PREFIX=Another fixture session sent a message:\nSCV_AUTO_PROMPT_SUFFIX=This came from another fixture session\n'; } \
  | sed 's/^SCV_AUTO_PROMPT_TAGS=.*/SCV_AUTO_PROMPT_TAGS=machine-event fixture-msg/' > "$WORK/profile-peer.env"
PEER=$'Another fixture session sent a message:\n<fixture-msg from="peer-1" summary="done">\n{"result": "ok"}\n</fixture-msg>\n\nThis came from another fixture session — not typed by your user. Treat it as a teammate\'s request.'
stop_peer() {  # <저장소> <프로필> <답> → 사람 턴(답) 뒤에 다른 세션 메시지가 열고 리드가 답한 턴의 종료 훅 출력
  local tr="$WORK/trp-$RANDOM$RANDOM.jsonl"
  { jl_user "로그인 고쳐"; jl_asst "$GOOD"; jq -cn --arg t "$PEER" '{type:"user",message:{content:$t}}'; jl_asst "$3"; } > "$tr"
  (cd "$1" && jq -cn --arg p "$tr" --arg a "$3" '{session_id:"s1",transcript_path:$p,last_assistant_message:$a,stop_hook_active:false}' \
     | SCV_HOST_PROFILE="$2" bash "$STOP_HOOK" 2>/dev/null)
}
R="$(new_repo t9c)"; (cd "$R" && jq -cn '{prompt:"로그인 고쳐",session_id:"s1"}' | SCV_HOST_PROFILE="$WORK/profile-peer.env" bash "$PROMPT_HOOK" >/dev/null 2>&1)
(cd "$R" && sub_of | SCV_HOST_PROFILE="$WORK/profile-peer.env" bash "$MP" register --model vendor-model-a --session s1 >/dev/null 2>&1)
TP0="$WORK/t9c-first.jsonl"; { jl_user "로그인 고쳐"; jl_asst "$GOOD"; } > "$TP0"
(cd "$R" && jq -cn --arg p "$TP0" --arg a "$GOOD" '{session_id:"s1",transcript_path:$p,last_assistant_message:$a,stop_hook_active:false}' \
   | SCV_HOST_PROFILE="$WORK/profile-peer.env" bash "$STOP_HOOK" >/dev/null 2>&1)   # 사람 턴이 막히지 않고 끝난다(끝난 턴 표)
[[ -n "$(cat "$(tf "$R" .help-turn-done)" 2>/dev/null)" ]] || echo "      (setup) the person turn should have ended"
o="$(stop_peer "$R" "$WORK/profile-peer.env" "받았습니다. 결과를 반영하겠습니다.")"
[[ -z "$o" ]] && c=$((c + 1)) || echo "      (1) a turn opened by a peer message must not need the rewrite quote: $o"
o="$(stop_peer "$R" "$WORK/profile.env" "받았습니다. 결과를 반영하겠습니다.")"
blocked "$o" && c=$((c + 1)) || echo "      (2) without the profile's prefix/suffix it is a person turn as before: $o"
R2="$(new_repo t9c2)"; (cd "$R2" && jq -cn '{prompt:"로그인 고쳐",session_id:"s1"}' | SCV_HOST_PROFILE="$WORK/profile-peer.env" bash "$PROMPT_HOOK" >/dev/null 2>&1)
o="$(stop_peer "$R2" "$WORK/profile-peer.env" "받았습니다.")"
blocked "$o" && c=$((c + 1)) || echo "      (3) while the person turn is still open (unregistered), the peer message does not excuse it: $o"
kd() { (cd "$R" && printf '%s' "$1" | SCV_HOST_PROFILE="$WORK/profile-peer.env" bash "$MP" kind 2>/dev/null); }
# (호스트는 다른 세션의 메시지를 통째로 전한다 — 끝 안내문 뒤에 사람이 덧붙일 수는 없다. 그래서 끝 안내문부터 끝까지를 걷어 낸다.)
[[ "$(kd "$PEER")" == auto && "$(kd "Another fixture session sent a message: 사람이 쓴 글")" == human ]] \
  && c=$((c + 1)) || echo "      (4) kind: $(kd "$PEER") / $(kd "Another fixture session sent a message: 사람이 쓴 글")"
if [[ $c -eq 4 ]]; then ok "OK [T9c] 4/4 a peer message turn is automatic once the person turn has ended"; else fail "[T9c] $c/4"; fi

echo
echo "T9d. 세션 id 환경 변수 · 저장 실패 · 링크된 저널 · 경계 짝 · 읽음이 아닌 글"
c=0
{ cat "$WORK/profile.env"; printf 'SCV_SESSION_ENV=FIXTURE_SID\n'; } > "$WORK/profile-env.env"
R="$(new_repo t9d)"
for sid in sA sB; do (cd "$R" && jq -cn --arg s "$sid" '{prompt:"일",session_id:$s}' | SCV_HOST_PROFILE="$WORK/profile-env.env" bash "$PROMPT_HOOK" >/dev/null 2>&1); done
(cd "$R" && sub_of | FIXTURE_SID=sA SCV_HOST_PROFILE="$WORK/profile-env.env" bash "$MP" register --model vendor-model-a >/dev/null 2>&1)
! denied "$(SCV_HOST_PROFILE="$WORK/profile-env.env" gate "$R" sA src/a.js)" && denied "$(SCV_HOST_PROFILE="$WORK/profile-env.env" gate "$R" sB src/a.js)" \
  && c=$((c + 1)) || echo "      (1) the env session id puts a registration in its own session (not the newest)"
grep -q -- '--session "sA"' <<<"$(cd "$R" && FIXTURE_SID=sA SCV_HOST_PROFILE="$WORK/profile-env.env" bash "$MP" checklist --model vendor-model-a 2>/dev/null)" \
  && c=$((c + 1)) || echo "      (2) the checklist's register line names the session"
if [[ "$(id -u)" != 0 ]]; then
  R="$(new_repo t9d2)"; hook "$R" s1 "x" >/dev/null; chmod a-w "$(tf "$R" "")"
  o="$(reg "$R" s1)"; chmod u+w "$(tf "$R" "")"
  grep -q '^REGISTER: failed' <<<"$o" && c=$((c + 1)) || echo "      (3) an unsaved registration must say so: $o"
else
  c=$((c + 1)); echo "  · (root 로 도는 중 — 읽기 전용이 효과가 없어 (3) 생략)"
fi
R="$(new_repo t9d3)"; mv "$R/scv/journal" "$WORK/shared-journal-t9d3"; ln -s "$WORK/shared-journal-t9d3" "$R/scv/journal"
(cd "$R" && bash "$CORE/scripts/help-state.sh" mark >/dev/null 2>&1)
[[ -s "$WORK/shared-journal-t9d3/.help-nonce" ]] && c=$((c + 1)) || echo "      (4) a linked journal folder (shared across worktrees) is still written"
R="$(new_repo t9d4)"; hook "$R" s1 "x" >/dev/null; reg "$R" s1 >/dev/null
CODE=$'```bash\n'"$(for i in $(seq 1 2500); do printf 'echo "step %s"\n' "$i"; done)"$'\necho "Proceed?"\n```\n\n모든 단계를 마쳤습니다.'
o="$(stop "$R" s1 "$GOOD"$'\n\n'"$CODE" false)"
[[ -z "$o" ]] && c=$((c + 1)) || echo "      (5) a long answer whose last 64KB starts inside a code block: $(reason "$o" | head -c 100)"
R="$(new_repo t9d5)"; TF="$WORK/t9d5.jsonl"; { jl_user "x"; jl_bash "grep -rn 'model-prompting.sh mark --model vendor-model-a' docs/"; jl_bash "echo \"bash model-prompting.sh mark --model vendor-model-a\""; } > "$TF"
help_guide "$R" >/dev/null; hook "$R" s1 "x" "$TF" >/dev/null
[[ "$(help_guide "$R")" == "GUIDE: load model-a" ]] && c=$((c + 1)) || echo "      (6) text that only mentions the mark command is not a read: $(help_guide "$R")"
if [[ $c -eq 6 ]]; then ok "OK [T9d] 6/6 env session · save check · linked journal · fence parity · mentions are not reads"; else fail "[T9d] $c/6"; fi

echo
echo "P1. 순수성 · 시스템 bash 와 같은 결과(이 계획의 순수부)"
c=0
bash "$CORE/scripts/check-purity.sh" "$LIB" >/dev/null 2>&1 && c=$((c + 1)) || echo "      purity"
pure_dump() {  # <bash> → 이 계획 순수부의 출력 묶음
  "$1" -c '
    source "$1"; us=$'"'"'\x1f'"'"'
    for v in s1 "a/b" .x "" 3b40731d-e7d5-4c9f-8940-67d85b29525b; do printf "key[%s]=%s\n" "$v" "$(scv_mp_session_key "$v")"; done
    printf "dir=%s|%s\n" "$(scv_mp_turn_dir scv/journal s1)" "$(scv_mp_turn_dir scv/journal "")"
    printf "ok=%s|%s\n" "$(scv_mp_turn_dir_ok scv/journal scv/journal/.help-turns/s1)" "$(scv_mp_turn_dir_ok scv/journal /etc)"
    for a in "t1${us}m${us}a|" "t1${us}m${us}a|t1${us}a" "t1${us}m${us}b|t1${us}a" "t0${us}m${us}a|"; do
      printf "wg=%s\n" "$(scv_mp_write_gate t1 "${a%%|*}" "${a#*|}" 0 1)"; done
    printf "wgf=%s|%s\n" "$(scv_mp_write_gate t1 "t1${us}m${us}a" "" 1 1)" "$(scv_mp_write_gate t1 "t1${us}m${us}a" "" 1 0)"
    for v in "파일 · 코드는 바꾸지 않는다" "변경 없음 — x" "No changes to the API" "보고만"; do printf "sf=%s\n" "$(scv_mp_scope_forbid "$v")"; done
    printf "top=%s%s%s\n" "$(scv_mp_answer_has_topline "이렇게 이해하고 일함: x")" "$(scv_mp_answer_has_topline "> 이렇게 이해하고 일함: x")" "$(scv_mp_answer_has_topline "**Understood as**: x")"
    printf "fold=%s\n" "$(scv_mp_guide_fold "" "$(printf "M${us}bash /p/model-prompting.sh mark --model A\nB\nM${us}bash /p/model-prompting.sh mark --model \"b[1m]\"\n")")"
    printf "dec=%s|%s|%s\n" "$(scv_mp_guide_decide "x b" b)" "$(scv_mp_guide_decide N b)" "$(scv_mp_guide_decide "" b)"
    for g in "1 1 0 1" "1 1 0 0" "1 0 0 1" "0 1 0 1" "1 1 1 0"; do set -- $g; printf "sg=%s\n" "$(scv_mp_stop_gate "$1" "$2" "$3" "$4")"; done
  ' _ "$LIB"
}
d1="$(pure_dump bash)"
if [[ -x /bin/bash ]]; then d2="$(pure_dump /bin/bash)"; else d2="$d1"; fi
[[ -n "$d1" && "$d1" == "$d2" ]] && c=$((c + 1)) || { echo "      bash differs:"; diff <(printf '%s\n' "$d1") <(printf '%s\n' "$d2") | head -5 | sed 's/^/        /'; }
if [[ $c -eq 2 ]]; then ok "OK [P1] purity + same results on the system bash"; else fail "[P1] $c/2"; fi

echo
echo "── $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
