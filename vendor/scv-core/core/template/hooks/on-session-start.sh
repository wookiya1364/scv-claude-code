#!/usr/bin/env bash
# on-session-start.sh — host hook template (SCV Core, v0.47.0+).
#
# Purpose: right after the context was reset — cleared, compacted, or resumed —
# hand the model back what this project was in the middle of: active plans,
# recent decisions, and the active conversation. Everything printed here is
# ASSEMBLED from files that are already written (promote/, INDEX.tsv,
# conversations/); this hook writes nothing anywhere.
#
# Contract (see docs/wrapper-integration.md §6 "Hook seam" in scv-core):
#   - The host's session-start event pipes ONE JSON object to stdin. When it
#     carries a `source` string (what reset the context), the header quotes it;
#     otherwise the header is generic. Nothing else is read from stdin.
#   - Registration is WRAPPER-OWNED. The wrapper decides WHICH session starts
#     invoke this template — the plan registers it for clear / compact / resume
#     and NOT for a fresh session start, because the first prompt's preflight
#     already carries the project state there.
#   - The wrapper should export SCV_CORE_ROOT (the materialized core/ dir);
#     without it, the template falls back to its in-payload location.
#   - stdout of this event reaches the model's context (the same channel as
#     on-user-prompt.sh). Switch: scv/scv_settings.json SCV_RESUME_RECAP —
#     absent / on / anything else = on; only off (any case) = off.
#
# NON-BLOCKING GUARANTEE: this hook never fails the session. Invalid JSON,
# missing jq/python3, missing recap script, missing conversations/, or an
# un-hydrated project → exit 0. Off → exit 0 with an empty stdout.
set -u

# Un-hydrated / non-SCV project → nothing to recap.
[[ -d scv ]] || exit 0

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" 2>/dev/null && pwd )" || exit 0
CORE_HOME="${SCV_CORE_ROOT:-$SCRIPT_DIR/../..}"

# 값은 settings 라이브러리로 읽는다 — 설정을 읽는 입구는 하나다. 라이브러리를
# 못 찾으면 기본값(on)으로 간다: 이 훅은 어떤 경우에도 세션을 막지 않는다.
_scv_settings_lib="$CORE_HOME/scripts/lib/settings.sh"
if [[ -f "$_scv_settings_lib" ]]; then
  # shellcheck disable=SC1090
  source "$_scv_settings_lib" 2>/dev/null || true
fi
_scv_read() {  # <KEY> — 라이브러리가 없으면 빈값(=기본값).
  declare -F settings_get >/dev/null 2>&1 || return 0
  settings_get "$1" 2>/dev/null || true
}

# 순수부 — 없으면 아무 것도 하지 않는다. 문자열부 없이 블록을 손으로 찍지 않는다.
# v0.49.0+ — 컨텍스트가 비워졌다(압축·지우기·재개): 다음 help 호출이 규약 전체를 다시 읽도록
# 표식을 되돌린다. 되찾기(recap) 스위치와 무관하게, 어떤 실패도 exit 0 로.
if [[ -f "$CORE_HOME/scripts/help-state.sh" ]]; then
  bash "$CORE_HOME/scripts/help-state.sh" reset >/dev/null 2>&1 || true
fi
_scv_resume_lib="$CORE_HOME/scripts/lib/resume-recap.sh"
[[ -f "$_scv_resume_lib" ]] || exit 0
# shellcheck disable=SC1090
source "$_scv_resume_lib" 2>/dev/null || exit 0
declare -F scv_resume_switch >/dev/null 2>&1 || exit 0

# 스위치 — off 면 여기서 끝. 바이트 하나도 내지 않는다.
[[ "$(scv_resume_switch "$(_scv_read SCV_RESUME_RECAP)")" == "on" ]] || exit 0

# 표준입력은 여기서 한 번만 읽는다. 무엇이 컨텍스트를 비웠는지(source)만 본다.
INPUT="$(cat 2>/dev/null || true)"
SOURCE=""
if [[ -n "$INPUT" ]]; then
  if command -v jq >/dev/null 2>&1; then
    SOURCE="$(printf '%s' "$INPUT" | jq -r 'try (.source // empty)' 2>/dev/null || true)"
  elif command -v python3 >/dev/null 2>&1; then
    SOURCE="$(printf '%s' "$INPUT" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    s = d.get("source", "")
    sys.stdout.write(s if isinstance(s, str) else "")
except Exception:
    pass' 2>/dev/null || true)"
  fi
fi

# ---------- 1. 머리말 --------------------------------------------------------
scv_resume_header "$SOURCE"
printf '\n'

# ---------- 2. 되찾기 — 기존 조립기 그대로 ---------------------------------------
# recap.sh 는 진행 중 계획(제목·상태), 최근 결정 5건(색인 줄 + 펼치는 명령), 막힌 것,
# 최근 계획의 미결 사항을 조립한다. 아무 것도 쓰지 않는다. 없거나 실패하면 건너뛴다.
# 폴더는 scv 로 고정 — 이 훅의 가드(`[[ -d scv ]]`)와 설정 파일 위치가 그렇고, 기존 두
# 훅 템플릿도 같다. 여기만 SCV_DIR 을 따르면 스위치는 한 폴더에서 읽고 내용은 다른
# 폴더에서 싣는 어긋남이 생긴다 (적대 검증에서 재현).
_scv_recap="$CORE_HOME/scripts/recap.sh"
if [[ -f "$_scv_recap" ]]; then
  SCV_DIR=scv bash "$_scv_recap" 2>/dev/null || true
  printf '\n'
