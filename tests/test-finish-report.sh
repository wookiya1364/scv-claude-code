#!/usr/bin/env bash
# test-finish-report.sh — 끝 보고 확인 범위 · 근거 목록(계획 20261105-wookiya1364-finish-report-evidence T1–T17).
#
# 매 턴 안내 · 세 줄 없으면 한 번 막기 · 짧은 턴 한 줄 · 도구 없는 턴 · '없음'의 이유 · 근거 없는 확인 · 근거 목록 판정 · 실패 먼저 ·
# 묶어 막기 · 끄기 · 영어 · 실제 기록 재현(사본이 있을 때만) · 속도 · 근거 목록 파일 · 다른 모양 원본.
set -euo pipefail
export SCV_STOP_MODE=block   # 0.83.0+ — 이 시험은 막힘(block)을 본다. 기본(notice)은 test-stop-notice.sh

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROMPT_HOOK="$CORE/template/hooks/on-user-prompt.sh"; STOP_HOOK="$CORE/template/hooks/on-stop.sh"
# shellcheck source=../scripts/lib/finish-report.sh
source "$CORE/scripts/lib/finish-report.sh"
fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }
TAG_KO="[SCV 확인 범위]"; TAG_EN="[SCV verification scope]"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-finish.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT

new_repo() {  # <이름> <언어> [끄기 on|off] → 저장소 경로. 등록 · 원칙 · 실체 보여 주기 검사는 꺼서 이 검사만 남긴다.
  local r="$WORK/$1"; mkdir -p "$r/scv/journal"
  jq -n --arg l "$2" --arg f "${3:-on}" '{SCV_LANG:$l, SCV_MODEL_PROMPTING:"off", SCV_REWRITE_PRINCIPLE:"off", SCV_SHOW_REAL:"off", SCV_FINISH_REPORT:$f}' > "$r/scv/scv_settings.json"
  printf '%s' "$r"
}
jl_user() { jq -cn --arg t "$1" '{type:"user",message:{content:$t}}'; }
jl_asst() { jq -cn --arg t "$1" --arg u "$2" '{type:"assistant",uuid:$u,message:{content:[{type:"text",text:$t}]}}'; }
jl_call() {  # <id> <입력 JSON>
  jq -cn --arg id "$1" --argjson i "$2" '{type:"assistant",uuid:("u-"+$id),message:{content:[{type:"tool_use",id:$id,name:"T",input:$i}]}}'
}
jl_res() {  # <id> <결과 글> [실패 true|false]
  jq -cn --arg id "$1" --arg t "$2" --argjson e "${3:-false}" '{type:"user",sourceToolUseID:$id,message:{content:[{type:"tool_result",tool_use_id:$id,content:$t,is_error:$e}]}}'
}
stop_hook() {  # <저장소> <원본> <마지막 답> <계속 중 true|false> [코어 루트] → 종료 훅 stdout
  (cd "$1" && jq -cn --arg p "$2" --arg a "$3" --argjson s "$4" '{transcript_path:$p,last_assistant_message:$a,stop_hook_active:$s}' \
     | CLAUDE_PLUGIN_ROOT="${5:-$CORE}" GIT_AUTHOR_NAME="Hook User" bash "$STOP_HOOK" 2>/dev/null)
}
prompt_hook() { (cd "$1" && printf '{"prompt":"x"}' | CLAUDE_PLUGIN_ROOT="$CORE" bash "$PROMPT_HOOK" 2>/dev/null || true); }
reason() { jq -r '.reason // empty' <<<"$1" 2>/dev/null || true; }
work_turn() {  # <원본 경로> — 파일을 바꾸고 명령을 돌린 턴
  { jl_user "고쳐 줘"
    jl_call e1 '{"file_path":"/w/src/app.sh","old_string":"a","new_string":"b"}'; jl_res e1 "ok"
    jl_call r1 '{"command":"ls src","description":"목록 보기"}'; jl_res r1 "app.sh"
  } > "$1"
}
THREE=$'**고쳤음**\n- 앱 줄을 바꿈\n\n**확인 범위**\n- 확인한 것: 목록 보기 → app.sh 있음\n- 확인 못 한 것: 실제 실행은 안 해 봄\n- 제가 대신 정한 것: 바꿀 줄을 하나로 정함'

