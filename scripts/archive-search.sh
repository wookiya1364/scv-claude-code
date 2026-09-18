#!/usr/bin/env bash
# archive-search.sh — 지난 작업 찾기의 효과부 (v0.53.0+).
#
#   archive-search.sh <낱말>...            맞는 대목을 출처와 함께 낸다
#   archive-search.sh --limit <n> <낱말>... 보여줄 출처 수 (기본 5)
#
# 읽기만 한다. 어떤 파일도 만들거나 고치지 않는다. 설치할 것을 늘리지 않는다 — grep 과 awk 뿐.
#
# 훑는 곳: 보관된 계획서·검사·구조·보관 기록, 소비된 원자료, 대화(보관 하위 폴더 포함), 결정 기록.
# 생성물(기획서 HTML)은 훑지 않는다 — 위 문서들로 만들어진 것이라 같은 내용을 두 번 세게 된다.
#
# 훑기는 한 번에 끝낸다. 줄마다 셸에서 다시 비교하면 백 배 느려진다(실측 26ms 대 3,729ms).
set -uo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/lib/archive-search.sh"
# 경로 초기화 helper 는 부르지 않는다 — 그것은 자동 동기화를 함께 부르고, 이 명령은
# 읽기만 해야 한다(안전장치). 필요한 것은 scv 폴더 위치 하나뿐이라 직접 찾는다.
if [[ -z "${SCV_DIR:-}" ]]; then
  _d="$PWD"
  while [[ "$_d" != "/" ]]; do
    [[ -d "$_d/scv/archive" || -d "$_d/scv/promote" ]] && { SCV_DIR="${_d}/scv"; break; }
    _d="$(dirname "$_d")"
  done
  SCV_DIR="${SCV_DIR:-scv}"
  unset _d
fi
US=$'\x1f'
LIMIT=5
MAX_EXCERPT="${SCV_SEARCH_EXCERPT:-100}"

TERMS_RAW=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit) LIMIT="${2:-5}"; shift 2 ;;
    -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
    *) TERMS_RAW="${TERMS_RAW:+$TERMS_RAW }$1"; shift ;;
  esac
done
[[ "$LIMIT" =~ ^[0-9]+$ ]] || LIMIT=5

TERMS="$(scv_as_parse_terms "$TERMS_RAW")"
if [[ -z "${TERMS//[[:space:]]/}" ]]; then
  echo "쓰는 법: archive-search.sh [--limit <n>] <낱말>..." >&2
  echo "  예: archive-search.sh 회귀 느림 관문" >&2
  exit 0
fi
NTERMS="$(printf '%s\n' "$TERMS" | awk 'NF>0' | wc -l | tr -d '[:space:]')"

# 훑을 파일 목록. 없는 곳은 조용히 빠진다.
files=()
while IFS= read -r f; do [[ -f "$f" ]] && files+=("$f"); done < <(
  printf '%s\n' \
    "$SCV_DIR"/archive/*/PLAN.md "$SCV_DIR"/archive/*/TESTS.md \
    "$SCV_DIR"/archive/*/FEATURE_ARCHITECTURE.md "$SCV_DIR"/archive/*/ARCHIVED_AT.md \
    "$SCV_DIR"/raw/stale/*.md \
    "$SCV_DIR"/conversations/*.md "$SCV_DIR"/conversations/archive/*.md \
    "$SCV_DIR"/DECISIONS.md 2>/dev/null
)
if (( ${#files[@]} == 0 )); then
  echo "ARCHIVE_SEARCH: 0"
  echo "아직 보관된 기록이 없습니다. 계획 세우기로 첫 계획을 만들어 보세요."
  exit 0
fi

# 아무 낱말이라도 걸리면 후보 — 첫 낱말로만 훑으면 순서에 따라 답이 달라진다.
# 낱말을 정규식으로 해석하지 않도록 -F 로 고정한다.
# -H 는 빼면 안 된다: 파일이 하나뿐일 때 grep 은 파일 이름을 생략하고, 그러면 줄번호가
# 파일 이름 자리에 와서 한 건도 못 읽는다. 기록 파일이 하나뿐인 프로젝트가 그 경우다.
#
# 두 번 훑어 합친다. 있는 그대로 한 번, 대소문자를 무시하고 한 번. -i 하나에 기대면
# 여러 바이트 글자(한글 등)를 깨뜨리는 grep 에서 한 건도 못 찾는다 — 실제로 맥에서 그랬다.
# 둘 중 하나만 맞아도 잡히고, 겹치는 줄은 뒤에서 하나로 합쳐진다.
_pat="$(printf '%s\n' "$TERMS" | awk "$_SCV_AS_AWK_NONEMPTY")"
sweep="$( { printf '%s\n' "$_pat" | grep -H -n -F -f /dev/stdin -- "${files[@]}" 2>/dev/null
            printf '%s\n' "$_pat" | grep -H -n -i -F -f /dev/stdin -- "${files[@]}" 2>/dev/null
          } | sort -u || true )"
unset _pat
if [[ -z "$sweep" ]]; then
  scv_as_render "" 0 "$NTERMS" "$LIMIT" ""
  exit 0
fi

# 점수 매기기도 한 번에 끝낸다 — 줄마다 셸로 돌면 327줄에 11초가 걸린다(실측).
rows="$(scv_as_score_lines "$sweep" "$TERMS")"
total="$(printf '%s\n' "$rows" | awk 'NF>0' | wc -l | tr -d '[:space:]')"

rows="$(scv_as_drop_weak "$rows")"
rows="$(scv_as_group_best "$rows")"
first_term="$(printf '%s\n' "$TERMS" | awk 'NF>0 {print; exit}')"
scv_as_render "$rows" "$total" "$NTERMS" "$LIMIT" "$first_term"
