#!/usr/bin/env bash
# test-anchor-intent.sh — run-dry 의 규약 문장 고정마다 이유가 있는지, 코칭 문구만 고정하는
# 앵커가 없는지, 총수가 상한 이하인지 검사한다 (v0.48.0+).
#
# 왜 있나: 규약 문장을 고정한 앵커는 규약을 고칠 때마다 마찰이 된다(help 다이어트에 10개
# 재조준). 계약을 지키는 고정은 남겨야 하지만, 이유 없는 고정은 두 달 뒤 아무도 못 지운다.
# 그래서 문장 고정마다 바로 위 줄에 `# why: …` 를 요구하고, GUIDANCE 블록(최소 프로필에서
# 잘리는 코칭 문구)만 고정하는 앵커는 금지하며, 총수에 상한을 둔다.
#
# 대상 변수 → 파일: PROMOTE_CMD·PROMOTE_CMD_FILE→promote.md, WORK_CMD→work.md, HELP_CMD→help.md,
#   HELP_ALL→help.md+help/*.md, REGRESSION_CMD·CODEGEN_CMD·SYNC_CMD·INSTALL_DEPS_CMD·STATUS_CMD·
#   DECK_CMD·HANDOFF_CMD·WORKSPACE_CMD→각 규약, PROTOCOL_ROOT/<x>.md, PROMOTE_DOC·PROMOTE_TPL→
#   template/scv/PROMOTE.md. 그 밖의 변수(스크립트·설정 예시·README)는 규약 문장 고정이 아니다.
#
# 순수부: core/tests/lib/anchors.sh (@pure). 파일 읽기와 출력은 여기.
#
# Covers TESTS.md T2·T3 of 20260914-wookiya1364-run-dry-anchor-diet.
#
# Run: bash core/tests/test-anchor-intent.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE=""
for up in "$HERE/.." "$HERE/../.."; do
  for sub in core vendor/scv-core/core plugins/scv/vendor/scv-core/core; do
    if [[ -f "$up/$sub/scripts/lib/settings.sh" ]]; then CORE="$(cd "$up/$sub" && pwd)"; break 2; fi
  done
done
[[ -n "$CORE" ]] || { echo "test-anchor-intent: payload not found from $HERE" >&2; exit 1; }
# shellcheck source=lib/anchors.sh
source "$HERE/lib/anchors.sh"

PASS=0; FAIL=0; SKIP=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "  – SKIP: $1"; SKIP=$((SKIP + 1)); }

RUN_DRY="${SCV_RUN_DRY:-$HERE/run-dry.sh}"
ANCHOR_MAX="${SCV_ANCHOR_MAX:-120}"
US=$'\x1f'

