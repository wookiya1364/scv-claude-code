#!/usr/bin/env bash
# help-state.sh — "규약은 세션당 한 번" 표식의 효과부 (v0.49.0+). 읽기·쓰기는 여기서만.
#
#   help-state.sh read                       표식 JSON 한 줄 (없으면 빈 줄), exit 0
#   help-state.sh prompt <session_id> [N]    매 턴 훅: 세션 비교·turn 증가·N턴 재읽기 → 저장, 새 JSON 출력
#   help-state.sh reset                      되찾기 훅: protocol=0 → 저장
#   help-state.sh mark                       help 가 규약 전체를 읽은 뒤: protocol=1 · 새 지문(nonce) → 저장, .help-nonce 에도
#   help-state.sh diag <hhmm> < 진단본문     해시 비교 → "full"|"brief <diag_at>" 출력, 저장
#   help-state.sh stop [--echo on|off] [--lint on|off] [--cap N] [--now ISO] < 답본문   (v0.50.0+)
#                                            종료 훅: 이번 턴 기록의 지문 검사 + 답 모양 린트 → 흐려짐이면 protocol=0
#                                            + .help-warn(다음 턴 경고) 저장, .help-drift 에 한 줄. "echo=<r> lint=<n> reload=<0|1>" 출력.
#
# 파일: ${SCV_JOURNAL_DIR:-scv/journal}/.help-state — 훅이 쓰는 자리(scv/journal/, ignore 대상). 같은 폴더의
#   .help-nonce(지문 한 줄 — 규약을 읽은 턴에 모델이 읽는다) · .help-warn(다음 턴 훅이 싣고 지운다) · .help-drift(관찰 로그).
# 어떤 실패도 exit 0 — 표식이 없거나 깨지면 "load + 전체 진단" 으로 떨어진다(이전 동작).
set -u
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" 2>/dev/null && pwd )" || exit 0
# shellcheck source=lib/help-state.sh
source "$SCRIPT_DIR/lib/help-state.sh" 2>/dev/null || exit 0
JOURNAL_DIR="${SCV_JOURNAL_DIR:-scv/journal}"
STATE_FILE="$JOURNAL_DIR/.help-state"
NONCE_FILE="$JOURNAL_DIR/.help-nonce"; WARN_FILE="$JOURNAL_DIR/.help-warn"; DRIFT_FILE="$JOURNAL_DIR/.help-drift"

