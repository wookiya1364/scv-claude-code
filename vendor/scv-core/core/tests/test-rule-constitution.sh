#!/usr/bin/env bash
# test-rule-constitution.sh — 규칙 헌법이 한 곳에 있고, 어긋난 규칙이 새로 생기지 않는지 잠근다.
#
# scv/SCV.md 의 "Top-level rules" 절이 최상위 층이다: 조항 3~7개 + 출처 + 해소 순서 문단.
# 우선순위를 서술하는 자리는 저장소에서 이 절 하나여야 하고(검사 a, 게이트), 같은 요구가 두
# 문서에 적힌 후보는 기준선보다 늘면 안 된다(검사 b, 래칫). 옛 우선순위 문장 3곳은 참조형이고,
# regression 삭감은 슬러그마다 묻지 않고 결정 표 하나로 묻는다.
#
# 순수부: core/scripts/lib/rule-constitution.sh. 파일 읽기·출력은 여기.
# --self-test: 위반을 심은 사본에서 검사가 반드시 실패하는지 본다 — 통과만 하는 검사는
# 없느니만 못하다 (purity 계약과 같은 이유).
#
# Covers TESTS.md T1–T5·T7·T10 of 20260920-wookiya1364-rule-constitution.
#
# Run: bash core/tests/test-rule-constitution.sh [--self-test]
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE=""
for up in "$HERE/.." "$HERE/../.."; do
  for sub in core vendor/scv-core/core plugins/scv/vendor/scv-core/core; do
    if [[ -f "$up/$sub/scripts/lib/rule-constitution.sh" ]]; then CORE="$(cd "$up/$sub" && pwd)"; break 2; fi
  done
done
[[ -n "$CORE" ]] || { echo "test-rule-constitution: payload not found from $HERE" >&2; exit 1; }
# shellcheck source=../scripts/lib/rule-constitution.sh
source "$CORE/scripts/lib/rule-constitution.sh"

FIX="$CORE/tests/fixtures/rule-constitution"
ALLOWLIST="$FIX/precedence-allowlist.txt"
BASELINE="$FIX/duplicate-baseline.txt"
DUP_ALLOW="$FIX/duplicate-allowlist.txt"
SCVMD_REL="core/template/scv/SCV.md"

PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; [[ $# -gt 1 ]] && printf '%s\n' "$2" | sed 's/^/      /'; FAIL=$((FAIL + 1)); }

# ------------------------------------------------------------------ 효과: 파일 → rows
# 규칙 문서: 프로토콜, 계약, 템플릿(문서 + 훅). rows 의 파일 경로는 core/ 기준 상대 경로에
# "core/" 를 붙인 꼴 — 허용목록·출력이 저장소 어디서 봐도 같은 이름이 되게.
rule_files() {  # <core root>
  find "$1/protocols" "$1/contracts" "$1/template" -type f \( -name '*.md' -o -path '*/hooks/*.sh' \) 2>/dev/null \
    | grep -v '/legacy/' | LC_ALL=C sort
}
collect_rows() {  # <core root> → "<파일>\t<줄>\t<본문>" — 호스트 표기는 정규형(action:)으로
  local root="$1" f rel
  while IFS= read -r f; do
    rel="core/${f#"$root"/}"
    awk -v f="$rel" '{ print f "\t" NR "\t" $0 }' "$f"
  done < <(rule_files "$root") | sed -E "$SCV_RC_CANON_SED"
}
# 이 검사가 원본 저장소에서 도는지, 벤더링된 사본에서 도는지. 검사 (b) 의 기준선은 원본의 산물이라
# 사본(호스트가 문장을 끼워 넣는다)에서는 돌리지 않는다 — (a) 와 문서 검사들은 사본에서도 그대로 돈다.
REPO_ROOT="$(cd "$CORE/.." && pwd)"
IS_CORE_REPO=0; [[ -f "$REPO_ROOT/VERSION" && -f "$REPO_ROOT/core/TEMPLATE_DIGEST" && -d "$REPO_ROOT/scv/archive" ]] && IS_CORE_REPO=1
section_range() {  # <SCV.md 경로> → "<from> <to>" (Top-level rules 절)
  awk '/^## Top-level rules/{f=NR} f&&NR>f&&/^## /{print f, NR-1; exit} END{if(f&&!done)print f, NR}' "$1" | head -1
}
strip_comments() { grep -v '^[[:space:]]*#' "$1" 2>/dev/null | sed -E "$SCV_RC_CANON_SED" || true; }
# 검사 (b) 허용목록 (0.56.0): "<키>\t<이유>" 줄들. 이유 없는 줄은 거부 — 허용은 근거가 있어야 한다.
# 두 필터 모두 파일 → 줄들: allow_keys 는 유효한 줄의 키(정규형), allow_bad 는 이유 없는 줄 그대로.
allow_keys() { grep -v '^[[:space:]]*#' "$1" 2>/dev/null | grep -v '^[[:space:]]*$' | awk -F'\t' 'NF>=2 && $2 !~ /^[[:space:]]*$/ {print $1}' | sed -E "$SCV_RC_CANON_SED" || true; }
allow_bad()  { grep -v '^[[:space:]]*#' "$1" 2>/dev/null | grep -v '^[[:space:]]*$' | awk -F'\t' 'NF<2 || $2 ~ /^[[:space:]]*$/' || true; }

run_checks() {  # <core root> <baseline text> → 위반 두 묶음을 전역에 둔다
  local root="$1" base="$2" rows scvmd range from to allow normative keys dups
  rows="$(collect_rows "$root")"
  scvmd="$root/template/scv/SCV.md"
  range="$(section_range "$scvmd")"; from="${range%% *}"; to="${range##* }"
  allow="$(strip_comments "$ALLOWLIST")"
  A_VIOLATIONS="$(scv_rc_precedence_violations "$rows" "$SCVMD_REL" "${from:-0}" "${to:-0}" "$allow")"
  keys="$(printf '%s\n' "$rows" | scv_rc_normative_rows | scv_rc_demand_keys)"
  dups="$(printf '%s\n' "$keys" | scv_rc_duplicate_keys)"
  B_CANDIDATES="$dups"
  B_ALLOWED="$(scv_rc_allowed_out "$dups" "$(allow_keys "$DUP_ALLOW")")"
  B_NEW="$(scv_rc_ratchet_new "$B_ALLOWED" "$base")"
}

# ------------------------------------------------------------------ --self-test
if [[ "${1:-}" == "--self-test" ]]; then
  echo "── self-test: 심어 둔 위반에서 검사가 실패하는가 ──"
  TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
  for d in protocols contracts template; do cp -R "$CORE/$d" "$TMP/$d"; done
  base="$(strip_comments "$BASELINE")"
  run_checks "$TMP" "$base"
  [[ -z "$A_VIOLATIONS" ]] && ok "사본 그대로: 검사 a 통과" || fail "사본 그대로인데 검사 a 가 실패" "$A_VIOLATIONS"
  [[ -z "$B_NEW" ]]        && ok "사본 그대로: 검사 b 통과" || fail "사본 그대로인데 검사 b 가 실패" "$B_NEW"
  # 호스트 표기로 바뀐 사본에서도 허용목록이 맞아야 한다 (0.54.1 — 코덱스 사본에서 붉던 것)
  sed -i.bak -E 's/action:([a-z-]+)/$host:\1/g' "$TMP/protocols/promote.md" && rm -f "$TMP/protocols/promote.md.bak"
  run_checks "$TMP" "$base"
  [[ -z "$A_VIOLATIONS" ]] && ok "호스트 접두어로 표기가 바뀐 사본에서도 검사 a 통과" || fail "호스트 표기 사본에서 허용목록이 어긋난다" "$A_VIOLATIONS"
  # (a) 우선순위 문장을 프로토콜 사본에 심는다
  cat "$FIX/inject-precedence.txt" >> "$TMP/protocols/status.md"
  run_checks "$TMP" "$base"
  if [[ -n "$A_VIOLATIONS" && "$A_VIOLATIONS" == *"takes priority"* ]]; then ok "심은 우선순위 문장을 검사 a 가 잡았다"; else fail "심은 우선순위 문장을 검사 a 가 놓쳤다"; fi
  # (b) 같은 규범 문장을 두 번째 파일에 심는다 → 후보가 하나 는다
  cat "$FIX/inject-duplicate.txt" >> "$TMP/protocols/status.md"
  cat "$FIX/inject-duplicate.txt" >> "$TMP/protocols/deck.md"
  run_checks "$TMP" "$base"
  if [[ -n "$B_NEW" ]]; then ok "심은 중복 요구를 검사 b 가 잡았다 (새 키: $(printf '%s' "$B_NEW" | head -1))"; else fail "심은 중복 요구를 검사 b 가 놓쳤다"; fi
  # (b) 허용목록 (0.56.0): 심은 키를 허용하면 사라지고, 다른 키는 그대로 남는다 — 순수 함수 한 번
  planted="$(printf '%s' "$B_NEW" | head -1)"
  left="$(scv_rc_allowed_out "$B_NEW" "$planted")"
  if [[ -n "$planted" && "$left" != *"$planted"* ]]; then ok "허용목록에 넣은 키는 후보에서 빠진다"; else fail "허용목록이 후보를 거르지 못한다" "$left"; fi
  [[ "$(scv_rc_allowed_out $'a b c d e f\ng h i j k l' 'zzz')" == $'a b c d e f\ng h i j k l' ]] && ok "허용목록에 없는 키는 그대로" || fail "allowed_out 이 무관한 키를 지운다"
  printf '# c\ngood key here six words long\tbecause\nbad key without reason at all\n' > "$TMP/allow.txt"
  k="$(allow_keys "$TMP/allow.txt")"; b="$(allow_bad "$TMP/allow.txt")"
  if [[ "$k" == "good key here six words long" && "$b" == *"bad key without reason"* ]]; then ok "이유 없는 허용목록 줄은 거부된다"; else fail "허용목록 이유 검사" "keys=$k bad=$b"; fi
  echo; echo "self-test: $PASS passed, $FAIL failed"
  (( FAIL == 0 )) || exit 1
  exit 0
fi

# ------------------------------------------------------------------ 본 검사
SCVMD="$CORE/template/scv/SCV.md"
SECTION="$(awk '/^## Top-level rules/{f=1} f&&/^## /&&!/^## Top-level rules/{exit} f' "$SCVMD")"

echo "── T1. 헌법 조항 수와 출처 ──"
n_clauses="$(printf '%s\n' "$SECTION" | grep -cE '^[0-9]+\. ')"
n_sources="$(printf '%s\n' "$SECTION" | grep -c 'Source:')"
if (( n_clauses >= 3 && n_clauses <= 7 )); then ok "조항 ${n_clauses}개 (허용 3~7)"; else fail "조항 수 ${n_clauses} — 허용 3~7"; fi
if (( n_sources >= n_clauses )); then ok "모든 조항에 Source: 가 있다 (${n_sources})"; else fail "Source: 가 조항 수보다 적다 (${n_sources} < ${n_clauses})"; fi
printf '%s\n' "$SECTION" | grep -q 'Resolution order' && ok "해소 순서 문단이 있다" || fail "해소 순서 문단 없음"

echo "── T4. 사용자 지침 양보 조항 ──"
printf '%s\n' "$SECTION" | grep -q 'Yield to the user' && printf '%s\n' "$SECTION" | grep -q 'one line' \
  && ok "7조: 사용자에게 양보하고 한 줄로 밝힌다" || fail "양보 조항 없음"

echo "── T3. 옛 우선순위 문장 3곳 → 참조 ──"
grep -q 'override the others, but never the pipeline rule' "$CORE/protocols/codegen.md" \
  && fail "codegen.md 에 옛 override 문장이 남아 있다" || ok "codegen.md 옛 문장 없음"
grep -q 'Top-level rules' "$CORE/protocols/codegen.md" && ok "codegen.md 가 Top-level rules 를 참조" || fail "codegen.md 참조 없음"
grep -q '계약이 검사보다 우선한다' "$CORE/contracts/purity.md" \
  && fail "purity.md 에 옛 우선 문장이 남아 있다" || ok "purity.md 옛 문장 없음"
grep -q 'Top-level rules' "$CORE/contracts/purity.md" && ok "purity.md 가 Top-level rules 를 참조" || fail "purity.md 참조 없음"

echo "── T10. 충돌 A — regression 삭감이 결정 표 하나로 묻는다 ──"
REG="$CORE/protocols/regression.md"
grep -q "Don't bundle multiple failures into one triage" "$REG" && fail "옛 '슬러그마다 질문' Never 항목이 남아 있다" || ok "옛 Never 항목 없음"
grep -q 'ask the user one independent question' "$REG" && fail "옛 Step 2 문장이 남아 있다" || ok "옛 Step 2 문장 없음"
grep -q 'one decisions table' "$REG" && grep -q 'replaces the earlier' "$REG" && ok "새 규칙 + 대체 선언" || fail "새 규칙 또는 대체 선언 없음"
grep -q 'must NOT ask interactive questions' "$REG" && ok "--ci 규칙 그대로" || fail "--ci 규칙이 사라졌다"

echo "── T2. 검사 a — 해소 순서 서술은 한 곳뿐 ──"
[[ -f "$BASELINE" ]] && base="$(strip_comments "$BASELINE")" || base=""
run_checks "$CORE" "$base"
[[ -z "$A_VIOLATIONS" ]] && ok "Top-level rules 절 밖의 비참조 우선순위 문장 0건" \
  || fail "우선순위를 서술하는 줄이 절 밖에 있다 — 참조로 바꾸거나 허용목록에 이유와 함께 적으라" "$A_VIOLATIONS"

echo "── T5. 검사 b — 중복 요구 래칫 ──"
if (( ! IS_CORE_REPO )); then
  echo "  – 벤더링된 사본 — 기준선은 원본 저장소의 산물이라 건너뛴다 (호스트가 끼워 넣는 문장이 후보로 잡힌다)"
elif [[ ! -f "$BASELINE" ]]; then
  printf '# 두 파일 이상에 적힌 규범 문장 키(앞 8단어). 첫 실행에 고정 — 줄면 갱신, 늘면 실패.\n%s\n' "$B_CANDIDATES" > "$BASELINE"
  ok "기준선이 없어 만들었다 ($(printf '%s\n' "$B_CANDIDATES" | grep -c .)건) — 첫 실행"
elif [[ -n "$(allow_bad "$DUP_ALLOW")" ]]; then
  fail "허용목록 줄에 이유가 없다 — <키>\\t<이유> 로 적으라" "$(allow_bad "$DUP_ALLOW")"
elif [[ -z "$B_NEW" ]]; then
  ok "중복 요구 후보 $(printf '%s\n' "$B_CANDIDATES" | grep -c .)건 (허용 $(( $(printf '%s\n' "$B_CANDIDATES" | grep -c .) - $(printf '%s\n' "$B_ALLOWED" | grep -c .) ))건 제외), 기준선 이하"
else
  fail "중복 요구 후보가 기준선보다 늘었다 — 한 곳으로 모으거나(4조) 의도된 반복이면 리뷰 뒤 기준선 갱신" "$B_NEW"
fi

echo; echo "test-rule-constitution: $PASS passed, $FAIL failed"
(( FAIL == 0 )) || exit 1
