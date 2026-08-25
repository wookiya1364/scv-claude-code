#!/usr/bin/env bash
# Collect artifact file paths for a given status (SCV artifact-path contract:
# Playwright test-results/**, MCP test-results/mcp/**, logs test-results/logs/*.log).
# Prints one absolute path per line to stdout. Silent if no artifacts.
#
# Usage: collect-artifacts.sh <status>
#   status: passed | failed | info
set -euo pipefail

STATUS="${1:-info}"
TR="test-results"

if [[ ! -d "$TR" ]]; then
  exit 0
fi

# Scope (v0.32.0+): only this plan's files by default. The report action is
# phase-level, so the slug comes from --slug (SCV_ATTACHMENTS_SLUG), else the
# single active promote plan; with neither, fall back to everything (legacy)
# and say so once on stderr. SCV_ATTACHMENTS_SCOPE=all skips all of this.
# shellcheck source=lib/attachment-scope.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/attachment-scope.sh"
SCOPE_MODE="$(attachment_scope_mode)"
SCOPE_SLUG=""
if [[ "$SCOPE_MODE" == "slug" ]]; then
  SCOPE_SLUG="$(attachment_scope_resolve_slug "${SCV_ATTACHMENTS_SLUG:-}")"
  if [[ -z "$SCOPE_SLUG" ]]; then
    echo "attachments: no slug to scope by (pass --slug to the report action, or keep exactly one active promote plan) — attaching the latest files of any slug" >&2
  fi
fi

# 실행 기록(run manifest, lib/run-manifest.sh)이 있으면 그것이 1순위 — 결과
# 폴더명이 잘려 슬러그가 경로에 없어도 붙는다. 이름 매칭은 기록이 없을 때의
# 폴백이다.
MANIFEST_LIST=""
if [[ "$SCOPE_MODE" == "slug" && -n "$SCOPE_SLUG" ]]; then
  # shellcheck source=lib/run-manifest.sh
  source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/run-manifest.sh"
  MANIFEST_LIST="$(run_manifest_read "$SCOPE_SLUG" "$TR")"
fi

# Find the most recent matching file (by mtime).
# BSD (macOS) and GNU (Linux) compatible — `find -printf` is GNU-only,
# so we hand the list to `ls -t` which sorts by mtime on both.
_latest() {
  # Usage: _latest <pattern_args...> — 실행 기록이 있으면 기록에서, 없으면
  # 이름 매칭으로 고른다 (둘 다 최신 파일 1개).
  local matches
  if [[ -n "$MANIFEST_LIST" ]]; then
    local line a keep
    matches=""
    while IFS= read -r line; do
      [[ -n "$line" && -f "$line" ]] || continue
      keep=0
      for a in "$@"; do
        case "$a" in \*.*) case "${line##*/}" in $a) keep=1 ;; esac ;; esac
      done
      [[ $keep -eq 1 ]] && matches+="$line"$'\n'
    done <<< "$MANIFEST_LIST"
    matches="${matches%$'\n'}"
  else
    # shellcheck disable=SC2068
    matches=$(find "$TR" -maxdepth 6 -type f \( $@ \) 2>/dev/null | attachment_scope_filter "$SCOPE_SLUG")
  fi
  [[ -z "$matches" ]] && return 0
  printf '%s\n' "$matches" | tr '\n' '\0' | xargs -0 ls -t 2>/dev/null | head -n 1
}

SCREENSHOT=$(_latest -name "*.png")
VIDEO=$(_latest -name "*.webm" -o -name "*.mp4")

# 0건이면 침묵하지 않는다 — 한 줄로 알리고 재실행 경로를 제시한다.
if [[ "$SCOPE_MODE" == "slug" && -n "$SCOPE_SLUG" && -z "$MANIFEST_LIST" && -z "$SCREENSHOT" && -z "$VIDEO" ]]; then
  echo "attachments: nothing under $TR belongs to '$SCOPE_SLUG' (SCV_ATTACHMENTS_SCOPE=slug) — no evidence attached; run-plan-tests.sh --slug '$SCOPE_SLUG' records this plan's evidence, or set SCV_ATTACHMENTS_SCOPE=all" >&2
fi

emit() {
  local f="$1"
  [[ -n "$f" && -f "$f" ]] && echo "$f"
  return 0   # an empty slot is not an error — under set -e it used to abort before the video
}

case "$STATUS" in
  passed)
    emit "$SCREENSHOT"
    emit "$VIDEO"
    ;;
  info)
    emit "$SCREENSHOT"
    ;;
  failed)
    emit "$SCREENSHOT"
    emit "$VIDEO"
    # Truncated log tail (max 20KB) for failure context.
    LOG=$(_latest -name "*.log")
    if [[ -n "$LOG" && -f "$LOG" ]]; then
      mkdir -p "$TR/.snippets"
      SNIPPET="$TR/.snippets/$(basename "$LOG").tail.txt"
      tail -c 20480 "$LOG" > "$SNIPPET"
      echo "$SNIPPET"
    fi
    ;;
  *)
    emit "$SCREENSHOT"
    ;;
esac
