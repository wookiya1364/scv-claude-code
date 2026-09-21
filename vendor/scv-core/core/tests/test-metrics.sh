#!/usr/bin/env bash
# test-metrics.sh — 과정 계기판(metrics.sh)이 기존 파일만 읽어 지표 넷을 결정적으로 찍는지 본다.
#
# 계획: scv/archive/20260921-wookiya1364-process-metrics/TESTS.md (T1~T6; T7 은 CI)
# 계약: core/contracts/purity.md
#
# 판정은 전부 문자열 비교다. 픽스처는 손으로 계산한 기대값과 전수 대조하고,
# 실제 저장소에서는 "에러 없이 표가 나오고 두 번이 같다" 만 본다 — 숫자는 보관할
# 때마다 바뀌므로 고정하지 않는다.
#
# Run: bash core/tests/test-metrics.sh
set -uo pipefail

CORE_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
REPO_ROOT="$( cd "$CORE_ROOT/.." && pwd )"
SCRIPT="$CORE_ROOT/scripts/metrics.sh"
LIB="$CORE_ROOT/scripts/lib/metrics.sh"
FIX="$CORE_ROOT/tests/fixtures/metrics"
FIX_SCV="$FIX/scv"

PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }

[[ -f "$SCRIPT" ]] || { echo "✖ 스크립트가 없다: $SCRIPT"; exit 1; }
[[ -f "$LIB" ]]    || { echo "✖ 순수부가 없다: $LIB"; exit 1; }
[[ -d "$FIX_SCV" ]] || { echo "✖ 픽스처가 없다: $FIX_SCV"; exit 1; }

# 픽스처 해시 — T5 가 전후를 대조한다 (파일 목록 + 내용)
fixture_digest() {
  ( cd "$FIX" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do
      printf '%s\n' "$f"; cat "$f"
    done ) | shasum | awk '{print $1}'
}
DIGEST_BEFORE="$(fixture_digest)"
GIT_BEFORE="$(cd "$REPO_ROOT" && git status --porcelain 2>/dev/null)"

echo "T1. 픽스처 전수 대조 — 지표 네 개와 적용 범위"
OUT="$(SCV_DIR="$FIX_SCV" bash "$SCRIPT" 2>&1)"; RC=$?
if [[ $RC -eq 0 ]] && diff -u "$FIX/expected.txt" <(printf '%s\n' "$OUT") >/dev/null; then
  ok "OK [T1] table matches"
else
  fail "[T1] 표가 기대와 다르다 (exit $RC)"
  diff -u "$FIX/expected.txt" <(printf '%s\n' "$OUT") | sed 's/^/      /'
fi
OUT_TSV="$(SCV_DIR="$FIX_SCV" bash "$SCRIPT" --tsv 2>&1)"; RC=$?
if [[ $RC -eq 0 ]] && diff -u "$FIX/expected.tsv" <(printf '%s\n' "$OUT_TSV") >/dev/null; then
  ok "OK [T1] tsv matches"
else
  fail "[T1] --tsv 가 기대와 다르다 (exit $RC)"
  diff -u "$FIX/expected.tsv" <(printf '%s\n' "$OUT_TSV") | sed 's/^/      /'
fi

echo
echo "T2. 반복 가능성"
R1="$(SCV_DIR="$FIX_SCV" bash "$SCRIPT" 2>&1)"
R2="$(SCV_DIR="$FIX_SCV" bash "$SCRIPT" 2>&1)"
R3="$(SCV_DIR="$FIX_SCV" bash "$SCRIPT" 2>&1)"
if [[ "$R1" == "$R2" && "$R2" == "$R3" ]]; then ok "OK [T2] 3/3 identical"; else fail "[T2] 실행마다 출력이 다르다"; fi

