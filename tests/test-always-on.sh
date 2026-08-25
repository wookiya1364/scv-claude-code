#!/usr/bin/env bash
# test-always-on.sh — 일반 대화에도 SCV 가 끼어든다 (SCV_ALWAYS_ON).
#
# 명령을 쳐야만 SCV 가 움직이면, 스킬 설명의 권고는 호스트 모델이 대부분
# 무시한다 (실측). 훅 stdout 은 매 턴 모델에 닿는 유일한 통로다 — 스위치가
# 꺼져 있지 않으면 그 길로 라우팅 지시를 싣는다. off 만 끈다.
#
# Covers TESTS.md T1–T5 of 20260825-wookiya1364-scv-always-on.
#
# Run: bash core/tests/test-always-on.sh
set -uo pipefail

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CORE="$HERE/.."
HOOK="$CORE/template/hooks/on-user-prompt.sh"
SETTINGS_LIB="$CORE/scripts/lib/settings.sh"
EXAMPLE="$CORE/template/scv/scv_settings.example.json"

PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS+1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL+1)); }

[[ -f "$HOOK" ]] || { echo "✖ 훅이 없다: $HOOK"; exit 1; }

WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# 훅 실행 헬퍼: <프로젝트 폴더> [설정 JSON 내용]
run_hook() {
  local proj="$1" settings="${2:-}"
  mkdir -p "$proj/scv"
  [[ -n "$settings" ]] && printf '%s\n' "$settings" > "$proj/scv/scv_settings.json"
  ( cd "$proj" && printf '{"prompt":"hello"}' \
    | CLAUDE_PLUGIN_ROOT="$CORE" bash "$HOOK" 2>/dev/null )
}

echo "── [T1] 기본 ON — 키가 없으면 라우팅 블록 ──"
OUT="$(run_hook "$WORK/t1")"
grep -q "\[SCV always-on\]" <<<"$OUT" && ok "라우팅 블록이 나온다" || fail "블록 없음: $OUT"
grep -q "Mode" <<<"$OUT" && ok "Mode 판정 지시 포함" || fail "Mode 지시 없음"
grep -q "SCV_ALWAYS_ON=off" <<<"$OUT" && ok "끄는 법 한 줄 포함" || fail "끄는 법 없음"

echo "── [T2] off 만 끈다 ──"
OUT="$(run_hook "$WORK/t2a" '{"SCV_ALWAYS_ON": "off"}')"
grep -q "\[SCV always-on\]" <<<"$OUT" && fail "off 인데 블록이 나온다" || ok "off → 블록 없음"
OUT="$(run_hook "$WORK/t2b" '{"SCV_ALWAYS_ON": "OFF"}')"
grep -q "\[SCV always-on\]" <<<"$OUT" && fail "OFF(대문자)인데 블록이 나온다" || ok "OFF(대소문자 무관) → 블록 없음"
OUT="$(run_hook "$WORK/t2c" '{"SCV_ALWAYS_ON": "on"}')"
grep -q "\[SCV always-on\]" <<<"$OUT" && ok "on → 블록 있음" || fail "on 인데 블록 없음"
OUT="$(run_hook "$WORK/t2d" '{"SCV_ALWAYS_ON": "maybe"}')"
grep -q "\[SCV always-on\]" <<<"$OUT" && ok "이상값 → 켜짐 (off 만 끈다)" || fail "이상값이 꺼 버렸다"

echo "── [T3] 쉬운말 스위치와 독립 ──"
OUT="$(run_hook "$WORK/t3a" '{"SCV_PLAIN_LANGUAGE": "off"}')"
grep -q "\[SCV plain language\]" <<<"$OUT" && fail "plain off 인데 쉬운말 블록이 있다" || ok "쉬운말 블록 없음"
grep -q "\[SCV always-on\]" <<<"$OUT" && ok "라우팅 블록은 있다" || fail "plain off 가 라우팅까지 껐다"
OUT="$(run_hook "$WORK/t3b" '{"SCV_ALWAYS_ON": "off"}')"
grep -q "\[SCV plain language\]" <<<"$OUT" && ok "always off 여도 쉬운말 블록은 있다" || fail "always off 가 쉬운말까지 껐다"

echo "── [T4] 비 SCV 폴더는 침묵 ──"
mkdir -p "$WORK/t4"
OUT="$( cd "$WORK/t4" && printf '{"prompt":"hello"}' | CLAUDE_PLUGIN_ROOT="$CORE" bash "$HOOK" 2>/dev/null )"
rc=$?
[[ $rc -eq 0 && -z "$OUT" ]] && ok "scv/ 없음 → 출력 없음, exit 0" || fail "침묵 계약 위반 (rc=$rc): $OUT"

echo "── [T5] 키 등록 — 등록부와 예시 파일 ──"
# shellcheck source=/dev/null
source "$SETTINGS_LIB"
grep -q "SCV_ALWAYS_ON" <<<"$SCV_PLAIN_KEYS" && ok "공개 키 목록에 있다" || fail "SCV_PLAIN_KEYS 에 없다"
grep -q "SCV_ALWAYS_ON" <<<"$SCV_SECRET_KEYS" && fail "비밀 키 목록에 들어갔다" || ok "비밀 키 목록에는 없다"
grep -q '"SCV_ALWAYS_ON": "on"' "$EXAMPLE" && ok "예시 파일 기본값 on" || fail "예시 파일에 기본값 없음"
python3 - "$EXAMPLE" <<'PY' && ok "예시 파일 _doc 에 설명이 있다" || fail "_doc 설명 없음"
import json,sys
d=json.load(open(sys.argv[1]))
assert "SCV_ALWAYS_ON" in d.get("_doc",{}) and d["_doc"]["SCV_ALWAYS_ON"].strip()
PY

echo
echo "─────────────────────────────"
echo "  통과 $PASS · 실패 $FAIL"
[[ $FAIL -eq 0 ]] && { echo "  ALL GATES OK"; exit 0; } || exit 1
