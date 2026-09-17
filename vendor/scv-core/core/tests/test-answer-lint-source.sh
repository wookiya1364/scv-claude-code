#!/usr/bin/env bash
# test-answer-lint-source.sh — "답 모양 검사는 이번 턴의 답만 본다" 검사 (v0.51.0+).
#
# 왜 있나: 종료 훅이 린트에 넘기는 본문은 (1) 호스트가 넘긴 마지막 답, (2) 그것이 없으면 대화 원본에서
# 이번 턴(마지막 사람 프롬프트 이후)의 답, (3) 그래도 없으면 없음(검사 생략) 이어야 한다. 원본은 호스트가
# 비동기로 적어 훅보다 늦을 수 있으므로, 낡은 답(한 턴 전)을 보는 일이 0 이어야 한다. 함께 따옴표·괄호
# 안 마침표를 문장으로 세던 오탐, 드리프트 줄의 src 토큰, 스위치·비차단 보장을 본다.
#
# Covers TESTS.md T1~T10 of 20260916-wookiya1364-answer-lint-turn-race (T11 은 test-help-echo.sh).
# Run: bash core/tests/test-answer-lint-source.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE=""
for up in "$HERE/.." "$HERE/../.."; do
  for sub in core vendor/scv-core/core plugins/scv/vendor/scv-core/core; do
    if [[ -f "$up/$sub/scripts/lib/settings.sh" ]]; then CORE="$(cd "$up/$sub" && pwd)"; break 2; fi
  done
