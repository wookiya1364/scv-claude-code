#!/usr/bin/env bash
# Inject the SCV template into a project directory.
#
# Single path (v2.0.0+): the template seeds only the workflow files
# (scv/SCV.md, scv/PROMOTE.md, scv/REPORTING.md, scv/raw/, promote/, archive/,
# WORKSPACE.yaml.example, .env/.gitignore fragments). The promote/work loop is
# usable immediately; there is no standard-doc scaffolding step.
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
STANDARD_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
TEMPLATE_DIR="$STANDARD_ROOT/template"

# shellcheck source=lib/merge.sh
source "$SCRIPT_DIR/lib/merge.sh"

usage() {
  cat <<'EOF'
Usage: hydrate.sh init <target_dir> [--force]

Inject the SCV template into a project directory.

Arguments:
  init <target_dir>  Target directory. Created if missing.

Options:
  --root             Make this the umbrella (workspace ROOT) repo: also creates
                     scv/WORKSPACE.yaml from the example so child repos can join.
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
ROOT_MODE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --new)
      # Removed in TEMPLATE_VERSION 2.0.0 — fail closed before touching anything.
      cat >&2 <<'EOF'
✖ --new (greenfield mode) was removed in SCV template 2.0.0.

  hydrate now has a single path: it seeds only the workflow files and no
  standard-doc scaffolding, so the promote/work loop is usable immediately
  on new and existing projects alike.

  Migration: re-run without --new

      hydrate.sh init <target_dir>

  Decisions worth keeping belong in version-controlled team notes
  (e.g. DECISIONS.md / a journal), not in pre-seeded snapshot docs.
EOF
      exit 1
      ;;
    --root)  ROOT_MODE=1; shift ;;
    *) echo "Unknown flag: $1" >&2; exit 1 ;;
  esac
done

# Resolve absolute target path (mkdir first so realpath works)
mkdir -p "$TARGET"
TARGET="$( cd "$TARGET" && pwd )"

if [[ -e "$TARGET/scv" && $FORCE -eq 0 ]]; then
  echo "✖ $TARGET/scv already exists. Use --force, or run /scv:sync for incremental updates." >&2
  echo "  (SCV is non-destructive: it only owns files under scv/.)" >&2
  exit 1
fi

echo "→ Copying template to $TARGET"
# `cp -R -p` is supported by both BSD and GNU implementations. dotglob makes
# `*` include dotfiles (.env.example.scv, .gitignore.fragment).
# template/hooks/ is deliberately EXCLUDED: host hook templates are
# wrapper-installed (registration is host-owned — see docs/wrapper-integration.md
# §"Hook seam"), never seeded into user projects.
shopt -s dotglob nullglob
for entry in "$TEMPLATE_DIR"/*; do
  [[ "$(basename "$entry")" == "hooks" ]] && continue
  if [[ "$(basename "$entry")" == "scv" ]]; then
    # scv/ is copied per-child so scv/routines/ seeds ONLY its README.md
    # (the convention doc): the example routine templates
    # (template/scv/routines/examples/) stay in core — routine files are
    # added by the user/agent (see routines/README.md).
    mkdir -p "$TARGET/scv"
    for sub in "$entry"/*; do
      if [[ "$(basename "$sub")" == "routines" ]]; then
        mkdir -p "$TARGET/scv/routines"
        cp -p "$sub/README.md" "$TARGET/scv/routines/README.md"
      else
        cp -R -p "$sub" "$TARGET/scv/"
      fi
    done
  else
    cp -R -p "$entry" "$TARGET/"
  fi
done
shopt -u dotglob nullglob

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

# Stamp scv/SCV.md with current SCV version + sync date
# (Project-root instruction files are user-owned; SCV never touches them.)
VERSION=$(tr -d '[:space:]' < "$STANDARD_ROOT/TEMPLATE_VERSION")
TODAY=$(date +%Y-%m-%d)

if [[ -f "$TARGET/scv/SCV.md" ]]; then
  replace_simple_marker "$TARGET/scv/SCV.md" \
    "<!-- STANDARD:VERSION -->" "<!-- /STANDARD:VERSION -->" "$VERSION"
  replace_simple_marker "$TARGET/scv/SCV.md" \
    "<!-- STANDARD:SYNCED_AT -->" "<!-- /STANDARD:SYNCED_AT -->" "$TODAY"
  echo "  scv/SCV.md stamped: version=$VERSION synced_at=$TODAY"
fi

# --root: promote this repo to the workspace umbrella by creating scv/WORKSPACE.yaml.
if [[ $ROOT_MODE -eq 1 ]]; then
  if [[ -f "$TARGET/scv/WORKSPACE.yaml" ]]; then
    echo "  scv/WORKSPACE.yaml already exists — left untouched (this repo is the ROOT)."
  elif [[ -f "$TARGET/scv/WORKSPACE.yaml.example" ]]; then
    cp "$TARGET/scv/WORKSPACE.yaml.example" "$TARGET/scv/WORKSPACE.yaml"
    echo "  scv/WORKSPACE.yaml created (this repo is the workspace ROOT) — edit its members."
  else
    echo "  ⚠ WORKSPACE.yaml.example missing from template — cannot create WORKSPACE.yaml." >&2
  fi
fi

cat <<EOF

✅ SCV template hydrated into: $TARGET
   SCV version: $VERSION (synced $TODAY)

▶ Next: in your Claude Code session, run this one line:

    /scv:help

/scv:help diagnoses the current state and recommends the next step.
EOF
