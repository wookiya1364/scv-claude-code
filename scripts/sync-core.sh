#!/usr/bin/env bash
# Explicit maintainer tool for pinning a local or released SCV Core payload.
# Installed SCV commands never call this script automatically.
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
PROFILE="$REPO_ROOT/adapter/claude-code.env"
PLUGIN_MANIFEST="$REPO_ROOT/.claude-plugin/plugin.json"
MARKETPLACE_MANIFEST="$REPO_ROOT/.claude-plugin/marketplace.json"
PATH_HELPER_SOURCE="$SCRIPT_DIR/sync-core-paths.py"
SOURCE_REPO="wookiya1364/scv-core"
SOURCE_DIR=
VERSION=
LATEST=0
DRY_RUN=0

usage() {
  cat <<'EOF'
Usage:
  scripts/sync-core.sh --source /path/to/scv-core [--dry-run]
  scripts/sync-core.sh --version 0.20.0 [--repository owner/repo] [--dry-run]
  scripts/sync-core.sh --latest [--repository owner/repo] [--dry-run]

The local form invokes the core repository's vendor tool directly. Release
forms download the immutable release artifact and its SHA-256 sidecar before
materializing the Claude Code profile. No plugin runtime path calls this tool.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      [[ $# -ge 2 ]] || { echo "ERROR: --source requires a directory" >&2; exit 2; }
      SOURCE_DIR=$2
      shift 2
      ;;
    --version)
      [[ $# -ge 2 ]] || { echo "ERROR: --version requires a version" >&2; exit 2; }
      VERSION=${2#v}
      shift 2
      ;;
    --latest)
      LATEST=1
      shift
      ;;
    --repository)
      [[ $# -ge 2 ]] || { echo "ERROR: --repository requires owner/repo" >&2; exit 2; }
      SOURCE_REPO=$2
      shift 2
      ;;
    --dry-run)
      DRY_RUN=1
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

mode_count=0
[[ -n "$SOURCE_DIR" ]] && mode_count=$((mode_count + 1))
[[ -n "$VERSION" ]] && mode_count=$((mode_count + 1))
(( LATEST )) && mode_count=$((mode_count + 1))
[[ "$mode_count" -eq 1 ]] || {
  echo "ERROR: choose exactly one of --source, --version, or --latest" >&2
  exit 2
}
[[ "$SOURCE_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || {
  echo "ERROR: --repository must be an owner/repository slug" >&2
  exit 2
}
[[ -f "$PROFILE" ]] || { echo "ERROR: missing adapter profile: $PROFILE" >&2; exit 1; }
[[ -f "$PLUGIN_MANIFEST" ]] || { echo "ERROR: missing Claude plugin manifest: $PLUGIN_MANIFEST" >&2; exit 1; }
[[ -f "$MARKETPLACE_MANIFEST" ]] || { echo "ERROR: missing Claude marketplace manifest: $MARKETPLACE_MANIFEST" >&2; exit 1; }
[[ -f "$PATH_HELPER_SOURCE" && ! -L "$PATH_HELPER_SOURCE" ]] || {
  echo "ERROR: missing safe path helper: $PATH_HELPER_SOURCE" >&2
  exit 1
}

for git_override in \
  GIT_DIR \
  GIT_WORK_TREE \
  GIT_INDEX_FILE \
  GIT_COMMON_DIR \
  GIT_OBJECT_DIRECTORY \
  GIT_ALTERNATE_OBJECT_DIRECTORIES \
  GIT_NAMESPACE; do
  if [[ -n "${!git_override:-}" ]]; then
    echo "ERROR: unsupported Git repository override: $git_override" >&2
    exit 1
  fi
done
# Every Git subprocess in this maintainer tool is observational. Prevent
# read-only diff/index queries from opportunistically rewriting index stat
# metadata before the updater acquires its short-lived canonical index lock.
export GIT_OPTIONAL_LOCKS=0

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/scv-claude-core-sync.XXXXXX")
TMP_DIR="$(cd "$TMP_DIR" && pwd -P)"
PATH_HELPER="$TMP_DIR/sync-core-paths.py"
cp -p "$PATH_HELPER_SOURCE" "$PATH_HELPER"
REPO_ID=$(python3 -B "$PATH_HELPER" identity --path "$REPO_ROOT")
REPO_DEVICE=${REPO_ID%%:*}
REPO_INODE=${REPO_ID#*:}
exec {REPO_FD}<"$REPO_ROOT"
[[ "$(python3 -B "$PATH_HELPER" identity-fd --fd "$REPO_FD")" == "$REPO_ID" ]] || {
  echo "ERROR: repository changed while opening its identity descriptor" >&2
  exit 1
}
CANDIDATE="$TMP_DIR/scv-core"
SYNC_LOCK="$REPO_ROOT/.scv-core-sync.lock"
SYNC_LOCK_NAME=.scv-core-sync.lock
LOCK_OWNED=0
LOCK_TOKEN=
LOCK_PROCESS_START=
LOCK_DEVICE=
LOCK_INODE=
GIT_INDEX_LOCK=
GIT_INDEX_LOCK_NAME=
GIT_INDEX_PARENT=
GIT_INDEX_PARENT_DEVICE=
GIT_INDEX_PARENT_INODE=
GIT_INDEX_PARENT_FD=
GIT_INDEX_LOCK_OWNED=0
GIT_INDEX_LOCK_TOKEN=
GIT_INDEX_LOCK_DEVICE=
GIT_INDEX_LOCK_INODE=
TX_INDEX_FINGERPRINT=
TX_ROOT=
TX_ROOT_RELATIVE=
TX_DEVICE=
TX_INODE=
TX_STAGE=
TX_BACKUP=
TX_ACTIVE=0
TX_COMMITTED=0
TX_ROLLING_BACK=0
TX_PATHS=()
TX_ORIGINAL_STATES=()
TX_STAGE_INSTALLED=()
TX_INSTALLED_DIGESTS=()
TX_DECK_INVENTORY=()
TX_DECK_INVENTORY_FILE=
TX_PRESERVED_PATHS=()
TX_EXPECTED_STATES=()
TX_EXPECTED_DIGESTS=()
TRANSACTION_PATHS=(
  vendor
  core.lock
  scripts
  commands
  tests
  template
  DeckUI
  assets
  protocols
  ralph-template-scv.md
  TEMPLATE_VERSION
  host-profile.env
)

path_exists() {
  [[ -e "$1" || -L "$1" ]]
}

process_start_id() {
  python3 - "$1" <<'PY'
import sys
from pathlib import Path

path = Path("/proc") / sys.argv[1] / "stat"
try:
    # Everything after the final ')' starts at proc field 3. Field 22 is index
    # 19 in that suffix and disambiguates a reused PID.
    print(path.read_text(encoding="utf-8").rsplit(")", 1)[1].split()[19])
except (IndexError, OSError):
    print("unknown")
PY
}

release_sync_lock() {
  (( LOCK_OWNED )) || return 0
  python3 -B "$PATH_HELPER" lock-release \
    --parent-fd "$REPO_FD" \
    --lock-name "$SYNC_LOCK_NAME" \
    --pid "$$" \
    --process-start "$LOCK_PROCESS_START" \
    --token "$LOCK_TOKEN" \
    --expected-parent-device "$REPO_DEVICE" \
    --expected-parent-inode "$REPO_INODE" \
    --expected-lock-device "$LOCK_DEVICE" \
    --expected-lock-inode "$LOCK_INODE" || {
      echo "WARNING: sync lock ownership changed; refusing unsafe removal" >&2
      return 1
    }
  LOCK_OWNED=0
}

release_git_index_lock() {
  (( GIT_INDEX_LOCK_OWNED )) || return 0
  python3 -B "$PATH_HELPER" file-lock-release \
    --parent-fd "$GIT_INDEX_PARENT_FD" \
    --lock-name "$GIT_INDEX_LOCK_NAME" \
    --token "$GIT_INDEX_LOCK_TOKEN" \
    --expected-parent-device "$GIT_INDEX_PARENT_DEVICE" \
    --expected-parent-inode "$GIT_INDEX_PARENT_INODE" \
    --expected-lock-device "$GIT_INDEX_LOCK_DEVICE" \
    --expected-lock-inode "$GIT_INDEX_LOCK_INODE" || {
      echo "WARNING: Git index lock ownership changed; refusing unsafe removal" >&2
      return 1
    }
  GIT_INDEX_LOCK_OWNED=0
}

prepare_git_index_lock_anchor() {
  local raw_lock parent_id observed_id
  raw_lock=$(git -C "$REPO_ROOT" rev-parse --git-path index.lock)
  case "$raw_lock" in
    /*) GIT_INDEX_LOCK=$raw_lock ;;
    *) GIT_INDEX_LOCK="$REPO_ROOT/$raw_lock" ;;
  esac
  GIT_INDEX_LOCK_NAME=${GIT_INDEX_LOCK##*/}
  GIT_INDEX_PARENT=${GIT_INDEX_LOCK%/*}
  GIT_INDEX_PARENT="$(cd "$GIT_INDEX_PARENT" && pwd -P)"
  GIT_INDEX_LOCK="$GIT_INDEX_PARENT/$GIT_INDEX_LOCK_NAME"
  parent_id=$(python3 -B "$PATH_HELPER" identity --path "$GIT_INDEX_PARENT")
  GIT_INDEX_PARENT_DEVICE=${parent_id%%:*}
  GIT_INDEX_PARENT_INODE=${parent_id#*:}
  exec {GIT_INDEX_PARENT_FD}<"$GIT_INDEX_PARENT"
  observed_id=$(python3 -B "$PATH_HELPER" identity-fd \
    --fd "$GIT_INDEX_PARENT_FD")
  [[ "$observed_id" == "$parent_id" ]] || {
    echo "ERROR: Git index parent changed while opening" >&2
    return 1
  }
}

acquire_git_index_lock() {
  local lock_id
  GIT_INDEX_LOCK_TOKEN=$(python3 -c 'import secrets; print(secrets.token_hex(24))')
  lock_id=$(python3 -B "$PATH_HELPER" file-lock-acquire \
    --parent-fd "$GIT_INDEX_PARENT_FD" \
    --lock-name "$GIT_INDEX_LOCK_NAME" \
    --token "$GIT_INDEX_LOCK_TOKEN" \
    --expected-parent-device "$GIT_INDEX_PARENT_DEVICE" \
    --expected-parent-inode "$GIT_INDEX_PARENT_INODE") || {
      echo "ERROR: Git index is locked by another process: $GIT_INDEX_LOCK" >&2
      return 1
    }
  GIT_INDEX_LOCK_DEVICE=${lock_id%%:*}
  GIT_INDEX_LOCK_INODE=${lock_id#*:}
  [[ "$GIT_INDEX_LOCK_DEVICE" =~ ^[0-9]+$ &&
     "$GIT_INDEX_LOCK_INODE" =~ ^[0-9]+$ ]] || {
    echo "ERROR: safe path helper returned an invalid Git lock identity" >&2
    return 1
  }
  GIT_INDEX_LOCK_OWNED=1
}

scoped_index_fingerprint() {
  python3 - "$REPO_ROOT" "${TRANSACTION_PATHS[@]}" <<'PY'
import hashlib
import subprocess
import sys

repo, *scopes = sys.argv[1:]
digest = hashlib.sha256()
for arguments in (
    ("ls-files", "--stage", "-z", "--", *scopes),
    ("ls-files", "-v", "-z", "--", *scopes),
):
    digest.update(
        subprocess.check_output(
            ["git", "-C", repo, *arguments],
            stderr=subprocess.DEVNULL,
        )
    )
    digest.update(b"\0SCV-INDEX-SECTION\0")
print(digest.hexdigest())
PY
}

validate_index_preimage() {
  local current
  current=$(scoped_index_fingerprint)
  [[ "$current" == "$TX_INDEX_FINGERPRINT" ]] || {
    echo "ERROR: scoped Git index changed during Core sync" >&2
    return 1
  }
}

acquire_sync_lock() {
  local lock_id
  LOCK_TOKEN=$(python3 -c 'import secrets; print(secrets.token_hex(24))')
  LOCK_PROCESS_START=$(process_start_id "$$")
  lock_id=$(python3 -B "$PATH_HELPER" lock-acquire \
    --parent "$REPO_ROOT" \
    --lock-name "$SYNC_LOCK_NAME" \
    --pid "$$" \
    --process-start "$LOCK_PROCESS_START" \
    --token "$LOCK_TOKEN" \
    --expected-parent-device "$REPO_DEVICE" \
    --expected-parent-inode "$REPO_INODE") || return 1
  LOCK_DEVICE=${lock_id%%:*}
  LOCK_INODE=${lock_id#*:}
  [[ "$LOCK_DEVICE" =~ ^[0-9]+$ && "$LOCK_INODE" =~ ^[0-9]+$ ]] || {
    echo "ERROR: safe path helper returned an invalid lock identity" >&2
    return 1
  }
  LOCK_OWNED=1
}

quarantine_owned_live() {
  local index=$1 relative=$2 live=$3 installed installed_digest
  local discard inventory= current_digest
  installed=${TX_STAGE_INSTALLED[$index]:-no}
  installed_digest=${TX_INSTALLED_DIGESTS[$index]:-}
  if [[ "$installed" != yes || -z "$installed_digest" ]]; then
    echo "ERROR: rollback found an unowned live path: $relative" >&2
    return 1
  fi
  discard="rollback-discard/$relative"
  guarded_rename_noreplace \
    repository "$relative" \
    transaction "rollback-discard/$relative" \
    "rollback-discard:$relative" || return 1
  [[ "$relative" != DeckUI ]] || inventory=$TX_DECK_INVENTORY_FILE
  current_digest=$(path_fingerprint "$discard" "$inventory")
  if [[ "$current_digest" != "$installed_digest" ]]; then
    echo "ERROR: rollback quarantined a concurrently modified live path: $relative" >&2
    return 1
  fi
}

rollback_transaction() {
  local index relative live backup original_state preserved_live preserved_backup
  local installed installed_digest current_digest inventory failures=0
  local deck_preserve_failures=0
  (( TX_ACTIVE )) || return 0
  (( TX_COMMITTED == 0 )) || return 0
  (( TX_ROLLING_BACK == 0 )) || return 0
  TX_ROLLING_BACK=1
  trap '' HUP INT TERM

  if [[ -n "${SCV_CORE_SYNC_ROLLBACK_SIGNAL:-}" ]]; then
    case "$SCV_CORE_SYNC_ROLLBACK_SIGNAL" in
      HUP|INT|TERM) kill "-$SCV_CORE_SYNC_ROLLBACK_SIGNAL" "$$" ;;
      *)
        echo "ERROR: invalid rollback signal test hook" >&2
        failures=$((failures + 1))
        ;;
    esac
  fi

  # Untracked/ignored DeckUI paths move from the exact old tree into the new
  # tree only after its directory swap. Put them back before restoring it.
  for (( index=${#TX_PRESERVED_PATHS[@]} - 1; index >= 0; index-- )); do
    relative=${TX_PRESERVED_PATHS[$index]}
    preserved_live="$REPO_ROOT/$relative"
    preserved_backup="$TX_BACKUP/$relative"
    if [[ "${SCV_CORE_SYNC_ROLLBACK_FAILPOINT:-}" == "preserved-collision:$relative" ]]; then
      mkdir -p "$preserved_backup"
      printf 'injected preserved-path collision\n' \
        > "$preserved_backup/.scv-rollback-collision"
    fi
    if path_exists "$preserved_live"; then
      if path_exists "$preserved_backup"; then
        echo "ERROR: rollback destination already exists: $preserved_backup" >&2
        failures=$((failures + 1))
        deck_preserve_failures=$((deck_preserve_failures + 1))
        continue
      fi
      if ! guarded_rename_noreplace \
        repository "$relative" \
        transaction "backup/$relative" \
        "rollback-preserved:$relative"; then
        echo "ERROR: could not restore preserved path to backup: $relative" >&2
        failures=$((failures + 1))
        deck_preserve_failures=$((deck_preserve_failures + 1))
      fi
    else
      echo "ERROR: preserved path disappeared during rollback: $relative" >&2
      failures=$((failures + 1))
      deck_preserve_failures=$((deck_preserve_failures + 1))
    fi
  done

  for (( index=${#TX_PATHS[@]} - 1; index >= 0; index-- )); do
    relative=${TX_PATHS[$index]}
    original_state=${TX_ORIGINAL_STATES[$index]}
    installed=${TX_STAGE_INSTALLED[$index]:-no}
    installed_digest=${TX_INSTALLED_DIGESTS[$index]:-}
    live="$REPO_ROOT/$relative"
    backup="$TX_BACKUP/$relative"
    if [[ "$relative" == DeckUI && "$deck_preserve_failures" -gt 0 ]]; then
      echo "ERROR: rollback preserves live and backup DeckUI after runtime restore failure" >&2
      continue
    fi
    if [[ "$original_state" == present ]]; then
      if path_exists "$backup"; then
        if [[ "${SCV_CORE_SYNC_ROLLBACK_FAILPOINT:-}" == "restore:$relative" ]]; then
          echo "ERROR: injected rollback restore failure for $relative" >&2
          failures=$((failures + 1))
          continue
        fi
        if path_exists "$live"; then
          if ! quarantine_owned_live "$index" "$relative" "$live"; then
            echo "ERROR: rollback could not quarantine staged live path: $relative" >&2
            failures=$((failures + 1))
            continue
          fi
        fi
        if ! guarded_rename_noreplace \
          transaction "backup/$relative" \
          repository "$relative" \
          "rollback-restore:$relative"; then
          echo "ERROR: rollback could not restore original path: $relative" >&2
          failures=$((failures + 1))
        fi
      else
        echo "ERROR: rollback backup is missing for original path: $relative" >&2
        failures=$((failures + 1))
      fi
    elif path_exists "$live"; then
      if ! quarantine_owned_live "$index" "$relative" "$live"; then
        echo "ERROR: rollback could not quarantine path while restoring absence: $relative" >&2
        failures=$((failures + 1))
      fi
    fi
  done

  if (( failures > 0 )); then
    echo "ERROR: rollback incomplete; recovery backup preserved at $TX_ROOT" >&2
    return 1
  fi
  TX_ACTIVE=0
  return 0
}

finish_on_exit() {
  local status=$? rollback_status=0 preserve_transaction=0
  trap - EXIT ERR
  trap '' HUP INT TERM
  set +e
  rollback_transaction || rollback_status=$?
  if (( rollback_status != 0 )); then
    preserve_transaction=1
    (( status != 0 )) || status=$rollback_status
  fi
  if (( preserve_transaction == 0 )) && [[ -n "$TX_ROOT" ]]; then
    cleanup_transaction_tree || {
      (( status != 0 )) || status=1
    }
  fi
  release_git_index_lock || {
    (( status != 0 )) || status=1
  }
  if [[ -n "$GIT_INDEX_PARENT_FD" ]]; then
    exec {GIT_INDEX_PARENT_FD}<&-
  fi
  release_sync_lock || {
    (( status != 0 )) || status=1
  }
  exec {REPO_FD}<&-
  if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
    rm -rf -- "$TMP_DIR"
  fi
  exit "$status"
}

exit_on_error() {
  local status=$1
  exit "$status"
}

exit_on_signal() {
  exit "$1"
}

validate_live_worktree() {
  python3 - "$REPO_ROOT" <<'PY'
import os
import stat
import subprocess
import sys
from pathlib import Path

repo = Path(sys.argv[1])
scopes = (
    "vendor",
    "core.lock",
    "scripts",
    "commands",
    "tests",
    "template",
    "DeckUI",
    "assets",
    "protocols",
    "ralph-template-scv.md",
    "TEMPLATE_VERSION",
    "host-profile.env",
)
protected_local_scopes = tuple(scope for scope in scopes if scope != "DeckUI")
adapter_owned = {
    "scripts/apply-model-policy.sh",
    "scripts/hydrate.sh",
    "scripts/project-core.sh",
    "scripts/sync-core.sh",
    "scripts/sync.sh",
    "scripts/update.sh",
    "scripts/verify-core.sh",
    "tests/test-apply-model-policy.sh",
    "tests/test-core-contract.sh",
    "tests/test-sync-core-atomicity.sh",
    "tests/test-state-adapter.sh",
    "commands/set-models.md",
    "commands/update.md",
}

def git(*arguments: str) -> bytes:
    return subprocess.check_output(
        ["git", "-C", str(repo), *arguments], stderr=subprocess.DEVNULL
    )

try:
    top = Path(git("rev-parse", "--show-toplevel").decode().strip()).resolve()
except subprocess.CalledProcessError:
    raise SystemExit("ERROR: Core sync requires the wrapper repository Git index")
if top != repo:
    raise SystemExit("ERROR: Core sync must run at the wrapper Git worktree root")

def names(*arguments: str):
    return {
        os.fsdecode(value).rstrip("/")
        for value in git(*arguments).split(b"\0")
        if value
    }

def in_scope(path: str) -> bool:
    return any(path == scope or path.startswith(scope + "/") for scope in scopes)

def is_preserved_wrapper_path(path: str) -> bool:
    return path in adapter_owned or (
        path.startswith("vendor/") and not path.startswith("vendor/scv-core/")
    )

def frontmatter_body(data: bytes):
    lines = data.splitlines(keepends=True)
    if not lines or lines[0].strip() != b"---":
        return None
    for index in range(1, len(lines)):
        if lines[index].strip() == b"---":
            return b"".join(lines[index + 1 :])
    return None

def command_frontmatter_only(path: str) -> bool:
    if not (
        path.startswith("commands/")
        and path.endswith(".md")
        and path not in adapter_owned
    ):
        return False
    live = repo / path
    try:
        if not stat.S_ISREG(live.lstat().st_mode):
            return False
        current_body = frontmatter_body(live.read_bytes())
        committed_body = frontmatter_body(git("show", f"HEAD:{path}"))
        indexed_body = frontmatter_body(git("show", f":{path}"))
    except (OSError, subprocess.CalledProcessError):
        return False
    return (
        current_body is not None
        and current_body == committed_body
        and current_body == indexed_body
    )

dirty = names(
    "diff", "--name-only", "-z", "--diff-filter=ACDMRTUXB", "--", *scopes
) | names(
    "diff", "--cached", "--name-only", "-z", "--diff-filter=ACDMRTUXB",
    "--", *scopes
)
untracked = names(
    "ls-files", "--others", "--exclude-standard", "-z",
    "--", *protected_local_scopes
)
ignored = names(
    "ls-files", "--others", "--ignored", "--exclude-standard", "-z",
    "--", *protected_local_scopes
)
flagged = set()
for record in git("ls-files", "-v", "-z", "--", *scopes).split(b"\0"):
    if not record:
        continue
    if len(record) < 3 or record[1:2] != b" ":
        raise SystemExit("ERROR: could not parse scoped Git index flags")
    tag = chr(record[0])
    path = os.fsdecode(record[2:])
    if tag.islower() or tag == "S":
        flagged.add(path)

mode_mismatches = set()
content_or_type_mismatches = set()
unmerged = set()
index_modes = {}
index_entries = {}
for record in git("ls-files", "--stage", "-z", "--", *scopes).split(b"\0"):
    if not record:
        continue
    try:
        metadata, encoded_path = record.split(b"\t", 1)
        index_mode, object_id, stage = metadata.split()
    except ValueError:
        raise SystemExit("ERROR: could not parse scoped Git index mode")
    path = os.fsdecode(encoded_path)
    if stage != b"0":
        unmerged.add(path)
        continue
    index_modes[path] = index_mode
    index_entries[path] = (index_mode, object_id)
    mode_is_core_owned = (
        path not in adapter_owned
        and not path.startswith("commands/")
        and not (
            path.startswith("vendor/")
            and not path.startswith("vendor/scv-core/")
        )
    )
    if not mode_is_core_owned or index_mode not in {b"100644", b"100755"}:
        continue
    live = repo / path
    try:
        live_mode = live.lstat().st_mode
    except FileNotFoundError:
        continue
    if not stat.S_ISREG(live_mode):
        continue
    expected_executable = index_mode == b"100755"
    actual_executable = bool(stat.S_IMODE(live_mode) & stat.S_IXUSR)
    if expected_executable != actual_executable:
        mode_mismatches.add(path)

regular_paths = []
symlink_paths = []
for path, (index_mode, object_id) in index_entries.items():
    if is_preserved_wrapper_path(path) or command_frontmatter_only(path):
        continue
    live = repo / path
    try:
        live_mode = live.lstat().st_mode
        if index_mode in {b"100644", b"100755"}:
            if not stat.S_ISREG(live_mode):
                content_or_type_mismatches.add(path)
                continue
            regular_paths.append(path)
        elif index_mode == b"120000":
            if not stat.S_ISLNK(live_mode):
                content_or_type_mismatches.add(path)
                continue
            symlink_paths.append(path)
        else:
            content_or_type_mismatches.add(path)
            continue
    except OSError:
        content_or_type_mismatches.add(path)
        continue

live_hashes = {}
batch_paths = [
    path for path in regular_paths if "\n" not in path and not path.startswith('"')
]
if batch_paths:
    process = subprocess.Popen(
        ["git", "-C", str(repo), "hash-object", "--stdin-paths"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    output, error = process.communicate(
        b"".join(os.fsencode(path) + b"\n" for path in batch_paths)
    )
    hashes = output.splitlines()
    if process.returncode != 0 or len(hashes) != len(batch_paths):
        raise SystemExit(
            "ERROR: could not hash scoped worktree files with Git filters: "
            + error.decode("utf-8", "replace").strip()
        )
    live_hashes.update(zip(batch_paths, hashes))

for path in regular_paths:
    if path in live_hashes:
        continue
    try:
        live_hashes[path] = git(
            "hash-object", f"--path={path}", "--", path
        ).strip()
    except subprocess.CalledProcessError:
        content_or_type_mismatches.add(path)

for path in regular_paths:
    if live_hashes.get(path) != index_entries[path][1]:
        content_or_type_mismatches.add(path)

for path in symlink_paths:
    try:
        live_data = os.fsencode(os.readlink(repo / path))
        indexed_data = git("show", f":{path}")
    except (OSError, subprocess.CalledProcessError):
        content_or_type_mismatches.add(path)
        continue
    if live_data != indexed_data:
        content_or_type_mismatches.add(path)

violations = []
for path in sorted(adapter_owned):
    live = repo / path
    try:
        live_mode = live.lstat().st_mode
    except FileNotFoundError:
        live_mode = 0
    if (
        not stat.S_ISREG(live_mode)
        or index_modes.get(path) not in {b"100644", b"100755"}
    ):
        violations.append(("adapter-owned path type change", path))
for path in sorted(unmerged):
    violations.append(("unmerged Git index entry", path))
for path in sorted(flagged):
    violations.append(("unsafe Git index flag", path))
for path in sorted(mode_mismatches):
    violations.append(("tracked executable-mode change", path))
for path in sorted(content_or_type_mismatches):
    violations.append(("tracked change", path))
for path in sorted(dirty):
    if not in_scope(path):
        continue
    if is_preserved_wrapper_path(path) or command_frontmatter_only(path):
        continue
    if path in content_or_type_mismatches:
        continue
    violations.append(("tracked change", path))

for path in sorted(untracked | ignored):
    if not in_scope(path) or path == "DeckUI" or path.startswith("DeckUI/"):
        continue
    if path in adapter_owned:
        continue
    violations.append(("local-only path", path))

if violations:
    for kind, path in violations[:20]:
        print(
            f"ERROR: Core sync would overwrite {kind}: {path}",
            file=sys.stderr,
        )
    if len(violations) > 20:
        print(
            f"ERROR: and {len(violations) - 20} more protected worktree paths",
            file=sys.stderr,
        )
    raise SystemExit(
        "ERROR: commit, move, or remove protected local changes before Core sync"
    )
PY
}

trap finish_on_exit EXIT
trap 'exit_on_error $?' ERR
trap 'exit_on_signal 129' HUP
trap 'exit_on_signal 130' INT
trap 'exit_on_signal 143' TERM

acquire_sync_lock
prepare_git_index_lock_anchor

orphan_transaction=
for recovery_candidate in \
  "$REPO_ROOT"/.scv-core-transaction.* \
  "$REPO_ROOT"/.scv-core-sync-quarantine.*; do
  if path_exists "$recovery_candidate"; then
    orphan_transaction=$recovery_candidate
    break
  fi
done
[[ -z "$orphan_transaction" ]] || {
  echo "ERROR: unfinished Core transaction requires manual recovery: $orphan_transaction" >&2
  exit 1
}

if [[ -n "${SCV_CORE_SYNC_LOCK_HOLD_FILE:-}" ]]; then
  printf 'ready\n' > "$SCV_CORE_SYNC_LOCK_HOLD_FILE.ready"
  while [[ -e "$SCV_CORE_SYNC_LOCK_HOLD_FILE" ]]; do
    sleep 0.05
  done
fi

VENDOR_PARENT="$REPO_ROOT/vendor"
VENDOR_TARGET="$VENDOR_PARENT/scv-core"
if path_exists "$VENDOR_PARENT"; then
  [[ -d "$VENDOR_PARENT" && ! -L "$VENDOR_PARENT" ]] || {
    echo "ERROR: vendor must be a real repository directory, not a link or file" >&2
    exit 1
  }
  [[ "$(cd "$VENDOR_PARENT" && pwd -P)" == "$VENDOR_PARENT" ]] || {
    echo "ERROR: vendor resolves outside its repository path" >&2
    exit 1
  }
fi

validate_live_worktree

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    echo "ERROR: sha256sum or shasum is required" >&2
    return 1
  fi
}

download() {
  local url=$1 output=$2
  command -v curl >/dev/null 2>&1 || {
    echo "ERROR: curl is required for release sync" >&2
    return 1
  }
  curl --fail --location --silent --show-error \
    --retry 3 --retry-delay 1 \
    --output "$output" "$url"
}

resolve_release_commit() {
  local tag=$1 metadata commit
  if command -v gh >/dev/null 2>&1; then
    commit=$(gh api "repos/$SOURCE_REPO/commits/$tag" --jq .sha)
  else
    metadata="$TMP_DIR/tag-commit.json"
    download "https://api.github.com/repos/$SOURCE_REPO/commits/$tag" "$metadata"
    commit=$(python3 -c \
      'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["sha"])' \
      "$metadata")
  fi
  [[ "$commit" =~ ^[0-9a-f]{40}$ ]] || {
    echo "ERROR: release tag did not resolve to a full commit id: $tag" >&2
    return 1
  }
  printf '%s\n' "$commit"
}

validate_release_provenance() {
  local release_root=$1 expected_version=$2 expected_repository=$3 expected_commit=$4
  python3 - \
    "$release_root" "$expected_version" "$expected_repository" "$expected_commit" <<'PY'
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
expected_version = sys.argv[2]
expected_repository = sys.argv[3].rstrip("/").removesuffix(".git")
expected_commit = sys.argv[4]

def normalize_repository(value: str) -> str:
    value = value.strip().rstrip("/")
    if value.endswith(".git"):
        value = value[:-4]
    if value.startswith("git@github.com:"):
        value = "https://github.com/" + value.removeprefix("git@github.com:")
    return value

version = (root / "VERSION").read_text(encoding="utf-8").strip()
source_commit = (root / "SOURCE_COMMIT").read_text(encoding="utf-8").strip()
source_info = (root / "SOURCE_INFO").read_text(encoding="utf-8").splitlines()
repositories = [
    line.split(":", 1)[1].strip()
    for line in source_info
    if line.startswith("source_repository:")
]
if len(repositories) != 1:
    raise SystemExit("ERROR: release SOURCE_INFO must contain exactly one source_repository")
source_repository = normalize_repository(repositories[0])
manifest = json.loads((root / "core-manifest.json").read_text(encoding="utf-8"))

if version != expected_version:
    raise SystemExit(
        f"ERROR: requested Core v{expected_version} but release payload VERSION is {version}"
    )
if str(manifest.get("version")) != expected_version:
    raise SystemExit("ERROR: release manifest version does not match the requested Core version")
if source_repository != expected_repository:
    raise SystemExit(
        "ERROR: release SOURCE_INFO repository does not match the requested repository"
    )
if normalize_repository(str(manifest.get("source_repository", ""))) != expected_repository:
    raise SystemExit(
        "ERROR: release manifest repository does not match the requested repository"
    )
if not re.fullmatch(r"[0-9a-f]{40}", source_commit):
    raise SystemExit("ERROR: release SOURCE_COMMIT is not a full lowercase commit id")
if source_commit != expected_commit:
    raise SystemExit("ERROR: release SOURCE_COMMIT does not match the requested tag commit")
if str(manifest.get("source_commit")) != expected_commit:
    raise SystemExit("ERROR: release manifest commit does not match the requested tag commit")
if manifest.get("profile_id") != "canonical":
    raise SystemExit("ERROR: release source manifest is not the canonical Core profile")
PY
}

validate_candidate_provenance() {
  local candidate=$1 source_root=${2:-} expected_version=${3:-}
  local expected_repository=${4:-} expected_commit=${5:-} artifact_sha=${6:-}
  python3 - \
    "$candidate" "$source_root" "$expected_version" \
    "$expected_repository" "$expected_commit" "$artifact_sha" <<'PY'
import hashlib
import json
import sys
from pathlib import Path

candidate = Path(sys.argv[1])
source_root = Path(sys.argv[2]) if sys.argv[2] else None
expected_version, expected_repository, expected_commit, artifact_sha = sys.argv[3:]
lock = json.loads((candidate / "core.lock.json").read_text(encoding="utf-8"))

def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()

if lock.get("manifest_sha256") != digest(candidate / "core-manifest.json"):
    raise SystemExit("ERROR: candidate lock manifest_sha256 does not match core-manifest.json")
if lock.get("payload_sha256") != digest(candidate / "SHA256SUMS"):
    raise SystemExit("ERROR: candidate lock payload_sha256 does not match SHA256SUMS")

if source_root is not None:
    if lock.get("source_manifest_sha256") != digest(source_root / "core-manifest.json"):
        raise SystemExit(
            "ERROR: candidate lock source_manifest_sha256 does not match the source manifest"
        )
    if lock.get("source_payload_sha256") != digest(source_root / "SHA256SUMS"):
        raise SystemExit(
            "ERROR: candidate lock source_payload_sha256 does not match the source payload"
        )

if expected_version:
    if (candidate / "VERSION").read_text(encoding="utf-8").strip() != expected_version:
        raise SystemExit("ERROR: materialized Core VERSION differs from the requested release")
    if str(lock.get("core_version")) != expected_version:
        raise SystemExit("ERROR: candidate lock version differs from the requested release")
    if str(lock.get("source_repository", "")).rstrip("/").removesuffix(".git") != expected_repository:
        raise SystemExit("ERROR: candidate lock repository differs from the requested release")
    if lock.get("source_commit") != expected_commit:
        raise SystemExit("ERROR: candidate lock commit differs from the requested tag")
    if lock.get("artifact_sha256") != artifact_sha:
        raise SystemExit("ERROR: candidate lock artifact digest differs from the verified release")
PY
}

if [[ -n "$SOURCE_DIR" ]]; then
  SOURCE_DIR="$(cd "$SOURCE_DIR" 2>/dev/null && pwd -P)" || {
    echo "ERROR: local core source not found: $SOURCE_DIR" >&2
    exit 1
  }
  VENDOR_TOOL="$SOURCE_DIR/tools/vendor-core.sh"
  [[ -x "$VENDOR_TOOL" ]] || {
    echo "ERROR: local core vendor tool is missing or not executable: $VENDOR_TOOL" >&2
    exit 1
  }
  LOCAL_SOURCE_ROOT="$TMP_DIR/local-source"
  source_git_root=$(git -C "$SOURCE_DIR" rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -n "$source_git_root" &&
        "$(cd "$source_git_root" && pwd -P)" == "$SOURCE_DIR" ]]; then
    EXPORT_TOOL="$SOURCE_DIR/tools/export-core.sh"
    [[ -x "$EXPORT_TOOL" ]] || {
      echo "ERROR: local Core checkout lacks tools/export-core.sh" >&2
      exit 1
    }
    "$EXPORT_TOOL" --output "$LOCAL_SOURCE_ROOT" >/dev/null
  else
    cp -R -p "$SOURCE_DIR" "$LOCAL_SOURCE_ROOT"
    "$LOCAL_SOURCE_ROOT/tools/verify-core.sh" --root "$LOCAL_SOURCE_ROOT"
  fi
  VENDOR_TOOL="$LOCAL_SOURCE_ROOT/tools/vendor-core.sh"
  "$VENDOR_TOOL" \
    --source "$LOCAL_SOURCE_ROOT" \
    --target "$CANDIDATE" \
    --profile "$PROFILE"
else
  if (( LATEST )); then
    command -v gh >/dev/null 2>&1 || {
      echo "ERROR: gh is required to resolve --latest; pass --version instead" >&2
      exit 1
    }
    tag=$(gh api "repos/$SOURCE_REPO/releases/latest" --jq .tag_name)
    VERSION=${tag#v}
  fi
  [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || {
    echo "ERROR: invalid core version: $VERSION" >&2
    exit 1
  }

  release_tag="v${VERSION}"
  release_commit=$(resolve_release_commit "$release_tag")
  release_repository="https://github.com/${SOURCE_REPO}"
  asset="scv-core-v${VERSION}.tar.gz"
  base="${release_repository}/releases/download/${release_tag}"
  download "$base/$asset" "$TMP_DIR/$asset"
  download "$base/$asset.sha256" "$TMP_DIR/$asset.sha256"

  expected=$(awk 'NF {print $1; exit}' "$TMP_DIR/$asset.sha256")
  actual=$(sha256_file "$TMP_DIR/$asset")
  [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || {
    echo "ERROR: release checksum sidecar is invalid" >&2
    exit 1
  }
  expected_lower=$(printf '%s' "$expected" | tr '[:upper:]' '[:lower:]')
  actual_lower=$(printf '%s' "$actual" | tr '[:upper:]' '[:lower:]')
  [[ "$expected_lower" == "$actual_lower" ]] || {
    echo "ERROR: release artifact checksum mismatch" >&2
    exit 1
  }

  top="scv-core-v${VERSION}"
  python3 - "$TMP_DIR/$asset" "$top" <<'PY'
import pathlib
import sys
import tarfile

archive = pathlib.Path(sys.argv[1])
expected_root = sys.argv[2]
seen = set()

with tarfile.open(archive, mode="r:gz") as handle:
    for member in handle.getmembers():
        raw = member.name
        normalized = raw.rstrip("/")
        parts = normalized.split("/")
        if (
            not normalized
            or raw.startswith("/")
            or any(part in {"", ".", ".."} for part in parts)
            or parts[0] != expected_root
        ):
            raise SystemExit(
                f"ERROR: release archive contains an unsafe path: {raw}"
            )
        if normalized in seen:
            raise SystemExit(
                f"ERROR: release archive contains a duplicate path: {raw}"
            )
        seen.add(normalized)
        if not (member.isdir() or member.isreg()):
            raise SystemExit(
                f"ERROR: release archive contains a link or special file: {raw}"
            )

if expected_root not in seen:
    raise SystemExit(
        f"ERROR: release archive lacks expected top-level directory: {expected_root}"
    )
PY
  tar -xzf "$TMP_DIR/$asset" -C "$TMP_DIR"
  RELEASE_ROOT="$TMP_DIR/$top"
  validate_release_provenance \
    "$RELEASE_ROOT" "$VERSION" "$release_repository" "$release_commit"
  VENDOR_TOOL="$RELEASE_ROOT/tools/vendor-core.sh"
  [[ -x "$VENDOR_TOOL" ]] || {
    echo "ERROR: release artifact lacks tools/vendor-core.sh" >&2
    exit 1
  }
  "$VENDOR_TOOL" \
    --source "$RELEASE_ROOT" \
    --target "$CANDIDATE" \
    --profile "$PROFILE" \
    --artifact-sha256 "$actual"
fi

[[ -x "$CANDIDATE/tools/verify-core.sh" ]] || {
  echo "ERROR: materialized core lacks tools/verify-core.sh" >&2
  exit 1
}
"$CANDIDATE/tools/verify-core.sh" --root "$CANDIDATE"
"$SCRIPT_DIR/verify-core.sh" \
  --vendor "$CANDIDATE" \
  --lock "$CANDIDATE/core.lock.json" \
  --no-projection
if [[ -n "$SOURCE_DIR" ]]; then
  validate_candidate_provenance "$CANDIDATE" "$LOCAL_SOURCE_ROOT"
else
  validate_candidate_provenance \
    "$CANDIDATE" "$RELEASE_ROOT" "$VERSION" \
    "$release_repository" "$release_commit" "$actual_lower"
fi

# Exercise the complete projection in an isolated wrapper-shaped directory
# before changing either the live pin or compatibility paths.
PROJECTION_STAGE="$TMP_DIR/wrapper-projection"
PROJECT_TOKEN=$(python3 -c 'import secrets; print(secrets.token_hex(24))')
printf '%s\n' "$PROJECT_TOKEN" > "$TMP_DIR/.scv-project-core-token"
chmod 600 "$TMP_DIR/.scv-project-core-token"
mkdir -p "$PROJECTION_STAGE"
cp -R -p "$REPO_ROOT/scripts" "$PROJECTION_STAGE/scripts"
cp -R -p "$REPO_ROOT/commands" "$PROJECTION_STAGE/commands"
cp -R -p "$REPO_ROOT/tests" "$PROJECTION_STAGE/tests"
SCV_PROJECT_CORE_STAGE_ROOT="$TMP_DIR" \
SCV_PROJECT_CORE_WRITE_TOKEN="$PROJECT_TOKEN" \
  "$SCRIPT_DIR/project-core.sh" \
  --vendor "$CANDIDATE" \
  --destination "$PROJECTION_STAGE"
"$SCRIPT_DIR/project-core.sh" \
  --vendor "$CANDIDATE" \
  --destination "$PROJECTION_STAGE" \
  --check

if (( DRY_RUN )); then
  echo "CORE_SYNC_DRY_RUN: yes"
  echo "CORE_VERSION: $(tr -d '[:space:]' < "$CANDIDATE/VERSION")"
  echo "CORE_COMMIT: $(tr -d '[:space:]' < "$CANDIDATE/SOURCE_COMMIT")"
  echo "PAYLOAD_SHA256: $(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["payload_sha256"])' "$CANDIDATE/core.lock.json")"
  echo "ARTIFACT_SHA256: $(python3 -c 'import json,sys; value=json.load(open(sys.argv[1]))["artifact_sha256"]; print("null" if value is None else value)' "$CANDIDATE/core.lock.json")"
  exit 0
fi

sync_failpoint() {
  local point=$1 requested=${SCV_CORE_SYNC_FAILPOINT:-}
  case "$requested" in
    "$point")
      echo "ERROR: injected core sync failure at $point" >&2
      return 97
      ;;
    "signal-hup:$point")
      kill -HUP "$$"
      ;;
    "signal-int:$point")
      kill -INT "$$"
      ;;
    "signal-term:$point")
      kill -TERM "$$"
      ;;
  esac
}

sync_test_pause() {
  local point=$1 attempt
  [[ "${SCV_CORE_SYNC_TEST_PAUSE_AT:-}" == "$point" ]] || return 0
  [[ -n "${SCV_CORE_SYNC_TEST_READY_FILE:-}" &&
     -n "${SCV_CORE_SYNC_TEST_CONTINUE_FILE:-}" ]] || {
    echo "ERROR: test pause requires ready and continue files" >&2
    return 2
  }
  printf '%s\n' "$point" > "$SCV_CORE_SYNC_TEST_READY_FILE"
  for (( attempt=1; attempt <= 1200; attempt++ )); do
    [[ -e "$SCV_CORE_SYNC_TEST_CONTINUE_FILE" ]] && return 0
    sleep 0.05
  done
  echo "ERROR: timed out at test pause: $point" >&2
  return 1
}

guarded_rename_noreplace() {
  local source_scope=$1 source_relative=$2
  local destination_scope=$3 destination_relative=$4 label=$5
  local source_anchor source_device source_inode
  local destination_anchor destination_device destination_inode
  case "$source_scope" in
    repository)
      source_anchor=$REPO_ROOT
      source_device=$REPO_DEVICE
      source_inode=$REPO_INODE
      ;;
    transaction)
      source_anchor=$TX_ROOT
      source_device=$TX_DEVICE
      source_inode=$TX_INODE
      ;;
    *)
      echo "ERROR: unknown guarded rename source scope: $source_scope" >&2
      return 2
      ;;
  esac
  case "$destination_scope" in
    repository)
      destination_anchor=$REPO_ROOT
      destination_device=$REPO_DEVICE
      destination_inode=$REPO_INODE
      ;;
    transaction)
      destination_anchor=$TX_ROOT
      destination_device=$TX_DEVICE
      destination_inode=$TX_INODE
      ;;
    *)
      echo "ERROR: unknown guarded rename destination scope: $destination_scope" >&2
      return 2
      ;;
  esac
  python3 -B "$PATH_HELPER" rename-noreplace \
    --source-anchor "$source_anchor" \
    --source-device "$source_device" \
    --source-inode "$source_inode" \
    --source-relative "$source_relative" \
    --destination-anchor "$destination_anchor" \
    --destination-device "$destination_device" \
    --destination-inode "$destination_inode" \
    --destination-relative "$destination_relative" \
    --label "$label" \
    --create-destination-parents
}

cleanup_transaction_tree() {
  [[ -n "$TX_ROOT" && -n "$TX_ROOT_RELATIVE" &&
     -n "$TX_DEVICE" && -n "$TX_INODE" ]] || {
    echo "ERROR: transaction cleanup identity is unavailable" >&2
    return 1
  }
  python3 -B "$PATH_HELPER" remove-tree \
    --anchor "$REPO_ROOT" \
    --anchor-device "$REPO_DEVICE" \
    --anchor-inode "$REPO_INODE" \
    --relative "$TX_ROOT_RELATIVE" \
    --expected-device "$TX_DEVICE" \
    --expected-inode "$TX_INODE"
}

path_fingerprint() {
  local target=$1 inventory=${2:-}
  python3 - "$target" "$inventory" <<'PY'
import hashlib
import os
import stat
import sys
from pathlib import Path

target = Path(sys.argv[1])
inventory = Path(sys.argv[2]) if sys.argv[2] else None
excluded = set()
if inventory is not None:
    for encoded in inventory.read_bytes().split(b"\0"):
        if not encoded:
            continue
        relative = os.fsdecode(encoded).rstrip("/")
        if relative.startswith("DeckUI/"):
            excluded.add(relative.removeprefix("DeckUI/"))

def is_excluded(relative: str) -> bool:
    parts = relative.split("/")
    return any(
        "/".join(parts[:index]) in excluded
        for index in range(1, len(parts) + 1)
    )

if not target.exists() and not target.is_symlink():
    print("absent")
    raise SystemExit(0)

digest = hashlib.sha256()
stack = [(target, ".")]
while stack:
    item, relative = stack.pop()
    if relative != "." and is_excluded(relative):
        continue
    metadata = item.lstat()
    mode = metadata.st_mode
    digest.update(
        relative.encode("utf-8", "surrogateescape")
        + b"\0"
        + str(stat.S_IMODE(mode)).encode()
        + b"\0"
    )
    if stat.S_ISDIR(mode):
        digest.update(b"D\0")
        with os.scandir(item) as handle:
            children = sorted(handle, key=lambda entry: entry.name, reverse=True)
        for child in children:
            child_relative = (
                child.name if relative == "." else f"{relative}/{child.name}"
            )
            stack.append((Path(child.path), child_relative))
    elif stat.S_ISLNK(mode):
        digest.update(
            b"L\0"
            + os.readlink(item).encode("utf-8", "surrogateescape")
            + b"\0"
        )
    elif stat.S_ISREG(mode):
        digest.update(b"F\0")
        with item.open("rb") as handle:
            while True:
                chunk = handle.read(1024 * 1024)
                if not chunk:
                    break
                digest.update(chunk)
        digest.update(b"\0")
    else:
        digest.update(b"O\0")
print(digest.hexdigest())
PY
}

capture_transaction_preimage() {
  local relative live state digest inventory
  TX_EXPECTED_STATES=()
  TX_EXPECTED_DIGESTS=()
  for relative in "${TRANSACTION_PATHS[@]}"; do
    live="$REPO_ROOT/$relative"
    state=absent
    path_exists "$live" && state=present
    inventory=
    [[ "$relative" != DeckUI ]] || inventory=$TX_DECK_INVENTORY_FILE
    digest=$(path_fingerprint "$live" "$inventory")
    TX_EXPECTED_STATES+=("$state")
    TX_EXPECTED_DIGESTS+=("$digest")
  done
}

validate_transaction_preimage() {
  local index relative live state digest inventory failures=0
  for (( index=0; index < ${#TRANSACTION_PATHS[@]}; index++ )); do
    relative=${TRANSACTION_PATHS[$index]}
    live="$REPO_ROOT/$relative"
    state=absent
    path_exists "$live" && state=present
    inventory=
    [[ "$relative" != DeckUI ]] || inventory=$TX_DECK_INVENTORY_FILE
    digest=$(path_fingerprint "$live" "$inventory")
    if [[ "$state" != "${TX_EXPECTED_STATES[$index]}" ||
          "$digest" != "${TX_EXPECTED_DIGESTS[$index]}" ]]; then
      echo "ERROR: live path changed after projection snapshot: $relative" >&2
      failures=$((failures + 1))
    fi
  done
  (( failures == 0 ))
}

validate_original_preimage() {
  local index=$1 relative=$2 actual=$3 state=$4 inventory= digest
  [[ "$relative" != DeckUI ]] || inventory=$TX_DECK_INVENTORY_FILE
  digest=$(path_fingerprint "$actual" "$inventory")
  if [[ "$state" != "${TX_EXPECTED_STATES[$index]}" ||
        "$digest" != "${TX_EXPECTED_DIGESTS[$index]}" ]]; then
    echo "ERROR: original path drifted before atomic backup: $relative" >&2
    return 1
  fi
}

validate_backup_preimages() {
  local index relative backup state digest inventory preserved failures=0
  for (( index=0; index < ${#TX_PATHS[@]}; index++ )); do
    relative=${TX_PATHS[$index]}
    backup="$TX_BACKUP/$relative"
    state=absent
    path_exists "$backup" && state=present
    inventory=
    [[ "$relative" != DeckUI ]] || inventory=$TX_DECK_INVENTORY_FILE
    if [[ "$relative" == DeckUI ]]; then
      for preserved in "${TX_DECK_INVENTORY[@]}"; do
        if path_exists "$backup/${preserved#DeckUI/}"; then
          echo "ERROR: DeckUI runtime path reappeared in original backup: $preserved" >&2
          failures=$((failures + 1))
        fi
      done
    fi
    digest=$(path_fingerprint "$backup" "$inventory")
    if [[ "$state" != "${TX_EXPECTED_STATES[$index]}" ||
          "$digest" != "${TX_EXPECTED_DIGESTS[$index]}" ]]; then
      echo "ERROR: original backup changed during Core sync: $relative" >&2
      failures=$((failures + 1))
    fi
  done
  (( failures == 0 ))
}

collect_deckui_inventory() {
  local suffix=${1:-} git_root raw normalized inventory_path
  git_root=$(git -C "$REPO_ROOT" rev-parse --show-toplevel 2>/dev/null) || {
    echo "ERROR: Core sync requires the wrapper repository Git index" >&2
    return 1
  }
  [[ "$(cd "$git_root" && pwd -P)" == "$REPO_ROOT" ]] || {
    echo "ERROR: Core sync must run at the wrapper Git worktree root" >&2
    return 1
  }
  raw="deckui-inventory${suffix}.raw"
  normalized="deckui-inventory${suffix}"
  {
    git -C "$REPO_ROOT" ls-files \
      --others --ignored --exclude-standard --directory -z -- DeckUI
    git -C "$REPO_ROOT" ls-files \
      --others --exclude-standard --directory -z -- DeckUI
  } > "$raw"
  python3 - "$REPO_ROOT" "$raw" "$normalized" <<'PY'
import os
import sys
from pathlib import Path

repo = Path(sys.argv[1])
raw = Path(sys.argv[2]).read_bytes().split(b"\0")
output = Path(sys.argv[3])
candidates = set()
for encoded in raw:
    if not encoded:
        continue
    value = os.fsdecode(encoded).rstrip("/")
    path = Path(value)
    if (
        path.is_absolute()
        or len(path.parts) < 2
        or path.parts[0] != "DeckUI"
        or any(part in {"", ".", ".."} for part in path.parts)
    ):
        raise SystemExit(f"ERROR: unsafe DeckUI runtime inventory path: {value!r}")
    if not (repo / path).exists() and not (repo / path).is_symlink():
        raise SystemExit(f"ERROR: DeckUI runtime inventory path disappeared: {value!r}")
    candidates.add(path.as_posix())

selected = []
selected_set = set()
for value in sorted(candidates, key=lambda item: (item.count("/"), item)):
    parts = value.split("/")
    if any("/".join(parts[:index]) in selected_set for index in range(2, len(parts))):
        continue
    selected.append(value)
    selected_set.add(value)
output.write_bytes(
    b"".join(os.fsencode(value) + b"\0" for value in selected)
)
PY
  if [[ -n "$suffix" ]]; then
    if ! cmp -s "$TX_DECK_INVENTORY_FILE" "$normalized"; then
      echo "ERROR: DeckUI runtime inventory changed after projection snapshot" >&2
      return 1
    fi
    return 0
  fi
  TX_DECK_INVENTORY=()
  TX_DECK_INVENTORY_FILE=$normalized
  while IFS= read -r -d '' inventory_path; do
    TX_DECK_INVENTORY+=("$inventory_path")
  done < "$normalized"
}

VENDOR_PROJECTION="$TMP_DIR/vendor-projection"
python3 - "$VENDOR_PARENT" "$VENDOR_PROJECTION" "$CANDIDATE" <<'PY'
import os
import shutil
import stat
import sys
from pathlib import Path

source = Path(sys.argv[1])
destination = Path(sys.argv[2])
candidate = Path(sys.argv[3])
destination.mkdir()
if source.exists():
    shutil.copystat(source, destination, follow_symlinks=False)
    with os.scandir(source) as handle:
        children = list(handle)
    for child in children:
        if child.name == "scv-core":
            continue
        source_child = Path(child.path)
        destination_child = destination / child.name
        mode = child.stat(follow_symlinks=False).st_mode
        if stat.S_ISDIR(mode):
            shutil.copytree(
                source_child,
                destination_child,
                symlinks=True,
                copy_function=shutil.copy2,
            )
        elif stat.S_ISLNK(mode):
            os.symlink(os.readlink(source_child), destination_child)
        elif stat.S_ISREG(mode):
            shutil.copy2(source_child, destination_child, follow_symlinks=False)
        else:
            raise SystemExit(
                f"ERROR: unsupported file type under vendor: {source_child}"
            )
shutil.copytree(
    candidate,
    destination / "scv-core",
    symlinks=True,
    copy_function=shutil.copy2,
)
PY

TX_ID=$(python3 -B "$PATH_HELPER" make-temp-directory \
  --anchor "$REPO_ROOT" \
  --anchor-device "$REPO_DEVICE" \
  --anchor-inode "$REPO_INODE" \
  --prefix .scv-core-transaction.)
TX_ROOT_RELATIVE=${TX_ID%%:*}
TX_ID=${TX_ID#*:}
TX_DEVICE=${TX_ID%%:*}
TX_INODE=${TX_ID#*:}
[[ "$TX_ROOT_RELATIVE" == .scv-core-transaction.* &&
   "$TX_ROOT_RELATIVE" != */* &&
   "$TX_DEVICE" =~ ^[0-9]+$ &&
   "$TX_INODE" =~ ^[0-9]+$ ]] || {
  echo "ERROR: safe path helper returned an invalid transaction identity" >&2
  exit 1
}
TX_ROOT="$REPO_ROOT/$TX_ROOT_RELATIVE"
cd "$TX_ROOT" || {
  echo "ERROR: cannot enter Core transaction root" >&2
  exit 1
}
TX_CWD_ID=$(python3 -B "$PATH_HELPER" identity --path .)
[[ "$TX_CWD_ID" == "$TX_DEVICE:$TX_INODE" ]] || {
  echo "ERROR: Core transaction root changed before staging" >&2
  exit 1
}
sync_test_pause before-transaction-staging
TX_STAGE=stage
TX_BACKUP=backup
TX_STAGE_VENDOR_PARENT="$TX_STAGE/vendor"
TX_STAGE_VENDOR="$TX_STAGE/vendor/scv-core"
TX_STAGE_WRAPPER="$TX_STAGE/wrapper"
python3 -B "$PATH_HELPER" make-directories \
  --anchor "$TX_ROOT" \
  --anchor-device "$TX_DEVICE" \
  --anchor-inode "$TX_INODE" \
  --relative backup
python3 -B "$PATH_HELPER" copy-tree \
  --source "$VENDOR_PROJECTION" \
  --destination-anchor "$TX_ROOT" \
  --destination-device "$TX_DEVICE" \
  --destination-inode "$TX_INODE" \
  --destination-relative stage/vendor \
  --label stage/vendor
python3 -B "$PATH_HELPER" copy-tree \
  --source "$PROJECTION_STAGE" \
  --destination-anchor "$TX_ROOT" \
  --destination-device "$TX_DEVICE" \
  --destination-inode "$TX_INODE" \
  --destination-relative stage/wrapper \
  --label stage/wrapper
python3 -B "$PATH_HELPER" copy-file \
  --source "$CANDIDATE/core.lock.json" \
  --destination-anchor "$TX_ROOT" \
  --destination-device "$TX_DEVICE" \
  --destination-inode "$TX_INODE" \
  --destination-relative stage/core.lock
"$TX_STAGE_VENDOR/tools/verify-core.sh" --root "$TX_STAGE_VENDOR"
"$SCRIPT_DIR/verify-core.sh" \
  --vendor "$TX_STAGE_VENDOR" \
  --lock "$TX_STAGE/core.lock" \
  --no-projection
"$SCRIPT_DIR/project-core.sh" \
  --vendor "$TX_STAGE_VENDOR" \
  --destination "$TX_STAGE_WRAPPER" \
  --check

# Couple the live preimage to the transaction projection. The second worktree
# validation closes the download/verification window. Snapshot-before-copy
# plus a pre-swap and post-backup digest check protects even adapter-owned
# files, whose local contents are intentionally allowed and projected.
acquire_git_index_lock
validate_live_worktree
TX_INDEX_FINGERPRINT=$(scoped_index_fingerprint)
collect_deckui_inventory
capture_transaction_preimage
for preserved_path in "${TX_DECK_INVENTORY[@]}"; do
  if path_exists "$TX_STAGE_WRAPPER/$preserved_path"; then
    echo "ERROR: staged Core conflicts with local runtime path: $preserved_path" >&2
    exit 1
  fi
done

case "${SCV_CORE_SYNC_TEST_DRIFT:-}" in
  "")
    ;;
  non-deck)
    printf 'late local helper sentinel\n' \
      > "$REPO_ROOT/scripts/late-local-helper.sh"
    ;;
  adapter)
    printf '\n# late adapter sentinel\n' >> "$REPO_ROOT/scripts/sync.sh"
    ;;
  deck)
    printf 'late DeckUI runtime sentinel\n' \
      > "$REPO_ROOT/DeckUI/.scv-late-runtime"
    ;;
  vendor-symlink)
    [[ -n "${SCV_CORE_SYNC_TEST_VENDOR_TARGET:-}" &&
       -n "${SCV_CORE_SYNC_TEST_VENDOR_SAVED:-}" ]] || {
      echo "ERROR: vendor drift test hook requires target and saved paths" >&2
      exit 2
    }
    mv "$VENDOR_PARENT" "$SCV_CORE_SYNC_TEST_VENDOR_SAVED"
    ln -s "$SCV_CORE_SYNC_TEST_VENDOR_TARGET" "$VENDOR_PARENT"
    ;;
  index)
    [[ -f "${SCV_CORE_SYNC_TEST_INDEX_REPLACEMENT:-}" ]] || {
      echo "ERROR: index drift test hook requires a replacement index" >&2
      exit 2
    }
    cp -p "$SCV_CORE_SYNC_TEST_INDEX_REPLACEMENT" "$REPO_ROOT/.git/index"
    ;;
  *)
    echo "ERROR: unknown Core sync drift test hook" >&2
    exit 2
    ;;
