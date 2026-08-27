#!/usr/bin/env bash
# bash 4+ required. macOS ships 3.2 — auto-escalate to brew bash.
if (( BASH_VERSINFO[0] < 4 )); then
  for _b in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    [[ -x "$_b" ]] && exec "$_b" "$0" "$@"
  done
  echo "Error: SCV requires bash 4+. Install via 'brew install bash'." >&2
  exit 1
fi

# deck.sh — /scv:deck wrapper. markdown planning doc → a spec-grade deck.
#
#   DEFAULT (document): a buildless, self-contained 기획서 HTML you read top to
#   bottom and print to PDF. Runs the deterministic transform + a zero-dependency
#   HTML renderer (deckdoc/) — NO Vite, NO React, NO build. Only a slim remark
#   stack (~7MB), so it works without the heavy slide-render deps.
#
#   --slides: the DeckUI slide presentation (Vite+React single-file build). Heavier
#   (needs the full DeckUI install), for when you want an on-screen deck.
#
# Both share ONE transform (deckdoc/transform.mjs → deck data) so the document and
# the slide deck can never diverge; neither ever invents content.
#
# Usage:  deck.sh <input.md> [slug] [--slides] [--out <path>] [--mermaid cdn|none]
#                  [--lang english|korean|japanese] [--no-source] [--no-static]
#   --lang: the deck UI chrome's language (English default — same SCV_LANG convention
#   as scripts/render-template.sh). Caller (references/protocols/deck.md) resolves LANG_RESOLVED
#   the same way every other command does and passes it here; omit to fall back to
#   the project's .env SCV_LANG, or English if that's unset too.
# Emits (for references/protocols/deck.md to parse):
#   DECK_SLUG: <slug>
#   LINT: <n> warning(s)   (+ one "  ⚠ ..." line each)
#   DECK_HTML: <absolute path to built single-file HTML>
#   STATIC_MERMAID: embedded diagrams=<n> → <path>   (doc mode; best-effort —
#     bakes diagrams as inline SVG via local headless Chrome so the deck opens
#     fully rendered offline. Skipped without touching the file when Chrome or
#     the mermaid CDN is unavailable; disable with --no-static or SCV_DECK_STATIC=0)
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
DECK_RUNTIME="$SCRIPT_DIR/deck-runtime.sh"
[[ -x "$DECK_RUNTIME" ]] || {
  echo "ERROR: Deck runtime helper not found at $DECK_RUNTIME" >&2
  exit 1
}

die() { echo "ERROR: $*" >&2; exit 1; }

# ---- args ----
MD=""; SLUG=""; OUT=""; MODE="doc"; MERMAID="cdn"; SOURCE_FLAG=""; LANG_ARG=""; FULL_FLAG=""; STATIC="${SCV_DECK_STATIC:-1}"
while (( $# )); do
  case "$1" in
    --slides) MODE="slides" ;;
    --doc) MODE="doc" ;;
    --out) OUT="${2:-}"; shift ;;
    --out=*) OUT="${1#--out=}" ;;
    --mermaid) MERMAID="${2:-cdn}"; shift ;;
    --mermaid=*) MERMAID="${1#--mermaid=}" ;;
    --lang) LANG_ARG="${2:-}"; shift ;;
    --lang=*) LANG_ARG="${1#--lang=}" ;;
    --no-source) SOURCE_FLAG="--no-source" ;;
    --full) FULL_FLAG="--full" ;;
    --no-static) STATIC=0 ;;
    -h|--help) sed -n '11,36p' "$0"; exit 0 ;;
    -*) die "unknown flag: $1" ;;
    *) if [[ -z "$MD" ]]; then MD="$1"; elif [[ -z "$SLUG" ]]; then SLUG="$1"; fi ;;
  esac
  shift
