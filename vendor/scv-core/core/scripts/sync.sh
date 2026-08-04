#!/usr/bin/env bash
# Sync SCV template into an existing project, honoring frontmatter merge_policy.
#
# Template layout (SCV owns only scv/; root is user-owned and never touched):
#   template/scv/SCV.md             → project scv/SCV.md   (merge-on-markers)
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
# SCV.md is always merge-on-markers (its spec is baked into this script).
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
STANDARD_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
TEMPLATE_DIR="$STANDARD_ROOT/template"

# shellcheck source=lib/yaml.sh
source "$SCRIPT_DIR/lib/yaml.sh"
# shellcheck source=lib/merge.sh
source "$SCRIPT_DIR/lib/merge.sh"
# shellcheck source=lib/host-profile.sh
source "$SCRIPT_DIR/lib/host-profile.sh"

PROJECT_DIR="."
DRY_RUN=0
FORCE_FILES=()
JOIN_ROOT=""
JOIN_ID=""
JOIN_ROLE=""
JOIN_WS=""

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

Workspace join (multi-repo):
  --join ROOT_URL      Make this repo a CHILD of the workspace whose umbrella
                       scv repo is ROOT_URL (a git URL or local path). Stamps
                       the SCV:WORKSPACE block in scv/SCV.md and exits — no
                       template merge. Re-runnable; clearing it detaches.
  --id ID              Workspace-global repo id (default: project dir basename).
  --role ROLE          Repo role (e.g. frontend, backend, ai-agent).
  --workspace NAME     Workspace name (optional, for cache namespacing).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir)
      [[ $# -ge 2 && -n "${2:-}" ]] \
        || { echo "✖ --project-dir requires PATH" >&2; usage >&2; exit 2; }
      PROJECT_DIR="$2"; shift 2 ;;
    --dry-run)     DRY_RUN=1; shift ;;
    --force)
      [[ $# -ge 2 && -n "${2:-}" ]] \
        || { echo "✖ --force requires FILE" >&2; usage >&2; exit 2; }
      FORCE_FILES+=("$2"); shift 2 ;;
    --join)
      [[ $# -ge 2 && -n "${2:-}" ]] \
        || { echo "✖ --join requires ROOT_URL" >&2; usage >&2; exit 2; }
      JOIN_ROOT="$2"; shift 2 ;;
    --id)
      [[ $# -ge 2 && -n "${2:-}" ]] \
        || { echo "✖ --id requires ID" >&2; usage >&2; exit 2; }
      JOIN_ID="$2"; shift 2 ;;
    --role)
      [[ $# -ge 2 && -n "${2:-}" ]] \
        || { echo "✖ --role requires ROLE" >&2; usage >&2; exit 2; }
      JOIN_ROLE="$2"; shift 2 ;;
    --workspace)
      [[ $# -ge 2 && -n "${2:-}" ]] \
        || { echo "✖ --workspace requires NAME" >&2; usage >&2; exit 2; }
      JOIN_WS="$2"; shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "Unknown flag: $1" >&2; usage >&2; exit 2 ;;
  esac
done

CANONICAL_STATE_INDEX="$PROJECT_DIR/scv/$SCV_STATE_INDEX"
BROKEN_POINTERS="$(scv_state_index_broken_pointers "$PROJECT_DIR/scv")"
if [[ -n "$BROKEN_POINTERS" ]]; then
  echo "✖ SCV state-index pointer is broken; no files changed." >&2
  printf '%s\n' "$BROKEN_POINTERS" | sed 's/^/  /' >&2
  echo "  Restore scv/$SCV_STATE_INDEX or restore the legacy state file from its backup." >&2
  exit 4
fi
LOCAL_STATE_INDEX="$(scv_state_index_path "$PROJECT_DIR/scv")"
if [[ ! -f "$LOCAL_STATE_INDEX" ]]; then
  echo "✖ $PROJECT_DIR does not look like a hydrated project (missing scv/SCV.md)" >&2
  echo "  Use hydrate.sh init <dir> for new projects." >&2
  exit 1
fi

INDEX_CONFLICTS="$(scv_state_index_conflicts "$PROJECT_DIR/scv")"
if [[ -n "$INDEX_CONFLICTS" ]]; then
  echo "✖ SCV state-index conflict; no files changed." >&2
  printf '%s\n' "$INDEX_CONFLICTS" | sed 's/^/  /' >&2
  echo "  Reconcile the files manually, or let the wrapper replace a verified legacy file with a pointer." >&2
  exit 3
fi

# One-time, non-destructive migration: seed the shared state index from a
# wrapper-declared legacy index. The legacy file is intentionally left intact;
# the adapter may back it up and replace it with a pointer after this succeeds.
if [[ "$LOCAL_STATE_INDEX" != "$CANONICAL_STATE_INDEX" && ! -f "$CANONICAL_STATE_INDEX" ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "MIGRATE   ${LOCAL_STATE_INDEX#"$PROJECT_DIR/"} → scv/$SCV_STATE_INDEX (legacy preserved)"
  else
    cp "$LOCAL_STATE_INDEX" "$CANONICAL_STATE_INDEX"
    echo "✓ migrated legacy state to scv/$SCV_STATE_INDEX (legacy file preserved)"
    LOCAL_STATE_INDEX="$CANONICAL_STATE_INDEX"
  fi
fi

# --join: stamp the SCV:WORKSPACE block (make this repo a workspace CHILD) and exit.
# Focused operation — does NOT run the template merge.
if [[ -n "$JOIN_ROOT" ]]; then
  STATE_INDEX="$LOCAL_STATE_INDEX"
  [[ -z "$JOIN_ID" ]] && JOIN_ID="$(basename "$(cd "$PROJECT_DIR" && pwd)")"
  if [[ $DRY_RUN -eq 1 ]]; then
    if [[ "$LOCAL_STATE_INDEX" != "$CANONICAL_STATE_INDEX" && ! -f "$CANONICAL_STATE_INDEX" ]]; then
      STATE_INDEX="$CANONICAL_STATE_INDEX"
    fi
    echo "JOIN      ${STATE_INDEX#"$PROJECT_DIR/"} (workspace block)"
    echo "  repo_id=$JOIN_ID role=${JOIN_ROLE:-<unset>} root=$JOIN_ROOT workspace=${JOIN_WS:-<unset>}"
    echo "(dry-run mode — no files modified)"
    exit 0
  fi
  body=$(printf '```yaml\nrepo_id: %s\nrole: %s\nroot: %s\nworkspace: %s\n```' \
    "$JOIN_ID" "$JOIN_ROLE" "$JOIN_ROOT" "$JOIN_WS")
  if has_marker_block "$STATE_INDEX" "SCV:WORKSPACE START"; then
    replace_marker_block "$STATE_INDEX" "SCV:WORKSPACE START" "SCV:WORKSPACE END" "$body"
  else
    {
      echo ""
      echo "## SCV workspace (multi-repo nesting)"
      echo ""
      echo "<!-- SCV:WORKSPACE START -->"
      echo "$body"
      echo "<!-- SCV:WORKSPACE END -->"
    } >> "$STATE_INDEX"
  fi
  echo "✓ Joined workspace as CHILD: repo_id=$JOIN_ID role=${JOIN_ROLE:-<unset>} root=$JOIN_ROOT"
  echo "  Detach anytime by clearing root: in scv/SCV.md's SCV:WORKSPACE block."
  exit 0
fi

REMOTE_VERSION=$(tr -d '[:space:]' < "$STANDARD_ROOT/TEMPLATE_VERSION")
LOCAL_VERSION=$(extract_simple_marker "$LOCAL_STATE_INDEX" "<!-- STANDARD:VERSION -->" "<!-- /STANDARD:VERSION -->" 2>/dev/null | tr -d '[:space:]' || true)
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

# merge-on-markers: copy template, restore local marker blocks that are
# project-owned (never overwritten by a template update).
#   PROJECT:LOCAL  — project-specific SCV-scope rules
#   SCV:WORKSPACE  — multi-repo nesting identity (a child's join must survive sync)
apply_merge_on_markers() {
  local src="$1" dst="$2"
  local pl="" ws="" pl_have=0 ws_have=0 preserved_status=""
  preserved_status="$(yaml_get "$dst" "status")"
  if has_marker_block "$dst" "PROJECT:LOCAL START"; then
    pl=$(extract_marker_block "$dst" "PROJECT:LOCAL START" "PROJECT:LOCAL END"); pl_have=1
  fi
  if has_marker_block "$dst" "SCV:WORKSPACE START"; then
    ws=$(extract_marker_block "$dst" "SCV:WORKSPACE START" "SCV:WORKSPACE END"); ws_have=1
  fi
  cp "$src" "$dst"
  if [[ -n "$preserved_status" ]]; then
    local status_tmp
    status_tmp="$(mktemp)"
    awk -v value="$preserved_status" '
      BEGIN { fences = 0; replaced = 0 }
      /^---[[:space:]]*$/ { fences++; print; next }
      fences == 1 && !replaced && /^status:[[:space:]]*/ {
        print "status: " value
        replaced = 1
        next
      }
      { print }
    ' "$dst" > "$status_tmp"
    mv "$status_tmp" "$dst"
  fi
  if [[ $pl_have -eq 1 ]]; then
    replace_marker_block "$dst" "PROJECT:LOCAL START" "PROJECT:LOCAL END" "$pl" || true
  fi
  if [[ $ws_have -eq 1 ]]; then
    replace_marker_block "$dst" "SCV:WORKSPACE START" "SCV:WORKSPACE END" "$ws" || true
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
    if [[ $DRY_RUN -eq 0 ]]; then
      cp "$tmpl" "$dst"
    fi
    return 0
  fi

  local policy
  policy=$(yaml_get "$tmpl" "merge_policy")
  [[ -z "$policy" ]] && policy="preserve"

  # SCV.md always uses merge-on-markers (no frontmatter).
  if [[ "$bn" == "SCV.md" ]]; then
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
# .md files under template/scv/ (incl. scv/SCV.md; merge-on-markers by basename rule)
for tmpl in "$TEMPLATE_DIR/scv"/*.md; do
  process_template_file "$tmpl" "scv"
done
shopt -u nullglob

# scv/raw/README.md — the raw lifecycle guide (unused vs stale/) must reach
# existing projects too; without this, pre-0.21.0 installs keep a README that
# contradicts the stale-move behavior their upgraded core now performs.
if [[ -f "$TEMPLATE_DIR/scv/raw/README.md" ]]; then
  process_template_file "$TEMPLATE_DIR/scv/raw/README.md" "scv/raw"
fi

# Stamp scv/SCV.md version markers (root instruction files stay untouched).
# Marker names kept as STANDARD:* for backward compatibility.
if [[ $DRY_RUN -eq 0 && -f "$PROJECT_DIR/scv/SCV.md" ]]; then
  replace_simple_marker "$PROJECT_DIR/scv/SCV.md" \
    "<!-- STANDARD:VERSION -->" "<!-- /STANDARD:VERSION -->" "$REMOTE_VERSION"
  replace_simple_marker "$PROJECT_DIR/scv/SCV.md" \
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
