#!/usr/bin/env bash
# update.sh — SCV plugin version diagnostic (v0.11.2+).
#
# Compares the installed plugin version (from plugin.json) against the latest
# GitHub release tag (via gh CLI). Read-only — does NOT modify any files.
#
# Output (stdout, parseable):
#   INSTALLED_VERSION: <x.y.z>
#   MARKETPLACE_NAME: <name>            (from marketplace.json root "name")
#   PLUGIN_NAME: <name>                  (from plugin.json "name")
#   LATEST_VERSION: <x.y.z> | (unavailable — ...)
#   UP_TO_DATE: yes | no | unknown
#
# Exit code: 0 always (read-only diagnostic).

set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PLUGIN_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
PLUGIN_JSON="$PLUGIN_ROOT/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$PLUGIN_ROOT/.claude-plugin/marketplace.json"

# --- Installed version (plugin.json) ---
INSTALLED_VERSION="(not found)"
if [[ -f "$PLUGIN_JSON" ]]; then
  v=$(grep -m1 '"version"' "$PLUGIN_JSON" 2>/dev/null | sed -E 's/.*"version":[[:space:]]*"([^"]+)".*/\1/')
  [[ -n "$v" ]] && INSTALLED_VERSION="$v"
fi
echo "INSTALLED_VERSION: $INSTALLED_VERSION"

# --- Plugin + marketplace names ---
PLUGIN_NAME="(unknown)"
MARKETPLACE_NAME="(unknown)"
if [[ -f "$PLUGIN_JSON" ]]; then
  n=$(grep -m1 '"name"' "$PLUGIN_JSON" 2>/dev/null | sed -E 's/.*"name":[[:space:]]*"([^"]+)".*/\1/')
  [[ -n "$n" ]] && PLUGIN_NAME="$n"
fi
if [[ -f "$MARKETPLACE_JSON" ]]; then
  # Root "name" is the first "name" key in marketplace.json (top-level)
  n=$(grep -m1 '"name"' "$MARKETPLACE_JSON" 2>/dev/null | sed -E 's/.*"name":[[:space:]]*"([^"]+)".*/\1/')
  [[ -n "$n" ]] && MARKETPLACE_NAME="$n"
fi
echo "MARKETPLACE_NAME: $MARKETPLACE_NAME"
echo "PLUGIN_NAME: $PLUGIN_NAME"

# --- Latest release via gh CLI ---
LATEST_VERSION=""
REPO=""
if [[ -f "$PLUGIN_JSON" ]]; then
  hp=$(grep -m1 '"homepage"' "$PLUGIN_JSON" 2>/dev/null | sed -E 's/.*"homepage":[[:space:]]*"([^"]+)".*/\1/')
  REPO=$(printf '%s' "$hp" | sed -E 's|https?://github.com/||; s|/$||')
fi

if [[ -z "$REPO" ]]; then
  echo "LATEST_VERSION: (unavailable — homepage not parseable from plugin.json)"
  echo "UP_TO_DATE: unknown"
elif ! command -v gh >/dev/null 2>&1; then
  echo "LATEST_VERSION: (unavailable — gh CLI not installed; check https://github.com/$REPO/releases manually)"
  echo "UP_TO_DATE: unknown"
else
  tag=$(gh release view --repo "$REPO" --json tagName -q '.tagName' 2>/dev/null | sed 's/^v//')
  if [[ -z "$tag" ]]; then
    echo "LATEST_VERSION: (unavailable — gh release view failed; run 'gh auth status' to check auth, or visit https://github.com/$REPO/releases)"
    echo "UP_TO_DATE: unknown"
  else
    echo "LATEST_VERSION: $tag"
    if [[ "$INSTALLED_VERSION" == "$tag" ]]; then
      echo "UP_TO_DATE: yes"
    else
      echo "UP_TO_DATE: no"
    fi
  fi
fi

exit 0
