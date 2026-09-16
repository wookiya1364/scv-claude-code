#!/usr/bin/env bash
# help-state.sh — "규약은 세션당 한 번" 표식의 효과부 (v0.49.0+). 읽기·쓰기는 여기서만.
#
#   help-state.sh read                       표식 JSON 한 줄 (없으면 빈 줄), exit 0
#   help-state.sh prompt <session_id> [N]    매 턴 훅: 세션 비교·turn 증가·N턴 재읽기 → 저장, 새 JSON 출력
#   help-state.sh reset                      되찾기 훅: protocol=0 → 저장
#   help-state.sh mark                       help 가 규약 전체를 읽은 뒤: protocol=1 → 저장
#   help-state.sh diag <hhmm> < 진단본문     해시 비교 → "full"|"brief <diag_at>" 출력, 저장
#
# 파일: ${SCV_JOURNAL_DIR:-scv/journal}/.help-state — 훅이 쓰는 유일한 자리(scv/journal/, ignore 대상).
# 어떤 실패도 exit 0 — 표식이 없거나 깨지면 "load + 전체 진단" 으로 떨어진다(이전 동작).
set -u
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" 2>/dev/null && pwd )" || exit 0
# shellcheck source=lib/help-state.sh
source "$SCRIPT_DIR/lib/help-state.sh" 2>/dev/null || exit 0
JOURNAL_DIR="${SCV_JOURNAL_DIR:-scv/journal}"
STATE_FILE="$JOURNAL_DIR/.help-state"

_read() { [[ -f "$STATE_FILE" && ! -L "$STATE_FILE" ]] && head -c 4096 "$STATE_FILE" 2>/dev/null | head -1 || printf ''; }
_write() {  # <json> — 임시 파일 뒤 mv. journal 디렉터리가 없으면 만든다(ignore 대상).
  local json="$1" tmp
  mkdir -p "$JOURNAL_DIR" 2>/dev/null || return 0
  [[ -L "$STATE_FILE" ]] && return 0
  tmp="$(mktemp "$JOURNAL_DIR/.help-state.XXXXXX" 2>/dev/null)" || return 0
  printf '%s\n' "$json" > "$tmp" 2>/dev/null && mv -f "$tmp" "$STATE_FILE" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  return 0
}

cmd="${1:-read}"; shift || true
st="$(scv_hstate_parse "$(_read)")"
case "$cmd" in
  read)   _read; echo ;;
  prompt) st="$(scv_hstate_reload "$st" "${1:-}" prompt "${2:-0}")"; json="$(scv_hstate_render "$st")"; _write "$json"; printf '%s\n' "$json" ;;
  reset)  st="$(scv_hstate_reload "$st" "" reset 0)"; json="$(scv_hstate_render "$st")"; _write "$json"; printf '%s\n' "$json" ;;
  mark)   st="$(scv_hstate_mark "$st")"; json="$(scv_hstate_render "$st")"; _write "$json"; printf '%s\n' "$json" ;;
  diag)   text="$(cat 2>/dev/null || true)"; r="$(scv_hstate_diag "$st" "$text" "${1:-}")"; mode="${r%%$'\x1f'*}"; st="${r#*$'\x1f'}"
          json="$(scv_hstate_render "$st")"; _write "$json"
          if [[ "$mode" == "brief" ]]; then IFS=$'\x1f' read -r _s _p _t _d _at <<<"$st"; printf 'brief %s\n' "${_at:-}"; else printf 'full\n'; fi ;;
  *) echo "usage: help-state.sh read|prompt <session_id> [N]|reset|mark|diag <hhmm>" >&2 ;;
esac
exit 0
