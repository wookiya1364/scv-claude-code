#!/usr/bin/env bash
# Verify the pinned core payload, lock, Claude profile, and generated projection.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR_ROOT="$REPO_ROOT/vendor/scv-core"
LOCK_FILE="$REPO_ROOT/core.lock"
CHECK_PROJECTION=1
SUPPORTED_CORE_API=1

usage() {
  cat <<'EOF'
Usage: scripts/verify-core.sh [--vendor DIR] [--lock FILE] [--no-projection]
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vendor)
      [[ $# -ge 2 ]] || { echo "ERROR: --vendor requires a directory" >&2; exit 2; }
      VENDOR_ROOT=$2
      shift 2
      ;;
    --lock)
      [[ $# -ge 2 ]] || { echo "ERROR: --lock requires a file" >&2; exit 2; }
      LOCK_FILE=$2
      shift 2
      ;;
    --no-projection)
      CHECK_PROJECTION=0
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

[[ -d "$VENDOR_ROOT" ]] || { echo "ERROR: vendored core not found: $VENDOR_ROOT" >&2; exit 1; }
[[ -f "$LOCK_FILE" ]] || { echo "ERROR: root core.lock not found: $LOCK_FILE" >&2; exit 1; }

for required in \
  VERSION CORE_API TEMPLATE_VERSION SOURCE_COMMIT SOURCE_DATE SOURCE_INFO \
  core/manifest.json core/actions.json core/host-profile.env \
  core-manifest.json SHA256SUMS core.lock.json; do
  [[ -f "$VENDOR_ROOT/$required" ]] || {
    echo "ERROR: vendored core is missing $required" >&2
    exit 1
  }
done

cmp -s "$LOCK_FILE" "$VENDOR_ROOT/core.lock.json" || {
  echo "ERROR: root core.lock differs from vendor/scv-core/core.lock.json" >&2
  exit 1
}

actual_api=$(tr -d '[:space:]' < "$VENDOR_ROOT/CORE_API")
[[ "$actual_api" == "$SUPPORTED_CORE_API" ]] || {
  echo "ERROR: unsupported SCV Core API $actual_api (wrapper supports $SUPPORTED_CORE_API)" >&2
  exit 1
}

if [[ -x "$VENDOR_ROOT/tools/verify-core.sh" ]]; then
  "$VENDOR_ROOT/tools/verify-core.sh" --root "$VENDOR_ROOT"
else
  echo "ERROR: vendored core verifier is missing or not executable" >&2
  exit 1
fi

python3 - \
  "$LOCK_FILE" \
  "$VENDOR_ROOT" \
  "$REPO_ROOT/adapter/claude-code.env" \
  "$REPO_ROOT/host-profile.env" \
  "$CHECK_PROJECTION" <<'PY'
import hashlib
import json
import pathlib
import re
import sys

lock_path = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2])
source_profile_path = pathlib.Path(sys.argv[3])
projected_profile_path = pathlib.Path(sys.argv[4])
check_projection = sys.argv[5] == "1"

def read_profile(path):
    values = {}
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise SystemExit(f"ERROR: malformed host profile line in {path}: {raw_line}")
        key, value = line.split("=", 1)
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
            value = value[1:-1]
        values[key] = value
    return values

source_profile = read_profile(source_profile_path)
vendored_profile = read_profile(root / "core" / "host-profile.env")
if source_profile != vendored_profile:
    raise SystemExit("ERROR: vendored host profile differs semantically from adapter/claude-code.env")
if check_projection:
    if not projected_profile_path.is_file():
        raise SystemExit("ERROR: root host-profile.env projection is absent")
    if read_profile(projected_profile_path) != vendored_profile:
        raise SystemExit("ERROR: root host-profile.env projection is stale")

with lock_path.open(encoding="utf-8") as handle:
    lock = json.load(handle)
with (root / "core" / "actions.json").open(encoding="utf-8") as handle:
    catalog = json.load(handle)
