#!/usr/bin/env bash
# model-prompting.sh — 모델별 프롬프팅의 효과부. 읽기·쓰기는 여기서만, 판단은 lib/model-prompting.sh.
#
#   model-prompting.sh guide --model <id>   help 가 부른다: 이 모델의 가이드 원문을 읽어야 하나 → GUIDE 줄들
#   model-prompting.sh mark  --model <id>   모델이 원문을 읽은 뒤: 이 컨텍스트(지금 규약 지문)에서 이 모델을 읽음으로 기록
#   model-prompting.sh status [--model <id>] 사람이 본다: 가이드 폴더 · 색인 행 수 · 읽음 기록 · (모델이 있으면) 결정
#   model-prompting.sh prompt              (v0.61.0+) 매 턴 훅이 부른다: 이 컨텍스트에서 아직 원문을 안 읽었으면, help 가
#                                            마지막으로 본 모델의 원문 경로 · 표시 명령 블록을 낸다(아니면 아무것도)
#   model-prompting.sh checklist --model <id> (v0.62.0+) 이 모델의 요구 항목 목록(공통 + 모델) — 매 턴 1:1 비교의 기준
#   model-prompting.sh register --model <id> < 제출  (v0.62.0+) 이번 턴 비교 결과를 등록 — 항목이 모두 채워졌을 때만.
#                                            (v0.63.0+) 출력의 REWRITE 끝에 SCV 원칙 표식, 그 아래 PRINCIPLE: 전문 —
#                                            contracts/rewrite-principle.md 의 SCV_LANG 구역, 설정 SCV_REWRITE_PRINCIPLE(on|off)
#                                            (2026-10-08+) 전문 아래 해로운 변경 줄 하나 — 이번 실행의 확인 통로(choice-gate.sh
#                                            tool · unattended → scv_show_real_channel)에 맞는 harm-choice | harm-text | harm-none
#   model-prompting.sh gate                 (v0.62.0+) 가드가 부른다: 이번 턴 등록 전이면 거절 사유를 낸다(아니면 아무것도)
#   model-prompting.sh kind < 프롬프트        (v0.63.0+) 매 턴 훅이 부른다: auto(호스트가 보낸 입력 — 호스트 프로필 SCV_AUTO_PROMPT_TAGS) | human
#   model-prompting.sh prompt --auto        (v0.63.0+) 자동 입력 턴: 새 표 없이 "이번 턴은 자동" 표시만 남긴다(출력 없음)
#   model-prompting.sh principle-gate [--active 0|1] < 끝 메시지  (v0.64.0+) 종료 훅이 부른다: 문제 표 · '생길 수 있는 문제'
#                                            칸이 있으면 PRINCIPLE_GATE: block(+ PRINCIPLE_REASON), --active 1(이미 전달)이면 warn(다음 턴 경고)
#   model-prompting.sh stop < 답본문        (v0.60.0+) 종료 훅이 부른다: 이번 턴에 원문을 읽었는지 · 다시 쓴 요청을
#                                            답에 보였는지 결과로 판정 → 어긋나면 다음 턴 경고(.help-warn 에 덧붙임)
#   model-prompting.sh human [--transcript <경로>]  (v0.65.0+) 매 턴 훅이 사람 입력마다 부른다: 이 세션이 사람 메시지를
#                                            받았다는 표시 · 대화 기록 경로를 남기고 자동 턴 표시를 지운다(출력 없음)
#   model-prompting.sh answered             (v0.65.0+) 선택 창 답 훅이 부른다: 이번 턴 마지막 등록 뒤에 답이 왔다고 적는다
#   model-prompting.sh register --keep      (v0.65.0+) 답 뒤 범위가 그대로일 때의 한 줄 등록 — 직전 등록을 새 차례로 다시 적는다
#   model-prompting.sh session              (v0.65.0+) 종료 · 시작 훅이 부른다: TURN_DIR(이 세션의 턴 상태 폴더) · HUMAN(사람 메시지를 받은 세션 1|0)
#
# 세션(v0.65.0+): 이번 턴 상태(.help-turn · .help-rewrite · .help-turn-auto · .help-turn-done · .help-turn-gates · .help-warn ·
#   .help-guide-turn · .help-answered · .help-human · .help-transcript)는 세션마다 ${SCV_JOURNAL_DIR:-scv/journal}/.help-turns/<세션>/ 에
#   둔다. --session <id> 를 받으면 그 세션(빈 값이면 공용 자리 — 이 기능 전과 같다), 안 받으면 이번 턴 표가 가장 새로운 세션
#   (모델이 직접 부르는 명령 · 세션 id 를 안 주는 호스트). 하위 세션(팀원 · 하위 에이전트)은 사람 메시지를 받지 않아 표가 없다.
#
# 입력: 호스트 프로필 SCV_PROMPTING_GUIDES (래퍼가 준다), 그 폴더의 INDEX.tsv, help 표식의 규약 지문(nonce),
#       ${SCV_JOURNAL_DIR:-scv/journal}/.help-guide (읽음 기록), .help-guide-turn (이번 턴 기록 — guide 가 쓰고 stop 이 지운다), 설정 SCV_MODEL_PROMPTING(on|off) ·
#       SCV_MODEL_PROMPTING_MAX_AGE_DAYS(기본 90), 오늘 날짜(SCV_TODAY 로 덮어쓸 수 있다 — 검사용).
# 어떤 실패도 exit 0 — 무엇이 없든 "GUIDE: none" 으로 떨어진다(이 기능이 없던 때와 같은 답).
set -u
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" 2>/dev/null && pwd )" || { echo "GUIDE: none"; exit 0; }
CORE_ROOT="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd)"
# shellcheck source=lib/model-prompting.sh
source "$SCRIPT_DIR/lib/model-prompting.sh" 2>/dev/null || { echo "GUIDE: none"; exit 0; }
# shellcheck source=lib/help-state.sh
source "$SCRIPT_DIR/lib/help-state.sh" 2>/dev/null || { echo "GUIDE: none"; exit 0; }
# shellcheck source=lib/host-profile.sh
source "$SCRIPT_DIR/lib/host-profile.sh" 2>/dev/null || true
# shellcheck source=lib/settings.sh
source "$SCRIPT_DIR/lib/settings.sh" 2>/dev/null || true
# shellcheck source=lib/show-real.sh
source "$SCRIPT_DIR/lib/show-real.sh" 2>/dev/null || true   # (2026-10-08+) 확인 통로 판단 scv_show_real_channel 을 함께 쓴다

JOURNAL_DIR="${SCV_JOURNAL_DIR:-scv/journal}"
READ_FILE="$JOURNAL_DIR/.help-guide"
LAST_FILE="$JOURNAL_DIR/.help-guide-last"     # v0.61.0+: help 가 마지막으로 본 모델 — 컨텍스트에 묶이지 않아 초기화가 지우지 않는다
STATE_FILE="$JOURNAL_DIR/.help-state"
TURNS_DIR="$JOURNAL_DIR/.help-turns"          # v0.65.0+: 세션별 턴 상태 폴더들

