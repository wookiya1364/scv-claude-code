#!/usr/bin/env bash
# on-stop.sh — host hook template (SCV Core, v0.22.0+).
#
# Purpose: when the host agent finishes responding (the stop / session-end hook
# event, e.g. the event named `Stop`), summarize the assistant's response into
# the committed team journal.
#
# Contract (see docs/wrapper-integration.md §6 "Hook seam" in scv-core):
#   - stdin carries ONE JSON object containing a `transcript_path` field — a
#     JSONL transcript file whose exact schema is host-version dependent.
#   - This template defensively extracts the latest assistant text blocks and
#     appends a bounded tail via journal-append.sh (redaction runs before any
#     write). Transcript formats it cannot parse are quietly skipped.
#   - Registration/installation is WRAPPER-OWNED — Core ships only this
#     template and the contract. The wrapper should export SCV_CORE_ROOT.
#
# NON-BLOCKING GUARANTEE: recording failure must never block a session — ANY
# failure (bad JSON, unreadable/unknown transcript, missing jq) → exit 0, no
# write. Wrappers copying this template must preserve that guarantee.
set -u

[[ -d scv ]] || exit 0

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" 2>/dev/null && pwd )" || exit 0
CORE_HOME="${SCV_CORE_ROOT:-$SCRIPT_DIR/../..}"
JOURNAL_APPEND="$CORE_HOME/scripts/journal-append.sh"

INPUT="$(cat 2>/dev/null || true)"

SCV_FORCE_BLOCK_REASON=""

# ---------- help 강제 (v0.39.0+) --------------------------------------------
# 이 블록만이 이 훅에서 세션을 되돌려 세울 수 있다. 판정 자체는 판정부의 순수함수가
# 하고, 여기서는 읽고 쓰고 내보내는 일만 한다.
#
# 여기서는 결정만 한다. 내보내는 것은 기록이 끝난 뒤다 — 되돌리는 턴에서 기록을
# 건너뛰면 호스트가 상한에서 턴을 끊었을 때 그 답이 팀 기록에서 사라진다.
_scv_force_lib="$CORE_HOME/scripts/lib/force-help.sh"
_scv_settings_lib="$CORE_HOME/scripts/lib/settings.sh"
[[ -f "$_scv_settings_lib" ]] && { source "$_scv_settings_lib" 2>/dev/null || true; }
[[ -f "$_scv_force_lib" ]] && { source "$_scv_force_lib" 2>/dev/null || true; }

_scv_setting() {  # <KEY> — 라이브러리가 없으면 빈 값(=기본값으로 간다)
  declare -F settings_get >/dev/null 2>&1 || return 0
  settings_get "$1" 2>/dev/null || true
}

_scv_json_str() {  # <키> — 읽을 도구가 없으면 빈 문자열
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$INPUT" | jq -r --arg k "$1" '.[$k] // empty' 2>/dev/null
  elif command -v python3 >/dev/null 2>&1; then
    printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    v = d.get(sys.argv[1], "")
    sys.stdout.write(v if isinstance(v, str) else "")
except Exception:
    pass' "$1" 2>/dev/null
  fi
}

_scv_emit_block() {  # <사유> — 결정 JSON 한 줄. 이스케이프는 도구에 맡긴다.
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -Rs '{decision:"block", reason:.}' 2>/dev/null && return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$1" | python3 -c '
import json, sys
sys.stdout.write(json.dumps({"decision": "block", "reason": sys.stdin.read()}, ensure_ascii=False))' 2>/dev/null \
      && { printf '\n'; return 0; }
  fi
  return 1
}

if [[ -n "$INPUT" ]] \
   && declare -F scv_force_classify >/dev/null 2>&1 \
   && { command -v jq >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1; }; then
  _scv_always="$(printf '%s' "$(_scv_setting SCV_ALWAYS_ON)" | tr -d '"[:space:]' | tr -d "'" | tr '[:upper:]' '[:lower:]')"
  _scv_force="$(scv_force_switch "$(_scv_setting SCV_FORCE_HELP)")"
  [[ "${_scv_always:-on}" == "off" ]] && _scv_force="off"

  _scv_event="main"
  case "$(_scv_json_str hook_event_name)" in
    *[Ss]ubagent*) _scv_event="subagent" ;;
  esac

  _scv_session="$(_scv_json_str session_id)"
  [[ -n "$_scv_session" ]] || _scv_session="nosession"
  _scv_state_dir="${SCV_GUARD_STATE:-${TMPDIR:-/tmp}/scv-guard}"
  _scv_key="$(scv_force_project_key "$PWD")"
  _scv_receipt="$(scv_force_receipt_file "$_scv_state_dir" "$_scv_session" "$_scv_key")"
  _scv_turn="$(scv_force_turn_file "$_scv_state_dir" "$_scv_session" "$_scv_key")"

  # 턴 시작 표시가 없으면(프롬프트 훅이 못 돌았거나 못 썼다) 판정 근거가 없다.
  # 그때는 되돌리지 않는다 — 고장은 열림 쪽으로 넘어간다.
  _scv_mark=""; _scv_attempts=0
  if [[ -r "$_scv_turn" ]]; then
    _scv_mark="$(sed -n '1p' "$_scv_turn" 2>/dev/null || true)"
    _scv_attempts="$(sed -n '2p' "$_scv_turn" 2>/dev/null || true)"
    [[ "$_scv_mark" =~ ^[0-9]+$ ]] || _scv_mark=""
    [[ "$_scv_attempts" =~ ^[0-9]+$ ]] || _scv_attempts=0
  fi

  # 턴 시작 이후에 발행된 영수증 줄만 본다. 지난 턴의 호출은 근거가 되지 않는다.
  _scv_lines=""
  if [[ -n "$_scv_mark" && -r "$_scv_receipt" ]]; then
    _scv_lines="$(tail -n "+$((_scv_mark + 1))" "$_scv_receipt" 2>/dev/null || true)"
  fi

  _scv_kind="$(scv_force_classify "$_scv_force" "$_scv_event" "$_scv_mark" "$_scv_lines")"
  if [[ "$(scv_force_decide "$_scv_kind")" == "block" ]]; then
    _scv_attempts=$((_scv_attempts + 1))
    { printf '%s\n%s\n' "$_scv_mark" "$_scv_attempts" > "$_scv_turn"; } 2>/dev/null || true
    SCV_FORCE_BLOCK_REASON="$(scv_force_reason "$_scv_attempts")"
  elif [[ -n "$_scv_mark" && "$_scv_attempts" -gt 0 ]]; then
    # 통과했으니 이번 턴은 실패가 아니다. 횟수를 지워 다음 턴의 표시줄이 거짓
    # 실패를 보고하지 않게 한다.
    { printf '%s\n0\n' "$_scv_mark" > "$_scv_turn"; } 2>/dev/null || true
  fi
