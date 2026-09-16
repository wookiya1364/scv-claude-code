#!/usr/bin/env bash
# test-help-echo.sh — "규약 지문 메아리 + 답 모양 린트" 검사 (v0.50.0+).
#
# 왜 있나: 규약이 컨텍스트에서 빠졌는지를 모델에게 묻지 않고 행동으로 판정한다는 약속은, 훅이 stdin 과
# 파일만으로 같은 판정을 내릴 때만 믿을 수 있다. 여기서 순수부(메아리 판정·린트·재읽기 결정), mark 의
# 지문 생성과 노출 범위, 종료 훅 → 매 턴 훅의 자기 회복 루프, 스위치와 실패 시 이전 동작, 10턴 시뮬레이션을 본다.
#
# Covers TESTS.md T1·T2·T3·T4·T5·T6 of 20260916-wookiya1364-help-protocol-echo.
# Run: bash core/tests/test-help-echo.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE=""
for up in "$HERE/.." "$HERE/../.."; do
  for sub in core vendor/scv-core/core plugins/scv/vendor/scv-core/core; do
    if [[ -f "$up/$sub/scripts/lib/settings.sh" ]]; then CORE="$(cd "$up/$sub" && pwd)"; break 2; fi
  done
done
[[ -n "$CORE" ]] || { echo "test-help-echo: payload not found from $HERE" >&2; exit 1; }
PASS=0; FAIL=0; SKIP=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "  – SKIP: $1"; SKIP=$((SKIP + 1)); }
US=$'\x1f'
LIB="$CORE/scripts/lib/help-state.sh"; STATE_SH="$CORE/scripts/help-state.sh"
PROMPT_HOOK="$CORE/template/hooks/on-user-prompt.sh"; START_HOOK="$CORE/template/hooks/on-session-start.sh"
STOP_HOOK="$CORE/template/hooks/on-stop.sh"; HELP_SH="$CORE/scripts/help.sh"
ROUTER="$CORE/protocols/help.md"; FULL="$CORE/protocols/help/full.md"
[[ -f "$LIB" ]] || { echo "lib missing: $LIB" >&2; exit 1; }
source "$LIB"
f() { local IFS="$US" a; read -r -a a <<<"$1"; printf '%s' "${a[$(( $2 - 1 ))]:-}"; }

