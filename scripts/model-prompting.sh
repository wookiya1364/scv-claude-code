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
#   model-prompting.sh gate                 (v0.62.0+) 가드가 부른다: 이번 턴 등록 전이면 거절 사유를 낸다(아니면 아무것도)
#   model-prompting.sh kind < 프롬프트        (v0.63.0+) 매 턴 훅이 부른다: auto(호스트가 보낸 입력 — 호스트 프로필 SCV_AUTO_PROMPT_TAGS) | human
#   model-prompting.sh prompt --auto        (v0.63.0+) 자동 입력 턴: 새 표 없이 "이번 턴은 자동" 표시만 남긴다(출력 없음)
#   model-prompting.sh principle-gate [--active 0|1] < 끝 메시지  (v0.64.0+) 종료 훅이 부른다: 문제 표 · '생길 수 있는 문제'
#                                            칸이 있으면 PRINCIPLE_GATE: block(+ PRINCIPLE_REASON), 계속 중이면 warn(다음 턴 경고)
#   model-prompting.sh stop < 답본문        (v0.60.0+) 종료 훅이 부른다: 이번 턴에 원문을 읽었는지 · 다시 쓴 요청을
#                                            답에 보였는지 결과로 판정 → 어긋나면 다음 턴 경고(.help-warn 에 덧붙임)
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

JOURNAL_DIR="${SCV_JOURNAL_DIR:-scv/journal}"
READ_FILE="$JOURNAL_DIR/.help-guide"
TURN_FILE="$JOURNAL_DIR/.help-guide-turn"
LAST_FILE="$JOURNAL_DIR/.help-guide-last"
TOKEN_FILE="$JOURNAL_DIR/.help-turn"          # v0.62.0+: 매 턴 훅이 새로 쓰는 이번 턴 표 — 등록이 이 턴 것인지 가른다
AUTO_FILE="$JOURNAL_DIR/.help-turn-auto"      # v0.63.0+: 자동 입력 턴 표시 — 그 턴의 표(바뀌지 않은 지난 표) 한 줄
DONE_FILE="$JOURNAL_DIR/.help-turn-done"      # v0.63.0+: 끝난 턴의 표 — 종료 판정이 막지 않고 끝낸 턴(자동 태그가 있을 때만 씀)
REG_FILE="$JOURNAL_DIR/.help-rewrite"         # v0.62.0+: 이번 턴 등록(첫 줄 표\x1f모델, 다음 줄부터 제출)   # v0.61.0+: help 가 마지막으로 본 모델 — 컨텍스트에 묶이지 않아 초기화가 지우지 않는다
STATE_FILE="$JOURNAL_DIR/.help-state"