echo
echo "T3. 순수 함수 전수 검사 (경계값)"
# shellcheck source=../scripts/lib/metrics.sh
source "$LIB"
N=0; BAD=0
case_eq() {  # <이름> <기대> <실제>
  N=$((N + 1))
  if [[ "$2" == "$3" ]]; then :; else BAD=$((BAD + 1)); echo "      ✖ $1: expected [$2] got [$3]"; fi
}
# civilToMinutes — 기준값은 python datetime 으로 독립 계산 (분)
case_eq "civil 2026-01-01" "29453760" "$(scv_mx_civil_to_minutes '2026-01-01 00:00')"
case_eq "civil 2026-03-01 (비윤년, 59일)" "$((29453760 + 59 * 1440))" "$(scv_mx_civil_to_minutes '2026-03-01 00:00')"
case_eq "civil 윤년 2024-02-28→03-01 = 2일" "$((2 * 1440))" "$(( $(scv_mx_civil_to_minutes '2024-03-01 00:00') - $(scv_mx_civil_to_minutes '2024-02-28 00:00') ))"
case_eq "civil 2026-09-11 10:00" "29818680" "$(scv_mx_civil_to_minutes '2026-09-11 10:00')"
case_eq "civil 형식 오류 → 빈 값" "" "$(scv_mx_civil_to_minutes 'YYYY-MM-DD HH:MM')"
case_eq "civil 13월 → 빈 값" "" "$(scv_mx_civil_to_minutes '2026-13-01 00:00')"
# countTurns
case_eq "turns 0" "0" "$(scv_mx_count_turns $'# 제목\n본문')"
case_eq "turns 1" "1" "$(scv_mx_count_turns $'## Turn 1 — t\n**User**: a')"
case_eq "turns 6" "6" "$(scv_mx_count_turns $'## Turn 1 — a\n## Turn 2 — b\n## Turn 3 — c\n## Turn 4 — d\n## Turn 5 — e\n## Turn 6 — f')"
case_eq "turns 코드 블록 안은 제외" "2" "$(scv_mx_count_turns $'## Turn 1 — a\n```\n## Turn 9 — x\n```\n## Turn 2 — b')"
case_eq "turns 본문 속 낱말은 제외" "1" "$(scv_mx_count_turns $'## Turn 1 — a\n이 문장은 ## Turn 5 를 담고 있다')"
# resolveConvPath
case_eq "resolve 두 후보" $'conversations/x.md\nconversations/archive/x.md' "$(scv_mx_resolve_conv_path 'scv/conversations/x.md')"
case_eq "resolve 빈 경로 → 빈 값" "" "$(scv_mx_resolve_conv_path '')"
# parseDecisions
DEC=$'## [YYYY-MM-DD HH:MM] a — 템플릿\n\n- verdict: adopted\n- refs: scv/promote/T/PLAN.md\n\n## [2026-09-01 10:00] a — 승인\n\n- verdict: adopted\n- refs: scv/promote/S1/PLAN.md\n\n## [2026-09-02 10:00] a — 보관\n\n- verdict: archived\n- path delta: as planned\n- refs: scv/archive/S1/PLAN.md\n\n## [2026-09-03 10:00] a — 손 refs\n\n- verdict: archived\n- refs: https://x/1'
case_eq "decisions 템플릿 제외 · promote/archive slug · unmatched" \
  $'S1\tadopted\t29804280\nS1\tarchived\t29805720\nunmatched\tarchived\t29807160' \
  "$(scv_mx_parse_decisions "$DEC")"
# parsePlan
case_eq "plan status 주석 · 블록 raw_sources · 순수 절 있음" $'scv/conversations/c.md\t0\t1' \
  "$(scv_mx_parse_plan $'---\nstatus: done   # 주석\nraw_sources:\n  - scv/conversations/c.md\n  - scv/raw/x.md\n---\n\n## 순수함수 · 파이프라인 (x)\n')"
case_eq "plan supersedes [] · 순수 절 없음" $'-\t0\t0' \
  "$(scv_mx_parse_plan $'---\nsupersedes: []\nraw_sources: []\n---\n본문')"
case_eq "plan supersedes [a, b] 인라인" $'-\t2\t0' \
  "$(scv_mx_parse_plan $'---\nsupersedes: [a, b]\n---\n본문')"
case_eq "plan supersedes 블록 2건 · 인라인 raw_sources" $'scv/conversations/z.md\t2\t0' \
  "$(scv_mx_parse_plan $'---\nsupersedes:\n  - a\n  - b\nraw_sources: [scv/conversations/z.md]\n---\n본문')"
case_eq "plan 본문 속 낱말은 절이 아니다" $'-\t0\t0' \
  "$(scv_mx_parse_plan $'---\ntitle: t\n---\n순수함수 · 파이프라인 이라는 낱말만')"
# parseIndex
case_eq "index 3건, obsoleted_by" $'A\tdone\t\nB\tobsolete\tC\nC\tdone\t' \
  "$(scv_mx_parse_index $'archives:\n  - slug: A\n    status: done\n  - slug: B\n    status: obsolete\n    obsoleted_by: C\n  - slug: C\n    title: "x"\n    status: done')"
