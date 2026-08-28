#!/usr/bin/env bash
# test-force-help.sh — help 호출을 기계로 강제한다 (SCV_FORCE_HELP).
#
# 안내는 부탁이고 모델은 대부분 흘린다 (실측). 호스트에는 스킬 호출을 강제하는
# 장치가 없지만, 응답 종료 훅은 차단 결정으로 모델을 되돌려 세울 수 있다. 호출
# 여부는 가드가 이미 발행하는 위조 불가 영수증으로 판정한다.
#
# 이 검사의 무게는 "되돌리는가" 보다 "되돌리지 않는가" 에 실려 있다. 잘못 되돌리면
# 대화 자체가 못 쓰게 되기 때문이다.
#
# Covers TESTS.md T1–T15 of 20260828-wookiya1364-forced-help-invocation.
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

PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }

for f in "$PROMPT_HOOK" "$STOP_HOOK" "$FORCE_LIB"; do
  [[ -f "$f" ]] || { echo "✖ 없다: $f"; exit 1; }
done

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

SESSION="sess-test"
STATE=""   # 시나리오마다 새로 잡는다

# 프로젝트 하나를 세운다: scv/ 폴더 + 전용 영수증 저장소.
#
# 값을 찍어 내지 않고 P·STATE 를 직접 채운다. 명령 치환으로 부르면 함수가 하위
# 셸에서 돌아 STATE 배정이 부모에 닿지 않고, 모든 시나리오가 앞 시나리오의 저장소를
# 공유하게 된다 — 처음 이 검사를 쓸 때 실제로 그렇게 새서 두 항목이 거짓 실패했다.
P=""; STATE=""
new_proj() {  # <이름> [설정 JSON]
  local name="$1" settings="${2:-}"
  P="$WORK/$name"
  STATE="$WORK/state-$name"
  # raw/ 까지 만드는 이유: 가드는 scv/ 폴더만으로는 프로젝트로 인정하지 않고
  # promote·archive·raw 중 하나를 찾는다. 실제 작업공간과 같은 모양이어야 T17 이
  # 가드의 실제 경로를 본다.
  mkdir -p "$P/scv/raw" "$STATE"
  [[ -n "$settings" ]] && printf '%s\n' "$settings" > "$P/scv/scv_settings.json"
  return 0
}

run_prompt() {  # <프로젝트> → 프롬프트 훅 stdout
  local proj="$1"
  ( cd "$proj" && printf '{"prompt":"안녕","session_id":"%s"}' "$SESSION" \
    | CLAUDE_PLUGIN_ROOT="$CORE" SCV_GUARD_STATE="$STATE" bash "$PROMPT_HOOK" 2>/dev/null )
}

run_stop() {  # <프로젝트> [이벤트 이름] → 종료 훅 stdout
  local proj="$1" ev="${2:-Stop}"
  ( cd "$proj" && printf '{"hook_event_name":"%s","session_id":"%s"}' "$ev" "$SESSION" \
    | CLAUDE_PLUGIN_ROOT="$CORE" SCV_GUARD_STATE="$STATE" bash "$STOP_HOOK" 2>/dev/null )
}

# 영수증에 한 줄 발행한다 (스킬 훅이 한 것과 같은 모양).
mint() {  # <프로젝트> <액션 id>
  local proj="$1" id="$2" key file
  # shellcheck source=/dev/null
  source "$FORCE_LIB"
  key="$(scv_force_project_key "$proj")"
  file="$(scv_force_receipt_file "$STATE" "$SESSION" "$key")"
  mkdir -p "$STATE"; printf '%s\n' "$id" >> "$file"
}

is_block() { grep -q '"decision"[[:space:]]*:[[:space:]]*"block"' <<<"${1:-}"; }
reason_of() { printf '%s' "${1:-}" | sed -n 's/.*"reason"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p'; }

echo "── [T1] 영수증이 없으면 되돌린다 ──"
new_proj t1; run_prompt "$P" >/dev/null
OUT="$(run_stop "$P")"
is_block "$OUT" && ok "차단 결정이 나온다" || fail "되돌리지 않았다: $OUT"
[[ -n "$(reason_of "$OUT")" ]] && ok "사유가 비어 있지 않다" || fail "사유 없음"

