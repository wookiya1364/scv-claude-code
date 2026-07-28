#!/usr/bin/env bash
# test-workspace-monorepo.sh — the MACRO root/scv umbrella over MICRO module scvs
# inside ONE git repo (monorepo), the case the v0.13.0 multi-REPO workspace
# machinery did not cover.
#
# Layout under a single git repo REPO:
#   REPO/scv/         → umbrella (hydrate --root)      → ROOT
#   REPO/fe/scv/      → module child, joined `root: ..`→ CHILD
#   REPO/be/scv/      → module child, joined `root: ..`→ CHILD
#   REPO/solo/scv/    → not joined                     → SINGLE (byte-identical)
#
# Covers: CWD-driven macro/micro detection, portable relative `root: ..`
# resolution under BOTH the cd-into-module form and the module-arg form
# (/scv:status fe, /scv:handoff fe ...), in-repo handoff commit (no push), and
# the SINGLE byte-identical guard.
#
# Run: bash tests/test-workspace-monorepo.sh
set -uo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
LIB="$REPO_ROOT/scripts/lib/workspace.sh"
HYDRATE="$REPO_ROOT/scripts/hydrate.sh"
SYNC="$REPO_ROOT/scripts/sync.sh"
HANDOFF="$REPO_ROOT/scripts/handoff.sh"
STATUS="$REPO_ROOT/scripts/status.sh"

