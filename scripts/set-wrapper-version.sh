#!/usr/bin/env bash
# Set the Claude wrapper release version in every place that records it.
#
# The version lives in three files, and a release that updates only some of them
# ships a plugin whose manifest disagrees with its own VERSION. Core versions
# (vendor/scv-core/**, core.lock, TEMPLATE_VERSION) are never touched here —
# those belong to the Core sync.
#
# The READMEs used to be a fourth place: each carried the release version in one
# prose line, and this script rewrote all three. That line is gone — the badge at
# the top of each README reads the latest release from GitHub instead — so the
# rewrite could never match and the script exited non-zero on every release, after
# it had already written the three version files. 0.45.0 and 0.46.0 both shipped
# through that error. Nothing here touches a README any more, and the contract
# test runs this script so the same rot cannot come back silently.

set -euo pipefail

[[ $# -eq 1 ]] || {
  echo "usage: scripts/set-wrapper-version.sh <X.Y.Z>" >&2
  exit 2
}
VERSION_VALUE="$1"
[[ "$VERSION_VALUE" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || {
  echo "error: invalid wrapper version: $VERSION_VALUE" >&2
  exit 2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

printf '%s\n' "$VERSION_VALUE" > "$REPO_ROOT/VERSION"

python3 - "$REPO_ROOT" "$VERSION_VALUE" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
value = sys.argv[2]

# plugin.json — a flat "version" field.
plugin = root / ".claude-plugin" / "plugin.json"
data = json.loads(plugin.read_text())
data["version"] = value
plugin.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")

# marketplace.json — the version sits on the scv plugin entry.
market = root / ".claude-plugin" / "marketplace.json"
data = json.loads(market.read_text())
found = False
for entry in data.get("plugins", []):
    if entry.get("name") == "scv":
        entry["version"] = value
        found = True
if not found:
    raise SystemExit("error: marketplace.json has no plugin named 'scv'")
market.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
PY

echo "WRAPPER_VERSION: $VERSION_VALUE"
