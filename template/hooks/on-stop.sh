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
  [[ "$_scv_clean" == *[![:space:]]* ]] && SUMMARY="$_scv_clean"
fi
if command -v python3 >/dev/null 2>&1; then
  _scv_clean="$(printf '%s' "$SUMMARY" | python3 -c 'import sys; sys.stdout.buffer.write(sys.stdin.buffer.read().decode("utf-8","ignore").encode("utf-8"))' 2>/dev/null || true)"
  [[ "$_scv_clean" == *[![:space:]]* ]] && SUMMARY="$_scv_clean"
fi
# ---------- drift check (v0.50.0+, 본문 출처 v0.51.0+) -----------------------
# 규약 지문 메아리 + 답 모양 린트. 이번 턴의 대화 기록에 이 세션의 규약 지문이 있는지, 직전 답의
# 골격이 답 모양 계약 안인지를 표식 스크립트가 판정한다 — 흐려졌으면 표식을 protocol=0 으로 되돌리고
# 다음 턴 훅이 실을 경고 한 줄을 예약한다. 답을 막거나 고치지 않는다. 어떤 실패도 exit 0.
# 린트가 볼 본문의 출처(v0.51.0+): (1) 호스트가 stdin 에 넘긴 `last_assistant_message` — 공식 문서가
# "원본은 비동기로 적혀 늦을 수 있으니 이 값을 쓰라" 고 명시한다. (2) 그 값이 없는 호스트에서는 원본에서
# 마지막 사람 프롬프트 이후의 어시스턴트 텍스트만 보고, 아직 안 적혔으면 짧게(4회 × 250ms) 다시 읽는다.
# (3) 그래도 없으면 이번 턴 린트를 생략한다 — 낡은 답(한 턴 전)을 보느니 안 본다. 지문 검사는 그대로 돈다.
# 원본 → 턴 스트림: 줄마다 "U"(사람이 쓴 프롬프트) 또는 "A\x1f<텍스트, 줄바꿈은 \x1e>". 자르기는 scv_turn_slice.
# v0.64.0+ — (1) 호스트의 내부 메시지(내부 표시 isMeta — 스킬 불러오기 · 종료 훅 피드백 등)는 사람 프롬프트가 아니다. 그것을
# U 로 세면 같은 턴에서 그보다 앞서 보인 답(다시 쓴 요청 인용 등)이 이번 턴에서 빠진다. (2) 자르기는 jq 한 번에 한다 — 마지막
# U 뒤만, 앞쪽 A 400개 + 마지막 A 하나로 낸다(긴 턴에서도 뒤의 bash 처리가 작다). U 가 없으면 아무것도 내지 않는다.
# (3) 도구가 만든 사용자 몫 글(도구 출처 표시 sourceToolUseID)도 사람 프롬프트가 아니다 — 내부 표시와 둘 중 하나만 있어도 뺀다
# (호스트가 한쪽 이름을 바꿔도 다른 쪽이 남는다; 로컬 원본 25개에서 사람 프롬프트에 출처 표시가 붙은 일은 0건). (4) 창 안에
# 사람 · 모델 줄이 하나도 없으면(이 형식이 아닌 원본 — 예: 코덱스 세션 기록) "N" 하나만 낸다: 넓혀 찾지 않고, 경계 기록도 남기지
# 않는다(자르기는 빈 값 — 이 기능 전과 같은 판정).
_scv_turn_stream() {  # [원본 끝에서 읽을 줄 수 — 기본 400]
  tail -n "${1:-400}" "$TRANSCRIPT" 2>/dev/null \
    | jq -Rrn '[inputs | fromjson? | if .type? == "user" then
                  (if (.isMeta? == true) or (.sourceToolUseID? != null) then empty
                   elif ((.message.content|type) == "string")
                      or ((.message.content|type) == "array" and any(.message.content[]?; .type? == "text"))
                   then "U" else empty end)
                elif .type? == "assistant" then
                  ("A\u001f" + ([.message.content[]? | select(.type? == "text") | .text] | join("\n") | gsub("\n"; "\u001e")))
                else empty end] as $s
               | ([range(0; $s | length) | select($s[.] == "U")] | last) as $i
               | if ($s | length) == 0 then "N" elif $i == null then empty
                 else ($s[($i + 1):]) as $t
                   | "U", ($t[:400][]), (if ($t | length) > 400 then $t[-1] else empty end)
                 end' 2>/dev/null || true
}
# v0.64.0+ — 창 안에 사람 프롬프트가 없으면(선택지 질문 · 도구 결과가 많은 긴 턴) 창을 넓혀 이번 사람 턴의 경계를 찾는다:
# 400 → 4000 → 40000 줄. 끝내 못 찾으면 아무것도 내지 않는다(자르기는 빈 값 — 지금처럼 안전 쪽). 기록은 부른 쪽이 한 번 남긴다.
# 창이 이 형식이 아니면("N") 그대로 돌려준다 — 넓혀도 찾을 것이 없다.
_scv_turn_stream_wide() {
  local n s="" total
  total="$(wc -l < "$TRANSCRIPT" 2>/dev/null | tr -d ' ')"; [[ "$total" =~ ^[0-9]+$ ]] || total=0
  for n in 400 4000 40000; do
    s="$(_scv_turn_stream "$n")"
    [[ -n "$s" ]] && { printf '%s' "$s"; return 0; }
    (( total <= n )) && break
  done
  return 0
}
_scv_core="${SCV_CORE_ROOT:-$SCRIPT_DIR/../..}"
# ---------- session (v0.65.0+) -----------------------------------------------
# 이번 턴 상태는 세션마다 따로 있다(model-prompting.sh 머리말). 자리와 "이 세션이 사람 메시지를 받았나" 는 그 명령이 정한다.
# 사람 메시지를 받지 않은 세션(팀원 · 하위 에이전트 — 리드가 일을 맡긴 세션)은 등록 · 원칙 · 선택지 검사와 답 모양 검사를 하지
# 않는다: 그 세션의 답은 사람이 아니라 리드가 읽고, 리드의 등록 · 막기 기록 · 경고를 건드리면 안 된다(2026-10-03 실측: 분석
# 에이전트 6개 중 5개가 리드의 등록 때문에 막혔다). 세션 id 가 없으면 이 기능 전과 같다(가장 최근 사람 턴의 자리, 검사 모두).
_scv_sess="$(printf '%s' "$INPUT" | jq -r 'try (.session_id // empty)' 2>/dev/null | head -c 256 | LC_ALL=C tr -d '\n\r\037' 2>/dev/null || true)"
_scv_jdir="${SCV_JOURNAL_DIR:-scv/journal}"
_scv_tdir="$_scv_jdir"; _scv_human=1
_scv_mp="$_scv_core/scripts/model-prompting.sh"
if [[ -f "$_scv_mp" ]]; then
  if [[ -n "$_scv_sess" ]]; then _scv_so="$(bash "$_scv_mp" session --session "$_scv_sess" 2>/dev/null || true)"
  else _scv_so="$(bash "$_scv_mp" session 2>/dev/null || true)"; fi
  _scv_d="$(printf '%s\n' "$_scv_so" | sed -n 's/^TURN_DIR: //p' | head -n 1)"; [[ -n "$_scv_d" ]] && _scv_tdir="$_scv_d"
  [[ "$(printf '%s\n' "$_scv_so" | sed -n 's/^HUMAN: //p' | head -n 1)" == "0" ]] && _scv_human=0