# T1 — 매 턴 안내 한 줄
o1="$(prompt_hook "$(new_repo t1a korean)")"; o2="$(prompt_hook "$(new_repo t1b english)")"
o3="$(prompt_hook "$(new_repo t1c "")")"; o4="$(prompt_hook "$(new_repo t1d korean off)")"
n1="$(grep -cF "$TAG_KO" <<<"$o1" || true)"; n2="$(grep -cF "$TAG_EN" <<<"$o2" || true)"
n3="$(grep -cF "$TAG_EN" <<<"$o3" || true)"; n4="$(grep -cE '\[SCV (확인 범위|verification scope)\]' <<<"$o4" || true)"
[[ "$n1" == 1 && "$n2" == 1 && "$n3" == 1 && "$n4" == 0 ]] && ok "T1 매 턴 안내(korean 1 · english 1 · 빈 값은 영어 1 · 끔 0)" || bad "T1 [$n1 $n2 $n3 $n4]"

# T2 — 일한 턴에 세 줄이 없으면 한 번 막힘
R="$(new_repo t2 korean)"; TR="$WORK/t2.jsonl"; work_turn "$TR"; A=$'**고쳤음**\n- 앱 줄을 바꿈'
r1="$(reason "$(stop_hook "$R" "$TR" "$A" false)")"; o2="$(stop_hook "$R" "$TR" "$A" true)"
[[ "$r1" == *"$TAG_KO"*"빠진 줄: 확인한 것 · 확인 못 한 것 · 제가 대신 정한 것"* && "$o2" != *"$TAG_KO"* ]] \
  && ok "T2 세 줄 없음 → 한 번 막힘(빠진 줄 이름) · 계속 중 멈춤은 안 막음" || bad "T2 [$r1] [$o2]"

# T3 — 세 줄이 있고 근거가 맞으면 통과
R="$(new_repo t3 korean)"; TR="$WORK/t3.jsonl"; work_turn "$TR"
o="$(stop_hook "$R" "$TR" "$THREE" false)"
[[ "$o" != *"$TAG_KO"* ]] && ok "T3 세 줄 · 근거 맞음 → '[SCV 확인 범위]' 없음" || bad "T3 [$o]"

# T4 — 짧은 턴(SCV 기록 · 질문만)은 한 줄로 통과, 없으면 막힘
R="$(new_repo t4 korean)"; TR="$WORK/t4.jsonl"
{ jl_user "고마워"; jl_call s1 '{"skill":"scv:help"}'; jl_res s1 "ok"; jl_call q1 '{"questions":[]}'; jl_res q1 "답"; } > "$TR"
oa="$(stop_hook "$R" "$TR" $'**고마움 기록함**\n- 확인 범위: 기록만 함 — 확인 · 결정 없음' false)"
R2="$(new_repo t4b korean)"; ob="$(reason "$(stop_hook "$R2" "$TR" $'**고마움 기록함**\n- 기록했음' false)")"
[[ "$oa" != *"$TAG_KO"* && "$ob" == *"확인 범위 한 줄"* ]] && ok "T4 짧은 턴: 한 줄이면 통과 · 없으면 '확인 범위 한 줄' 요구" || bad "T4 [$oa] [$ob]"

# T5 — 도구를 안 쓴 턴은 요구 없음
R="$(new_repo t5 korean)"; TR="$WORK/t5.jsonl"; { jl_user "질문"; jl_asst "답임" a5; } > "$TR"
o="$(stop_hook "$R" "$TR" "답임" false)"
[[ "$o" != *"$TAG_KO"* ]] && ok "T5 도구 없는 턴 → 확인 범위 요구 없음" || bad "T5 [$o]"