fi

# ---------- 3. 활성 대화 — 가장 최근 것 하나는 전문, 나머지는 경로만 ------------------
# 최상위 scv/conversations/*.md 만 본다 — archive/ 는 끝난 대화다. 심볼릭 링크는 따라가지
# 않는다 (저장소 밖 파일을 실을 수 있다 — 설정 파일 읽기와 같은 규칙). 탭·개행이 든
# 파일명은 건너뛴다 — 아래 줄 목록의 구분자라서.
# 전문은 가림 필터를 거쳐서만 나간다. 필터가 없으면 경로만 싣고 본문은 싣지 않는다.
# 파일마다 프로세스를 띄우지 않는다 — status 는 awk 한 번, mtime 은 stat 한 번으로
# 전부 읽는다 (파일 3천 개에서 21초 → 래퍼 제한 30초에 닿았다).
_scv_conv_dir="scv/conversations"
_scv_redact="$CORE_HOME/scripts/journal-append.sh"
if [[ -d "$_scv_conv_dir" ]]; then
  _scv_files=()
  for _f in "$_scv_conv_dir"/*.md; do
    [[ -f "$_f" && ! -L "$_f" ]] || continue
    [[ "$_f" == *$'\t'* || "$_f" == *$'\n'* ]] && continue
    _scv_files+=("$_f")
  done
  _scv_lines=""
  if (( ${#_scv_files[@]} > 0 )); then
    # status: frontmatter(첫 줄 --- 부터 닫는 --- 까지, 60줄 상한) 안의 status 만.
    # CRLF·따옴표·뒤 공백·주석·BOM·대소문자를 관대하게 — 사람이 손으로 쓴 파일이다.
    # BOM 은 바이트로 벗긴다: LC_ALL=C 에서 8진 이스케이프는 gawk·맥 awk 둘 다 같고, \x 16진은
    # 맥 awk(20200816)가 모른다 — 그 차이가 status 를 통째로 놓치게 했다.
    _scv_status="$(LC_ALL=C awk '
      FNR == 1 { st = ""; sub(/^\357\273\277/, ""); sub(/\r$/, ""); if ($0 != "---") nextfile; next }
      FNR > 60 { print FILENAME "\t"; nextfile }
      /^---[[:space:]]*\r?$/ { print FILENAME "\t" st; nextfile }
      /^status:/ { v = $0; sub(/^status:[[:space:]]*/, "", v); sub(/[[:space:]]*#.*$/, "", v)
                   gsub(/["\047\r]/, "", v); sub(/[[:space:]]+$/, "", v); st = tolower(v) }
    ' "${_scv_files[@]}" 2>/dev/null || true)"
    # mtime: GNU stat → BSD stat → 전부 0 (그래도 멈추지 않는다). 다음 폴백은 앞의 출력이
    # 비었을 때만 — 출력을 내고도 실패로 끝난 stat 뒤에 폴백까지 더하면 줄이 겹친다.
    _scv_raw_m="$(stat -c '%Y %n' "${_scv_files[@]}" 2>/dev/null)"
    [[ -n "$_scv_raw_m" ]] || _scv_raw_m="$(stat -f '%m %N' "${_scv_files[@]}" 2>/dev/null)"
    [[ -n "$_scv_raw_m" ]] || _scv_raw_m="$(printf '0 %s\n' "${_scv_files[@]}")"
    _scv_mtimes="$(printf '%s\n' "$_scv_raw_m" | awk '{ m = $1; sub(/^[^ ]+ /, ""); print $0 "\t" m }')"
    # 합치기: 경로<TAB>status<TAB>mtime
    _scv_lines="$(awk -F'\t' 'NR == FNR { st[$1] = $2; next } { print $1 "\t" st[$1] "\t" $2 }' \
                   <(printf '%s\n' "$_scv_status") <(printf '%s\n' "$_scv_mtimes") 2>/dev/null || true)"
  fi
  _scv_pick="$(scv_resume_pick_active "$_scv_lines")"
  # 고른 경로가 정말 그 폴더의 일반 파일인지 한 번 더 — 줄 목록이 깨졌어도 엉뚱한
  # 파일을 싣지 않는다.
  if [[ -n "$_scv_pick" && -f "$_scv_pick" && ! -L "$_scv_pick" && "$_scv_pick" == "$_scv_conv_dir"/*.md ]]; then
    _scv_others="$(scv_resume_other_active "$_scv_lines" "$_scv_pick")"
    printf '%s\n' "[SCV resume] active conversation — ${_scv_pick} (most recent; its full text follows)"
    if [[ -n "$_scv_others" ]]; then
      printf '%s\n' "[SCV resume] other active conversations (path only):"
      printf '%s\n' "$_scv_others" | sed 's/^/  · /'
    fi
    if [[ -f "$_scv_redact" ]]; then
      bash "$_scv_redact" --redact-only < "$_scv_pick" 2>/dev/null || true
      printf '\n'
    fi
  fi
fi

exit 0
