#!/usr/bin/env bash
# test-force-help.sh — 매 턴 SCV 를 준비시키는 preflight (SCV_FORCE_HELP).
#
# 0.39.0 은 응답 종료 시점에 모델을 되돌려 세워 help 호출을 강제했다. 그 되돌림은
# 모델이 답을 다 쓴 뒤에 걸리므로, 되돌릴 때마다 답이 통째로 다시 생성됐다.
# 0.40.0 은 지점을 턴의 시작으로 옮긴다 — 진단을 미리 실어 보내면 확인하려고 액션을
# 한 번 더 부를 이유가 없어지고, 강제할 것도 남지 않는다.
#
# 0.41.0 은 그 지시가 무시되던 네 원인을 고친다: 자기모순·묻힌 위치·조건문 형태·
# 중복 블록. 그래서 이 검사는 텍스트의 **순서와 내용**을 직접 읽는다.
#
# 검사의 일부(T7~T9)는 대체된 계획에서 **이어받은** 것이다. 그 계획을 supersedes 로
# 선언하면 옛 검사가 회귀에서 빠지므로, 여기서 다시 세우지 않으면 조용히 사라진다.
#
# Covers TESTS.md T1–T15 of 20260901-wookiya1364-preflight-directive-strength.
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

echo "── [T1] 지시 블록이 진단보다 먼저 나온다 ──"
new_proj t1
OUT="$(run_prompt "$P")"
DIR_LINE="$(grep -n "SCV: 이 턴의 첫 행동" <<<"$OUT" | head -1 | cut -d: -f1)"
DIAG_LINE="$(grep -n "Current project diagnosis" <<<"$OUT" | head -1 | cut -d: -f1)"
if [[ -n "$DIR_LINE" && -n "$DIAG_LINE" && "$DIR_LINE" -lt "$DIAG_LINE" ]]; then
  ok "지시(${DIR_LINE}행)가 진단(${DIAG_LINE}행)보다 앞이다"
else
  fail "순서가 뒤집혔다 — 지시=${DIR_LINE:-없음} 진단=${DIAG_LINE:-없음}"
fi

echo "── [T2] 갈래가 없다 — 판단보다 행동이 앞선다 ──"
# 0.41.0 까지는 세 갈래를 제시하고 고르게 했다. 고르는 일이 행동보다 앞에 있으면
# 그 판단이 곧 빠져나갈 구멍이 된다 — 애매한 턴 앞에서 침묵이 언제나 더 싸다.
grep -qE "^  A\.|^  B\.|^  C\." <<<"$OUT" && fail "갈래 표지가 남아 있다" || ok "A/B/C 갈래 표지 없음"
grep -q "셋 중 하나를 고르" <<<"$OUT" && fail "여전히 고르라고 한다" || ok "고르라는 문장 없음"
grep -q "바로 답하라" <<<"$OUT" && fail "부르지 말라는 출구가 남아 있다" || ok "부르지 말라는 출구 없음"

echo "── [T2b] 명령이 하나이고 조건이 붙어 있지 않다 ──"
grep -q "답을 쓰기 전에" <<<"$OUT" && ok "답보다 먼저라는 시점이 있다" || fail "시점이 없다"
grep -q "지금 호출하라" <<<"$OUT" && ok "호출 명령이 있다" || fail "호출 명령이 없다"
grep -q "판단하지 말고 부르라" <<<"$OUT" && ok "판단을 넘기는 문장이 있다" || fail "판단이 여전히 모델에게 있다"
grep -q "help 가 판단한다" <<<"$OUT" && ok "판단 주체가 help 로 명시돼 있다" || fail "판단 주체가 없다"

echo "── [T2c] 부르지 않는 경우가 둘만 명시돼 있다 ──"
grep -q "이미 SCV 액션이 실려 있거나" <<<"$OUT" && ok "예외 1 — 이미 액션이 실린 턴" || fail "예외 1 없음 — 자기 자신을 다시 부른다"
grep -q "사람이 쓰지 않은 자동 알림" <<<"$OUT" && ok "예외 2 — 자동 알림" || fail "예외 2 없음"
grep -q "그 외에는 예외가 없다" <<<"$OUT" && ok "그 둘 외에 예외가 없다고 못 박았다" || fail "예외의 상한이 없다"