done
[[ -n "$CORE" ]] || { echo "test-answer-lint-source: payload not found from $HERE" >&2; exit 1; }
PASS=0; FAIL=0; SKIP=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "  – SKIP: $1"; SKIP=$((SKIP + 1)); }
US=$'\x1f'
LIB="$CORE/scripts/lib/help-state.sh"; STATE_SH="$CORE/scripts/help-state.sh"
PROMPT_HOOK="$CORE/template/hooks/on-user-prompt.sh"; STOP_HOOK="$CORE/template/hooks/on-stop.sh"
[[ -f "$LIB" ]] || { echo "lib missing: $LIB" >&2; exit 1; }
source "$LIB"
command -v jq >/dev/null 2>&1 || { echo "jq 없음 — 이 검사는 jq 가 필요하다" >&2; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-lintsrc.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
mkproj() { local p="$WORK/$1"; mkdir -p "$p/scv/raw" "$p/scv/conversations"; [[ -n "${2:-}" ]] && printf '%s\n' "$2" > "$p/scv/scv_settings.json"; echo "$p"; }
hook() { ( cd "$1" && printf '{"prompt":"안녕","session_id":"%s"}' "$2" | CLAUDE_PLUGIN_ROOT="$CORE" SCV_GUARD_STATE="$WORK/gs" bash "$PROMPT_HOOK" 2>/dev/null ); }
mark() { ( cd "$1" && bash "$STATE_SH" mark ); }
nonce_of() { ( cd "$1" && bash "$STATE_SH" read | grep -o '"nonce":"[0-9a-f]*"' | cut -d'"' -f4 ); }
append() {  # <proj> <n> <지문|''>
  local fl="$1/scv/conversations/20260916-000000-src.md"
  [[ -f "$fl" ]] || printf -- '---\nslug: src\nstatus: active\n---\n' > "$fl"
  { printf '\n## Turn %s — 2026-09-16T10:00:00+09:00\n' "$2"; [[ -n "$3" ]] && printf 'protocol: %s\n' "$3"; printf '\n**User**: 안녕\n\n**Claude Code**: 답.\n'; } >> "$fl"
  [[ -f "$1/scv/journal/.help-state" ]] && touch -t 202001010000 "$1/scv/journal/.help-state"
}
# 원본(JSONL) 한 줄씩: U:<text> 사람 프롬프트 · R 도구 결과(사람 아님) · A:<text> 어시스턴트 텍스트 · T 도구 호출만
tr_line() {
  case "$1" in
    U:*) jq -cn --arg t "${1#U:}" '{type:"user",message:{content:$t}}' ;;
    R)   jq -cn '{type:"user",message:{content:[{type:"tool_result",content:"x"}]}}' ;;
    A:*) jq -cn --arg t "${1#A:}" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}' ;;
    T)   jq -cn '{type:"assistant",message:{content:[{type:"tool_use",name:"Bash"}]}}' ;;
  esac
}
tr_write() { local f="$1"; shift; : > "$f"; local l; for l in "$@"; do tr_line "$l" >> "$f"; done; }
# 종료 훅 실행: <proj> <stdin JSON> → rc
stop_in() { ( cd "$1" && printf '%s' "$2" | CLAUDE_PLUGIN_ROOT="$CORE" GIT_AUTHOR_NAME=t bash "$STOP_HOOK" >/dev/null 2>&1 ); echo $?; }
drift_last() { tail -n 1 "$1/scv/journal/.help-drift" 2>/dev/null; }
ready() {  # 표식 + 지문 + 이번 턴 기록(지문 있음) 까지 준비된 프로젝트
  local p; p="$(mkproj "$1" "${2:-}")"; hook "$p" A >/dev/null; mark "$p" >/dev/null; append "$p" 1 "$(nonce_of "$p")"; echo "$p"
}
GOOD=$'네, 됩니다. 이렇게요.\n\n- 항목 하나.\n'
BAD4=$'하나다. 둘이다. 셋이다. 넷이다.\n\n- 항목.\n'
QUOTE2=$'공유 대화의 결론은 같습니다. "코드는 빌려 쓰고, 그래프는 직접 만든다." 로 정리돼 있었고 저장했습니다.\n\n- 항목.\n'
QUOTE3=$'공유 대화의 결론은 같습니다. "코드는 빌려 쓰고, 그래프는 직접 만든다." 로 정리돼 있었고 저장했습니다. 하나 더입니다.\n\n- 항목.\n'
# 밀리초 시각 — GNU date 의 %N 은 macOS 에 없다(리터럴 "N" 이 붙어 산술 오류). python3 → 초 단위 순으로 폴백.
now_ms() { local n; n="$(date +%s%3N 2>/dev/null || true)"; [[ "$n" =~ ^[0-9]+$ ]] || n="$(python3 -c 'import time;print(int(time.time()*1000))' 2>/dev/null || true)"; [[ "$n" =~ ^[0-9]+$ ]] || n=$(( $(date +%s) * 1000 )); printf '%s' "$n"; }