# T6 — '없음'은 이유가 있어야 인정
R="$(new_repo t6 korean)"; TR="$WORK/t6.jsonl"; work_turn "$TR"
A1="${THREE/실제 실행은 안 해 봄/없음}"; A2="${THREE/실제 실행은 안 해 봄/없음 — 바꾼 줄 하나뿐이고 목록으로 확인함}"
r1="$(reason "$(stop_hook "$R" "$TR" "$A1" false)")"; R2="$(new_repo t6b korean)"; o2="$(stop_hook "$R2" "$TR" "$A2" false)"
[[ "$r1" == *"'없음'에 이유 없음: 확인 못 한 것"* && "$o2" != *"$TAG_KO"* ]] && ok "T6 빈 '없음' 막힘 · 이유 붙은 '없음' 통과" || bad "T6 [$r1] [$o2]"

# T7 — 근거 없는 '확인한 것'은 막힘(통과를 말했는데 시험 실행 없음 · 근거 목록에 없는 파일)
R="$(new_repo t7 korean)"; TR="$WORK/t7.jsonl"; work_turn "$TR"
A="${THREE/목록 보기 → app.sh 있음/언어 시험 실행 → 14개 통과, missing.sh 확인}"
r="$(reason "$(stop_hook "$R" "$TR" "$A" false)")"
[[ "$r" == *"이번 턴 근거 목록에 없는 확인: 통과(이번 턴에 시험 실행 없음) · missing.sh"* ]] && ok "T7 근거 없는 확인(통과 · 파일) 막힘" || bad "T7 [$r]"

# T8 — 근거 목록 판정: 읽기 명령은 시험 아님 · 파이프로 끝 코드 0 이어도 출력 ✖ 면 실패 · 뒤 실행은 알림 끝 코드 · FAIL=0 은 통과
TR="$WORK/t8.jsonl"
{ jl_user "시험 돌려"
  jl_call g1 '{"command":"grep -n x core/tests/test-a.sh","description":"시험 파일 읽기"}'; jl_res g1 "12: x"
  jl_call p1 '{"command":"bash core/tests/test-a.sh | tail -3","description":"파이프 시험"}'; jl_res p1 $'ok T1\n✖ T10 []'
  jl_call b1 '{"command":"bash core/tests/test-b.sh","description":"뒤 시험","run_in_background":true}'
  jl_res b1 "Command running in background with ID: bx1. Output is being written to: /tmp/w/bx1.output"
  jl_call c1 '{"command":"bash core/tests/test-c.sh","description":"요약 시험"}'; jl_res c1 "test-c: PASS=38 FAIL=0"
  jl_user $'<task-notification>\n<task-id>bx1</task-id>\n<summary>Background command "뒤 시험" completed (exit code 1)</summary>\n</task-notification>'
} > "$TR"
led="$(scv_evidence_build "$(scv_turn_group "$(cat "$TR")")")"; us=$'\x1f'
k1="$(sed -n 1p <<<"$led" | cut -d"$us" -f1,3)"; k2="$(sed -n 2p <<<"$led" | cut -d"$us" -f1,3)"
k3="$(sed -n 3p <<<"$led" | cut -d"$us" -f1,3)"; k4="$(sed -n 4p <<<"$led" | cut -d"$us" -f1,3)"
[[ "$k1" == "run${us}ok" && "$k2" == "test${us}fail" && "$k3" == "test${us}fail" && "$k4" == "test${us}ok" ]] \
  && ok "T8 근거 목록(읽기=실행 · 파이프 ✖=실패 · 뒤 실행 알림 끝 코드 1=실패 · FAIL=0=통과)" || bad "T8 [$k1] [$k2] [$k3] [$k4]"

# T9 — 실패 먼저: 바꾼 시험이 실패하는 걸 못 봤으면 '확인 못 한 것'에 이름이 있어야 함
TA="$WORK/t9a.jsonl"; TB="$WORK/t9b.jsonl"
{ jl_user "시험 고쳐"; jl_call e9 '{"file_path":"/w/core/tests/test-a.sh","old_string":"a","new_string":"b"}'; jl_res e9 "ok"
  jl_call t9 '{"command":"bash core/tests/test-a.sh","description":"시험 실행"}'; jl_res t9 "ok T1"; } > "$TA"
{ jl_user "시험 고쳐"; jl_call e9 '{"file_path":"/w/core/tests/test-a.sh","old_string":"a","new_string":"b"}'; jl_res e9 "ok"
  jl_call t8 '{"command":"bash core/tests/test-a.sh","description":"고치기 전 시험"}'; jl_res t8 "✖ T1" true
  jl_call t9 '{"command":"bash core/tests/test-a.sh","description":"시험 실행"}'; jl_res t9 "ok T1"; } > "$TB"
