#!/usr/bin/env bash
# Inspect or explicitly migrate SCV's canonical and legacy state indexes.
#
# This resolver is host-neutral. Wrappers delegate to this file so supported
# hosts cannot drift on hydration, conflict, or compatibility-pointer
# semantics.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/host-profile.sh
source "$SCRIPT_DIR/lib/host-profile.sh"

PROJECT_DIR=.
MIGRATE=0
DRY_RUN=0
CORE_SYNC_SUCCEEDED=0
POINTER_MARKER='<!-- SCV:HOST-POINTER target=SCV.md -->'

usage() {
  cat <<'EOF'
Usage: state-index.sh [--project-dir DIR] [--migrate] [--dry-run]

Default mode is strictly read-only. It reports canonical, legacy, missing,
conflicting, or broken-pointer state using the same contract for every host.

--migrate is explicit: verified legacy state is copied to scv/SCV.md, every
existing active legacy index is backed up, and only those existing files are
replaced with host-neutral compatibility pointers. A missing other-host file
is never created.

--core-sync-succeeded is an internal wrapper flag. It permits pointer
finalization after a successful Core sync has advanced canonical SCV.md from
already-verified legacy state.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir)
      [[ $# -ge 2 ]] || {
        echo "ERROR: --project-dir requires a path" >&2
        exit 2
      }
      PROJECT_DIR="$2"
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

PROJECT_DIR="$(cd "$PROJECT_DIR" 2>/dev/null && pwd -P)" || {
  echo "ERROR: project directory not found: $PROJECT_DIR" >&2
  exit 2
}

case "$SCV_STATE_INDEX" in
  ""|*/*|.|..) echo "ERROR: invalid SCV_STATE_INDEX: $SCV_STATE_INDEX" >&2; exit 2 ;;
esac

SCV_DIR="$PROJECT_DIR/scv"
CANONICAL="$SCV_DIR/$SCV_STATE_INDEX"

relative_path() {
  local path="$1"
  printf '%s\n' "${path#"$PROJECT_DIR/"}"
}

is_pointer() {
  local file="$1"
  grep -qxF "$POINTER_MARKER" "$file" 2>/dev/null
}

legacy_names=()
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  case "$name" in
    */*|.|..)
      echo "ERROR: invalid legacy state index: $name" >&2
      exit 2
      ;;
  esac
  [[ "$name" == "$SCV_STATE_INDEX" ]] && continue
  duplicate=0
  for existing in "${legacy_names[@]}"; do
    [[ "$existing" == "$name" ]] && duplicate=1
  done
  (( duplicate == 0 )) && legacy_names+=("$name")
done < <(printf '%s\n' "$SCV_LEGACY_STATE_INDEXES" | tr '|' '\n')

active_legacy=()
pointer_legacy=()
for name in "${legacy_names[@]}"; do
  file="$SCV_DIR/$name"
  [[ -f "$file" ]] || continue
  if is_pointer "$file"; then
    pointer_legacy+=("$file")
  else
    active_legacy+=("$file")
  fi
done

canonical_valid=0
if [[ -f "$CANONICAL" ]] && ! is_pointer "$CANONICAL"; then
  canonical_valid=1
fi

if (( CORE_SYNC_SUCCEEDED )); then
  if (( MIGRATE == 0 || canonical_valid == 0 )); then
    echo "ERROR: --core-sync-succeeded requires --migrate and canonical scv/$SCV_STATE_INDEX" >&2
    exit 2
  fi
fi

baseline=
if (( canonical_valid )); then
  baseline="$CANONICAL"