fi
# 하위 에이전트 안의 멈춤(훅 입력의 에이전트 id)도 하위 세션이다 — 지금 래퍼는 그 사건을 걸지 않지만, 걸려도 리드의 검사를 하지 않게.
[[ -n "$(printf '%s' "$INPUT" | jq -r 'try (.agent_id // empty)' 2>/dev/null)" ]] && _scv_human=0
_scv_sarg=(); [[ -n "$_scv_sess" ]] && _scv_sarg=(--session "$_scv_sess")
# ---------- /session ---------------------------------------------------------
_scv_hs="$_scv_core/scripts/help-state.sh"
_scv_hslib="$_scv_core/scripts/lib/help-state.sh"
if [[ "$_scv_human" == 1 && -f "$_scv_hs" && -f "$_scv_hslib" ]]; then
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
      if [[ "$_scv_host" != *[![:space:]]* ]]; then
        for _scv_try in 1 2 3 4; do
          _scv_stream="$(_scv_turn_stream_wide)"
          _scv_turn="$(scv_turn_slice "$_scv_stream" | head -c 65536)"
          [[ "$_scv_turn" == *[![:space:]]* ]] && break
          [[ "$_scv_stream" == "N" ]] && break   # 이 형식이 아닌 원본 — 다시 읽어도 같다
          [[ "$_scv_try" -lt 4 ]] && sleep 0.25
        done
      fi
      _scv_pick="$(scv_stop_pick_source "$_scv_host" "$_scv_turn")"
      _scv_src="${_scv_pick%%$'\x1f'*}"; _scv_last="${_scv_pick#*$'\x1f'}"
    fi
    printf '%s' "$_scv_last" | bash "$_scv_hs" stop --echo "$_scv_echo" --lint "$_scv_lint" --cap "$_scv_cap" --src "$_scv_src" --turn-dir "$_scv_tdir" >/dev/null 2>&1 || true
  fi