esac

validate_live_worktree
validate_index_preimage
collect_deckui_inventory .recheck
validate_transaction_preimage

DECK_RUNTIME_MIGRATOR="$TX_STAGE_VENDOR/core/scripts/deck-runtime.sh"
if [[ -x "$DECK_RUNTIME_MIGRATOR" && -d "$REPO_ROOT/DeckUI" ]]; then
  if [[ -n "${SCV_DECK_CACHE_DIR:-}" ]]; then
    DECK_CACHE_BASE=$SCV_DECK_CACHE_DIR
  elif [[ -n "${XDG_CACHE_HOME:-}" ]]; then
    DECK_CACHE_BASE="$XDG_CACHE_HOME/scv/deckui"
  elif [[ -n "${HOME:-}" ]]; then
    DECK_CACHE_BASE="$HOME/.cache/scv/deckui"
  else
    echo "ERROR: set SCV_DECK_CACHE_DIR, XDG_CACHE_HOME, or HOME" >&2
    exit 1
  fi
  python3 - \
    "$DECK_CACHE_BASE" \
    "$REPO_ROOT" \
    "$TX_ROOT" \
    "$TMP_DIR" \
    "$REPO_ROOT/DeckUI" <<'PY'
import sys
from pathlib import Path

raw_cache = Path(sys.argv[1]).expanduser()
try:
    cache = raw_cache.resolve(strict=False)
    protected = [Path(value).resolve(strict=False) for value in sys.argv[2:]]
