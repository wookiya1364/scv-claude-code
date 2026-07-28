#!/usr/bin/env bash
# Cross-host state compatibility and explicit Claude pointer migration.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HYDRATE="$REPO_ROOT/scripts/hydrate.sh"
HELP="$REPO_ROOT/scripts/help.sh"
SYNC="$REPO_ROOT/scripts/sync.sh"
STATE_INDEX="$REPO_ROOT/adapter/scripts/state-index.sh"
MERGE_LIB="$REPO_ROOT/scripts/lib/merge.sh"
READPATH="$REPO_ROOT/scripts/readpath.sh"
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/scv-state-adapter.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

pass_count=0
fail() {
  echo "FAIL: $*" >&2
  exit 1
}
pass() {
  pass_count=$((pass_count + 1))
  echo "PASS: $*"
}

# The model-facing adapter must pass parsed text to the helper as one quoted
# argv element. Shell metacharacters, whitespace, and quotes stay inert.
ARG_PROJECT="$TMP_DIR/argument-safety"
mkdir -p "$ARG_PROJECT"
SENTINEL="$ARG_PROJECT/argument-was-executed"
malicious_arg="two words 'single' \"double\" ; touch $SENTINEL ; \$(touch $SENTINEL)"
argument_output=$(cd "$ARG_PROJECT" && "$HELP" "$malicious_arg")
[[ "$argument_output" == *"ARG_CONVERSATION: $malicious_arg"* ]] ||
  fail "help did not preserve the parsed argument as one value"
[[ ! -e "$SENTINEL" ]] ||
  fail "help executed shell syntax embedded in its argument"
pass "help keeps spaces, quotes, and shell syntax inert"

tree_digest() {
  local root=$1
  (
    cd "$root"
    find scv -type f -print | LC_ALL=C sort | while IFS= read -r file; do
      cksum "$file"
    done
  ) | cksum | awk '{print $1 ":" $2}'
}

PROJECT="$TMP_DIR/codex-legacy"
"$HYDRATE" init "$PROJECT" >/dev/null
[[ -f "$PROJECT/scv/SCV.md" ]] ||
  fail "Claude hydrate did not create canonical SCV.md"
[[ ! -e "$PROJECT/scv/CLAUDE.md" ]] ||
  fail "Claude hydrate created a host-specific pointer"
[[ ! -e "$PROJECT/scv/CODEX.md" ]] ||
  fail "Claude hydrate created an absent other-host pointer"
[[ ! -e "$PROJECT/loop-runner.md" ]] ||
  fail "Claude hydrate leaked the adapter integration template"
pass "hydrate creates only host-neutral SCV.md"

CORE_PROJECT="$TMP_DIR/core-hydrate"
"$REPO_ROOT/vendor/scv-core/core/scripts/hydrate.sh" \
  init "$CORE_PROJECT" >/dev/null
diff -qr "$PROJECT" "$CORE_PROJECT" >/dev/null ||
  fail "Claude wrapper hydrate differs from the host-neutral core tree"
pass "new hydrate tree is byte-identical to core"
printf 'legacy material\n' > "$PROJECT/scv/raw/legacy.txt"
(cd "$PROJECT" && "$READPATH" update >/dev/null)

# Simulate a project hydrated only by the legacy Codex wrapper.
cp -p "$PROJECT/scv/SCV.md" "$PROJECT/scv/CODEX.md"
rm -f "$PROJECT/scv/SCV.md"

# Preserve project-local state through the explicit migration.
# shellcheck source=../scripts/lib/merge.sh
source "$MERGE_LIB"
replace_marker_block \
  "$PROJECT/scv/CODEX.md" \
  "PROJECT:LOCAL START" \
  "PROJECT:LOCAL END" \
  "KEEP-CROSS-HOST-LOCAL-RULE"

before_help=$(tree_digest "$PROJECT")
state_output=$("$STATE_INDEX" --project-dir "$PROJECT")
[[ "$state_output" == *"STATE_INDEX: legacy"* && "$state_output" == *"HYDRATED: yes"* ]] ||
  fail "state-index read did not classify CODEX.md-only state as hydrated legacy"
help_output=$(cd "$PROJECT" && "$HELP")
after_help=$(tree_digest "$PROJECT")
[[ "$help_output" == *"hydrate complete (scv/CODEX.md"* ]] ||
  fail "Claude help did not recognize a CODEX.md-only hydrated project"
[[ "$before_help" == "$after_help" ]] ||
  fail "read-only Claude help mutated the legacy project"
