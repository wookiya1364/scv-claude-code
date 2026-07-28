#!/usr/bin/env bash
# test-workspace.sh — unit tests for scripts/lib/workspace.sh
# Self-contained: creates temp fixtures, sources the lib, asserts mode + readers.
# Run: bash tests/test-workspace.sh

set -uo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
LIB="$REPO_ROOT/scripts/lib/workspace.sh"

PASS=0
FAIL=0
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
eq()   { # eq <label> <expected> <actual>
  if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1 — expected [$2], got [$3]"; fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Helper: write a scv/SCV.md with a SCV:WORKSPACE block carrying given fields.
make_index() { # make_index <dir> <repo_id> <role> <root> <workspace>
  local dir="$1" rid="$2" role="$3" root="$4" ws="$5"
  mkdir -p "$dir"
  cat > "$dir/SCV.md" <<EOF
# scv/SCV.md

## SCV workspace (multi-repo nesting)

<!-- SCV:WORKSPACE START -->
<!-- comment line that must be ignored by the parser -->
\`\`\`yaml
repo_id: $rid
role: $role
root: $root
workspace: $ws
\`\`\`
<!-- SCV:WORKSPACE END -->
EOF
}

run_mode() { # run_mode <index-path> <manifest-path>
  WS_INDEX="$1" WS_MANIFEST="$2" bash -c '
    source "'"$LIB"'"
    echo "$(scv_resolve_mode)"
  '
}

run_field() { # run_field <index-path> <fn>
  WS_INDEX="$1" bash -c '
    source "'"$LIB"'"
    '"$2"'
  '
}

echo "── workspace.sh tests ──"

# 1. No SCV.md, no manifest → SINGLE
eq "no files → SINGLE" "SINGLE" "$(run_mode "$WORK/none/SCV.md" "$WORK/none/WORKSPACE.yaml")"

# 2. Empty workspace block → SINGLE (default hydrated repo)
make_index "$WORK/empty" "" "" "" ""
eq "empty block → SINGLE" "SINGLE" "$(run_mode "$WORK/empty/SCV.md" "$WORK/empty/WORKSPACE.yaml")"

# 3. Populated root → CHILD + readers correct
make_index "$WORK/child" "fe" "frontend" "/some/root/path" "acme"
eq "populated root → CHILD" "CHILD" "$(run_mode "$WORK/child/SCV.md" "$WORK/child/WORKSPACE.yaml")"
eq "scv_repo_id"   "fe"               "$(run_field "$WORK/child/SCV.md" 'scv_repo_id')"
eq "scv_role"      "frontend"         "$(run_field "$WORK/child/SCV.md" 'scv_role')"
eq "scv_root"      "/some/root/path"  "$(run_field "$WORK/child/SCV.md" 'scv_root')"
eq "scv_workspace" "acme"             "$(run_field "$WORK/child/SCV.md" 'scv_workspace')"

# 4. WORKSPACE.yaml present → ROOT (wins even with empty block)
make_index "$WORK/root" "" "" "" ""
touch "$WORK/root/WORKSPACE.yaml"
eq "manifest present → ROOT" "ROOT" "$(run_mode "$WORK/root/SCV.md" "$WORK/root/WORKSPACE.yaml")"

# 5. graceful degrade — root path exists → reachable; bogus path + no cache → not reachable
realroot="$WORK/realroot"; mkdir -p "$realroot"
make_index "$WORK/reach" "be" "backend" "$realroot" "acme"
WS_INDEX="$WORK/reach/SCV.md" bash -c 'source "'"$LIB"'"; scv_root_reachable' \
  && ok "existing root path → reachable" || fail "existing root path should be reachable"

make_index "$WORK/unreach" "be" "backend" "/no/such/dir/xyz" "acme-missing"
WS_INDEX="$WORK/unreach/SCV.md" SCV_CACHE_DIR="$WORK/emptycache" bash -c 'source "'"$LIB"'"; scv_root_reachable' \
  && fail "missing root path should NOT be reachable" || ok "missing root path → degrade (not reachable)"

# Still CHILD even when unreachable (mode = declaration, not reachability)
eq "unreachable still CHILD" "CHILD" "$(run_mode "$WORK/unreach/SCV.md" "$WORK/unreach/WORKSPACE.yaml")"

# 6. Detach — clear root → back to SINGLE (no migration)
make_index "$WORK/detach" "fe" "frontend" "" ""
eq "cleared root → SINGLE (detach)" "SINGLE" "$(run_mode "$WORK/detach/SCV.md" "$WORK/detach/WORKSPACE.yaml")"

# 7. ROOT workspace name falls back to WORKSPACE.yaml workspace_id (block empty)
make_index "$WORK/wsname" "" "" "" ""
printf 'workspace_id: acme-platform\nmembers:\n' > "$WORK/wsname/WORKSPACE.yaml"
WSN="$(WS_INDEX="$WORK/wsname/SCV.md" WS_MANIFEST="$WORK/wsname/WORKSPACE.yaml" bash -c 'source "'"$LIB"'"; scv_workspace')"
eq "ROOT workspace from manifest" "acme-platform" "$WSN"

echo ""
echo "── result: $PASS passed, $FAIL failed ──"
[[ "$FAIL" -eq 0 ]]