echo "── [T3] 빠져나갈 구멍이 닫혀 있다 ──"
grep -q "상태를 다시 조회하지 않는 데에만" <<<"$OUT" \
  && ok "재조회 금지가 진단으로 한정돼 있다" || fail "재조회 문장이 여전히 넓다"
grep -q "호출을 건너뛸 이유가 되지 않는다" <<<"$OUT" \
  && ok "진단을 받아도 호출은 그대로라는 문장이 있다" || fail "구멍이 열려 있다"

echo "── [T4] 호출해야 하는 이유가 실려 있다 ──"
grep -q "어디에도 남지 않는다" <<<"$OUT" && ok "부르지 않으면 논의가 사라진다는 사실" || fail "이유 문장 없음"
grep -q "파일로" <<<"$OUT" && ok "대화 모드가 파일로 남긴다는 설명" || fail "무엇을 남기는지가 없다"

echo "── [T5] 같은 요구를 하는 블록이 하나뿐이다 ──"
grep -q "\[SCV always-on\]" <<<"$OUT" && fail "옛 라우팅 표지가 따로 나온다" || ok "옛 표지 없음 — 한 블록으로 합쳐졌다"

echo "── [T6] 진단은 여전히 실린다 ──"
grep -q "Current project diagnosis" <<<"$OUT" && ok "진단이 지시 뒤에 있다" || fail "진단이 사라졌다"

echo "── [T7] 전체 스위치를 끄면 아무 것도 주입하지 않는다 (이어받음) ──"
new_proj t7 '{"SCV_ALWAYS_ON": "off"}'
OUT="$(run_prompt "$P")"
grep -q "SCV: 이 턴의 첫 행동" <<<"$OUT" && fail "off 인데 지시가 있다" || ok "지시 없음"
grep -q "Current project diagnosis" <<<"$OUT" && fail "off 인데 진단이 있다" || ok "진단 없음"

echo "── [T8] off 만 끈다 (이어받음) ──"
for v in off OFF; do
  new_proj "t8$v" "{\"SCV_ALWAYS_ON\": \"$v\"}"
  grep -q "SCV: 이 턴의 첫 행동" <<<"$(run_prompt "$P")" \
    && fail "$v 인데 켜져 있다" || ok "$v → 꺼짐"
done
for v in on maybe; do
  new_proj "t8$v" "{\"SCV_ALWAYS_ON\": \"$v\"}"
  grep -q "SCV: 이 턴의 첫 행동" <<<"$(run_prompt "$P")" \
    && ok "$v → 켜짐" || fail "$v 인데 꺼졌다"
done

echo "── [T9] 쉬운말 스위치와 독립이다 (이어받음) ──"
new_proj t9 '{"SCV_PLAIN_LANGUAGE": "off"}'
OUT="$(run_prompt "$P")"
grep -q "\[SCV plain language\]" <<<"$OUT" && fail "쉬운말 off 인데 그 블록이 있다" || ok "쉬운말 블록 없음"
grep -q "SCV: 이 턴의 첫 행동" <<<"$OUT" && ok "지시 블록은 그대로 있다" || fail "쉬운말 off 가 지시까지 껐다"

echo "── [T10] preflight 스위치를 끄면 진단 없이 지시만 ──"
new_proj t10 '{"SCV_FORCE_HELP": "off"}'
OUT="$(run_prompt "$P")"
grep -q "SCV: 이 턴의 첫 행동" <<<"$OUT" && ok "지시는 있다" || fail "지시가 사라졌다"
grep -q "Current project diagnosis" <<<"$OUT" && fail "off 인데 진단이 있다" || ok "진단 없음"

