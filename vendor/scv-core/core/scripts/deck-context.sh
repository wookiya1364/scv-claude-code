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
# in references/protocols/deck.md: B = big picture ABSENT (help create it first),
# A = big picture PRESENT (pull it and compose).
#
# Usage: deck-context.sh [<slug>] [<module>]
#   <slug>   — a promote/archive plan slug (to find its FEATURE_ARCHITECTURE.md)
#   <module> — a monorepo module dir containing scv/ (nested; e.g. FE)
#
# Emits KEY: value lines for references/protocols/deck.md to parse.
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

# /scv:deck may pass a markdown PATH where a slug is expected — derive the slug
# from the basename so FEATURE_ARCHITECTURE-by-slug detection can still fire.
if [[ -n "$SLUG" ]]; then SLUG="${SLUG##*/}"; SLUG="${SLUG%.md}"; fi

# Resolve scv/ (monorepo-nested aware). Sets SCV_DIR/PROMOTE_DIR/ARCHIVE_DIR.
scv_init_paths "$TARGET"

echo "SCV_DIR: $SCV_DIR"

present=0

# A doc counts as a real "big picture" only if it is NOT an unfilled SCV
# template — the template scaffolds sections with <TODO ...> placeholders.
_doc_is_real() {
  [[ -f "$1" ]] || return 1
  local todos; todos=$(grep -c '<TODO' "$1" 2>/dev/null)  # grep -c prints 0 on no-match
  [[ "${todos:-0}" -ge 2 ]] && return 1
  return 0
}

if [[ -f "$SCV_DIR/ARCHITECTURE.md" ]]; then
  if _doc_is_real "$SCV_DIR/ARCHITECTURE.md"; then
    echo "ARCHITECTURE: present $SCV_DIR/ARCHITECTURE.md"; present=1
  else
    echo "ARCHITECTURE: template (unfilled <TODO> — not counted as big picture)"
  fi
else
  echo "ARCHITECTURE: absent"
fi
# DESIGN/DOMAIN are extra context (do not by themselves count as the big picture).
[[ -e "$SCV_DIR/DESIGN.md" ]]  && echo "DESIGN: present $SCV_DIR/DESIGN.md"   || echo "DESIGN: absent"
[[ -e "$SCV_DIR/DOMAIN.md" ]]  && echo "DOMAIN: present $SCV_DIR/DOMAIN.md"   || echo "DOMAIN: absent"

# Real architecture / screen / system / IA docs under docs/ (project root) or
# <scv-parent>/docs — a strong big-picture source (e.g. a screens/IA doc).
_bases=("docs")
_pdir="$(dirname "$SCV_DIR")"
[[ "$_pdir" != "." && -d "$_pdir/docs" ]] && _bases+=("$_pdir/docs")
_docs=()
for _base in "${_bases[@]}"; do
  [[ -d "$_base" ]] || continue
  while IFS= read -r _f; do
    if basename "$_f" | grep -qiE 'arch|screen|structure|system|화면|기획|[-_]ia'; then
      _doc_is_real "$_f" && _docs+=("$_f")
    fi
  done < <(find "$_base" -maxdepth 2 -type f -iname '*.md' 2>/dev/null | LC_ALL=C sort)
done
if [[ ${#_docs[@]} -gt 0 ]]; then
  echo "DOCS_CONTEXT: present ${_docs[*]}"; present=1
else
  echo "DOCS_CONTEXT: absent"
fi

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