echo "── [T0] 순수부 — 이번 턴 자르기 · 출처 고르기 · 드리프트 줄 src ──"
S=$'U\nA'"$US"$'낡은 답.\nU\nA'"$US"$'이번 답.'
[[ "$(scv_turn_slice "$S")" == "이번 답." ]] && ok "마지막 U 이후의 A 만" || fail "slice: $(scv_turn_slice "$S")"
S=$'U\nA'"$US"$'낡은 답.\nU'
[[ -z "$(scv_turn_slice "$S")" ]] && ok "U 뒤에 A 없음 → 빈값" || fail "slice lag"
S=$'A'"$US"$'답만.'
[[ -z "$(scv_turn_slice "$S")" ]] && ok "U 가 창 안에 없음 → 빈값(안전 쪽)" || fail "slice no-U"
S=$'U\nA'"$US"$'첫 줄\x1e둘째 줄\nA'"$US"$'셋째'
[[ "$(scv_turn_slice "$S")" == $'첫 줄\n둘째 줄\n셋째' ]] && ok "줄바꿈 복원 · 여러 A 이어붙임" || fail "slice join: $(scv_turn_slice "$S")"
p="$(scv_stop_pick_source '호스트 답' '원본 답')"; [[ "${p%%$US*}" == "host" && "${p#*$US}" == "호스트 답" ]] && ok "호스트 값 있으면 host" || fail "pick host: $p"
p="$(scv_stop_pick_source '' '원본 답')"; [[ "${p%%$US*}" == "transcript" && "${p#*$US}" == "원본 답" ]] && ok "없으면 transcript" || fail "pick tr: $p"
p="$(scv_stop_pick_source '' '')"; [[ "${p%%$US*}" == "none" && -z "${p#*$US}" ]] && ok "둘 다 없으면 none" || fail "pick none: $p"
p="$(scv_stop_pick_source $'  \n ' '원본 답')"; [[ "${p%%$US*}" == "transcript" ]] && ok "공백뿐인 호스트 값은 없음으로" || fail "pick blank host: $p"
l="$(scv_drift_line 2026-09-16T10:00:00 7 ok '' 0 host)"; [[ "$l" == "2026-09-16T10:00:00 turn=7 echo=ok lint=0 reload=0 src=host" ]] && ok "드리프트 줄 끝에 src" || fail "drift src: $l"
l="$(scv_drift_line 2026-09-16T10:00:00 7 ok '' 0)"; [[ "$l" == "2026-09-16T10:00:00 turn=7 echo=ok lint=0 reload=0" ]] && ok "src 없이 부르면 옛 형식 그대로" || fail "drift old: $l"
if [[ -f "$CORE/scripts/check-purity.sh" ]]; then
  OUT="$(bash "$CORE/scripts/check-purity.sh" "$LIB" 2>&1)"; grep -q '^OK  purity' <<<"$OUT" && ok "순수성 계약 통과" || fail "순수성: $(head -2 <<<"$OUT")"
fi

echo "── [T1] 호스트 값이 있으면 낡은 원본을 보지 않는다 ──"
P=$(ready t1); TR="$WORK/t1.jsonl"; tr_write "$TR" "U:안녕" "A:$BAD4" "U:다음"
IN="$(jq -cn --arg p "$TR" --arg m "$GOOD" '{transcript_path:$p,last_assistant_message:$m}')"
rc="$(stop_in "$P" "$IN")"; L="$(drift_last "$P")"
[[ "$rc" == "0" ]] && ok "exit 0" || fail "rc=$rc"
[[ "$L" == *"lint=0 reload=0 src=host" ]] && ok "lint=0 reload=0 src=host ($L)" || fail "T1 줄: $L"
[[ ! -e "$P/scv/journal/.help-warn" ]] && ok "경고 없음" || fail "경고 생김: $(cat "$P/scv/journal/.help-warn")"
D1="$L"

echo "── [T2] 호스트 값이 없고 원본에 이번 턴 답이 있으면 그것을 본다 ──"
P=$(ready t2); TR="$WORK/t2.jsonl"; tr_write "$TR" "U:안녕" "A:$BAD4"
stop_in "$P" "$(jq -cn --arg p "$TR" '{transcript_path:$p}')" >/dev/null; L="$(drift_last "$P")"
[[ "$L" == *"lint=1 reload=1 src=transcript" ]] && ok "lint=1 reload=1 src=transcript" || fail "T2 줄: $L"
grep -q '답 모양' "$P/scv/journal/.help-warn" 2>/dev/null && ok "답 모양 경고 예약" || fail "경고 없음"
D2="$L"

echo "── [T3] 호스트 값이 없고 원본이 늦으면 검사를 건너뛴다 ──"
P=$(ready t3); TR="$WORK/t3.jsonl"; tr_write "$TR" "U:안녕" "A:$BAD4" "U:다음"
t0=$(now_ms); stop_in "$P" "$(jq -cn --arg p "$TR" '{transcript_path:$p}')" >/dev/null; t1=$(now_ms); L="$(drift_last "$P")"
[[ "$L" == *"lint=0 reload=0 src=none" ]] && ok "lint=0 reload=0 src=none" || fail "T3 줄: $L"
[[ ! -e "$P/scv/journal/.help-warn" ]] && ok "경고 없음 (낡은 답을 보지 않음)" || fail "경고 생김"
grep -q '"protocol":1' "$P/scv/journal/.help-state" && ok "표식 protocol 그대로 1" || fail "표식 바뀜"
# 벽시계 단언은 두지 않는다 — 위 test-graph 와 같은 이유. 시간은 기록만 한다.
ok "훅 실행 완료 ($((t1 - t0))ms)"
D3="$L"

