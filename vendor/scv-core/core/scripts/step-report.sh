#!/usr/bin/env bash
# step-report.sh — 구현 중인 계획이 있고 호스트에 단계 보고 도구가 있으면, 매 턴 훅에 실을 안내 한 줄을 낸다.
#
#   step-report.sh line [<scv 폴더>]    (기본 scv)
#
# 입력: 호스트 프로필 SCV_STEP_TOOL(래퍼가 준다), <scv>/promote/*/PLAN.md 의 status. 판단은 lib/step-report.sh 의 순수함수가 하고
# 여기는 읽기와 출력만 한다. 도구가 없거나 구현 중인 계획이 없으면 아무것도 내지 않는다. 어떤 실패도 exit 0.
set -u
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" 2>/dev/null && pwd )" || exit 0
# shellcheck source=lib/step-report.sh
source "$SCRIPT_DIR/lib/step-report.sh" 2>/dev/null || exit 0
# shellcheck source=lib/host-profile.sh
source "$SCRIPT_DIR/lib/host-profile.sh" 2>/dev/null || exit 0

case "${1:-}" in
  line)
    TOOL="${SCV_STEP_TOOL:-}"
    [[ -n "$TOOL" ]] || exit 0
    SCV_DIR="${2:-scv}"
    rows=""
    for plan in "$SCV_DIR"/promote/*/PLAN.md; do
      [[ -f "$plan" ]] || continue
      status="$(awk '/^---/{n++; next} n==1 && /^status:/{sub(/^status:[ \t]*/, ""); print; exit}' "$plan" 2>/dev/null)"
      rows="$rows$(basename "$(dirname "$plan")")"$'\t'"$status"$'\n'
    done
    out="$(scv_step_line "$TOOL" "$(scv_step_active_plan "$rows")")"
    [[ -n "$out" ]] && printf '%s\n' "$out"
    ;;
  *) echo "usage: step-report.sh line [<scv dir>]" >&2 ;;
esac
exit 0
