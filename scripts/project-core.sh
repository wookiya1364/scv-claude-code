#!/usr/bin/env bash
# Materialize the pinned core payload at the legacy Claude plugin paths.
#
# Existing Claude commands and downstream tests rely on root-level scripts/,
# template/, DeckUI/, and assets/.  The canonical copies live under
# vendor/scv-core/core; this script makes those paths deterministic generated
# projections while preserving the adapter-owned command frontmatter and
# scripts.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR_ROOT="$REPO_ROOT/vendor/scv-core"
DESTINATION="$REPO_ROOT"
MODE=write

usage() {
  cat <<'EOF'
Usage:
  scripts/project-core.sh [--vendor DIR] [--destination DIR] [--check]

Options:
  --vendor DIR       Materialized SCV Core export (default: vendor/scv-core)
  --destination DIR  Wrapper root to update (default: repository root)
  --check            Compare only; do not write
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --vendor)
      [[ $# -ge 2 ]] || { echo "ERROR: --vendor requires a directory" >&2; exit 2; }
      VENDOR_ROOT=$2
      shift 2
      ;;
    --destination)
      [[ $# -ge 2 ]] || { echo "ERROR: --destination requires a directory" >&2; exit 2; }
      DESTINATION=$2
      shift 2
      ;;
    --check)
      MODE=check
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

VENDOR_ROOT="$(cd "$VENDOR_ROOT" 2>/dev/null && pwd)" || {
  echo "ERROR: vendor root not found: $VENDOR_ROOT" >&2
  exit 1
}
DESTINATION="$(cd "$DESTINATION" 2>/dev/null && pwd)" || {
  echo "ERROR: destination not found: $DESTINATION" >&2
  exit 1
}
CORE_ROOT="$VENDOR_ROOT/core"

for required in \
  "$CORE_ROOT/scripts" \
  "$CORE_ROOT/template" \
  "$CORE_ROOT/DeckUI" \
  "$CORE_ROOT/assets" \
  "$CORE_ROOT/integrations/loop-runner.md" \
  "$CORE_ROOT/protocols" \
  "$CORE_ROOT/tests" \
  "$VENDOR_ROOT/TEMPLATE_VERSION"; do
  [[ -e "$required" ]] || {
    echo "ERROR: incomplete vendored core; missing ${required#"$VENDOR_ROOT/"}" >&2
    exit 1
  }
done

ADAPTER_SCRIPTS='
apply-model-policy.sh
hydrate.sh
project-core.sh
sync-core.sh
sync.sh
update.sh
verify-core.sh
'
ADAPTER_ACTIONS='
set-models
update
'
ADAPTER_TESTS='
test-apply-model-policy.sh
test-core-contract.sh
test-state-adapter.sh
'
FAILURES=0

is_adapter_script() {
  case "$ADAPTER_SCRIPTS" in
    *$'\n'"$1"$'\n'*) return 0 ;;
    *) return 1 ;;
  esac
}

is_adapter_action() {
  case "$ADAPTER_ACTIONS" in
    *$'\n'"$1"$'\n'*) return 0 ;;
    *) return 1 ;;
  esac
}

is_adapter_test() {
  case "$ADAPTER_TESTS" in
    *$'\n'"$1"$'\n'*) return 0 ;;
    *) return 1 ;;
  esac
}

compare_or_copy_file() {
  local source=$1 target=$2 label=$3
  if [[ "$MODE" == check ]]; then
    if [[ ! -f "$target" ]] || ! cmp -s "$source" "$target"; then
      echo "PROJECTION_MISMATCH: $label"
      FAILURES=$((FAILURES + 1))
    fi
    return
  fi
  mkdir -p "$(dirname "$target")"
  cp -p "$source" "$target"
}

compare_or_replace_tree() {
  local source=$1 target=$2 label=$3 parent staged backup
  if [[ "$MODE" == check ]]; then
    if [[ ! -d "$target" ]] || ! diff -qr "$source" "$target" >/dev/null 2>&1; then
      echo "PROJECTION_MISMATCH: $label"
      FAILURES=$((FAILURES + 1))
    fi
    return
  fi

  parent=$(dirname "$target")
  mkdir -p "$parent"
  staged=$(mktemp -d "$parent/.scv-projection.XXXXXX")
  cp -R -p "$source/." "$staged/"
  if [[ -e "$target" ]]; then
    backup="$parent/.scv-projection-backup.$$.${RANDOM}"
    mv "$target" "$backup"
    if mv "$staged" "$target"; then
      rm -rf "$backup"
    else
      mv "$backup" "$target"
      rm -rf "$staged"
      return 1
    fi
  else
    mv "$staged" "$target"
  fi
}

compare_or_replace_deckui() {
  local source=$1 target=$2 parent preserve name
  if [[ "$MODE" == check ]]; then
    if [[ ! -d "$target" ]] || \
      ! diff -qr -x node_modules -x dist-deck "$source" "$target" >/dev/null 2>&1; then
      echo "PROJECTION_MISMATCH: DeckUI"
      FAILURES=$((FAILURES + 1))
    fi
    return
  fi

  parent=$(dirname "$target")
  preserve=$(mktemp -d "$parent/.scv-deck-runtime.XXXXXX")
  for name in node_modules dist-deck; do
    if [[ -e "$target/$name" ]]; then
      mv "$target/$name" "$preserve/$name"
    fi
  done
  if ! compare_or_replace_tree "$source" "$target" DeckUI; then
    for name in node_modules dist-deck; do
      [[ ! -e "$preserve/$name" ]] || mv "$preserve/$name" "$target/$name"
    done
    rmdir "$preserve" 2>/dev/null || true
    return 1
  fi
  for name in node_modules dist-deck; do
    if [[ -e "$preserve/$name" ]]; then
      [[ ! -e "$target/$name" ]] || rm -rf "$target/$name"
      mv "$preserve/$name" "$target/$name"
    fi
  done
  rmdir "$preserve"
}

