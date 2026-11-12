#!/usr/bin/env bash
# wrapup.sh — 계획 폴더의 마무리 보고(WRAPUP.md)가 다 채워졌는지 보고, 끝 답에 실을 글을 낸다.
#
#   wrapup.sh check <계획 폴더>   다 채웠으면 0, 빈 칸 · 모자란 칸 · 잘못된 건너뜀이 있으면 1 과 그 이름들
#   wrapup.sh show  <계획 폴더>   틀의 안내 글을 뺀 마무리 보고(묶음 제목과 칸). 파일이 없으면 아무것도 내지 않는다
#   wrapup.sh new   <계획 폴더> [--lang <언어>]   채울 자리만 있는 새 마무리 보고 파일을 쓴다(제목은 계획 문서에서). 이미 있으면 1
#
# 판단은 lib/wrapup.sh 의 순수함수가 하고 여기는 읽기와 출력만 한다. 보관 명령(work.sh --archive)이 옮기기 전에 check 를,
# 옮긴 뒤에 show 를 부른다. 마무리 보고 파일도 없고 계획 문서가 그 파일을 가리키지도 않으면 옛 계획이다 — 알림 한 줄, 종료 코드 0.
set -u
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/wrapup.sh
source "$SCRIPT_DIR/lib/wrapup.sh"

cmd="${1:-}"; dir="${2:-}"; lang=""
if [[ -z "$cmd" || -z "$dir" ]]; then
  echo "usage: wrapup.sh check|show|new <plan folder> [--lang <language>]" >&2
  exit 2
fi
shift 2
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lang) lang="${2:-}"; shift 2 || shift ;;
    --lang=*) lang="${1#--lang=}"; shift ;;
    *) echo "wrapup.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done
if [[ ! -d "$dir" ]]; then
  echo "wrapup.sh: no such plan folder: $dir" >&2
  exit 2
fi

has="no"; text=""; plan=""
if [[ -f "$dir/WRAPUP.md" ]]; then has="yes"; text="$(cat "$dir/WRAPUP.md")"; fi
if [[ -f "$dir/PLAN.md" ]]; then plan="$(cat "$dir/PLAN.md")"; fi
fields="$(scv_wu_fields "$text")"

case "$cmd" in
  check)
    verdict="$(scv_wu_verdict "$(scv_wu_empty "$fields")" "$(scv_wu_skip_bad "$fields")" "$has" "$(scv_wu_points "$plan")")"
    case "${verdict%%$'\n'*}" in
      pass)
        echo "WRAPUP: pass"
        exit 0 ;;
      legacy)
        echo "WRAPUP: legacy — 마무리 보고 없음(옛 계획). 그대로 보관한다"
        exit 0 ;;
      *)
        echo "WRAPUP: block — 마무리 보고를 다 채워야 보관된다: $dir/WRAPUP.md"
        printf '%s\n' "${verdict#*$'\n'}" | sed 's/^/  /'
        exit 1 ;;
    esac ;;
  show)
    [[ "$has" == "yes" ]] || exit 0
    scv_wu_digest "$fields"
    echo ""
    exit 0 ;;
  new)
    if [[ "$has" == "yes" ]]; then
      echo "WRAPUP_EXISTS: $dir/WRAPUP.md — left as it is" >&2
      exit 1
    fi
    title="$(printf '%s\n' "$plan" | sed -n 's/^title:[[:space:]]*//p' | head -1)"
    [[ -n "$lang" ]] || lang="$(printf '%s\n' "$plan" | sed -n 's/^lang:[[:space:]]*//p' | sed 's/[[:space:]]*#.*$//' | head -1)"
    printf '%s\n\n%s\n' "$(scv_wu_head "$lang" "$title")" "$(scv_wu_skeleton "$(scv_wu_names "$lang")")" > "$dir/WRAPUP.md"
    echo "WROTE: $dir/WRAPUP.md"
    exit 0 ;;
  *)
    echo "wrapup.sh: unknown command: $cmd (check | show | new)" >&2
    exit 2 ;;
esac