AN=$'**고쳤음**\n- 확인한 것: 시험 실행 → 통과\n- 확인 못 한 것: 실제 세션은 안 봄\n- 제가 대신 정한 것: 없음 — 정한 것 없이 계획대로 함'
AY="${AN/실제 세션은 안 봄/test-a.sh 는 고치기 전 실패를 못 봄}"
ra="$(reason "$(stop_hook "$(new_repo t9a korean)" "$TA" "$AN" false)")"
oy="$(stop_hook "$(new_repo t9b korean)" "$TA" "$AY" false)"; ob="$(stop_hook "$(new_repo t9c korean)" "$TB" "$AN" false)"
[[ "$ra" == *"고치기 전 실패를 못 본 시험('확인 못 한 것'에 적어라): test-a.sh"* && "$oy" != *"$TAG_KO"* && "$ob" != *"$TAG_KO"* ]] \
  && ok "T9 실패 먼저: 못 봤는데 안 밝힘 → 막힘 · 밝힘 → 통과 · 실패를 봄 → 요구 없음" || bad "T9 [$ra] [$oy] [$ob]"

# T10 — 다른 검사(언어)와 묶어 한 번에 막음
R="$(new_repo t10 korean)"; TR="$WORK/t10.jsonl"; work_turn "$TR"
A=$'**결과**\n- Statuses, moods and enemy statuses are wired in for the next battle step now.'
o="$(stop_hook "$R" "$TR" "$A" false)"; r="$(reason "$o")"
nd="$(grep -o '"decision"' <<<"$o" | wc -l | tr -d ' ')"
[[ "$nd" == 1 && "$r" == *"[SCV 언어]"* && "$r" == *"$TAG_KO"* ]] && ok "T10 언어 · 확인 범위 이유 둘을 막기 한 번에" || bad "T10 [$nd] [$r]"

# T11 — 끄면 이 기능 전과 같음(이 기능의 라이브러리가 없는 코어와 출력이 바이트 같음)
NOLIB="$WORK/core-nolib"; cp -R "$CORE" "$NOLIB"; rm -f "$NOLIB/scripts/lib/finish-report.sh"
TR="$WORK/t11.jsonl"; work_turn "$TR"; A=$'**고쳤음**\n- 앱 줄을 바꿈'
off="$(stop_hook "$(new_repo t11a korean off)" "$TR" "$A" false)"; nol="$(stop_hook "$(new_repo t11b korean)" "$TR" "$A" false "$NOLIB")"
# 매 턴 훅: 같은 저장소에서 끔 출력 = 켬 출력에서 안내 한 줄만 뺀 것(코어 사본은 판 정보가 없어 다른 안내가 붙으므로 쓰지 않는다).
RP="$(new_repo t11c korean off)"; po="$(prompt_hook "$RP")"
jq '.SCV_FINISH_REPORT = "on"' "$RP/scv/scv_settings.json" > "$RP/s.json" && mv "$RP/s.json" "$RP/scv/scv_settings.json"
pn="$(prompt_hook "$RP" | grep -vF "$TAG_KO" || true)"
[[ "$off" == "$nol" && "$po" == "$pn" && ! -e "$WORK/t11a/scv/journal/evidence.md" ]] \
  && ok "T11 끔 = 라이브러리 없는 코어와 같은 출력(종료 훅 · 매 턴 훅) · 근거 목록 파일 없음" || bad "T11 [$off] / [$nol] / po=${#po} pn=${#pn}"

