#!/usr/bin/env bash
# on-choice-answer.sh — host hook template (SCV Core, v0.65.0+).
#
# Purpose: the user just answered the host's choice tool (contracts/choices.md) in
# the middle of a turn. An answer can change what the turn is about, so the
# rewritten request registered before it may be stale. Record that the answer came
# after the turn's last registration; the write gate (guard Rule P) then asks for a
# fresh registration — or a one-line `register --keep` when the scope is unchanged —
# before the next editor write.
#
# Contract (see docs/wrapper-integration.md §6 "Hook seam" in scv-core):
#   - Registration is WRAPPER-OWNED: register this template for the event that
#     fires after the host's choice tool returns the user's answer (for a host
#     with hook events per tool, the post-tool event matched to that tool). A host
#     without a choice tool registers nothing — the gate then never asks for this.
#   - stdin carries ONE JSON object; `session_id` (whose turn) and `agent_id`
#     (present only inside a subagent — ignored) are read. Nothing else.
#   - The wrapper should export SCV_CORE_ROOT; without it, the template falls back
#     to its in-payload location.
#
# NON-BLOCKING GUARANTEE: this hook never fails or blocks the session — invalid
# JSON, missing jq, no turn, switch off, or an un-hydrated project → exit 0 with
# nothing written and nothing printed.
set -u

[[ -d scv ]] || exit 0
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" 2>/dev/null && pwd )" || exit 0
_scv_mp="${SCV_CORE_ROOT:-$SCRIPT_DIR/../..}/scripts/model-prompting.sh"
[[ -f "$_scv_mp" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(head -c 1048576 2>/dev/null || true)"
[[ -n "$INPUT" ]] || exit 0
_scv_sid="$(printf '%s' "$INPUT" | jq -r 'try (.session_id // empty)' 2>/dev/null || true)"
_scv_agent="$(printf '%s' "$INPUT" | jq -r 'try (.agent_id // empty)' 2>/dev/null || true)"
[[ -z "$_scv_agent" ]] || exit 0

if [[ -n "$_scv_sid" ]]; then
  bash "$_scv_mp" answered --session "$_scv_sid" >/dev/null 2>&1 || true
else
  bash "$_scv_mp" answered >/dev/null 2>&1 || true
fi

# ---------- turn plan check (0.87.0+) ----------------------------------------
# 선택 답을 진행 중 계획의 `## 변경 이력` 에 바로 적는다(질문 · 답) — 폰에서도 계획 파일과 대시보드로 결정이 보이게.
# 답은 tool_response.answers({질문: 답}) 에서, 없으면 글 모양 '"질문"="답"' 에서 꺼낸다. SCV_TURN_PLAN_CHECK=off 면 적지 않는다.
_scv_tc_sh="${SCV_CORE_ROOT:-$SCRIPT_DIR/../..}/scripts/turn-check.sh"
if [[ -f "$_scv_tc_sh" ]]; then
  _scv_qa="$(printf '%s' "$INPUT" | jq -r '
      try (
        (.tool_response | if type == "object" then (.answers // {}) else {} end | to_entries[] | [.key, (.value | tostring)])
      ) catch empty | @tsv' 2>/dev/null || true)"
  if [[ -z "$_scv_qa" ]]; then
    _scv_qa="$(printf '%s' "$INPUT" | jq -r 'try (.tool_response | if type == "string" then . elif type == "array" then (map(.text? // "") | join("")) else "" end) catch ""' 2>/dev/null \
      | sed -n 's/.*"\(.*\)"="\([^"]*\)".*/\1	\2/p' | head -n 4 || true)"
  fi
  while IFS=$'\t' read -r _scv_q _scv_a; do
    [[ -n "$_scv_q$_scv_a" ]] || continue
    bash "$_scv_tc_sh" choice --question "$_scv_q" --answer "$_scv_a" >/dev/null 2>&1 || true
  done <<< "$_scv_qa"
fi

# ---------- recommended effort (0.89.2+) --------------------------------------
# 이번 턴에 effort 요청 줄이 실렸고 그 질문을 선택 창으로 물었으면 '물었다'로 적는다 — 질문 글만 넘기고 판단은 코어가 한다.
# 실린 줄이 없으면(대부분의 턴) 아무 일도 없다.
_scv_eq="$(printf '%s' "$INPUT" | jq -r 'try ([.tool_input.questions[]?.question // empty] | join("\n")) catch ""' 2>/dev/null || true)"
[[ -n "$_scv_eq" ]] || _scv_eq="$(printf '%s' "${_scv_qa:-}" | cut -f1)"
if [[ -n "$_scv_eq" ]]; then
  if [[ -n "$_scv_sid" ]]; then printf '%s' "$_scv_eq" | bash "$_scv_mp" effort-seen --session "$_scv_sid" >/dev/null 2>&1 || true
  else printf '%s' "$_scv_eq" | bash "$_scv_mp" effort-seen >/dev/null 2>&1 || true; fi
fi
exit 0