_read() { [[ -f "$STATE_FILE" && ! -L "$STATE_FILE" ]] && head -c 4096 "$STATE_FILE" 2>/dev/null | head -1 || printf ''; }
_write() {  # <json> — 임시 파일 뒤 mv. journal 디렉터리가 없으면 만든다(ignore 대상).
  local json="$1" tmp
  mkdir -p "$JOURNAL_DIR" 2>/dev/null || return 0
  [[ -L "$STATE_FILE" ]] && return 0
  tmp="$(mktemp "$JOURNAL_DIR/.help-state.XXXXXX" 2>/dev/null)" || return 0
  printf '%s\n' "$json" > "$tmp" 2>/dev/null && mv -f "$tmp" "$STATE_FILE" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  return 0
}
_put() {  # <파일> <본문> — 같은 폴더의 부속 파일 한 개를 통째로 쓴다(임시 파일 뒤 mv). 심볼릭 링크면 안 쓴다.
  local file="$1" body="$2" tmp
  mkdir -p "$JOURNAL_DIR" 2>/dev/null || return 0
  [[ -L "$file" ]] && return 0
  tmp="$(mktemp "$file.XXXXXX" 2>/dev/null)" || return 0
  printf '%s\n' "$body" > "$tmp" 2>/dev/null && mv -f "$tmp" "$file" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  return 0
}
_nonce_new() {  # 8자리 16진 무작위 — 효과부의 일. /dev/urandom 이 없으면 $RANDOM 둘.
  local n=""
  n="$(head -c 4 /dev/urandom 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')"
  [[ "$n" =~ ^[0-9a-f]{8}$ ]] || n="$(printf '%04x%04x' "$RANDOM" "$RANDOM")"
  printf '%s' "$n"
}
_mtime() { stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1" 2>/dev/null || printf '0'; }
# 이번 턴의 기록: 대화 폴더에서 가장 최근에 바뀐 대화 파일이 표식(턴 시작에 씀)보다 나중에 바뀌었으면
# "이번 턴에 기록됨(yes)" 이고, 그 파일의 마지막 Turn 블록에서 `protocol: <지문>` 줄을 읽는다.
# 출력: "yes|no\x1f<지문>". 대화 폴더가 없거나 파일이 없으면 "no\x1f".
_turn_record() {
  local dir="${SCV_CONVERSATIONS_DIR:-scv/conversations}" f best="" bm=0 m sm got=""
  [[ -d "$dir" ]] || { printf 'no\x1f'; return 0; }
  for f in "$dir"/*.md; do
    [[ -f "$f" && ! -L "$f" ]] || continue
    m="$(_mtime "$f")"; [[ "$m" =~ ^[0-9]+$ ]] || m=0
    if (( m >= bm )); then bm=$m; best="$f"; fi
  done
  [[ -n "$best" ]] || { printf 'no\x1f'; return 0; }
  sm="$(_mtime "$STATE_FILE")"; [[ "$sm" =~ ^[0-9]+$ ]] || sm=0
  (( bm >= sm )) || { printf 'no\x1f'; return 0; }
  got="$(tail -n 400 "$best" 2>/dev/null | awk '/^## Turn /{blk=""; inb=1; next} inb && /^protocol:[[:space:]]*/{v=$0; sub(/^protocol:[[:space:]]*/,"",v); sub(/[[:space:]]+$/,"",v); blk=v} END{print blk}')"
  printf 'yes\x1f%s' "$got"
}

cmd="${1:-read}"; shift || true
st="$(scv_hstate_parse "$(_read)")"
case "$cmd" in
  read)   _read; echo ;;
  prompt) st="$(scv_hstate_reload "$st" "${1:-}" prompt "${2:-0}")"; json="$(scv_hstate_render "$st")"; _write "$json"; printf '%s\n' "$json" ;;
  reset)  st="$(scv_hstate_reload "$st" "" reset 0)"; json="$(scv_hstate_render "$st")"; _write "$json"
          # 지문은 컨텍스트에 묶인 값 — 컨텍스트가 비워졌으니 파일도 비운다. 예약된 경고도 의미를 잃는다.
          for _f in "$NONCE_FILE" "$WARN_FILE"; do [[ -f "$_f" && ! -L "$_f" ]] && rm -f "$_f" 2>/dev/null; done
          printf '%s\n' "$json" ;;
  mark)   _n="$(_nonce_new)"; st="$(scv_hstate_mark "$st" "$_n")"; json="$(scv_hstate_render "$st")"; _write "$json"
          _put "$NONCE_FILE" "$_n"; printf '%s\n' "$json" ;;
  stop)   # 인자: --echo on|off · --lint on|off · --cap N · --now ISO · --src host|transcript|none. stdin = 직전 답 본문(없으면 린트 생략).
          _esw=on; _lsw=on; _cap=2; _now=""; _src=""
          while [[ $# -gt 0 ]]; do
            case "$1" in
              --src)  _src="${2:-}"; shift 2 ;;   # v0.51.0+: 본문 출처 host|transcript|none — 드리프트 줄 끝에 남긴다
              --echo) _esw="$(scv_hstate_switch "${2:-}")"; shift 2 ;;
              --lint) _lsw="$(scv_hstate_switch "${2:-}")"; shift 2 ;;
              --cap)  _cap="${2:-2}"; shift 2 ;;
              --now)  _now="${2:-}"; shift 2 ;;
              *) shift ;;
            esac
          done
          # 둘 다 꺼져 있으면 아무 것도 읽지도 쓰지도 않는다 — 0.49 와 같은 동작.
          [[ "$_esw" == "off" && "$_lsw" == "off" ]] && exit 0
          [[ -n "$_now" ]] || _now="$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"
          _text="$(head -c 65536 2>/dev/null || true)"
          IFS=$'\x1f' read -r _s _p _t _d _at _n <<<"$st"
          _rec="$(_turn_record)"; _app="${_rec%%$'\x1f'*}"; _got="${_rec#*$'\x1f'}"
          _echo="$(scv_echo_check "$_got" "${_n:-}" "${_p:-0}" "$_app")"
          _viol=""; [[ "$_lsw" == "on" && -n "${_text//[[:space:]]/}" ]] && _viol="$(scv_answer_lint "$_text" "$_cap")"
          _dec="$(scv_drift_decide "$_echo" "$_viol" "$_esw" "$_lsw")"; _reload="${_dec%%$'\x1f'*}"; _warn="${_dec#*$'\x1f'}"
          if [[ "$_reload" == "1" ]]; then
            st="$(scv_hstate_reload "$st" "" reset 0)"   # protocol=0 · 지문 비움 — 다음 mark 가 새 지문을 만든다
            _write "$(scv_hstate_render "$st")"; _put "$WARN_FILE" "$_warn"
          fi
          mkdir -p "$JOURNAL_DIR" 2>/dev/null && [[ ! -L "$DRIFT_FILE" ]] && { scv_drift_line "$_now" "${_t:-0}" "$_echo" "$_viol" "$_reload" "$_src"; echo; } >> "$DRIFT_FILE" 2>/dev/null
          _nv=0; [[ -n "${_viol//[[:space:]]/}" ]] && _nv="$(printf '%s\n' "$_viol" | grep -c . || true)"
          printf 'echo=%s lint=%s reload=%s\n' "$_echo" "$_nv" "$_reload" ;;
  diag)   text="$(cat 2>/dev/null || true)"; r="$(scv_hstate_diag "$st" "$text" "${1:-}")"; mode="${r%%$'\x1f'*}"; st="${r#*$'\x1f'}"
          json="$(scv_hstate_render "$st")"; _write "$json"
          if [[ "$mode" == "brief" ]]; then IFS=$'\x1f' read -r _s _p _t _d _at _n <<<"$st"; printf 'brief %s\n' "${_at:-}"; else printf 'full\n'; fi ;;
  *) echo "usage: help-state.sh read|prompt <session_id> [N]|reset|mark|diag <hhmm>|stop [--echo on|off] [--lint on|off] [--cap N] [--now ISO] [--src host|transcript|none]" >&2 ;;
esac
exit 0
