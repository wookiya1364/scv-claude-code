#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: export-core.sh --output DIR" >&2
}

OUTPUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output) OUTPUT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done
[[ -n "$OUTPUT" ]] || { usage; exit 2; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
case "$OUTPUT" in
  /|.|..|"") echo "unsafe output directory: $OUTPUT" >&2; exit 1 ;;
esac
if [[ -e "$OUTPUT" && -n "$(find "$OUTPUT" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
  echo "output directory must be absent or empty: $OUTPUT" >&2
  exit 1
fi

PARENT="$(dirname "$OUTPUT")"
mkdir -p "$PARENT"
TMP="$(mktemp -d "$PARENT/.scv-core-export.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

for file in VERSION CORE_API TEMPLATE_VERSION LICENSE README.md README.ko.md README.ja.md CHANGELOG.md; do
  [[ -f "$REPO_ROOT/$file" ]] && cp "$REPO_ROOT/$file" "$TMP/$file"
done
if command -v rsync >/dev/null 2>&1; then
  rsync -a \
    --exclude='host-profile.env' \
    --exclude='node_modules/' \
    --exclude='dist/' \
    --exclude='dist-deck/' \
    --exclude='coverage/' \
    --exclude='.vite/' \
    --exclude='.cache/' \
    --exclude='*.tsbuildinfo' \
    --exclude='*.tmp' \
    --include='DeckUI/src/deck/decks/demo-prd/deck.json' \
    --include='DeckUI/src/deck/decks/refund/deck.json' \
    --exclude='DeckUI/src/deck/decks/*/deck.json' \
    "$REPO_ROOT/core/" "$TMP/core/"
  rsync -a "$REPO_ROOT/tools/" "$TMP/tools/"
else
  cp -R -p "$REPO_ROOT/core" "$TMP/core"
  rm -f "$TMP/core/host-profile.env"
  find "$TMP/core" -type d \
    \( -name node_modules -o -name dist -o -name dist-deck -o -name coverage -o -name .vite -o -name .cache \) \
    -prune -exec rm -rf {} +
  find "$TMP/core" -type f \
    \( -name '*.tsbuildinfo' -o -name '*.tmp' \) -exec rm -f {} +
  if [[ -d "$TMP/core/DeckUI/src/deck/decks" ]]; then
    find "$TMP/core/DeckUI/src/deck/decks" -mindepth 2 -maxdepth 2 \
      -type f -name deck.json \
      ! -path '*/demo-prd/deck.json' \
      ! -path '*/refund/deck.json' \
      -exec rm -f {} +
  fi
  cp -R -p "$REPO_ROOT/tools" "$TMP/tools"
fi

# Both export paths may retain source-owned parent directories after generated
# deck.json files are excluded. Remove only directories that are truly empty.
if [[ -d "$TMP/core/DeckUI/src/deck/decks" ]]; then
  find "$TMP/core/DeckUI/src/deck/decks" -depth -mindepth 1 -type d -empty -delete
fi

# Source checkout metadata uses links to the canonical root files. Published
# exports must contain only regular files/directories so every wrapper can apply
# one strict archive policy without following links during extraction.
for file in VERSION CORE_API TEMPLATE_VERSION; do
  rm -f "$TMP/core/$file"
  cp "$TMP/$file" "$TMP/core/$file"
done
if non_regular="$(find "$TMP" ! -type f ! -type d -print -quit)" && [[ -n "$non_regular" ]]; then
  echo "export contains a link or special file: ${non_regular#"$TMP/"}" >&2
  exit 1
fi

SOURCE_COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || printf 'unknown')"
SOURCE_DATE="$(git -C "$REPO_ROOT" show -s --format=%cI HEAD 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"
SOURCE_REPOSITORY="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || printf 'https://github.com/wookiya1364/scv-core.git')"
printf '%s\n' "$SOURCE_COMMIT" > "$TMP/SOURCE_COMMIT"
printf '%s\n' "$SOURCE_DATE" > "$TMP/SOURCE_DATE"
printf 'source_repository: %s\n' "$SOURCE_REPOSITORY" > "$TMP/SOURCE_INFO"

"$TMP/tools/generate-manifest.sh" --root "$TMP" >/dev/null
"$TMP/tools/verify-core.sh" --root "$TMP" >/dev/null

if [[ -d "$OUTPUT" ]]; then
  rmdir "$OUTPUT"
fi
mv "$TMP" "$OUTPUT"
trap - EXIT
echo "exported SCV Core to $OUTPUT"
