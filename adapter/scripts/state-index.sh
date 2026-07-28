#!/usr/bin/env bash
# Resolve or explicitly migrate SCV's shared project-state index.
# Default mode is strictly read-only.
set -euo pipefail

PROJECT_DIR=.
MIGRATE=0
DRY_RUN=0
CORE_SYNC_SUCCEEDED=0

usage() {
  cat <<'EOF'
Usage: adapter/scripts/state-index.sh [--project-dir DIR] [--migrate] [--dry-run]

Default mode only reports canonical, legacy, missing, or conflicting state.
--migrate is an explicit operation: it copies verified legacy state to SCV.md,
backs up active legacy files, and replaces only those existing files with
marker-bearing pointers. A missing other-host pointer is never created.

--core-sync-succeeded is an internal adapter flag. It permits pointer
finalization after a successful core sync has advanced the canonical SCV.md
copied from already-verified legacy state.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir)
      [[ $# -ge 2 ]] || { echo "ERROR: --project-dir requires a path" >&2; exit 2; }
      PROJECT_DIR=$2
      shift 2
      ;;
    --migrate)
      MIGRATE=1
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --core-sync-succeeded)
      CORE_SYNC_SUCCEEDED=1
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

PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd)" || {
  echo "ERROR: project directory not found: $PROJECT_DIR" >&2
  exit 2
}
SCV_DIR="$PROJECT_DIR/scv"
CANONICAL="$SCV_DIR/SCV.md"

is_pointer() {
  grep -q '<!-- SCV:HOST-POINTER target=SCV.md -->' "$1" 2>/dev/null
}

active_legacy=()
pointer_legacy=()
for name in CLAUDE.md CODEX.md; do
  file="$SCV_DIR/$name"
  [[ -f "$file" ]] || continue
  if is_pointer "$file"; then
    pointer_legacy+=("$file")
  else
    active_legacy+=("$file")
  fi
done

if [[ ! -f "$CANONICAL" ]] && (( ${#pointer_legacy[@]} > 0 )); then
  echo "STATE_INDEX_BROKEN_POINTER:"
  printf '  %s\n' "${pointer_legacy[@]}"
  echo "HYDRATED: no"
  exit 4
fi

baseline=
[[ -f "$CANONICAL" ]] && baseline=$CANONICAL
conflicts=()
if (( CORE_SYNC_SUCCEEDED )); then
  if (( MIGRATE == 0 )) || [[ ! -f "$CANONICAL" ]]; then
    echo "ERROR: --core-sync-succeeded requires --migrate and scv/SCV.md" >&2
    exit 2
  fi
  legacy_baseline=
  for file in "${active_legacy[@]}"; do
    if [[ -z "$legacy_baseline" ]]; then
      legacy_baseline=$file
    elif ! cmp -s "$legacy_baseline" "$file"; then
      conflicts+=("$legacy_baseline <> $file")
    fi
  done
else
  for file in "${active_legacy[@]}"; do
    if [[ -z "$baseline" ]]; then
      baseline=$file
    elif ! cmp -s "$baseline" "$file"; then
      conflicts+=("$baseline <> $file")
    fi
  done
fi

if (( ${#conflicts[@]} > 0 )); then
  echo "STATE_INDEX_CONFLICT:"
  printf '  %s\n' "${conflicts[@]}"
  echo "HYDRATED: no"
  exit 4
fi

if [[ -f "$CANONICAL" ]]; then
  state_kind=canonical
  state_file=$CANONICAL
elif [[ -n "$baseline" ]]; then
  state_kind=legacy
  state_file=$baseline
else
  state_kind=missing
  state_file=$CANONICAL
fi

if (( MIGRATE )) && (( ${#active_legacy[@]} > 0 )); then
  if (( DRY_RUN )); then
    if [[ ! -f "$CANONICAL" ]]; then
      echo "MIGRATION_PREVIEW: ${state_file#"$PROJECT_DIR/"} → scv/SCV.md"
    fi
    for file in "${active_legacy[@]}"; do
      echo "POINTER_PREVIEW: ${file#"$PROJECT_DIR/"} → scv/SCV.md"
    done
  else
    timestamp=$(date +%Y%m%d-%H%M%S)
    backup_rel=".scv-backup/$timestamp/shared-core-migration"
    backup_root="$PROJECT_DIR/$backup_rel"
    if [[ -e "$backup_root" ]]; then
      backup_rel="${backup_rel}-$$"
      backup_root="$PROJECT_DIR/$backup_rel"
    fi
    mkdir -p "$backup_root"
    for file in "${active_legacy[@]}"; do
      cp -p "$file" "$backup_root/$(basename "$file")"
    done

    if [[ ! -f "$CANONICAL" ]]; then
      canonical_tmp="$CANONICAL.scv-migration.$$"
      cp -p "$state_file" "$canonical_tmp"
      mv "$canonical_tmp" "$CANONICAL"
      echo "MIGRATED: ${state_file#"$PROJECT_DIR/"} → scv/SCV.md"
    fi

    for file in "${active_legacy[@]}"; do
      name=$(basename "$file")
      pointer_tmp="$file.scv-pointer.$$"
      cat > "$pointer_tmp" <<EOF
# SCV host compatibility pointer

<!-- SCV:HOST-POINTER target=SCV.md -->

SCV's shared workflow state and rules live in [\`SCV.md\`](./SCV.md).
The pre-migration \`$name\` is preserved at
\`$backup_rel/$name\`.
EOF
      mv "$pointer_tmp" "$file"
      echo "POINTERED: ${file#"$PROJECT_DIR/"} → scv/SCV.md"
    done
    echo "LEGACY_STATE_BACKUP: $backup_rel"
    state_kind=canonical
    state_file=$CANONICAL
  fi
fi

echo "STATE_INDEX: $state_kind"
echo "STATE_INDEX_FILE: ${state_file#"$PROJECT_DIR/"}"
if [[ "$state_kind" != missing && -f "$SCV_DIR/INTAKE.md" ]]; then
  echo "HYDRATED: yes"
else
  echo "HYDRATED: no"
fi