echo "── [T2] 턴 시작 이후 help 영수증이 있으면 통과 ──"
new_proj t2; run_prompt "$P" >/dev/null
mint "$P" "scv:help"
OUT="$(run_stop "$P")"
is_block "$OUT" && fail "help 를 불렀는데 되돌렸다: $OUT" || ok "통과한다"

echo "── [T3] 턴 시작 이전의 help 는 근거가 아니다 ──"
new_proj t3
mint "$P" "scv:help"          # 지난 턴의 호출
run_prompt "$P" >/dev/null    # 그 다음 턴이 시작된다
OUT="$(run_stop "$P")"
is_block "$OUT" && ok "지난 턴 호출은 무시하고 되돌린다" || fail "지난 턴 호출을 근거로 통과시켰다"

echo "── [T4] 회차마다 사유가 달라진다 ──"
new_proj t4; run_prompt "$P" >/dev/null
R1="$(reason_of "$(run_stop "$P")")"
R2="$(reason_of "$(run_stop "$P")")"
R3="$(reason_of "$(run_stop "$P")")"
[[ -n "$R1" && -n "$R2" && -n "$R3" ]] && ok "세 회차 모두 사유가 있다" || fail "빈 사유가 있다"
[[ "$R1" != "$R2" && "$R2" != "$R3" && "$R1" != "$R3" ]] \
  && ok "1·2·3회차 사유가 서로 다르다" || fail "같은 문구를 반복한다"

echo "── [T5] 자체 상한이 없다 ──"
new_proj t5; run_prompt "$P" >/dev/null
for _ in 1 2 3 4 5 6 7 8; do run_stop "$P" >/dev/null; done
OUT="$(run_stop "$P")"   # 9회차
is_block "$OUT" && ok "9회차에도 되돌린다 (포기 로직 없음)" || fail "스스로 포기했다: $OUT"

echo "── [T6] 턴 시작 표시가 없으면 통과 (고장은 열림으로) ──"
new_proj t6   # 프롬프트 훅을 돌리지 않는다
OUT="$(run_stop "$P")"; rc=$?
is_block "$OUT" && fail "기준선이 없는데 되돌렸다" || ok "되돌리지 않는다"
[[ $rc -eq 0 ]] && ok "종료 코드 0" || fail "rc=$rc"

echo "── [T7] 저장소를 못 쓰면 통과 ──"
new_proj t7; run_prompt "$P" >/dev/null
chmod 000 "$STATE" 2>/dev/null || true
OUT="$(run_stop "$P")"
chmod 755 "$STATE" 2>/dev/null || true
if [[ "$(id -u)" == "0" ]]; then
  ok "root 라 권한 시나리오는 건너뛴다"
else
  is_block "$OUT" && fail "저장소 불가인데 되돌렸다" || ok "되돌리지 않는다"
fi

echo "── [T8] 강제 스위치 off — 되돌림도 표시줄도 없다 ──"
new_proj t8 '{"SCV_FORCE_HELP": "off"}'
OUT="$(run_prompt "$P")"
grep -q "\[SCV force\]" <<<"$OUT" && fail "off 인데 표시줄이 있다" || ok "표시줄 없음"
grep -q "\[SCV always-on\]" <<<"$OUT" && ok "라우팅 안내는 그대로 (두 스위치는 독립)" || fail "라우팅 안내까지 껐다"
OUT="$(run_stop "$P")"
is_block "$OUT" && fail "off 인데 되돌렸다" || ok "되돌리지 않는다"

echo "── [T9] 전체 라우팅 off — 안내·표시줄·되돌림 전부 없다 ──"
new_proj t9 '{"SCV_ALWAYS_ON": "off"}'
OUT="$(run_prompt "$P")"
grep -q "\[SCV always-on\]" <<<"$OUT" && fail "라우팅 안내가 있다" || ok "라우팅 안내 없음"
grep -q "\[SCV force\]" <<<"$OUT" && fail "표시줄이 있다" || ok "표시줄 없음"
OUT="$(run_stop "$P")"
is_block "$OUT" && fail "되돌렸다" || ok "되돌리지 않는다"