echo "── [T11] 되돌림은 여전히 없다 ──"
new_proj t11; run_prompt "$P" >/dev/null
blocked=0
for _ in 1 2 3 4 5; do is_block "$(run_stop "$P")" && blocked=$((blocked+1)); done
[[ $blocked -eq 0 ]] && ok "5회 모두 차단 없음" || fail "${blocked}회 되돌렸다"

echo "── [T12] scv 폴더가 없으면 아무 출력도 없다 ──"
mkdir -p "$WORK/t12"; STATE="$WORK/state-t12"
OUT="$( cd "$WORK/t12" && printf '{"prompt":"x","session_id":"%s"}' "$SESSION" \
  | CLAUDE_PLUGIN_ROOT="$CORE" bash "$PROMPT_HOOK" 2>/dev/null )"; rc=$?
[[ $rc -eq 0 && -z "$OUT" ]] && ok "프롬프트 훅 무출력·exit 0" || fail "침묵 위반 (rc=$rc)"
OUT="$( cd "$WORK/t12" && printf '{"hook_event_name":"Stop","session_id":"%s"}' "$SESSION" \
  | CLAUDE_PLUGIN_ROOT="$CORE" bash "$STOP_HOOK" 2>/dev/null )"; rc=$?
[[ $rc -eq 0 && -z "$OUT" ]] && ok "종료 훅 무출력·exit 0" || fail "침묵 위반 (rc=$rc)"

echo "── [T13] 점검을 못 돌려도 지시는 나간다 ──"
new_proj t13
FAKE="$WORK/fakecore"; mkdir -p "$FAKE/scripts/lib"
cp "$FORCE_LIB" "$FAKE/scripts/lib/force-help.sh"
cp "$SETTINGS_LIB" "$FAKE/scripts/lib/settings.sh" 2>/dev/null || true
OUT="$( cd "$P" && printf '{"prompt":"x","session_id":"%s"}' "$SESSION" \
  | CLAUDE_PLUGIN_ROOT="$FAKE" bash "$PROMPT_HOOK" 2>/dev/null )"; rc=$?
[[ $rc -eq 0 ]] && ok "종료 코드 0" || fail "rc=$rc"
grep -q "SCV: 이 턴의 첫 행동" <<<"$OUT" && ok "지시는 나온다" || fail "점검 실패가 지시까지 막았다"

echo "── [T14] 문구 생성부가 순수성 계약을 지킨다 ──"
OUT="$(bash "$CORE/scripts/check-purity.sh" "$FORCE_LIB" 2>&1)"
grep -q '^OK  purity' <<<"$OUT" && ok "순수성 계약 통과" || fail "순수성 위반: $OUT"

echo "── [T15] 저널 기록이 그대로다 ──"
if bash "$CORE/tests/test-journal.sh" >/dev/null 2>&1; then
  ok "기존 저널 검사 초록"
else
  fail "저널 검사가 깨졌다 — bash core/tests/test-journal.sh 로 확인"
fi

echo "── [T16] 두 스위치가 모두 등록부와 예시 파일에 있다 (이어받음) ──"
# 옛 라우팅 검사가 SCV_ALWAYS_ON 의 등록을 지켰다. 그 계획을 대체하므로 여기서
# 이어받는다 — 등록되지 않은 키는 사용자가 존재를 알 수 없는 숨은 스위치가 된다.
# shellcheck source=/dev/null
source "$SETTINGS_LIB"
for k in SCV_ALWAYS_ON SCV_FORCE_HELP; do
  grep -q "$k" <<<"$SCV_PLAIN_KEYS" && ok "$k 이 공개 키 목록에 있다" || fail "$k 이 등록부에 없다"
  grep -q "$k" <<<"$SCV_SECRET_KEYS" && fail "$k 이 비밀 키 목록에 들어갔다" || ok "$k 은 비밀 키가 아니다"
  grep -q "\"$k\": \"on\"" "$EXAMPLE" && ok "$k 예시 기본값 on" || fail "$k 예시 기본값 없음"
done
python3 - "$EXAMPLE" <<'PY2' && ok "두 키 모두 _doc 에 설명이 있다" || fail "_doc 설명 누락"
import json, sys
d = json.load(open(sys.argv[1]))
doc = d.get("_doc", {})
for k in ("SCV_ALWAYS_ON", "SCV_FORCE_HELP"):
    assert k in doc and doc[k].strip(), k