echo "── [T1] 순수부 — 메아리 판정 · 답 모양 린트 · 재읽기 결정 ──"
[[ "$(scv_echo_check '' 'abcd1234' 0 yes)" == "skip" ]] && ok "protocol=0 → skip" || fail "protocol=0"
[[ "$(scv_echo_check '' '' 1 yes)" == "skip" ]] && ok "표식에 지문 없음(0.49 표식) → skip" || fail "지문 없는 표식"
[[ "$(scv_echo_check 'abcd1234' 'abcd1234' 1 no)" == "skip" ]] && ok "이번 턴 기록 없음 → skip" || fail "기록 없음"
[[ "$(scv_echo_check 'abcd1234' 'abcd1234' 1 yes)" == "ok" ]] && ok "지문 같음 → ok" || fail "ok"
[[ "$(scv_echo_check '' 'abcd1234' 1 yes)" == "missing" ]] && ok "지문 없음 → missing" || fail "missing"
[[ "$(scv_echo_check 'ffff0000' 'abcd1234' 1 yes)" == "mismatch" ]] && ok "지문 다름 → mismatch" || fail "mismatch"
v="$(scv_answer_lint $'하나다. 둘이다. 셋이다.\n\n- 항목\n' 2)"; grep -q '^lead-sentences=3>2$' <<<"$v" && ok "3문장 결론 → 위반" || fail "3문장: $v"
v="$(scv_answer_lint $'하나다. 둘이다. 셋이다.\n' 3)"; [[ -z "$v" ]] && ok "상한 3 이면 3문장 통과" || fail "상한 3: $v"
v="$(scv_answer_lint $'결론이다.\n\n| # | 질문 | 추천 |\n|---|---|---|\n| 1 | 무엇 | 이것 |\n| 2 | 어디 | |\n| 3 | 언제 |\n' 2)"
grep -q '^decision-no-reco=2$' <<<"$v" && grep -q '^decision-no-reco=3$' <<<"$v" && ! grep -q 'reco=1' <<<"$v" && ok "추천 열 빈 결정표 행 2·3 → 위반, 1 은 통과" || fail "결정표: $v"
v="$(scv_answer_lint $'설정은 `core/x.sh` 와 `SCV_LANG` 에 있고 `0.49.1` 부터다. 명령은 `mark` 다.\n' 2)"
grep -q 'lead-code=core/x.sh' <<<"$v" && grep -q 'lead-code=SCV_LANG' <<<"$v" && grep -q 'lead-code=0.49.1' <<<"$v" && ! grep -q 'lead-code=mark' <<<"$v" && ok "첫 문단 백틱 경로·설정 키·버전 → 위반, 짧은 명령 이름은 통과" || fail "코드값: $v"
v="$(scv_answer_lint $'| a | b |\n|---|---|\n| 1 | 2 |\n' 2)"; grep -q '^lead-missing$' <<<"$v" && ok "표로 시작 → 결론 없음" || fail "표 시작: $v"
v="$(scv_answer_lint $'네, 잘 됩니다. 지난 턴에 못 본 것을 이번에 봤습니다.\n\n- 항목 하나.\n- 항목 둘.\n\n| # | 질문 | 추천 |\n|---|---|---|\n| 1 | 무엇 | 이것 |\n' 2)"
[[ -z "$v" ]] && ok "정상 답 → 위반 0" || fail "정상 답: $v"
v="$(scv_answer_lint $'0.49.1 에서 고쳤다... 정말이다.\n' 2)"; [[ -z "$v" ]] && ok "버전 점·말줄임표는 문장으로 안 센다" || fail "점 세기: $v"
v="$(scv_answer_lint $'결론.\n\n```\n| # | a |\n| 1 | |\n하나. 둘. 셋. 넷.\n```\n' 2)"; [[ -z "$v" ]] && ok "코드 블록 안은 보지 않는다" || fail "코드 블록: $v"
d="$(scv_drift_decide missing '' on on)"; [[ "${d%%$US*}" == "1" && "${d#*$US}" == *"[SCV 규약 지문]"* ]] && ok "missing → reload + 지문 경고" || fail "decide missing: $d"
d="$(scv_drift_decide mismatch '' on on)"; [[ "${d%%$US*}" == "1" && "${d#*$US}" == *"[SCV 규약 지문]"* ]] && ok "mismatch → reload + 지문 경고" || fail "decide mismatch: $d"
d="$(scv_drift_decide ok $'lead-sentences=4>2' on on)"; [[ "${d%%$US*}" == "1" && "${d#*$US}" == *"[SCV 답 모양]"*"lead-sentences=4>2"* ]] && ok "위반 1 → reload + 모양 경고(위반 포함)" || fail "decide lint: $d"
d="$(scv_drift_decide ok '' on on)"; [[ "${d%%$US*}" == "0" && -z "${d#*$US}" ]] && ok "ok·0 → 변화 없음" || fail "decide ok: $d"
d="$(scv_drift_decide skip '' on on)"; [[ "${d%%$US*}" == "0" ]] && ok "skip → 변화 없음" || fail "decide skip: $d"
d="$(scv_drift_decide missing 'x' off off)"; [[ "${d%%$US*}" == "0" && -z "${d#*$US}" ]] && ok "스위치 둘 다 off → 아무 것도 안 한다" || fail "decide off: $d"
d="$(scv_drift_decide missing 'x' off on)"; [[ "${d#*$US}" != *"규약 지문"* && "${d#*$US}" == *"답 모양"* ]] && ok "메아리만 off → 린트 경고만" || fail "decide echo off: $d"
l="$(scv_drift_line 2026-09-16T10:00:00 7 missing $'a\nb' 1)"; [[ "$l" == "2026-09-16T10:00:00 turn=7 echo=missing lint=2 reload=1" ]] && ok "드리프트 로그 한 줄" || fail "로그 줄: $l"
st="$(scv_hstate_parse '{"session":"A","protocol":1,"turn":4,"diag":"abc","diag_at":"10:00","nonce":"deadbeef"}')"
[[ "$(scv_hstate_nonce "$st")" == "deadbeef" && "$(f "$st" 1)" == "A" ]] && ok "표식 파싱: nonce 필드" || fail "nonce 파싱: $st"
[[ "$(scv_hstate_nonce "$(scv_hstate_parse '{"session":"A","protocol":1,"turn":4}')")" == "" ]] && ok "0.49.0 표식(필드 없음) → nonce 빈값" || fail "옛 표식"
[[ "$(scv_hstate_nonce "$(scv_hstate_mark "$st" 01234567)")" == "01234567" && "$(scv_hstate_nonce "$(scv_hstate_mark "$st")")" == "deadbeef" ]] && ok "mark: 지문 갈아끼움 · 없으면 유지" || fail "mark nonce"
[[ -z "$(scv_hstate_nonce "$(scv_hstate_reload "$st" A reset 0)")" && -z "$(scv_hstate_nonce "$(scv_hstate_reload "$st" B prompt 0)")" && "$(scv_hstate_nonce "$(scv_hstate_reload "$st" A prompt 0)")" == "deadbeef" ]] \
  && ok "reset·세션 전환은 지문을 비우고, 같은 세션은 유지" || fail "reload nonce"
