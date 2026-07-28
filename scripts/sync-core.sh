#!/usr/bin/env bash
# Explicit maintainer tool for pinning a local or released SCV Core payload.
# Installed SCV commands never call this script automatically.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROFILE="$REPO_ROOT/adapter/claude-code.env"
PLUGIN_MANIFEST="$REPO_ROOT/.claude-plugin/plugin.json"
MARKETPLACE_MANIFEST="$REPO_ROOT/.claude-plugin/marketplace.json"
SOURCE_REPO="wookiya1364/scv-core"
SOURCE_DIR=
VERSION=
LATEST=0
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  scripts/sync-core.sh --source /path/to/scv-core [--dry-run]
  scripts/sync-core.sh --version 0.20.0 [--repository owner/repo] [--dry-run]
  scripts/sync-core.sh --latest [--repository owner/repo] [--dry-run]

The local form invokes the core repository's vendor tool directly. Release
forms download the immutable release artifact and its SHA-256 sidecar before
materializing the Claude Code profile. No plugin runtime path calls this tool.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      [[ $# -ge 2 ]] || { echo "ERROR: --source requires a directory" >&2; exit 2; }
      SOURCE_DIR=$2
      shift 2
      ;;
    --version)
      [[ $# -ge 2 ]] || { echo "ERROR: --version requires a version" >&2; exit 2; }
      VERSION=${2#v}
      shift 2
      ;;
    --latest)
      LATEST=1
      shift
      ;;
    --repository)
      [[ $# -ge 2 ]] || { echo "ERROR: --repository requires owner/repo" >&2; exit 2; }
      SOURCE_REPO=$2
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

mode_count=0
[[ -n "$SOURCE_DIR" ]] && mode_count=$((mode_count + 1))
[[ -n "$VERSION" ]] && mode_count=$((mode_count + 1))
(( LATEST )) && mode_count=$((mode_count + 1))
[[ "$mode_count" -eq 1 ]] || {
  echo "ERROR: choose exactly one of --source, --version, or --latest" >&2
  exit 2
}
[[ "$SOURCE_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || {
  echo "ERROR: --repository must be an owner/repository slug" >&2
  exit 2
}
[[ -f "$PROFILE" ]] || { echo "ERROR: missing adapter profile: $PROFILE" >&2; exit 1; }
[[ -f "$PLUGIN_MANIFEST" ]] || { echo "ERROR: missing Claude plugin manifest: $PLUGIN_MANIFEST" >&2; exit 1; }
[[ -f "$MARKETPLACE_MANIFEST" ]] || { echo "ERROR: missing Claude marketplace manifest: $MARKETPLACE_MANIFEST" >&2; exit 1; }

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/scv-claude-core-sync.XXXXXX")
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT
CANDIDATE="$TMP_DIR/scv-core"

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "ERROR: sha256sum or shasum is required" >&2
    return 1
  fi
}

download() {
  local url=$1 output=$2
  command -v curl >/dev/null 2>&1 || {
    echo "ERROR: curl is required for release sync" >&2
    return 1
  }
  curl --fail --location --silent --show-error \
    --retry 3 --retry-delay 1 \
    --output "$output" "$url"
}

set_wrapper_version() {
  local version_file=$1
  python3 - "$version_file" "$PLUGIN_MANIFEST" "$MARKETPLACE_MANIFEST" <<'PY'
import json
import pathlib
import re
import sys

version = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8").strip()
if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+(?:[.-][0-9A-Za-z.-]+)?", version):
    raise SystemExit(f"ERROR: invalid materialized core version: {version}")

plugin_path = pathlib.Path(sys.argv[2])
marketplace_path = pathlib.Path(sys.argv[3])

plugin = json.loads(plugin_path.read_text(encoding="utf-8"))
plugin["version"] = version

marketplace = json.loads(marketplace_path.read_text(encoding="utf-8"))
entries = [item for item in marketplace.get("plugins", []) if item.get("name") == "scv"]
if len(entries) != 1:
    raise SystemExit("ERROR: marketplace must contain exactly one scv entry")
entries[0]["version"] = version

plugin_path.write_text(
    json.dumps(plugin, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
marketplace_path.write_text(
    json.dumps(marketplace, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY
}

if [[ -n "$SOURCE_DIR" ]]; then
  SOURCE_DIR="$(cd "$SOURCE_DIR" 2>/dev/null && pwd)" || {
    echo "ERROR: local core source not found: $SOURCE_DIR" >&2
    exit 1
  }
  VENDOR_TOOL="$SOURCE_DIR/tools/vendor-core.sh"
  [[ -x "$VENDOR_TOOL" ]] || {
    echo "ERROR: local core vendor tool is missing or not executable: $VENDOR_TOOL" >&2
    exit 1
  }
  "$VENDOR_TOOL" --source "$SOURCE_DIR" --target "$CANDIDATE" --profile "$PROFILE"
else
  if (( LATEST )); then
    command -v gh >/dev/null 2>&1 || {
      echo "ERROR: gh is required to resolve --latest; pass --version instead" >&2
      exit 1
    }
    tag=$(gh api "repos/$SOURCE_REPO/releases/latest" --jq .tag_name)
    VERSION=${tag#v}
  fi
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || {
    echo "ERROR: invalid core version: $VERSION" >&2
    exit 1
  }

  asset="scv-core-v${VERSION}.tar.gz"
  base="https://github.com/${SOURCE_REPO}/releases/download/v${VERSION}"
  download "$base/$asset" "$TMP_DIR/$asset"
  download "$base/$asset.sha256" "$TMP_DIR/$asset.sha256"

  expected=$(awk 'NF {print $1; exit}' "$TMP_DIR/$asset.sha256")
  actual=$(sha256_file "$TMP_DIR/$asset")
  [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || {
    echo "ERROR: release checksum sidecar is invalid" >&2
    exit 1
  }
  expected_lower=$(printf '%s' "$expected" | tr '[:upper:]' '[:lower:]')
  actual_lower=$(printf '%s' "$actual" | tr '[:upper:]' '[:lower:]')
  [[ "$expected_lower" == "$actual_lower" ]] || {
    echo "ERROR: release artifact checksum mismatch" >&2
    exit 1
  }

  top="scv-core-v${VERSION}"
  python3 - "$TMP_DIR/$asset" "$top" <<'PY'
import pathlib
import sys
import tarfile

archive = pathlib.Path(sys.argv[1])
expected_root = sys.argv[2]
seen = set()

with tarfile.open(archive, mode="r:gz") as handle:
    for member in handle.getmembers():
        raw = member.name
        normalized = raw.rstrip("/")
        parts = normalized.split("/")
        if (
            not normalized
            or raw.startswith("/")
            or any(part in {"", ".", ".."} for part in parts)
            or parts[0] != expected_root
        ):
            raise SystemExit(
                f"ERROR: release archive contains an unsafe path: {raw}"
            )
        if normalized in seen:
            raise SystemExit(
                f"ERROR: release archive contains a duplicate path: {raw}"
            )
        seen.add(normalized)
        if not (member.isdir() or member.isreg()):
            raise SystemExit(
                f"ERROR: release archive contains a link or special file: {raw}"
            )

if expected_root not in seen:
    raise SystemExit(
        f"ERROR: release archive lacks expected top-level directory: {expected_root}"
    )
PY
  tar -xzf "$TMP_DIR/$asset" -C "$TMP_DIR"
  RELEASE_ROOT="$TMP_DIR/$top"
  VENDOR_TOOL="$RELEASE_ROOT/tools/vendor-core.sh"
  [[ -x "$VENDOR_TOOL" ]] || {
    echo "ERROR: release artifact lacks tools/vendor-core.sh" >&2
    exit 1
  }
  "$VENDOR_TOOL" \
    --source "$RELEASE_ROOT" \
    --target "$CANDIDATE" \
    --profile "$PROFILE" \
    --artifact-sha256 "$actual"
fi

[[ -x "$CANDIDATE/tools/verify-core.sh" ]] || {
  echo "ERROR: materialized core lacks tools/verify-core.sh" >&2
  exit 1
}
"$CANDIDATE/tools/verify-core.sh" --root "$CANDIDATE"
"$SCRIPT_DIR/verify-core.sh" \
  --vendor "$CANDIDATE" \
  --lock "$CANDIDATE/core.lock.json" \
  --no-projection

# Exercise the complete projection in an isolated wrapper-shaped directory
# before changing either the live pin or compatibility paths.
PROJECTION_STAGE="$TMP_DIR/wrapper-projection"
mkdir -p "$PROJECTION_STAGE"
cp -R -p "$REPO_ROOT/scripts" "$PROJECTION_STAGE/scripts"
cp -R -p "$REPO_ROOT/commands" "$PROJECTION_STAGE/commands"
cp -R -p "$REPO_ROOT/tests" "$PROJECTION_STAGE/tests"
"$SCRIPT_DIR/project-core.sh" \
  --vendor "$CANDIDATE" \
  --destination "$PROJECTION_STAGE"
"$SCRIPT_DIR/project-core.sh" \
  --vendor "$CANDIDATE" \
  --destination "$PROJECTION_STAGE" \
  --check

if (( DRY_RUN )); then
  echo "CORE_SYNC_DRY_RUN: yes"
  echo "CORE_VERSION: $(tr -d '[:space:]' < "$CANDIDATE/VERSION")"
  echo "CORE_COMMIT: $(tr -d '[:space:]' < "$CANDIDATE/SOURCE_COMMIT")"
  echo "PAYLOAD_SHA256: $(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["payload_sha256"])' "$CANDIDATE/core.lock.json")"
  echo "ARTIFACT_SHA256: $(python3 -c 'import json,sys; value=json.load(open(sys.argv[1]))["artifact_sha256"]; print("null" if value is None else value)' "$CANDIDATE/core.lock.json")"
  exit 0
fi

VENDOR_PARENT="$REPO_ROOT/vendor"
VENDOR_TARGET="$VENDOR_PARENT/scv-core"
NEXT_TARGET="$VENDOR_PARENT/.scv-core.next.$$"
BACKUP_TARGET="$VENDOR_PARENT/.scv-core.backup.$$"
LOCK_BACKUP="$TMP_DIR/core.lock.previous"
PLUGIN_BACKUP="$TMP_DIR/plugin.json.previous"
MARKETPLACE_BACKUP="$TMP_DIR/marketplace.json.previous"
HAD_VENDOR=0
mkdir -p "$VENDOR_PARENT"
mv "$CANDIDATE" "$NEXT_TARGET"
if [[ -e "$VENDOR_TARGET" ]]; then
  HAD_VENDOR=1
  mv "$VENDOR_TARGET" "$BACKUP_TARGET"
fi
[[ ! -f "$REPO_ROOT/core.lock" ]] || cp -p "$REPO_ROOT/core.lock" "$LOCK_BACKUP"
cp -p "$PLUGIN_MANIFEST" "$PLUGIN_BACKUP"
cp -p "$MARKETPLACE_MANIFEST" "$MARKETPLACE_BACKUP"

rollback() {
  local status=$?
  if [[ -e "$NEXT_TARGET" ]]; then
    rm -rf "$NEXT_TARGET"
  fi
  if [[ -e "$BACKUP_TARGET" ]]; then
    [[ ! -e "$VENDOR_TARGET" ]] || rm -rf "$VENDOR_TARGET"
    mv "$BACKUP_TARGET" "$VENDOR_TARGET"
  elif (( HAD_VENDOR == 0 )) && [[ -e "$VENDOR_TARGET" ]]; then
    rm -rf "$VENDOR_TARGET"
  fi
  if [[ -f "$LOCK_BACKUP" ]]; then
    cp -p "$LOCK_BACKUP" "$REPO_ROOT/core.lock"
  else
    rm -f "$REPO_ROOT/core.lock"
  fi
  cp -p "$PLUGIN_BACKUP" "$PLUGIN_MANIFEST"
  cp -p "$MARKETPLACE_BACKUP" "$MARKETPLACE_MANIFEST"
  if [[ -d "$VENDOR_TARGET/core" ]]; then
    "$SCRIPT_DIR/project-core.sh" \
      --vendor "$VENDOR_TARGET" \
      --destination "$REPO_ROOT" >/dev/null 2>&1 || true
  fi
  echo "ERROR: core sync rolled back after a failed projection or verification" >&2
  exit "$status"
}
trap rollback ERR

mv "$NEXT_TARGET" "$VENDOR_TARGET"
cp -p "$VENDOR_TARGET/core.lock.json" "$REPO_ROOT/.core.lock.next.$$"
mv "$REPO_ROOT/.core.lock.next.$$" "$REPO_ROOT/core.lock"
set_wrapper_version "$VENDOR_TARGET/VERSION"
"$SCRIPT_DIR/project-core.sh" --vendor "$VENDOR_TARGET" --destination "$REPO_ROOT"
"$SCRIPT_DIR/verify-core.sh"

trap - ERR
[[ ! -e "$BACKUP_TARGET" ]] || rm -rf "$BACKUP_TARGET"

echo "CORE_SYNCED: yes"
echo "CORE_VERSION: $(tr -d '[:space:]' < "$VENDOR_TARGET/VERSION")"
echo "CORE_COMMIT: $(tr -d '[:space:]' < "$VENDOR_TARGET/SOURCE_COMMIT")"
