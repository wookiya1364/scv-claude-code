#!/usr/bin/env bash
# test-scvroot.sh — regression tests for lib/scvroot.sh (multi-scv resolution)
# and the readpath/status/promote wiring that depends on it.
#
# Covers the monorepo model: micro scv per module (FE/scv, BE/scv, AI/scv) plus
# a macro umbrella scv at the repo root. Resolution precedence under test:
#   explicit target arg  >  CWD/scv  >  walk-up  >  SCV_DIR (fallback)  >  default
set -uo pipefail

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPTS="$HERE/../scripts"
LIB="$SCRIPTS/lib/scvroot.sh"

pass=0; fail=0
ck() {  # desc expected actual
  if [[ "$2" == "$3" ]]; then pass=$((pass+1)); # echo "  ✓ $1";
  else echo "  ✗ $1 — expected [$2] got [$3]"; fail=$((fail+1)); fi
}
ok() {  # desc cmd... (expect exit 0)
  if "${@:2}" >/dev/null 2>&1; then pass=$((pass+1)); else echo "  ✗ $1 (expected success)"; fail=$((fail+1)); fi
}
no() {  # desc cmd... (expect non-zero)
  if "${@:2}" >/dev/null 2>&1; then echo "  ✗ $1 (expected failure)"; fail=$((fail+1)); else pass=$((pass+1)); fi
}

BASE=$(mktemp -d)
trap 'rm -rf "$BASE"' EXIT

# ---- scv_target_path ----
mkdir -p "$BASE/mono/FE/scv/raw"
( source "$LIB"; cd "$BASE/mono"
  scv_target_path FE     ) > "$BASE/o1" 2>/dev/null; ck "target 'FE' → FE/scv"      "FE/scv" "$(cat "$BASE/o1")"
( source "$LIB"; cd "$BASE/mono"; scv_target_path FE/scv ) > "$BASE/o2" 2>/dev/null; ck "target 'FE/scv' → FE/scv"  "FE/scv" "$(cat "$BASE/o2")"
ok "target trailing slash ok"  bash -c "cd '$BASE/mono'; source '$LIB'; scv_target_path FE/"
no "target 'nope' fails"       bash -c "cd '$BASE/mono'; source '$LIB'; scv_target_path nope"
no "target '' fails"           bash -c "cd '$BASE/mono'; source '$LIB'; scv_target_path ''"

# ---- scv_root_dir precedence ----
mkdir -p "$BASE/single/scv/raw"
ck "CWD/scv → scv (standalone)"          "scv"           "$(cd "$BASE/single"; source "$LIB"; scv_root_dir)"
mkdir -p "$BASE/single/deep/nested"
ck "walk-up from subdir → parent scv"    "$BASE/single/scv" "$(cd "$BASE/single/deep/nested"; source "$LIB"; scv_root_dir)"
# SCV_DIR DEMOTED: CWD/scv must win over an explicit SCV_DIR
ck "CWD/scv beats SCV_DIR (demotion)"    "scv"           "$(cd "$BASE/single"; source "$LIB"; SCV_DIR="$BASE/mono/FE/scv" scv_root_dir)"
# SCV_DIR fallback: only used when nothing else resolves
mkdir -p "$BASE/empty"
ck "SCV_DIR fallback when no CWD/walk-up" "$BASE/mono/FE/scv" "$(cd "$BASE/empty"; source "$LIB"; SCV_DIR="$BASE/mono/FE/scv" scv_root_dir)"
ck "no scv anywhere → default scv"       "scv"           "$(cd "$BASE/empty"; source "$LIB"; unset SCV_DIR; scv_root_dir)"

# ---- scv_init_paths ----
ck "init: target FE → RAW_DIR"           "FE/scv/raw"        "$(cd "$BASE/mono"; source "$LIB"; scv_init_paths FE; echo "$RAW_DIR")"
ck "init: target FE → STATE_FILE"        "FE/scv/readpath.json" "$(cd "$BASE/mono"; source "$LIB"; scv_init_paths FE; echo "$STATE_FILE")"
ck "init: no-arg standalone byte-ident"  "scv/raw"           "$(cd "$BASE/single"; source "$LIB"; scv_init_paths; echo "$RAW_DIR")"
ck "init: env RAW_DIR override wins"      "/custom"           "$(cd "$BASE/single"; source "$LIB"; RAW_DIR=/custom scv_init_paths; echo "$RAW_DIR")"

# ---- multi-scv model: macro (root) vs micro (FE), addressed by context/arg ----
mkdir -p "$BASE/full/scv/raw" "$BASE/full/FE/scv/raw" "$BASE/full/BE/scv/raw"
ck "macro: root CWD → root scv"          "scv"        "$(cd "$BASE/full"; source "$LIB"; scv_root_dir)"
ck "micro: arg FE from root → FE/scv"    "FE/scv"     "$(cd "$BASE/full"; source "$LIB"; scv_init_paths FE; echo "$SCV_DIR")"
ck "micro: arg BE from root → BE/scv"    "BE/scv"     "$(cd "$BASE/full"; source "$LIB"; scv_init_paths BE; echo "$SCV_DIR")"
ck "micro: CWD FE → FE/scv (no arg)"     "scv"        "$(cd "$BASE/full/FE"; source "$LIB"; scv_root_dir)"