fi
# ---------- /drift check -----------------------------------------------------

# v0.60.0+ — 모델별 가이드를 결과로 판정한다. help 가 이번 턴에 가이드를 냈을 때만(.help-guide-turn) 읽음 표시와
# 답의 인용을 보고, 어긋나면 다음 턴 경고를 덧붙인다. 답 본문은 위 드리프트 검사가 고른 것을 그대로 쓴다(없으면 빈 값 —
# 그러면 "보였나" 는 판정하지 않는다). 어떤 실패도 막지 않는다.
# v0.62.0+ — 매 턴 등록 판정도 같은 호출이 한다: 이번 턴 요청을 등록하지 않았거나 다시 쓴 요청을 답에 보이지 않았으면
# 끝내기를 막고 계속하게 한다. 막는 출력은 저널 기록을 마친 뒤, 훅이 끝날 때 한 번 낸다.
# v0.64.2+ — 검사마다 한 턴에 한 번(계획 stop-gates-each-once). 규칙은 contracts/choices.md 7항 한 곳, '이미 전달' 판단은
# lib/stop-gates.sh(순수 — 그 머리말이 경우를 모두 적는다). 여기는 효과만: 훅 입력 · 턴 표 · 이번 턴 전달 기록(.help-turn-gates)을
# 읽고, 막을 때만 기록을 쓰고, 첫 멈춤에서 같은 세션의 지난 기록을 지우고, 계속 중인 멈춤은 쓴 기록을 다시 읽어 확인했을 때만
# 막는다(못 남겼으면 다음 턴 경고). 0.64.1 까지는 막을 기회가 턴 전체에 하나뿐이라, 등록 판정이 먼저 막은 턴에는 선택지 · 원칙
# 판정이 차례를 받지 못했다(2026-10-02 설치본 대화형 재현).
_scv_sgl="${SCV_CORE_ROOT:-$SCRIPT_DIR/../..}/scripts/lib/stop-gates.sh"
_scv_active=0
[[ "$(printf '%s' "$INPUT" | jq -r 'try (.stop_hook_active // false)' 2>/dev/null)" == "true" ]] && _scv_active=1
_scv_line1() { [[ -f "$1" && ! -L "$1" ]] && head -c 4096 "$1" 2>/dev/null | head -1 || printf ''; }
_scv_tok="$(_scv_line1 "$_scv_tdir/.help-turn")"; _scv_grec="$(_scv_line1 "$_scv_tdir/.help-turn-gates")"
_scv_d_prompt="$_scv_active"; _scv_d_principle="$_scv_active"; _scv_d_choice="$_scv_active"   # 순수부가 없으면 이 기능 전과 같다
# shellcheck disable=SC1090
if [[ -f "$_scv_sgl" ]] && source "$_scv_sgl" 2>/dev/null; then
  _scv_d_prompt="$(scv_gates_delivered prompt "$_scv_active" "$_scv_sess" "$_scv_tok" "$_scv_grec")"
  _scv_d_principle="$(scv_gates_delivered principle "$_scv_active" "$_scv_sess" "$_scv_tok" "$_scv_grec")"
  _scv_d_choice="$(scv_gates_delivered choice "$_scv_active" "$_scv_sess" "$_scv_tok" "$_scv_grec")"