cmd="${1:-guide}"; shift || true
MODEL_RAW=""; SESSION_ARG=""; SESSION_SET=0; ACTIVE_ARG="0"; AUTO_ARG=0; KEEP_ARG=0; AGENT_ARG=""; CODE_ARG="0"; TRANSCRIPT_ARG=""; OPENED_AUTO=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --session) SESSION_ARG="${2:-}"; SESSION_SET=1; shift 2 || shift ;;
    --active)  ACTIVE_ARG="${2:-0}"; shift 2 || shift ;;
    --auto)    AUTO_ARG=1; shift ;;
    --keep)    KEEP_ARG=1; shift ;;
    --agent)   AGENT_ARG="${2:-}"; shift 2 || shift ;;
    --code)    CODE_ARG="${2:-0}"; shift 2 || shift ;;
    --transcript) TRANSCRIPT_ARG="${2:-}"; shift 2 || shift ;;
    --opened-auto) OPENED_AUTO="${2:-0}"; shift 2 || shift ;;
    --model)   MODEL_RAW="${2:-}"; shift 2 || shift ;;
    --model=*) MODEL_RAW="${1#--model=}"; shift ;;
    *) shift ;;
  esac
done

# ---------------------------------------------------------------- 효과: 읽기 (입구)
_setting() { declare -F settings_get >/dev/null 2>&1 && settings_get "$1" 2>/dev/null || true; }
_first_line() { [[ -f "$1" && ! -L "$1" ]] && head -c 4096 "$1" 2>/dev/null | head -1 || printf ''; }
_principle_body() {  # (v0.63.0+) 원칙 파일 본문 — 후보 중 처음 있는 것. 심볼릭 링크는 읽지 않고, 64KB 까지만.
  local c
  while IFS= read -r c; do
    [[ -n "$c" && -f "$c" && ! -L "$c" ]] && { head -c 65536 "$c" 2>/dev/null; return 0; }
  done <<< "$(scv_mp_principle_candidates "$CORE_ROOT")"
  return 0
}
_dir_ok() {  # <폴더> — 쓸 수 있는 자리인가: 저널 폴더 자신이거나, 심볼릭 링크가 아닌 세션 폴더(필요하면 만든다)
  local d="$1"
  mkdir -p "$JOURNAL_DIR" 2>/dev/null || return 1
  [[ "$d" == "$JOURNAL_DIR" ]] && return 0
  [[ -L "$TURNS_DIR" || -L "$d" ]] && return 1
  mkdir -p "$d" 2>/dev/null || return 1
  [[ -d "$d" && ! -L "$d" ]]
}
_put() {  # <파일> <본문> — 임시 파일 뒤 mv. 심볼릭 링크면 안 쓴다(파일 · 세션 폴더 모두).
  local file="$1" body="$2" tmp
  _dir_ok "${file%/*}" || return 0
  [[ -L "$file" ]] && return 0
  tmp="$(mktemp "$file.XXXXXX" 2>/dev/null)" || return 0
  printf '%s\n' "$body" > "$tmp" 2>/dev/null && mv -f "$tmp" "$file" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  return 0
}
_drop() { [[ -f "$1" && ! -L "$1" ]] && rm -f "$1" 2>/dev/null; return 0; }
_mtime() { stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1" 2>/dev/null || printf '0'; }
_warn_add() {  # <줄> — 이 세션의 다음 턴 경고에 한 줄 덧붙인다
  _dir_ok "$TDIR" || return 0
  [[ -L "$WARN_FILE" ]] || printf '%s\n' "$1" >> "$WARN_FILE" 2>/dev/null
  return 0
}
_newest_key() {  # 이번 턴 표가 가장 새로운 세션 폴더 이름. 공용 표가 더 새것이거나 세션 폴더가 없으면 빈 값(공용).
  # 한 번의 ls -t 로 고른다 — 세션 폴더가 수백 개여도 프로세스 하나(폴더마다 stat 을 부르면 300개에 1초가 넘었다, 독립 검토 실측).
  local newest name
  [[ -d "$TURNS_DIR" && ! -L "$TURNS_DIR" ]] || return 0
  newest="$(ls -t "$JOURNAL_DIR/.help-turn" "$TURNS_DIR"/*/.help-turn 2>/dev/null | head -n 1)"
  [[ -n "$newest" && "$newest" != "$JOURNAL_DIR/.help-turn" && -f "$newest" && ! -L "$newest" ]] || return 0
  name="${newest%/.help-turn}"; name="${name##*/}"
  [[ -d "$TURNS_DIR/$name" && ! -L "$TURNS_DIR/$name" ]] || return 0
  scv_mp_session_key "$name"
}

_any_human() {  # 사람 메시지 표시가 있는 세션 폴더가 하나라도 있나 — 이 호스트의 매 턴 훅이 세션 id 를 준다는 증거
  local f
  [[ -d "$TURNS_DIR" && ! -L "$TURNS_DIR" ]] || return 1
  for f in "$TURNS_DIR"/*/.help-human; do [[ -f "$f" ]] && return 0; done
  return 1
}

# v0.65.0+ — 이 호출의 세션과 턴 상태 폴더.
#   --session 을 받은 호출: 그 세션(빈 값 · 형식 밖이면 공용). 단, 읽는 쪽(prompt · human 밖)에서 그 세션에 사람 메시지 표시가 없고
#     어느 세션에도 표시가 없으면 공용으로 간다 — 매 턴 훅에 세션 id 를 주지 않는 호스트는 이 기능 전과 같게.
#   --session 을 안 받은 호출(모델이 직접 부르는 명령 · 세션 id 를 안 주는 훅): 이번 턴 표가 가장 새로운 세션.
#   (v0.65.0+) --session 이 없으면 먼저 호스트 프로필 SCV_SESSION_ENV 가 이름 붙인 환경 변수(모델의 셸 명령에 호스트가 담는 세션 id)를
#     본다 — 그 세션 자리가 이미 있을 때만(한 저장소에 사람 세션이 여럿이어도 자기 자리로 간다). 판별 · 표시 같은 명령은 자리를 고르지 않는다.
SKEY=""
case "$cmd" in
  kind|mark|status) ;;
  *)
    if (( SESSION_SET )); then
      SKEY="$(scv_mp_session_key "$SESSION_ARG")"
      case "$cmd" in
        prompt|human) ;;
        *) if [[ -n "$SKEY" && ! -f "$(scv_mp_turn_dir "$JOURNAL_DIR" "$SKEY")/.help-human" ]] && ! _any_human; then SKEY=""; fi ;;
      esac
    else
      _envname="${SCV_SESSION_ENV:-}"; _envkey=""
      if [[ "$_envname" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        _envkey="$(scv_mp_session_key "${!_envname:-}")"
        [[ -n "$_envkey" && -d "$TURNS_DIR/$_envkey" && ! -L "$TURNS_DIR/$_envkey" ]] || _envkey=""
      fi
      if [[ -n "$_envkey" ]]; then SKEY="$_envkey"; else SKEY="$(_newest_key)"; fi
    fi ;;
esac
TDIR="$(scv_mp_turn_dir "$JOURNAL_DIR" "$SKEY")"
TOKEN_FILE="$TDIR/.help-turn"          # v0.62.0+: 매 턴 훅이 새로 쓰는 이번 턴 표 — 등록이 이 턴 것인지 가른다
AUTO_FILE="$TDIR/.help-turn-auto"      # v0.63.0+: 자동 입력 턴 표시 — 그 턴의 표(바뀌지 않은 지난 표) 한 줄
DONE_FILE="$TDIR/.help-turn-done"      # v0.63.0+: 끝난 턴의 표 — 종료 판정이 막지 않고 끝낸 턴(자동 태그가 있을 때만 씀)
REG_FILE="$TDIR/.help-rewrite"         # v0.62.0+: 이번 턴 등록(첫 줄 표\x1f모델\x1f차례(v0.65.0+), 다음 줄부터 제출)
TURN_FILE="$TDIR/.help-guide-turn"     # v0.60.0+: 이번 턴 가이드 결정(guide 가 쓰고 stop 이 지운다)
WARN_FILE="$TDIR/.help-warn"           # 다음 턴 경고(매 턴 훅이 싣고 지운다)
ANS_FILE="$TDIR/.help-answered"        # v0.65.0+: 선택 창 답 — "<표>\x1f<그때 마지막 등록의 차례>"
HUMAN_FILE="$TDIR/.help-human"         # v0.65.0+: 이 세션이 사람 메시지를 받았다(하위 세션에는 없다)
TRANS_FILE="$TDIR/.help-transcript"    # v0.65.0+: 이 세션의 대화 기록 경로(가이드 다시 읽기 판단)
SCAN_FILE="$TDIR/.help-guide-scan"    # v0.65.0+: 대화 기록을 어디까지 읽었나 — "<경로>\x1f<바이트>\x1f<표시된 모델 집합>"
_fsize() { stat -c '%s' "$1" 2>/dev/null || stat -f '%z' "$1" 2>/dev/null || printf ''; }
_guide_set() {  # <대화 기록> → 마지막 압축 경계 뒤에 읽음 표시한 모델 집합(공백 구분, 없으면 빈 값) 또는 "N"(판단 못 함)
  # 기록은 덧붙기만 한다 — 지난번에 읽은 곳(SCAN_FILE)부터 새로 붙은 부분만 읽고 집합을 이어 접는다(끝부분 읽기는 큰 파일에서도
  # 수십 ms — 맥 기본 tail -c 는 건너뛰어 읽는다). 처음 · 파일이 바뀜 · 줄어듦이면 처음부터. 덜 적힌 마지막 줄은 다음에 다시 읽는다.
  local t="$1" size cp co cs start=0 set="" lastb out len off
  [[ -n "$t" && -f "$t" && -r "$t" ]] || { printf 'N'; return 0; }
  command -v jq >/dev/null 2>&1 || { printf 'N'; return 0; }
  size="$(_fsize "$t")"; [[ "$size" =~ ^[0-9]+$ ]] || { printf 'N'; return 0; }
  IFS=$'\x1f' read -r cp co cs <<< "$(_first_line "$SCAN_FILE")"
  if [[ "$cp" == "$t" && "$co" =~ ^[0-9]+$ ]] && (( co <= size )); then
    start=$co; set="$cs"
  else
    grep -m1 -qF '"type":"assistant"' "$t" 2>/dev/null || { printf 'N'; return 0; }   # 이 형식(줄마다 JSON 한 건)의 기록이 아니다
  fi
  if (( size > start )); then
    lastb="$(tail -c +"$size" "$t" 2>/dev/null | head -c 1 | od -An -tx1 2>/dev/null | tr -d ' \n')"
    # 경계 줄은 표시 한 줄로, 이 명령 이름이 든 모델 줄은 그대로, 마지막 줄 길이는 끝에 — jq 가 차례대로 사건 줄로 바꾼다.
    # 경계 표시는 JSON 키 그대로 찾는다 — 본문 글에 든 같은 글자는 따옴표가 이스케이프돼 맞지 않는다.
    out="$( { if (( start == 0 )); then head -c "$size" "$t"; else tail -c +"$((start + 1))" "$t" | head -c "$((size - start))"; fi; } 2>/dev/null \
      | LC_ALL=C awk '{ len = length($0) }
                      index($0, "\"subtype\":\"compact_boundary\"") { print "{\"scvB\":1}"; next }
                      index($0, "model-prompting.sh") && index($0, "\"type\":\"assistant\"") { print }
                      END { printf "{\"scvL\":%d}\n", len + 0 }' 2>/dev/null \
      | jq -Rr 'fromjson? | if .scvB? == 1 then "B" elif .scvL? != null then "L\(.scvL)"
                elif .type? == "assistant" then (.message.content[]? | select(.type? == "tool_use") | (.input.command? // empty) | strings
                  | select(contains("model-prompting.sh")) | gsub("[\r\n]"; " ") | "M\u001f" + .)
                else empty end' 2>/dev/null)"
    len="$(printf '%s\n' "$out" | sed -n 's/^L\([0-9][0-9]*\)$/\1/p' | tail -n 1)"; [[ "$len" =~ ^[0-9]+$ ]] || len=0
    off=$size; [[ "$lastb" == "0a" ]] || off=$(( size - len ))
    (( off >= start )) || off=$start
    set="$(scv_mp_guide_fold "$set" "$(printf '%s\n' "$out" | grep -v '^L[0-9]*$')")"
    _put "$SCAN_FILE" "$(printf '%s\x1f%s\x1f%s' "$t" "$off" "$set")"
  fi
  printf '%s' "$set"
}

ID="$(scv_mp_normalize_id "$MODEL_RAW")"
SWITCH="$(scv_mp_switch "$(_setting SCV_MODEL_PROMPTING)")"
MAX_AGE="$(_setting SCV_MODEL_PROMPTING_MAX_AGE_DAYS)"; [[ "$MAX_AGE" =~ ^[0-9]+$ ]] || MAX_AGE=90
# v0.62.0+: 후보를 앞에서부터 시도해 INDEX.tsv 가 있는 첫 폴더 — 벤더 코어에서 도는 훅도 래퍼 최상위 기준 값을 찾는다.
GUIDES_DIR=""
while IFS= read -r _c; do
  [[ -n "$_c" && -f "$_c/INDEX.tsv" && ! -L "$_c/INDEX.tsv" ]] && { GUIDES_DIR="$_c"; break; }   # 경로는 정규화하지 않는다(출력 글자 그대로)
done <<< "$(scv_mp_guides_candidates "$CORE_ROOT" "${SCV_PROMPTING_GUIDES:-}")"
[[ -n "$GUIDES_DIR" ]] || GUIDES_DIR="$(scv_mp_guides_dir "$CORE_ROOT" "${SCV_PROMPTING_GUIDES:-}")"
INDEX_FILE=""; INDEX=""
if [[ -n "$GUIDES_DIR" && -f "$GUIDES_DIR/INDEX.tsv" && ! -L "$GUIDES_DIR/INDEX.tsv" ]]; then
  INDEX_FILE="$GUIDES_DIR/INDEX.tsv"
  INDEX="$(head -c 65536 "$INDEX_FILE" 2>/dev/null)"
fi
# 지금 규약 지문 — help 표식의 여섯째 필드. 컨텍스트가 바뀌면 비워진다(lib 머리말 참조).
_ST="$(scv_hstate_parse "$(_first_line "$STATE_FILE")")"
NONCE="$(scv_hstate_nonce "$_ST")"; STATE_SESSION="${_ST%%$'\x1f'*}"
RECORD="$(scv_mp_read_parse "$(_first_line "$READ_FILE")")"
TODAY="${SCV_TODAY:-$(date +%Y-%m-%d 2>/dev/null)}"

# ---------------------------------------------------------------- 순수: 조회 → 결정 → 줄
ROW=""; [[ "$SWITCH" == "on" ]] && ROW="$(scv_mp_lookup "$ID" "$INDEX")"
KEY=""; MFILE=""; MDATE=""
[[ -n "$ROW" ]] && IFS=$'\t' read -r KEY MFILE MDATE <<< "$ROW"
MFILE_RAW="$MFILE"; MFILE="$(scv_mp_safe_name "$MFILE")"
COMMON="$(scv_mp_common "$INDEX")"; CFILE=""; CDATE=""
[[ -n "$COMMON" ]] && IFS=$'\t' read -r CFILE CDATE <<< "$COMMON"
CFILE="$(scv_mp_safe_name "$CFILE")"
_cl_file() { local k; k="$(scv_mp_safe_name "checklist-${1:-}.tsv")"; [[ -n "${1:-}" && -n "$k" && -f "$GUIDES_DIR/$k" && ! -L "$GUIDES_DIR/$k" ]] && head -c 16384 "$GUIDES_DIR/$k" 2>/dev/null; }
_checklist_for() {  # <모델 키 또는 ""> → 병합 목록 (공통 목록이 없으면 빈 값 — 이 호스트에 요구 항목 데이터가 없다)
  local common; common="$(_cl_file "$(scv_mp_common_key "$INDEX")")"
  [[ "$common" == *[![:space:]]* ]] || return 0
  scv_mp_checklist_merge "$common" "$(_cl_file "${1:-}")"
}
_token_new() { local n; n="$(head -c 4 /dev/urandom 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n')"; [[ "$n" =~ ^[0-9a-f]{8}$ ]] || n="$(printf '%04x%04x' "$RANDOM" "$RANDOM")"; printf '%s' "$n"; }
_last_model() { local m; m="$(_first_line "$LAST_FILE")"; m="${m//[[:space:]]/}"; [[ "$m" == "none" ]] && m=""; printf '%s' "$m"; }
_key_of() { local r; r="$(scv_mp_lookup "$(scv_mp_normalize_id "${1:-}")" "$INDEX")"; printf '%s' "${r%%$'\t'*}"; }

case "$cmd" in
  guide)
    [[ -n "$INDEX_FILE" || -n "${SCV_PROMPTING_GUIDES:-}" || -n "$ID" ]] || { echo "GUIDE: none"; exit 0; }
    MISSING=""
    MPATH=""; CPATH=""
    if [[ -n "$ROW" && -z "$MFILE" ]]; then
      MISSING="${MFILE_RAW:-?} (not a plain file name)"   # 폴더 밖을 가리키는 색인 값은 읽히지 않는다
    elif [[ -n "$MFILE" ]]; then
      MPATH="$GUIDES_DIR/$MFILE"
      [[ -f "$MPATH" && ! -L "$MPATH" ]] || MISSING="$MFILE"
    fi
    if [[ -n "$CFILE" && -z "$MISSING" ]]; then
      CPATH="$GUIDES_DIR/$CFILE"
      [[ -f "$CPATH" && ! -L "$CPATH" ]] || CPATH=""   # 공통 원문이 없으면 모델 원문만
    fi
    HAVE=0; [[ -n "$ROW" ]] && HAVE=1
    DEC="$(scv_mp_decision "$HAVE" "$RECORD" "$NONCE" "$ID")"
    # v0.65.0+ — 이 세션의 대화 기록이 있으면 그것으로 정한다: 마지막 압축 경계 뒤에 이 모델의 읽음 표시 명령이 있으면 loaded.
    # 재접속 · 이어받기 · 턴 수 · 규약 다시 읽기(지문이 바뀜)만으로는 다시 읽게 하지 않는다. 기록을 못 읽으면 위 판단 그대로.
    if [[ "$DEC" == "load" || "$DEC" == "loaded" ]]; then
      _tdec="$(scv_mp_guide_decide "$(_guide_set "$(_first_line "$TRANS_FILE")")" "$ID")"
      [[ -n "$_tdec" ]] && DEC="$_tdec"
    fi
    AGE="$(scv_mp_age_days "$MDATE" "$TODAY")"
    REFRESH=""; _r="$(scv_mp_safe_name "$(scv_mp_meta "$INDEX" refresh)")"; [[ -n "$_r" ]] && REFRESH="$GUIDES_DIR/$_r"
    scv_mp_guide_lines "$DEC" "$KEY" "$MPATH" "$CPATH" "$AGE" "$MAX_AGE" "$REFRESH" "$MISSING"
    # v0.60.0+: 읽음 표시 명령을 절대 경로 그대로 준다 — 모델이 경로를 짓다 빠뜨리지 않게. 이번 턴 기록은
    # 종료 훅이 결과로 판정할 근거다(load · loaded 일 때만. none 이면 판정할 것이 없다).
    # v0.60.1+: load 이면 턴 기록 둘째 줄부터 지금 낸 GUIDE_FILE · GUIDE_MARK_CMD 줄을 그대로 담는다 — 멈춤 훅은 다른 실행
    # 위치(벤더 코어)에서 돌아 경로를 다시 계산하면 틀릴 수 있으니, 경고에는 help 가 실제로 낸 값을 싣는다.
    _detail=""; _all=""
    if [[ ( "$DEC" == "load" || "$DEC" == "loaded" ) && -z "$MISSING" && -n "$MPATH" ]]; then
      _cmd="$(printf 'GUIDE_MARK_CMD: bash "%s" mark --model "%s"' "$SCRIPT_DIR/model-prompting.sh" "$ID")"
      _all="GUIDE_FILE: $MPATH"; [[ -n "$CPATH" ]] && _all="$_all"$'\n'"GUIDE_FILE: $CPATH"
      _all="$_all"$'\n'"$_cmd"
      if [[ "$DEC" == "load" ]]; then printf '%s\n' "$_cmd"; _detail="$_all"; fi
    fi
    # v0.61.0+: 마지막으로 본 모델 — 새 컨텍스트의 첫 턴에 매 턴 훅이 싣는다(prompt). 가이드가 없는 모델이면 none.
    if [[ -n "$_all" ]]; then
      _put "$LAST_FILE" "$ID"$'\n'"$_all"
    elif [[ -z "$ROW" && -n "$ID" && "$SWITCH" == "on" ]]; then
      _put "$LAST_FILE" "none"
    fi
    if [[ "$DEC" == "load" || "$DEC" == "loaded" ]] && [[ -z "$MISSING" ]]; then
      _tl="$(printf '%s\x1f%s\x1f%s\x1f%s' "$NONCE" "$ID" "$DEC" "$KEY")"
      [[ -n "$_detail" ]] && _tl="$_tl"$'\n'"$_detail"
      _put "$TURN_FILE" "$_tl"
    else
      _drop "$TURN_FILE"
    fi
    ;;
  mark)
    # 색인에 있는 모델만 기록한다 — 모르는 모델을 "읽음" 으로 적으면 나중에 색인이 생겨도 load 가 안 뜬다.
    [[ -n "$ROW" ]] || { echo "GUIDE_MARK: skipped (no guide for this model)"; exit 0; }
    mkdir -p "$JOURNAL_DIR" 2>/dev/null || exit 0
    [[ -L "$READ_FILE" ]] && exit 0
    tmp="$(mktemp "$READ_FILE.XXXXXX" 2>/dev/null)" || exit 0
    printf '%s\x1f%s\n' "$NONCE" "$ID" > "$tmp" 2>/dev/null && mv -f "$tmp" "$READ_FILE" 2>/dev/null || rm -f "$tmp" 2>/dev/null
    echo "GUIDE_MARK: $KEY"
    ;;
  status)
    echo "GUIDES_DIR: ${GUIDES_DIR:-(none — host profile has no SCV_PROMPTING_GUIDES)}"
    if [[ -n "$INDEX_FILE" ]]; then
      _n=0; while IFS=$'\t' read -r _m _rest || [[ -n "$_m" ]]; do [[ -z "$_m" || "$_m" == \#* || "$_m" == @* ]] || _n=$((_n + 1)); done <<< "$INDEX"
      echo "INDEX: $INDEX_FILE ($_n row(s))"
    else
      echo "INDEX: (none)"
    fi
    echo "SWITCH: $SWITCH · MAX_AGE_DAYS: $MAX_AGE"
    echo "READ: nonce=${RECORD%%$'\x1f'*} model=${RECORD#*$'\x1f'} (current nonce: ${NONCE:-none})"
    if [[ -n "$ID" ]]; then
      echo "MODEL: $ID -> ${KEY:-(no guide)}"
    fi
    ;;
  prompt)
    # v0.63.0+ — 자동 입력 턴: 표를 새로 쓰지 않고(직전 사람 턴의 등록이 그대로 유효), 지금 표를 자동 표시에 적고 끝낸다.
    # 표시는 지금 표의 턴이 이미 끝났을 때만 남긴다 — 사람 턴 도중에 알림이 끼어들면 그 사람 턴의 등록 · 인용 검사가
    # 꺼지지 않게(턴이 끝났는지는 종료 판정이 적은 끝난 턴 표로 안다).
    if (( AUTO_ARG )); then
      _t="$(_first_line "$TOKEN_FILE")"
      [[ -n "$_t" && "$(_first_line "$DONE_FILE")" == "$_t" ]] && _put "$AUTO_FILE" "$_t"
      exit 0
    fi
    _drop "$AUTO_FILE"
    # 읽음: 읽음 기록의 지문이 지금 지문과 같다(빈 지문은 증거가 아니다). 가이드 경고가 이미 예약돼 있으면 그것이 같은 내용을 싣는다.
    # 훅은 표식 갱신(세션 비교)보다 먼저 부른다 — 세션이 바뀌었으면 갱신이 지문을 비울 것이니 안 읽음으로 본다.
    # v0.65.0+ — 이번 턴 표를 먼저 쓴다: 대화 기록 읽기가 아무리 오래 걸려도(훅 시간 초과) 새 턴은 열린다(독립 검토).
    _tok=""; _haslist=0
    if [[ "$SWITCH" == "on" && -n "$(_checklist_for "")" ]]; then _haslist=1; _tok="$(_token_new)"; _put "$TOKEN_FILE" "$_tok"; fi
    _rn="${RECORD%%$'\x1f'*}"; _read=0; [[ -n "$_rn" && "$_rn" == "$NONCE" ]] && _read=1
    [[ -n "$SESSION_ARG" && "$SESSION_ARG" != "$STATE_SESSION" ]] && _read=0
    _lm="$(_last_model)"
    # v0.65.0+ — 이 세션의 대화 기록이 있으면 그것으로 정한다(마지막 압축 경계 뒤에 지난 모델의 읽음 표시 명령이 있나).
    # 재접속 · 이어받기 · 세션 표식 초기화만으로는 다시 읽게 하지 않는다. 기록을 못 읽으면 위 판단 그대로.
    if [[ -n "$_lm" ]]; then
      _tr="$TRANSCRIPT_ARG"; [[ -n "$_tr" ]] || _tr="$(_first_line "$TRANS_FILE")"
      case "$(scv_mp_guide_decide "$(_guide_set "$_tr")" "$(scv_mp_normalize_id "$_lm")")" in
        loaded) _read=1 ;;
        load) _read=0 ;;
      esac
    fi
    _warned=0
    for _wf in "$WARN_FILE" "$JOURNAL_DIR/.help-warn"; do   # v0.65.0+ — 매 턴 훅은 공용 자리에 남은 경고도 싣는다(그 훅 참조)
      [[ -f "$_wf" && ! -L "$_wf" ]] && head -c 4096 "$_wf" 2>/dev/null | grep -q '^\[SCV 가이드\]' && _warned=1
    done
    _rec=""; [[ -f "$LAST_FILE" && ! -L "$LAST_FILE" ]] && _rec="$(head -c 4096 "$LAST_FILE" 2>/dev/null)"
    # v0.62.0+: 매 턴(모든 메시지) 새 표를 쓰고 1:1 비교 · 등록 블록을 싣는다 — 요구 항목 데이터가 있는 호스트에서만.
    if (( _haslist )); then
      _list=""; [[ -n "$_lm" ]] && _list="$(_checklist_for "$(_key_of "$_lm")")"
      scv_mp_turn_block "$SWITCH" "$_tok" "$_lm" "$_list" "$SCRIPT_DIR/model-prompting.sh" "$SKEY"
    fi
    scv_mp_first_turn_lines "$SWITCH" "$_read" "$_warned" "$_rec"
    ;;
  human)
    # v0.65.0+ — 사람 입력(매 턴 훅이 자동 입력 밖의 모든 입력에 부른다): 자동 턴 표시를 지우고(이 기능 전에는 훅이 직접 지웠다),
    # 세션이 있으면 사람 메시지를 받았다는 표시와 대화 기록 경로를 남긴다 — 하위 세션(사람 메시지를 받지 않은 팀원 · 하위 에이전트)을
    # 가르는 근거. 두 주 넘게 손대지 않은 세션 폴더는 지운다(세션마다 작은 파일 몇 개).
    _drop "$AUTO_FILE"
    [[ "$TDIR" != "$JOURNAL_DIR" ]] && _drop "$JOURNAL_DIR/.help-turn-auto"   # 공용 자리의 표시도(업그레이드 전 · 세션 id 없던 턴의 것)
    if [[ -n "$SKEY" ]]; then
      _put "$HUMAN_FILE" "$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"
      [[ -n "$TRANSCRIPT_ARG" ]] && _put "$TRANS_FILE" "$TRANSCRIPT_ARG"
      [[ -d "$TURNS_DIR" && ! -L "$TURNS_DIR" ]] \
        && find "$TURNS_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +14 -exec rm -rf {} + 2>/dev/null
    fi
    echo "TURN_DIR: $TDIR"   # 매 턴 훅이 이 세션의 경고를 이 자리에서 싣는다(모델에게는 보이지 않는 값)
    ;;
  session)
    # v0.65.0+ — 종료 · 시작 훅이 이 세션의 자리를 묻는다. HUMAN 0 = 세션 id 를 받았는데 그 세션이 사람 메시지를 받은 적이 없다
    # (하위 세션) — 종료 훅은 그 세션에서 등록 · 원칙 · 선택지 검사와 답 모양 검사를 하지 않는다. 세션을 모르면 1(이 기능 전과 같다).
    _h=1; if (( SESSION_SET )) && [[ -n "$SKEY" && ! -f "$HUMAN_FILE" ]]; then _h=0; fi
    echo "TURN_DIR: $TDIR"
    echo "HUMAN: $_h"
    ;;
  answered)
    # v0.65.0+ — 선택 창 답(래퍼의 답 신호 훅이 부른다). 이번 턴 표와 "그때 마지막 등록의 차례"를 적는다 — 쓰기 검사는 그 차례가
    # 지금 등록의 차례와 같으면(답 뒤에 다시 등록하지 않았으면) 편집을 거절한다. 하위 에이전트 · 표 없음 · 기능 꺼짐이면 아무것도 안 한다.
    [[ "$SWITCH" == "on" && -n "$(_checklist_for "")" && -z "$AGENT_ARG" ]] || exit 0
    _tok="$(_first_line "$TOKEN_FILE")"; [[ -n "$_tok" ]] || exit 0
    _rt="$(_first_line "$REG_FILE")"; _seq=""
    [[ "${_rt%%$'\x1f'*}" == "$_tok" ]] && _seq="$(scv_mp_reg_seq "$_rt")"
    _put "$ANS_FILE" "$(printf '%s\x1f%s' "$_tok" "$_seq")"
    echo "ANSWERED: turn $_tok"
    ;;
  checklist)
    _list="$(_checklist_for "$KEY")"
    [[ -n "$_list" ]] || { echo "CHECKLIST: none (this host ships no requirement list)"; exit 0; }
    echo "CHECKLIST: ${KEY:-common} (model ${ID:-?})"
    printf '%s\n' "$_list" | while IFS=$'\t' read -r _i _l; do [[ -n "$_i" ]] && printf '%s | %s\n' "$_i" "$_l"; done
    _ss=""; [[ -n "$SKEY" ]] && _ss=" --session \"$SKEY\""
    echo "REGISTER: bash \"$SCRIPT_DIR/model-prompting.sh\" register --model \"${ID:-<id>}\"$_ss — stdin: id | msg|ctx|asked|na | value, then rewrite | - | <rewritten request>"
    ;;
  register)
    _rewrite_out() {  # <저장된 제출> — REWRITE 줄(원칙 표식) · PRINCIPLE 전문. (v0.63.0+) 원칙은 저장된 제출에 넣지 않고 출력에만 붙인다.
      local psw psec
      psw="$(scv_mp_switch "$(_setting SCV_REWRITE_PRINCIPLE)")"
      psec=""; [[ "$psw" == "on" ]] && psec="$(scv_mp_principle_section "$(_principle_body)" "$(_setting SCV_LANG)")"
      echo "REWRITE: $(scv_mp_rewrite_tagged "$(scv_mp_register_rewrite "$1")" "$psw" "$(scv_mp_principle_tag "$psec")")"
      if [[ -n "$psec" ]]; then
        echo "PRINCIPLE:"
        printf '%s\n' "$(scv_mp_principle_text "$psec")"
        # (2026-10-08+) 해로운 변경 줄 — 이번 실행의 확인 통로에 맞는 한 줄. 통로 판단은 실체 보여 주기와 같다(입구: choice-gate.sh).
        local hl
        hl="$(scv_mp_harm_line "$psec" "$(_harm_channel)")"
        [[ -n "$hl" ]] && printf '%s\n' "$hl"
      fi
      return 0
    }
    _harm_channel() {  # → choice | text | none. 읽기(호스트 프로필 · 환경)는 choice-gate.sh 가, 판단은 순수 함수가 한다.
      local t="" u=0
      if [[ -f "$SCRIPT_DIR/choice-gate.sh" ]]; then
        t="$(bash "$SCRIPT_DIR/choice-gate.sh" tool 2>/dev/null || true)"
        u="$(bash "$SCRIPT_DIR/choice-gate.sh" unattended 2>/dev/null || true)"
      fi
      if declare -F scv_show_real_channel >/dev/null 2>&1; then scv_show_real_channel "$t" "$u" human; else printf 'text'; fi
    }
    if (( KEEP_ARG )); then
      # v0.65.0+ — 선택 창 답 뒤 범위가 그대로일 때의 한 줄 등록: 이번 턴 등록이 있고 그 뒤에 답이 왔을 때만. 제출(범위 칸 포함)은
      # 그대로 두고 차례만 새로 — 인용 판정의 기준도 직전 다시 쓴 요청 그대로다. 답이 없으면 불완전 등록으로 거절한다.
      [[ "$SWITCH" == "on" && -n "$(_checklist_for "")" ]] || { echo "REGISTER: skipped (no requirement list)"; exit 0; }
      _tok="$(_first_line "$TOKEN_FILE")"; _rt="$(_first_line "$REG_FILE")"
      if [[ -z "$_tok" || "$(scv_mp_write_gate "$_tok" "$_rt" "$(_first_line "$ANS_FILE")" 0 0)" != "answered" ]]; then
        echo "REGISTER: incomplete — --keep is only for a choice answer after this turn's registration; register the full submission (stdin: id | msg|ctx|asked|na | value, then rewrite | - | <rewritten request>)"
        exit 0
      fi
      _rm="${_rt#*$'\x1f'}"; _rm="${_rm%%$'\x1f'*}"
      _red="$(head -c 16384 "$REG_FILE" 2>/dev/null | tail -n +2)"
      _first="$(printf '%s\x1f%s\x1f%s' "$_tok" "$_rm" "$(_token_new)")"
      _put "$REG_FILE" "$_first"$'\n'"$_red"
      if [[ "$(_first_line "$REG_FILE")" != "$_first" ]]; then echo "REGISTER: failed — could not save the registration ($REG_FILE); tell the user"; exit 0; fi
      echo "REGISTERED: turn $_tok · model ${_rm:-?} · kept (scope unchanged after the answer)"
      _rewrite_out "$_red"
      exit 0
    fi
    _list="$(_checklist_for "$KEY")"
    [[ -n "$_list" ]] || { echo "REGISTER: skipped (no requirement list)"; exit 0; }
    [[ -n "$ID" ]] || { echo "REGISTER: refused — pass --model <your exact model id>"; exit 0; }
    _sub="$(head -c 16384 2>/dev/null || true)"
    _sub="$(scv_mp_register_normalize "$_sub")"
    _prob="$(scv_mp_register_problems "$_list" "$_sub")"
    if [[ -n "$_prob" ]]; then
      echo "REGISTER: incomplete — fix and run again:"
      printf '%s\n' "$_prob" | sed 's/^/  /'
      echo "CHECKLIST (${KEY:-common}):"
      printf '%s\n' "$_list" | while IFS=$'\t' read -r _i _l; do [[ -n "$_i" ]] && printf '  %s | %s\n' "$_i" "$_l"; done
      exit 0
    fi
    _tok="$(_first_line "$TOKEN_FILE")"
    _red="$_sub"; [[ -f "$SCRIPT_DIR/journal-append.sh" ]] && _red="$(printf '%s' "$_sub" | bash "$SCRIPT_DIR/journal-append.sh" --redact-only 2>/dev/null || printf '%s' "$_sub")"
    # v0.65.0+ — 첫 줄 셋째 칸은 등록마다 새로 생기는 차례 — 선택 창 답이 이 등록 뒤에 왔는지 가른다.
    _first="$(printf '%s\x1f%s\x1f%s' "$_tok" "$ID" "$(_token_new)")"
    _put "$REG_FILE" "$_first"$'\n'"$_red"
    # 저장을 다시 읽어 확인한다 — 못 남겼는데 "등록됨" 이라 하면 모델이 거절과 등록 사이를 맴돈다(독립 검토).
    if [[ "$(_first_line "$REG_FILE")" != "$_first" ]]; then echo "REGISTER: failed — could not save the registration ($REG_FILE); tell the user"; exit 0; fi
    _n="$(printf '%s\n' "$_list" | grep -c . || true)"
    echo "REGISTERED: turn ${_tok:-?} · model $ID · $_n item(s)"
    _rewrite_out "$_red"
    ;;
  kind)
    # v0.63.0+ — 스위치와 무관하게 판별만 한다. 입력은 표준 입력의 프롬프트(64KB 까지).
    scv_mp_prompt_kind "$(head -c 65536 2>/dev/null || true)" "${SCV_AUTO_PROMPT_TAGS:-}" "${SCV_AUTO_PROMPT_PREFIX:-}" "${SCV_AUTO_PROMPT_SUFFIX:-}"; echo
    ;;
  gate)
    [[ "$SWITCH" == "on" && -n "$(_checklist_for "")" ]] || exit 0
    _tok="$(_first_line "$TOKEN_FILE")"; [[ -n "$_tok" ]] || exit 0
    # v0.63.0+ — 자동 입력 턴(표시 = 지금 표)은 등록할 사람의 요청이 없으니 거절하지 않는다(직전 사람 턴이 등록 없이 끝났어도).
    [[ "$(_first_line "$AUTO_FILE")" == "$_tok" ]] && exit 0
    _rt="$(_first_line "$REG_FILE")"
    # v0.65.0+ — 답 뒤 재등록 · 범위 칸 금지(범위 칸만 본다 — 다른 칸의 문장은 판정하지 않는다).
    _hit=""; [[ "${_rt%%$'\x1f'*}" == "$_tok" ]] \
      && _hit="$(scv_mp_scope_forbid "$(scv_mp_register_value "$(head -c 16384 "$REG_FILE" 2>/dev/null | tail -n +2)" scope)")"
    _forbid=0; [[ -n "$_hit" ]] && _forbid=1
    _v="$(scv_mp_write_gate "$_tok" "$_rt" "$(_first_line "$ANS_FILE")" "$_forbid" "$CODE_ARG")"
    [[ "$_v" == "ok" ]] && exit 0
    # v0.65.0+ — 하위 에이전트(훅 입력의 에이전트 id)의 쓰기: 등록하지 않았다는 이유로는 막지 않는다(사람 메시지를 받은 것은 그
    # 에이전트가 아니다). 다만 이 세션의 마지막 등록이 낡았거나(답 뒤) 범위가 변경을 막으면, 맡긴 편집도 그 등록을 따른다 — 하위
    # 에이전트는 등록하지 않으니 리드에게 돌려보내라고 말한다.
    if [[ -n "$AGENT_ARG" ]]; then
      [[ "$_v" == "unregistered" ]] && exit 0
      scv_mp_gate_reason_sub "$_v" "$_hit"; echo; exit 0
    fi
    _lm=""; [[ "${_rt%%$'\x1f'*}" == "$_tok" ]] && { _lm="${_rt#*$'\x1f'}"; _lm="${_lm%%$'\x1f'*}"; }
    [[ -n "$_lm" ]] || _lm="$(_last_model)"
    scv_mp_gate_reason "$_v" "$_tok" "$SCRIPT_DIR/model-prompting.sh" "$_lm" "$SKEY" "$_hit"; echo
    ;;
  principle-gate)
    # v0.64.0+ — 답의 끝 메시지에 문제 표 · '생길 수 있는 문제' 칸이 있으면 막는다. 원칙이 실리는 곳(요구 항목 데이터가 있고
    # 원칙 스위치가 켜짐)에서만 판정하고, 아니면 ok — 이 기능 전과 같다. 자동 알림 턴도 본다(턴 종류와 무관).
    # v0.65.0+ — 답 전체를 본다: '|' 나 '```' 가 든 줄만 먼저 고른다 — 판정이 보는 줄(표 줄 · 코드 블록 경계)을 모두 담는 더 넓은
    # 거름이라 결과는 같고(줄 앞 공백의 종류와 무관), 64KB 를 넘는 답의 한가운데 표도 잡는다(고른 줄은 128KB 까지).
    ANSWER="$(LC_ALL=C grep -E '[|]|```' 2>/dev/null | head -c 131072 || true)"
    _psw="$(scv_mp_switch "$(_setting SCV_REWRITE_PRINCIPLE)")"
    [[ "$SWITCH" == "on" && -n "$(_checklist_for "")" ]] || _psw="off"
    _hit=0; [[ "$ANSWER" == *[![:space:]]* ]] && _hit="$(scv_mp_answer_has_problem_table "$ANSWER")"
    _pg="$(scv_mp_principle_gate "$_hit" "$_psw" "$ACTIVE_ARG")"
    echo "PRINCIPLE_GATE: $_pg"
    if [[ "$_pg" != "ok" ]]; then
      _why="$(scv_mp_principle_reason)"
      echo "PRINCIPLE_REASON: $_why"
      [[ "$_pg" == "warn" ]] && _warn_add "[SCV 가이드] 직전 턴: $_why"
    fi
    ;;
  stop)
    ANSWER="$(head -c 65536 2>/dev/null || true)"
    # v0.62.0+ — 매 턴 등록 판정: 이번 턴 표가 있고(매 턴 훅이 씀) 요구 항목 데이터가 있을 때만. ok | block | warn.
    if [[ "$SWITCH" == "on" && -n "$(_checklist_for "")" ]]; then
      _tok="$(_first_line "$TOKEN_FILE")"
      # v0.63.0+ — 자동 입력 턴(표시 = 지금 표)은 사람의 요청이 없으니 등록 · 인용을 판정하지 않는다.
      if [[ -n "$_tok" && "$(_first_line "$AUTO_FILE")" == "$_tok" ]]; then echo "STOP_GATE: auto"; _tok=""; fi
      # v0.65.0+ — 매 턴 훅을 거치지 않는 자동 입력(다른 세션이 보낸 메시지)이 이 턴을 열었고(종료 훅이 대화 기록에서 판별해 넘긴다)
      # 지난 사람 턴이 이미 끝났으면(끝난 턴 표 = 지금 표) 자동 턴과 같다. 사람 턴이 막힌 채 이어지는 중이면 지금처럼 판정한다.
      if [[ -n "$_tok" && "$OPENED_AUTO" == "1" && "$(_first_line "$DONE_FILE")" == "$_tok" ]]; then echo "STOP_GATE: auto"; _tok=""; fi
      if [[ -n "$_tok" ]]; then
        _rt="$(_first_line "$REG_FILE")"; _reg=0; [[ "${_rt%%$'\x1f'*}" == "$_tok" ]] && _reg=1
        _rw=""; (( _reg )) && _rw="$(scv_mp_register_rewrite "$(head -c 16384 "$REG_FILE" 2>/dev/null | tail -n +2)")"
        _shown=""; [[ "$ANSWER" == *[![:space:]]* ]] && _shown="$(scv_mp_answer_shows_rewrite "$ANSWER" "$_rw")"
        # v0.65.0+ — 답 맨 위의 "이렇게 이해하고 일함: …" 한 줄(등록한 턴만 판정한다 — 등록이 없으면 등록이 먼저다).
        _top=""; [[ "$ANSWER" == *[![:space:]]* ]] && _top="$(scv_mp_answer_has_topline "$ANSWER")"
        _sg="$(scv_mp_stop_gate "$_reg" "$_shown" "$ACTIVE_ARG" "$_top")"
        echo "STOP_GATE: $_sg"
        # v0.63.0+ — 막지 않으면 이 턴은 끝난다: 자동 입력 턴 표시의 근거(끝난 턴 표). 자동 태그가 없으면 쓰지 않는다(이전과 같은 파일들).
        [[ "$_sg" != "block" && "$SCV_AUTO_PROMPT_TAGS" == *[![:space:]]* ]] && _put "$DONE_FILE" "$_tok"
        if [[ "$_sg" != "ok" ]]; then
          _lm=""; (( _reg )) && { _lm="${_rt#*$'\x1f'}"; _lm="${_lm%%$'\x1f'*}"; }
          [[ -n "$_lm" ]] || _lm="$(_last_model)"
          _why="$(scv_mp_stop_reason "$_reg" "$_shown" "$_top" "$_tok" "$SCRIPT_DIR/model-prompting.sh" "$_lm" "$SKEY")"
          echo "STOP_REASON: [SCV 프롬프트] $_why"
          [[ "$_sg" == "warn" ]] && _warn_add "[SCV 가이드] 직전 턴: $_why"
        fi
        # 이 판정(stop)은 판정을 파일에 남기지 않는다 — 여기서 쓰는 것은(계속 중일 때만) 다음 턴 경고, 그리고(0.63.0+, 자동
        # 태그가 있을 때만) 끝난 턴 표뿐이다. 저널은 종료 훅이 쓰고, 이번 턴 전달 기록(.help-turn-gates, v0.64.2+)도 종료 훅
        # on-stop.sh 가 막을 때 쓴다.
        # 막을 때의 사유는 호스트가 대화 기록에 남긴다.
      fi
    fi
    # 이번 턴에 help 가 가이드를 내지 않았으면 원문 읽음 판정은 할 것이 없다.
    TURN="$(scv_mp_turn_parse "$(_first_line "$TURN_FILE")")"
    [[ -n "$TURN" ]] || { _drop "$TURN_FILE"; exit 0; }
    DETAIL="$(head -c 4096 "$TURN_FILE" 2>/dev/null | tail -n +2)"   # v0.60.1+: help 가 낸 GUIDE_FILE · GUIDE_MARK_CMD 줄
    IFS=$'\x1f' read -r _tn TMODEL TDEC TKEY <<< "$TURN"
    WAS_READ="$(scv_mp_was_read "$TURN" "$RECORD" "$NONCE")"
    # 다시 쓴 요청이 기록됐나: 가장 최근에 바뀐 대화 파일이 이번 턴 기록보다 나중(같은 초 포함)에 바뀌었을 때만
    # 그 파일의 마지막 Turn 블록을 본다. 대화 폴더가 없거나 오래된 파일이면 "기록 안 됨" — 경고하지 않는 쪽.
    RECORDED=0; _cdir="${SCV_CONVERSATIONS_DIR:-scv/conversations}"; _best=""; _bm=0
    if [[ -d "$_cdir" ]]; then
      for _f in "$_cdir"/*.md; do
        [[ -f "$_f" && ! -L "$_f" ]] || continue
        _m="$(_mtime "$_f")"; [[ "$_m" =~ ^[0-9]+$ ]] || _m=0
        if (( _m >= _bm )); then _bm=$_m; _best="$_f"; fi
      done
      _tm="$(_mtime "$TURN_FILE")"; [[ "$_tm" =~ ^[0-9]+$ ]] || _tm=0
      if [[ -n "$_best" ]] && (( _bm >= _tm )); then
        _blk="$(tail -n 400 "$_best" 2>/dev/null | awk '/^## Turn /{b=""} {b=b $0 "\n"} END{printf "%s", b}')"
        RECORDED="$(scv_mp_rewrite_recorded "$_blk")"
      fi
    fi
    QUOTED=""; [[ "$ANSWER" == *[![:space:]]* ]] && QUOTED="$(scv_mp_answer_has_quote "$ANSWER")"
    VERDICT="$(scv_mp_turn_verdict "$TDEC" "$WAS_READ" "$RECORDED" "$QUOTED")"
    _drop "$TURN_FILE"
    if [[ -n "$VERDICT" ]] && _dir_ok "$TDIR"; then
      [[ -L "$WARN_FILE" ]] || scv_mp_warn_lines "$VERDICT" "$TKEY" "$DETAIL" >> "$WARN_FILE" 2>/dev/null
    fi
    _drift="$JOURNAL_DIR/.help-drift"; _now="$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"
    _vs="$(printf '%s' "$VERDICT" | tr '\n' ',' | sed 's/,$//')"
    mkdir -p "$JOURNAL_DIR" 2>/dev/null && [[ ! -L "$_drift" ]] \
      && printf '%s guide=%s decision=%s read=%s recorded=%s quoted=%s verdict=%s\n' "$_now" "${TKEY:-?}" "$TDEC" "$WAS_READ" "$RECORDED" "${QUOTED:-?}" "${_vs:-ok}" >> "$_drift" 2>/dev/null
    echo "GUIDE_VERDICT: ${_vs:-ok}"
    ;;
  *) echo "usage: model-prompting.sh guide|mark|status|prompt|human|session|answered|checklist|register [--keep]|kind|gate|principle-gate|stop --model <id> [--session <id>]" >&2 ;;
esac
exit 0