# ---- integration: readpath / status write into the right nested scv ----
# A root session (only FE/scv present) operates on the macro root scv and must
# NOT reach into FE's micro scv. (It may lazily create root/scv — that's fine.)
mkdir -p "$BASE/it/FE/scv/raw"; printf 'notes' > "$BASE/it/FE/scv/raw/mtg.txt"
( cd "$BASE/it"; bash "$SCRIPTS/readpath.sh" update >/dev/null 2>&1 )
ck "root session does NOT write into FE/scv" "" "$(ls "$BASE/it/FE/scv/readpath.json" 2>/dev/null || true)"
# Running from the FE module context writes FE/scv/readpath.json.
( cd "$BASE/it/FE"; bash "$SCRIPTS/readpath.sh" update >/dev/null 2>&1 )
ok "readpath @FE writes FE/scv/readpath.json" test -f "$BASE/it/FE/scv/readpath.json"

mkdir -p "$BASE/it2/FE/scv/raw" "$BASE/it2/FE/scv/promote"; printf 'x' > "$BASE/it2/FE/scv/raw/n.txt"
( cd "$BASE/it2"; git init -q 2>/dev/null; git config user.name t; git config user.email t@t
  bash "$SCRIPTS/status.sh" FE --ack >/dev/null 2>&1 )   # positional target from root
ok "status FE --ack writes FE/scv/readpath.json" test -f "$BASE/it2/FE/scv/readpath.json"
ck "status FE: no wrong root scv/"        ""  "$(ls "$BASE/it2/scv" 2>/dev/null || true)"

# ---- review fix: scv_target_path normalizes "." → "scv" (no ./ diff churn) ----
ck "target '.' → scv (normalized)"  "scv"     "$(cd "$BASE/single"; source "$LIB"; scv_target_path .)"
ck "init '.' → scv/raw (no ./)"     "scv/raw" "$(cd "$BASE/single"; source "$LIB"; scv_init_paths .; echo "$RAW_DIR")"

# ---- review fix: promote-helper reads the RESOLVED module's CLAUDE.md ----
mkdir -p "$BASE/ph/scv/raw" "$BASE/ph/FE/scv/raw"
printf '<!-- STANDARD:VERSION -->1.0.0-ROOT<!-- /STANDARD:VERSION -->\n' > "$BASE/ph/scv/CLAUDE.md"
printf '<!-- STANDARD:VERSION -->9.9.9-FE<!-- /STANDARD:VERSION -->\n'   > "$BASE/ph/FE/scv/CLAUDE.md"
ver_fe=$(cd "$BASE/ph"; bash "$SCRIPTS/promote-helper.sh" FE --dry-run 2>/dev/null | sed -n 's/^STANDARD_VERSION: //p')
ck "promote FE → FE module version"        "9.9.9-FE"   "$ver_fe"
ver_root=$(cd "$BASE/ph"; bash "$SCRIPTS/promote-helper.sh" --dry-run 2>/dev/null | sed -n 's/^STANDARD_VERSION: //p')
ck "promote @root CWD → root version"      "1.0.0-ROOT" "$ver_root"

# ---- review fix: --topic value must NOT be swallowed as a module target ----
ver_topic=$(cd "$BASE/ph"; bash "$SCRIPTS/promote-helper.sh" --topic FE --dry-run 2>/dev/null | sed -n 's/^STANDARD_VERSION: //p')
ck "--topic FE not hijacked → root version" "1.0.0-ROOT" "$ver_topic"

# ---- follow-up: work.sh (+ codegen via delegation) accepts a leading module target ----
mkdir -p "$BASE/wk/FE/scv/promote/20260101-x-demo" "$BASE/wk/scv/promote/20260101-x-demo"
for d in "$BASE/wk/FE/scv/promote/20260101-x-demo" "$BASE/wk/scv/promote/20260101-x-demo"; do
  printf '# plan\n' > "$d/PLAN.md"; printf '# tests\n' > "$d/TESTS.md"
done
td_fe=$(cd "$BASE/wk"; bash "$SCRIPTS/work.sh" FE 20260101-x-demo 2>/dev/null | sed -n 's/^TARGET_DIR: //p')
ck "work FE <slug> → FE/scv/promote"           "FE/scv/promote/20260101-x-demo" "$td_fe"
sl_fe=$(cd "$BASE/wk"; bash "$SCRIPTS/work.sh" FE 20260101-x-demo 2>/dev/null | sed -n 's/^TARGET_SLUG: //p')
ck "work FE <slug> → slug not swallowed"        "20260101-x-demo" "$sl_fe"
td_root=$(cd "$BASE/wk"; bash "$SCRIPTS/work.sh" 20260101-x-demo 2>/dev/null | sed -n 's/^TARGET_DIR: //p')
ck "work <slug> (no module) → root scv/promote"  "scv/promote/20260101-x-demo" "$td_root"

echo ""
echo "── test-scvroot: $pass passed, $fail failed ──"
exit $(( fail > 0 ? 1 : 0 ))
