#!/usr/bin/env bash
# test-force-help.sh — 매 턴 SCV 를 준비시키는 preflight (SCV_FORCE_HELP).
#
# 0.39.0 은 응답 종료 시점에 모델을 되돌려 세워 help 호출을 강제했다. 그 되돌림은
# 모델이 답을 다 쓴 뒤에 걸리므로, 되돌릴 때마다 답이 통째로 다시 생성됐다.
# 0.40.0 은 지점을 턴의 시작으로 옮긴다 — 진단을 미리 실어 보내면 확인하려고 액션을
# 한 번 더 부를 이유가 없어지고, 강제할 것도 남지 않는다.
#
# 그래서 이 검사의 핵심 단언은 **부정형**이다: 종료 훅이 어떤 경우에도 되돌리지
# 않는다. 앞 계획의 검사가 정확히 그 반대를 단언했으므로, 뒤집는 것이 이 파일의 일이다.
#
# Covers TESTS.md T1–T15 of 20260831-wookiya1364-force-help-preflight.
#
# Run: bash core/tests/test-force-help.sh
set -uo pipefail

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CORE="$HERE/.."
PROMPT_HOOK="$CORE/template/hooks/on-user-prompt.sh"
STOP_HOOK="$CORE/template/hooks/on-stop.sh"
GUARD_HOOK="$CORE/template/hooks/guard.sh"
FORCE_LIB="$CORE/scripts/lib/force-help.sh"
SETTINGS_LIB="$CORE/scripts/lib/settings.sh"
EXAMPLE="$CORE/template/scv/scv_settings.example.json"
PROBE="$CORE/scripts/help.sh"

PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }

for f in "$PROMPT_HOOK" "$STOP_HOOK" "$FORCE_LIB"; do
  [[ -f "$f" ]] || { echo "✖ 없다: $f"; exit 1; }
done

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
SESSION="sess-test"

P=""; STATE=""
new_proj() {  # <이름> [설정 JSON]
  local name="$1" settings="${2:-}"
  P="$WORK/$name"
  STATE="$WORK/state-$name"
  mkdir -p "$P/scv/raw" "$STATE"
  [[ -n "$settings" ]] && printf '%s\n' "$settings" > "$P/scv/scv_settings.json"
  return 0
}

run_prompt() {  # <프로젝트> → 프롬프트 훅 stdout
  ( cd "$1" && printf '{"prompt":"안녕","session_id":"%s"}' "$SESSION" \
    | CLAUDE_PLUGIN_ROOT="$CORE" SCV_GUARD_STATE="$STATE" bash "$PROMPT_HOOK" 2>/dev/null )
}

run_stop() {  # <프로젝트> [이벤트] → 종료 훅 stdout
  ( cd "$1" && printf '{"hook_event_name":"%s","session_id":"%s"}' "${2:-Stop}" "$SESSION" \
    | CLAUDE_PLUGIN_ROOT="$CORE" SCV_GUARD_STATE="$STATE" bash "$STOP_HOOK" 2>/dev/null )
}

is_block() { grep -q '"decision"[[:space:]]*:[[:space:]]*"block"' <<<"${1:-}"; }

echo "── [T1] 종료 훅이 되돌리지 않는다 ──"
new_proj t1; run_prompt "$P" >/dev/null
OUT="$(run_stop "$P")"; rc=$?
is_block "$OUT" && fail "되돌렸다: $OUT" || ok "차단 결정이 없다"
[[ $rc -eq 0 ]] && ok "종료 코드 0" || fail "rc=$rc"

echo "── [T2] 여러 번 실행해도 되돌리지 않는다 ──"
new_proj t2; run_prompt "$P" >/dev/null
blocked=0
for _ in 1 2 3 4 5; do is_block "$(run_stop "$P")" && blocked=$((blocked+1)); done
[[ $blocked -eq 0 ]] && ok "5회 모두 차단 없음" || fail "${blocked}회 되돌렸다"

echo "── [T3] 매 턴 진단이 주입된다 ──"
new_proj t3
OUT="$(run_prompt "$P")"
grep -q "Current project diagnosis" <<<"$OUT" && ok "진단이 실린다" || fail "진단 없음"

