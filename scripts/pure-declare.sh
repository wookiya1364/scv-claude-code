#!/usr/bin/env bash
# pure-declare.sh — 모든 함수가 순수 · 부수효과를 선언했는지 본다 (0.81.0+, 계획 pure-declare-081, 계약 contracts/purity.md).
#
# 판정은 lib/pure-declare.sh 의 순수 함수가 하고, 여기는 파일 읽기 · 설정 · 기준선 쓰기만 한다.
#
# Usage:
#   pure-declare.sh gate --file PATH --after FILE [--before FILE]
#       파일 쓰기 검사(가드가 부른다). 편집 뒤 본문(--after)에서 선언 없는 함수가 편집 전(--before, 없으면 새 파일)보다
#       늘었으면 거절 이유 한 줄을 낸다. 판정하지 않는 언어 · 제외 폴더 · 시험 파일 · SCV_PURE_DECLARE=off 면 아무것도 안 낸다.
#   pure-declare.sh scan [--root DIR] [--project]
#       선언 없는 함수를 "경로<탭>이름" 줄로, 끝에 "UNDECLARED: N" 을 낸다. --project 는 저장소 추적 파일(언어 무관),
#       아니면 DIR 아래 *.sh(코어).
#   pure-declare.sh baseline (check|update) --baseline FILE [--root DIR] [--project]
#       check: 선언 없는 함수 수가 기준선보다 많으면 exit 1. update: 지금 수를 기준선으로 쓴다(늘리지는 않는다 — 처음이면 만든다).
#
# Exit: 0 통과 · 1 위반 · 2 사용법 오류

set -uo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/pure-declare.sh
source "$SCRIPT_DIR/lib/pure-declare.sh"
# shellcheck source=lib/settings.sh
source "$SCRIPT_DIR/lib/settings.sh" 2>/dev/null || true

# 판정하지 않는 자리 — 시험 · 의존성 · 생성물 · SCV 기록(목록 만들기와 같은 목록, SCV_CATALOG_EXCLUDE 로 바꾼다).
PD_EXCLUDE="${SCV_CATALOG_EXCLUDE:-tests test __tests__ spec node_modules vendor dist build target scv .git}"

# @effect pd_skip_path
# 이유: 설정 값(제외 폴더 목록)을 읽어 경로를 거른다 — 판정은 아니고 입구의 거름
pd_skip_path() {
  local f="/$1" seg
  for seg in $PD_EXCLUDE; do [[ "$f" == *"/$seg/"* ]] && return 0; done
  case "${f##*/}" in
    *.test.*|*.spec.*|*_test.*|test_*.py|*_test.go) return 0 ;;
  esac
  return 1
}

# 0.98.0+ — 사전이 원본인 프로젝트(scv/core/catalog/pure/SOURCE): 선언은 코드 주석이 아니라 사전(순수 항목 · effects.md)에
# 있다. PD_SRC_ROOT 가 그 저장소, PD_SRC_REL 이 판정하는 파일의 저장소 기준 경로다.
PD_SRC_ROOT=""; PD_SRC_REL=""

