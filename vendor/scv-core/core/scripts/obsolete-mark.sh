#!/usr/bin/env bash
# obsolete-mark.sh — 보관된 계획 하나를 폐기로 표시하고, 보관 목록(INDEX.yaml)을 바로 다시 만든다.
#
#   obsolete-mark.sh <폐기할 계획> <대체한 계획 또는 이유 이름> [<날짜 YYYY-MM-DD>]
#   ARCHIVE_DIR=<dir> obsolete-mark.sh …   # 이미 해석된 보관 폴더를 그대로 쓴다(모노레포 · 시험)
#
# PLAN.md 앞머리 세 칸(status · obsoleted_at · obsoleted_by)만 바꾼다 — 판단은 lib/obsolete.sh 의 순수함수.
# 이미 obsolete 면 파일을 다시 쓰지 않는다. TESTS.md · ARCHIVED_AT.md 는 건드리지 않는다.
# work 9c(대체 선언)와 regression(분류)의 폐기 표시가 이것을 부른다.
#
# Output: "MARKED: <slug> (obsoleted_by: <by>)" 또는 "ALREADY: <slug>", 그다음 archive-index.sh 의 "WROTE: …".
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/obsolete.sh
source "$SCRIPT_DIR/lib/obsolete.sh"
# shellcheck source=lib/scvroot.sh
source "$SCRIPT_DIR/lib/scvroot.sh"

SLUG="${1:-}"; BY="${2:-}"; DAY="${3:-$(date +%Y-%m-%d)}"
[[ -n "$SLUG" && -n "$BY" ]] || { echo "usage: obsolete-mark.sh <slug> <obsoleted_by> [<YYYY-MM-DD>]" >&2; exit 2; }
[[ -n "${ARCHIVE_DIR:-}" ]] || scv_init_paths ""
PLAN="$ARCHIVE_DIR/$SLUG/PLAN.md"
[[ -f "$PLAN" ]] || { echo "✖ not an archived plan: $PLAN" >&2; exit 1; }

before="$(cat "$PLAN"; printf x)"; before="${before%x}"
after="$(scv_obsolete_frontmatter "$before" "$DAY" "$BY"; printf x)"; after="${after%x}"   # 끝 줄바꿈까지 그대로 견준다
if [[ "$after" == "$before" ]]; then
  echo "ALREADY: $SLUG"
else
  printf '%s' "$after" > "$PLAN"
  echo "MARKED: $SLUG (obsoleted_by: $BY)"
fi
ARCHIVE_DIR="$ARCHIVE_DIR" bash "$SCRIPT_DIR/archive-index.sh"
