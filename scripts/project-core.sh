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
PATH_HELPER="$SCRIPT_DIR/sync-core-paths.py"
VENDOR_ROOT="$REPO_ROOT/vendor/scv-core"
DESTINATION="$REPO_ROOT"
MODE=write
STAGE_ROOT=${SCV_PROJECT_CORE_STAGE_ROOT:-}
WRITE_TOKEN=${SCV_PROJECT_CORE_WRITE_TOKEN:-}
DESTINATION_DEVICE=
DESTINATION_INODE=

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

DESTINATION_INPUT=$DESTINATION
STAGE_ROOT_INPUT=$STAGE_ROOT
VENDOR_ROOT="$(cd "$VENDOR_ROOT" 2>/dev/null && pwd)" || {
  echo "ERROR: vendor root not found: $VENDOR_ROOT" >&2
  exit 1
}
DESTINATION="$(cd "$DESTINATION" 2>/dev/null && pwd)" || {
  echo "ERROR: destination not found: $DESTINATION" >&2
  exit 1
}
CORE_ROOT="$VENDOR_ROOT/core"

if [[ "$MODE" == write ]]; then
  [[ -n "$STAGE_ROOT" && -n "$WRITE_TOKEN" ]] || {
    echo "ERROR: project-core write mode is internal; use sync-core.sh" >&2
    exit 1
  }
  [[ ! -L "$STAGE_ROOT_INPUT" && ! -L "$DESTINATION_INPUT" ]] || {
    echo "ERROR: project-core stage root and destination must not be symlinks" >&2
    exit 1
  }
  STAGE_ROOT="$(cd "$STAGE_ROOT" 2>/dev/null && pwd)" || {
    echo "ERROR: project-core stage root not found: $STAGE_ROOT" >&2
    exit 1
  }
  TOKEN_FILE="$STAGE_ROOT/.scv-project-core-token"
  [[ -f "$TOKEN_FILE" && ! -L "$TOKEN_FILE" ]] || {
    echo "ERROR: project-core stage authorization is missing" >&2
    exit 1
  }
  [[ "$(tr -d '\r\n' < "$TOKEN_FILE")" == "$WRITE_TOKEN" ]] || {
    echo "ERROR: project-core stage authorization does not match" >&2
    exit 1
  }
  python3 - "$REPO_ROOT" "$STAGE_ROOT" "$DESTINATION" <<'PY'
import os
import sys
from pathlib import Path

repo = Path(sys.argv[1]).resolve()
stage = Path(sys.argv[2]).resolve()
destination = Path(sys.argv[3]).resolve()

def is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False

if stage == Path(stage.anchor):
    raise SystemExit("ERROR: project-core stage root is too broad")
if destination == stage or not is_relative_to(destination, stage):
    raise SystemExit(
        "ERROR: project-core destination must be a strict stage descendant"
    )
if stage == repo or is_relative_to(repo, stage):
    raise SystemExit(
        "ERROR: project-core stage root must not contain the wrapper repository"
    )
if destination == repo:
    raise SystemExit(
        "ERROR: project-core refuses to write the live wrapper repository"
    )

relative = destination.relative_to(stage)
cursor = stage
for part in relative.parts:
    cursor = cursor / part
    if cursor.is_symlink():
        raise SystemExit(
            f"ERROR: project-core destination contains a symlink: {cursor}"
        )
PY
  python3 - "$DESTINATION" <<'PY'
import os
import stat
import sys
from pathlib import Path

root = Path(sys.argv[1])
root_mode = root.lstat().st_mode
if not stat.S_ISDIR(root_mode):
    raise SystemExit(
        f"ERROR: project-core destination is not a real directory: {root}"
    )

stack = [root]
while stack:
    directory = stack.pop()
    with os.scandir(directory) as handle:
        children = list(handle)
    for child in children:
        mode = child.stat(follow_symlinks=False).st_mode
        if stat.S_ISLNK(mode):
            raise SystemExit(
                "ERROR: project-core destination tree contains a symlink: "
                f"{child.path}"
            )
        if stat.S_ISDIR(mode):
            stack.append(Path(child.path))
