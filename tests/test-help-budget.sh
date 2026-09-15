#!/usr/bin/env bash
# test-help-budget.sh — help 규약의 매 턴 비용 상한과 부속 파일 참조 검사 (v0.48.0+).
#
# 왜 있나: help 는 매 턴 강제로 불린다. 본문 28KB 에 보조 스크립트 출력 10KB, 훅 주입 5KB 가
# 매 턴 실렸다(≈17k 토큰). 분기 전용 본문을 protocols/help/*.md 로 빼고, 스크립트의 대화 모드
# 출력을 파싱 머리만 남기고, 매 턴 합에 상한을 둔다. 이 검사가 그 셋을 기계로 본다 —
# 상한이 없으면 두 달 뒤 본문은 다시 자란다.
#
# 무엇을 보나:
#   T1  help.md 본문 ≤ SCV_HELP_BODY_MAX (기본 14000)
#   T2  부속 파일 다섯이 있고, 본문이 각각을 정확히 한 번 참조한다 (고아 참조·고아 파일·중복 없음)
#   T3  참조 줄은 "Read … now" 명령형 한 문장
#   T4  부속 파일에 쉬운 말 절·언어 절이 없고, 경로 자리표시자(CLAUDE_PLUGIN_ROOT)가 없다 —
#       부속 파일은 SKILL.md 와 달리 호스트가 자리표시자를 펼치지 않는다 (0.48.1)
#   T10 help.sh --with-context 는 파싱 머리만 (진단·배너·archive 목록 없음, ≤ 1000B);
#       인자 없음 출력은 진단을 품고, 위치 인자 출력은 ARCHIVE_INDEX 를 품는다
#   T11 help.sh --archive-index 는 파싱 머리 + ARCHIVE_INDEX 만; 규약 파싱 목록엔 ARCHIVE_INDEX 없음
#   T12 매 턴 스택(훅 출력 + help.md + --with-context 출력) ≤ SCV_HELP_TURN_MAX (기본 18000)
#   합계(본문 + 부속 파일) ≤ SCV_HELP_TOTAL_MAX (기본 30000) — 내용 폭증 방지
#
# 순수부: 문자열을 받아 위반 줄을 내는 함수들 (@pure). 파일 읽기·스크립트 실행은 바깥층.
#
# Covers TESTS.md T1·T2·T3·T4·T10·T11·T12 of 20260914-wookiya1364-help-body-diet.
#
# Run: bash core/tests/test-help-budget.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE=""
for up in "$HERE/.." "$HERE/../.."; do
  for sub in core vendor/scv-core/core plugins/scv/vendor/scv-core/core; do
    if [[ -f "$up/$sub/scripts/lib/settings.sh" ]]; then CORE="$(cd "$up/$sub" && pwd)"; break 2; fi
  done
done
[[ -n "$CORE" ]] || { echo "test-help-budget: payload not found from $HERE" >&2; exit 1; }

PASS=0; FAIL=0; SKIP=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "  – SKIP: $1"; SKIP=$((SKIP + 1)); }

BODY_MAX="${SCV_HELP_BODY_MAX:-14000}"
TOTAL_MAX="${SCV_HELP_TOTAL_MAX:-30000}"
TURN_MAX="${SCV_HELP_TURN_MAX:-18000}"
WC_MAX="${SCV_HELP_WITH_CONTEXT_MAX:-1000}"
SUBS="language-setup legacy-migration hydrate archive-search promote-handoff"

PROTO="$CORE/protocols/help.md"
SUBDIR="$CORE/protocols/help"
HELP_SH="$CORE/scripts/help.sh"
PROMPT_HOOK="$CORE/template/hooks/on-user-prompt.sh"