j="$(scv_hstate_render "$st")"; [[ "$(scv_hstate_parse "$j")" == "$st" && "$j" == *'"nonce":"deadbeef"'* ]] && ok "render→parse 항등 (nonce 포함)" || fail "왕복: $j"
if [[ -f "$CORE/scripts/check-purity.sh" ]]; then
  OUT="$(bash "$CORE/scripts/check-purity.sh" "$LIB" 2>&1)"; grep -q '^OK  purity' <<<"$OUT" && ok "순수성 계약 통과" || fail "순수성: $(head -2 <<<"$OUT")"
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-echo.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
mkproj() { local p="$WORK/$1"; mkdir -p "$p/scv/raw" "$p/scv/conversations"; [[ -n "${2:-}" ]] && printf '%s\n' "$2" > "$p/scv/scv_settings.json"; echo "$p"; }
hook() { ( cd "$1" && printf '{"prompt":"안녕","session_id":"%s"}' "$2" | CLAUDE_PLUGIN_ROOT="$CORE" SCV_GUARD_STATE="$WORK/gs" bash "$PROMPT_HOOK" 2>/dev/null ); }
start() { ( cd "$1" && printf '{"source":"%s"}' "$2" | CLAUDE_PLUGIN_ROOT="$CORE" bash "$START_HOOK" >/dev/null 2>&1 ); }
wc_line() { ( cd "$1" && bash "$HELP_SH" --with-context 2>/dev/null | grep '^PROTOCOL:' ); }
mark() { ( cd "$1" && bash "$STATE_SH" mark ); }
nonce_of() { ( cd "$1" && bash "$STATE_SH" read | grep -o '"nonce":"[0-9a-f]*"' | cut -d'"' -f4 ); }
# 종료 훅: 답 본문을 transcript(JSONL) 에 담아 넘긴다. jq 없으면 훅은 조용히 건너뛴다.
stop() {  # <proj> <답 본문>
  local tr="$WORK/tr-$RANDOM.jsonl"
  jq -cn --arg t "$2" '{type:"assistant",message:{content:[{type:"text",text:$t}]}}' > "$tr"
  ( cd "$1" && printf '{"transcript_path":"%s"}' "$tr" | CLAUDE_PLUGIN_ROOT="$CORE" GIT_AUTHOR_NAME=t bash "$STOP_HOOK" >/dev/null 2>&1 ); echo $?
}
# 대화 파일에 Turn 블록을 이어붙인다 — 지문 줄은 셋째 인자(빈 문자열이면 줄 자체를 뺀다).
append() {  # <proj> <n> <지문|''>
  local fl="$1/scv/conversations/20260916-000000-echo.md"
  [[ -f "$fl" ]] || printf -- '---\nslug: echo\nstatus: active\n---\n' > "$fl"
  { printf '\n## Turn %s — 2026-09-16T10:00:00+09:00\n' "$2"; [[ -n "$3" ]] && printf 'protocol: %s\n' "$3"; printf '\n**User**: 안녕\n\n**Claude Code**: 답.\n'; } >> "$fl"
  # 기록이 표식(턴 시작에 씀)보다 나중이어야 "이번 턴에 기록됨" 으로 본다 — mtime 초 단위라 1초 대기 대신
  # 표식을 과거로 돌린다 (회귀 러너의 코어 검사 게이트는 5분 제한: 대기 30번이면 그 선을 넘긴다).
  [[ -f "$1/scv/journal/.help-state" ]] && touch -t 202001010000 "$1/scv/journal/.help-state"
}
GOOD=$'네, 됩니다. 이렇게요.\n\n- 항목 하나.\n'
BAD4=$'하나다. 둘이다. 셋이다. 넷이다.\n\n- 항목.\n'
BADTBL=$'결론이다.\n\n| # | 질문 | 추천 |\n|---|---|---|\n| 1 | 무엇 | |\n'
have_jq=1; command -v jq >/dev/null 2>&1 || have_jq=0

