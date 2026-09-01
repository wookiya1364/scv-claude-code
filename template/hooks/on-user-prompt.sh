#!/usr/bin/env bash
# on-user-prompt.sh — host hook template (SCV Core, v0.22.0+).
#
# Purpose: capture EVERY user prompt (free conversation included — turns that
# never invoke an action:*) into the committed team journal.
#
# Contract (see docs/wrapper-integration.md §6 "Hook seam" in scv-core):
#   - The host agent's user-prompt-submit hook event (e.g. the event named
#     `UserPromptSubmit`) pipes ONE JSON object to stdin containing a `prompt`
#     string field. This template extracts `.prompt` and appends it via
#     journal-append.sh, whose redaction filter runs BEFORE anything is
#     written (password/token/secret/api-key/Bearer/AKIA → [REDACTED]).
#   - Registration/installation is WRAPPER-OWNED — Core ships only this
#     template and the contract (same ownership boundary as update/set-models).
#   - The wrapper should export SCV_CORE_ROOT (the materialized core/ dir);
#     without it, the template falls back to its in-payload location.
#
# NON-BLOCKING GUARANTEE: this hook never fails the session. Invalid JSON,
# empty prompt, missing jq/python3, or an un-hydrated project → exit 0, no
# write. Wrappers copying this template must preserve that guarantee.
set -u

# Un-hydrated / non-SCV project → nothing to journal.
[[ -d scv ]] || exit 0

# Plain-language reminder (v0.31.0+). This hook's stdout is the one channel that
# reaches the model on EVERY turn, commands or not — both hosts add it to the
# model's context. Print the answer shape unless the project .env turns it off:
# SCV_PLAIN_LANGUAGE absent / on / anything else = on; only off (any case) = off.
# Read the one line with sed — never source .env (secrets, nounset). The text
# goes to stdout only; it is never written into the journal.
# 값은 settings 라이브러리로 읽는다 — 설정을 읽는 입구는 하나다. 라이브러리를
# 못 찾으면 예전 방식으로 떨어진다: 이 훅은 어떤 경우에도 세션을 막지 않는다.
_scv_settings_lib="${SCV_CORE_ROOT:-$( cd "$( dirname "${BASH_SOURCE[0]}" )/../.." 2>/dev/null && pwd )}/scripts/lib/settings.sh"
if [[ -f "$_scv_settings_lib" ]]; then
  # shellcheck disable=SC1090
  source "$_scv_settings_lib" 2>/dev/null || true
fi
_scv_read() {  # <KEY> — 라이브러리가 없으면 기본값으로 간다.
  # .env 로 되돌아가지 않는다: 설정은 scv/ 아래 두 파일에만 있다. 옛 파일을 몰래
  # 읽으면 "이 값이 어디서 왔지" 가 그대로 남는다.
  declare -F settings_get >/dev/null 2>&1 || return 0
  settings_get "$1" 2>/dev/null || true
}

_scv_plain="$(_scv_read SCV_PLAIN_LANGUAGE | tr -d '"[:space:]' | tr -d "'" | tr '[:upper:]' '[:lower:]' || true)"
if [[ "${_scv_plain:-on}" != "off" ]]; then
  # Sentence cap (v0.31.0+): .env SCV_PLAIN_MAX_SENTENCES=<n>, positive integer
  # only — absent or anything else means 2. Rendered into the first rule.
  _scv_cap="$(_scv_read SCV_PLAIN_MAX_SENTENCES | tr -d '"[:space:]' | tr -d "'" || true)"
  [[ "$_scv_cap" =~ ^[1-9][0-9]*$ ]] || _scv_cap=2
  if [[ "$_scv_cap" == "1" ]]; then _scv_first="one sentence"; else _scv_first="1–${_scv_cap} sentences"; fi
  cat <<PLAIN
[SCV plain language] Answer shape: (1) first, ${_scv_first} — lead with what
the user gets; (2) then one example; (3) no code values (paths, variable names,
versions, settings) before the user asks — use plain names; (4) detail after,
only when wanted. Identifiers the user needs to act on stay exact, after the
plain summary. Switches: scv/scv_settings.json SCV_PLAIN_LANGUAGE=off (silence),
SCV_PLAIN_MAX_SENTENCES=<n> (sentence cap, default 2).
PLAIN
fi

