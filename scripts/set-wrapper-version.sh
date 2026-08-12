#!/usr/bin/env bash
# Set the Claude wrapper release version in every place that records it.
#
# The version lives in five files, and a release that updates only some of them
# ships a plugin whose manifest disagrees with its own VERSION. Core versions
# (vendor/scv-core/**, core.lock, TEMPLATE_VERSION) are never touched here —
# those belong to the Core sync.

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
import re
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

# READMEs carry the release version in one prose line each. The three phrasings
# differ per language, so match the backticked version that follows each lead-in.
readmes = {
    "README.md": r"(release is )`[^`]+`",
    "README.ko.md": r"(release는\s*\n)`[^`]+`",
    "README.ja.md": r"(release\s*\nは )`[^`]+`",
}
for name, pattern in readmes.items():
    path = root / name
    text = path.read_text()
    new_text, count = re.subn(pattern, lambda m: f"{m.group(1)}`{value}`", text, count=1)
    if count != 1:
        raise SystemExit(f"error: could not find the release version line in {name}")
    path.write_text(new_text)
PY

echo "WRAPPER_VERSION: $VERSION_VALUE"
