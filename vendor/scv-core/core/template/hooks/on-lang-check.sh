#!/usr/bin/env bash
# on-lang-check.sh — host hook template (SCV Core, 0.79.0+, 계획 lang-enforce-079).
#
# Purpose: 설정 언어(SCV_LANG)가 korean 인데 도구 사이 중간 보고가 다른 언어로 흐르면, 그 턴 안에서 바로 교정한다.
# 도구가 끝날 때마다 지난 검사 뒤에 새로 쓴 어시스턴트 글만 보고(lib/lang-enforce.sh scv_lang_new_text), 다른 언어 줄을
# 세어(lib/help-state.sh scv_lint_lang_turn) 있으면 교정 문구 한 줄을 모델에게 덧붙인다. 이미 화면에 나간 글은 되돌리지 못한다 —
# 다음 글부터 바로잡는다. 최종 답은 종료 훅(on-stop.sh)이 막는다.
#
# Contract (see docs/wrapper-integration.md §6 "Hook seam" in scv-core):
#   - Registration is WRAPPER-OWNED: register this template for the event that fires after every tool call
#     (for a host with hook events per tool, the post-tool event with no tool filter) and that accepts extra
#     context for the model in its output. A host without such an event registers nothing — the stop hook and
#     the per-turn rule line still apply.
#   - stdin carries ONE JSON object; `transcript_path`, `session_id` and `agent_id` (present only inside a
#     subagent — then nothing is done) are read. The output, when there is one, is one JSON object:
#     {"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"<교정 문구>"}}.
#   - 지난 검사 위치는 이번 턴 폴더의 .help-lang-seen 한 줄(마지막으로 본 글 id)에 남긴다.
#
# 막지 않는다: 깨진 입력 · jq 없음 · 원본 없음 · 설정 없음 · scv/ 없음이면 아무것도 내지 않고 exit 0.
set -u

[[ -d scv ]] || exit 0
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" 2>/dev/null && pwd )" || exit 0
_scv_core="${SCV_CORE_ROOT:-$SCRIPT_DIR/../..}"
command -v jq >/dev/null 2>&1 || exit 0
for _scv_f in settings.sh help-state.sh lang-enforce.sh turn-stream.sh; do
  [[ -f "$_scv_core/scripts/lib/$_scv_f" ]] || exit 0
  # shellcheck disable=SC1090
  source "$_scv_core/scripts/lib/$_scv_f" 2>/dev/null || exit 0
done

_scv_lang="$(settings_get SCV_LANG 2>/dev/null | tr -d '"[:space:]' | tr -d "'" | tr '[:upper:]' '[:lower:]' || true)"
[[ "$_scv_lang" == korean || "$_scv_lang" == ko ]] || exit 0
_scv_lint="$(settings_get SCV_ANSWER_LINT 2>/dev/null | tr -d '"[:space:]' | tr '[:upper:]' '[:lower:]' || true)"
[[ "$_scv_lint" == off ]] && exit 0

INPUT="$(head -c 1048576 2>/dev/null || true)"
[[ -n "$INPUT" ]] || exit 0
[[ -z "$(printf '%s' "$INPUT" | jq -r 'try (.agent_id // empty)' 2>/dev/null)" ]] || exit 0
TRANSCRIPT="$(printf '%s' "$INPUT" | jq -r 'try (.transcript_path // empty)' 2>/dev/null || true)"
[[ -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]] || exit 0
_scv_sess="$(printf '%s' "$INPUT" | jq -r 'try (.session_id // empty)' 2>/dev/null | head -c 256 | LC_ALL=C tr -d '\n\r\037' || true)"

# 이번 턴 폴더 — 종료 훅과 같은 자리(model-prompting.sh session). 못 구하면 저널 폴더.
_scv_tdir="${SCV_JOURNAL_DIR:-scv/journal}"
_scv_mp="$_scv_core/scripts/model-prompting.sh"
if [[ -f "$_scv_mp" ]]; then
  if [[ -n "$_scv_sess" ]]; then _scv_so="$(bash "$_scv_mp" session --session "$_scv_sess" 2>/dev/null || true)"
  else _scv_so="$(bash "$_scv_mp" session 2>/dev/null || true)"; fi
  [[ "$(printf '%s\n' "$_scv_so" | sed -n 's/^HUMAN: //p' | head -n 1)" == "0" ]] && exit 0
  _scv_d="$(printf '%s\n' "$_scv_so" | sed -n 's/^TURN_DIR: //p' | head -n 1)"; [[ -n "$_scv_d" ]] && _scv_tdir="$_scv_d"
fi
_scv_seen_file="$_scv_tdir/.help-lang-seen"
_scv_seen=""
[[ -f "$_scv_seen_file" && ! -L "$_scv_seen_file" ]] && _scv_seen="$(head -c 256 "$_scv_seen_file" 2>/dev/null | head -n 1)"

# 사용자가 이 턴에 다른 언어를 요청했거나 다른 언어로 썼으면 교정하지 않는다(SCV.md Top-level rules 7조).
[[ "$(scv_lang_user_other "$(_scv_turn_prompt 400)")" == 1 ]] && exit 0
_scv_list="$(_scv_turn_texts 400 | tail -c 65536)"
[[ -n "$_scv_list" ]] || exit 0
_scv_new="$(scv_lang_new_text "$_scv_list" "$_scv_seen")"
[[ -n "$_scv_new" ]] || exit 0
_scv_lastid="${_scv_new%%$'\x1f'*}"; _scv_text="${_scv_new#*$'\x1f'}"
if [[ "$_scv_lastid" != "$_scv_seen" && ! -L "$_scv_seen_file" ]] && mkdir -p "$_scv_tdir" 2>/dev/null; then
  printf '%s\n' "$_scv_lastid" > "$_scv_seen_file" 2>/dev/null || true
fi
[[ "$_scv_text" == *[![:space:]]* ]] || exit 0

_scv_n="$(scv_lint_lang_turn "" "$_scv_text" "$_scv_lang" | sed -n 's/^lang-mismatch-lines=//p')"
_scv_note="$(scv_lang_fix_note "$_scv_lang" "${_scv_n:-0}" mid)"
[[ -n "$_scv_note" ]] || exit 0
jq -cn --arg c "$_scv_note" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$c}}' 2>/dev/null || true
exit 0