with (root / "core-manifest.json").open(encoding="utf-8") as handle:
    manifest = json.load(handle)

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def normalize_repository(value):
    value = str(value).strip().rstrip("/")
    if value.endswith(".git"):
        value = value[:-4]
    if value.startswith("git@github.com:"):
        value = "https://github.com/" + value.removeprefix("git@github.com:")
    return value

source_info_lines = (root / "SOURCE_INFO").read_text(encoding="utf-8").splitlines()
source_repositories = [
    line.split(":", 1)[1].strip()
    for line in source_info_lines
    if line.startswith("source_repository:")
]
if len(source_repositories) != 1:
    raise SystemExit("ERROR: SOURCE_INFO must contain exactly one source_repository")
source_repository = normalize_repository(source_repositories[0])

required = {
    "schema_version",
    "core_version",
    "core_api",
    "template_version",
    "source_repository",
    "source_commit",
    "source_manifest_sha256",
    "source_payload_sha256",
    "manifest_sha256",
    "payload_sha256",
    "artifact_sha256",
    "vendored_at",
}
missing = sorted(required - set(lock))
if missing:
    raise SystemExit(f"ERROR: core.lock missing fields: {', '.join(missing)}")

if lock["schema_version"] != 1:
    raise SystemExit("ERROR: unsupported core.lock schema_version")
if str(lock["core_version"]) != (root / "VERSION").read_text().strip():
    raise SystemExit("ERROR: core.lock core_version does not match VERSION")
if str(lock["core_api"]) != (root / "CORE_API").read_text().strip():
    raise SystemExit("ERROR: core.lock core_api does not match CORE_API")
if str(lock["template_version"]) != (root / "TEMPLATE_VERSION").read_text().strip():
    raise SystemExit("ERROR: core.lock template_version does not match TEMPLATE_VERSION")
if str(lock["source_commit"]) != (root / "SOURCE_COMMIT").read_text().strip():
    raise SystemExit("ERROR: core.lock source_commit does not match SOURCE_COMMIT")
if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", str(lock["source_commit"])):
    raise SystemExit("ERROR: core.lock source_commit is not a full commit id")
for digest_field in (
    "source_manifest_sha256",
    "source_payload_sha256",
    "manifest_sha256",
    "payload_sha256",
):
    if not re.fullmatch(r"[0-9a-f]{64}", str(lock[digest_field])):
        raise SystemExit(f"ERROR: core.lock {digest_field} is not SHA-256")
artifact_sha256 = lock["artifact_sha256"]
if artifact_sha256 is not None and not re.fullmatch(r"[0-9a-f]{64}", str(artifact_sha256)):
    raise SystemExit("ERROR: core.lock artifact_sha256 is neither null nor SHA-256")
if normalize_repository(lock["source_repository"]) != source_repository:
    raise SystemExit("ERROR: core.lock source_repository does not match SOURCE_INFO")
if str(manifest.get("version")) != (root / "VERSION").read_text().strip():
    raise SystemExit("ERROR: core manifest version does not match VERSION")
if str(manifest.get("core_api")) != (root / "CORE_API").read_text().strip():
    raise SystemExit("ERROR: core manifest core_api does not match CORE_API")
if str(manifest.get("template_version")) != (root / "TEMPLATE_VERSION").read_text().strip():
    raise SystemExit("ERROR: core manifest template_version does not match TEMPLATE_VERSION")
if normalize_repository(manifest.get("source_repository", "")) != source_repository:
    raise SystemExit("ERROR: core manifest repository does not match SOURCE_INFO")
if str(manifest.get("source_commit")) != str(lock["source_commit"]):
    raise SystemExit("ERROR: core manifest commit does not match core.lock")
if str(manifest.get("profile_id")) != str(vendored_profile.get("SCV_HOST_ID")):
    raise SystemExit("ERROR: core manifest profile_id does not match the host profile")
if lock["manifest_sha256"] != digest(root / "core-manifest.json"):
    raise SystemExit("ERROR: core.lock manifest_sha256 does not match core-manifest.json")
