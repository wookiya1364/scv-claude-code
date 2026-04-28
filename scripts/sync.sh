#!/usr/bin/env bash
# Sync SCV template into an existing project, honoring frontmatter merge_policy.
#
# Template layout (SCV owns only scv/; root is user-owned and never touched):
#   template/scv/CLAUDE.md             → project scv/CLAUDE.md   (merge-on-markers)
#   template/scv/*.md                  → project scv/*.md
#   template/scv/promote/*             → project scv/promote/    (preserved)
#   template/scv/archive/*             → project scv/archive/    (preserved)
#   template/scv/raw/*                 → project scv/raw/        (preserved)
#
# Rules:
#   - overwrite          Replace file wholesale
#   - preserve           Never change (unless --force <rel_path>)
#   - merge-on-markers   Replace file, but restore PROJECT:LOCAL block from local
#
# CLAUDE.md is always merge-on-markers (its spec is baked into this script).
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
STANDARD_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
TEMPLATE_DIR="$STANDARD_ROOT/template"

# shellcheck source=lib/yaml.sh
source "$SCRIPT_DIR/lib/yaml.sh"
# shellcheck source=lib/merge.sh
source "$SCRIPT_DIR/lib/merge.sh"

PROJECT_DIR="."
DRY_RUN=0
FORCE_FILES=()

usage() {
  cat <<'EOF'
Usage: sync.sh [--project-dir PATH] [--dry-run] [--force FILE ...]

Syncs the current team standard template into an existing project.
Respects frontmatter merge_policy on each template file.

Options:
  --project-dir PATH   Target project directory (default: cwd).
  --dry-run            Print planned actions without modifying files.
  --force FILE         Force-overwrite a file whose merge_policy is 'preserve'.
                       Use the relative path under the project (e.g. scv/DOMAIN.md).
                       May be passed multiple times.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) PROJECT_DIR="$2"; shift 2 ;;
    --dry-run)     DRY_RUN=1; shift ;;
    --force)       FORCE_FILES+=("$2"); shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "Unknown flag: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if [[ ! -f "$PROJECT_DIR/scv/CLAUDE.md" ]]; then
  echo "✖ $PROJECT_DIR does not look like a hydrated project (missing scv/CLAUDE.md)" >&2
  echo "  Use hydrate.sh init <dir> for new projects." >&2
  exit 1
fi

REMOTE_VERSION=$(tr -d '[:space:]' < "$STANDARD_ROOT/VERSION")
LOCAL_VERSION=$(extract_simple_marker "$PROJECT_DIR/scv/CLAUDE.md" "<!-- STANDARD:VERSION -->" "<!-- /STANDARD:VERSION -->" 2>/dev/null | tr -d '[:space:]' || true)
[[ -z "$LOCAL_VERSION" ]] && LOCAL_VERSION="unknown"

echo "Standard version: local=$LOCAL_VERSION → remote=$REMOTE_VERSION"
echo "Project dir: $(cd "$PROJECT_DIR" && pwd)"
[[ $DRY_RUN -eq 1 ]] && echo "(dry-run mode — no files modified)"
echo

TS=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="$PROJECT_DIR/.scv-backup/$TS"
BACKUPS_CREATED=0
CHANGES=()

backup_file() {
  local f="$1"
  [[ $DRY_RUN -eq 1 ]] && return 0
  [[ ! -f "$f" ]] && return 0
  local rel="${f#$PROJECT_DIR/}"
  local backup_path="$BACKUP_DIR/$rel"
  mkdir -p "$(dirname "$backup_path")"
  cp "$f" "$backup_path"
  BACKUPS_CREATED=$((BACKUPS_CREATED + 1))
}

is_forced() {
  local name="$1"
  for f in "${FORCE_FILES[@]:-}"; do
    [[ "$f" == "$name" ]] && return 0
  done
  return 1
}

# merge-on-markers: copy template, restore local PROJECT:LOCAL block
apply_merge_on_markers() {
  local src="$1" dst="$2"
  local preserved=""
  if has_marker_block "$dst" "PROJECT:LOCAL START"; then
    preserved=$(extract_marker_block "$dst" "PROJECT:LOCAL START" "PROJECT:LOCAL END")
  fi
  cp "$src" "$dst"
  if [[ -n "$preserved" ]]; then
    replace_marker_block "$dst" "PROJECT:LOCAL START" "PROJECT:LOCAL END" "$preserved" || true
  fi
}

