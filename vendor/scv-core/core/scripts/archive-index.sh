#!/usr/bin/env bash
# archive-index.sh — scv/archive/INDEX.yaml 을 다시 만든다 (프런트매터만 모은 색인).
#
# 왜 따로 있나: 색인은 원래 보관(work.sh --archive)할 때만 다시 만들어졌다. 그런데 회귀
# 실행기와 help 는 이 색인을 **먼저** 읽는다 — 삭감에서 계약을 obsolete 로 표시해도 다음
# 보관까지 색인이 낡아 실행기가 그 계약을 계속 돌렸다 (0.54.0 에서 드러남). 색인을 만드는
# 코드를 한 곳에 두고, 보관과 삭감이 같은 것을 부른다.
#
# 동작: PLAN.md 프런트매터(title/kind/status/epic/obsoleted_by)만 읽는다. 본문은 읽지 않는다.
# 판단은 없다 — 있는 값을 그대로 옮긴다.
#
# Usage:
#   archive-index.sh [<module>]        # 모듈 인자는 work.sh 와 같다 (모노레포 중첩)
#   ARCHIVE_DIR=<dir> archive-index.sh # 이미 해석된 보관 폴더를 그대로 쓴다
#
# Output: "WROTE: <path>" 한 줄.
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/yaml.sh
source "$SCRIPT_DIR/lib/yaml.sh"
# shellcheck source=lib/scvroot.sh
source "$SCRIPT_DIR/lib/scvroot.sh"

scv_init_paths "${1:-}"

# archive_index_render <archive dir> — 표준출력으로 색인 본문을 낸다. 파일은 바깥에서 쓴다.
archive_index_render() {
  local dir="$1" plan_file idx_slug idx_title idx_kind idx_status idx_epic idx_obsoleted_by
  echo "# scv/archive/INDEX.yaml — auto-managed by /scv:work --archive and scripts/archive-index.sh (v0.11.0+)."
  echo "# Do not edit manually. Regenerated on every archive and on every obsolete marking."
  echo "generated_at: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "archives:"
  for plan_file in "$dir"/*/PLAN.md; do
    [[ -f "$plan_file" ]] || continue
    idx_slug=$(basename "$(dirname "$plan_file")")
    idx_title=$(yaml_get "$plan_file" title)
    idx_kind=$(yaml_get "$plan_file" kind)
    idx_status=$(yaml_get "$plan_file" status)
    idx_epic=$(yaml_get "$plan_file" epic)
    idx_obsoleted_by=$(yaml_get "$plan_file" obsoleted_by)
    echo "  - slug: $idx_slug"
    [[ -n "$idx_title" ]] && echo "    title: \"$idx_title\""
    [[ -n "$idx_kind" ]] && echo "    kind: $idx_kind"
    [[ -n "$idx_status" ]] && echo "    status: $idx_status"
    [[ -n "$idx_epic" ]] && echo "    epic: $idx_epic"
    [[ -n "$idx_obsoleted_by" ]] && echo "    obsoleted_by: $idx_obsoleted_by"
  done
}

[[ -d "$ARCHIVE_DIR" ]] || { echo "✖ archive dir not found: $ARCHIVE_DIR" >&2; exit 1; }
INDEX_FILE="$ARCHIVE_DIR/INDEX.yaml"
archive_index_render "$ARCHIVE_DIR" > "$INDEX_FILE"
echo "WROTE: $INDEX_FILE"