echo "── [T10] scv/ 없는 곳은 침묵 ──"
mkdir -p "$WORK/t10"; STATE="$WORK/state-t10"
OUT="$( cd "$WORK/t10" && printf '{"prompt":"x","session_id":"%s"}' "$SESSION" \
  | CLAUDE_PLUGIN_ROOT="$CORE" SCV_GUARD_STATE="$STATE" bash "$PROMPT_HOOK" 2>/dev/null )"; rc=$?
[[ $rc -eq 0 && -z "$OUT" ]] && ok "프롬프트 훅 무출력·exit 0" || fail "침묵 위반 (rc=$rc): $OUT"
OUT="$( cd "$WORK/t10" && printf '{"hook_event_name":"Stop","session_id":"%s"}' "$SESSION" \
  | CLAUDE_PLUGIN_ROOT="$CORE" SCV_GUARD_STATE="$STATE" bash "$STOP_HOOK" 2>/dev/null )"; rc=$?
[[ $rc -eq 0 && -z "$OUT" ]] && ok "종료 훅 무출력·exit 0" || fail "침묵 위반 (rc=$rc): $OUT"

echo "── [T11] 하위 작업자 턴은 가로채지 않는다 ──"
new_proj t11; run_prompt "$P" >/dev/null
OUT="$(run_stop "$P" "SubagentStop")"
is_block "$OUT" && fail "하위 작업자 턴을 되돌렸다" || ok "되돌리지 않는다"

echo "── [T12] 다른 SCV 액션이 도는 턴은 가로채지 않는다 ──"
new_proj t12; run_prompt "$P" >/dev/null
mint "$P" "scv:promote"
OUT="$(run_stop "$P")"
is_block "$OUT" && fail "다른 액션이 도는 턴을 되돌렸다" || ok "되돌리지 않는다"

echo "── [T13] 표시줄에 상태와 되돌림 횟수 ──"
new_proj t13
OUT="$(run_prompt "$P")"
grep -q "\[SCV force\]" <<<"$OUT" && ok "표시줄이 나온다" || fail "표시줄 없음: $OUT"
grep -q "0회" <<<"$OUT" && ok "첫 턴은 되돌림 0회로 표시" || fail "횟수 표기 없음"
run_stop "$P" >/dev/null; run_stop "$P" >/dev/null   # 2회 되돌린 채 턴이 끝난다
OUT="$(run_prompt "$P")"
grep -q "2회" <<<"$OUT" && ok "다음 턴 표시줄이 직전 2회를 보고한다" || fail "직전 횟수 미표시: $OUT"
# 새 턴이 시작됐으니 횟수는 0 으로 돌아가 있어야 한다 — 첫 되돌림이 1회차 문구여야
# 하고, 3회차 문구가 나오면 횟수가 턴을 넘어 새고 있다는 뜻이다.
OUT="$(reason_of "$(run_stop "$P")")"
[[ "$OUT" == "$R1" ]] && ok "새 턴의 첫 되돌림이 1회차 문구다 (횟수 초기화됨)" \
  || fail "횟수가 턴을 넘어 샌다 — 나온 문구: $OUT"

echo "── [T14] 끝내 실패한 턴이 기록에 남는다 ──"
new_proj t14
run_prompt "$P" >/dev/null
run_stop "$P" >/dev/null; run_stop "$P" >/dev/null    # 되돌린 채 턴 종료
run_prompt "$P" >/dev/null                            # 다음 턴 시작 → 실패 기록
if grep -rq "강제 실패" "$P/scv/journal" 2>/dev/null; then
  ok "팀 기록에 실패 한 줄이 남는다"
else
  fail "실패 기록 없음: $(ls -R "$P/scv" 2>/dev/null | tr '\n' ' ')"
fi

echo "── [T15] 통과한 턴은 실패로 기록되지 않는다 ──"
new_proj t15
run_prompt "$P" >/dev/null
run_stop "$P" >/dev/null          # 1회 되돌림
mint "$P" "scv:help"              # 그러고 나서 호출
OUT="$(run_stop "$P")"
is_block "$OUT" && fail "호출했는데 또 되돌렸다" || ok "호출 뒤에는 통과한다"
run_prompt "$P" >/dev/null
grep -rq "강제 실패" "$P/scv/journal" 2>/dev/null \
  && fail "성공한 턴을 실패로 기록했다" || ok "실패 기록이 남지 않는다"