PY2

echo
echo "── [T17] 지시 블록이 전보다 짧다 ──"
# 분류를 걷어낸 만큼 줄어야 한다. 늘었다면 갈래를 말로 바꿔 남긴 것이다.
LINES="$( ( source "$FORCE_LIB"; scv_force_routing ) | wc -l | tr -d ' ' )"
if [[ "$LINES" -lt 21 ]]; then
  ok "지시 블록 ${LINES}행 — 이전 21행보다 짧다"
else
  fail "지시 블록이 ${LINES}행 — 줄지 않았다 (이전 21행)"
fi

echo "── [T18] help 에 돌려보내는 갈래가 없다 ──"
# 초안은 모델의 출구를 없애면서 help 안에 같은 출구를 새로 뒀다. 출구를 옮기는 것은
# 없애는 것이 아니다 — 이 검사가 그 실수를 다시 못 하게 막는다.
HELP_PROTO="$CORE/protocols/help.md"
if [[ -f "$HELP_PROTO" ]]; then
  grep -q "Never hand the turn back unrecorded" "$HELP_PROTO" \
    && ok "돌려보내지 않는다는 규칙이 있다" || fail "규칙이 없다"
  grep -qi "nothing worth keeping" "$HELP_PROTO" \
    && grep -qi "rejected on purpose" "$HELP_PROTO" \
    && ok "그 갈래를 일부러 뺐다는 근거가 남아 있다" \
    || fail "왜 뺐는지가 없다 — 다음 사람이 다시 넣는다"
else
  fail "help 프로토콜을 찾을 수 없다: $HELP_PROTO"
fi

echo "── [T19] 짧은 턴은 세션의 대화 파일에 이어 붙는다 ──"
if [[ -f "$HELP_PROTO" ]]; then
  grep -q "appended to the" "$HELP_PROTO" \
    && grep -q "conversation file this session is already writing" "$HELP_PROTO" \
    && ok "세션 파일에 이어 붙인다는 규칙이 있다" || fail "이어 붙이기 규칙이 없다"
  grep -q "no conversation file yet, open one" "$HELP_PROTO" \
    && ok "세션 파일이 없을 때 하나 연다는 규칙이 있다" || fail "첫 짧은 턴의 처리가 없다"
  grep -q "Short turns skip this question entirely" "$HELP_PROTO" \
    && ok "짧은 턴에는 되묻지 않는다" || fail "짧은 턴에도 질문이 붙는다"
fi

echo "── [T20] 위임 스위치 — 기본 꺼짐, on 만 켠다 (v0.46.0+) ──"
new_proj t20; OUT="$(run_prompt "$P")"
grep -q "\[SCV delegate\]" <<<"$OUT" && fail "스위치 없음인데 위임 블록이 있다" || ok "기본: 위임 블록 없음"
new_proj t20on '{"SCV_DELEGATE_EFFORT": "on"}'; OUT="$(run_prompt "$P")"
grep -q "\[SCV delegate\]" <<<"$OUT" && ok "on → 위임 블록 있음" || fail "on 인데 위임 블록이 없다"
grep -q "SCV: 이 턴의 첫 행동" <<<"$OUT" && ok "라우팅 지시는 그대로" || fail "위임 스위치가 라우팅 지시를 껐다"
new_proj t20both '{"SCV_DELEGATE_EFFORT": "on", "SCV_ALWAYS_ON": "off"}'; OUT="$(run_prompt "$P")"
grep -q "\[SCV delegate\]" <<<"$OUT" && ok "항상-켬 off 여도 위임 블록은 자기 스위치만 본다" || fail "항상-켬 off 가 위임 블록까지 껐다"

echo "─────────────────────────────"
echo "  통과 $PASS · 실패 $FAIL"
[[ $FAIL -eq 0 ]] && { echo "  ALL GATES OK"; exit 0; } || exit 1
