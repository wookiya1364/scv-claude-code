#!/usr/bin/env bash
# Maintainer updater transaction, provenance, and wrapper-version contracts.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE_VENDOR="$REPO_ROOT/vendor/scv-core"
PASS=0
FAIL=0

ok() {
  echo "  ✓ $1"
  PASS=$((PASS + 1))
}

fail() {
  echo "  ✖ FAIL: $1"
  FAIL=$((FAIL + 1))
}

portable_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

tree_snapshot() {
  python3 - "$1" <<'PY'
import hashlib
import os
import stat
import sys
from pathlib import Path

root = Path(sys.argv[1])
digest = hashlib.sha256()
for item in sorted(root.rglob("*")):
    relative = item.relative_to(root).as_posix()
    mode = item.lstat().st_mode
    digest.update(relative.encode() + b"\0" + str(stat.S_IMODE(mode)).encode() + b"\0")
    if stat.S_ISLNK(mode):
        digest.update(b"L\0" + os.readlink(item).encode() + b"\0")
    elif stat.S_ISDIR(mode):
        digest.update(b"D\0")
    elif stat.S_ISREG(mode):
        digest.update(b"F\0" + item.read_bytes() + b"\0")
    else:
        digest.update(b"O\0")
print(digest.hexdigest())
PY
}