proto_file() {  # <변수> <하위파일> → 본문 파일 경로들 (공백 구분) 또는 빈 문자열
  local var="$1" sub="$2"
  case "$var" in
    PROMOTE_CMD|PROMOTE_CMD_FILE) echo "$CORE/protocols/promote.md" ;;
    WORK_CMD) echo "$CORE/protocols/work.md" ;;
    HELP_CMD) echo "$CORE/protocols/help.md" ;;
    HELP_ALL) echo "$CORE/protocols/help.md" "$CORE"/protocols/help/*.md ;;
    REGRESSION_CMD) echo "$CORE/protocols/regression.md" ;;
    CODEGEN_CMD) echo "$CORE/protocols/codegen.md" ;;
    SYNC_CMD) echo "$CORE/protocols/sync.md" ;;
    INSTALL_DEPS_CMD) echo "$CORE/protocols/install-deps.md" ;;
    STATUS_CMD) echo "$CORE/protocols/status.md" ;;
    DECK_CMD) echo "$CORE/protocols/deck.md" ;;
    HANDOFF_CMD) echo "$CORE/protocols/handoff.md" ;;
    WORKSPACE_CMD) echo "$CORE/protocols/workspace.md" ;;
    PROMOTE_DOC|PROMOTE_TPL) echo "$CORE/template/scv/PROMOTE.md" ;;
    PROTOCOL_ROOT) [[ -n "$sub" ]] && echo "$CORE/protocols/$sub" ;;
    *) echo "" ;;
  esac
}

declare -A BODY_CACHE STRIP_CACHE
body_for() {  # <파일 목록> → 캐시된 본문 (한 번만 읽고, GUIDANCE 걷어낸 본문도 같이 만든다)
  local key="$1" f text=""
  if [[ -z "${BODY_CACHE[$key]+x}" ]]; then
    for f in $key; do [[ -f "$f" ]] && text="$text$(cat "$f")"$'\n'; done
    BODY_CACHE[$key]="$text"
    STRIP_CACHE[$key]="$(scv_anchor_strip_guidance "$text")"
  fi
}
classify() {  # <run-dry 경로> → "<줄>\x1f<kind>\x1f<why>" 줄들 (규약 앵커만)
  local rows n var sub body why files kind
  rows="$(scv_anchor_extract "$(cat "$1")")"
  while IFS="$US" read -r n var sub body why; do
    [[ -z "$var" ]] && continue
    files="$(proto_file "$var" "$sub")"; [[ -z "$files" ]] && continue
    body_for "$files"
    kind="$(scv_anchor_kind "$(scv_anchor_unescape "$body")" "${BODY_CACHE[$files]}" "${STRIP_CACHE[$files]}")"
    printf '%s%s%s%s%s\n' "$n" "$US" "$kind" "$US" "$why"
  done <<<"$rows"
}

[[ -f "$RUN_DRY" ]] || { echo "run-dry not found: $RUN_DRY" >&2; exit 1; }
ROWS="$(classify "$RUN_DRY")"
count() { local k="$1" c=0 n kind why; while IFS="$US" read -r n kind why; do [[ "$kind" == "$k" ]] && c=$((c + 1)); done <<<"$ROWS"; echo "$c"; }
echo "  · 규약 앵커: token=$(count token) short=$(count short) sentence=$(count sentence) guidance=$(count guidance) missing=$(count missing)"

echo "── [T2] 중복 0 · GUIDANCE 전용 고정 0 ──"
DUPS="$(scv_anchor_dups "$(scv_anchor_extract "$(cat "$RUN_DRY")")")"
[[ -z "$DUPS" ]] && ok "같은 (파일, 문장) 중복 없음" || fail "중복: $(printf '%s' "$DUPS" | tr '\n' ';' | cut -c1-160)"
V="$(scv_anchor_check "$ROWS" "$ANCHOR_MAX")"
G="$(grep '^guidance' <<<"$V" || true)"
[[ -z "$G" ]] && ok "GUIDANCE 블록만 고정하는 앵커 없음" || fail "GUIDANCE 전용 고정 $(grep -c . <<<"$G")건: $(tr '\n' ' ' <<<"$G" | cut -c1-120)"

echo "── [T3] 문장 고정마다 why · 총수 ≤ ${ANCHOR_MAX} ──"
N="$(grep '^no-why' <<<"$V" || true)"
[[ -z "$N" ]] && ok "모든 문장 고정에 # why: 가 있다" || fail "why 없는 문장 고정 $(grep -c . <<<"$N")건: $(tr '\n' ' ' <<<"$N" | cut -c1-120)"
B="$(grep '^over-budget' <<<"$V" || true)"
[[ -z "$B" ]] && ok "문장 고정 총수 ≤ ${ANCHOR_MAX}" || fail "$B"

echo "── [T3n] 순수부가 위반을 잡는다 ──"
r1="$(scv_anchor_check "$(printf '1\x1fsentence\x1f0\n2\x1fguidance\x1f1\n')" 120)"
grep -q "no-why 1" <<<"$r1" && grep -q "guidance 2" <<<"$r1" && ok "no-why·guidance 를 잡는다" || fail "순수부 위반 탐지 실패: $r1"
r2="$(scv_anchor_check "$(printf '1\x1fsentence\x1f1\n2\x1fshort\x1f1\n')" 1)"
grep -q "over-budget 2" <<<"$r2" && ok "상한 초과를 잡는다" || fail "상한 탐지 실패: $r2"
d="$(scv_anchor_dups "$(printf '1\x1fX\x1f\x1fsame\x1f0\n2\x1fX\x1f\x1fsame\x1f0\n3\x1fY\x1f\x1fsame\x1f0\n')")"
[[ "$(grep -c . <<<"$d")" -eq 1 ]] && ok "중복을 잡는다 (다른 파일은 중복 아님)" || fail "중복 탐지 실패: $d"
k="$(scv_anchor_kind "only inside the coaching block here" "$(printf 'x\n<!-- SCV:GUIDANCE -->\nonly inside the coaching block here\n<!-- /SCV:GUIDANCE -->\ny')")"
[[ "$k" == "guidance" ]] && ok "GUIDANCE 전용 판정" || fail "kind=$k"
[[ "$(scv_anchor_kind "--with-context" "x")" == "token" ]] && ok "토큰 판정" || fail "토큰 판정 실패"

echo "── [T13] 순수부 선언 ──"
if [[ -f "$CORE/scripts/check-purity.sh" ]]; then
  OUT="$(bash "$CORE/scripts/check-purity.sh" "$HERE/lib/anchors.sh" 2>&1)"
  grep -q '^OK  purity' <<<"$OUT" && ok "순수성 계약 통과" || fail "순수성 위반: $(printf '%s' "$OUT" | head -3)"
else
  skip "check-purity.sh 없음"
fi

echo "─────────────────────────────"
echo "  통과 $PASS · 실패 $FAIL · 생략 $SKIP"
[[ $FAIL -eq 0 ]] && { echo "  ALL GATES OK"; exit 0; } || exit 1
