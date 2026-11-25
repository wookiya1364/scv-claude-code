#!/usr/bin/env bash
# words.sh — 프로젝트 낱말 사전을 보고 · 고치고 · 답을 검사한다 (계획 20261125-wookiya1364-words).
#
# 사용자가 정한 말("재다" 대신 "측정하다")을 프로젝트마다 한 파일에 둔다. 대화 첫머리에 안내 묶음이 한 번 실리고,
# 답이 나간 뒤 직전 답에서 피할 말을 찾아 다음 턴에 한 줄로 알린다 — 이미 보인 답은 다시 쓰게 하지 않는다.
#
#   words.sh list                         항목을 저장된 그대로 한 줄씩(탭으로 나눈 네 칸). 없으면 "WORDS: none"
#   words.sh add --avoid "<피할 말>" --use "<쓸 말>" [--forms "<꼴, 꼴, …>"] [--note "<메모>"]
#                                         항목을 넣는다. 같은 피할 말이 있으면 갈아 끼운다 — --forms 를 주지 않으면 있던 꼴을,
#                                         --note 를 주지 않으면 있던 메모를 지킨다. "WORDS_SAVED: <피할 말> → <쓸 말>"
#   words.sh remove "<피할 말>"            항목을 뺀다. "WORDS_REMOVED: <피할 말>"
#   words.sh check                        표준 입력의 답 글에서 피할 말을 찾는다 — 항목마다 "WORDS_HIT: <찾은 꼴> → <쓸 말>"
#   words.sh text                         대화 첫머리에 실을 안내 묶음(항목이 없으면 아무것도 내지 않는다)
#   words.sh turn --dir <세션 자리>        매 턴 훅이 부른다 — 이 맥락에 아직 싣지 않았거나 사전이 바뀌었으면 안내 묶음을 내고
#                                         세션 자리에 표시(.words-seen — 사전의 지문)를 남긴다. 한 번만 싣기는 SCV_RULES_ONCE 를 따른다
#
# 자리:  scv/words/WORDS.tsv — 한 줄에 항목 하나, 탭으로 나눈 네 칸: 피할 말(으뜸꼴 — 항목의 이름) · 쓸 말 · 다른 꼴들(", " 로 나눔) · 메모.
#        "#" 로 시작하는 줄과 빈 줄은 읽지 않는다. 칸 안의 탭 · 줄바꿈은 빈칸으로 바꿔 쓴다. 저장소와 함께 커밋된다.
# 끄기:  설정 SCV_WORDS=off(환경 변수도 같다) — text · turn 은 아무것도 내지 않고 check 는 찾지 않는다. list · add · remove 는 그대로 된다.
# 판단은 lib/words.sh 의 순수 함수가 하고, 여기는 읽기 · 쓰기 · 출력만 한다.
# Exit: 0 해냄(check 는 찾은 것 없음) · 1 check 가 찾음 · remove 할 말이 없음 · 쓰기 실패 · 2 잘못된 인자(WORDS_ERROR 줄은 표준 오류로)
set -uo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/words.sh
source "$SCRIPT_DIR/lib/words.sh"
# shellcheck source=lib/switch.sh
source "$SCRIPT_DIR/lib/switch.sh"
# shellcheck source=lib/scvroot.sh
source "$SCRIPT_DIR/lib/scvroot.sh"

SCV_ROOT="$(scv_root_dir 2>/dev/null || printf 'scv')"
WFILE="${SCV_WORDS_FILE:-$SCV_ROOT/words/WORDS.tsv}"
# 설정 파일은 같은 scv/ 아래에서 읽는다(하위 폴더에서 불러도 같은 프로젝트의 설정을 본다).
export SCV_SETTINGS_FILE="${SCV_SETTINGS_FILE:-$SCV_ROOT/scv_settings.json}"
export SCV_SETTINGS_SECRET_FILE="${SCV_SETTINGS_SECRET_FILE:-$SCV_ROOT/scv_settings.secret.json}"
# shellcheck source=lib/settings.sh
source "$SCRIPT_DIR/lib/settings.sh" 2>/dev/null || true
HEAD_LINE='# SCV words — one entry per line, 4 tab-separated fields: avoid, use, forms (", " separated), note. Edit with the SCV words action.'

# @effect die
# 이유: 오류 한 줄을 표준 오류에 쓰고 주어진 종료 코드로 끝낸다
die() { printf 'WORDS_ERROR: %s\n' "$2" >&2; exit "$1"; }

# @effect setting
# 이유: 설정 파일 · 환경 변수에서 값 하나를 읽는다(읽는 길이 없으면 빈 값)
setting() { declare -F settings_get >/dev/null 2>&1 && settings_get "$1" 2>/dev/null || true; }

# @effect entries
# 이유: 사전 파일을 읽어 항목 줄들을 낸다(파일이 없거나 링크면 빈 값)
entries() {
  [[ -f "$WFILE" && ! -L "$WFILE" ]] || return 0
  scv_words_parse "$(head -c 262144 "$WFILE" 2>/dev/null)"
}

