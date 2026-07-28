#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: vendor-core.sh --source PATH --target DIR [--profile FILE] [--artifact-sha256 HEX]" >&2
}

SOURCE=""
TARGET=""
PROFILE=""
ARTIFACT_SHA256=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) SOURCE="${2:-}"; shift 2 ;;
    --target) TARGET="${2:-}"; shift 2 ;;
    --profile) PROFILE="${2:-}"; shift 2 ;;
    --artifact-sha256) ARTIFACT_SHA256="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done
[[ -n "$SOURCE" && -d "$SOURCE" && -n "$TARGET" ]] || { usage; exit 2; }
case "$TARGET" in
  /|.|..|"") echo "unsafe target directory: $TARGET" >&2; exit 1 ;;
esac
if [[ -n "$ARTIFACT_SHA256" && ! "$ARTIFACT_SHA256" =~ ^[0-9a-fA-F]{64}$ ]]; then
  echo "--artifact-sha256 must be exactly 64 hexadecimal characters" >&2
  exit 1
fi

SOURCE="$(cd "$SOURCE" && pwd)"
PROFILE_ABS=""
if [[ -n "$PROFILE" ]]; then
  [[ -f "$PROFILE" ]] || { echo "profile not found: $PROFILE" >&2; exit 1; }
  PROFILE_ABS="$(cd "$(dirname "$PROFILE")" && pwd)/$(basename "$PROFILE")"
fi

PARENT="$(dirname "$TARGET")"
mkdir -p "$PARENT"
STAGE="$(mktemp -d "$PARENT/.scv-core-vendor.XXXXXX")"
EXPORT_TMP="$(mktemp -d)"
trap 'rm -rf "$STAGE" "$EXPORT_TMP"' EXIT

if git -C "$SOURCE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  rmdir "$EXPORT_TMP"
  "$SOURCE/tools/export-core.sh" --output "$EXPORT_TMP" >/dev/null
  SOURCE_EXPORT="$EXPORT_TMP"
else
  SOURCE_EXPORT="$SOURCE"
  "$SOURCE_EXPORT/tools/verify-core.sh" --root "$SOURCE_EXPORT" >/dev/null
fi

if command -v rsync >/dev/null 2>&1; then
  rsync -a "$SOURCE_EXPORT/" "$STAGE/"
else
  cp -R -p "$SOURCE_EXPORT/." "$STAGE/"
fi
source_manifest_sha="$(
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$SOURCE_EXPORT/core-manifest.json" | awk '{print $1}'
  else
    shasum -a 256 "$SOURCE_EXPORT/core-manifest.json" | awk '{print $1}'
  fi
)"
source_payload_sha="$(
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$SOURCE_EXPORT/SHA256SUMS" | awk '{print $1}'
  else
    shasum -a 256 "$SOURCE_EXPORT/SHA256SUMS" | awk '{print $1}'
  fi
)"

if [[ -n "$PROFILE_ABS" ]]; then
  "$STAGE/tools/materialize-profile.sh" --root "$STAGE/core" --profile "$PROFILE_ABS" >/dev/null
fi
"$STAGE/tools/generate-manifest.sh" --root "$STAGE" >/dev/null
"$STAGE/tools/verify-core.sh" --root "$STAGE" >/dev/null

manifest_sha="$(
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$STAGE/core-manifest.json" | awk '{print $1}'
  else
    shasum -a 256 "$STAGE/core-manifest.json" | awk '{print $1}'
  fi
)"
payload_sha="$(
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$STAGE/SHA256SUMS" | awk '{print $1}'
  else
    shasum -a 256 "$STAGE/SHA256SUMS" | awk '{print $1}'
  fi
)"

version="$(tr -d '[:space:]' < "$STAGE/VERSION")"
core_api="$(tr -d '[:space:]' < "$STAGE/CORE_API")"
template_version="$(tr -d '[:space:]' < "$STAGE/TEMPLATE_VERSION")"
source_commit="$(tr -d '[:space:]' < "$STAGE/SOURCE_COMMIT")"
vendored_at="$(tr -d '[:space:]' < "$STAGE/SOURCE_DATE")"
source_repository="$(sed -n 's/^source_repository:[[:space:]]*//p' "$STAGE/SOURCE_INFO" | head -1)"
artifact_json="null"
if [[ -n "$ARTIFACT_SHA256" ]]; then
  artifact_lower="$(printf '%s' "$ARTIFACT_SHA256" | tr '[:upper:]' '[:lower:]')"
  artifact_json="\"$artifact_lower\""
fi
cat > "$STAGE/core.lock.json" <<EOF
{
  "schema_version": 1,
  "core_version": "$version",
  "core_api": $core_api,
  "template_version": "$template_version",
  "source_repository": "$source_repository",
  "source_commit": "$source_commit",
  "source_manifest_sha256": "$source_manifest_sha",
  "source_payload_sha256": "$source_payload_sha",
  "manifest_sha256": "$manifest_sha",
  "payload_sha256": "$payload_sha",
  "artifact_sha256": $artifact_json,
  "vendored_at": "$vendored_at"
}
EOF
"$STAGE/tools/verify-core.sh" --root "$STAGE" >/dev/null

BACKUP=""
if [[ -e "$TARGET" ]]; then
  BACKUP="$PARENT/.scv-core-previous.$$"
  mv "$TARGET" "$BACKUP"
fi
if mv "$STAGE" "$TARGET"; then
  [[ -z "$BACKUP" ]] || rm -rf "$BACKUP"
else
  [[ -z "$BACKUP" ]] || mv "$BACKUP" "$TARGET"
  exit 1
fi
trap 'rm -rf "$EXPORT_TMP"' EXIT
echo "vendored SCV Core v$version to $TARGET"
