#!/usr/bin/env bash
# choice-gate.sh — 고르게 할 때 규칙(contracts/choices.md)의 효과부. 읽기 · 쓰기는 여기서만, 판단은 lib/choices.sh.
#
#   choice-gate.sh line                         매 턴 훅이 부른다: 호스트 설정에 선택지 도구가 있으면 안내 한 줄(없으면 아무것도)
#   choice-gate.sh stop [--active 0|1] < 마지막 답  종료 훅이 부른다: 글로 묻거나 번호로 고르게 하면서 끝났으면
#                                                 CHOICE_GATE: block + CHOICE_REASON: <이유>. 호스트가 이미 계속 중이면
#                                                 CHOICE_GATE: warn — 막지 않고 다음 턴 경고(.help-warn)에 덧붙인다. 그 밖에는 ok.
#
# 입력: 호스트 프로필 SCV_CHOICE_TOOL (래퍼가 준다), 설정 SCV_CHOICE_GATE(on 기본 | off — 이 프로젝트에서 끄기),
# 호스트 프로필 SCV_CHOICE_OFF_WHEN("이름=값" — 그 환경 변수가 그 값인 실행에는 도구가 없다. 예: 헤드리스 실행).
# 도구가 없거나 스위치가 off 면 두 하위 명령 모두 이 기능 전과 같다(아무것도 내지 않음 · ok).
# 다음 턴 경고는 "[SCV 가이드] 직전 턴: …" 머리말로 남긴다 — 컨텍스트 초기화(clear · 압축 · 재개)에도 살아남는 경고와 같은 꼴.
# 어떤 실패도 exit 0 — 판정을 못 하면 막지 않는다.
set -u
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" 2>/dev/null && pwd )" || exit 0
# shellcheck source=lib/choices.sh
source "$SCRIPT_DIR/lib/choices.sh" 2>/dev/null || exit 0
# shellcheck source=lib/host-profile.sh
source "$SCRIPT_DIR/lib/host-profile.sh" 2>/dev/null || exit 0
# shellcheck source=lib/settings.sh
source "$SCRIPT_DIR/lib/settings.sh" 2>/dev/null || true
TOOL="${SCV_CHOICE_TOOL:-}"
_sw=""; declare -F settings_get >/dev/null 2>&1 && _sw="$(settings_get SCV_CHOICE_GATE 2>/dev/null || true)"
_sw="$(printf '%s' "$_sw" | tr -d '"[:space:]' | tr -d "'" | tr '[:upper:]' '[:lower:]')"
[[ "$_sw" == "off" ]] && TOOL=""   # 스위치 off — 도구가 없는 것과 같다
_off="${SCV_CHOICE_OFF_WHEN:-}"; _offname="${_off%%=*}"
if [[ -n "$TOOL" && "$_off" == *=* && "$_offname" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
  # 호스트가 이 실행에서 도구를 빼는 조건(사람이 답할 수 없는 헤드리스 등) — 도구가 없는 것과 같다: 안내도 막기도 없다
  [[ "$(scv_choice_off_when "$_off" "${!_offname:-}")" == "1" ]] && TOOL=""
fi
JOURNAL_DIR="${SCV_JOURNAL_DIR:-scv/journal}"

case "${1:-}" in
  line)
    scv_choice_line "$TOOL"
    ;;
  stop)
    shift
    ACTIVE=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --active) ACTIVE="${2:-0}"; shift 2 2>/dev/null || shift ;;
        *) shift ;;
      esac
    done
    [[ "$ACTIVE" == "1" ]] || ACTIVE=0
    ANSWER="$(head -c 65536 2>/dev/null || true)"
    _asks=0
    [[ "$ANSWER" == *[![:space:]]* ]] && _asks="$(scv_asks_in_text "$(scv_answer_body "$ANSWER")")"
    _gate="$(scv_choice_gate "$_asks" "$TOOL" "$ACTIVE")"
    echo "CHOICE_GATE: $_gate"
    if [[ "$_gate" != "ok" ]]; then
      _why="$(scv_choice_reason "$TOOL")"
      echo "CHOICE_REASON: $_why"
      if [[ "$_gate" == "warn" ]]; then
        mkdir -p "$JOURNAL_DIR" 2>/dev/null && [[ ! -L "$JOURNAL_DIR/.help-warn" ]] \
          && printf '%s\n' "[SCV 가이드] 직전 턴: $_why" >> "$JOURNAL_DIR/.help-warn" 2>/dev/null
      fi
    fi
    ;;
  *) echo "usage: choice-gate.sh line | stop [--active 0|1]" >&2 ;;
esac
exit 0
