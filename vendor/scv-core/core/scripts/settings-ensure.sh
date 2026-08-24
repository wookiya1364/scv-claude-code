#!/usr/bin/env bash
# settings-ensure.sh — 설정 파일이 항상 있게 한다 (v0.34.0+).
#
# 없으면 만든다: 공개 키 전부 = 기본값(+ _doc 설명), .env 에 값이 있으면 그 값.
# 있으면 없는 키만 더한다 — 사용자가 정한 값은 절대 바꾸지 않는다.
# 비밀 파일은 git 이 무시한다고 확인될 때만 만든다 (.gitignore 에 한 줄 더하고 확인).
#
# 액션이 시작될 때 자동으로 돌므로 손으로 부를 일은 드물다. 두 번 돌려도 같다.
#
# Usage:
#   settings-ensure.sh [--project-dir DIR]
set -uo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/settings.sh
source "$SCRIPT_DIR/lib/settings.sh"
PROJECT_DIR="."
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) PROJECT_DIR="${2:-.}"; shift 2 ;;
    -h|--help) sed -n '2,11p' "$0"; exit 0 ;;
    *) echo "settings-ensure.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done
[[ -d "$PROJECT_DIR/scv" ]] || { echo "settings-ensure.sh: no scv/ under $PROJECT_DIR — hydrate the project first." >&2; exit 1; }
settings_ensure "$PROJECT_DIR"