echo "── [T4] 개요와 명령 목록은 주입되지 않는다 ──"
if [[ -f "$PROBE" ]]; then
  FULL="$(bash "$PROBE" 2>/dev/null | wc -c)"
  INJ="$(printf '%s' "$OUT" | wc -c)"
  # 훅 출력에는 쉬운말·라우팅 블록도 들어가므로 단순 크기 비교로는 부족하다.
  # 점검 앞부분에만 있는 표지가 빠졌는지를 직접 본다.
  grep -q "Core idea (S·C·V)" <<<"$OUT" && fail "SCV 개요가 실렸다" || ok "개요가 빠졌다"
  grep -q "Run accumulated archived regression" <<<"$OUT" && fail "명령 목록이 실렸다" || ok "명령 목록이 빠졌다"
  echo "     (점검 전체 ${FULL}바이트 · 훅 출력 ${INJ}바이트)"
else
  ok "점검 스크립트가 없어 건너뛴다"
fi

echo "── [T5] 분류 지침이 세 갈래를 모두 말한다 ──"
grep -q "앞을 보는 말" <<<"$OUT" && ok "앞을 보는 턴 지침" || fail "앞 갈래 없음"
grep -q "뒤를 보는 말" <<<"$OUT" && ok "뒤를 보는 턴 지침" || fail "뒤 갈래 없음"
grep -q "둘 다 아니면" <<<"$OUT" && ok "둘 다 아닌 턴 지침 (가장 중요)" || fail "셋째 갈래 없음 — 모든 턴이 둘 중 하나로 밀린다"

echo "── [T6] 표시줄이 매 턴 나온다 ──"
A="$(run_prompt "$P")"; B="$(run_prompt "$P")"
grep -q "\[SCV preflight\]" <<<"$A" && grep -q "\[SCV preflight\]" <<<"$B" \
  && ok "두 번 다 표시줄이 있다" || fail "표시줄이 빠진 실행이 있다"

echo "── [T7] preflight 스위치를 끄면 주입도 표시줄도 없다 ──"
new_proj t7 '{"SCV_FORCE_HELP": "off"}'
OUT="$(run_prompt "$P")"
grep -q "\[SCV preflight\]" <<<"$OUT" && fail "off 인데 표시줄이 있다" || ok "표시줄 없음"
grep -q "Current project diagnosis" <<<"$OUT" && fail "off 인데 진단이 있다" || ok "진단 없음"
grep -q "\[SCV always-on\]" <<<"$OUT" && ok "라우팅 안내는 그대로 (두 스위치는 독립)" || fail "라우팅 안내까지 껐다"
is_block "$(run_stop "$P")" && fail "되돌렸다" || ok "되돌리지 않는다"

echo "── [T8] 전체 라우팅 스위치를 끄면 아무것도 없다 ──"
new_proj t8 '{"SCV_ALWAYS_ON": "off"}'
OUT="$(run_prompt "$P")"
grep -q "\[SCV always-on\]" <<<"$OUT" && fail "라우팅 안내가 있다" || ok "라우팅 안내 없음"
grep -q "\[SCV preflight\]" <<<"$OUT" && fail "표시줄이 있다" || ok "표시줄 없음"
grep -q "Current project diagnosis" <<<"$OUT" && fail "진단이 있다" || ok "진단 없음"

echo "── [T9] scv 폴더가 없으면 아무 출력도 없다 ──"
mkdir -p "$WORK/t9"; STATE="$WORK/state-t9"
OUT="$( cd "$WORK/t9" && printf '{"prompt":"x","session_id":"%s"}' "$SESSION" \
  | CLAUDE_PLUGIN_ROOT="$CORE" bash "$PROMPT_HOOK" 2>/dev/null )"; rc=$?
[[ $rc -eq 0 && -z "$OUT" ]] && ok "프롬프트 훅 무출력·exit 0" || fail "침묵 위반 (rc=$rc)"
OUT="$( cd "$WORK/t9" && printf '{"hook_event_name":"Stop","session_id":"%s"}' "$SESSION" \
  | CLAUDE_PLUGIN_ROOT="$CORE" bash "$STOP_HOOK" 2>/dev/null )"; rc=$?
[[ $rc -eq 0 && -z "$OUT" ]] && ok "종료 훅 무출력·exit 0" || fail "침묵 위반 (rc=$rc)"

echo "── [T10] 점검을 못 돌려도 막지 않는다 ──"
new_proj t10
FAKE="$WORK/fakecore"; mkdir -p "$FAKE/scripts/lib"
cp "$FORCE_LIB" "$FAKE/scripts/lib/force-help.sh"
cp "$SETTINGS_LIB" "$FAKE/scripts/lib/settings.sh" 2>/dev/null || true
# help.sh 가 없는 코어를 가리킨다 — 진단은 못 싣지만 나머지는 나와야 한다.
OUT="$( cd "$P" && printf '{"prompt":"x","session_id":"%s"}' "$SESSION" \
  | CLAUDE_PLUGIN_ROOT="$FAKE" bash "$PROMPT_HOOK" 2>/dev/null )"; rc=$?