[[ ! -f "$PROJECT/scv/SCV.md" ]] ||
  fail "read-only Claude help auto-migrated SCV.md"
pass "CODEX.md-only project is recognized without mutation"

before_usage=$(tree_digest "$PROJECT")
(cd "$PROJECT" && "$HYDRATE" --help >/dev/null)
(cd "$PROJECT" && "$SYNC" --help >/dev/null)
set +e
(cd "$PROJECT" && "$SYNC" --not-a-real-option >/dev/null 2>&1)
unknown_rc=$?
set -e
[[ "$unknown_rc" -ne 0 ]] ||
  fail "sync accepted an unknown option"
[[ "$(tree_digest "$PROJECT")" == "$before_usage" ]] ||
  fail "help or invalid arguments mutated legacy project state"
[[ ! -e "$PROJECT/.scv-backup" ]] ||
  fail "help or invalid arguments created a migration backup"
pass "help and invalid arguments stay read-only"

grep -q '^status: N/A' "$PROJECT/scv/DOMAIN.md" ||
  fail "legacy project lost adoption-mode N/A status"
readpath_before=$(cksum "$PROJECT/scv/readpath.json")
legacy_before=$(cksum "$PROJECT/scv/CODEX.md")
pass "legacy N/A state and readpath baseline exist"

"$SYNC" --project-dir "$PROJECT" --dry-run >/dev/null
[[ ! -f "$PROJECT/scv/SCV.md" ]] ||
  fail "sync --dry-run created SCV.md"
[[ "$(cksum "$PROJECT/scv/CODEX.md")" == "$legacy_before" ]] ||
  fail "sync --dry-run modified CODEX.md"
pass "sync --dry-run previews without migration"

sync_output=$("$SYNC" --project-dir "$PROJECT")
[[ -f "$PROJECT/scv/SCV.md" ]] ||
  fail "explicit sync did not create canonical SCV.md"
grep -q 'KEEP-CROSS-HOST-LOCAL-RULE' "$PROJECT/scv/SCV.md" ||
  fail "PROJECT:LOCAL was not preserved in canonical SCV.md"
grep -q '<!-- SCV:HOST-POINTER target=SCV.md -->' "$PROJECT/scv/CODEX.md" ||
  fail "legacy CODEX.md was not converted to a verified pointer"
[[ ! -e "$PROJECT/scv/CLAUDE.md" ]] ||
  fail "migration created the absent Claude pointer"
[[ "$sync_output" == *"LEGACY_STATE_BACKUP:"* ]] ||
  fail "explicit sync did not report the legacy backup"
find "$PROJECT/.scv-backup" -path '*/shared-core-migration/CODEX.md' -type f | grep -q . ||
  fail "legacy CODEX.md backup is absent"
grep -q '^status: N/A' "$PROJECT/scv/DOMAIN.md" ||
  fail "explicit migration changed adoption-mode N/A status"
[[ "$(cksum "$PROJECT/scv/readpath.json")" == "$readpath_before" ]] ||
  fail "explicit migration changed the readpath baseline"
pass "explicit sync preserves state and installs a pointer"

# The same migration rule applies to the Claude legacy filename: preserve the
# existing path as a pointer, but never manufacture the absent Codex path.
CLAUDE_LEGACY_PROJECT="$TMP_DIR/claude-legacy"
"$HYDRATE" init "$CLAUDE_LEGACY_PROJECT" >/dev/null
mv \
  "$CLAUDE_LEGACY_PROJECT/scv/SCV.md" \
  "$CLAUDE_LEGACY_PROJECT/scv/CLAUDE.md"
"$SYNC" --project-dir "$CLAUDE_LEGACY_PROJECT" >/dev/null
[[ -f "$CLAUDE_LEGACY_PROJECT/scv/SCV.md" ]] ||
  fail "Claude legacy migration did not create canonical SCV.md"
grep -qx '<!-- SCV:HOST-POINTER target=SCV.md -->' \
  "$CLAUDE_LEGACY_PROJECT/scv/CLAUDE.md" ||
  fail "existing Claude legacy index was not pointerized"
[[ ! -e "$CLAUDE_LEGACY_PROJECT/scv/CODEX.md" ]] ||
  fail "Claude legacy migration created an absent Codex pointer"
find "$CLAUDE_LEGACY_PROJECT/.scv-backup" \
  -path '*/shared-core-migration/CLAUDE.md' -type f | grep -q . ||
  fail "legacy CLAUDE.md backup is absent"
pass "migration pointerizes only the existing Claude legacy file"