fi
_scv_r_prompt=""; _scv_r_principle=""; _scv_r_choice=""
_scv_block_reason=""
if [[ "$_scv_human" == 1 && -f "$_scv_mp" ]]; then
  _scv_ans="${_scv_last:-}"   # 린트가 꺼져 본문을 안 골랐으면 호스트가 준 답만 본다
  [[ "$_scv_ans" == *[![:space:]]* ]] || _scv_ans="$(printf '%s' "$INPUT" | jq -r 'try (.last_assistant_message // empty)' 2>/dev/null | head -c 65536 || true)"
  # 호스트가 준 답은 마지막 메시지뿐이다 — 도구를 부르기 전 첫 메시지에 인용을 보였을 수 있으니, 원본에서 이번 턴의
  # 답 텍스트 전부도 덧붙여 본다(이미 적힌 앞 메시지만 필요하므로 다시 읽기는 하지 않는다).
  _scv_tstream=""
  if declare -F scv_turn_slice >/dev/null 2>&1; then
    _scv_tstream="$(_scv_turn_stream_wide)"
    if [[ -z "$_scv_tstream" ]]; then   # v0.64.0+ — 40000 줄 안에 사람 프롬프트가 없다: 판정 기록에 한 번 남긴다
      _scv_jd="${SCV_JOURNAL_DIR:-scv/journal}"
      mkdir -p "$_scv_jd" 2>/dev/null && [[ ! -L "$_scv_jd/.help-drift" ]] \
        && printf '%s turn-boundary=not-found lines=%s\n' "$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)" \
             "$(wc -l < "$TRANSCRIPT" 2>/dev/null | tr -d ' ')" >> "$_scv_jd/.help-drift" 2>/dev/null
    fi
    _scv_all="$(scv_turn_slice "$_scv_tstream" | head -c 65536)"
    [[ "$_scv_all" == *[![:space:]]* ]] && _scv_ans="$(printf '%s\n\n%s' "$_scv_ans" "$_scv_all")"
  fi
  # v0.64.2+ — 이번 턴의 앞선 글을 못 보는 원본(코덱스 모양 "N" · 경계를 못 찾음 · 자르기 함수 없음)에서는 앞에서 보인 인용을
  # 확인할 수 없다 — 계속 중일 때 등록 검사는 '이미 전달'로 본다(이 기능 전과 같음). 끝 메시지에 인용을 다시 쓰지 않은 답을 막지
  # 않는다(독립 검토 2026-10-02: 원칙에 막힌 뒤 표만 고친 코덱스 답이 "인용을 보이지 않았다"로 새로 막혔다).
  if [[ "$_scv_active" == 1 && ( -z "$_scv_tstream" || "$_scv_tstream" == "N" ) ]]; then _scv_d_prompt=1; fi
  # v0.65.0+ — 이 턴을 연 입력: 매 턴 훅을 거치지 않는 자동 입력(다른 세션이 보낸 메시지)은 원본에서만 보인다. 마지막 사람 모양 입력이
  # 자동 입력으로 판별되면(호스트 프로필의 태그 · 머리 · 끝 안내문) 판정 명령이 그 턴을 자동 턴으로 본다(지난 사람 턴이 끝났을 때만).
  _scv_open=0
  _scv_opener="$(tail -n 400 "$TRANSCRIPT" 2>/dev/null | jq -Rr 'fromjson? | select(.type? == "user") | select((.isMeta? != true) and (.sourceToolUseID? == null))
      | (.message.content) as $c
      | if ($c|type) == "string" then $c elif ($c|type) == "array" then ([$c[]? | select(.type? == "text") | .text] | join("\n")) else empty end
      | select(length > 0) | @json' 2>/dev/null | tail -n 1 | jq -r '. // empty' 2>/dev/null | head -c 65536 || true)"
  if [[ -n "$_scv_opener" ]] && [[ "$(printf '%s' "$_scv_opener" | bash "$_scv_mp" kind 2>/dev/null)" == auto ]]; then _scv_open=1; fi
  _scv_gate="$(printf '%s' "$_scv_ans" | bash "$_scv_mp" stop --active "$_scv_d_prompt" --opened-auto "$_scv_open" ${_scv_sarg[@]+"${_scv_sarg[@]}"} 2>/dev/null || true)"
  if grep -qx 'STOP_GATE: block' <<<"$_scv_gate"; then
    _scv_r_prompt="$(grep -m1 '^STOP_REASON: ' <<<"$_scv_gate" | sed 's/^STOP_REASON: //')"
    [[ -n "$_scv_r_prompt" ]] || _scv_r_prompt="[SCV 프롬프트] 이번 턴 요청을 비교 · 등록하고 다시 쓴 요청을 보여라."
  fi
