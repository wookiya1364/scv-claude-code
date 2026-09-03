#!/usr/bin/env bash
# test-apply-model-policy.sh — apply-model-policy.sh --from-env, esp. the
# "SCV_MODEL_POLICY not set" graceful-skip path.
#
# Regression: apply-model-policy.sh runs under `set -euo pipefail`. The
# --from-env grep for `^SCV_MODEL_POLICY=` in .env exits 1 (no match) when the
# key is simply absent — a normal, expected case meant to be handled by the
# `[[ -z "$POLICY" ]]` check right after it. Under pipefail, that non-zero
# grep exit aborted the WHOLE script before that check ever ran, which in turn
# made the parent `sync.sh` (which pipes this script's output through `sed`)
# die too, right after printing "Model policy (from .env SCV_MODEL_POLICY):"
# with no further output — a real /scv:sync run on a project whose .env has
# no SCV_MODEL_POLICY line hit exactly this. Fixed with `|| true` on the pipe.
#
# Run: bash tests/test-apply-model-policy.sh
set -uo pipefail

REPO_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"
SCRIPT="$REPO_ROOT/scripts/apply-model-policy.sh"

PASS=0; FAIL=0
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "── apply-model-policy.sh --from-env tests ──"

# 1. No .env at all → graceful skip, exit 0
PROJ1="$WORK/proj-no-env"
mkdir -p "$PROJ1"
OUT1="$(SCV_PROJECT_DIR="$PROJ1" "$SCRIPT" --from-env 2>&1)"; RC1=$?
[[ $RC1 -eq 0 ]] && ok "no .env: exit 0" || fail "no .env: exit $RC1"
printf '%s' "$OUT1" | grep -q "no .env at" && ok "no .env: correct message" || { fail "no .env: wrong message"; echo "[$OUT1]"; }

# 2. .env present, no SCV_MODEL_POLICY= line at all (the reported crash) → graceful skip, exit 0
PROJ2="$WORK/proj-no-key"
mkdir -p "$PROJ2"
printf 'SOME_OTHER_VAR=1\n' > "$PROJ2/.env"
OUT2="$(SCV_PROJECT_DIR="$PROJ2" "$SCRIPT" --from-env 2>&1)"; RC2=$?
[[ $RC2 -eq 0 ]] && ok "no SCV_MODEL_POLICY key: exit 0 (regression: used to abort under set -e)" || { fail "no SCV_MODEL_POLICY key: exit $RC2"; echo "[$OUT2]"; }
printf '%s' "$OUT2" | grep -q "SCV_MODEL_POLICY not set" && ok "no SCV_MODEL_POLICY key: correct skip message" || { fail "no SCV_MODEL_POLICY key: wrong message"; echo "[$OUT2]"; }

# 3. .env present, SCV_MODEL_POLICY= set but empty → same graceful skip
PROJ3="$WORK/proj-empty-value"
mkdir -p "$PROJ3"
printf 'SCV_MODEL_POLICY=\n' > "$PROJ3/.env"
OUT3="$(SCV_PROJECT_DIR="$PROJ3" "$SCRIPT" --from-env 2>&1)"; RC3=$?
[[ $RC3 -eq 0 ]] && ok "empty SCV_MODEL_POLICY value: exit 0" || { fail "empty SCV_MODEL_POLICY value: exit $RC3"; echo "[$OUT3]"; }
printf '%s' "$OUT3" | grep -q "SCV_MODEL_POLICY not set" && ok "empty SCV_MODEL_POLICY value: correct skip message" || fail "empty SCV_MODEL_POLICY value: wrong message"

# 4. .env present, SCV_MODEL_POLICY=<invalid> → error exit 2, no crash-before-validation
PROJ4="$WORK/proj-invalid"
mkdir -p "$PROJ4"
printf 'SCV_MODEL_POLICY=not-a-real-policy\n' > "$PROJ4/.env"
OUT4="$(SCV_PROJECT_DIR="$PROJ4" "$SCRIPT" --from-env 2>&1)"; RC4=$?
[[ $RC4 -eq 2 ]] && ok "invalid policy value: exit 2" || { fail "invalid policy value: exit $RC4"; echo "[$OUT4]"; }
printf '%s' "$OUT4" | grep -qi "invalid policy" && ok "invalid policy value: correct error message" || fail "invalid policy value: wrong message"