[[ $rc -eq 0 ]] && ok "종료 코드 0" || fail "rc=$rc"
grep -q "\[SCV preflight\]" <<<"$OUT" && ok "표시줄과 지침은 나온다" || fail "점검 실패가 전부를 막았다"

echo "── [T11] 저널 기록이 이번 변경 이전과 같다 ──"
if bash "$CORE/tests/test-journal.sh" >/dev/null 2>&1; then
  ok "기존 저널 검사 초록"
else
  fail "저널 검사가 깨졌다 — bash core/tests/test-journal.sh 로 확인"
fi

echo "── [T12] 가드가 라이브러리를 읽지 않는다 ──"
new_proj t12
HIDDEN="$WORK/nolib"; mkdir -p "$HIDDEN/scripts"
# 판정부가 아예 없는 코어를 가리켜도 가드는 평소처럼 영수증을 남겨야 한다.
( cd "$P" && printf '{"session_id":"%s","cwd":"%s","tool_input":{"skill":"scv:help"}}' "$SESSION" "$P" \
  | SCV_GUARD_MODE=mint CLAUDE_PLUGIN_ROOT="$HIDDEN" SCV_GUARD_STATE="$STATE" \
    bash "$GUARD_HOOK" >/dev/null 2>&1 )
if ls "$STATE"/* >/dev/null 2>&1 && grep -rq "help" "$STATE" 2>/dev/null; then
  ok "판정부 없이도 영수증을 남긴다 — 가드가 다시 홀로 선다"
else
  fail "가드가 라이브러리에 매여 있다"
fi
grep -q "force-help" "$GUARD_HOOK" && fail "가드에 라이브러리 참조가 남았다" || ok "가드에 참조 없음"

echo "── [T13] 되돌림용 함수가 남아 있지 않다 ──"
gone=0
for fn in scv_force_classify scv_force_decide scv_force_reason scv_force_turn_file scv_force_directive; do
  grep -q "^${fn}()" "$FORCE_LIB" && { fail "되돌림용 함수가 남았다: $fn"; gone=1; }
done
[[ $gone -eq 0 ]] && ok "되돌림용 함수가 모두 걷혔다"
grep -q "^scv_force_trim_diagnosis()" "$FORCE_LIB" && ok "진단 잘라내기 함수가 있다" || fail "잘라내기 함수 없음"
grep -q "decision.*block" "$STOP_HOOK" && fail "종료 훅에 차단 결정이 남았다" || ok "종료 훅에 차단 결정 없음"

echo "── [T14] 판정부가 순수성 계약을 지킨다 ──"
OUT="$(bash "$CORE/scripts/check-purity.sh" "$FORCE_LIB" 2>&1)"
grep -q '^OK  purity' <<<"$OUT" && ok "순수성 계약 통과" || fail "순수성 위반: $OUT"

echo "── [T15] 잘라내기가 표지를 못 찾으면 전체를 돌려준다 ──"
# shellcheck source=/dev/null
source "$FORCE_LIB"
GOT="$(printf 'a\nb\nc\n' | scv_force_trim_diagnosis)"
[[ "$GOT" == $'a\nb\nc' ]] && ok "표지 없음 → 전체 반환 (반쪽보다 낫다)" || fail "잘못 잘랐다: $(printf '%q' "$GOT")"
GOT="$(printf 'x\n Current project diagnosis (p)\ny\n' | scv_force_trim_diagnosis)"
[[ "$GOT" == $' Current project diagnosis (p)\ny' ]] && ok "표지부터 끝까지만 남긴다" || fail "잘못 잘랐다: $(printf '%q' "$GOT")"

echo "── [T16] 키 등록 — 등록부와 예시 파일 ──"
# shellcheck source=/dev/null
source "$SETTINGS_LIB"
grep -q "SCV_FORCE_HELP" <<<"$SCV_PLAIN_KEYS" && ok "공개 키 목록에 있다" || fail "등록부에 없다"
grep -q '"SCV_FORCE_HELP": "on"' "$EXAMPLE" && ok "예시 파일 기본값 on" || fail "예시 파일에 기본값 없음"

echo
echo "─────────────────────────────"
echo "  통과 $PASS · 실패 $FAIL"
[[ $FAIL -eq 0 ]] && { echo "  ALL GATES OK"; exit 0; } || exit 1