fi
# v0.64.0+ — 답의 끝 메시지 판정 둘: (1) SCV 원칙 — 문제 표 · '생길 수 있는 문제' 칸(model-prompting.sh principle-gate,
# 원칙이 실리는 곳에서만), (2) 고르게 할 때 규칙(contracts/choices.md) — 호스트 설정에 선택지 도구가 있을 때, 글로 묻거나 번호로
# 고르게 하면서 끝남(choice-gate.sh). 자동 알림 턴에도 적용된다. 마지막 메시지만 본다 — 앞에서 선택지로 물었어도 끝을 글
# 질문으로 맺으면 막는다. 판정할 것이 없으면(원칙이 안 실림 · 도구 없음 · 끝 메시지를 못 받음) 이 기능 전과 같다.
# v0.64.2+ — 등록 판정이 막았어도 끝 메시지를 읽고 둘 다 판정한다(검사마다 한 턴에 한 번 — 위 설명).
_scv_cg="${SCV_CORE_ROOT:-$SCRIPT_DIR/../..}/scripts/choice-gate.sh"
# 끝 메시지는 호스트가 준 것만 본다 — 원본에서 고르면 아직 안 적힌 끝 메시지 대신 도구 호출 전의 글을 볼 수 있다(그때는 판정하지
# 않는다 — 막지 않는 쪽).
# v0.65.0+ — 검사마다 필요한 쪽을 본다(64KB 를 넘는 답도 판정한다): 선택지 검사는 답의 끝(뒤 64KB — 질문은 끝에 있다),
# 원칙 검사는 답 전체(문제 표는 어디에나 있을 수 있다 — 그 명령이 표 줄만 골라 본다). 0.64 까지는 둘 다 앞 64KB 였다.
_scv_lastmsg=""; _scv_win_end=""
if [[ "$_scv_human" == 1 ]] && [[ -f "$_scv_mp" || -f "$_scv_cg" ]]; then
  _scv_lastmsg="$(printf '%s' "$INPUT" | jq -r 'try (.last_assistant_message // empty)' 2>/dev/null || true)"
fi
[[ "$_scv_lastmsg" == *[![:space:]]* ]] || _scv_lastmsg=""
if [[ -n "$_scv_lastmsg" ]]; then
  _scv_lmb="$(printf '%s' "$_scv_lastmsg" | wc -c | tr -d '[:space:]')"; [[ "$_scv_lmb" =~ ^[0-9]+$ ]] || _scv_lmb=0
  if (( _scv_lmb <= 65536 )); then _scv_win_end="$_scv_lastmsg"
  else
    _scv_win_end="$(printf '%s' "$_scv_lastmsg" | tail -c 65536)"
    # 창이 코드 블록 안에서 시작하면 블록 경계가 뒤집힌다 — 잘라 낸 앞부분의 경계 줄 수가 홀수면 창 맨 앞에 경계 한 줄을 더한다(독립 검토).
    _scv_fc="$(printf '%s' "$_scv_lastmsg" | head -c "$(( _scv_lmb - 65536 ))" | LC_ALL=C grep -c '^[[:space:]]*```' 2>/dev/null || true)"
    [[ "$_scv_fc" =~ ^[0-9]+$ ]] && (( _scv_fc % 2 == 1 )) && _scv_win_end='```'$'\n'"$_scv_win_end"
  fi