# Core shell entrypoints retain their long-standing root paths. Adapter scripts
# are deliberately excluded.
while IFS= read -r -d '' source; do
  rel=${source#"$CORE_ROOT/scripts/"}
  if [[ "$rel" != */* ]] && is_adapter_script "$rel"; then
    continue
  fi
  compare_or_copy_file "$source" "$DESTINATION/scripts/$rel" "scripts/$rel"
done < <(find "$CORE_ROOT/scripts" -type f -print0)

# A deleted core file must disappear from the compatibility projection too.
# Only the explicit adapter allow-list may exist without a core counterpart.
while IFS= read -r -d '' projected; do
  rel=${projected#"$DESTINATION/scripts/"}
  if [[ "$rel" != */* ]] && is_adapter_script "$rel"; then
    continue
  fi
  if [[ ! -f "$CORE_ROOT/scripts/$rel" ]]; then
    if [[ "$MODE" == check ]]; then
      echo "PROJECTION_EXTRA: scripts/$rel"
      FAILURES=$((FAILURES + 1))
    else
      rm -f "$projected"
    fi
  fi
done < <(find "$DESTINATION/scripts" -type f -print0)

# New hydrate trees are host-neutral and contain only scv/SCV.md.
# Compatibility pointers are created only when an existing legacy file is
# explicitly migrated, never as part of the template.
compare_or_replace_tree "$CORE_ROOT/template" "$DESTINATION/template" template
compare_or_replace_deckui "$CORE_ROOT/DeckUI" "$DESTINATION/DeckUI"
compare_or_replace_tree "$CORE_ROOT/assets" "$DESTINATION/assets" assets
compare_or_replace_tree "$CORE_ROOT/protocols" "$DESTINATION/protocols" protocols

# Shared tests are projected too; wrapper-contract and Claude model-policy tests
# remain adapter-owned.
while IFS= read -r -d '' source; do
  rel=${source#"$CORE_ROOT/tests/"}
  if [[ "$rel" != */* ]] && is_adapter_test "$rel"; then
    continue
  fi
  compare_or_copy_file "$source" "$DESTINATION/tests/$rel" "tests/$rel"
done < <(find "$CORE_ROOT/tests" -type f -print0)

while IFS= read -r -d '' projected; do
  rel=${projected#"$DESTINATION/tests/"}
  if [[ "$rel" != */* ]] && is_adapter_test "$rel"; then
    continue
  fi
  if [[ ! -f "$CORE_ROOT/tests/$rel" ]]; then
    if [[ "$MODE" == check ]]; then
      echo "PROJECTION_EXTRA: tests/$rel"
      FAILURES=$((FAILURES + 1))
    else
      rm -f "$projected"
    fi
  fi
done < <(find "$DESTINATION/tests" -type f -print0)

# Ralph's host path is adapter-specific, but its protocol body is core-owned
# and deliberately lives outside template/ so hydrate never leaks it into a
# project root.
compare_or_copy_file \
  "$CORE_ROOT/integrations/loop-runner.md" \
  "$DESTINATION/ralph-template-scv.md" \
  ralph-template-scv.md

# Root VERSION follows the pinned core/wrapper release. TEMPLATE_VERSION remains
# independently versioned and is what hydrate/sync stamp into project state.
compare_or_copy_file \
  "$VENDOR_ROOT/VERSION" \
  "$DESTINATION/VERSION" \
  VERSION
compare_or_copy_file \
  "$VENDOR_ROOT/TEMPLATE_VERSION" \
  "$DESTINATION/TEMPLATE_VERSION" \
  TEMPLATE_VERSION
compare_or_copy_file \
  "$CORE_ROOT/host-profile.env" \
  "$DESTINATION/host-profile.env" \
  host-profile.env

# A command's YAML frontmatter is owned by the Claude adapter. Its protocol
# body is generated from core. update and set-models are wholly adapter-owned.
while IFS= read -r protocol; do
  action=$(basename "$protocol" .md)
  is_adapter_action "$action" && continue
  command="$DESTINATION/commands/$action.md"
  [[ -f "$command" ]] || {
    echo "ERROR: missing Claude command adapter: commands/$action.md" >&2
    exit 1
  }

  expected=$(mktemp)
  awk '
    NR == 1 && $0 == "---" { print; in_frontmatter=1; next }
    in_frontmatter { print; if ($0 == "---") exit }
  ' "$command" > "$expected"
  printf '\n' >> "$expected"
  cat "$protocol" >> "$expected"

  if [[ "$MODE" == check ]]; then
    if ! cmp -s "$expected" "$command"; then
      echo "PROJECTION_MISMATCH: commands/$action.md (core body)"
      FAILURES=$((FAILURES + 1))
    fi
  else
    mv "$expected" "$command"
    expected=
  fi
  [[ -z "${expected:-}" ]] || rm -f "$expected"
done < <(find "$CORE_ROOT/protocols" -maxdepth 1 -type f -name '*.md' | sort)

if [[ "$MODE" == check ]]; then
  if (( FAILURES > 0 )); then
    echo "PROJECTION_OK: no"
    exit 1
  fi
  echo "PROJECTION_OK: yes"
else
  echo "PROJECTED_CORE_VERSION: $(tr -d '[:space:]' < "$VENDOR_ROOT/VERSION")"
  echo "PROJECTED_TEMPLATE_VERSION: $(tr -d '[:space:]' < "$VENDOR_ROOT/TEMPLATE_VERSION")"
fi
