#!/usr/bin/env bash
# show-real.sh — 실체 보여 주기(contracts/show-real.md)의 효과부 (v0.66.0+). 읽기 · 출력은 여기서만, 판단은 lib/show-real.sh.
#
#   show-real.sh line < 훅 입력(JSON, 없어도 된다)
#       매 턴 훅이 부른다: 설정 SCV_SHOW_REAL 이 off 가 아니면 안내 세 줄, off 면 아무것도 내지 않는다(입력도 읽지 않는다).
#
# 확인을 묻는 통로: 고르게 할 때 규칙과 같은 판단(choice-gate.sh tool — 호스트 설정의 선택 창 이름에 그 규칙의 스위치
# SCV_CHOICE_GATE 와 사람 없는 실행 조건을 반영한 값, choice-gate.sh unattended — 사람 없는 실행 조건)과, 이번 입력이 사람
# 메시지인지(훅 입력의 prompt 를 매 턴 훅과 같은 명령 model-prompting.sh kind 로 가른다).
# 막는 검사는 없다. 어떤 실패도 exit 0 — 판단을 못 하면 사람 메시지 · 사람 있는 실행으로 본다.
set -u
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" 2>/dev/null && pwd )" || exit 0
# shellcheck source=lib/show-real.sh
source "$SCRIPT_DIR/lib/show-real.sh" 2>/dev/null || exit 0
# shellcheck source=lib/settings.sh
source "$SCRIPT_DIR/lib/settings.sh" 2>/dev/null || true

case "${1:-}" in
  line)
    _raw=""; declare -F settings_get >/dev/null 2>&1 && _raw="$(settings_get SCV_SHOW_REAL 2>/dev/null || true)"
    _sw="$(scv_show_real_switch "$_raw")"
    [[ "$_sw" == "on" ]] || exit 0
    # 이번 입력이 자동 알림인지 — 매 턴 훅이 자기 판별에 쓰는 명령과 같은 명령(model-prompting.sh kind: 프롬프트 앞 64KB ·
    # 호스트 설정의 자동 입력 모양)으로 가른다. 두 판별이 갈라지지 않게(독립 검토 2026-10-07: 64KB 넘는 알림에서 갈렸다).
    _kind="human"
    if [[ ! -t 0 && -f "$SCRIPT_DIR/model-prompting.sh" ]] && command -v jq >/dev/null 2>&1; then
      _kind="$(jq -r 'try (.prompt // "") catch ""' 2>/dev/null | bash "$SCRIPT_DIR/model-prompting.sh" kind 2>/dev/null || true)"
      [[ "$_kind" == "auto" ]] || _kind="human"
    fi
    _tool=""; _un=0
    if [[ -f "$SCRIPT_DIR/choice-gate.sh" ]]; then
      _tool="$(bash "$SCRIPT_DIR/choice-gate.sh" tool 2>/dev/null || true)"
      _un="$(bash "$SCRIPT_DIR/choice-gate.sh" unattended 2>/dev/null || true)"
    fi
    scv_show_real_rule "$_sw" "$(scv_show_real_channel "$_tool" "$_un" "$_kind")"
    ;;
  *) echo "usage: show-real.sh line" >&2 ;;
esac
exit 0