# T12 — 영어 설정
R="$(new_repo t12 english)"; TR="$WORK/t12.jsonl"; work_turn "$TR"
EN3=$'**Fixed**\n- changed the app line\n\n**Verification scope**\n- Verified: 목록 보기 → app.sh present\n- Not verified: did not run the app\n- Decided for you: changed one line only'
r1="$(reason "$(stop_hook "$R" "$TR" $'**Fixed**\n- changed the app line' false)")"; o2="$(stop_hook "$(new_repo t12b english)" "$TR" "$EN3" false)"
[[ "$r1" == *"$TAG_EN"*"missing: Verified, Not verified, Decided for you"* && "$o2" != *"$TAG_EN"* ]] && ok "T12 영어 이름으로 같은 판정" || bad "T12 [$r1] [$o2]"

# T14 — 실제 기록 재현(사본이 있을 때만): SCV_FINISH_REPLAY=<폴더> 안의 *.jsonl 과 expected.txt("파일이름 시험바꾼턴 못본턴")
if [[ -n "${SCV_FINISH_REPLAY:-}" && -f "${SCV_FINISH_REPLAY}/expected.txt" ]]; then
  t14=0
  while read -r name want_tf want_miss; do
    f="$SCV_FINISH_REPLAY/$name"; [[ -f "$f" ]] || { bad "T14 사본 없음 $name"; t14=1; continue; }
    starts="$(jq -Rrn '[inputs | fromjson?] | to_entries[] | select(.value.type? == "user" and (.value.isMeta? != true) and (.value.sourceToolUseID? == null)
        and ((.value.message.content|type) == "string" or ((.value.message.content|type) == "array" and any(.value.message.content[]?; .type? == "text") and (any(.value.message.content[]?; .type? == "tool_result") | not)))
        and (((if (.value.message.content|type) == "string" then .value.message.content else ([.value.message.content[]? | select(.type? == "text") | .text] | join("\n")) end)) | test("^\\s*<(task-notification|system-reminder)") | not))
        | .key + 1' "$f")"
    total="$(wc -l < "$f" | tr -d ' ')"; tf=0; miss=0; prev=""
    for s in $starts $((total + 1)); do
      if [[ -n "$prev" ]]; then
        led="$(scv_evidence_build "$(scv_turn_group "$(sed -n "1,$((s - 1))p" "$f")")")"
        if grep -qE "^edit${us}" <<<"$led" && grep -E "^edit${us}" <<<"$led" | grep -qE '(^|/)(tests?|__tests__|e2e)/|[._-](test|spec)\.[A-Za-z]+$|(^|/)test-[A-Za-z0-9_-]+\.sh$'; then
          tf=$((tf + 1)); [[ -n "$(scv_evidence_test_first "$led")" ]] && miss=$((miss + 1))
        fi
      fi
      prev="$s"
    done
    [[ "$tf" == "$want_tf" && "$miss" == "$want_miss" ]] || { bad "T14 $name 시험 바꾼 턴 $tf(기대 $want_tf) · 못 본 턴 $miss(기대 $want_miss)"; t14=1; }
  done < "$SCV_FINISH_REPLAY/expected.txt"
  (( t14 == 0 )) && ok "T14 실제 기록 재현 — 시험판과 같은 숫자"
else
  echo "SKIP T14 실제 기록 재현(SCV_FINISH_REPLAY 사본 없음 — 공개 저장소에 원본을 넣지 않는다)"
fi