PY
  [[ -f "$PATH_HELPER" && ! -L "$PATH_HELPER" ]] || {
    echo "ERROR: project-core safe path helper is missing" >&2
    exit 1
  }
  DESTINATION_ID=$(python3 -B "$PATH_HELPER" identity --path "$DESTINATION")
  DESTINATION_DEVICE=${DESTINATION_ID%%:*}
  DESTINATION_INODE=${DESTINATION_ID#*:}
fi

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
sync-core-paths.py
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
test-sync-core-atomicity.sh
test-state-adapter.sh
'
FAILURES=0

validate_destination_write_path() {
  local target=$1
  [[ "$MODE" == write ]] || return 0
  python3 - "$DESTINATION" "$target" <<'PY'
import os
import stat
import sys
from pathlib import Path

root = Path(sys.argv[1])
target = Path(os.path.abspath(sys.argv[2]))
try:
    relative = target.relative_to(root)
except ValueError:
    raise SystemExit(
        f"ERROR: project-core write target escapes destination: {target}"
    )

cursor = root
for index, part in enumerate(relative.parts):
    cursor = cursor / part
    try:
        mode = cursor.lstat().st_mode
    except FileNotFoundError:
        break
    if stat.S_ISLNK(mode):
        raise SystemExit(
            f"ERROR: project-core write path contains a symlink: {cursor}"
        )
    if index < len(relative.parts) - 1 and not stat.S_ISDIR(mode):
        raise SystemExit(
            f"ERROR: project-core write parent is not a directory: {cursor}"
        )
PY
}

safe_remove_destination() {
  local target=$1 relative
  [[ "$MODE" == write ]] || return 0
  validate_destination_write_path "$target"
  # A future Core release may introduce a new nested scripts/ or tests/ path.
  # A path-based absence check is safe here: if an entry appears afterwards,
  # the anchored O_EXCL copy fails closed instead of replacing it.
  [[ -e "$target" || -L "$target" ]] || return 0
  relative=${target#"$DESTINATION"/}
  [[ "$relative" != "$target" ]] || {
    echo "ERROR: project-core removal target escapes destination" >&2
    return 1
  }
  python3 -B "$PATH_HELPER" remove-entry \
    --anchor "$DESTINATION" \
    --anchor-device "$DESTINATION_DEVICE" \
    --anchor-inode "$DESTINATION_INODE" \
    --relative "$relative"
}

safe_copy_file() {
  local source=$1 target=$2 relative
  validate_destination_write_path "$target"
  relative=${target#"$DESTINATION"/}
  [[ "$relative" != "$target" ]] || {
    echo "ERROR: project-core copy target escapes destination" >&2
    return 1
  }
  python3 -B "$PATH_HELPER" copy-file \
    --source "$source" \
    --destination-anchor "$DESTINATION" \
    --destination-device "$DESTINATION_DEVICE" \
    --destination-inode "$DESTINATION_INODE" \
    --destination-relative "$relative" \
    --label "project:$relative"
}

safe_copy_tree() {
  local source=$1 target=$2 relative
  validate_destination_write_path "$target"
  relative=${target#"$DESTINATION"/}
  [[ "$relative" != "$target" ]] || {
    echo "ERROR: project-core tree target escapes destination" >&2
    return 1
  }
  python3 -B "$PATH_HELPER" copy-tree \
    --source "$source" \
    --destination-anchor "$DESTINATION" \
    --destination-device "$DESTINATION_DEVICE" \
    --destination-inode "$DESTINATION_INODE" \
    --destination-relative "$relative" \
    --label "project:$relative"
}

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
  safe_remove_destination "$target"
  safe_copy_file "$source" "$target"
}

compare_or_replace_tree() {
  local source=$1 target=$2 label=$3
  if [[ "$MODE" == check ]]; then
    if [[ ! -d "$target" ]] || ! diff -qr "$source" "$target" >/dev/null 2>&1; then
      echo "PROJECTION_MISMATCH: $label"
      FAILURES=$((FAILURES + 1))
    fi
    return
  fi

  safe_remove_destination "$target"
  safe_copy_tree "$source" "$target"
}

compare_or_replace_deckui() {
  local source=$1 target=$2 inventory git_root
  if [[ "$MODE" == check ]]; then
    inventory=$(mktemp)
    git_root=$(git -C "$DESTINATION" rev-parse --show-toplevel 2>/dev/null || true)
    if [[ "$git_root" == "$DESTINATION" ]]; then
      {
        git -C "$DESTINATION" ls-files \
          --others --ignored --exclude-standard --directory -z -- DeckUI
        git -C "$DESTINATION" ls-files \
          --others --exclude-standard --directory -z -- DeckUI
      } > "$inventory"
    fi
    if [[ ! -d "$target" ]] || ! python3 - "$source" "$target" "$inventory" <<'PY'
import os
import stat
import sys
from pathlib import Path

source = Path(sys.argv[1])
target = Path(sys.argv[2])
raw = Path(sys.argv[3]).read_bytes().split(b"\0")
candidate_exclusions = set()
for value in raw:
    if not value:
        continue
    relative = os.fsdecode(value).rstrip("/")
    if relative.startswith("DeckUI/"):
        deck_relative = relative.removeprefix("DeckUI/")
        source_path = source / deck_relative
        # A path supplied by Core remains part of the projection contract even
        # when Git considers the directory untracked (Git cannot own an empty
        # directory). Core ownership wins over the runtime exclusion.
        if source_path.exists() or source_path.is_symlink():
            continue
        candidate_exclusions.add(deck_relative)

excluded = set()
for relative in sorted(
    candidate_exclusions, key=lambda item: (item.count("/"), item)
):
    parts = relative.split("/")
    if any("/".join(parts[:index]) in excluded for index in range(1, len(parts))):
        continue
    excluded.add(relative)

def entries(root: Path, apply_exclusions: bool):
    result = {}
    stack = [(root, "")]
    while stack:
        directory, prefix = stack.pop()
        with os.scandir(directory) as handle:
            children = sorted(handle, key=lambda entry: entry.name, reverse=True)
        for child in children:
            relative = f"{prefix}/{child.name}".lstrip("/")
            if apply_exclusions and relative in excluded:
                continue
            mode = child.stat(follow_symlinks=False).st_mode
            item = Path(child.path)
            if stat.S_ISDIR(mode):
                result[relative] = ("directory",)
                stack.append((item, relative))
            elif stat.S_ISLNK(mode):
                result[relative] = ("symlink", os.readlink(item))
            elif stat.S_ISREG(mode):
                result[relative] = ("file", item.read_bytes())
            else:
                result[relative] = ("special",)
    return result

raise SystemExit(0 if entries(source, False) == entries(target, True) else 1)
PY
    then
      echo "PROJECTION_MISMATCH: DeckUI"
      FAILURES=$((FAILURES + 1))
    fi
    rm -f "$inventory"
    return
  fi
  compare_or_replace_tree "$source" "$target" DeckUI
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
      safe_remove_destination "$projected"
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
      safe_remove_destination "$projected"
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

# Wrapper releases and Core releases are independent. Root VERSION belongs to
# the Claude adapter release; only TEMPLATE_VERSION is projected from Core and
# stamped into hydrated project state.
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
for protocol in "$CORE_ROOT"/protocols/*.md; do
  [[ -f "$protocol" ]] || continue
  action=$(basename "$protocol" .md)
  is_adapter_action "$action" && continue
  command="$DESTINATION/commands/$action.md"
  validate_destination_write_path "$command"
  [[ -f "$command" ]] || {
    echo "ERROR: missing Claude command adapter: commands/$action.md" >&2
    exit 1
  }

  expected=$(mktemp "${TMPDIR:-/tmp}/scv-command.XXXXXX")
  awk '
    NR == 1 && $0 == "---" { print; in_frontmatter=1; next }
    in_frontmatter { print; if ($0 == "---") exit }
  ' "$command" > "$expected"
  printf '\n' >> "$expected"
  cat "$protocol" >> "$expected"
  python3 - "$command" "$expected" <<'PY'
import os
import stat
import sys
from pathlib import Path

source = Path(sys.argv[1])
target = Path(sys.argv[2])
os.chmod(target, stat.S_IMODE(source.lstat().st_mode))
PY

  if [[ "$MODE" == check ]]; then
    if ! cmp -s "$expected" "$command"; then
      echo "PROJECTION_MISMATCH: commands/$action.md (core body)"
      FAILURES=$((FAILURES + 1))
    fi
  else
    safe_remove_destination "$command"
    safe_copy_file "$expected" "$command"
    rm -f "$expected"
    expected=
  fi
  [[ -z "${expected:-}" ]] || rm -f "$expected"
done

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
