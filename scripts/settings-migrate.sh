#!/usr/bin/env bash
# settings-migrate.sh — .env 의 SCV 설정을 scv/scv_settings.json 두 벌로 옮긴다.
#
# 한 번만 돌리면 되고, 두 번 돌려도 같은 결과다.
#
# 원본 .env 는 **지우지 않는다.** 프로젝트가 원래 쓰던 파일이라 SCV 와 무관한
# 값이 같이 들어 있을 수 있다. 옮기는 것은 SCV 가 아는 키뿐이고, 나머지 줄은
# 손대지 않는다.
#
# 비밀값(토큰·채널 ID)은 무시 목록에 드는 별도 파일로 간다. 일반 설정은 커밋되는
# 파일로 간다. 어느 쪽인지는 lib/settings.sh 의 목록이 정한다.
#
# Usage:
#   settings-migrate.sh [--project-dir DIR] [--dry-run]
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/settings.sh
source "$SCRIPT_DIR/lib/settings.sh"

PROJECT_DIR="."
DRY_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) PROJECT_DIR="${2:-.}"; shift 2 ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
    *) echo "✖ unknown argument: $1" >&2; exit 2 ;;
  esac
done

cd "$PROJECT_DIR" || { echo "✖ cannot enter $PROJECT_DIR" >&2; exit 1; }
[[ -d scv ]] || { echo "✖ no scv/ directory — hydrate the project first." >&2; exit 1; }
PLAIN="${SCV_SETTINGS_FILE:-scv/scv_settings.json}"
SECRET="${SCV_SETTINGS_SECRET_FILE:-scv/scv_settings.secret.json}"
# 0.34.0: 이 스크립트는 settings_ensure 의 별칭이다 — 액션 시작 때 자동으로 도는 것과
# 같은 일을 한다. .env 가 없어도 파일을 만들고(전체 키 + 기본값), 있으면 그 값을
# 옮기며, 두 번 돌려도 같다. 원본 .env 는 지우지 않는다.
if [[ $DRY_RUN -eq 1 ]]; then
  PN="$(printf '%s' "$(_settings_env_overlay "$SCV_PLAIN_KEYS" .env)" | grep -o '":"' | wc -l | tr -d ' ')"
  SN="$(printf '%s' "$(_settings_env_overlay "$SCV_SECRET_KEYS" .env)" | grep -o '":"' | wc -l | tr -d ' ')"
  echo "(dry-run — nothing written)"
  [[ -f "$PLAIN" ]]  && echo "  $PLAIN   exists — only missing keys would be added" || echo "  $PLAIN   ← every SCV key with defaults, $PN value(s) from .env"
  [[ -f "$SECRET" ]] && echo "  $SECRET  exists — untouched" || echo "  $SECRET  ← every secret key (empty), $SN value(s) from .env (only if git ignores it)"
  exit 0
fi
had_plain=0; [[ -f "$PLAIN" ]] && had_plain=1
settings_ensure . 2>/dev/null
if [[ $had_plain -eq 1 ]]; then
  echo "settings files already exist — nothing was changed except newly added keys, if any."
else
  PN="$(printf '%s' "$(_settings_env_overlay "$SCV_PLAIN_KEYS" .env)" | grep -o '":"' | wc -l | tr -d ' ')"
  echo "migrated:"
  echo "  $PLAIN   ← every SCV key with its default; $PN value(s) from .env   (committed)"
  if [[ -f "$SECRET" ]]; then echo "  $SECRET  ← every secret key; values from .env if any    (git-ignored)"
  else echo "  $SECRET  NOT created — git does not ignore it here; add 'scv/scv_settings.secret.json' to .gitignore and re-run" >&2; fi
  [[ -f .env ]] && echo "  .env was NOT touched — remove the SCV lines yourself once you are happy."
fi