# A pointer without its canonical target must fail before core sync can mistake
# the pointer prose for legacy workflow state.
BROKEN_POINTER="$TMP_DIR/broken-pointer"
mkdir -p "$BROKEN_POINTER/scv"
cat > "$BROKEN_POINTER/scv/CLAUDE.md" <<'EOF'
# SCV host compatibility pointer

<!-- SCV:HOST-POINTER target=SCV.md -->
EOF
set +e
broken_output=$("$SYNC" --project-dir "$BROKEN_POINTER" 2>&1)
broken_rc=$?
set -e
[[ "$broken_rc" -eq 4 ]] ||
  fail "broken legacy pointer did not return exit 4 (got $broken_rc)"
[[ "$broken_output" == *"STATE_INDEX_BROKEN_POINTER"* ]] ||
  fail "broken legacy pointer was not explained"
[[ ! -e "$BROKEN_POINTER/scv/SCV.md" ]] ||
  fail "broken legacy pointer was copied into canonical state"
pass "broken pointer fails before core sync"

# A canonical/legacy disagreement must stop before changing either file.
CONFLICT="$TMP_DIR/conflict"
"$HYDRATE" init "$CONFLICT" >/dev/null
cp -p "$CONFLICT/scv/SCV.md" "$CONFLICT/scv/CODEX.md"
printf '\nconflicting legacy state\n' >> "$CONFLICT/scv/CODEX.md"
conflict_before=$(tree_digest "$CONFLICT")
set +e
conflict_output=$("$SYNC" --project-dir "$CONFLICT" 2>&1)
conflict_rc=$?
set -e
[[ "$conflict_rc" -eq 4 ]] ||
  fail "state conflict did not return exit 4 (got $conflict_rc)"
[[ "$conflict_output" == *"STATE_INDEX_CONFLICT"* ]] ||
  fail "state conflict was not explained"
[[ "$(tree_digest "$CONFLICT")" == "$conflict_before" ]] ||
  fail "state conflict mutated project files"
pass "conflicting canonical and legacy state fails without mutation"

# A core failure must happen before the adapter backs up or pointerizes legacy
# state. Use an isolated wrapper-shaped fixture so the injected failure cannot
# alter the real vendored payload.
FAILURE_PLUGIN="$TMP_DIR/failure-plugin"
mkdir -p \
  "$FAILURE_PLUGIN/scripts" \
  "$FAILURE_PLUGIN/adapter/scripts" \
  "$FAILURE_PLUGIN/vendor/scv-core/core/scripts"
cp -p "$SYNC" "$FAILURE_PLUGIN/scripts/sync.sh"
cp -p "$STATE_INDEX" "$FAILURE_PLUGIN/adapter/scripts/state-index.sh"
cat > "$FAILURE_PLUGIN/vendor/scv-core/core/scripts/sync.sh" <<'EOF'
#!/usr/bin/env bash
echo "INJECTED_CORE_FAILURE"
exit 23
EOF
chmod +x "$FAILURE_PLUGIN/vendor/scv-core/core/scripts/sync.sh"

FAILURE_PROJECT="$TMP_DIR/core-sync-failure"
mkdir -p "$FAILURE_PROJECT/scv"
printf 'legacy state before core failure\n' > "$FAILURE_PROJECT/scv/CODEX.md"
failure_before=$(cksum "$FAILURE_PROJECT/scv/CODEX.md")
set +e
failure_output=$(
  "$FAILURE_PLUGIN/scripts/sync.sh" \
    --project-dir "$FAILURE_PROJECT" 2>&1
)
failure_rc=$?
set -e
[[ "$failure_rc" -eq 23 ]] ||
  fail "core sync failure was not propagated (got $failure_rc)"
[[ "$failure_output" == *"INJECTED_CORE_FAILURE"* ]] ||
  fail "failure injection did not reach the core sync boundary"
[[ "$(cksum "$FAILURE_PROJECT/scv/CODEX.md")" == "$failure_before" ]] ||
  fail "core failure modified the active legacy index"
[[ ! -e "$FAILURE_PROJECT/scv/SCV.md" ]] ||
  fail "core failure left a canonical index behind"
[[ ! -e "$FAILURE_PROJECT/scv/CLAUDE.md" ]] ||
  fail "core failure created the current-host pointer"
[[ ! -e "$FAILURE_PROJECT/.scv-backup" ]] ||
  fail "core failure created a migration backup"
pass "core failure occurs before legacy migration"

echo "PASS: $pass_count cross-host state adapter checks"