metadata_snapshot() {
  python3 - "$1" <<'PY'
import hashlib
import sys
from pathlib import Path

root = Path(sys.argv[1])
digest = hashlib.sha256()
for relative in (
    "VERSION",
    ".claude-plugin/plugin.json",
    ".claude-plugin/marketplace.json",
):
    path = root / relative
    digest.update(relative.encode() + b"\0" + path.read_bytes() + b"\0")
print(digest.hexdigest())
PY
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export SCV_DECK_CACHE_DIR="$WORK/deck-cache"
SOURCE_CORE="$WORK/source-core"
cp -R -p "$SOURCE_VENDOR" "$SOURCE_CORE"

copy_fixture() {
  local destination=$1 directory
  mkdir -p "$destination"
  cp -p "$REPO_ROOT/.gitignore" "$destination/.gitignore"
  for directory in \
    .claude-plugin adapter scripts commands tests template protocols assets vendor; do
    cp -R -p "$REPO_ROOT/$directory" "$destination/$directory"
  done
  mkdir -p "$destination/DeckUI"
  python3 - "$REPO_ROOT/DeckUI" "$destination/DeckUI" <<'PY'
import shutil
import sys
from pathlib import Path

source = Path(sys.argv[1])
destination = Path(sys.argv[2])

def ignore_runtime(_directory, names):
    return {name for name in names if name in {"node_modules", "dist-deck"}}

shutil.copytree(
    source,
    destination,
    dirs_exist_ok=True,
    symlinks=True,
    copy_function=shutil.copy2,
    ignore=ignore_runtime,
)
PY
  for file in VERSION TEMPLATE_VERSION core.lock host-profile.env ralph-template-scv.md; do
    cp -p "$REPO_ROOT/$file" "$destination/$file"
  done
  printf 'tracked wrapper vendor sibling\n' \
    > "$destination/vendor/wrapper-owned-sibling.txt"
  git -C "$destination" init -q
  git -C "$destination" config user.name "SCV Core Sync Test"
  git -C "$destination" config user.email "scv-sync-test@example.invalid"
  git -C "$destination" add -A
  git -C "$destination" commit -qm "fixture baseline"
  mkdir -p \
    "$destination/DeckUI/node_modules" \
    "$destination/DeckUI/dist-deck" \
    "$destination/DeckUI/scripts/deckdoc/node_modules" \
    "$destination/DeckUI/src/deck/decks/atomic-runtime"
  printf 'runtime dependency sentinel\n' \
    > "$destination/DeckUI/node_modules/.scv-atomicity-sentinel"
  printf 'runtime build sentinel\n' \
    > "$destination/DeckUI/dist-deck/.scv-atomicity-sentinel"
  printf 'nested runtime dependency sentinel\n' \
    > "$destination/DeckUI/scripts/deckdoc/node_modules/.scv-atomicity-sentinel"
  printf '{"runtime":"generated deck sentinel"}\n' \
    > "$destination/DeckUI/src/deck/decks/atomic-runtime/deck.json"
  printf 'untracked local DeckUI sentinel\n' \
    > "$destination/DeckUI/.scv-untracked-local"
}

runtime_paths_preserved() {
  local fixture=$1
  [[ -f "$fixture/DeckUI/node_modules/.scv-atomicity-sentinel" &&
     -f "$fixture/DeckUI/dist-deck/.scv-atomicity-sentinel" &&
     -f "$fixture/DeckUI/scripts/deckdoc/node_modules/.scv-atomicity-sentinel" &&
     -f "$fixture/DeckUI/src/deck/decks/atomic-runtime/deck.json" &&
     -f "$fixture/DeckUI/.scv-untracked-local" ]]
}

transaction_debris() {
  local candidate
  for candidate in "$1"/.scv-core-transaction.*; do
    if [[ -e "$candidate" || -L "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done
}

quarantine_debris() {
  local candidate
  for candidate in "$1"/.scv-core-sync-quarantine.*; do
    if [[ -e "$candidate" || -L "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done
}

CASE_NUMBER=0
run_failure_case() {
  local label=$1 failpoint=$2 fixture before after output rc
  local tmp_override=${3:-} rollback_signal=${4:-}
  CASE_NUMBER=$((CASE_NUMBER + 1))
  fixture="$WORK/failure-$CASE_NUMBER"
  output="$WORK/failure-$CASE_NUMBER.out"
  copy_fixture "$fixture"
  before=$(tree_snapshot "$fixture")
  if [[ -n "$tmp_override" ]]; then
    TMPDIR="$tmp_override" \
      SCV_CORE_SYNC_FAILPOINT="$failpoint" \
      SCV_CORE_SYNC_ROLLBACK_SIGNAL="$rollback_signal" \
      bash "$fixture/scripts/sync-core.sh" --source "$SOURCE_CORE" \
      >"$output" 2>&1
  else
    SCV_CORE_SYNC_FAILPOINT="$failpoint" \
      SCV_CORE_SYNC_ROLLBACK_SIGNAL="$rollback_signal" \
      bash "$fixture/scripts/sync-core.sh" --source "$SOURCE_CORE" \
      >"$output" 2>&1
  fi
  rc=$?
  after=$(tree_snapshot "$fixture")
  if [[ "$rc" -ne 0 ]]; then
    ok "$label: injected failure is propagated"
  else
    fail "$label: updater unexpectedly succeeded"
  fi
  if [[ "$before" == "$after" ]]; then
    ok "$label: original wrapper is restored byte/type/mode-exact"
  else
    fail "$label: wrapper changed after rollback"
  fi
  if [[ -z "$(transaction_debris "$fixture")" ]]; then
    ok "$label: partial transaction stage is removed"
  else
    fail "$label: transaction debris remains"
  fi
}

echo "── sync-core transaction rollback ──"
run_failure_case \
  "failure after existing vendor backup" \
  "after-backup:vendor"
run_failure_case \
  "failure after vendor install" \
  "after-swap:vendor"
run_failure_case \
  "failure after lock install" \
  "after-swap:core.lock"
run_failure_case \
  "failure midway through projection" \
  "after-swap:scripts"
run_failure_case \
  "failure before final verification" \
  "before-final-verify"
run_failure_case \
  "TERM midway through projection" \
  "signal-term:after-swap:DeckUI"
run_failure_case \
  "TERM ignored while rollback restores DeckUI runtime paths" \
  "after-swap:DeckUI" \
  "" \
  "TERM"

cross_tmp=
if [[ -d /dev/shm && -w /dev/shm ]]; then
  repo_device=$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_dev)' "$WORK")
  shm_device=$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_dev)' /dev/shm)
  if [[ "$repo_device" != "$shm_device" ]]; then
    cross_tmp=/dev/shm
  fi
fi
if [[ -n "$cross_tmp" ]]; then
  run_failure_case \
    "cross-device TMPDIR failure" \
    "after-swap:vendor" \
    "$cross_tmp"
else
  ok "cross-device TMPDIR fixture unavailable on this host (skipped)"
fi

fixture="$WORK/absent-target"
output="$WORK/absent-target.out"
copy_fixture "$fixture"
rm -rf "$fixture/vendor"
rm -f "$fixture/core.lock"
git -C "$fixture" add -A
git -C "$fixture" commit -qm "fixture with absent Core targets"
before=$(tree_snapshot "$fixture")
SCV_CORE_SYNC_FAILPOINT="after-swap:vendor" \
  bash "$fixture/scripts/sync-core.sh" --source "$SOURCE_CORE" \
  >"$output" 2>&1
rc=$?
after=$(tree_snapshot "$fixture")
if [[ "$rc" -ne 0 &&
      "$(cat "$output")" == *"injected core sync failure at after-swap:vendor"* ]]; then
  ok "absent target: injected failure is propagated"
else
  fail "absent target: updater did not reach the injected transaction failure"
fi
if [[ "$before" == "$after" ]]; then
  ok "absent target: rollback restores exact absence"
else
  fail "absent target: rollback left files behind"
fi
if [[ -z "$(transaction_debris "$fixture")" ]]; then
  ok "absent target: partial transaction stage is removed"
else
  fail "absent target: transaction debris remains"
fi

echo
echo "── rollback recovery durability ──"
fixture="$WORK/rollback-recovery"
output="$WORK/rollback-recovery.out"
copy_fixture "$fixture"
SCV_CORE_SYNC_FAILPOINT="after-swap:scripts" \
  SCV_CORE_SYNC_ROLLBACK_FAILPOINT="restore:scripts" \
  bash "$fixture/scripts/sync-core.sh" --source "$SOURCE_CORE" \
  >"$output" 2>&1
rc=$?
recovery_path=$(transaction_debris "$fixture")
if [[ "$rc" -ne 0 &&
      "$(cat "$output")" == *"rollback incomplete; recovery backup preserved at"* ]]; then
  ok "rollback restore failure is nonzero and reports a recovery path"
else
  fail "rollback restore failure was hidden or lacked recovery guidance"
fi
if [[ -n "$recovery_path" && -d "$recovery_path/backup/scripts" ]]; then
  ok "failed rollback preserves its original backup"
else
  fail "failed rollback deleted the recovery backup"
fi
second_output="$WORK/rollback-recovery-second.out"
if bash "$fixture/scripts/sync-core.sh" --source "$SOURCE_CORE" --dry-run \
    >"$second_output" 2>&1; then
  fail "orphan transaction did not block a later sync"
elif [[ "$(cat "$second_output")" == *"unfinished Core transaction"* &&
        -d "$recovery_path/backup/scripts" ]]; then
  ok "orphan transaction fails closed without deleting recovery data"
else
  fail "orphan transaction rejection lacked recovery guidance"
fi

fixture="$WORK/after-backup-collision"
output="$WORK/after-backup-collision.out"
copy_fixture "$fixture"
SCV_CORE_SYNC_TEST_AFTER_BACKUP="recreate:scripts" \
  bash "$fixture/scripts/sync-core.sh" --source "$SOURCE_CORE" \
  >"$output" 2>&1
rc=$?
recovery_path=$(transaction_debris "$fixture")
if [[ "$rc" -ne 0 &&
      -f "$fixture/scripts/.scv-concurrent-live" &&
      -d "$recovery_path/backup/scripts" &&
      "$(cat "$output")" == *"rollback incomplete; recovery backup preserved at"* ]]; then
  ok "post-backup live recreation preserves both concurrent data and backup"
else
  fail "post-backup live recreation was overwritten or lost its backup"
fi

fixture="$WORK/deck-backup-reappearance"
output="$WORK/deck-backup-reappearance.out"
copy_fixture "$fixture"
SCV_CORE_SYNC_TEST_BEFORE_COMMIT=recreate-deck-runtime \
  bash "$fixture/scripts/sync-core.sh" --source "$SOURCE_CORE" \
  >"$output" 2>&1
rc=$?
recovery_path=$(transaction_debris "$fixture")
if [[ "$rc" -ne 0 &&
      -f "$fixture/DeckUI/node_modules/.scv-atomicity-sentinel" &&
      -f "$recovery_path/backup/DeckUI/node_modules/.scv-late-backup-runtime" &&
      "$(cat "$output")" == *"preserves live and backup DeckUI"* ]]; then
  ok "DeckUI runtime restore collision retains live and backup trees"
else
  fail "DeckUI runtime restore collision deleted live or backup data"
fi

echo
echo "── projection snapshot drift guards ──"
fixture="$WORK/late-non-deck"
output="$WORK/late-non-deck.out"
copy_fixture "$fixture"
SCV_CORE_SYNC_TEST_DRIFT=non-deck \
  bash "$fixture/scripts/sync-core.sh" --source "$SOURCE_CORE" \
  >"$output" 2>&1
rc=$?
if [[ "$rc" -ne 0 &&
      -f "$fixture/scripts/late-local-helper.sh" &&
      "$(cat "$output")" == *"Core sync would overwrite local-only path"* &&
      -z "$(transaction_debris "$fixture")" ]]; then
  ok "late non-Deck local file is rejected and preserved"
else
  fail "late non-Deck local file was lost or accepted"
fi

fixture="$WORK/late-adapter"
output="$WORK/late-adapter.out"
copy_fixture "$fixture"
SCV_CORE_SYNC_TEST_DRIFT=adapter \
  bash "$fixture/scripts/sync-core.sh" --source "$SOURCE_CORE" \
  >"$output" 2>&1
rc=$?
if [[ "$rc" -ne 0 &&
      "$(tail -n 1 "$fixture/scripts/sync.sh")" == "# late adapter sentinel" &&
      "$(cat "$output")" == *"live path changed after projection snapshot: scripts"* &&
      -z "$(transaction_debris "$fixture")" ]]; then
  ok "late adapter-owned edit is rejected and preserved"
else
  fail "late adapter-owned edit was lost or accepted"
fi

fixture="$WORK/late-deck-runtime"
output="$WORK/late-deck-runtime.out"
copy_fixture "$fixture"
SCV_CORE_SYNC_TEST_DRIFT=deck \
  bash "$fixture/scripts/sync-core.sh" --source "$SOURCE_CORE" \
  >"$output" 2>&1
rc=$?
if [[ "$rc" -ne 0 &&
      -f "$fixture/DeckUI/.scv-late-runtime" &&
      "$(cat "$output")" == *"DeckUI runtime inventory changed"* &&
      -z "$(transaction_debris "$fixture")" ]]; then
  ok "late DeckUI runtime path is rejected and preserved"
else
  fail "late DeckUI runtime path was lost or accepted"
fi

fixture="$WORK/late-vendor-symlink"
output="$WORK/late-vendor-symlink.out"
copy_fixture "$fixture"
vendor_target="$WORK/late-vendor-external"
vendor_saved="$WORK/late-vendor-saved"
cp -R -p "$fixture/vendor" "$vendor_target"
target_before=$(tree_snapshot "$vendor_target")
SCV_CORE_SYNC_TEST_DRIFT=vendor-symlink \
  SCV_CORE_SYNC_TEST_VENDOR_TARGET="$vendor_target" \
  SCV_CORE_SYNC_TEST_VENDOR_SAVED="$vendor_saved" \
  bash "$fixture/scripts/sync-core.sh" --source "$SOURCE_CORE" \
  >"$output" 2>&1
rc=$?
if [[ "$rc" -ne 0 &&
      -L "$fixture/vendor" &&
      -d "$vendor_saved/scv-core" &&
      "$(tree_snapshot "$vendor_target")" == "$target_before" &&
      -z "$(transaction_debris "$fixture")" ]]; then
  ok "late vendor symlink is rejected without external writes"
else
  fail "late vendor symlink redirected or deleted data"
fi

echo
echo "── live worktree collision guards ──"
fixture="$WORK/deck-conflict"
output="$WORK/deck-conflict.out"
copy_fixture "$fixture"
collision_core="$WORK/collision-core"
cp -R -p "$SOURCE_CORE" "$collision_core"
printf 'local/runtime collision\n' \
  > "$fixture/DeckUI/local-runtime-collision.txt"
printf 'Core/source collision\n' \
  > "$collision_core/core/DeckUI/local-runtime-collision.txt"
bash "$collision_core/tools/generate-manifest.sh" \
  --root "$collision_core" >/dev/null
before=$(tree_snapshot "$fixture")
bash "$fixture/scripts/sync-core.sh" --source "$collision_core" \
  >"$output" 2>&1
rc=$?
after=$(tree_snapshot "$fixture")
if [[ "$rc" -ne 0 &&
      "$(cat "$output")" == *"staged Core conflicts with local runtime path"* ]]; then
  ok "DeckUI runtime path colliding with staged Core fails closed"
else
  fail "DeckUI runtime/Core collision was accepted or misdiagnosed"
fi
if [[ "$before" == "$after" && -z "$(transaction_debris "$fixture")" ]]; then
  ok "DeckUI collision rejection makes no live mutation"
else
  fail "DeckUI collision rejection changed the wrapper"
fi

run_protected_path_case() {
  local label=$1 relative=$2 mode=$3 fixture output before after rc
  CASE_NUMBER=$((CASE_NUMBER + 1))
  fixture="$WORK/protected-$CASE_NUMBER"
  output="$WORK/protected-$CASE_NUMBER.out"
  copy_fixture "$fixture"
  if [[ "$mode" == untracked ]]; then
    mkdir -p "$(dirname "$fixture/$relative")"
    printf 'local-only sentinel\n' > "$fixture/$relative"
  else
    printf '\nlocal dirty sentinel\n' >> "$fixture/$relative"
  fi
  before=$(tree_snapshot "$fixture")
  bash "$fixture/scripts/sync-core.sh" --source "$SOURCE_CORE" \
    >"$output" 2>&1
  rc=$?
  after=$(tree_snapshot "$fixture")
  if [[ "$rc" -ne 0 &&
        "$(cat "$output")" == *"Core sync would overwrite"* ]]; then
    ok "$label: protected path is rejected before sync"
  else
    fail "$label: protected path was accepted or misdiagnosed"
  fi
  if [[ "$before" == "$after" && -z "$(transaction_debris "$fixture")" ]]; then
    ok "$label: rejection is mutation-free"
  else
    fail "$label: rejection changed the wrapper"
  fi
}

run_protected_path_case \
  "untracked scripts helper" \
  "scripts/local-helper.sh" \
  untracked
run_protected_path_case \
  "untracked template artifact" \
  "template/local-only.txt" \
  untracked
run_protected_path_case \
  "untracked assets artifact" \
  "assets/local-only.txt" \
  untracked
run_protected_path_case \
  "untracked protocols artifact" \
  "protocols/local-only.md" \
  untracked
run_protected_path_case \
  "tracked Core script edit" \
  "scripts/check-branch-flow.sh" \
  dirty
run_protected_path_case \
  "tracked template edit" \
  "template/scv/SCV.md" \
  dirty
run_protected_path_case \
  "tracked asset edit" \
  "assets/scv.jpg" \
  dirty
run_protected_path_case \
  "tracked protocol edit" \
  "protocols/help.md" \
  dirty
run_protected_path_case \
  "tracked command protocol-body edit" \
  "commands/help.md" \
  dirty

fixture="$WORK/adapter-file-replaced-by-directory"
output="$WORK/adapter-file-replaced-by-directory.out"
copy_fixture "$fixture"
mv "$fixture/scripts/sync.sh" "$WORK/adapter-sync-original.sh"
mkdir "$fixture/scripts/sync.sh"
printf 'adapter descendant sentinel\n' > "$fixture/scripts/sync.sh/local.txt"
before=$(tree_snapshot "$fixture")
bash "$fixture/scripts/sync-core.sh" --source "$SOURCE_CORE" \
  >"$output" 2>&1
rc=$?
after=$(tree_snapshot "$fixture")
if [[ "$rc" -ne 0 &&
      "$before" == "$after" &&
      -f "$fixture/scripts/sync.sh/local.txt" &&
      "$(cat "$output")" == *"adapter-owned path type change"* ]]; then
  ok "adapter-owned file replaced by a directory is rejected without data loss"
else
  fail "adapter-owned file/directory replacement was accepted or changed"
fi

fixture="$WORK/racy-clean-content"
output="$WORK/racy-clean-content.out"
copy_fixture "$fixture"
racy_path="$fixture/scripts/check-branch-flow.sh"
printf 'AAAA\n' > "$racy_path"
python3 - "$racy_path" <<'PY'
import os
import sys

# Keep the index timestamp far outside Git's racy-timestamp window so the
# setup deterministically exercises trustctime=false's same-size/stat bypass.
old = 946684800_000_000_000
os.utime(sys.argv[1], ns=(old, old))
PY
git -C "$fixture" add scripts/check-branch-flow.sh
git -C "$fixture" commit -qm "racy-clean baseline"
git -C "$fixture" config core.trustctime false
python3 - "$racy_path" <<'PY'
import os
import sys
from pathlib import Path

path = Path(sys.argv[1])
metadata = path.stat()
path.write_bytes(b"BBBB\n")
os.utime(path, ns=(metadata.st_atime_ns, metadata.st_mtime_ns))
PY
if [[ -z "$(git -C "$fixture" status --porcelain -- \
              scripts/check-branch-flow.sh)" ]]; then
  before=$(tree_snapshot "$fixture")
  bash "$fixture/scripts/sync-core.sh" --source "$SOURCE_CORE" --dry-run \
    >"$output" 2>&1
  rc=$?
  after=$(tree_snapshot "$fixture")
  if [[ "$rc" -ne 0 &&
        "$before" == "$after" &&
        "$(cat "$racy_path")" == "BBBB" &&
        "$(cat "$output")" == *"Core sync would overwrite tracked change"* ]]; then
    ok "direct index-blob hashing rejects a Git racy-clean content change"
  else
    fail "racy-clean content was accepted, changed, or misdiagnosed"
  fi
else
  fail "racy-clean test setup was visible to ordinary Git status"
fi

fixture="$WORK/hidden-mode"
output="$WORK/hidden-mode.out"
copy_fixture "$fixture"
git -C "$fixture" config core.fileMode false
chmod 645 "$fixture/scripts/check-branch-flow.sh"
before=$(tree_snapshot "$fixture")
bash "$fixture/scripts/sync-core.sh" --source "$SOURCE_CORE" --dry-run \
  >"$output" 2>&1
rc=$?
after=$(tree_snapshot "$fixture")
if [[ "$rc" -ne 0 &&
      "$(cat "$output")" == *"tracked executable-mode change"* &&
      "$before" == "$after" ]]; then
  ok "core.fileMode=false cannot hide a protected executable-bit edit"
else
  fail "hidden executable-bit edit was accepted, changed, or misdiagnosed"
fi

echo
echo "── hidden and concurrent Git index guards ──"
run_hidden_index_case() {
  local label=$1 flag=$2 fixture output before after rc
  CASE_NUMBER=$((CASE_NUMBER + 1))
  fixture="$WORK/hidden-index-$CASE_NUMBER"
  output="$WORK/hidden-index-$CASE_NUMBER.out"
  copy_fixture "$fixture"
  git -C "$fixture" update-index "$flag" scripts/check-branch-flow.sh
  printf '\nhidden index sentinel\n' \
    >> "$fixture/scripts/check-branch-flow.sh"
  before=$(tree_snapshot "$fixture")
  bash "$fixture/scripts/sync-core.sh" --source "$SOURCE_CORE" --dry-run \
    >"$output" 2>&1
  rc=$?
  after=$(tree_snapshot "$fixture")
  if [[ "$rc" -ne 0 &&
        "$(cat "$output")" == *"unsafe Git index flag"* &&
        "$before" == "$after" ]]; then
    ok "$label: hidden local edit is rejected and preserved"
  else
    fail "$label: hidden local edit was accepted, changed, or misdiagnosed"
  fi
}

run_hidden_index_case "assume-unchanged" --assume-unchanged
run_hidden_index_case "skip-worktree" --skip-worktree

fixture="$WORK/staged-command-body"
output="$WORK/staged-command-body.out"
copy_fixture "$fixture"
index_body="$WORK/staged-command-body.md"
git -C "$fixture" show HEAD:commands/help.md > "$index_body"
printf '\nstaged index body sentinel\n' >> "$index_body"
index_blob=$(git -C "$fixture" hash-object -w "$index_body")
git -C "$fixture" update-index \
  --cacheinfo "100644,$index_blob,commands/help.md"
before=$(tree_snapshot "$fixture")
bash "$fixture/scripts/sync-core.sh" --source "$SOURCE_CORE" --dry-run \
  >"$output" 2>&1
rc=$?
after=$(tree_snapshot "$fixture")
if [[ "$rc" -ne 0 &&
      "$(git -C "$fixture" show :commands/help.md)" == *"staged index body sentinel"* &&
      "$(cat "$output")" == *"Core sync would overwrite tracked change"* &&
      "$before" == "$after" ]]; then
  ok "staged command body is rejected and remains in the index"
else
  fail "staged command body was accepted, lost, or misdiagnosed"
fi

fixture="$WORK/late-index"
output="$WORK/late-index.out"
copy_fixture "$fixture"
late_index_body="$WORK/late-index-body.md"
late_index_replacement="$WORK/late-index-replacement"
git -C "$fixture" show HEAD:commands/help.md > "$late_index_body"
printf '\nlate staged index sentinel\n' >> "$late_index_body"
late_index_blob=$(git -C "$fixture" hash-object -w "$late_index_body")
git -C "$fixture" update-index \
  --cacheinfo "100644,$late_index_blob,commands/help.md"
cp -p "$fixture/.git/index" "$late_index_replacement"
git -C "$fixture" reset -q HEAD -- commands/help.md
SCV_CORE_SYNC_TEST_DRIFT=index \
  SCV_CORE_SYNC_TEST_INDEX_REPLACEMENT="$late_index_replacement" \
  bash "$fixture/scripts/sync-core.sh" --source "$SOURCE_CORE" \
  >"$output" 2>&1
rc=$?
if [[ "$rc" -ne 0 &&
      "$(git -C "$fixture" show :commands/help.md)" == *"late staged index sentinel"* &&
      ! -e "$fixture/.git/index.lock" &&
      -z "$(transaction_debris "$fixture")" ]]; then
  ok "late index-only change is rejected, preserved, and unlocks Git"
else
  fail "late index-only change was accepted, lost, or left Git locked"
fi

fixture="$WORK/alternate-index"
output="$WORK/alternate-index.out"
copy_fixture "$fixture"
alternate_index="$WORK/alternate-clean-index"
cp -p "$fixture/.git/index" "$alternate_index"
alternate_index_body="$WORK/alternate-index-body.md"
git -C "$fixture" show HEAD:commands/help.md > "$alternate_index_body"
printf '\ncanonical staged index sentinel\n' >> "$alternate_index_body"
alternate_index_blob=$(git -C "$fixture" hash-object -w "$alternate_index_body")
git -C "$fixture" update-index \
  --cacheinfo "100644,$alternate_index_blob,commands/help.md"
before=$(tree_snapshot "$fixture")
GIT_INDEX_FILE="$alternate_index" \
  bash "$fixture/scripts/sync-core.sh" --source "$SOURCE_CORE" --dry-run \
    >"$output" 2>&1
rc=$?
after=$(tree_snapshot "$fixture")
if [[ "$rc" -ne 0 &&
      "$before" == "$after" &&
      "$(git -C "$fixture" show :commands/help.md)" == \
        *"canonical staged index sentinel"* &&
      "$(cat "$output")" == *"unsupported Git repository override: GIT_INDEX_FILE"* ]]; then
  ok "alternate index override is rejected without hiding canonical staging"
else
  fail "alternate index override hid, changed, or misdiagnosed canonical staging"
fi

echo
echo "── concurrent sync lock ──"
fixture="$WORK/concurrent-lock"
copy_fixture "$fixture"
hold_file="$WORK/concurrent.hold"
ready_file="$hold_file.ready"
first_output="$WORK/concurrent-first.out"
second_output="$WORK/concurrent-second.out"
printf 'hold\n' > "$hold_file"
SCV_CORE_SYNC_LOCK_HOLD_FILE="$hold_file" \
  bash "$fixture/scripts/sync-core.sh" --source "$SOURCE_CORE" --dry-run \
  >"$first_output" 2>&1 &
first_pid=$!
for (( _attempt=1; _attempt <= 200; _attempt++ )); do
  [[ -f "$ready_file" ]] && break
  sleep 0.05
done
if [[ -f "$ready_file" ]]; then
  bash "$fixture/scripts/sync-core.sh" --source "$SOURCE_CORE" --dry-run \
    >"$second_output" 2>&1
  second_rc=$?
else
  second_rc=0
fi
rm -f "$hold_file"
wait "$first_pid"
first_rc=$?
if [[ "$second_rc" -ne 0 &&
      "$(cat "$second_output" 2>/dev/null)" == *"already running"* ]]; then
  ok "a concurrent updater is rejected by the repo-local lock"
else
  fail "concurrent updater was not rejected by the active lock"
fi
if [[ "$first_rc" -eq 0 && ! -e "$fixture/.scv-core-sync.lock" ]]; then
  ok "lock owner completes and removes its lock"
else
  fail "lock owner failed or left its lock behind"
fi

fixture="$WORK/stale-lock"
output="$WORK/stale-lock.out"
copy_fixture "$fixture"
mkdir "$fixture/.scv-core-sync.lock"
cat > "$fixture/.scv-core-sync.lock/owner" <<'EOF'
pid=999999999
process_start=1
token=stale-owner
EOF
if bash "$fixture/scripts/sync-core.sh" --source "$SOURCE_CORE" --dry-run \
    >"$output" 2>&1 &&
   [[ ! -e "$fixture/.scv-core-sync.lock" &&
      -z "$(quarantine_debris "$fixture")" ]]; then
  ok "dead-owner lock is safely quarantined and reclaimed"
else
  fail "dead-owner lock could not be reclaimed cleanly"
fi

fixture="$WORK/malformed-lock"
output="$WORK/malformed-lock.out"
copy_fixture "$fixture"
mkdir "$fixture/.scv-core-sync.lock"
printf 'not valid owner metadata\n' > "$fixture/.scv-core-sync.lock/owner"
if bash "$fixture/scripts/sync-core.sh" --source "$SOURCE_CORE" --dry-run \
    >"$output" 2>&1; then
  fail "malformed lock was accepted"
elif [[ -d "$fixture/.scv-core-sync.lock" &&
        "$(cat "$output")" == *"unsafe or malformed"* ]]; then
  ok "malformed lock fails closed and is preserved for inspection"
else
  fail "malformed lock rejection was unsafe or unclear"
fi

fixture="$WORK/symlink-lock"
output="$WORK/symlink-lock.out"
copy_fixture "$fixture"
lock_target="$WORK/symlink-lock-target"
mkdir "$lock_target"
printf 'do not delete\n' > "$lock_target/sentinel"
ln -s "$lock_target" "$fixture/.scv-core-sync.lock"
if bash "$fixture/scripts/sync-core.sh" --source "$SOURCE_CORE" --dry-run \
    >"$output" 2>&1; then
  fail "symlink lock was accepted"
elif [[ -L "$fixture/.scv-core-sync.lock" &&
        -f "$lock_target/sentinel" ]]; then
  ok "symlink lock fails closed without touching its target"
else
  fail "symlink lock guard changed its target"
fi

fixture="$WORK/symlink-vendor"
output="$WORK/symlink-vendor.out"
copy_fixture "$fixture"
external_vendor="$WORK/external-vendor"
mv "$fixture/vendor" "$external_vendor"
ln -s "$external_vendor" "$fixture/vendor"
external_before=$(tree_snapshot "$external_vendor")
if bash "$fixture/scripts/sync-core.sh" --source "$SOURCE_CORE" --dry-run \
    >"$output" 2>&1; then
  fail "symlink vendor parent was accepted"
elif [[ "$(tree_snapshot "$external_vendor")" == "$external_before" &&
        "$(cat "$output")" == *"vendor must be a real repository directory"* ]]; then
  ok "symlink vendor parent fails closed without external writes"
else
  fail "symlink vendor parent guard changed external data"
fi

echo
echo "── Deck runtime cache boundary ──"
fixture="$WORK/cache-overlap-repository"
output="$WORK/cache-overlap-repository.out"
copy_fixture "$fixture"
before=$(tree_snapshot "$fixture")
if SCV_DECK_CACHE_DIR="$fixture/scripts" \
    bash "$fixture/scripts/sync-core.sh" --source "$SOURCE_CORE" \
      >"$output" 2>&1; then
  fail "Deck cache inside the wrapper repository was accepted"
elif [[ "$before" == "$(tree_snapshot "$fixture")" &&
        "$(cat "$output")" == *"cache base overlaps updater-protected path"* ]]; then
  ok "Deck cache inside the wrapper fails closed without live mutation"
else
  fail "Deck cache repository-overlap rejection was unsafe or unclear"
fi

fixture="$WORK/cache-overlap-legacy"
output="$WORK/cache-overlap-legacy.out"
copy_fixture "$fixture"
before=$(tree_snapshot "$fixture")
if SCV_DECK_CACHE_DIR="$fixture/DeckUI/node_modules" \
    bash "$fixture/scripts/sync-core.sh" --source "$SOURCE_CORE" \
      >"$output" 2>&1; then
  fail "Deck cache nested in the legacy migration source was accepted"
elif [[ "$before" == "$(tree_snapshot "$fixture")" &&
        "$(cat "$output")" == *"cache base overlaps updater-protected path"* ]]; then
  ok "Deck cache nested in legacy DeckUI fails without recursive migration"
else
  fail "Deck cache legacy-overlap rejection was unsafe or unclear"
fi

echo
echo "── project-core write boundary ──"
fixture="$WORK/project-core-direct"
output="$WORK/project-core-direct.out"
copy_fixture "$fixture"
before=$(tree_snapshot "$fixture")
if bash "$fixture/scripts/project-core.sh" \
    --vendor "$SOURCE_CORE" --destination "$fixture" >"$output" 2>&1; then
  fail "project-core wrote directly to the live wrapper"
elif [[ "$before" == "$(tree_snapshot "$fixture")" &&
        "$(cat "$output")" == *"write mode is internal"* ]]; then
  ok "project-core direct live write is blocked without authorization"
else
  fail "project-core direct-write guard changed the wrapper"
fi

token="0123456789abcdef0123456789abcdef"
printf '%s\n' "$token" > "$WORK/.scv-project-core-token"
output="$WORK/project-core-broad.out"
if SCV_PROJECT_CORE_STAGE_ROOT="$WORK" \
    SCV_PROJECT_CORE_WRITE_TOKEN="$token" \
    bash "$fixture/scripts/project-core.sh" \
      --vendor "$SOURCE_CORE" --destination "$fixture" >"$output" 2>&1; then
  fail "project-core accepted a stage root containing the live repository"
elif [[ "$(cat "$output")" == *"must not contain the wrapper repository"* ]]; then
  ok "project-core rejects broad stage roots containing the wrapper"
else
  fail "project-core broad-stage rejection was unclear"
fi
rm -f "$WORK/.scv-project-core-token"

project_stage="$WORK/project-core-stage"
project_destination="$project_stage/wrapper"
mkdir -p "$project_destination"
ln -s "$project_destination" "$project_stage/wrapper-link"
printf '%s\n' "$token" > "$project_stage/.scv-project-core-token"
output="$WORK/project-core-symlink.out"
if SCV_PROJECT_CORE_STAGE_ROOT="$project_stage" \
    SCV_PROJECT_CORE_WRITE_TOKEN="$token" \
    bash "$REPO_ROOT/scripts/project-core.sh" \
      --vendor "$SOURCE_CORE" \
      --destination "$project_stage/wrapper-link" >"$output" 2>&1; then
  fail "project-core accepted a symlink destination"
elif [[ "$(cat "$output")" == *"must not be symlinks"* ]]; then
  ok "project-core rejects symlink destinations"
else
  fail "project-core symlink-destination rejection was unclear"
fi

symlink_stage="$WORK/project-core-tree-symlink-stage"
symlink_destination="$symlink_stage/wrapper"
external_commands="$WORK/project-core-external-commands"
mkdir -p "$symlink_destination"
for directory in scripts tests; do
  cp -R -p "$REPO_ROOT/$directory" "$symlink_destination/$directory"
done
cp -R -p "$REPO_ROOT/commands" "$external_commands"
ln -s "$external_commands" "$symlink_destination/commands"
printf '%s\n' "$token" > "$symlink_stage/.scv-project-core-token"
external_before=$(tree_snapshot "$external_commands")
output="$WORK/project-core-tree-symlink.out"
if SCV_PROJECT_CORE_STAGE_ROOT="$symlink_stage" \
    SCV_PROJECT_CORE_WRITE_TOKEN="$token" \
    bash "$REPO_ROOT/scripts/project-core.sh" \
      --vendor "$SOURCE_CORE" \
      --destination "$symlink_destination" >"$output" 2>&1; then
  fail "project-core accepted a symlink inside the destination tree"
elif [[ "$external_before" == "$(tree_snapshot "$external_commands")" &&
        "$(cat "$output")" == *"destination tree contains a symlink"* ]]; then
  ok "project-core rejects a command-tree symlink without external writes"
else
  fail "project-core command-tree symlink rejection changed external data"
fi

nested_stage="$WORK/project-core-nested-symlink-stage"
nested_destination="$nested_stage/wrapper"
external_lib="$WORK/project-core-external-lib"
mkdir -p "$nested_destination"
for directory in scripts commands tests; do
  cp -R -p "$REPO_ROOT/$directory" "$nested_destination/$directory"
done
mv "$nested_destination/scripts/lib" "$external_lib"
ln -s "$external_lib" "$nested_destination/scripts/lib"
printf '%s\n' "$token" > "$nested_stage/.scv-project-core-token"
external_before=$(tree_snapshot "$external_lib")
output="$WORK/project-core-nested-symlink.out"
if SCV_PROJECT_CORE_STAGE_ROOT="$nested_stage" \
    SCV_PROJECT_CORE_WRITE_TOKEN="$token" \
    bash "$REPO_ROOT/scripts/project-core.sh" \
      --vendor "$SOURCE_CORE" \
      --destination "$nested_destination" >"$output" 2>&1; then
  fail "project-core accepted a nested symlink parent"
elif [[ "$external_before" == "$(tree_snapshot "$external_lib")" &&
        "$(cat "$output")" == *"destination tree contains a symlink"* ]]; then
  ok "project-core rejects a nested script symlink without external writes"
else
  fail "project-core nested-symlink rejection changed external data"
fi

for directory in scripts commands tests; do
  cp -R -p "$REPO_ROOT/$directory" "$project_destination/$directory"
done
command_mode_before=$(python3 -c \
  'import os,stat,sys; print(stat.S_IMODE(os.lstat(sys.argv[1]).st_mode))' \
  "$project_destination/commands/help.md")
if SCV_PROJECT_CORE_STAGE_ROOT="$project_stage" \
    SCV_PROJECT_CORE_WRITE_TOKEN="$token" \
    bash "$REPO_ROOT/scripts/project-core.sh" \
      --vendor "$SOURCE_CORE" \
      --destination "$project_destination" >/dev/null 2>&1; then
  ok "authorized safe-stage projection succeeds"
else
  fail "authorized safe-stage projection failed"
fi
command_mode_after=$(python3 -c \
  'import os,stat,sys; print(stat.S_IMODE(os.lstat(sys.argv[1]).st_mode))' \
  "$project_destination/commands/help.md")
if [[ "$command_mode_before" == "$command_mode_after" ]]; then
  ok "command body rewrite preserves adapter-owned file mode"
else
  fail "command body rewrite changed adapter-owned file mode"
fi
mkdir -p "$project_destination/DeckUI/node_modules"
printf 'non-git runtime\n' \
  > "$project_destination/DeckUI/node_modules/.scv-non-git-runtime"
if bash "$REPO_ROOT/scripts/project-core.sh" \
    --vendor "$SOURCE_CORE" \
    --destination "$project_destination" --check >/dev/null 2>&1; then
  fail "non-Git projection check silently excluded runtime paths"
else
  ok "non-Git projection check treats every DeckUI path as contract-owned"
fi

empty_vendor="$WORK/core-owned-empty-vendor"
cp -R -p "$SOURCE_CORE" "$empty_vendor"
mkdir -p \
  "$empty_vendor/core/DeckUI/src/deck/decks/core-owned-empty"
if SCV_PROJECT_CORE_STAGE_ROOT="$project_stage" \
    SCV_PROJECT_CORE_WRITE_TOKEN="$token" \
    bash "$REPO_ROOT/scripts/project-core.sh" \
      --vendor "$empty_vendor" \
      --destination "$project_destination" >/dev/null 2>&1; then
  git -C "$project_destination" init -q
  git -C "$project_destination" config user.name "SCV Projection Test"
  git -C "$project_destination" config user.email "projection@example.invalid"
  git -C "$project_destination" add -A
  git -C "$project_destination" commit -qm "projected baseline"
  if [[ -d "$project_destination/DeckUI/src/deck/decks/core-owned-empty" ]] &&
     bash "$REPO_ROOT/scripts/project-core.sh" \
       --vendor "$empty_vendor" \
       --destination "$project_destination" --check >/dev/null 2>&1; then
    ok "Git projection check retains Core-owned empty DeckUI directories"
  else
    fail "Git projection check excluded a Core-owned empty directory"
  fi
else
  fail "Core-owned empty-directory projection failed"
fi

echo
echo "── wrapper/Core version independence ──"
fixture="$WORK/version-independent"
copy_fixture "$fixture"
python3 - "$fixture" <<'PY'
import json
import sys
from pathlib import Path

root = Path(sys.argv[1])
wrapper_version = "7.8.9"
(root / "VERSION").write_text(wrapper_version + "\n", encoding="utf-8")
plugin_path = root / ".claude-plugin/plugin.json"
plugin = json.loads(plugin_path.read_text(encoding="utf-8"))
plugin["version"] = wrapper_version
plugin_path.write_text(json.dumps(plugin, indent=2) + "\n", encoding="utf-8")
marketplace_path = root / ".claude-plugin/marketplace.json"
marketplace = json.loads(marketplace_path.read_text(encoding="utf-8"))
for entry in marketplace["plugins"]:
    if entry["name"] == "scv":
        entry["version"] = wrapper_version
marketplace_path.write_text(json.dumps(marketplace, indent=2) + "\n", encoding="utf-8")
PY
if bash "$fixture/scripts/verify-core.sh" >/dev/null 2>&1; then
  ok "wrapper metadata may use a valid version independent from pinned Core"
else
  fail "verifier still couples wrapper version to Core version"
fi

fixture="$WORK/nested-materialized-source"
output="$WORK/nested-materialized-source.out"
copy_fixture "$fixture"
expected_source_commit=$(tr -d '[:space:]' < "$fixture/vendor/scv-core/SOURCE_COMMIT")
if bash "$fixture/scripts/sync-core.sh" \
    --source "$fixture/vendor/scv-core" --dry-run >"$output" 2>&1 &&
   [[ "$(cat "$output")" == *"CORE_COMMIT: $expected_source_commit"* ]]; then
  ok "materialized Core nested in wrapper Git is not misclassified as a checkout"
else
  fail "nested materialized Core inherited wrapper Git provenance"
fi

fixture="$WORK/success"
output="$WORK/success.out"
copy_fixture "$fixture"
printf '\n# adapter-owned local sentinel\n' >> "$fixture/scripts/sync.sh"
adapter_before=$(portable_sha256 "$fixture/scripts/sync.sh")
before_metadata=$(metadata_snapshot "$fixture")
if bash "$fixture/scripts/sync-core.sh" --source "$SOURCE_CORE" \
    >"$output" 2>&1; then
  ok "successful local Core sync completes"
else
  fail "successful local Core sync failed"
  tail -n 20 "$output"
fi
after_metadata=$(metadata_snapshot "$fixture")
if [[ "$before_metadata" == "$after_metadata" ]]; then
  ok "successful Core sync preserves wrapper VERSION/plugin/marketplace bytes"
else
  fail "successful Core sync rewrote wrapper release metadata"
fi
if [[ "$(portable_sha256 "$fixture/scripts/sync.sh")" == "$adapter_before" ]]; then
  ok "successful Core sync preserves adapter-owned script changes"
else
  fail "successful Core sync overwrote an adapter-owned script"
fi
if [[ "$(cat "$fixture/vendor/wrapper-owned-sibling.txt" 2>/dev/null)" == \
      "tracked wrapper vendor sibling" ]]; then
  ok "successful Core sync preserves other tracked vendor entries"
else
  fail "successful Core sync lost another tracked vendor entry"
fi
if runtime_paths_preserved "$fixture"; then
  ok "successful transaction preserves all ignored/untracked DeckUI paths"
else
  fail "successful transaction lost ignored/untracked DeckUI paths"
fi
deck_runtime_path=$(
  "$fixture/vendor/scv-core/core/scripts/deck-runtime.sh" path
)
if [[ -f "$deck_runtime_path/node_modules/.scv-atomicity-sentinel" &&
      -f "$deck_runtime_path/scripts/deckdoc/node_modules/.scv-atomicity-sentinel" &&
      -f "$deck_runtime_path/dist-deck/.scv-atomicity-sentinel" &&
      -f "$deck_runtime_path/src/deck/decks/atomic-runtime/deck.json" ]]; then
  ok "successful sync migrates known legacy DeckUI runtime into external cache"
else
  fail "successful sync did not migrate known DeckUI runtime entries"
fi
if bash "$fixture/scripts/verify-core.sh" >/dev/null 2>&1; then
  ok "successful transaction leaves a verified wrapper"
else
  fail "successful transaction leaves an invalid wrapper"
fi
if [[ -z "$(transaction_debris "$fixture")" ]]; then
  ok "successful transaction removes its stage and backup"
else
  fail "successful transaction left transaction debris"
fi

echo
echo "── verifier provenance binding ──"
fixture="$WORK/tampered-manifest"
copy_fixture "$fixture"
python3 - "$fixture/vendor/scv-core/core-manifest.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
data = json.loads(path.read_text(encoding="utf-8"))
data["source_commit"] = "0" * 40
path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
if bash "$fixture/scripts/verify-core.sh" >/dev/null 2>&1; then
  fail "tampered materialized manifest provenance was accepted"
else
  ok "tampered materialized manifest provenance is rejected"
fi

fixture="$WORK/tampered-lock"
copy_fixture "$fixture"
python3 - "$fixture/core.lock" "$fixture/vendor/scv-core/core.lock.json" <<'PY'
import json
import sys
from pathlib import Path

for raw_path in sys.argv[1:]:
    path = Path(raw_path)
    data = json.loads(path.read_text(encoding="utf-8"))
    data["manifest_sha256"] = "0" * 64
    data["payload_sha256"] = "1" * 64
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
if bash "$fixture/scripts/verify-core.sh" >/dev/null 2>&1; then
  fail "tampered materialized lock digests were accepted"
else
  ok "materialized manifest/payload digests are recomputed from disk"
fi

tampered_local_source="$WORK/tampered-local-source"
cp -R -p "$SOURCE_CORE" "$tampered_local_source"
python3 - "$tampered_local_source/tools/vendor-core.sh" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
needle = '"$STAGE/tools/verify-core.sh" --root "$STAGE" >/dev/null\n'
injection = """python3 - "$STAGE/core.lock.json" <<'PY_TAMPER'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
lock = json.loads(path.read_text(encoding="utf-8"))
lock["source_manifest_sha256"] = "0" * 64
path.write_text(json.dumps(lock, indent=2) + "\\n", encoding="utf-8")
PY_TAMPER
"""
if text.count(needle) != 2:
    raise SystemExit("unexpected vendor-core verifier layout")
first = text.index(needle)
second = text.index(needle, first + len(needle))
text = text[:second] + injection + text[second:]
path.write_text(text, encoding="utf-8")
PY
bash "$tampered_local_source/tools/generate-manifest.sh" \
  --root "$tampered_local_source" >/dev/null
fixture="$WORK/tampered-local-source-wrapper"
output="$WORK/tampered-local-source.out"
copy_fixture "$fixture"
before=$(tree_snapshot "$fixture")
bash "$fixture/scripts/sync-core.sh" \
  --source "$tampered_local_source" --dry-run >"$output" 2>&1
rc=$?
after=$(tree_snapshot "$fixture")
if [[ "$rc" -ne 0 &&
      "$(cat "$output")" == *"source_manifest_sha256 does not match"* &&
      "$before" == "$after" ]]; then
  ok "local source manifest digest is recomputed and bound to candidate lock"
else
  fail "tampered local source digest was accepted, changed, or misdiagnosed"
fi

echo
echo "── requested release provenance ──"
FAKE_BIN="$WORK/fake-bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
set -eu
output=
request_url=
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      output=$2
      shift 2
      ;;
    http://*|https://*)
      request_url=$1
      shift
      ;;
    *)
      shift
      ;;
  esac
done
[[ -n "$output" && -n "$request_url" ]]
case "$request_url" in
  *.sha256) cp "$SCV_FAKE_SIDECAR" "$output" ;;
  *) cp "$SCV_FAKE_ARCHIVE" "$output" ;;
