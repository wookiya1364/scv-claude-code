#!/usr/bin/env bash
# bash 4+ required. macOS ships 3.2 — auto-escalate to brew bash.
if (( BASH_VERSINFO[0] < 4 )); then
  for _b in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    [[ -x "$_b" ]] && exec "$_b" "$0" "$@"
  done
  echo "Error: SCV requires bash 4+. Install via 'brew install bash'." >&2
  exit 1
fi

# deck.sh — /scv:deck wrapper. Turns a markdown planning doc into a
# self-contained single-HTML deck via the DeckUI kit + deterministic transform.
#
# Usage:  deck.sh <input.md> [slug] [--out <path>]
# Emits (for commands/deck.md to parse):
#   DECK_SLUG: <slug>
#   LINT: <n> warning(s)   (+ one "  ⚠ ..." line each)
#   DECK_HTML: <absolute path to built single-file HTML>
#
# DeckUI (Vite+React) lives in the plugin at ../DeckUI. Node + pnpm required
# (new /scv:deck-only deps — see /scv:install-deps).
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DECKUI="$SCRIPT_DIR/../DeckUI"

die() { echo "ERROR: $*" >&2; exit 1; }

# ---- args ----
MD=""; SLUG=""; OUT=""
while (( $# )); do
  case "$1" in
    --out) OUT="${2:-}"; shift ;;
    --out=*) OUT="${1#--out=}" ;;
    -h|--help) sed -n '11,22p' "$0"; exit 0 ;;
    -*) die "unknown flag: $1" ;;
    *) if [[ -z "$MD" ]]; then MD="$1"; elif [[ -z "$SLUG" ]]; then SLUG="$1"; fi ;;
  esac
  shift
done
[[ -n "$MD" ]] || die "input markdown path required (usage: deck.sh <input.md> [slug])"
[[ "$MD" != /* ]] && MD="$PWD/$MD"
[[ -f "$MD" ]] || die "markdown not found: $MD"
[[ -d "$DECKUI" ]] || die "DeckUI kit not found at $DECKUI"

if [[ -z "$SLUG" ]]; then
  SLUG=$(basename "$MD"); SLUG="${SLUG%.md}"
fi
SLUG=$(printf '%s' "$SLUG" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9' '-' | sed 's/^-*//; s/-*$//')
[[ -n "$SLUG" ]] || SLUG="deck"
[[ -z "$OUT" ]] && OUT="$PWD/${SLUG}-deck.html"
[[ "$OUT" != /* ]] && OUT="$PWD/$OUT"

command -v node >/dev/null 2>&1 || die "node not found — /scv:deck needs Node + pnpm (see /scv:install-deps)"
command -v pnpm >/dev/null 2>&1 || die "pnpm not found — install with 'npm i -g pnpm' (see /scv:install-deps)"

# ---- deps (first run only) ----
if [[ ! -d "$DECKUI/node_modules" ]]; then
  echo "Installing DeckUI dependencies (first run)..." >&2
  ( cd "$DECKUI" && pnpm install ) >&2 || die "pnpm install failed in $DECKUI"
fi

# ---- transform: md → deck.json (deterministic; prints DECK_SLUG/LINT) ----
node "$DECKUI/scripts/md-to-deck.mjs" "$MD" "$SLUG" || die "transform failed"

# ---- build: self-contained single HTML ----
( cd "$DECKUI" && VITE_DECK_SLUG="$SLUG" pnpm build:deck ) >&2 || die "deck build failed"
[[ -f "$DECKUI/dist-deck/index.html" ]] || die "build produced no HTML"

mkdir -p "$(dirname "$OUT")"
cp "$DECKUI/dist-deck/index.html" "$OUT"
echo "DECK_HTML: $OUT"
