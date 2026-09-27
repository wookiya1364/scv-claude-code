#!/usr/bin/env bash
# model-prompting.sh — 모델별 프롬프팅의 효과부. 읽기·쓰기는 여기서만, 판단은 lib/model-prompting.sh.
#
#   model-prompting.sh guide --model <id>   help 가 부른다: 이 모델의 가이드 원문을 읽어야 하나 → GUIDE 줄들
#   model-prompting.sh mark  --model <id>   모델이 원문을 읽은 뒤: 이 컨텍스트(지금 규약 지문)에서 이 모델을 읽음으로 기록
#   model-prompting.sh status [--model <id>] 사람이 본다: 가이드 폴더 · 색인 행 수 · 읽음 기록 · (모델이 있으면) 결정
#
# 입력: 호스트 프로필 SCV_PROMPTING_GUIDES (래퍼가 준다), 그 폴더의 INDEX.tsv, help 표식의 규약 지문(nonce),
#       ${SCV_JOURNAL_DIR:-scv/journal}/.help-guide (읽음 기록), 설정 SCV_MODEL_PROMPTING(on|off) ·
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
STATE_FILE="$JOURNAL_DIR/.help-state"

cmd="${1:-guide}"; shift || true
MODEL_RAW=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)   MODEL_RAW="${2:-}"; shift 2 || shift ;;
    --model=*) MODEL_RAW="${1#--model=}"; shift ;;
    *) shift ;;
  esac
done

# ---------------------------------------------------------------- 효과: 읽기 (입구)
_setting() { declare -F settings_get >/dev/null 2>&1 && settings_get "$1" 2>/dev/null || true; }
_first_line() { [[ -f "$1" && ! -L "$1" ]] && head -c 4096 "$1" 2>/dev/null | head -1 || printf ''; }

ID="$(scv_mp_normalize_id "$MODEL_RAW")"
SWITCH="$(scv_mp_switch "$(_setting SCV_MODEL_PROMPTING)")"
MAX_AGE="$(_setting SCV_MODEL_PROMPTING_MAX_AGE_DAYS)"; [[ "$MAX_AGE" =~ ^[0-9]+$ ]] || MAX_AGE=90
GUIDES_DIR="$(scv_mp_guides_dir "$CORE_ROOT" "${SCV_PROMPTING_GUIDES:-}")"
INDEX_FILE=""; INDEX=""
if [[ -n "$GUIDES_DIR" && -f "$GUIDES_DIR/INDEX.tsv" && ! -L "$GUIDES_DIR/INDEX.tsv" ]]; then
  INDEX_FILE="$GUIDES_DIR/INDEX.tsv"
  INDEX="$(head -c 65536 "$INDEX_FILE" 2>/dev/null)"
fi
# 지금 규약 지문 — help 표식의 여섯째 필드. 컨텍스트가 바뀌면 비워진다(lib 머리말 참조).
NONCE="$(scv_hstate_nonce "$(scv_hstate_parse "$(_first_line "$STATE_FILE")")")"
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
  *) echo "usage: model-prompting.sh guide|mark|status --model <id>" >&2 ;;
esac
exit 0