esac
EOF
cat > "$FAKE_BIN/gh" <<'EOF'
#!/usr/bin/env bash
set -eu
[[ "${1:-}" == api ]]
printf '%s\n' "$SCV_FAKE_TAG_COMMIT"
EOF
chmod +x "$FAKE_BIN/curl" "$FAKE_BIN/gh"

make_fake_release() {
  local requested_version=$1 tamper_source_lock=${2:-0}
  local payload_parent="$WORK/fake-payload"
  local payload_root="$payload_parent/scv-core-v${requested_version}"
  rm -rf "$payload_parent"
  mkdir -p "$payload_parent"
  cp -R -p "$SOURCE_CORE" "$payload_root"
  python3 - "$payload_root/core/host-profile.env" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace("SCV_HOST_ID=claude-code", "SCV_HOST_ID=canonical")
path.write_text(text, encoding="utf-8")
PY
  bash "$payload_root/tools/generate-manifest.sh" --root "$payload_root" \
    >/dev/null
  if (( tamper_source_lock )); then
    python3 - "$payload_root/tools/vendor-core.sh" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
needle = '"$STAGE/tools/verify-core.sh" --root "$STAGE" >/dev/null\n'
injection = """python3 - "$STAGE/core.lock.json" <<'PY_TAMPER'
import json
import sys
from pathlib import Path
path = Path(sys.argv[1])
lock = json.loads(path.read_text(encoding="utf-8"))
lock["source_manifest_sha256"] = "0" * 64
path.write_text(json.dumps(lock, indent=2) + "\\n", encoding="utf-8")
PY_TAMPER
"""
if text.count(needle) != 2:
    raise SystemExit("unexpected vendor-core verifier layout")
first = text.index(needle)
second = text.index(needle, first + len(needle))
text = text[:second] + injection + text[second:]
path.write_text(text, encoding="utf-8")
PY
    bash "$payload_root/tools/generate-manifest.sh" --root "$payload_root" \
      >/dev/null
  fi
  SCV_FAKE_ARCHIVE="$WORK/scv-core-v${requested_version}.tar.gz"
  SCV_FAKE_SIDECAR="$SCV_FAKE_ARCHIVE.sha256"
  tar -czf "$SCV_FAKE_ARCHIVE" \
    -C "$payload_parent" "scv-core-v${requested_version}"
  printf '%s  %s\n' \
    "$(portable_sha256 "$SCV_FAKE_ARCHIVE")" \
    "scv-core-v${requested_version}.tar.gz" \
    > "$SCV_FAKE_SIDECAR"
}

