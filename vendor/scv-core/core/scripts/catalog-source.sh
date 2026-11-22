#!/usr/bin/env bash
# catalog-source.sh — 코드 주석 없이 순수 함수 사전이 원본(SCV_CATALOG_SOURCE)을 켜고 끈다 (0.98.0+, 계획 comments-to-catalog).
#
#   catalog-source.sh            설정 파일의 값을 뒤집는다(off → on, on → off)
#   catalog-source.sh on|off     그 값으로 정한다
#
# 켜기: 설정을 켜고, 아직 옮기지 않은 프로젝트면 그 자리에서 코드 주석을 사전으로 옮기고 지운다(comments-migrate.sh run).
# 끄기: 주석 막기(새 주석 거절 · 남은 주석 위반)만 푼다 — 이미 옮긴 사전은 원본(사전 폴더의 SOURCE) 그대로다. 옮긴 주석을
#       되돌리려면 git 으로(커밋 전이면 git checkout -- .).
# 출력: CATALOG_SOURCE: <전> -> <후> · MIGRATED: now|already|no · (옮겼으면) MIGRATE 줄 · ENV_VALUE: <값>(환경 변수가 있으면)
# Exit: 0 · 1 옮기기 멈춤 · 2 잘못된 인자
set -uo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# @pure cs_next
# 역할: 지금 값과 명령 인자로 바꿀 값을 고른다 — 인자가 on · off 면 그 값, 비었으면 뒤집기, 그 밖은 빈 값(잘못된 인자)
# 종류: 판정
# 예: off "" → "on"
# 예: on "" → "off"
# 예: off ON → "on"
# 예: on "maybe" → ""
cs_next() {
  local cur="${1:-off}" arg="${2:-}"
  arg="${arg//[[:space:]]/}"
  case "$arg" in
    "") [[ "$cur" == on ]] && printf 'off' || printf 'on' ;;
    [Oo][Nn]) printf 'on' ;;
    [Oo][Ff][Ff]) printf 'off' ;;
    *) return 0 ;;
  esac
}

ARG="${1:-}"
CUR="$(env -u SCV_CATALOG_SOURCE bash "$SCRIPT_DIR/settings-set.sh" --get SCV_CATALOG_SOURCE 2>/dev/null | tr -d '"[:space:]' | tr '[:upper:]' '[:lower:]')"
[[ "$CUR" == off ]] || CUR=on   # 기본 on — 키가 없으면 켬, 적힌 off 만 끔
NEXT="$(cs_next "$CUR" "$ARG")"
[[ -n "$NEXT" ]] || { echo "catalog-source.sh: 인자는 on 또는 off (없으면 뒤집기) — 받은 값: $ARG" >&2; exit 2; }
bash "$SCRIPT_DIR/settings-set.sh" "SCV_CATALOG_SOURCE=$NEXT" >/dev/null || { echo "catalog-source.sh: 설정 파일에 쓰지 못함" >&2; exit 1; }
printf 'CATALOG_SOURCE: %s -> %s\n' "$CUR" "$NEXT"
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
if [[ "$NEXT" == on ]]; then
  if [[ -f "$ROOT/scv/core/catalog/pure/SOURCE" ]]; then
    printf 'MIGRATED: already\n'
  else
    out="$(bash "$SCRIPT_DIR/comments-migrate.sh" run --root "$ROOT" 2>&1)" || { printf 'MIGRATED: no\n%s\n' "$(printf '%s' "$out" | tail -1)"; exit 1; }
    printf 'MIGRATED: now\n%s\n' "$(printf '%s\n' "$out" | grep '^MIGRATE' | tail -1)"
  fi
else
  if [[ -f "$ROOT/scv/core/catalog/pure/SOURCE" ]]; then printf 'MIGRATED: already\n'; else printf 'MIGRATED: no\n'; fi
fi
[[ -n "${SCV_CATALOG_SOURCE:-}" ]] && printf 'ENV_VALUE: %s\n' "$SCV_CATALOG_SOURCE"
exit 0