echo "── [T2] mark 가 지문을 만들고, 규약을 읽은 자리에만 노출한다 ──"
P=$(mkproj t2); hook "$P" A >/dev/null
J1="$(mark "$P")"; N1="$(nonce_of "$P")"
[[ "$N1" =~ ^[0-9a-f]{8}$ ]] && ok "mark → 표식 nonce 8자리 16진 ($N1)" || fail "nonce 형식: $J1"
[[ "$J1" == *"\"nonce\":\"$N1\""* ]] && ok "mark 출력이 지문을 싣는다 (규약을 읽은 턴의 컨텍스트에만)" || fail "mark 출력: $J1"
[[ "$(cat "$P/scv/journal/.help-nonce" 2>/dev/null)" == "$N1" ]] && ok ".help-nonce 파일 = 표식 지문" || fail "지문 파일"
mark "$P" >/dev/null; N2="$(nonce_of "$P")"; [[ "$N2" =~ ^[0-9a-f]{8}$ && "$N2" != "$N1" ]] && ok "두 번째 mark → 새 지문" || fail "지문 갱신 안 됨: $N1 $N2"
O="$(hook "$P" A)"; ! grep -q "$N2" <<<"$O" && ok "매 턴 훅 출력에 지문 없음" || fail "훅 출력에 지문 노출"
! grep -q "$N2" <<<"$( cd "$P" && bash "$HELP_SH" --with-context 2>/dev/null )" && ok "--with-context 출력에 지문 없음" || fail "PROTOCOL 줄에 지문 노출"
! grep -qE '\b[0-9a-f]{8}\b' <<<"$(grep -i 'nonce\|fingerprint\|지문' "$ROUTER" || true)" && ok "라우터에 지문 값 없음" || fail "라우터에 지문 값"
grep -q 'scv/journal/.help-nonce' "$FULL" && grep -qi 'fingerprint' "$FULL" && ok "full.md 끝에 지문 파일·기록 지시" || fail "full.md 지시 없음"
grep -q 'protocol: <fingerprint>' "$ROUTER" && grep -q 'protocol: <fingerprint>' "$FULL" && ok "라우터·full.md 의 기록 형식에 지문 줄" || fail "기록 형식에 지문 줄 없음"
start "$P" clear; [[ -z "$(nonce_of "$P")" && ! -e "$P/scv/journal/.help-nonce" ]] && ok "reset → 표식 지문·지문 파일 비움" || fail "reset 뒤 지문 남음"

if (( have_jq )); then
echo "── [T3] 메아리 — 적으면 유지, 빠지면 다음 턴 load + 경고 ──"
P=$(mkproj t3); hook "$P" A >/dev/null; mark "$P" >/dev/null; N="$(nonce_of "$P")"
append "$P" 1 "$N"; rc="$(stop "$P" "$GOOD")"; [[ "$rc" == "0" ]] && ok "종료 훅 exit 0" || fail "종료 훅 rc=$rc"
O="$(hook "$P" A)"; ! grep -q '\[SCV 규약 지문\]' <<<"$O" && [[ "$(wc_line "$P")" == "PROTOCOL: loaded" ]] && ok "(a) 지문 적음 → loaded 유지 · 경고 없음" || fail "(a): $(wc_line "$P") / $(grep 'SCV 규약' <<<"$O")"
append "$P" 2 ""; stop "$P" "$GOOD" >/dev/null
O="$(hook "$P" A)"; grep -q '\[SCV 규약 지문\]' <<<"$O" && [[ "$(wc_line "$P")" == "PROTOCOL: load" ]] && ok "(b) 지문 없음 → 다음 턴 경고 + load" || fail "(b): $(wc_line "$P") / $(grep -c 'SCV 규약' <<<"$O")"
O="$(hook "$P" A)"; ! grep -q '\[SCV 규약 지문\]' <<<"$O" && ok "(b) 경고는 한 턴만 (다음 턴엔 없음)" || fail "경고 반복"
mark "$P" >/dev/null; append "$P" 3 "ffff0000"; stop "$P" "$GOOD" >/dev/null
O="$(hook "$P" A)"; grep -q '\[SCV 규약 지문\]' <<<"$O" && [[ "$(wc_line "$P")" == "PROTOCOL: load" ]] && ok "(c) 틀린 지문 → 경고 + load" || fail "(c)"
P=$(mkproj t3d); hook "$P" A >/dev/null; mark "$P" >/dev/null; stop "$P" "$GOOD" >/dev/null   # 이번 턴에 기록 없음(진단 모드 등)
O="$(hook "$P" A)"; ! grep -q '\[SCV 규약 지문\]' <<<"$O" && [[ "$(wc_line "$P")" == "PROTOCOL: loaded" ]] && ok "기록 없는 턴 → skip (loaded 유지)" || fail "기록 없는 턴에 경고"
P=$(mkproj t3e); hook "$P" A >/dev/null; append "$P" 1 ""; stop "$P" "$GOOD" >/dev/null   # protocol=0 (읽기 전)
O="$(hook "$P" A)"; ! grep -q '\[SCV 규약 지문\]' <<<"$O" && ok "읽기 전(protocol 0) 턴 → skip" || fail "읽기 전 턴에 경고"