RELEASE_CASE=0
run_release_rejection() {
  local label=$1 requested_version=$2 repository=$3 tag_commit=$4
  local expected_message=$5 tamper_source_lock=${6:-0}
  local fixture output before after rc
  RELEASE_CASE=$((RELEASE_CASE + 1))
  fixture="$WORK/release-rejection-$RELEASE_CASE"
  output="$WORK/release-rejection-$RELEASE_CASE.out"
  copy_fixture "$fixture"
  make_fake_release "$requested_version" "$tamper_source_lock"
  before=$(tree_snapshot "$fixture")
  PATH="$FAKE_BIN:$PATH" \
    SCV_FAKE_ARCHIVE="$SCV_FAKE_ARCHIVE" \
    SCV_FAKE_SIDECAR="$SCV_FAKE_SIDECAR" \
    SCV_FAKE_TAG_COMMIT="$tag_commit" \
    bash "$fixture/scripts/sync-core.sh" \
      --version "$requested_version" \
      --repository "$repository" \
      --dry-run >"$output" 2>&1
  rc=$?
  after=$(tree_snapshot "$fixture")
  if [[ "$rc" -ne 0 && "$(cat "$output")" == *"$expected_message"* ]]; then
    ok "$label: mismatch is rejected with a specific diagnosis"
  else
    fail "$label: mismatched release was accepted or misdiagnosed"
    tail -n 10 "$output"
  fi
  if [[ "$before" == "$after" ]]; then
    ok "$label: rejection is read-only"
  else
    fail "$label: rejection changed the wrapper"
  fi
}

source_commit=$(tr -d '[:space:]' < "$SOURCE_CORE/SOURCE_COMMIT")
core_version=$(tr -d '[:space:]' < "$SOURCE_CORE/VERSION")
mismatched_version=99.99.99
[[ "$mismatched_version" != "$core_version" ]] || mismatched_version=98.98.98
run_release_rejection \
  "requested tag versus payload VERSION" \
  "$mismatched_version" \
  "wookiya1364/scv-core" \
  "$source_commit" \
  "payload VERSION"
run_release_rejection \
  "requested repository versus SOURCE_INFO" \
  "$core_version" \
  "example/core" \
  "$source_commit" \
  "SOURCE_INFO repository"
run_release_rejection \
  "requested tag commit versus SOURCE_COMMIT" \
  "$core_version" \
  "wookiya1364/scv-core" \
  "ffffffffffffffffffffffffffffffffffffffff" \
  "SOURCE_COMMIT does not match"
run_release_rejection \
  "source manifest digest versus candidate lock" \
  "$core_version" \
  "wookiya1364/scv-core" \
  "$source_commit" \
  "source_manifest_sha256 does not match" \
  1

echo
echo "── result: $PASS passed, $FAIL failed ──"
[[ "$FAIL" -eq 0 ]]
