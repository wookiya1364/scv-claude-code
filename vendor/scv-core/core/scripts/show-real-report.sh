#!/usr/bin/env bash
# show-real-report.sh — 실체 보여 주기(contracts/show-real.md)의 실사용 보고 (v0.66.0+).
# 효과부: 세션 기록 읽기(입구) · 표 출력(출구). 나누기 · 분류 · 세기 · 표는 lib/show-real.sh 의 순수부(세는 기준은 그 머리말).
#
#   show-real-report.sh --before <YYYY-MM-DD..YYYY-MM-DD> --after <YYYY-MM-DD..YYYY-MM-DD> [--dir <세션 기록 폴더>]...
#
# 켜기 전 기간은 켠 뒤 기간보다 앞서고 겹치지 않아야 한다. 기록 폴더: --dir 로 준 것들(같은 폴더는 한 번만). 없으면 SCV 가 세션마다
# 남긴 대화 기록 경로(호스트가 매 턴 훅에 준 값 — ${SCV_JOURNAL_DIR:-scv/journal}/.help-turns/<세션>/.help-transcript)의 폴더들.
# 폴더 바로 아래 *.jsonl 하나가 세션 하나다. 두 기간 중 이른 시작일 0시(지역)보다 오래 손대지 않은 파일은 읽지 않는다(그 시각을
# 못 만들면 모두 읽는다). 날짜는 이 기계의 지역 오프셋(date +%z)으로 옮긴다.
# 호스트 설정 파일(SCV_HOST_PROFILE — 래퍼 설치본에는 있다)에서 선택 창 이름 · 자동 입력 모양을 읽는다. 그 파일이 없으면 확인 창과
# 자동 알림을 가를 수 없어 숫자가 틀리므로 멈춘다.
# 출력은 숫자 · 날짜뿐 — 대화 내용 · 경로 · 세션 이름 · 메일 주소는 내지 않는다(공개 저장소에 붙여도 되게). 오류 메시지도 경로를
# 담지 않는다.
# 종료 코드: 0 보고함 · 1 jq · 호스트 설정 · 기록 폴더가 없음 · 2 사용법 오류.
set -u
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/show-real.sh
source "$SCRIPT_DIR/lib/show-real.sh"
# shellcheck source=lib/model-prompting.sh
source "$SCRIPT_DIR/lib/model-prompting.sh"
# shellcheck source=lib/choices.sh
source "$SCRIPT_DIR/lib/choices.sh"
# shellcheck source=lib/host-profile.sh
source "$SCRIPT_DIR/lib/host-profile.sh" 2>/dev/null || true
# shellcheck source=lib/settings.sh
source "$SCRIPT_DIR/lib/settings.sh" 2>/dev/null || true

usage() {
  [[ -n "${1:-}" ]] && echo "show-real-report: $1" >&2
  echo "usage: show-real-report.sh --before <YYYY-MM-DD..YYYY-MM-DD> --after <YYYY-MM-DD..YYYY-MM-DD> [--dir <folder>]..." >&2
  exit 2
}

BEFORE=""; AFTER=""; DIRS_IN=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --before) [[ $# -ge 2 ]] || usage; BEFORE="$2"; shift 2 ;;
    --before=*) BEFORE="${1#--before=}"; shift ;;
    --after) [[ $# -ge 2 ]] || usage; AFTER="$2"; shift 2 ;;
    --after=*) AFTER="${1#--after=}"; shift ;;
    --dir) [[ $# -ge 2 ]] || usage; DIRS_IN+=("$2"); shift 2 ;;
    --dir=*) DIRS_IN+=("${1#--dir=}"); shift ;;
    -h|--help) awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;;
    *) usage "unknown argument" ;;
  esac