PASS=0; FAIL=0
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
eq()   { if [[ "$2" == "$3" ]]; then ok "$1"; else fail "$1 — expected [$2], got [$3]"; fi; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export SCV_CACHE_DIR="$WORK/cache"   # never touch the real ~/.cache

echo "── monorepo macro-root (single git repo, nested scv/) tests ──"

# --- one git repo containing an umbrella scv + module children ---------------
REPO="$WORK/monorepo"
mkdir -p "$REPO"
bash "$HYDRATE" init "$REPO" --root >/dev/null 2>&1          # REPO/scv = umbrella
bash "$HYDRATE" init "$REPO/fe"      >/dev/null 2>&1          # REPO/fe/scv
bash "$HYDRATE" init "$REPO/be"      >/dev/null 2>&1          # REPO/be/scv
bash "$HYDRATE" init "$REPO/solo"    >/dev/null 2>&1          # REPO/solo/scv (single)
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t.t
git -C "$REPO" config user.name "Mono Dev"

# Join the modules to the in-repo umbrella with the PORTABLE relative root (`..`
# is the module dir's parent = REPO, the parent of the umbrella scv/).
bash "$SYNC" --project-dir "$REPO/fe" --join ".." --id fe --role frontend --workspace acme >/dev/null 2>&1
bash "$SYNC" --project-dir "$REPO/be" --join ".." --id be --role backend  --workspace acme >/dev/null 2>&1

git -C "$REPO" add -A >/dev/null 2>&1
git -C "$REPO" commit -qm "init monorepo" >/dev/null 2>&1

# helper: resolve scv_root_path from <cwd> for module <scvdir> and print the
# absolute directory it points at (robust to relative vs absolute return).
resolve_root_from() { # <cwd> <scv_dir_relative_to_cwd>
  ( cd "$1" && SCV_DIR="$2" WS_INDEX="$2/SCV.md" WS_MANIFEST="$2/WORKSPACE.yaml" \
      bash -c 'source "'"$LIB"'"; p="$(scv_root_path)" || exit 1; cd "$p" && pwd' )
}
mode_from() { # <cwd> <scv_dir>
  ( cd "$1" && SCV_DIR="$2" WS_INDEX="$2/SCV.md" WS_MANIFEST="$2/WORKSPACE.yaml" \
      bash -c 'source "'"$LIB"'"; scv_resolve_mode' )
}

REPO_ABS="$( cd "$REPO" && pwd )"
REPO_PHYS="$( cd "$REPO" && pwd -P )"

# 1. macro/micro detection by CWD (already expected to work)
eq "cd REPO → ROOT (macro umbrella)"  "ROOT"  "$(mode_from "$REPO" "scv")"
eq "cd REPO/fe → CHILD (micro)"       "CHILD" "$(mode_from "$REPO/fe" "scv")"
eq "cd REPO/solo → SINGLE"            "SINGLE" "$(mode_from "$REPO/solo" "scv")"

# 2. relative root resolves to REPO from INSIDE the module (cd form)
eq "cd fe: relative root .. → REPO" "$REPO_ABS" "$(resolve_root_from "$REPO/fe" "scv")"

# 3. relative root resolves to REPO via the MODULE-ARG form (cwd = repo root,
#    SCV_DIR = fe/scv). This is the gap: `..` must anchor to the module dir, not CWD.
eq "module-arg: fe/scv root .. → REPO (not CWD parent)" "$REPO_PHYS" "$(resolve_root_from "$REPO" "fe/scv")"

# 3b. module reached via a symlink whose LOGICAL parent differs from the real
#     module's parent: the relative root must dereference the symlink (physical)
#     so arg-form resolves to the REAL umbrella, not the symlink's logical parent.
mkdir -p "$REPO/other"
ln -s "$REPO/fe" "$REPO/other/felink"
eq "symlinked module (arg-form) → real umbrella (physical, not symlink logical parent)" \
  "$REPO_PHYS" "$(resolve_root_from "$REPO" "other/felink/scv")"

# 4. handoff from INSIDE the module writes into the in-repo umbrella + 1 commit, no push
before=$(git -C "$REPO" rev-list --count HEAD)
HOUT="$( cd "$REPO/fe" && bash "$HANDOFF" write --to be --slug refund-api --title "BE: POST /api/refunds" 2>&1 )"; HRC=$?
[[ $HRC -eq 0 ]] && ok "cd fe: handoff write succeeds" || { fail "handoff write rc=$HRC"; echo "[$HOUT]"; }
HID="$(printf '%s\n' "$HOUT" | sed -n 's/^HANDOFF_ID: //p')"
[[ -n "$HID" && -f "$REPO/scv/handoffs/raw/HANDOFF-$HID.md" ]] \
  && ok "handoff landed in REPO/scv/handoffs/raw" || fail "handoff file not in umbrella"
after=$(git -C "$REPO" rev-list --count HEAD)
eq "exactly one umbrella commit (no push)" "$((before + 1))" "$after"

# 5. MODULE-ARG handoff parity: from the repo root, `handoff fe write ...` must
#    target fe's umbrella the same way (gap: handoff has no module arg today).
HOUT2="$( cd "$REPO" && bash "$HANDOFF" fe write --to be --slug audit-log --title "BE: audit log" 2>&1 )"; HRC2=$?
[[ $HRC2 -eq 0 ]] && ok "module-arg: 'handoff fe write' succeeds" || { fail "handoff fe write rc=$HRC2"; echo "[$HOUT2]"; }
HID2="$(printf '%s\n' "$HOUT2" | sed -n 's/^HANDOFF_ID: //p')"
[[ -n "$HID2" && -f "$REPO/scv/handoffs/raw/HANDOFF-$HID2.md" ]] \
  && ok "module-arg handoff landed in umbrella" || fail "module-arg handoff file not in umbrella"

# 5c. module-arg targeting an UMBRELLA (ROOT mode via a relative module target):
#     both list and mark must operate on the same scv (regression: cmd_mark once
#     used $(pwd) and diverged from cmd_list for this exact invocation).
MLIST="$( cd "$REPO/fe" && bash "$HANDOFF" .. list 2>/dev/null )"
printf '%s' "$MLIST" | grep -q "^$HID|" && ok "module-arg '.. list' finds the umbrella handoff" || { fail "'.. list' missing $HID"; echo "[$MLIST]"; }
MOUT="$( cd "$REPO/fe" && bash "$HANDOFF" .. mark "$HID" done 2>&1 )"; MRC=$?
[[ $MRC -eq 0 ]] && ok "module-arg '.. mark' succeeds (ROOT target)" || { fail "'.. mark' rc=$MRC"; echo "[$MOUT]"; }
grep -q "^status: done" "$REPO/scv/handoffs/raw/HANDOFF-$HID.md" && ok "umbrella handoff marked done" || fail "handoff status not updated"

# 6. macro coordination view: status from the umbrella surfaces the handoffs
SOUT="$( cd "$REPO" && bash "$STATUS" 2>/dev/null )"
printf '%s' "$SOUT" | grep -qi "workspace" && ok "umbrella status shows workspace section" || fail "no workspace section in ROOT status"

# 7. byte-identical guard: SINGLE module handoff is a no-op, no [7] section
SGL="$( cd "$REPO/solo" && bash "$HANDOFF" write --to be --slug x --title y 2>&1 )"; SGLRC=$?
[[ $SGLRC -eq 0 ]] && printf '%s' "$SGL" | grep -qi "single-repo" \
  && ok "SINGLE module: handoff write is a no-op" || { fail "SINGLE handoff not a no-op (rc=$SGLRC)"; echo "[$SGL]"; }

echo ""
echo "── result: $PASS passed, $FAIL failed ──"
[[ "$FAIL" -eq 0 ]]