except (OSError, RuntimeError) as error:
    raise SystemExit(f"ERROR: cannot resolve SCV Deck cache boundary: {error}")

if not raw_cache.is_absolute():
    raise SystemExit("ERROR: SCV Deck cache base must be an absolute path")

def is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False

for boundary in protected:
    if is_relative_to(cache, boundary) or is_relative_to(boundary, cache):
        raise SystemExit(
            "ERROR: SCV Deck cache base overlaps updater-protected path: "
            f"{cache} <-> {boundary}"
        )
PY
  deck_runtime_path=$(
    "$DECK_RUNTIME_MIGRATOR" migrate --from "$REPO_ROOT/DeckUI"
  )
  echo "DECK_RUNTIME_MIGRATED: $deck_runtime_path"
fi

transaction_source_relative() {
  case "$1" in
    vendor) printf '%s\n' stage/vendor ;;
    core.lock) printf '%s\n' stage/core.lock ;;
    *) printf 'stage/wrapper/%s\n' "$1" ;;
  esac
}

swap_transaction_path() {
  local relative=$1 source_relative source live backup
  local original_state=absent preserved inventory
  local expected_index actual_original source_digest installed_digest
  source_relative=$(transaction_source_relative "$relative")
  source=$source_relative
  live="$REPO_ROOT/$relative"
  backup="$TX_BACKUP/$relative"
  path_exists "$source" || {
    echo "ERROR: transaction stage lacks $relative" >&2
    return 1
  }
  inventory=
  [[ "$relative" != DeckUI ]] || inventory=$TX_DECK_INVENTORY_FILE
  source_digest=$(path_fingerprint "$source" "$inventory")
  if path_exists "$live"; then
    original_state=present
  fi
  expected_index=${#TX_PATHS[@]}
  TX_PATHS+=("$relative")
  TX_ORIGINAL_STATES+=("$original_state")
  TX_STAGE_INSTALLED+=(no)
  TX_INSTALLED_DIGESTS+=("$source_digest")

  if [[ "$original_state" == present ]]; then
    guarded_rename_noreplace \
      repository "$relative" \
      transaction "backup/$relative" \
      "backup:$relative"
    actual_original=$backup
  else
    actual_original=$live
  fi
  validate_original_preimage \
    "$expected_index" "$relative" "$actual_original" "$original_state"
  sync_failpoint "after-backup:$relative"

  if [[ "${SCV_CORE_SYNC_TEST_AFTER_BACKUP:-}" == "recreate:$relative" ]]; then
    mkdir -p "$(dirname "$live")"
    if [[ -d "$source" ]]; then
      mkdir -p "$live"
      printf 'concurrent live sentinel\n' > "$live/.scv-concurrent-live"
    else
      printf 'concurrent live sentinel\n' > "$live"
    fi
  fi
  if path_exists "$live"; then
    echo "ERROR: live path was recreated after atomic backup: $relative" >&2
    return 1
  fi

  guarded_rename_noreplace \
    transaction "$source_relative" \
    repository "$relative" \
    "install:$relative"
  TX_STAGE_INSTALLED[$expected_index]=yes

  if [[ "$relative" == DeckUI && "$original_state" == present ]]; then
    for preserved in "${TX_DECK_INVENTORY[@]}"; do
      if path_exists "$backup/${preserved#DeckUI/}"; then
        path_exists "$live/${preserved#DeckUI/}" && {
          echo "ERROR: staged DeckUI unexpectedly contains $preserved" >&2
          return 1
        }
        guarded_rename_noreplace \
          transaction "backup/$preserved" \
          repository "$preserved" \
          "preserve:$preserved"
        TX_PRESERVED_PATHS+=("$preserved")
      fi
    done
  fi
  installed_digest=$(path_fingerprint "$live" "$inventory")
  if [[ "$installed_digest" != "$source_digest" ]]; then
    echo "ERROR: installed path changed during atomic swap: $relative" >&2
    return 1
  fi
  sync_failpoint "after-swap:$relative"
}

TX_ACTIVE=1
sync_failpoint before-live-install

for transaction_path in "${TRANSACTION_PATHS[@]}"; do
  swap_transaction_path "$transaction_path"
done

sync_failpoint before-final-verify
"$SCRIPT_DIR/verify-core.sh"
sync_failpoint after-final-verify
if [[ "${SCV_CORE_SYNC_TEST_BEFORE_COMMIT:-}" == recreate-deck-runtime ]]; then
  mkdir -p "$TX_BACKUP/DeckUI/node_modules"
  printf 'late backup runtime sentinel\n' \
    > "$TX_BACKUP/DeckUI/node_modules/.scv-late-backup-runtime"
fi
validate_index_preimage
validate_backup_preimages

TX_COMMITTED=1
TX_ACTIVE=0
cleanup_transaction_tree
TX_ROOT=
TX_ROOT_RELATIVE=
TX_DEVICE=
TX_INODE=

echo "CORE_SYNCED: yes"
echo "CORE_VERSION: $(tr -d '[:space:]' < "$VENDOR_TARGET/VERSION")"
echo "CORE_COMMIT: $(tr -d '[:space:]' < "$VENDOR_TARGET/SOURCE_COMMIT")"