done
[[ -n "$MD" ]] || die "input path required (usage: deck.sh <input.md|slug-dir> [slug] [--slides])"
[[ "$MD" != /* ]] && MD="$PWD/$MD"
[[ -e "$MD" ]] || die "input not found: $MD"
DECKUI="$(bash "$DECK_RUNTIME" ensure)" || exit $?
DECKDOC="$DECKUI/scripts/deckdoc"
[[ -d "$DECKUI" ]] || die "DeckUI kit not found at $DECKUI"

# A slug FOLDER (scv/promote|archive/<slug>/) combines PLAN + FEATURE_ARCHITECTURE
# + TESTS into ONE document written next to the markdown. Slides build from a
# single markdown only.
IS_DIR=0
if [[ -d "$MD" ]]; then
  IS_DIR=1
  [[ "$MODE" == "slides" ]] && die "--slides takes a single markdown file, not a slug folder: $MD"
  MODE="doc"
fi

if [[ -z "$SLUG" ]]; then
  SLUG=$(basename "$MD"); SLUG="${SLUG%.[Mm][Dd]}"   # dir basename has no .md; case-insensitive strip for files
fi
# -cs: complement + squeeze so runs of non-alnum collapse to ONE dash — must
# match transform.mjs's /[^a-z0-9]+/→"-" or the emitted paths won't line up.
SLUG=$(printf '%s' "$SLUG" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-*//; s/-*$//')
[[ -n "$SLUG" ]] || SLUG="deck"
# File default: <slug>-deck.html in CWD. Folder default: leave empty so doc.mjs
# writes <slug>.deck.html INTO the slug folder (next to the markdown).
if [[ -z "$OUT" && "$IS_DIR" -eq 0 ]]; then OUT="$PWD/${SLUG}-deck.html"; fi
[[ -n "$OUT" && "$OUT" != /* ]] && OUT="$PWD/$OUT"

command -v node >/dev/null 2>&1 || die "node not found — /scv:deck needs Node + pnpm (see /scv:install-deps)"
command -v pnpm >/dev/null 2>&1 || die "pnpm not found — install with 'npm i -g pnpm' (see /scv:install-deps)"

# ---- deckdoc slim deps (both paths: the shared transform lives here) ----
if [[ ! -d "$DECKDOC/node_modules" ]]; then
  echo "Installing deckdoc (slim, ~7MB) dependencies (first run)..." >&2
  ( cd "$DECKDOC" && pnpm install ) >&2 || die "pnpm install failed in $DECKDOC"
fi

LANG_FLAG=""
[[ -n "$LANG_ARG" ]] && LANG_FLAG="--lang $LANG_ARG"

# ---- DEFAULT: buildless document (no Vite/React) ----
if [[ "$MODE" == "doc" ]]; then
  # doc.mjs prints DECK_SLUG / LINT / DECK_HTML itself. Omit --out for a slug
  # folder so doc.mjs defaults the file into the folder. Capture stdout (and
  # replay it verbatim) so the built path is known for the static-embed step.
  if [[ -n "$OUT" ]]; then
    BUILD_OUT=$(node "$DECKDOC/doc.mjs" "$MD" "$SLUG" --out "$OUT" --mermaid "$MERMAID" $SOURCE_FLAG $LANG_FLAG $FULL_FLAG) || die "document build failed"
  else
    BUILD_OUT=$(node "$DECKDOC/doc.mjs" "$MD" "$SLUG" --mermaid "$MERMAID" $SOURCE_FLAG $LANG_FLAG $FULL_FLAG) || die "document build failed"
  fi
  printf '%s\n' "$BUILD_OUT"
  BUILT=$(printf '%s\n' "$BUILD_OUT" | sed -n 's/^DECK_HTML: //p' | tail -1)

  # Best-effort offline embed: bake every diagram as inline SVG via a local
  # headless Chrome (static-mermaid.mjs). On any miss (no Chrome, offline CDN,
  # diagram error) the CDN + text-fallback deck ships unchanged.
  if [[ "$STATIC" != "0" && "$MERMAID" == "cdn" && -n "$BUILT" && -f "$BUILT" ]]; then
    node "$DECKDOC/static-mermaid.mjs" "$BUILT" \
      || echo "STATIC_MERMAID: skipped (kept CDN render + text fallback)" >&2
  fi
  exit 0
fi

# ---- --slides: heavy DeckUI Vite build ----
if [[ ! -d "$DECKUI/node_modules" ]]; then
  echo "Installing DeckUI (slide) dependencies (first run)..." >&2
  ( cd "$DECKUI" && pnpm install ) >&2 || die "pnpm install failed in $DECKUI"
fi
# transform: md → deck.json (deterministic; prints DECK_SLUG/LINT). md-to-deck.mjs has
# no --lang flag (only reads SCV_LANG), so an explicit --lang here is passed via env.
if [[ -n "$LANG_ARG" ]]; then
  SCV_LANG="$LANG_ARG" node "$DECKUI/scripts/md-to-deck.mjs" "$MD" "$SLUG" || die "transform failed"
else
  node "$DECKUI/scripts/md-to-deck.mjs" "$MD" "$SLUG" || die "transform failed"
fi
# build: self-contained single HTML
( cd "$DECKUI" && VITE_DECK_SLUG="$SLUG" pnpm build:deck ) >&2 || die "deck build failed"
[[ -f "$DECKUI/dist-deck/index.html" ]] || die "build produced no HTML"
mkdir -p "$(dirname "$OUT")" || die "cannot create output dir: $(dirname "$OUT")"
cp "$DECKUI/dist-deck/index.html" "$OUT" || die "cannot write deck HTML: $OUT"
echo "DECK_HTML: $OUT"