fi
if [[ -n "$_scv_lastmsg" && -f "$_scv_mp" ]]; then
  _scv_pgo="$(printf '%s' "$_scv_lastmsg" | bash "$_scv_mp" principle-gate --active "$_scv_d_principle" ${_scv_sarg[@]+"${_scv_sarg[@]}"} 2>/dev/null || true)"
  if grep -qx 'PRINCIPLE_GATE: block' <<<"$_scv_pgo"; then
    _scv_r_principle="$(grep -m1 '^PRINCIPLE_REASON: ' <<<"$_scv_pgo" | sed 's/^PRINCIPLE_REASON: //')"
    [[ -n "$_scv_r_principle" ]] || _scv_r_principle="[SCV 원칙] 문제 표 · 문제 칸 없이, 해결책 안에서 막아 다시 써라."
  fi
fi
if [[ -n "$_scv_lastmsg" && -f "$_scv_cg" ]]; then
  _scv_cgo="$(printf '%s' "$_scv_win_end" | bash "$_scv_cg" stop --active "$_scv_d_choice" --turn-dir "$_scv_tdir" 2>/dev/null || true)"
  if grep -qx 'CHOICE_GATE: block' <<<"$_scv_cgo"; then
    _scv_r_choice="$(grep -m1 '^CHOICE_REASON: ' <<<"$_scv_cgo" | sed 's/^CHOICE_REASON: //')"
    [[ -n "$_scv_r_choice" ]] || _scv_r_choice="[SCV 선택지] 고를 것은 선택지 도구로 다시 물어라(contracts/choices.md)."
  fi