elif (( ${#active_legacy[@]} > 0 )); then
  baseline="${active_legacy[0]}"
fi

conflicts=()
if (( CORE_SYNC_SUCCEEDED )); then
  legacy_baseline=
  for file in "${active_legacy[@]}"; do
    if [[ -z "$legacy_baseline" ]]; then
      legacy_baseline="$file"
    elif ! cmp -s "$legacy_baseline" "$file"; then
      conflicts+=("$legacy_baseline|$file")
    fi
  done
else
  for file in "${active_legacy[@]}"; do
    [[ "$file" == "$baseline" ]] && continue
    if [[ -n "$baseline" ]] && ! cmp -s "$baseline" "$file"; then
      conflicts+=("$baseline|$file")
    fi
  done
fi

broken_pointers=()
if (( canonical_valid == 0 )); then
  for file in "${pointer_legacy[@]}"; do
    broken_pointers+=("$file")
  done
  if [[ -f "$CANONICAL" ]] && is_pointer "$CANONICAL"; then
    broken_pointers+=("$CANONICAL")
  fi
fi

if (( canonical_valid )); then
  state_kind=canonical
  state_file="$CANONICAL"
elif [[ -n "$baseline" ]]; then
  state_kind=legacy
  state_file="$baseline"
else
  state_kind=missing
  state_file="$CANONICAL"
fi

hydrated=no
if [[ "$state_kind" != missing && -f "$SCV_DIR/INTAKE.md" ]]; then
  hydrated=yes
fi

report_state() {
  echo "STATE_INDEX: $state_kind"
  echo "STATE_INDEX_FILE: $(relative_path "$state_file")"
  echo "HYDRATED: $hydrated"
}

if (( ${#broken_pointers[@]} > 0 )); then
  echo "STATE_INDEX_BROKEN_POINTER:"
  for file in "${broken_pointers[@]}"; do
    printf '  %s -> scv/%s (missing)\n' \
      "$(relative_path "$file")" "$SCV_STATE_INDEX"
  done
fi

if (( ${#conflicts[@]} > 0 )); then
  echo "STATE_INDEX_CONFLICT:"
  for pair in "${conflicts[@]}"; do
    left="${pair%%|*}"
    right="${pair#*|}"
    printf '  %s <> %s\n' "$(relative_path "$left")" "$(relative_path "$right")"
  done
fi

if (( ${#broken_pointers[@]} > 0 || ${#conflicts[@]} > 0 )); then
  report_state
  echo "MIGRATION_REQUIRED: reconcile the listed state indexes explicitly; no file was overwritten"
  exit 4
fi

if (( MIGRATE == 0 )); then
  report_state
  if (( canonical_valid == 0 && ${#active_legacy[@]} > 0 )); then
    echo "MIGRATION_AVAILABLE: an approved sync can create scv/$SCV_STATE_INDEX"
  elif (( canonical_valid && ${#active_legacy[@]} > 0 )); then
    echo "MIGRATION_AVAILABLE: an approved sync can replace identical legacy state with pointers"
  fi
  exit 0
fi

if (( DRY_RUN )); then
  if (( canonical_valid == 0 && ${#active_legacy[@]} > 0 )); then
    echo "MIGRATION_PREVIEW: $(relative_path "$baseline") -> scv/$SCV_STATE_INDEX"
  fi
  for file in "${active_legacy[@]}"; do
    echo "POINTER_PREVIEW: $(relative_path "$file") -> scv/$SCV_STATE_INDEX"
  done
  report_state
  exit 0
fi

if (( ${#active_legacy[@]} == 0 )); then
  report_state
  echo "MIGRATION_COMPLETE: no-active-legacy-state"
  exit 0
fi

timestamp="$(date +%Y%m%d-%H%M%S)"
backup_rel=".scv-backup/$timestamp/shared-core-migration-$$"
backup_root="$PROJECT_DIR/$backup_rel"
canonical_tmp=
canonical_created=0
backup_created=0
transaction_committed=0
pointer_tmps=()

cleanup_transaction() {
  local tmp
  set +e
  for tmp in "${pointer_tmps[@]}"; do
    [[ -e "$tmp" || -L "$tmp" ]] && rm -f "$tmp"
  done
  if [[ -n "$canonical_tmp" && ( -e "$canonical_tmp" || -L "$canonical_tmp" ) ]]; then
    if (( canonical_created && transaction_committed == 0 )) \
      && [[ -e "$CANONICAL" && "$CANONICAL" -ef "$canonical_tmp" ]]; then
      rm -f "$CANONICAL"
    fi
    rm -f "$canonical_tmp"
  fi
  if (( backup_created && transaction_committed == 0 )) && [[ -d "$backup_root" ]]; then
    rm -rf "$backup_root"
    rmdir "$PROJECT_DIR/.scv-backup/$timestamp" 2>/dev/null || true
    rmdir "$PROJECT_DIR/.scv-backup" 2>/dev/null || true
  fi
}
trap cleanup_transaction EXIT

migration_changed() {
  echo "STATE_INDEX_CONFLICT: state changed while migration was being staged" >&2
  echo "MIGRATION_REQUIRED: retry after reconciling concurrent state changes; no pointer was replaced" >&2
  exit 4
}

for file in "${active_legacy[@]}"; do
  [[ -f "$file" && ! -L "$file" ]] || migration_changed
done

if (( canonical_valid == 0 )); then
  canonical_tmp="$CANONICAL.scv-migration.$$"
  cp -p "$baseline" "$canonical_tmp"
  cmp -s "$baseline" "$canonical_tmp" || migration_changed
  if ! ln "$canonical_tmp" "$CANONICAL" 2>/dev/null; then
    echo "STATE_INDEX_CONFLICT: scv/$SCV_STATE_INDEX appeared during migration" >&2
    echo "MIGRATION_REQUIRED: inspect the new canonical state; no pointer was replaced" >&2
    exit 4
  fi
  canonical_created=1
fi

mkdir -p "$PROJECT_DIR/.scv-backup/$timestamp"
if ! mkdir "$backup_root"; then
  echo "ERROR: migration backup path already exists: $backup_rel" >&2
  exit 4
fi
backup_created=1

for file in "${active_legacy[@]}"; do
  name="$(basename "$file")"
  backup="$backup_root/$name"
  cp -p "$file" "$backup"
  [[ -f "$file" && ! -L "$file" ]] || migration_changed
  cmp -s "$backup" "$file" || migration_changed

  pointer_tmp="$file.scv-pointer.$$"
  pointer_tmps+=("$pointer_tmp")
  cp -p "$file" "$pointer_tmp"
  {
    echo "# SCV host compatibility pointer"
    echo
    echo "$POINTER_MARKER"
    echo
    echo "SCV's shared workflow state and rules live in [\`$SCV_STATE_INDEX\`](./$SCV_STATE_INDEX)."
    echo "The pre-migration \`$name\` is preserved at"
    echo "\`$backup_rel/$name\`."
  } > "$pointer_tmp"
done

# Revalidate the whole state set after every backup and pointer has been
# staged. No active legacy file is replaced unless this all-or-none preflight
# still matches the bytes that were backed up.
for file in "${active_legacy[@]}"; do
  backup="$backup_root/$(basename "$file")"
  [[ -f "$file" && ! -L "$file" ]] || migration_changed
  cmp -s "$backup" "$file" || migration_changed
  if (( CORE_SYNC_SUCCEEDED == 0 && canonical_valid )); then
    [[ -f "$CANONICAL" && ! -L "$CANONICAL" ]] || migration_changed
    cmp -s "$CANONICAL" "$backup" || migration_changed
  fi
done

# From this point canonical state and its recoverable backup must remain if a
# later filesystem error interrupts pointer publication.
transaction_committed=1
if [[ -n "$canonical_tmp" ]]; then
  rm -f "$canonical_tmp"
  canonical_tmp=
fi

if (( canonical_created )); then
  echo "MIGRATED: $(relative_path "$baseline") -> scv/$SCV_STATE_INDEX"
fi
for index in "${!active_legacy[@]}"; do
  file="${active_legacy[$index]}"
  pointer_tmp="${pointer_tmps[$index]}"
  mv "$pointer_tmp" "$file"
  pointer_tmps[$index]=
  echo "POINTERED: $(relative_path "$file") -> scv/$SCV_STATE_INDEX"
done

echo "LEGACY_STATE_BACKUP: $backup_rel"
state_kind=canonical
state_file="$CANONICAL"
hydrated=no
[[ -f "$SCV_DIR/INTAKE.md" ]] && hydrated=yes
report_state
echo "MIGRATION_COMPLETE: yes"
trap - EXIT
