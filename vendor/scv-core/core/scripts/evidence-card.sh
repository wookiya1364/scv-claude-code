#!/usr/bin/env bash
# evidence-card.sh — 숫자 결과를 막대 그림(SVG) 파일로 쓴다. 단계가 끝났다는 증거로 붙일, 눈에 보이는 그림을 토큰 없이 만든다.
#
#   evidence-card.sh card --out <프로젝트 안 경로.svg> --title "<제목>" "<이름>=<값>" ["<이름>=<값>" …]
#
# 그림 글은 lib/evidence-card.sh 의 순수 함수가 만들고, 여기는 인자를 읽고 파일을 쓰기만 한다.
# 쓰는 자리는 지금 폴더(프로젝트) 안이어야 한다 — 절대 경로 · 위로 올라가는 경로 · 심볼릭 링크를 지나는 경로에는 쓰지 않는다.
# Exit: 0 씀 · 2 잘못된 인자나 쓸 수 없는 자리
set -uo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/evidence-card.sh
source "$SCRIPT_DIR/lib/evidence-card.sh"

# @effect usage
# 이유: 사용법을 표준 오류에 쓰고 끝낸다
usage() { echo 'usage: evidence-card.sh card --out <path.svg> --title "<제목>" "<이름>=<값>" …' >&2; exit 2; }
[[ "${1:-}" == card ]] || usage
shift
out=""; title=""; rows=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) out="${2:-}"; shift 2 || usage ;;
    --title) title="${2:-}"; shift 2 || usage ;;
    *) rows+="${rows:+$'\n'}$1"; shift ;;
  esac
done
[[ -n "$out" && -n "$rows" ]] || usage
case "$out" in /*|../*|*/../*|*/..|..) echo "✖ 프로젝트 안의 경로만 쓴다: $out" >&2; exit 2 ;; esac
[[ "$out" == *.svg ]] || { echo "✖ 그림 파일 이름은 .svg 로 끝나야 한다: $out" >&2; exit 2; }
p="$out"
while [[ "$p" == */* ]]; do
  p="${p%/*}"
  [[ -L "$p" ]] && { echo "✖ 심볼릭 링크를 지나는 자리에는 쓰지 않는다: $p" >&2; exit 2; }
done
[[ -L "$out" ]] && { echo "✖ 심볼릭 링크에는 쓰지 않는다: $out" >&2; exit 2; }
svg="$(scv_card_svg "$title" "$(scv_card_rows "$rows" 300)")"
[[ -n "$svg" ]] || { echo "✖ 그릴 값이 없다 — \"이름=숫자\" 꼴로 준다" >&2; exit 2; }
[[ "$out" == */* ]] && { mkdir -p "${out%/*}" || exit 2; }
printf '%s\n' "$svg" > "$out" || exit 2
echo "CARD: $out"