echo "── [T16] 키 등록 — 등록부와 예시 파일 ──"
# shellcheck source=/dev/null
source "$SETTINGS_LIB"
grep -q "SCV_FORCE_HELP" <<<"$SCV_PLAIN_KEYS" && ok "공개 키 목록에 있다" || fail "등록부에 없다"
grep -q "SCV_FORCE_HELP" <<<"$SCV_SECRET_KEYS" && fail "비밀 키 목록에 들어갔다" || ok "비밀 키 목록에는 없다"
grep -q '"SCV_FORCE_HELP": "on"' "$EXAMPLE" && ok "예시 파일 기본값 on" || fail "예시 파일에 기본값 없음"
python3 - "$EXAMPLE" <<'PY' && ok "예시 파일 _doc 에 설명이 있다" || fail "_doc 설명 없음"
import json, sys
d = json.load(open(sys.argv[1]))
assert "SCV_FORCE_HELP" in d.get("_doc", {}) and d["_doc"]["SCV_FORCE_HELP"].strip()
PY

echo "── [T17] 가드와 판정부가 같은 영수증 경로를 본다 ──"
# 경로 규칙이 갈라지면 강제가 조용히 무력해진다. 가드가 발행한 곳을 판정부가
# 그대로 찾는지 본다.
new_proj t17
( cd "$P" && printf '{"session_id":"%s","tool_input":{"skill":"scv:help"}}' "$SESSION" \
  | SCV_GUARD_MODE=mint CLAUDE_PLUGIN_ROOT="$CORE" SCV_GUARD_STATE="$STATE" \
    bash "$GUARD_HOOK" >/dev/null 2>&1 )
# shellcheck source=/dev/null
source "$FORCE_LIB"
RK="$(scv_force_project_key "$P")"
RF="$(scv_force_receipt_file "$STATE" "$SESSION" "$RK")"
if [[ -s "$RF" ]] && grep -q "help" "$RF"; then
  ok "가드가 발행한 영수증을 판정부 경로에서 찾는다"
else
  fail "경로가 갈라졌다 — 판정부가 본 곳: $RF"
fi

echo "── [T18] 되돌리는 턴에도 기록은 남는다 ──"
# 처음 구현할 때 되돌림을 내보내며 그 자리에서 훅을 끝냈고, 그 결과 호스트가 상한에서
# 턴을 끊으면 그 턴의 답이 팀 기록에서 통째로 사라졌다. 기존 저널 계약이 그것을
# 잡았으므로, 순서(기록 먼저, 되돌림 나중)를 여기서 못 박는다.
if command -v jq >/dev/null 2>&1; then
  new_proj t18; run_prompt "$P" >/dev/null
  TR="$WORK/t18.jsonl"
  printf '{"type":"assistant","message":{"content":[{"type":"text","text":"되돌려도 남아야 하는 줄"}]}}\n' > "$TR"
  OUT="$( cd "$P" && printf '{"hook_event_name":"Stop","session_id":"%s","transcript_path":"%s"}' "$SESSION" "$TR" \
    | CLAUDE_PLUGIN_ROOT="$CORE" SCV_GUARD_STATE="$STATE" GIT_AUTHOR_NAME="Hook User" bash "$STOP_HOOK" 2>/dev/null )"
  is_block "$OUT" && ok "되돌림 결정이 나온다" || fail "되돌리지 않았다"
  grep -rqF "되돌려도 남아야 하는 줄" "$P/scv/journal" 2>/dev/null \
    && ok "같은 턴의 답이 팀 기록에 남는다" || fail "되돌리느라 기록을 건너뛰었다"
else
  ok "jq 가 없어 건너뛴다 (기록 구간은 jq 를 요구한다)"
fi

echo "── [T19] 판정부는 순수하다 ──"
OUT="$(bash "$CORE/scripts/check-purity.sh" "$CORE/scripts/lib/force-help.sh" 2>&1)"
grep -q '^OK  purity' <<<"$OUT" && ok "순수성 계약 통과" || fail "순수성 위반: $OUT"

echo
echo "─────────────────────────────"
echo "  통과 $PASS · 실패 $FAIL"
[[ $FAIL -eq 0 ]] && { echo "  ALL GATES OK"; exit 0; } || exit 1