echo "── [T4] 원본이 재시도 창 안에 따라잡으면 그것을 본다 ──"
P=$(ready t4); TR="$WORK/t4.jsonl"; tr_write "$TR" "U:안녕" "A:$BAD4" "U:다음"
( sleep 0.3; tr_line "A:$BAD4" >> "$TR" ) &
stop_in "$P" "$(jq -cn --arg p "$TR" '{transcript_path:$p}')" >/dev/null; wait; L="$(drift_last "$P")"
[[ "$L" == *"lint=1 reload=1 src=transcript" ]] && ok "300ms 뒤 도착한 답을 봤다" || fail "T4 줄: $L"

echo "── [T5] 도구 결과 항목은 턴 경계가 아니다 ──"
P=$(ready t5); TR="$WORK/t5.jsonl"; tr_write "$TR" "U:안녕" "T" "R" "A:$BAD4"
stop_in "$P" "$(jq -cn --arg p "$TR" '{transcript_path:$p}')" >/dev/null; L="$(drift_last "$P")"
[[ "$L" == *"lint=1 reload=1 src=transcript" ]] && ok "tool_result 뒤의 답이 이번 턴으로 선택" || fail "T5 줄: $L"

echo "── [T6] 따옴표·괄호 안 마침표는 문장 끝이 아니다 ──"
v="$(scv_answer_lint "$QUOTE2" 2)"; [[ -z "$v" ]] && ok "따옴표 안 마침표 → 2문장 통과" || fail "quote2: $v"
v="$(scv_answer_lint "$QUOTE3" 2)"; grep -q '^lead-sentences=3>2$' <<<"$v" && ok "실제 3문장은 여전히 잡힘" || fail "quote3: $v"
v="$(scv_answer_lint $'"인용 하나. 인용 둘." 밖 문장이다. 둘째 문장.\n' 2)"; [[ -z "$v" ]] && ok "곧은 따옴표 안의 문장 여러 개도 안 센다" || fail "quote-inner: $v"
v="$(scv_answer_lint $'괄호(예: 이것.) 안도 같다. 둘째 문장.\n' 2)"; [[ -z "$v" ]] && ok "괄호 안 마침표도 안 센다" || fail "paren: $v"
v="$(scv_answer_lint $'“굽은 따옴표. 안.” 하나. 둘.\n' 2)"; [[ -z "$v" ]] && ok "굽은 따옴표 안도 안 센다" || fail "curly: $v"
P=$(ready t6); TR="$WORK/t6.jsonl"; tr_write "$TR" "U:안녕"
stop_in "$P" "$(jq -cn --arg p "$TR" --arg m "$QUOTE2" '{transcript_path:$p,last_assistant_message:$m}')" >/dev/null; L="$(drift_last "$P")"
[[ "$L" == *"lint=0 reload=0 src=host" ]] && ok "호스트 경로로도 통과" || fail "T6 훅: $L"

echo "── [T7] 드리프트 줄 형식 — 기존 토큰 그대로, 끝에 src 하나 ──"
RE='^[0-9T:+-]+ turn=[0-9]+ echo=[a-z]+ lint=[0-9]+ reload=[01] src=(host|transcript|none)$'
for L in "$D1" "$D2" "$D3"; do grep -qE "$RE" <<<"$L" && ok "형식 일치: $L" || fail "형식 불일치: $L"; done
grep -qE '^[0-9T:+-]+ turn=[0-9]+ echo=[a-z]+ lint=[0-9]+ reload=[01]' <<<"2026-09-16T21:05:17+09:00 turn=3 echo=skip lint=0 reload=0" && ok "0.50.0 옛 줄도 앞부분 정규식으로 집계됨" || fail "옛 줄"