# aggregate
case_eq "aggregate 홀수 중앙값" $'3\t4\t12\t40\t40' "$(scv_mx_aggregate $'a\t1\nb\t4\nc\t7\nd\tnone')"
case_eq "aggregate 짝수 중앙값 x10" $'2\t2\t8\t40\t40' "$(scv_mx_aggregate $'a\t3\nb\t5')"
case_eq "aggregate none 만 → 빈 avg/med" $'0\t2\t0\t\t' "$(scv_mx_aggregate $'a\tnone\nb\tnone')"
case_eq "fmt10" "817.5" "$(scv_mx_fmt10 8175)"
case_eq "fmt10 빈 값 → —" "—" "$(scv_mx_fmt10 '')"
# followup — 합집합, 이중 계산 없음
case_eq "followup obsoleted_by 대상 ∪ supersedes" $'A\t0\nB\t0\nC\t1\nD\t1' \
  "$(scv_mx_metric_followup $'A\tdone\t\nB\tobsolete\tC\nC\tdone\t\nD\tdone\t' $'A\t0\nB\t0\nC\t1\nD\t1')"
if [[ $BAD -eq 0 ]]; then ok "OK [T3] $N/$N"; else fail "[T3] $((N - BAD))/$N (실패 $BAD)"; fi

echo
echo "T4. 실제 저장소에서 돈다"
# 래퍼가 벤더한 Core 사본에는 scv/archive 가 없다 — 그 자리에서는 "색인 없음" 한 줄과
# exit 0 이 계약이다 (부르는 쪽을 막지 않는다). 아카이브가 있는 저장소에서만 표를 본다.
if [[ ! -f "$REPO_ROOT/scv/archive/INDEX.yaml" ]]; then
  ERR="$(cd "$REPO_ROOT" && bash "$SCRIPT" 2>&1 >/dev/null)"; RCA=$?
  OUTN="$(cd "$REPO_ROOT" && bash "$SCRIPT" 2>/dev/null)"
  if [[ $RCA -eq 0 && -z "$OUTN" && "$ERR" == *"no archive index"* ]]; then
    ok "OK [T4] no archive at repo root (vendored copy): exit 0, stderr notice, empty stdout"
  else
    fail "[T4] no-archive case: exit=$RCA stdout=[$OUTN] stderr=[$ERR]"
  fi
else
  A="$(cd "$REPO_ROOT" && bash "$SCRIPT" 2>/dev/null)"; RCA=$?
  B="$(cd "$REPO_ROOT" && bash "$SCRIPT" 2>/dev/null)"
  NAMES=0
  for name in "계획당 대화 턴 수" "승인→보관 리드타임(분)" "후속 재발률" "순수 절 보유율"; do
    # 이름에 괄호가 있어 -F 로 찾고, 적용 범위 n/m 꼴은 bash 정규식으로 본다
    line="$(grep -F "$name | " <<<"$A" | head -1)"
    [[ "$line" =~ \|\ [0-9]+/[0-9]+\ \| ]] && NAMES=$((NAMES + 1))
  done
  if [[ $RCA -eq 0 && $NAMES -eq 4 && "$A" == "$B" ]]; then
    ok "OK [T4] real repo: exit 0, 4 metrics, identical"
  else
    fail "[T4] exit=$RCA metrics=$NAMES identical=$([[ "$A" == "$B" ]] && echo yes || echo no)"
    printf '%s\n' "$A" | sed 's/^/      /'
  fi
fi

echo
echo "T5. 읽기 전용"
DIGEST_AFTER="$(fixture_digest)"
GIT_AFTER="$(cd "$REPO_ROOT" && git status --porcelain 2>/dev/null)"
if [[ "$DIGEST_BEFORE" == "$DIGEST_AFTER" && "$GIT_BEFORE" == "$GIT_AFTER" ]]; then
  ok "OK [T5] no writes"
else
  fail "[T5] 실행이 파일을 바꿨다 (fixture $([[ "$DIGEST_BEFORE" == "$DIGEST_AFTER" ]] && echo same || echo CHANGED), git $([[ "$GIT_BEFORE" == "$GIT_AFTER" ]] && echo same || echo CHANGED))"
fi

echo
echo "T6. 순수성 계약"
if bash "$CORE_ROOT/scripts/check-purity.sh" "$LIB" >/dev/null 2>&1; then
  ok "OK [T6] check-purity"
else
  fail "[T6] 순수성 위반:"
  bash "$CORE_ROOT/scripts/check-purity.sh" "$LIB" 2>&1 | sed 's/^/      /'
fi

echo
echo "── $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