fi
# ---------- /help 강제 -------------------------------------------------------

# 기록은 되돌림보다 먼저 한다. 되돌리는 턴에서 기록을 건너뛰면, 호스트가 연속 차단
# 상한에서 턴을 끊었을 때 그 턴의 답이 팀 기록에서 통째로 사라진다 — 기존 저널 계약이
# 그 구멍을 잡았다. 함수로 감싼 이유는 아래 이른 반환들이 훅 전체를 끝내면 안 되기
# 때문이다.
_scv_journal_turn() {
  [[ -f "$JOURNAL_APPEND" ]] || return 0
  [[ -n "$INPUT" ]] || return 0

  TRANSCRIPT=""
  if command -v jq >/dev/null 2>&1; then
    TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r 'try (.transcript_path // empty)' 2>/dev/null || true)"
  elif command -v python3 >/dev/null 2>&1; then
    TRANSCRIPT="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    p = d.get("transcript_path", "")
    sys.stdout.write(p if isinstance(p, str) else "")
except Exception:
    pass' 2>/dev/null || true)"
  fi
  [[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]] || return 0

  # Transcript scan needs jq's tolerant per-line parse (fromjson?). Without jq,
  # skip quietly — journaling is best-effort by contract.
  command -v jq >/dev/null 2>&1 || return 0

  SUMMARY="$(tail -n 200 "$TRANSCRIPT" 2>/dev/null \
    | jq -Rr 'fromjson? | select(.type? == "assistant")
              | (.message.content[]? | select(.type? == "text") | .text) // empty' 2>/dev/null \
    | tail -n 40 | tail -c 4000 || true)"
  # The byte cap above can land inside a multibyte character (Korean, Japanese,
  # emoji are 3–4 bytes each), leaving the tail of one character — up to three
  # continuation bytes (0x80–0xBF) — at the head of the entry; one such byte is
  # enough to make an editor misread the whole journal file. Strip them with
  # POSIX tools only (head/tail/od), so every host behaves the same; iconv -c is
  # a second, optional pass where it exists (GNU iconv exits 1 when it drops
  # bytes and BSD iconv may emit nothing on invalid input — so judge by output).
  for _ in 1 2 3; do
    _scv_b="$(printf '%s' "$SUMMARY" | head -c1 | od -An -tu1 2>/dev/null | tr -d ' \n')"
    [[ -n "$_scv_b" && "$_scv_b" -ge 128 && "$_scv_b" -le 191 ]] || break
    SUMMARY="$(printf '%s' "$SUMMARY" | tail -c +2)"
  done
  if command -v iconv >/dev/null 2>&1; then
    _scv_clean="$(printf '%s' "$SUMMARY" | iconv -c -f UTF-8 -t UTF-8 2>/dev/null || true)"
    [[ -n "${_scv_clean//[[:space:]]/}" ]] && SUMMARY="$_scv_clean"
  fi
  if command -v python3 >/dev/null 2>&1; then
    _scv_clean="$(printf '%s' "$SUMMARY" | python3 -c 'import sys; sys.stdout.buffer.write(sys.stdin.buffer.read().decode("utf-8","ignore").encode("utf-8"))' 2>/dev/null || true)"
    [[ -n "${_scv_clean//[[:space:]]/}" ]] && SUMMARY="$_scv_clean"
  fi
  [[ -n "${SUMMARY//[[:space:]]/}" ]] || return 0

  printf '%s\n' "$SUMMARY" | bash "$JOURNAL_APPEND" --speaker assistant >/dev/null 2>&1 || true
}

_scv_journal_turn

# 기록이 끝났으니 이제 되돌린다. 결정은 위에서 이미 났다.
if [[ -n "$SCV_FORCE_BLOCK_REASON" ]]; then
  _scv_emit_block "$SCV_FORCE_BLOCK_REASON" || true
fi
exit 0