done
BR="$(scv_show_real_range "$BEFORE")"; AR="$(scv_show_real_range "$AFTER")"
[[ -n "$BR" && -n "$AR" ]] || usage "each period must be YYYY-MM-DD..YYYY-MM-DD with real dates, start no later than end"
(( 10#${BR##* } < 10#${AR%% *} )) || usage "the before period must end before the after period starts"
command -v jq >/dev/null 2>&1 || { echo "show-real-report: jq is required" >&2; exit 1; }
[[ -f "${SCV_HOST_PROFILE:-}" ]] || {
  echo "show-real-report: host profile not found — choice windows and automatic inputs cannot be told apart, so the numbers would be wrong. Run the installed plugin's copy of this script, or set SCV_HOST_PROFILE to the host profile file." >&2
  exit 1
}

# ---------------------------------------------------------------- 입구: 기록 폴더 · 파일
DIRS=()
_add_dir() {  # <폴더> — 실제 경로로 바꿔 한 번만 넣는다
  local d x
  d="$(cd "$1" 2>/dev/null && pwd -P)" || return 1
  for x in ${DIRS[@]+"${DIRS[@]}"}; do [[ "$x" == "$d" ]] && return 0; done
  DIRS+=("$d")
}
if [[ ${#DIRS_IN[@]} -gt 0 ]]; then
  _i=0
  for _d in "${DIRS_IN[@]}"; do
    _i=$((_i + 1))
    [[ -d "$_d" ]] && _add_dir "$_d" || { echo "show-real-report: --dir #$_i is not a readable folder" >&2; exit 1; }
  done
else
  for _t in "${SCV_JOURNAL_DIR:-scv/journal}"/.help-turns/*/.help-transcript; do
    [[ -f "$_t" && ! -L "$_t" ]] || continue
    _p="$(head -n 1 "$_t" 2>/dev/null)"; _d="${_p%/*}"
    [[ -n "$_p" && "$_d" != "$_p" && -d "$_d" ]] && _add_dir "$_d"
  done
fi
[[ ${#DIRS[@]} -gt 0 ]] || { echo "show-real-report: no session record folder found — pass --dir <folder>" >&2; exit 1; }

_start="${BR%% *}"
REF="$(mktemp "${TMPDIR:-/tmp}/scv-show-real.XXXXXX" 2>/dev/null)" || REF=""
[[ -n "$REF" ]] && trap 'rm -f "$REF"' EXIT
# 시작일 0시가 없는 날(일광 절약 시간)이거나 touch 가 날짜를 거절하면 거르지 않고 모두 읽는다 — 거른 결과가 0 이 되지 않게.
if [[ -n "$REF" ]] && ! touch -t "${_start}0000" "$REF" 2>/dev/null; then rm -f "$REF"; REF=""; fi
OFF="$(scv_show_real_offset "$(date +%z 2>/dev/null)")"

TOOL="${SCV_CHOICE_TOOL:-}"; TAGS="${SCV_AUTO_PROMPT_TAGS:-}"; PFX="${SCV_AUTO_PROMPT_PREFIX:-}"; SFX="${SCV_AUTO_PROMPT_SUFFIX:-}"
ROWS=""; NF=0; NU=0; _i=0
for _d in "${DIRS[@]}"; do
  _i=$((_i + 1))
  for _f in "$_d"/*.jsonl; do
    [[ -f "$_f" && ! -L "$_f" ]] || continue
    [[ -z "$REF" || "$_f" -nt "$REF" ]] || continue
    [[ -r "$_f" ]] || { NU=$((NU + 1)); continue; }
    _e="$(scv_show_real_entries "$TOOL" < "$_f" 2>/dev/null)"
    if [[ -z "$_e" ]]; then [[ -s "$_f" ]] && NU=$((NU + 1)); continue; fi
    _s="${_f##*/}"; _s="$_i/${_s%.jsonl}"   # 폴더마다 따로 — 같은 이름 파일이 한 세션으로 섞이지 않게(출력에는 나오지 않는다)
    ROWS+="$(scv_show_real_classify "$(scv_show_real_split "$_s" "$_e" "$TAGS" "$PFX" "$SFX")")"$'\n'
    NF=$((NF + 1))
  done
done

# ---------------------------------------------------------------- 출구: 표
_lang=""; declare -F settings_get >/dev/null 2>&1 && _lang="$(settings_get SCV_LANG 2>/dev/null || true)"
scv_show_real_render "$(scv_show_real_count "$ROWS" "$OFF" "$BR" "$AR")" "$_lang" "$BEFORE" "$AFTER" "$NF" "$NU"
exit 0
