#!/usr/bin/env bash
# decisions-append.sh — 결정 하나를 scv/DECISIONS.md 에 쌓고, 그 위치를 색인에 남긴다.
#
# 왜 스크립트인가: 결정 로그는 세 지점에서 **자동으로** 쌓인다 — 계획 승인,
# 보관, 폐기 판정. 프로토콜이 손으로 쓰면 형식이 흔들리고 색인이 안 남는다.
# 한 곳을 거치게 하면 형식도 위치 기록도 공짜다. 사람이 판단할 것이 없다.
#
# 색인이 있으면 결정 하나를 읽는 데 로그 전체를 읽지 않는다. 이 저장소의
# DECISIONS 는 이미 668줄이고 계속 자란다.
#
# Usage:
#   decisions-append.sh --title T --verdict V --why W [옵션]
#
#   --title T      제목 (필수)
#   --verdict V    adopted | archived | obsolete | needed | maybe | not-needed | lesson
#   --why W        1–3줄 근거 (필수)
#   --key NAME     나중에 부를 이름 (기본: 제목에서 만든 슬러그)
#   --discarded X  버린 대안
#   --path-delta X 계획 대비 실제로 간 경로 (보관 엔트리에서는 필수)
#   --refs X       관련 계획/PR/티켓
#   --conversation X  대화나 저널 링크
#   --author NAME  기본: git config user.name
#   --dry-run      쓰지 않고 만들어질 엔트리를 찍는다
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/author.sh
source "$SCRIPT_DIR/lib/author.sh"
# shellcheck source=lib/record-index.sh
source "$SCRIPT_DIR/lib/record-index.sh"

TITLE=""; VERDICT=""; WHY=""; KEY=""
DISCARDED=""; PATH_DELTA=""; REFS=""; CONVERSATION=""; AUTHOR=""; DRY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)        TITLE="${2:-}"; shift 2 ;;
    --verdict)      VERDICT="${2:-}"; shift 2 ;;
    --why)          WHY="${2:-}"; shift 2 ;;
    --key)          KEY="${2:-}"; shift 2 ;;
    --discarded)    DISCARDED="${2:-}"; shift 2 ;;
    --path-delta)   PATH_DELTA="${2:-}"; shift 2 ;;
    --refs)         REFS="${2:-}"; shift 2 ;;
    --conversation) CONVERSATION="${2:-}"; shift 2 ;;
    --author)       AUTHOR="${2:-}"; shift 2 ;;
    --dry-run)      DRY=1; shift ;;
    -h|--help) sed -n '2,25p' "$0"; exit 0 ;;
    *) echo "decisions-append.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$TITLE"   ]] || { echo "decisions-append.sh: --title is required" >&2; exit 2; }
[[ -n "$WHY"     ]] || { echo "decisions-append.sh: --why is required" >&2; exit 2; }
[[ -n "$VERDICT" ]] || { echo "decisions-append.sh: --verdict is required" >&2; exit 2; }
case "$VERDICT" in
  adopted|archived|obsolete|needed|maybe|not-needed|lesson) : ;;
  *) echo "decisions-append.sh: unknown verdict [$VERDICT] — see scv/DECISIONS.md 스키마" >&2; exit 2 ;;
esac

# @pure
# decisions_slug <제목> — 제목에서 부를 이름을 만든다. 문자열만 다룬다.
decisions_slug() {
  local t="${1:-}"
  t="${t,,}"
  t="${t//[^a-z0-9가-힣]/-}"
  while [[ "$t" == *--* ]]; do t="${t//--/-}"; done
  t="${t#-}"; t="${t%-}"
  printf '%s\n' "${t:0:48}"
}
[[ -n "$KEY" ]] || KEY="$(decisions_slug "$TITLE")"
[[ -n "$KEY" ]] || KEY="decision"

[[ -n "$AUTHOR" ]] || AUTHOR="$(scv_author)"

SCV_DIR_RESOLVED="${SCV_DIR:-scv}"
FILE="$SCV_DIR_RESOLVED/DECISIONS.md"
INDEX_FILE="$SCV_DIR_RESOLVED/INDEX.tsv"

# 엔트리를 만든다. 값 안의 줄바꿈은 그대로 둔다 — 결정 로그는 여러 줄을 허용한다.
STAMP="$(date '+%Y-%m-%d %H:%M')"
ENTRY="$(
  printf '\n## [%s] %s — %s\n\n' "$STAMP" "$AUTHOR" "$TITLE"
  printf -- '- verdict: %s\n' "$VERDICT"
  printf -- '- why: %s\n' "$WHY"
  [[ -n "$DISCARDED"    ]] && printf -- '- discarded alternatives: %s\n' "$DISCARDED"
  [[ -n "$PATH_DELTA"   ]] && printf -- '- path delta: %s\n' "$PATH_DELTA"
  [[ -n "$REFS"         ]] && printf -- '- refs: %s\n' "$REFS"
  [[ -n "$CONVERSATION" ]] && printf -- '- conversation: %s\n' "$CONVERSATION"
  true
)"

if [[ $DRY -eq 1 ]]; then
  printf '%s\n' "$ENTRY"
  echo "(dry-run — nothing written; key would be: $KEY)"
  exit 0
fi

if [[ ! -f "$FILE" ]]; then
  echo "decisions-append.sh: $FILE not found — hydrate the project first." >&2
  exit 1
fi
[[ -L "$FILE" ]] && { echo "decisions-append.sh: $FILE is a symlink — refusing to write through it." >&2; exit 1; }

# 쓰기 직전 크기가 이 엔트리의 시작 위치다.
OFFSET_BEFORE="$(wc -c < "$FILE" 2>/dev/null | tr -d '[:space:]')"
[[ "$OFFSET_BEFORE" =~ ^[0-9]+$ ]] || OFFSET_BEFORE=0

printf '%s\n' "$ENTRY" >> "$FILE" || {
  echo "decisions-append.sh: write failed — $FILE unchanged" >&2; exit 1; }

echo "DECISION: $FILE ← [$VERDICT] $TITLE"

# 색인은 편의지 필수가 아니다 — 여기서 무엇이 잘못돼도 결정은 이미 쌓였다.
OFFSET_AFTER="$(wc -c < "$FILE" 2>/dev/null | tr -d '[:space:]')"
if [[ "$OFFSET_AFTER" =~ ^[0-9]+$ ]] && (( OFFSET_AFTER > OFFSET_BEFORE )); then
  LENGTH=$(( OFFSET_AFTER - OFFSET_BEFORE ))
  SUMMARY="[$VERDICT] $TITLE"
  RECORD="$(record_index_entry decision "$KEY" "$FILE" "$OFFSET_BEFORE" "$LENGTH" "$STAMP" "$SUMMARY")"
  if [[ -n "$RECORD" && ! -L "$INDEX_FILE" ]]; then
    printf '%s\n' "$RECORD" >> "$INDEX_FILE" 2>/dev/null || true
    echo "INDEXED: key=$KEY at ${OFFSET_BEFORE}+${LENGTH}"
  fi
fi