# Process a single template file relative to the project root.
# Arg 1: absolute path to template file
# Arg 2: relative subdirectory under PROJECT_DIR (empty string for root, or "scv")
process_template_file() {
  local tmpl="$1"
  local rel_dir="$2"
  local bn
  bn=$(basename "$tmpl")

  local dst_dir
  if [[ -z "$rel_dir" ]]; then
    dst_dir="$PROJECT_DIR"
  else
    dst_dir="$PROJECT_DIR/$rel_dir"
  fi
  local dst="$dst_dir/$bn"
  local display
  if [[ -z "$rel_dir" ]]; then
    display="$bn"
  else
    display="$rel_dir/$bn"
  fi

  mkdir -p "$dst_dir"

  if [[ ! -f "$dst" ]]; then
    CHANGES+=("NEW       $display")
    [[ $DRY_RUN -eq 0 ]] && cp "$tmpl" "$dst"
    return
  fi

  local policy
  policy=$(yaml_get "$tmpl" "merge_policy")
  [[ -z "$policy" ]] && policy="preserve"

  # CLAUDE.md always uses merge-on-markers (no frontmatter).
  if [[ "$bn" == "CLAUDE.md" ]]; then
    policy="merge-on-markers"
  fi

  if cmp -s "$tmpl" "$dst"; then
    return
  fi

  case "$policy" in
    overwrite)
      CHANGES+=("OVERWRITE $display")
      if [[ $DRY_RUN -eq 0 ]]; then
        backup_file "$dst"
        cp "$tmpl" "$dst"
      fi
      ;;
    preserve)
      if is_forced "$display"; then
        CHANGES+=("FORCED    $display  (preserve overridden)")
        if [[ $DRY_RUN -eq 0 ]]; then
          backup_file "$dst"
          cp "$tmpl" "$dst"
        fi
      else
        CHANGES+=("SKIP      $display  (preserve)")
      fi
      ;;
    merge-on-markers)
      CHANGES+=("MERGE     $display  (PROJECT:LOCAL preserved)")
      if [[ $DRY_RUN -eq 0 ]]; then
        backup_file "$dst"
        apply_merge_on_markers "$tmpl" "$dst"
      fi
      ;;
    *)
      CHANGES+=("UNKNOWN   $display  (unknown merge_policy='$policy', skipped)")
      ;;
  esac
}

shopt -s nullglob
# template/scv/ 하위의 .md (scv/CLAUDE.md 포함; merge-on-markers by basename rule)
for tmpl in "$TEMPLATE_DIR/scv"/*.md; do
  process_template_file "$tmpl" "scv"
done
shopt -u nullglob

# Stamp scv/CLAUDE.md version markers (root CLAUDE.md is user-owned and untouched).
# Marker names kept as STANDARD:* for backward compatibility.
if [[ $DRY_RUN -eq 0 && -f "$PROJECT_DIR/scv/CLAUDE.md" ]]; then
  replace_simple_marker "$PROJECT_DIR/scv/CLAUDE.md" \
    "<!-- STANDARD:VERSION -->" "<!-- /STANDARD:VERSION -->" "$REMOTE_VERSION"
  replace_simple_marker "$PROJECT_DIR/scv/CLAUDE.md" \
    "<!-- STANDARD:SYNCED_AT -->" "<!-- /STANDARD:SYNCED_AT -->" "$(date +%Y-%m-%d)"
fi

echo "Changes:"
if [[ ${#CHANGES[@]} -eq 0 ]]; then
  echo "  (none)"
else
  for c in "${CHANGES[@]}"; do
    echo "  $c"
  done
fi

if [[ $DRY_RUN -eq 0 && $BACKUPS_CREATED -gt 0 ]]; then
  echo
  echo "Backups: $BACKUPS_CREATED file(s) saved to $BACKUP_DIR"
fi

if [[ $DRY_RUN -eq 1 ]]; then
  echo
  echo "(dry-run) re-run without --dry-run to apply."
fi
