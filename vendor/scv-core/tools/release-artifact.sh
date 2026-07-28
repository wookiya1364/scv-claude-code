#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: release-artifact.sh [--output-dir DIR]" >&2
}

OUTPUT_DIR="dist"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir) OUTPUT_DIR="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(tr -d '[:space:]' < "$REPO_ROOT/VERSION")"
NAME="scv-core-v$VERSION"
mkdir -p "$OUTPUT_DIR"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
"$REPO_ROOT/tools/export-core.sh" --output "$STAGING/$NAME" >/dev/null

ARCHIVE="$OUTPUT_DIR/$NAME.tar.gz"
if tar --version 2>/dev/null | grep -q 'GNU tar'; then
  tar --sort=name --mtime='@0' --owner=0 --group=0 --numeric-owner \
    -C "$STAGING" -cf - "$NAME" | gzip -n > "$ARCHIVE"
else
  find "$STAGING/$NAME" -exec touch -t 197001010000 {} +
  COPYFILE_DISABLE=1 tar --uid 0 --gid 0 -C "$STAGING" -cf - "$NAME" \
    | gzip -n > "$ARCHIVE"
fi

if command -v sha256sum >/dev/null 2>&1; then
  (cd "$OUTPUT_DIR" && sha256sum "$NAME.tar.gz" > "$NAME.tar.gz.sha256")
elif command -v shasum >/dev/null 2>&1; then
  (cd "$OUTPUT_DIR" && shasum -a 256 "$NAME.tar.gz" > "$NAME.tar.gz.sha256")
else
  echo "sha256sum or shasum is required" >&2
  exit 1
fi
echo "release artifacts: $ARCHIVE and $ARCHIVE.sha256"
