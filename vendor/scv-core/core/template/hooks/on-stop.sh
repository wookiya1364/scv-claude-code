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
JOURNAL_APPEND="${SCV_CORE_ROOT:-$SCRIPT_DIR/../..}/scripts/journal-append.sh"
[[ -f "$JOURNAL_APPEND" ]] || exit 0

INPUT="$(cat 2>/dev/null || true)"
[[ -n "$INPUT" ]] || exit 0

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
[[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]] || exit 0

# Transcript scan needs jq's tolerant per-line parse (fromjson?). Without jq,
# skip quietly — journaling is best-effort by contract.
command -v jq >/dev/null 2>&1 || exit 0

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
# ---------- drift check (v0.50.0+, 본문 출처 v0.51.0+) -----------------------
# 규약 지문 메아리 + 답 모양 린트. 이번 턴의 대화 기록에 이 세션의 규약 지문이 있는지, 직전 답의
# 골격이 답 모양 계약 안인지를 표식 스크립트가 판정한다 — 흐려졌으면 표식을 protocol=0 으로 되돌리고
# 다음 턴 훅이 실을 경고 한 줄을 예약한다. 답을 막거나 고치지 않는다. 어떤 실패도 exit 0.
# 린트가 볼 본문의 출처(v0.51.0+): (1) 호스트가 stdin 에 넘긴 `last_assistant_message` — 공식 문서가
# "원본은 비동기로 적혀 늦을 수 있으니 이 값을 쓰라" 고 명시한다. (2) 그 값이 없는 호스트에서는 원본에서
# 마지막 사람 프롬프트 이후의 어시스턴트 텍스트만 보고, 아직 안 적혔으면 짧게(4회 × 250ms) 다시 읽는다.
# (3) 그래도 없으면 이번 턴 린트를 생략한다 — 낡은 답(한 턴 전)을 보느니 안 본다. 지문 검사는 그대로 돈다.
_scv_core="${SCV_CORE_ROOT:-$SCRIPT_DIR/../..}"
_scv_hs="$_scv_core/scripts/help-state.sh"
_scv_hslib="$_scv_core/scripts/lib/help-state.sh"
if [[ -f "$_scv_hs" && -f "$_scv_hslib" ]]; then
  _scv_settings_lib="$_scv_core/scripts/lib/settings.sh"
  # shellcheck disable=SC1090
  [[ -f "$_scv_settings_lib" ]] && source "$_scv_settings_lib" 2>/dev/null || true
  # shellcheck disable=SC1090
  source "$_scv_hslib" 2>/dev/null || true
  _scv_get() { declare -F settings_get >/dev/null 2>&1 || return 0; settings_get "$1" 2>/dev/null || true; }
  _scv_sw() { local v; v="$(printf '%s' "${1:-}" | tr -d '"[:space:]' | tr -d "'" | tr '[:upper:]' '[:lower:]')"; [[ "$v" == "off" ]] && printf 'off' || printf 'on'; }
  _scv_echo="$(_scv_sw "$(_scv_get SCV_HELP_ECHO)")"; _scv_lint="$(_scv_sw "$(_scv_get SCV_ANSWER_LINT)")"
  # 규약을 매 턴 읽는 프로젝트(SCV_HELP_LOAD_ONCE=off)에서는 지문이 무의미 — 메아리만 끈다.
  [[ "$(_scv_sw "$(_scv_get SCV_HELP_LOAD_ONCE)")" == "off" ]] && _scv_echo="off"
  if [[ "$_scv_echo" == "on" || "$_scv_lint" == "on" ]]; then   # 둘 다 off 면 읽지도 쓰지도 않는다 (0.49 와 같음)
    _scv_cap="$(printf '%s' "$(_scv_get SCV_PLAIN_MAX_SENTENCES)" | tr -d '"[:space:]' | tr -d "'")"
    [[ "$_scv_cap" =~ ^[1-9][0-9]*$ ]] || _scv_cap=2
    _scv_last=""; _scv_src="none"
    if [[ "$_scv_lint" == "on" ]] && declare -F scv_turn_slice >/dev/null 2>&1 && declare -F scv_stop_pick_source >/dev/null 2>&1; then
      _scv_host="$(printf '%s' "$INPUT" | jq -r 'try (.last_assistant_message // empty)' 2>/dev/null | head -c 65536 || true)"
      _scv_turn=""
      if [[ -z "${_scv_host//[[:space:]]/}" ]]; then
        for _scv_try in 1 2 3 4; do
          _scv_stream="$(tail -n 400 "$TRANSCRIPT" 2>/dev/null \
            | jq -Rr 'fromjson? | if .type? == "user" then
                        (if ((.message.content|type) == "string")
                            or ((.message.content|type) == "array" and any(.message.content[]?; .type? == "text"))
                         then "U" else empty end)
                      elif .type? == "assistant" then
                        ("A\u001f" + ([.message.content[]? | select(.type? == "text") | .text] | join("\n") | gsub("\n"; "\u001e")))
                      else empty end' 2>/dev/null || true)"
          _scv_turn="$(scv_turn_slice "$_scv_stream" | head -c 65536)"
          [[ -n "${_scv_turn//[[:space:]]/}" ]] && break
          [[ "$_scv_try" -lt 4 ]] && sleep 0.25
        done
      fi
      _scv_pick="$(scv_stop_pick_source "$_scv_host" "$_scv_turn")"
      _scv_src="${_scv_pick%%$'\x1f'*}"; _scv_last="${_scv_pick#*$'\x1f'}"
    fi
    printf '%s' "$_scv_last" | bash "$_scv_hs" stop --echo "$_scv_echo" --lint "$_scv_lint" --cap "$_scv_cap" --src "$_scv_src" >/dev/null 2>&1 || true
  fi
fi
# ---------- /drift check -----------------------------------------------------

[[ -n "${SUMMARY//[[:space:]]/}" ]] || exit 0

printf '%s\n' "$SUMMARY" | bash "$JOURNAL_APPEND" --speaker assistant >/dev/null 2>&1 || true
exit 0