# 5. Isolated scratch copy: SCV_MODEL_POLICY=all-opus actually applies (still works after the fix)
SCRATCH="$WORK/scratch-plugin"
mkdir -p "$SCRATCH/scripts" "$SCRATCH/commands"
cp "$SCRIPT" "$SCRATCH/scripts/apply-model-policy.sh"
cat > "$SCRATCH/commands/status.md" <<'EOF'
---
description: "test"
model: haiku
---
# /scv:status
EOF
PROJ5="$WORK/proj-valid"
mkdir -p "$PROJ5"
printf 'SCV_MODEL_POLICY=all-opus\n' > "$PROJ5/.env"
OUT5="$(SCV_PROJECT_DIR="$PROJ5" "$SCRATCH/scripts/apply-model-policy.sh" --from-env 2>&1)"; RC5=$?
[[ $RC5 -eq 0 ]] && ok "valid policy (all-opus): exit 0" || { fail "valid policy: exit $RC5"; echo "[$OUT5]"; }
grep -q "^model: opus" "$SCRATCH/commands/status.md" && ok "valid policy (all-opus): status.md updated to opus" || fail "valid policy: status.md not updated"

# 6. Settings file first: scv/scv_settings.json SCV_MODEL_POLICY=all-haiku, no .env → applies haiku
SCRATCH6="$WORK/scratch6"
mkdir -p "$SCRATCH6/scripts" "$SCRATCH6/commands"
cp "$SCRIPT" "$SCRATCH6/scripts/apply-model-policy.sh"
printf -- '---\ndescription: "test"\n---\n# /scv:help\n' > "$SCRATCH6/commands/help.md"
PROJ6="$WORK/proj-settings"
mkdir -p "$PROJ6/scv"
printf '{\n  "SCV_MODEL_POLICY": "all-haiku"\n}\n' > "$PROJ6/scv/scv_settings.json"
OUT6="$(SCV_PROJECT_DIR="$PROJ6" "$SCRATCH6/scripts/apply-model-policy.sh" --from-env 2>&1)"; RC6=$?
[[ $RC6 -eq 0 ]] && ok "settings file policy: exit 0" || { fail "settings file policy: exit $RC6"; echo "[$OUT6]"; }
grep -q "^model: haiku" "$SCRATCH6/commands/help.md" && ok "settings file policy (all-haiku): help.md gained haiku" || { fail "settings file policy: help.md not updated"; echo "[$OUT6]"; }

# 7. Settings file present WITHOUT the key, .env has it → legacy .env still honored
SCRATCH7="$WORK/scratch7"
mkdir -p "$SCRATCH7/scripts" "$SCRATCH7/commands"
cp "$SCRIPT" "$SCRATCH7/scripts/apply-model-policy.sh"
printf -- '---\ndescription: "test"\n---\n# /scv:status\n' > "$SCRATCH7/commands/status.md"
PROJ7="$WORK/proj-legacy-env"
mkdir -p "$PROJ7/scv"
printf '{\n  "SCV_LANG": "korean"\n}\n' > "$PROJ7/scv/scv_settings.json"
printf 'SCV_MODEL_POLICY=all-opus\n' > "$PROJ7/.env"
OUT7="$(SCV_PROJECT_DIR="$PROJ7" "$SCRATCH7/scripts/apply-model-policy.sh" --from-env 2>&1)"; RC7=$?
[[ $RC7 -eq 0 ]] && ok "legacy .env fallback: exit 0" || { fail "legacy .env fallback: exit $RC7"; echo "[$OUT7]"; }
grep -q "^model: opus" "$SCRATCH7/commands/status.md" && ok "legacy .env fallback (all-opus): status.md gained opus" || { fail "legacy .env fallback: status.md not updated"; echo "[$OUT7]"; }

# 8. Shipped default: the repository's commands/*.md carry no model: line
n_model="$(grep -l '^model: ' "$REPO_ROOT"/commands/*.md 2>/dev/null | wc -l | tr -d ' ')"
[[ "$n_model" == "0" ]] && ok "shipped default: no commands/*.md carries a model: line" || fail "shipped default: $n_model command file(s) still carry a model: line"

echo ""
echo "── result: $PASS passed, $FAIL failed ──"
[[ "$FAIL" -eq 0 ]]