# @effect save
# 이유: 항목 줄들을 사전 파일에 쓴다 — 있던 주석 줄은 맨 위에 그대로 두고, 임시 파일에 쓴 뒤 옮긴다
save() {
  local body="$1" dir="${WFILE%/*}" notes="" tmp
  [[ -L "$WFILE" || -L "$dir" ]] && die 1 "사전 파일이나 그 폴더가 링크다 — 쓰지 않는다: $WFILE"
  mkdir -p "$dir" 2>/dev/null || die 1 "사전 폴더를 만들지 못했다: $dir"
  if [[ -f "$WFILE" ]]; then notes="$(grep -E '^[[:space:]]*#' "$WFILE" 2>/dev/null || true)"; else notes="$HEAD_LINE"; fi
  tmp="$(mktemp "$WFILE.XXXXXX" 2>/dev/null)" || die 1 "사전 파일을 쓰지 못했다: $WFILE"
  { [[ -z "$notes" ]] || printf '%s\n' "$notes"; [[ -z "$body" ]] || printf '%s\n' "$body"; } > "$tmp" 2>/dev/null \
    && mv -f "$tmp" "$WFILE" 2>/dev/null || { rm -f "$tmp" 2>/dev/null; die 1 "사전 파일을 쓰지 못했다: $WFILE"; }
}

# @effect usage
# 이유: 쓰는 법을 표준 오류에 쓰고 종료 코드 2 로 끝낸다
usage() {
  sed -n '7,15p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

cmd="${1:-list}"; [[ $# -gt 0 ]] && shift
ON="$(scv_switch "$(setting SCV_WORDS)")"

case "$cmd" in
  list)
    E="$(entries)"
    if [[ -n "$E" ]]; then printf '%s\n' "$E"; else echo "WORDS: none"; fi ;;
  add)
    A=""; U=""; F=""; N=""; FG=0; NG=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --avoid) A="${2:-}"; shift 2 || shift ;;
        --avoid=*) A="${1#--avoid=}"; shift ;;
        --use) U="${2:-}"; shift 2 || shift ;;
        --use=*) U="${1#--use=}"; shift ;;
        --forms) F="${2:-}"; FG=1; shift 2 || shift ;;
        --forms=*) F="${1#--forms=}"; FG=1; shift ;;
        --note) N="${2:-}"; NG=1; shift 2 || shift ;;
        --note=*) N="${1#--note=}"; NG=1; shift ;;
        *) die 2 "모르는 인자: $1 (add --avoid <말> --use <말> [--forms <꼴들>] [--note <메모>])" ;;
      esac
    done
    A="$(scv_words_field "$A")"; U="$(scv_words_field "$U")"; F="$(scv_words_forms "$F")"; N="$(scv_words_field "$N")"
    why="$(scv_words_add_error "$A" "$U")"
    [[ -z "$why" ]] || die 2 "$why"
    save "$(scv_words_upsert "$(entries)" "$A" "$U" "$F" "$FG" "$N" "$NG")"
    printf 'WORDS_SAVED: %s → %s\n' "$A" "$U" ;;
  remove)
    A="$(scv_words_field "${1:-}")"
    [[ -n "$A" ]] || die 2 "뺄 말을 주지 않았다 (remove <피할 말>)"
    E="$(entries)"
    rest="$(scv_words_remove "$E" "$A")" || die 1 "사전에 없는 말이다: $A"
    save "$rest"
    printf 'WORDS_REMOVED: %s\n' "$A" ;;
  check)
    ans="$(head -c 262144 2>/dev/null || true)"
    [[ "$ON" == on ]] || exit 0
    hits="$(scv_words_hits "$ans" "$(entries)")"
    [[ -n "$hits" ]] || exit 0
    while IFS= read -r line; do printf 'WORDS_HIT: %s\n' "$line"; done <<< "$hits"
    exit 1 ;;
  text)
    [[ "$ON" == on ]] || exit 0
    out="$(scv_words_text "$(entries)" "$(setting SCV_LANG | tr -d '"[:space:]' | tr -d "'" | tr '[:upper:]' '[:lower:]')")"
    [[ -z "$out" ]] || printf '%s\n' "$out" ;;
  turn)
    D=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --dir) D="${2:-}"; shift 2 || shift ;;
        --dir=*) D="${1#--dir=}"; shift ;;
        *) shift ;;
      esac
    done
    [[ "$ON" == on ]] || exit 0
    E="$(entries)"
    [[ -n "$E" ]] || exit 0
    cur="$(cksum < "$WFILE" 2>/dev/null | tr -s '[:space:]' ' ' | sed 's/ $//')"
    mark=""; seen=""
    [[ -n "$D" && -d "$D" && ! -L "$D" && ! -L "$D/.words-seen" ]] && mark="$D/.words-seen"
    [[ -n "$mark" && -f "$mark" ]] && seen="$(head -c 256 "$mark" 2>/dev/null | head -n 1)"
    once="$(scv_switch "$(setting SCV_RULES_ONCE)")"
    [[ -n "$mark" ]] || once=off   # 표시를 남길 자리가 없으면 판단할 수 없다 — 싣는다(규칙 글과 같다)
    [[ "$(scv_words_due "$seen" "$cur" "$once")" == full ]] || exit 0
    scv_words_text "$E" "$(setting SCV_LANG | tr -d '"[:space:]' | tr -d "'" | tr '[:upper:]' '[:lower:]')"; printf '\n'
    [[ -z "$mark" ]] || printf '%s\n' "$cur" > "$mark" 2>/dev/null || true ;;
  -h|--help|help) usage ;;
  *) die 2 "모르는 명령: $cmd (list | add | remove | check | text)" ;;
esac
exit 0