cmd="${1:-guide}"; shift || true
MODEL_RAW=""; SESSION_ARG=""; ACTIVE_ARG="0"; AUTO_ARG=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --session) SESSION_ARG="${2:-}"; shift 2 || shift ;;
    --active)  ACTIVE_ARG="${2:-0}"; shift 2 || shift ;;
    --auto)    AUTO_ARG=1; shift ;;
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
_put() {  # <파일> <본문> — 임시 파일 뒤 mv. 심볼릭 링크면 안 쓴다.
  local file="$1" body="$2" tmp
  mkdir -p "$JOURNAL_DIR" 2>/dev/null || return 0
  [[ -L "$file" ]] && return 0
  tmp="$(mktemp "$file.XXXXXX" 2>/dev/null)" || return 0
  printf '%s\n' "$body" > "$tmp" 2>/dev/null && mv -f "$tmp" "$file" 2>/dev/null || rm -f "$tmp" 2>/dev/null
  return 0
}
_drop() { [[ -f "$1" && ! -L "$1" ]] && rm -f "$1" 2>/dev/null; return 0; }
_mtime() { stat -c '%Y' "$1" 2>/dev/null || stat -f '%m' "$1" 2>/dev/null || printf '0'; }

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
    _rn="${RECORD%%$'\x1f'*}"; _read=0; [[ -n "$_rn" && "$_rn" == "$NONCE" ]] && _read=1
    [[ -n "$SESSION_ARG" && "$SESSION_ARG" != "$STATE_SESSION" ]] && _read=0
    _warned=0; _w="$JOURNAL_DIR/.help-warn"
    [[ -f "$_w" && ! -L "$_w" ]] && head -c 4096 "$_w" 2>/dev/null | grep -q '^\[SCV 가이드\]' && _warned=1
    _rec=""; [[ -f "$LAST_FILE" && ! -L "$LAST_FILE" ]] && _rec="$(head -c 4096 "$LAST_FILE" 2>/dev/null)"
    # v0.62.0+: 매 턴(모든 메시지) 새 표를 쓰고 1:1 비교 · 등록 블록을 싣는다 — 요구 항목 데이터가 있는 호스트에서만.
    if [[ "$SWITCH" == "on" && -n "$(_checklist_for "")" ]]; then
      _tok="$(_token_new)"; _put "$TOKEN_FILE" "$_tok"
      _lm="$(_last_model)"; _list=""; [[ -n "$_lm" ]] && _list="$(_checklist_for "$(_key_of "$_lm")")"
      scv_mp_turn_block "$SWITCH" "$_tok" "$_lm" "$_list" "$SCRIPT_DIR/model-prompting.sh"
    fi
    scv_mp_first_turn_lines "$SWITCH" "$_read" "$_warned" "$_rec"
    ;;
  checklist)
    _list="$(_checklist_for "$KEY")"
    [[ -n "$_list" ]] || { echo "CHECKLIST: none (this host ships no requirement list)"; exit 0; }
    echo "CHECKLIST: ${KEY:-common} (model ${ID:-?})"
    printf '%s\n' "$_list" | while IFS=$'\t' read -r _i _l; do [[ -n "$_i" ]] && printf '%s | %s\n' "$_i" "$_l"; done
    echo "REGISTER: bash \"$SCRIPT_DIR/model-prompting.sh\" register --model \"${ID:-<id>}\" — stdin: id | msg|ctx|asked|na | value, then rewrite | - | <rewritten request>"
    ;;
  register)
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
    _put "$REG_FILE" "$(printf '%s\x1f%s' "$_tok" "$ID")"$'\n'"$_red"
    _n="$(printf '%s\n' "$_list" | grep -c . || true)"
    echo "REGISTERED: turn ${_tok:-?} · model $ID · $_n item(s)"
    # (v0.63.0+) SCV 원칙 — 저장된 제출에는 넣지 않고 출력에만 붙인다. off · 원칙 파일 없음이면 이 기능 전과 같은 출력.
    _psw="$(scv_mp_switch "$(_setting SCV_REWRITE_PRINCIPLE)")"
    _psec=""; [[ "$_psw" == "on" ]] && _psec="$(scv_mp_principle_section "$(_principle_body)" "$(_setting SCV_LANG)")"
    echo "REWRITE: $(scv_mp_rewrite_tagged "$(scv_mp_register_rewrite "$_red")" "$_psw" "$(scv_mp_principle_tag "$_psec")")"
    if [[ -n "$_psec" ]]; then
      echo "PRINCIPLE:"
      printf '%s\n' "$(scv_mp_principle_text "$_psec")"
    fi
    ;;
  kind)
    # v0.63.0+ — 스위치와 무관하게 판별만 한다. 입력은 표준 입력의 프롬프트(64KB 까지).
    scv_mp_prompt_kind "$(head -c 65536 2>/dev/null || true)" "${SCV_AUTO_PROMPT_TAGS:-}"; echo
    ;;
  gate)
    [[ "$SWITCH" == "on" && -n "$(_checklist_for "")" ]] || exit 0
    _tok="$(_first_line "$TOKEN_FILE")"; [[ -n "$_tok" ]] || exit 0
    # v0.63.0+ — 자동 입력 턴(표시 = 지금 표)은 등록할 사람의 요청이 없으니 거절하지 않는다(직전 사람 턴이 등록 없이 끝났어도).
    [[ "$(_first_line "$AUTO_FILE")" == "$_tok" ]] && exit 0
    _rt="$(_first_line "$REG_FILE")"; [[ "${_rt%%$'\x1f'*}" == "$_tok" ]] && exit 0
    _lm="$(_last_model)"
    echo "SCV 프롬프트: 이번 턴($_tok)의 요청을 아직 모델 가이드 요구 항목과 비교 · 등록하지 않아 파일 쓰기를 거절한다. 먼저 bash \"$SCRIPT_DIR/model-prompting.sh\" checklist --model \"${_lm:-<지금 모델 id>}\" 로 항목을 받아 비교하고, bash \"$SCRIPT_DIR/model-prompting.sh\" register --model \"${_lm:-<지금 모델 id>}\" 로 등록한 뒤(stdin: id | msg|ctx|asked|na | 값, 끝에 rewrite | - | 다시 쓴 요청) 다시 시도하라."
    ;;
  principle-gate)
    # v0.64.0+ — 답의 끝 메시지에 문제 표 · '생길 수 있는 문제' 칸이 있으면 막는다. 원칙이 실리는 곳(요구 항목 데이터가 있고
    # 원칙 스위치가 켜짐)에서만 판정하고, 아니면 ok — 이 기능 전과 같다. 자동 알림 턴도 본다(턴 종류와 무관).
    ANSWER="$(head -c 65536 2>/dev/null || true)"
    _psw="$(scv_mp_switch "$(_setting SCV_REWRITE_PRINCIPLE)")"
    [[ "$SWITCH" == "on" && -n "$(_checklist_for "")" ]] || _psw="off"
    _hit=0; [[ "$ANSWER" == *[![:space:]]* ]] && _hit="$(scv_mp_answer_has_problem_table "$ANSWER")"
    _pg="$(scv_mp_principle_gate "$_hit" "$_psw" "$ACTIVE_ARG")"
    echo "PRINCIPLE_GATE: $_pg"
    if [[ "$_pg" != "ok" ]]; then
      _why="$(scv_mp_principle_reason)"
      echo "PRINCIPLE_REASON: $_why"
      if [[ "$_pg" == "warn" ]]; then
        mkdir -p "$JOURNAL_DIR" 2>/dev/null && [[ ! -L "$JOURNAL_DIR/.help-warn" ]] && printf '%s\n' "[SCV 가이드] 직전 턴: $_why" >> "$JOURNAL_DIR/.help-warn" 2>/dev/null
      fi
    fi
    ;;
  stop)
    ANSWER="$(head -c 65536 2>/dev/null || true)"
    # v0.62.0+ — 매 턴 등록 판정: 이번 턴 표가 있고(매 턴 훅이 씀) 요구 항목 데이터가 있을 때만. ok | block | warn.
    if [[ "$SWITCH" == "on" && -n "$(_checklist_for "")" ]]; then
      _tok="$(_first_line "$TOKEN_FILE")"
      # v0.63.0+ — 자동 입력 턴(표시 = 지금 표)은 사람의 요청이 없으니 등록 · 인용을 판정하지 않는다.
      if [[ -n "$_tok" && "$(_first_line "$AUTO_FILE")" == "$_tok" ]]; then echo "STOP_GATE: auto"; _tok=""; fi
      if [[ -n "$_tok" ]]; then
        _rt="$(_first_line "$REG_FILE")"; _reg=0; [[ "${_rt%%$'\x1f'*}" == "$_tok" ]] && _reg=1
        _rw=""; (( _reg )) && _rw="$(scv_mp_register_rewrite "$(head -c 16384 "$REG_FILE" 2>/dev/null | tail -n +2)")"
        _shown=""; [[ "$ANSWER" == *[![:space:]]* ]] && _shown="$(scv_mp_answer_shows_rewrite "$ANSWER" "$_rw")"
        _sg="$(scv_mp_stop_gate "$_reg" "$_shown" "$ACTIVE_ARG")"
        echo "STOP_GATE: $_sg"
        # v0.63.0+ — 막지 않으면 이 턴은 끝난다: 자동 입력 턴 표시의 근거(끝난 턴 표). 자동 태그가 없으면 쓰지 않는다(이전과 같은 파일들).
        [[ "$_sg" != "block" && "$SCV_AUTO_PROMPT_TAGS" == *[![:space:]]* ]] && _put "$DONE_FILE" "$_tok"
        _lm="$(_last_model)"
        if [[ "$_sg" != "ok" ]]; then
          if (( _reg )); then
            _why="이번 턴에 등록한 다시 쓴 요청을 답에 보이지 않았다 — 결론 바로 뒤에 인용 블록으로 보여라(REWRITE 줄 그대로)."
          else
            _why="이번 턴($_tok)의 요청을 모델 가이드 요구 항목과 비교 · 등록하지 않았다 — bash \"$SCRIPT_DIR/model-prompting.sh\" checklist --model \"${_lm:-<지금 모델 id>}\" 로 항목을 받아 비교하고, register 로 등록한 뒤, 다시 쓴 요청을 결론 바로 뒤 인용으로 보이고 그것으로 답하라."
          fi
          echo "STOP_REASON: [SCV 프롬프트] $_why"
          if [[ "$_sg" == "warn" ]]; then
            mkdir -p "$JOURNAL_DIR" 2>/dev/null && [[ ! -L "$JOURNAL_DIR/.help-warn" ]] && printf '%s\n' "[SCV 가이드] 직전 턴: $_why" >> "$JOURNAL_DIR/.help-warn" 2>/dev/null
          fi
        fi
        # 판정은 파일에 남기지 않는다 — 종료 훅이 쓰는 것은 저널과(계속 중일 때만) 다음 턴 경고, 그리고(0.63.0+, 자동 태그가
        # 있을 때만) 끝난 턴 표뿐이다.
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
    if [[ -n "$VERDICT" ]]; then
      mkdir -p "$JOURNAL_DIR" 2>/dev/null || exit 0
      _warn="$JOURNAL_DIR/.help-warn"
      [[ -L "$_warn" ]] || scv_mp_warn_lines "$VERDICT" "$TKEY" "$DETAIL" >> "$_warn" 2>/dev/null
    fi
    _drift="$JOURNAL_DIR/.help-drift"; _now="$(date -Iseconds 2>/dev/null || date +%Y-%m-%dT%H:%M:%S)"
    _vs="$(printf '%s' "$VERDICT" | tr '\n' ',' | sed 's/,$//')"
    mkdir -p "$JOURNAL_DIR" 2>/dev/null && [[ ! -L "$_drift" ]] \
      && printf '%s guide=%s decision=%s read=%s recorded=%s quoted=%s verdict=%s\n' "$_now" "${TKEY:-?}" "$TDEC" "$WAS_READ" "$RECORDED" "${QUOTED:-?}" "${_vs:-ok}" >> "$_drift" 2>/dev/null
    echo "GUIDE_VERDICT: ${_vs:-ok}"
    ;;
  *) echo "usage: model-prompting.sh guide|mark|status|prompt|checklist|register|kind|gate|principle-gate|stop --model <id>" >&2 ;;
esac
exit 0
