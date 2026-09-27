#!/usr/bin/env bash
# model-prompting.sh — 모델별 프롬프팅의 효과부. 읽기·쓰기는 여기서만, 판단은 lib/model-prompting.sh.
#
#   model-prompting.sh guide --model <id>   help 가 부른다: 이 모델의 가이드 원문을 읽어야 하나 → GUIDE 줄들
#   model-prompting.sh mark  --model <id>   모델이 원문을 읽은 뒤: 이 컨텍스트(지금 규약 지문)에서 이 모델을 읽음으로 기록
#   model-prompting.sh status [--model <id>] 사람이 본다: 가이드 폴더 · 색인 행 수 · 읽음 기록 · (모델이 있으면) 결정
#   model-prompting.sh prompt              (v0.61.0+) 매 턴 훅이 부른다: 이 컨텍스트에서 아직 원문을 안 읽었으면, help 가
#                                            마지막으로 본 모델의 원문 경로 · 표시 명령 블록을 낸다(아니면 아무것도)
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
LAST_FILE="$JOURNAL_DIR/.help-guide-last"   # v0.61.0+: help 가 마지막으로 본 모델 — 컨텍스트에 묶이지 않아 초기화가 지우지 않는다
STATE_FILE="$JOURNAL_DIR/.help-state"

cmd="${1:-guide}"; shift || true
MODEL_RAW=""; SESSION_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --session) SESSION_ARG="${2:-}"; shift 2 || shift ;;
    --model)   MODEL_RAW="${2:-}"; shift 2 || shift ;;
    --model=*) MODEL_RAW="${1#--model=}"; shift ;;
    *) shift ;;
  esac
done

# ---------------------------------------------------------------- 효과: 읽기 (입구)
_setting() { declare -F settings_get >/dev/null 2>&1 && settings_get "$1" 2>/dev/null || true; }
_first_line() { [[ -f "$1" && ! -L "$1" ]] && head -c 4096 "$1" 2>/dev/null | head -1 || printf ''; }
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
GUIDES_DIR="$(scv_mp_guides_dir "$CORE_ROOT" "${SCV_PROMPTING_GUIDES:-}")"
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
    # 읽음: 읽음 기록의 지문이 지금 지문과 같다(빈 지문은 증거가 아니다). 가이드 경고가 이미 예약돼 있으면 그것이 같은 내용을 싣는다.
    # 훅은 표식 갱신(세션 비교)보다 먼저 부른다 — 세션이 바뀌었으면 갱신이 지문을 비울 것이니 안 읽음으로 본다.
    _rn="${RECORD%%$'\x1f'*}"; _read=0; [[ -n "$_rn" && "$_rn" == "$NONCE" ]] && _read=1
    [[ -n "$SESSION_ARG" && "$SESSION_ARG" != "$STATE_SESSION" ]] && _read=0
    _warned=0; _w="$JOURNAL_DIR/.help-warn"
    [[ -f "$_w" && ! -L "$_w" ]] && head -c 4096 "$_w" 2>/dev/null | grep -q '^\[SCV 가이드\]' && _warned=1
    _rec=""; [[ -f "$LAST_FILE" && ! -L "$LAST_FILE" ]] && _rec="$(head -c 4096 "$LAST_FILE" 2>/dev/null)"
    scv_mp_first_turn_lines "$SWITCH" "$_read" "$_warned" "$_rec"
    ;;
  stop)
    # 이번 턴에 help 가 가이드를 내지 않았으면 판정할 것이 없다 — 아무 것도 읽지도 쓰지도 않는다.
    TURN="$(scv_mp_turn_parse "$(_first_line "$TURN_FILE")")"
    [[ -n "$TURN" ]] || { _drop "$TURN_FILE"; exit 0; }
    DETAIL="$(head -c 4096 "$TURN_FILE" 2>/dev/null | tail -n +2)"   # v0.60.1+: help 가 낸 GUIDE_FILE · GUIDE_MARK_CMD 줄
    ANSWER="$(head -c 65536 2>/dev/null || true)"
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
    QUOTED=""; [[ -n "${ANSWER//[[:space:]]/}" ]] && QUOTED="$(scv_mp_answer_has_quote "$ANSWER")"
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
  *) echo "usage: model-prompting.sh guide|mark|status|prompt|stop --model <id>" >&2 ;;
esac
exit 0