fi
# 막은 검사들 → 막는 이유 하나 · 이번 턴 전달 기록(막을 때만 쓴다, 첫 멈춤에서는 같은 세션의 지난 기록을 지운다).
# 순수부가 없으면 이 기능 전처럼 첫 이유 하나만.
_scv_blocked=""
[[ -n "$_scv_r_prompt" ]] && _scv_blocked="${_scv_blocked:+$_scv_blocked,}prompt"
[[ -n "$_scv_r_principle" ]] && _scv_blocked="${_scv_blocked:+$_scv_blocked,}principle"
[[ -n "$_scv_r_choice" ]] && _scv_blocked="${_scv_blocked:+$_scv_blocked,}choice"
if declare -F scv_gates_reason >/dev/null 2>&1 && declare -F scv_gates_record >/dev/null 2>&1 && declare -F scv_gates_drop >/dev/null 2>&1; then
  _scv_block_reason="$(scv_gates_reason "$_scv_r_prompt" "$_scv_r_principle" "$_scv_r_choice")"
  _scv_gfile="$_scv_tdir/.help-turn-gates"
  _scv_newrec="$(scv_gates_record "$_scv_sess" "$_scv_tok" "$_scv_grec" "$_scv_active" "$_scv_blocked")"
  # 첫 멈춤은 같은 세션의 지난 기록을 먼저 지운다 — 막으면서 새 기록 쓰기에 실패해도 지난 턴 기록이 이번 것으로 남지 않게
  # (재검토 2026-10-02). 지우지도 쓰지도 못한 첫 멈춤 뒤에는 같은 검사가 한 번 더 막을 수 있다 — 상한 2, 끝없는 반복은 없다.
  if [[ "$(scv_gates_drop "$_scv_sess" "$_scv_grec" "$_scv_active")" == 1 && -f "$_scv_gfile" && ! -L "$_scv_gfile" ]]; then
    rm -f "$_scv_gfile" 2>/dev/null
  fi
  if [[ -n "$_scv_newrec" ]]; then
    # 세션 자리 · 그 위 폴더 · 기록 파일이 심볼릭 링크면 쓰지 않는다(링크를 따라 만들지도 않는다).
    if [[ ! -L "$_scv_gfile" ]] && { [[ "$_scv_tdir" == "$_scv_jdir" ]] || [[ ! -L "$_scv_jdir/.help-turns" && ! -L "$_scv_tdir" ]]; } \
       && mkdir -p "$_scv_tdir" 2>/dev/null; then
      _scv_tmp="$(mktemp "$_scv_gfile.XXXXXX" 2>/dev/null)" \
        && { printf '%s\n' "$_scv_newrec" > "$_scv_tmp" 2>/dev/null && mv -f "$_scv_tmp" "$_scv_gfile" 2>/dev/null \
             || rm -f "$_scv_tmp" 2>/dev/null; }
    fi
    if [[ "$_scv_active" == 1 && "$(_scv_line1 "$_scv_gfile")" != "$_scv_newrec" ]]; then
      # 기록을 남기지 못했다 — 막으면 다음 멈춤이 같은 검사를 또 막는다. 막지 않고 다음 턴 경고로 돌린다.
      if [[ ! -L "$_scv_tdir/.help-warn" ]] && { [[ "$_scv_tdir" == "$_scv_jdir" ]] || [[ ! -L "$_scv_jdir/.help-turns" && ! -L "$_scv_tdir" ]]; }; then
        while IFS= read -r _scv_l; do
          [[ -n "$_scv_l" ]] && printf '%s\n' "[SCV 가이드] 직전 턴: $_scv_l" >> "$_scv_tdir/.help-warn" 2>/dev/null
        done <<< "$_scv_block_reason"
      fi
      _scv_block_reason=""
    fi
  fi
else
  _scv_block_reason="${_scv_r_prompt:-${_scv_r_principle:-$_scv_r_choice}}"
fi
_scv_emit_block() {
  [[ -n "${_scv_block_reason:-}" ]] || return 0
  jq -cn --arg r "$_scv_block_reason" '{decision:"block",reason:$r}' 2>/dev/null || true
}
trap '_scv_emit_block' EXIT

[[ "$SUMMARY" == *[![:space:]]* ]] || exit 0
# v0.65.0+ — 사람 메시지를 받지 않은 세션(팀원 등 하위 세션)의 답은 저널에 적지 않는다: 그 답은 리드가 받아 자기 답으로 적고, 하위
# 세션이 읽은 다른 저장소 · 다른 세션의 내용이 이 저장소의 커밋되는 기록에 섞이지 않게(2026-10-03: 공개 전에 다섯 건을 손으로 가렸다).
[[ "$_scv_human" == 1 ]] || exit 0

# v0.59.0+ — 답한 모델을 화자 이름에 붙인다 (계기판의 모델별 답 수). 대화 기록의 마지막 답 메시지에
# 모델 id 가 있을 때만: "assistant · <id>". 없으면 이전과 같은 "assistant". 이름을 만드는 판단은 순수부.
_scv_speaker="assistant"
_scv_mplib="${SCV_CORE_ROOT:-$SCRIPT_DIR/../..}/scripts/lib/model-prompting.sh"
# shellcheck disable=SC1090
if [[ -f "$_scv_mplib" ]] && source "$_scv_mplib" 2>/dev/null; then
  _scv_model="$(tail -n 200 "$TRANSCRIPT" 2>/dev/null \
    | jq -Rr 'fromjson? | select(.type? == "assistant") | (.message.model // empty) | strings' 2>/dev/null \
    | tail -n 1 || true)"
  _scv_speaker="$(scv_mp_speaker_label "$_scv_model")"
fi
printf '%s\n' "$SUMMARY" | bash "$JOURNAL_APPEND" --speaker "$_scv_speaker" >/dev/null 2>&1 || true
exit 0