echo "── [T4] 답 모양 린트 — 위반이면 다음 턴 경고 + load ──"
P=$(mkproj t4); hook "$P" A >/dev/null; mark "$P" >/dev/null; N="$(nonce_of "$P")"
append "$P" 1 "$N"; stop "$P" "$BAD4" >/dev/null
O="$(hook "$P" A)"; grep -q '\[SCV 답 모양\]' <<<"$O" && grep -q 'lead-sentences=4>2' <<<"$O" && [[ "$(wc_line "$P")" == "PROTOCOL: load" ]] && ok "(a) 결론 4문장 → 경고(위반 포함) + load" || fail "(a): $(wc_line "$P")"
mark "$P" >/dev/null; N="$(nonce_of "$P")"; append "$P" 2 "$N"; stop "$P" "$BADTBL" >/dev/null
O="$(hook "$P" A)"; grep -q '\[SCV 답 모양\]' <<<"$O" && grep -q 'decision-no-reco=1' <<<"$O" && [[ "$(wc_line "$P")" == "PROTOCOL: load" ]] && ok "(b) 추천 열 없는 결정표 → 경고 + load" || fail "(b)"
mark "$P" >/dev/null; N="$(nonce_of "$P")"; append "$P" 3 "$N"; stop "$P" "$GOOD" >/dev/null
O="$(hook "$P" A)"; ! grep -q '\[SCV 답 모양\]' <<<"$O" && ! grep -q '\[SCV 규약 지문\]' <<<"$O" && [[ "$(wc_line "$P")" == "PROTOCOL: loaded" ]] && ok "(c) 정상 답 → 아무 것도 없음" || fail "(c)"
P=$(mkproj t4c '{"SCV_PLAIN_MAX_SENTENCES":"4"}'); hook "$P" A >/dev/null; mark "$P" >/dev/null; N="$(nonce_of "$P")"; append "$P" 1 "$N"; stop "$P" "$BAD4" >/dev/null
O="$(hook "$P" A)"; ! grep -q '\[SCV 답 모양\]' <<<"$O" && ok "문장 상한 설정(4)을 린트도 따른다" || fail "상한 설정 무시"

