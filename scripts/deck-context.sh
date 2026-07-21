#!/usr/bin/env bash
# bash 4+ required. macOS ships 3.2 — auto-escalate to brew bash.
if (( BASH_VERSINFO[0] < 4 )); then
  for _b in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    [[ -x "$_b" ]] && exec "$_b" "$0" "$@"
  done
  echo "Error: SCV requires bash 4+. Install via 'brew install bash'." >&2
  exit 1
fi

# deck-context.sh — detect the "big picture" sources /scv:deck needs to render a
# real 기획서 (whole → position → change → why). Read-only. Drives the B→A flow
# in commands/deck.md: B = big picture ABSENT (help create it first),
# A = big picture PRESENT (pull it and compose).
#
# Usage: deck-context.sh [<slug>] [<module>]
#   <slug>   — a promote/archive plan slug (to find its FEATURE_ARCHITECTURE.md)
#   <module> — a monorepo module dir containing scv/ (nested; e.g. FE)
#
# Emits KEY: value lines for commands/deck.md to parse.
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/env.sh
source "$SCRIPT_DIR/lib/env.sh"
# shellcheck source=lib/scvroot.sh
source "$SCRIPT_DIR/lib/scvroot.sh"
env_load 2>/dev/null || true

SLUG=""; TARGET=""
for a in "$@"; do
  case "$a" in
    -h|--help) sed -n '11,21p' "$0"; exit 0 ;;
    *)
      if [[ -z "$TARGET" ]] && scv_target_path "$a" >/dev/null 2>&1; then
        TARGET="$a"
      elif [[ -z "$SLUG" ]]; then
        SLUG="$a"
      fi
      ;;
  esac
done

# Resolve scv/ (monorepo-nested aware). Sets SCV_DIR/PROMOTE_DIR/ARCHIVE_DIR.
scv_init_paths "$TARGET"

echo "SCV_DIR: $SCV_DIR"

present=0
_report() { # KEY path
  if [[ -e "$2" ]]; then echo "$1: present $2"; present=1; else echo "$1: absent"; fi
}

_report ARCHITECTURE "$SCV_DIR/ARCHITECTURE.md"
# DESIGN/DOMAIN are extra context (do not by themselves count as the big picture).
[[ -e "$SCV_DIR/DESIGN.md" ]]  && echo "DESIGN: present $SCV_DIR/DESIGN.md"   || echo "DESIGN: absent"
[[ -e "$SCV_DIR/DOMAIN.md" ]]  && echo "DOMAIN: present $SCV_DIR/DOMAIN.md"   || echo "DOMAIN: absent"

# graphify docs graph (project-root relative, matching /scv:work convention).
if [[ -d ".graphify/docs/graphify-out" ]]; then
  echo "GRAPHIFY_GRAPH: present .graphify/docs/graphify-out"; present=1
else
  echo "GRAPHIFY_GRAPH: absent"
fi

# FEATURE_ARCHITECTURE for a specific plan (position-in-whole diagram).
if [[ -n "$SLUG" ]]; then
  fa=""
  for cand in "$PROMOTE_DIR/$SLUG/FEATURE_ARCHITECTURE.md" "$ARCHIVE_DIR/$SLUG/FEATURE_ARCHITECTURE.md"; do
    [[ -f "$cand" ]] && { fa="$cand"; break; }
  done
  if [[ -n "$fa" ]]; then echo "FEATURE_ARCH: present $fa"; present=1; else echo "FEATURE_ARCH: absent (slug=$SLUG)"; fi
else
  echo "FEATURE_ARCH: n/a (no slug)"
fi

if [[ $present -eq 1 ]]; then
  echo "BIG_PICTURE: present"
  echo "MODE_HINT: A (pull existing big picture → compose context-first deck)"
else
  echo "BIG_PICTURE: absent"
  echo "MODE_HINT: B (no big picture found → help create ARCHITECTURE.md or run /scv:promote first, then A)"
fi