# ---------------------------------------------------------------- 순수부
# @pure
# 본문 문자열 → 참조된 부속 파일 이름들 (한 줄에 하나, 참조 순서·중복 유지).
# 자리표시자가 무엇으로 치환됐든 "protocols/help/<name>.md" 꼴만 본다.
scv_help_refs() {
  local text="${1:-}" line rest name
  while IFS= read -r line; do
    rest="$line"
    while [[ "$rest" == *protocols/help/*.md* ]]; do
      rest="${rest#*protocols/help/}"
      name="${rest%%.md*}"
      [[ "$name" == *[!a-z0-9-]* || -z "$name" ]] || printf '%s\n' "$name"
      rest="${rest#*.md}"
    done
  done <<<"$text"
}

# @pure
# 참조 목록(줄) + 기대 이름 목록(공백 구분) + 실제 파일 이름 목록(공백 구분) → 위반 줄들.
scv_help_check_refs() {
  local refs="${1:-}" expected="${2:-}" actual="${3:-}" n cnt
  for n in $expected; do
    cnt=0
    while IFS= read -r r; do [[ "$r" == "$n" ]] && cnt=$((cnt + 1)); done <<<"$refs"
    (( cnt == 1 )) || printf 'ref-count %s=%s (expected 1)\n' "$n" "$cnt"
    [[ " $actual " == *" $n "* ]] || printf 'missing-file %s\n' "$n"
  done
  for n in $actual; do
    [[ " $expected " == *" $n "* ]] || printf 'orphan-file %s\n' "$n"
  done
  while IFS= read -r r; do
    [[ -z "$r" || " $expected " == *" $r "* ]] || printf 'orphan-ref %s\n' "$r"
  done <<<"$refs"
}

# @pure
# 바이트 수 + 상한 + 이름 → 위반 줄 (없으면 빈 출력).
scv_help_budget() {
  local bytes="${1:-0}" max="${2:-0}" label="${3:-}"
  (( bytes <= max )) || printf 'over-budget %s=%s (max %s)\n' "$label" "$bytes" "$max"
}

# @pure
# 본문 문자열 → 부속 파일을 참조하는 줄 중 "Read … now" 명령형이 아닌 줄들.
scv_help_pointer_bad() {
  local text="${1:-}" line
  while IFS= read -r line; do
    [[ "$line" == *protocols/help/*.md* ]] || continue
    [[ "$line" == *Read* && "$line" == *now* ]] || printf '%s\n' "$line"
  done <<<"$text"
}

# @pure
# 부속 파일 문자열 + 이름 → 위반 줄들: 규칙 중복(쉬운 말 절 · 언어 절) · 경로 자리표시자
# (부속 파일은 호스트가 자리표시자를 펼치지 않는다 — 0.48.0 실사용에서 발견, 0.48.1).
scv_help_sub_clean() {
  local text="${1:-}" name="${2:-}" line
  while IFS= read -r line; do
    case "$line" in
      "## Plain language first"*) printf 'dup-rule %s: plain-language section\n' "$name" ;;
      "## Language preference"*)  printf 'dup-rule %s: language section\n' "$name" ;;
      *CLAUDE_PLUGIN_ROOT*)            printf 'placeholder %s: CLAUDE_PLUGIN_ROOT in a branch file (not expanded by the host; write the path plugin-root-relative)\n' "$name" ;;
    esac
  done <<<"$text"
}
# ---------------------------------------------------------------- /순수부

[[ -f "$PROTO" ]] || { echo "help protocol not found: $PROTO" >&2; exit 1; }
BODY="$(cat "$PROTO")"
BODY_BYTES=$(wc -c < "$PROTO" | tr -d '[:space:]')

echo "── [T1] 본문 상한 ──"
v="$(scv_help_budget "$BODY_BYTES" "$BODY_MAX" help.md)"
[[ -z "$v" ]] && ok "help.md ${BODY_BYTES}B ≤ ${BODY_MAX}B" || fail "$v"
v="$(scv_help_budget 99999 "$BODY_MAX" fake)"
[[ -n "$v" ]] && ok "상한 초과를 잡는다" || fail "상한 초과를 못 잡는다"

echo "── [T2] 부속 파일 다섯 — 존재·참조 1회 ──"
ACTUAL=""
if [[ -d "$SUBDIR" ]]; then
  for f in "$SUBDIR"/*.md; do [[ -f "$f" ]] && ACTUAL="$ACTUAL $(basename "$f" .md)"; done
fi
REFS="$(scv_help_refs "$BODY")"
v="$(scv_help_check_refs "$REFS" "$SUBS" "${ACTUAL# }")"
[[ -z "$v" ]] && ok "다섯 파일 존재 · 본문 참조 각 1회 · 고아 없음" || fail "$(printf '%s' "$v" | tr '\n' ';')"
v="$(scv_help_check_refs "$(printf 'hydrate\nhydrate\n')" "hydrate archive-search" "hydrate")"
grep -q "ref-count hydrate=2" <<<"$v" && grep -q "missing-file archive-search" <<<"$v" \
  && ok "중복 참조·빠진 파일을 잡는다" || fail "순수부가 위반을 못 잡는다: $v"

echo "── [T3] 포인터는 명령형 한 문장 ──"
v="$(scv_help_pointer_bad "$BODY")"
[[ -z "$v" ]] && ok "참조 줄 전부 'Read … now'" || fail "명령형 아님: $(printf '%s' "$v" | head -2)"

echo "── [T4] 부속 파일 청결 ──"
TOTAL_BYTES=$BODY_BYTES
for n in $SUBS; do
  f="$SUBDIR/$n.md"
  if [[ -f "$f" ]]; then
    v="$(scv_help_sub_clean "$(cat "$f")" "$n")"
    [[ -z "$v" ]] && ok "$n: 규칙 중복 없음" || fail "$v"
    TOTAL_BYTES=$((TOTAL_BYTES + $(wc -c < "$f" | tr -d '[:space:]')))
  else
    fail "$n.md 없음"
  fi
done
v="$(scv_help_budget "$TOTAL_BYTES" "$TOTAL_MAX" total)"
[[ -z "$v" ]] && ok "본문+부속 합 ${TOTAL_BYTES}B ≤ ${TOTAL_MAX}B" || fail "$v"

echo "── [T10] help.sh — 대화 모드는 파싱 머리만, 다른 두 형태는 그대로 ──"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-help-budget.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/p/scv/raw" "$WORK/p/scv/archive/20260420-wookiya1364-sample-feature"
printf -- '---\ntitle: "Sample Feature"\nslug: 20260420-wookiya1364-sample-feature\ncreated_at: 2026-04-20\nstatus: done\n---\n# Sample\n' \
  > "$WORK/p/scv/archive/20260420-wookiya1364-sample-feature/PLAN.md"
WC_OUT="$(cd "$WORK/p" && bash "$HELP_SH" --with-context 2>/dev/null)"
NOARG_OUT="$(cd "$WORK/p" && bash "$HELP_SH" 2>/dev/null)"
POS_OUT="$(cd "$WORK/p" && bash "$HELP_SH" "search refund" 2>/dev/null)"
grep -q "^ARG_CONTEXT: provided" <<<"$WC_OUT" && grep -q "^UNFINISHED_CONVERSATIONS:" <<<"$WC_OUT" \
  && grep -q "^LEGACY_CONVERSATIONS:" <<<"$WC_OUT" && ok "--with-context: 파싱 머리 있음" || fail "--with-context: 파싱 머리 빠짐"
for bad in "Current project diagnosis" "Dependency check:" "╔" "ARCHIVE_INDEX:"; do
  grep -qF -- "$bad" <<<"$WC_OUT" && fail "--with-context 에 '$bad' 가 남아 있다" || ok "--with-context: '$bad' 없음"
done
WC_BYTES=$(printf '%s' "$WC_OUT" | wc -c | tr -d '[:space:]')
v="$(scv_help_budget "$WC_BYTES" "$WC_MAX" with-context)"
[[ -z "$v" ]] && ok "--with-context ${WC_BYTES}B ≤ ${WC_MAX}B" || fail "$v"
grep -q "Current project diagnosis" <<<"$NOARG_OUT" && grep -q "Dependency check:" <<<"$NOARG_OUT" \
  && ok "인자 없음: 진단·의존성 표 그대로" || fail "인자 없음 출력이 바뀌었다"
grep -q "^ARCHIVE_INDEX:" <<<"$POS_OUT" && grep -q "20260420-wookiya1364-sample-feature" <<<"$POS_OUT" \
  && ok "위치 인자: ARCHIVE_INDEX 그대로" || fail "위치 인자 출력이 바뀌었다"

echo "── [T11] archive 목록은 요청할 때만 ──"
AI_OUT="$(cd "$WORK/p" && bash "$HELP_SH" --archive-index 2>/dev/null)"
grep -q "^ARG_CONTEXT: provided" <<<"$AI_OUT" && grep -q "^ARCHIVE_INDEX:" <<<"$AI_OUT" \
  && grep -q "20260420-wookiya1364-sample-feature | Sample Feature | 2026-04-20" <<<"$AI_OUT" \
  && ok "--archive-index: 파싱 머리 + 목록" || fail "--archive-index 출력이 기대와 다르다"
grep -q "Current project diagnosis" <<<"$AI_OUT" && fail "--archive-index 에 진단이 있다" || ok "--archive-index: 진단·배너 없음"
awk '/^Parse the helper output:/{f=1} f&&/^## /{exit} f' "$PROTO" | grep -q 'ARCHIVE_INDEX:' \
  && fail "규약 파싱 목록에 ARCHIVE_INDEX 줄이 남아 있다" || ok "규약 파싱 목록에 ARCHIVE_INDEX 없음"
if [[ -f "$SUBDIR/archive-search.md" ]]; then
  grep -q -- "--archive-index" "$SUBDIR/archive-search.md" && ok "archive 검색 분기가 --archive-index 를 부른다" \
    || fail "archive-search.md 가 --archive-index 를 모른다"
else
  fail "archive-search.md 없음"
fi

echo "── [T12] 매 턴 스택 합 ──"
if [[ -f "$PROMPT_HOOK" ]]; then
  HOOK_OUT="$(cd "$WORK/p" && printf '{"prompt":"안녕","session_id":"t"}' \
    | CLAUDE_PLUGIN_ROOT="$CORE" SCV_GUARD_STATE="$WORK/state" bash "$PROMPT_HOOK" 2>/dev/null)"
  HOOK_BYTES=$(printf '%s' "$HOOK_OUT" | wc -c | tr -d '[:space:]')
  TURN=$((HOOK_BYTES + BODY_BYTES + WC_BYTES))
  echo "  · hook=${HOOK_BYTES}B body=${BODY_BYTES}B with-context=${WC_BYTES}B → turn=${TURN}B"
  v="$(scv_help_budget "$TURN" "$TURN_MAX" turn)"
  [[ -z "$v" ]] && ok "매 턴 스택 ${TURN}B ≤ ${TURN_MAX}B" || fail "$v"
else
  skip "프롬프트 훅 없음 — 매 턴 합 생략"
fi

echo "── [T13] 순수부 선언 ──"
if [[ -f "$CORE/scripts/check-purity.sh" ]]; then
  OUT="$(bash "$CORE/scripts/check-purity.sh" "${BASH_SOURCE[0]}" 2>&1)"
  grep -q '^OK  purity' <<<"$OUT" && ok "순수성 계약 통과" || fail "순수성 위반: $(printf '%s' "$OUT" | head -3)"
else
  skip "check-purity.sh 없음"
fi

echo "─────────────────────────────"
echo "  통과 $PASS · 실패 $FAIL · 생략 $SKIP"
[[ $FAIL -eq 0 ]] && { echo "  ALL GATES OK"; exit 0; } || exit 1