# T15 — 속도: 40MB 원본에서 켬 − 끔 ≤ 1초 또는 켬 ≤ 끔 × 1.5(각 두 번 중 짧은 값).
# 비율 조건(0.82.2): 다른 시험과 함께 도는 공용 실행기에서는 끔 자체가 4~6초로 늘어 차이만으로는 흔들렸다(1.7초 · 1.04초, 비율 1.37 · 1.16).
TR="$WORK/t15.jsonl"; big="$(head -c 100000 /dev/zero | tr '\0' 'x')"
{ jl_user "큰 일"; for i in $(seq 1 400); do jl_call "c$i" '{"command":"ls","description":"목록"}'; jl_res "c$i" "$big"; done; } > "$TR"
now() { perl -MTime::HiRes=time -e 'printf "%.3f", time'; }
# 판정은 CPU 시간으로 한다(0.89.2): 벽시계는 붐비는 검사 기계에서 같은 코드가 켬 6.40초 · 끔 3.73초까지 흔들렸다(2026-11-11 맥 CI).
# shellcheck source=lib/cpu-time.sh
source "$CORE/tests/lib/cpu-time.sh"
best() {  # <끄기 on|off> → "CPU 초 벽시계 초" — 각각 두 번 중 짧은 값
  local m="" mw="" i t0 t1 c0 c1 d dw R
  for i in 1 2; do R="$(new_repo "t15$1$i" korean "$1")"; cpu_mark c0; t0="$(now)"; stop_hook "$R" "$TR" "답" false >/dev/null; t1="$(now)"; cpu_mark c1
    d="$(perl -e "printf '%.3f', $c1 - $c0")"; if [[ -z "$m" ]] || perl -e "exit !($d < $m)"; then m="$d"; fi
    dw="$(perl -e "printf '%.3f', $t1 - $t0")"; if [[ -z "$mw" ]] || perl -e "exit !($dw < $mw)"; then mw="$dw"; fi; done
  printf '%s %s' "$m" "$mw"
}
read -r on_t on_w <<<"$(best on)"; read -r off_t off_w <<<"$(best off)"; sz="$(wc -c < "$TR" | tr -d ' ')"
perl -e "exit !($on_t - $off_t <= 1.0 || $on_t <= $off_t * 1.5)" && ok "T15 속도 ${sz}B 원본(CPU 시간): 켬 ${on_t}s · 끔 ${off_t}s — 벽시계: 켬 ${on_w}s · 끔 ${off_w}s" || bad "T15 (CPU 시간) 켬 ${on_t}s 끔 ${off_t}s — 벽시계: 켬 ${on_w}s 끔 ${off_w}s"

# T16 — 근거 목록 파일: 가림 필터 · 기록 자리에만 · 링크면 안 씀
R="$(new_repo t16 korean)"; TR="$WORK/t16.jsonl"
{ jl_user "고쳐 줘"; jl_call k1 '{"command":"curl -H x","description":"Bearer abcdefghijklmnopqrstuvwxyz0123456789 로 확인"}'; jl_res k1 "ok"; } > "$TR"
stop_hook "$R" "$TR" $'**결과**\n- 했음' false >/dev/null
ev="$(cat "$R/scv/journal/evidence.md" 2>/dev/null || true)"
R2="$(new_repo t16b korean)"; ln -s "$WORK/elsewhere.md" "$R2/scv/journal/evidence.md"
stop_hook "$R2" "$TR" $'**결과**\n- 했음' false >/dev/null
[[ "$ev" == *"실행 · 성공"* && "$ev" == *"[REDACTED]"* && "$ev" != *"abcdefghijklmnopqrstuvwxyz0123456789"* && ! -e "$WORK/elsewhere.md" ]] \
  && ok "T16 근거 목록 파일(가림 필터 · 기록 자리 · 링크면 안 씀)" || bad "T16 [$ev]"

# T17 — 다른 모양 원본(도구 호출을 못 찾음): 이 검사는 꺼지고 실패하지 않음
R="$(new_repo t17 korean)"; TR="$WORK/t17.jsonl"
printf '%s\n' '{"type":"session_meta","payload":{"id":"x"}}' '{"type":"response_item","payload":{"type":"function_call","name":"shell","arguments":"{\"command\":[\"ls\"]}"}}' > "$TR"
e=0; o="$(stop_hook "$R" "$TR" $'**결과**\n- 했음' false)" || e=1
[[ "$e" == 0 && "$o" != *"$TAG_KO"* && -z "$(scv_turn_group "$(cat "$TR")")" ]] && ok "T17 다른 모양 원본 → 근거 목록 비고 검사 꺼짐 · 실패 없음" || bad "T17 e=$e [$o]"

# 순수 함수 직접 확인
[[ "$(scv_finish_needed "")" == none && -z "$(scv_finish_note "" korean)" && -z "$(scv_finish_scan "**이 답의 확인 범위**" korean)" ]] \
  && ok "순수 함수(빈 목록 none · 빈 문제 빈 문구 · 굵은 제목은 칸 아님)" || bad "순수 함수"

exit "$fail"