echo "── [T8] 지문 검사는 출처와 무관하게 그대로 ──"
P=$(mkproj t8); hook "$P" A >/dev/null; mark "$P" >/dev/null; append "$P" 1 ""
TR="$WORK/t8.jsonl"; tr_write "$TR" "U:안녕"
stop_in "$P" "$(jq -cn --arg p "$TR" --arg m "$GOOD" '{transcript_path:$p,last_assistant_message:$m}')" >/dev/null; L="$(drift_last "$P")"
[[ "$L" == *"echo=missing lint=0 reload=1 src=host" ]] && ok "echo=missing reload=1 src=host" || fail "T8 줄: $L"
grep -q '규약 지문' "$P/scv/journal/.help-warn" 2>/dev/null && ok "지문 경고 그대로" || fail "지문 경고 없음"

echo "── [T9] 스위치 off 는 0.49.1 과 같다 ──"
P=$(ready t9 '{"SCV_ANSWER_LINT":"off","SCV_HELP_ECHO":"off"}'); TR="$WORK/t9.jsonl"; tr_write "$TR" "U:안녕" "A:$BAD4" "U:다음"
before="$( cd "$P" && find scv/journal -type f ! -name '2*' | LC_ALL=C sort | xargs cksum )"
t0=$(now_ms); stop_in "$P" "$(jq -cn --arg p "$TR" '{transcript_path:$p}')" >/dev/null; t1=$(now_ms)
after="$( cd "$P" && find scv/journal -type f ! -name '2*' | LC_ALL=C sort | xargs cksum )"
[[ "$before" == "$after" ]] && ok "드리프트·경고·표식 변화 없음" || fail "파일 바뀜"
ok "재시도 없이 종료 ($((t1 - t0))ms)"
P=$(ready t9b '{"SCV_ANSWER_LINT":"off"}'); tr_write "$WORK/t9b.jsonl" "U:안녕" "A:$BAD4"
stop_in "$P" "$(jq -cn --arg p "$WORK/t9b.jsonl" '{transcript_path:$p}')" >/dev/null; L="$(drift_last "$P")"
[[ "$L" == *"echo=ok lint=0 reload=0 src=none" ]] && ok "린트만 off → 본문 안 읽고 지문만, src=none" || fail "T9b 줄: $L"

echo "── [T10] 깨진 입력에도 exit 0 ──"
P=$(ready t10); snap() { ( cd "$1" && find . -type f ! -path './scv/journal/*' | LC_ALL=C sort ); }
S0="$(snap "$P")"
rc="$(stop_in "$P" 'not json')"; [[ "$rc" == "0" ]] && ok "JSON 아님 → exit 0" || fail "rc=$rc"
rc="$(stop_in "$P" '{"transcript_path":"/nonexistent/x.jsonl"}')"; [[ "$rc" == "0" ]] && ok "원본 없음 → exit 0" || fail "rc=$rc"
NOJQ="$WORK/nojq"; mkdir -p "$NOJQ"; for b in bash sed awk grep head tail tr cut sort cat date find touch mktemp printf sleep od; do p="$(command -v $b 2>/dev/null)"; [[ -n "$p" ]] && ln -sf "$p" "$NOJQ/$b"; done
rc="$( cd "$P" && printf '{"transcript_path":"%s"}' "$WORK/t2.jsonl" | PATH="$NOJQ" CLAUDE_PLUGIN_ROOT="$CORE" bash "$STOP_HOOK" >/dev/null 2>&1; echo $? )"
[[ "$rc" == "0" ]] && ok "jq 없음 → exit 0" || fail "jq 없음 rc=$rc"
[[ "$(snap "$P")" == "$S0" ]] && ok "scv/journal 밖에 새 파일 없음" || fail "밖에 파일 생김"

echo; echo "test-answer-lint-source: pass=$PASS fail=$FAIL skip=$SKIP"
(( FAIL == 0 ))