# @effect pd_catalog_names
# 이유: 사전 파일을 읽어 한 파일(저장소 기준 경로)에 선언된 함수 이름들을 낸다
pd_catalog_names() {  # <root> <rel>
  local cat="$1/scv/core/catalog/pure" f
  for f in "$cat"/*.md; do
    [[ -f "$f" ]] || continue
    case "$(basename "$f")" in INDEX.md|notes.md) continue ;; esac
    LC_ALL=C awk -v rel="$2" '/^### /{n=substr($0,5)} /^- 위치: /{v=$0; sub(/^- 위치: /,"",v); split(v,p," · "); if (p[1] == rel) print n}' "$f"
  done
}

# @effect pd_missing_in
# 이유: 파일을 읽어 그 파일의 선언 없는 함수 이름을 낸다
pd_missing_in() {  # <언어> <파일>
  local text; text="$(cat "$2" 2>/dev/null || true)"
  if [[ -n "$PD_SRC_ROOT" ]]; then
    scv_rc_allowed_out "$(scv_pd_functions "$1" "$text")" "$(pd_catalog_names "$PD_SRC_ROOT" "$PD_SRC_REL")"; return 0
  fi
  scv_rc_allowed_out "$(scv_pd_functions "$1" "$text")" "$(scv_pd_declared "$1" "$text")"
}

# @effect pd_files
# 이유: 저장소 파일 목록을 읽는다(git 또는 find)
pd_files() {  # <root> <project 0|1> → 절대 경로들
  local root="$1" f
  if [[ "$2" == 1 ]]; then
    git -C "$root" ls-files 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
      [[ -n "$(scv_pd_lang "$f" "$PD_RS")" ]] || continue
      pd_skip_path "$f" || printf '%s\n' "$root/$f"
    done
  else
    find "$root" -type f -name '*.sh' 2>/dev/null | LC_ALL=C sort | while IFS= read -r f; do
      pd_skip_path "${f#"$root"/}" || printf '%s\n' "$f"
    done
  fi
}

# @effect pd_scan
# 이유: 파일들을 읽어 선언 없는 함수를 세고 출력한다
pd_scan() {  # <root> <project 0|1>
  local root="$1" f n=0 name rel
  while IFS= read -r f; do
    rel="${f#"$root"/}"
    [[ -n "$PD_SRC_ROOT" ]] && PD_SRC_REL="$rel"
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      printf '%s\t%s\n' "$rel" "$name"; n=$((n + 1))
    done < <(pd_missing_in "$(scv_pd_lang "$f" "$PD_RS")" "$f")
  done < <(pd_files "$root" "$2")
  printf 'UNDECLARED: %s\n' "$n"
}

PD_RS=""
# @effect pd_source_mode
# 이유: 저장소에 사전 원본 표시가 있는지 본다 — 있으면 선언은 사전에서 읽고 러스트도 판정한다
pd_source_mode() {  # <저장소 안 아무 경로>
  local top; top="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" || return 1
  [[ -f "$top/scv/core/catalog/pure/SOURCE" ]] || return 1
  PD_SRC_ROOT="$top"; PD_RS=on
}

MODE="${1:-}"; shift || true
FILE=""; AFTER=""; BEFORE=""; ROOT="."; PROJECT=0; BASELINE=""; SUB=""
[[ "$MODE" == baseline ]] && { SUB="${1:-}"; shift || true; }
while [[ $# -gt 0 ]]; do
  case "$1" in
    --file) FILE="${2:-}"; shift 2 ;;
    --after) AFTER="${2:-}"; shift 2 ;;
    --before) BEFORE="${2:-}"; shift 2 ;;
    --root) ROOT="${2:-.}"; shift 2 ;;
    --project) PROJECT=1; shift ;;
    --baseline) BASELINE="${2:-}"; shift 2 ;;
    *) echo "pure-declare.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done

case "$MODE" in
  gate)
    [[ -n "$FILE" && -f "$AFTER" ]] || exit 0
    _sw="$(declare -F settings_get >/dev/null 2>&1 && settings_get SCV_PURE_DECLARE 2>/dev/null | tr -d '"[:space:]' | tr '[:upper:]' '[:lower:]')"
    [[ "$_sw" == off ]] && exit 0
    pd_source_mode "." && PD_SRC_REL="$FILE"
    _lang="$(scv_pd_lang "$FILE" "$PD_RS")"; [[ -n "$_lang" ]] || exit 0
    pd_skip_path "$FILE" && exit 0
    _after="$(pd_missing_in "$_lang" "$AFTER")"
    _before=""; [[ -n "$BEFORE" && -f "$BEFORE" ]] && _before="$(pd_missing_in "$_lang" "$BEFORE")"
    if [[ -n "$PD_SRC_ROOT" ]]; then
      _new="$(scv_pd_write_verdict "$_before" "$_after")"
      [[ -n "$_new" ]] || exit 0
      printf '[SCV 함수 선언] %s 에 사전에 없는 함수가 생긴다: %s — 이 프로젝트는 사전이 원본이다. scv/core/catalog/pure 의 알맞은 종류 파일에 항목(### 이름 · 역할 · 위치 · 예)을, 부수효과면 effects.md 에 이유를 먼저 적고 다시 써라(코드에는 주석 없이).\n' \
        "$FILE" "$(printf '%s' "$_new" | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
      exit 0
    fi
    _new="$(scv_pd_write_verdict "$_before" "$_after")"
    [[ -n "$_new" ]] || exit 0
    printf '[SCV 함수 선언] %s 에 선언 없는 함수가 생긴다: %s — 함수마다 바로 위 주석에 @pure(역할 · 종류 · 예) 또는 @effect(이유: 바깥을 바꾸는 이유 한 줄)를 달아 다시 써라(contracts/purity.md).\n' \
      "$FILE" "$(printf '%s' "$_new" | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
    ;;
  scan)
    ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || exit 2
    (( PROJECT )) && { ROOT="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null)" || exit 2; pd_source_mode "$ROOT" || true; }
    pd_scan "$ROOT" "$PROJECT"
    ;;
  baseline)
    [[ -n "$BASELINE" ]] || { echo "pure-declare.sh baseline: --baseline FILE" >&2; exit 2; }
    ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || exit 2
    (( PROJECT )) && { ROOT="$(git -C "$ROOT" rev-parse --show-toplevel 2>/dev/null)" || exit 2; pd_source_mode "$ROOT" || true; }
    _out="$(pd_scan "$ROOT" "$PROJECT")"
    _n="$(printf '%s\n' "$_out" | sed -n 's/^UNDECLARED: //p')"
    _base=""; [[ -f "$BASELINE" ]] && _base="$(head -1 "$BASELINE" | tr -cd '0-9')"
    if [[ "$SUB" == update ]]; then
      if [[ -z "$_base" || "$_n" -lt "$_base" ]]; then printf '%s\n' "$_n" > "$BASELINE"; fi
      echo "UNDECLARED: $_n (baseline ${_base:-none} → $(head -1 "$BASELINE"))"
    else
      if [[ -n "$_base" && "$_n" -gt "$_base" ]]; then
        echo "✖ 선언 없는 함수가 기준선보다 늘었다: $_n > $_base — 새 함수에 @pure 또는 @effect 를 달아라(contracts/purity.md)" >&2
        printf '%s\n' "$_out" | grep -v '^UNDECLARED' | tail -n "$((_n - _base))" >&2
        exit 1
      fi
      echo "UNDECLARED: $_n (baseline ${_base:-none})"
    fi
    ;;
  *) echo "usage: pure-declare.sh gate|scan|baseline (see header)" >&2; exit 2 ;;
esac
exit 0
