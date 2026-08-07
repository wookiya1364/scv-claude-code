#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: verify-core.sh [--root EXPORT_ROOT]" >&2
}

ROOT="."
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done
ROOT="$(cd "$ROOT" && pwd -P)"

for path in VERSION CORE_API TEMPLATE_VERSION core/manifest.json core/actions.json \
  core/contracts/host-profile.md core/protocols core/scripts core/template \
  core/DeckUI core/assets core/docs core/tests core-manifest.json SHA256SUMS; do
  [[ -e "$ROOT/$path" ]] || { echo "missing core artifact: $path" >&2; exit 1; }
done

VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
CORE_API="$(tr -d '[:space:]' < "$ROOT/CORE_API")"
TEMPLATE_VERSION="$(tr -d '[:space:]' < "$ROOT/TEMPLATE_VERSION")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "invalid VERSION: $VERSION" >&2; exit 1; }
[[ "$CORE_API" == "1" ]] || { echo "unsupported CORE_API: $CORE_API" >&2; exit 1; }
[[ "$TEMPLATE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || { echo "invalid TEMPLATE_VERSION: $TEMPLATE_VERSION" >&2; exit 1; }

for forbidden_dir in node_modules dist dist-deck coverage .vite .cache; do
  found="$(find "$ROOT/core" "$ROOT/tools" -type d -name "$forbidden_dir" -print -quit)"
  [[ -z "$found" ]] \
    || { echo "development directory leaked into export: ${found#"$ROOT/"}" >&2; exit 1; }
done

while IFS= read -r generated_deck; do
  rel="${generated_deck#"$ROOT/"}"
  case "$rel" in
    core/DeckUI/src/deck/decks/demo-prd/deck.json|\
    core/DeckUI/src/deck/decks/refund/deck.json) ;;
    *) echo "generated DeckUI deck leaked into export: $rel" >&2; exit 1 ;;
  esac
done < <(
  find "$ROOT/core/DeckUI/src/deck/decks" -mindepth 2 -maxdepth 2 \
    -type f -name deck.json 2>/dev/null | LC_ALL=C sort
)

while IFS= read -r link; do
  target="$(readlink "$ROOT/$link")"
  [[ "$target" != /* ]] || { echo "absolute symlink is forbidden: $link" >&2; exit 1; }
  [[ ! -d "$ROOT/$link" ]] \
    || { echo "directory symlink is forbidden: $link -> $target" >&2; exit 1; }
  link_dir="$(dirname "$ROOT/$link")"
  target_dir="$(cd "$link_dir/$(dirname "$target")" 2>/dev/null && pwd -P)" \
    || { echo "broken symlink: $link" >&2; exit 1; }
  resolved="$target_dir/$(basename "$target")"
  case "$resolved" in
    "$ROOT"|"$ROOT"/*) ;;
    *) echo "symlink escapes export root: $link -> $target" >&2; exit 1 ;;
  esac
  [[ -e "$resolved" ]] || { echo "broken symlink: $link" >&2; exit 1; }
done < <(cd "$ROOT" && find core tools -type l | LC_ALL=C sort)

if command -v sha256sum >/dev/null 2>&1; then
  (cd "$ROOT" && sha256sum -c SHA256SUMS >/dev/null)
elif command -v shasum >/dev/null 2>&1; then
  (cd "$ROOT" && shasum -a 256 -c SHA256SUMS >/dev/null)
else
  echo "sha256sum or shasum is required" >&2
  exit 1
fi

action_count="$(grep -c '"id":' "$ROOT/core/actions.json")"
protocol_count="$(find "$ROOT/core/protocols" -type f -name '*.md' | wc -l | tr -d '[:space:]')"
[[ "$action_count" -eq 15 ]] || { echo "expected 15 actions, got $action_count" >&2; exit 1; }
[[ "$protocol_count" -eq 15 ]] || { echo "expected 15 protocols, got $protocol_count" >&2; exit 1; }
grep -A4 '"id": "update"' "$ROOT/core/actions.json" | grep -q '"owner": "adapter"'
grep -A4 '"id": "set-models"' "$ROOT/core/actions.json" | grep -q '"owner": "adapter"'
[[ ! -e "$ROOT/core/scripts/update.sh" && ! -e "$ROOT/core/scripts/apply-model-policy.sh" ]] \
  || { echo "adapter-owned entrypoint leaked into core scripts" >&2; exit 1; }

if [[ -f "$ROOT/core/host-profile.env" ]]; then
  "$ROOT/tools/validate-host-profile.sh" --profile "$ROOT/core/host-profile.env" >/dev/null
fi

if [[ -f "$ROOT/core.lock.json" ]]; then
  artifact_value="$(sed -n 's/^[[:space:]]*"artifact_sha256":[[:space:]]*//p' "$ROOT/core.lock.json" | sed 's/,[[:space:]]*$//' | head -1)"
  [[ "$artifact_value" == "null" || "$artifact_value" =~ ^\"[0-9a-f]{64}\"$ ]] \
    || { echo "invalid artifact_sha256 in core.lock.json" >&2; exit 1; }
fi

echo "SCV Core verified: v$VERSION (API $CORE_API, 15 actions)"