echo "── [T5] 실패·스위치 — 이전 동작 ──"
P=$(mkproj t5); hook "$P" A >/dev/null; mark "$P" >/dev/null; N="$(nonce_of "$P")"; append "$P" 1 ""
before="$( cd "$P" && find scv -type f | LC_ALL=C sort | xargs cksum )"
( cd "$P" && printf '' | CLAUDE_PLUGIN_ROOT="$CORE" bash "$STOP_HOOK" ); rc=$?; [[ $rc -eq 0 ]] && ok "stdin 비움: exit 0" || fail "stdin 비움 rc=$rc"
( cd "$P" && printf '{{not json' | CLAUDE_PLUGIN_ROOT="$CORE" bash "$STOP_HOOK" ); rc=$?; [[ $rc -eq 0 ]] && ok "JSON 아님: exit 0" || fail "JSON 아님 rc=$rc"
after="$( cd "$P" && find scv -type f | LC_ALL=C sort | xargs cksum )"; [[ "$before" == "$after" ]] && ok "무효 입력엔 아무 것도 안 쓴다" || fail "무효 입력이 파일을 썼다"
[[ "$(wc_line "$P")" == "PROTOCOL: loaded" ]] && ok "무효 입력: 표식 불변(loaded)" || fail "무효 입력이 표식을 바꿈"
rm -f "$P/scv/journal/.help-nonce"; stop "$P" "$GOOD" >/dev/null; O="$(hook "$P" A)"
grep -q '\[SCV 규약 지문\]' <<<"$O" && ok "지문 파일이 없어도 표식 지문으로 판정(기록에 지문 없음 → 경고)" || fail "지문 파일 삭제 뒤 판정"
P=$(mkproj t5b '{"SCV_HELP_ECHO":"off"}'); hook "$P" A >/dev/null; mark "$P" >/dev/null; append "$P" 1 ""; stop "$P" "$GOOD" >/dev/null
O="$(hook "$P" A)"; ! grep -q '\[SCV 규약 지문\]' <<<"$O" && [[ "$(wc_line "$P")" == "PROTOCOL: loaded" ]] && ok "SCV_HELP_ECHO=off: 지문 없어도 경고·재읽기 없음" || fail "echo off 무시"
P=$(mkproj t5c '{"SCV_ANSWER_LINT":"off"}'); hook "$P" A >/dev/null; mark "$P" >/dev/null; N="$(nonce_of "$P")"; append "$P" 1 "$N"; stop "$P" "$BAD4" >/dev/null
O="$(hook "$P" A)"; ! grep -q '\[SCV 답 모양\]' <<<"$O" && [[ "$(wc_line "$P")" == "PROTOCOL: loaded" ]] && ok "SCV_ANSWER_LINT=off: 모양 위반에 경고·재읽기 없음" || fail "lint off 무시"
P=$(mkproj t5d '{"SCV_HELP_ECHO":"off","SCV_ANSWER_LINT":"off"}'); hook "$P" A >/dev/null; mark "$P" >/dev/null; append "$P" 1 ""
before="$( cd "$P" && find scv -type f ! -path '*/journal/2*' | LC_ALL=C sort | xargs cksum )"; stop "$P" "$BAD4" >/dev/null
after="$( cd "$P" && find scv -type f ! -path '*/journal/2*' | LC_ALL=C sort | xargs cksum )"; [[ "$before" == "$after" ]] && ok "둘 다 off: 종료 훅은 저널 외 아무 것도 안 쓴다 (0.49 동작)" || fail "둘 다 off 인데 썼다"
P=$(mkproj t5e '{"SCV_HELP_LOAD_ONCE":"off"}'); hook "$P" A >/dev/null; mark "$P" >/dev/null; append "$P" 1 ""; stop "$P" "$GOOD" >/dev/null
O="$(hook "$P" A)"; ! grep -q '\[SCV 규약 지문\]' <<<"$O" && ok "SCV_HELP_LOAD_ONCE=off: 메아리 검사 없음(매 턴 load 라 무의미)" || fail "load-once off 인데 메아리 경고"
# test-journal 은 TESTS.md 의 실행 블록과 코어 검사 게이트가 따로 돌린다 — 여기서 겹쳐 돌리지 않는다(시간).

echo "── [T6] 10턴 시뮬레이션 — 4·8턴 지문 누락, 6턴 모양 위반 → load 는 1·5·7·9 ──"
P=$(mkproj t6 '{"SCV_HELP_RELOAD_EVERY":"0"}'); loads=""; N=""
for i in $(seq 1 10); do
  hook "$P" S >/dev/null
  if [[ "$(wc_line "$P")" == "PROTOCOL: load" ]]; then loads="$loads$i "; mark "$P" >/dev/null; N="$(nonce_of "$P")"; fi
  case "$i" in 4|8) append "$P" "$i" "" ;; *) append "$P" "$i" "$N" ;; esac
  case "$i" in 6) stop "$P" "$BAD4" >/dev/null ;; *) stop "$P" "$GOOD" >/dev/null ;; esac
done
[[ "$loads" == "1 5 7 9 " ]] && ok "load 턴 = 1 5 7 9" || fail "load 턴: $loads"
DL="$P/scv/journal/.help-drift"
[[ "$(grep -c . "$DL" 2>/dev/null)" == "10" ]] && ok "드리프트 로그 10줄" || fail "드리프트 로그 $(grep -c . "$DL" 2>/dev/null) 줄"
[[ "$(grep -c 'echo=missing' "$DL")" == "2" && "$(grep -c 'lint=[1-9]' "$DL")" == "1" ]] && ok "로그: 누락 2 · 위반 1" || fail "로그 집계: $(cat "$DL")"
else
  skip "jq 없음 — 종료 훅 시나리오(T3~T6) 생략"
fi
echo "─────────────────────────────"; echo "  통과 $PASS · 실패 $FAIL · 생략 $SKIP"; [[ $FAIL -eq 0 ]] && { echo "  ALL GATES OK"; exit 0; } || exit 1