if lock["payload_sha256"] != digest(root / "SHA256SUMS"):
    raise SystemExit("ERROR: core.lock payload_sha256 does not match SHA256SUMS")

if check_projection:
    wrapper_root = projected_profile_path.parent
    wrapper_version = (wrapper_root / "VERSION").read_text().strip()
    template_version = (wrapper_root / "TEMPLATE_VERSION").read_text().strip()
    if not re.fullmatch(
        r"[0-9]+\.[0-9]+\.[0-9]+(?:[.-][0-9A-Za-z.-]+)?",
        wrapper_version,
    ):
        raise SystemExit("ERROR: wrapper VERSION is not a supported release version")
    if template_version != str(lock["template_version"]):
        raise SystemExit("ERROR: wrapper TEMPLATE_VERSION does not match pinned template version")

    with (wrapper_root / ".claude-plugin" / "plugin.json").open(encoding="utf-8") as handle:
        plugin = json.load(handle)
    if str(plugin.get("version")) != wrapper_version:
        raise SystemExit("ERROR: Claude plugin version does not match wrapper VERSION")

    with (wrapper_root / ".claude-plugin" / "marketplace.json").open(encoding="utf-8") as handle:
        marketplace = json.load(handle)
    entries = [item for item in marketplace.get("plugins", []) if item.get("name") == "scv"]
    if len(entries) != 1:
        raise SystemExit("ERROR: marketplace must contain exactly one scv entry")
    marketplace_version = entries[0].get("version")
    if str(marketplace_version) != wrapper_version:
        raise SystemExit("ERROR: marketplace scv version differs from the plugin manifest")

    state_adapter = wrapper_root / "adapter" / "scripts" / "state-index.sh"
    if not state_adapter.is_file():
        raise SystemExit("ERROR: Claude state-index delegation shim is absent")
    state_adapter_text = state_adapter.read_text(encoding="utf-8")
    required_delegation = (
        'CORE_STATE_INDEX="$WRAPPER_ROOT/vendor/scv-core/core/scripts/state-index.sh"',
        'exec "$CORE_STATE_INDEX" "$@"',
    )
    for expected_line in required_delegation:
        if expected_line not in state_adapter_text.splitlines():
            raise SystemExit(
                "ERROR: Claude state-index adapter does not delegate argv "
                "unchanged to the vendored Core resolver"
            )
    for duplicate_resolver_token in (
        "SCV:HOST-POINTER",
        "STATE_INDEX_CONFLICT:",
        "active_legacy",
        "is_pointer()",
    ):
        if duplicate_resolver_token in state_adapter_text:
            raise SystemExit(
                "ERROR: Claude state-index adapter duplicates Core resolver "
                f"semantics: {duplicate_resolver_token}"
            )

actions = catalog.get("actions")
if isinstance(actions, dict):
    action_items = actions
elif isinstance(actions, list):
    action_items = {item.get("id"): item for item in actions}
else:
    raise SystemExit("ERROR: core/actions.json has no actions catalog")

expected = {
    "codegen", "deck", "handoff", "help", "install-deps", "promote",
    "regression", "report", "set-models", "status", "sync", "update",
    "work", "workspace",
}
if set(action_items) != expected:
    raise SystemExit(
        "ERROR: action catalog mismatch: "
        f"expected={sorted(expected)} actual={sorted(action_items)}"
    )
for action in ("update", "set-models"):
    if action_items[action].get("owner") != "adapter":
        raise SystemExit(f"ERROR: {action} must remain adapter-owned")
PY

if (( CHECK_PROJECTION )); then
  "$SCRIPT_DIR/project-core.sh" --vendor "$VENDOR_ROOT" --destination "$REPO_ROOT" --check
fi

echo "CORE_LOCK_OK: yes"
echo "CORE_VERSION: $(tr -d '[:space:]' < "$VENDOR_ROOT/VERSION")"
echo "CORE_API: $actual_api"
echo "TEMPLATE_VERSION: $(tr -d '[:space:]' < "$VENDOR_ROOT/TEMPLATE_VERSION")"