# 라우팅 스위치. 켜져 있으면 아래 preflight 가 지시 블록과 진단을 싣는다 —
# 0.41.0 부터 안내 문구는 preflight 블록에 흡수됐다. 무시되는 지시가 둘이면
# 서로를 약화시키므로, 같은 요구는 한 곳에서만 한다.
_scv_always="$(_scv_read SCV_ALWAYS_ON | tr -d '"[:space:]' | tr -d "'" | tr '[:upper:]' '[:lower:]' || true)"

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" 2>/dev/null && pwd )" || exit 0
CORE_HOME="${SCV_CORE_ROOT:-$SCRIPT_DIR/../..}"
JOURNAL_APPEND="$CORE_HOME/scripts/journal-append.sh"
# 표준입력은 여기서 한 번만 읽는다. 저널 기록은 아래에서 이 값을 그대로 쓴다.
INPUT="$(cat 2>/dev/null || true)"

# ---------- preflight (v0.40.0+) --------------------------------------------
# 이 훅이 하는 일은 강제가 아니라 **준비**다. 이번 턴의 프로젝트 상태를 미리 실어
# 보내면, 그것을 확인하려고 액션을 한 번 더 부를 이유가 사라진다.
#
# 0.39.0 은 같은 목적을 응답 종료 시점의 되돌림으로 달성하려 했고, 그것이 비쌌다 —
# 되돌림은 모델이 답을 다 쓴 뒤에 걸리므로 되돌릴 때마다 답이 통째로 다시
# 생성됐다. 지점을 턴의 시작으로 옮기면 반복할 일 자체가 없다.
#
# 실려 나가는 것은 셋이다: 진단(점검 출력에서 개요·명령 목록을 뺀 뒷부분), 분류
# 지침(앞/뒤/둘 다 아님), 표시줄 한 줄. 스위치가 꺼졌거나 문자열부를 못 찾으면
# 아무 것도 하지 않는다 — 기존 NON-BLOCKING 보장이 여기서도 상한이다.
_scv_force_lib="$CORE_HOME/scripts/lib/force-help.sh"
if [[ -f "$_scv_force_lib" ]]; then
  # shellcheck disable=SC1090
  source "$_scv_force_lib" 2>/dev/null || true
fi
# 전체 스위치가 꺼져 있으면 여기서 끝난다 — 지시도 진단도 없다. 대체된 계획의
# 검사에 있던 성질이고, 새 검사가 이어받는다.
if [[ "${_scv_always:-on}" != "off" ]] && declare -F scv_force_routing >/dev/null 2>&1; then
  _scv_pre="$(scv_force_switch "$(_scv_read SCV_FORCE_HELP)")"
  # 지시가 먼저, 진단이 나중이다. 0.40.0 은 반대였고 명령이 40줄 뒤에 묻혀
  # 무시됐다. 읽는 쪽에서 명령은 맨 앞에 와야 한다.
  scv_force_routing
  printf '\n'
  if [[ "$_scv_pre" == "on" ]]; then
    printf '%s\n' "$(scv_force_banner "$_scv_pre")"
    # 점검이 실패하거나 없으면 진단 없이 지시만 간다. 막지 않는다.
    _scv_probe="$CORE_HOME/scripts/help.sh"
    if [[ -f "$_scv_probe" ]]; then
      _scv_diag="$(bash "$_scv_probe" 2>/dev/null | scv_force_trim_diagnosis || true)"
      [[ -n "${_scv_diag//[[:space:]]/}" ]] && printf '%s\n' "$_scv_diag"
    fi
    printf '\n'
  fi
fi
# ---------- /preflight -------------------------------------------------------

[[ -f "$JOURNAL_APPEND" ]] || exit 0
[[ -n "$INPUT" ]] || exit 0

PROMPT=""
if command -v jq >/dev/null 2>&1; then
  PROMPT="$(printf '%s' "$INPUT" | jq -r 'try (.prompt // empty)' 2>/dev/null || true)"
elif command -v python3 >/dev/null 2>&1; then
  PROMPT="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    p = d.get("prompt", "")
    sys.stdout.write(p if isinstance(p, str) else "")
except Exception:
    pass' 2>/dev/null || true)"
fi
[[ -n "$PROMPT" ]] || exit 0   # invalid JSON or no prompt → quietly skip

printf '%s\n' "$PROMPT" | bash "$JOURNAL_APPEND" --speaker user >/dev/null 2>&1 || true
exit 0
