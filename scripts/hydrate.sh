#!/usr/bin/env bash
# Inject the SCV template into a project directory.
#
# Modes:
#   default        Adoption mode — for existing projects. Standard docs are
#                  seeded with status: N/A so the promote/work loop can run
#                  immediately. Scope what you actually need later.
#   --new          Greenfield mode — for brand-new projects. Standard docs
#                  stay as status: draft so /scv:help can guide you through
#                  the full INTAKE protocol.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
STANDARD_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
TEMPLATE_DIR="$STANDARD_ROOT/template"

# shellcheck source=lib/merge.sh
source "$SCRIPT_DIR/lib/merge.sh"

usage() {
  cat <<'EOF'
Usage: hydrate.sh init <target_dir> [--new] [--force]

Inject the SCV template into a project directory.

Arguments:
  init <target_dir>  Target directory. Created if missing.

Modes (default = adoption mode — for existing projects):
  --new              Greenfield mode. Seeds standard docs as status: draft
                     so /scv:help drives the full INTAKE dialog. Use this
                     only when starting a brand-new project from scratch.

Other options:
  --force            Allow copying into a directory that already has scv/.
  -h, --help         Show this help.
EOF
}

cmd="${1:-}"
case "$cmd" in
  init) shift ;;
  -h|--help|"") usage; exit 0 ;;
  *) echo "Unknown command: $cmd" >&2; usage >&2; exit 1 ;;
esac

TARGET="${1:-}"
if [[ -z "$TARGET" ]]; then
  echo "✖ target_dir is required" >&2
  usage >&2
  exit 1
fi
shift || true

FORCE=0
NEW_MODE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --new)   NEW_MODE=1; shift ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

# Resolve absolute target path (mkdir first so realpath works)
mkdir -p "$TARGET"
TARGET="$( cd "$TARGET" && pwd )"

if [[ -e "$TARGET/scv" && $FORCE -eq 0 ]]; then
  echo "✖ $TARGET/scv already exists. Use --force, or run /scv:sync for incremental updates." >&2
  echo "  (SCV is non-destructive: it does NOT touch the root CLAUDE.md — only scv/.)" >&2
  exit 1
fi

if [[ $NEW_MODE -eq 1 ]]; then
  MODE_LABEL="new (greenfield)"
else
  MODE_LABEL="adoption (default)"
fi
echo "→ Hydrate mode: $MODE_LABEL"
echo "→ Copying template to $TARGET"
# cp -a preserves attributes; the /. suffix copies contents including dotfiles
cp -a "$TEMPLATE_DIR/." "$TARGET/"

# Merge .gitignore fragment
if [[ -f "$TARGET/.gitignore.fragment" ]]; then
  if [[ -f "$TARGET/.gitignore" ]]; then
    {
      echo ""
      echo "# --- appended by scv hydrate.sh ---"
      cat "$TARGET/.gitignore.fragment"
    } >> "$TARGET/.gitignore"
    rm -f "$TARGET/.gitignore.fragment"
    echo "  .gitignore.fragment appended to existing .gitignore"
  else
    mv "$TARGET/.gitignore.fragment" "$TARGET/.gitignore"
    echo "  .gitignore created from fragment"
  fi
fi

# Stamp scv/CLAUDE.md with current SCV version + sync date
# (Root CLAUDE.md is user-owned; SCV never touches it.)
VERSION=$(cat "$STANDARD_ROOT/VERSION" | tr -d '[:space:]')
TODAY=$(date +%Y-%m-%d)

if [[ -f "$TARGET/scv/CLAUDE.md" ]]; then
  replace_simple_marker "$TARGET/scv/CLAUDE.md" \
    "<!-- STANDARD:VERSION -->" "<!-- /STANDARD:VERSION -->" "$VERSION"
  replace_simple_marker "$TARGET/scv/CLAUDE.md" \
    "<!-- STANDARD:SYNCED_AT -->" "<!-- /STANDARD:SYNCED_AT -->" "$TODAY"
  echo "  scv/CLAUDE.md stamped: version=$VERSION synced_at=$TODAY"
fi

# Default (adoption) mode: flip standard-doc status from "draft" to "N/A"
# so the promote/work loop can run immediately without INTAKE being enforced.
# --new (greenfield) mode: leave them as "draft" (INTAKE will drive them).
if [[ $NEW_MODE -eq 0 ]]; then
  for doc in DOMAIN ARCHITECTURE DESIGN AGENTS TESTING REPORTING RALPH_PROMPT; do
    f="$TARGET/scv/$doc.md"
    [[ -f "$f" ]] || continue
    sed -i '0,/^status: draft$/s#^status: draft$#status: N/A#' "$f"
  done
  echo "  standard docs seeded with status: N/A (adoption mode)"
else
  echo "  standard docs seeded with status: draft (greenfield — /scv:help drives INTAKE)"
fi

cat <<EOF

✅ SCV template hydrated into: $TARGET
   SCV version: $VERSION (synced $TODAY, mode=$MODE_LABEL)

▶ Next: in your Claude Code session, run this one line:

    /scv:help

/scv:help diagnoses the current state and recommends the next step.
EOF
