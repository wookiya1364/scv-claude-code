#!/usr/bin/env bash
# Set (or clear) one KEY=VALUE in the project-root .env, preserving every other line.
#
# Why a script instead of an Edit instruction: the protocols used to tell the agent
# to create-or-append .env by hand, and one of those instructions ran BEFORE the
# protocol's first helper call — so on a host where the receipt is minted by a
# script invocation, the very first interaction in a project had no receipt yet and
# the write was denied. Routing every sanctioned .env write through a named script
# closes that ordering hole and keeps `.env` itself out of the guard's exempt list,
# where it does not belong: a user's .env is arbitrary content worth watching.
#
# Portability: no `sed -i` (BSD and GNU disagree on its argument), no in-place
# rewrite of the original inode — write a sibling temp file and mv it over.
# Values are never re-quoted or expanded: whatever is passed lands verbatim, so a
# secret containing `$` or spaces survives a round trip.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  env-set.sh KEY=VALUE [--project-dir PATH]   set or replace one key
  env-set.sh --unset KEY [--project-dir PATH] remove the key entirely
  env-set.sh --get KEY [--project-dir PATH]   print the current value (empty if unset)

The file is created when absent. Unrelated lines, comments, and blank lines are
preserved byte for byte, and the key keeps its original position when replaced.
USAGE
}

PROJECT_DIR="."
MODE="set"
PAIR=""
KEY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir)
      [[ $# -ge 2 ]] || { echo "env-set.sh: --project-dir needs a path" >&2; exit 2; }
      PROJECT_DIR="$2"; shift 2 ;;
    --unset)
      [[ $# -ge 2 ]] || { echo "env-set.sh: --unset needs a KEY" >&2; exit 2; }
      MODE="unset"; KEY="$2"; shift 2 ;;
    --get)
      [[ $# -ge 2 ]] || { echo "env-set.sh: --get needs a KEY" >&2; exit 2; }
      MODE="get"; KEY="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) echo "env-set.sh: unknown flag: $1" >&2; exit 2 ;;
    *)
      [[ -z "$PAIR" ]] || { echo "env-set.sh: unexpected argument: $1" >&2; exit 2; }
      PAIR="$1"; shift ;;
  esac
done

if [[ "$MODE" == "set" ]]; then
  [[ -n "$PAIR" ]] || { usage >&2; exit 2; }
  [[ "$PAIR" == *=* ]] || { echo "env-set.sh: expected KEY=VALUE, got: $PAIR" >&2; exit 2; }
  KEY="${PAIR%%=*}"
fi

# A key must be a plain shell-safe identifier. This is also what keeps the key out
# of the awk pattern below as anything but a literal.
[[ "$KEY" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || {
  echo "env-set.sh: invalid key: $KEY" >&2; exit 2
}

[[ -d "$PROJECT_DIR" ]] || { echo "env-set.sh: no such directory: $PROJECT_DIR" >&2; exit 2; }
ENV_FILE="$PROJECT_DIR/.env"

if [[ "$MODE" == "get" ]]; then
  [[ -f "$ENV_FILE" ]] || exit 0
  # First assignment wins, matching how `source` would leave the variable.
  awk -v k="$KEY" '
    index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }
  ' "$ENV_FILE"
  exit 0
fi

if [[ ! -f "$ENV_FILE" ]]; then
  if [[ "$MODE" == "unset" ]]; then
    exit 0
  fi
  printf '%s\n' "$PAIR" > "$ENV_FILE"
  echo "ENV_SET: $KEY (created ${ENV_FILE#./})"
  exit 0
fi

TMP="$(mktemp "${ENV_FILE}.XXXXXX")"
# The temp file sits next to the target so the mv stays on one filesystem, and it
# is removed on any failure path rather than left as litter beside a user's .env.
trap 'rm -f "$TMP"' EXIT

# awk, not sed: the replacement value is passed as a variable, so it is never
# parsed as a regex or as a replacement template. A value containing `&`, `/`, or
# a backslash would otherwise be rewritten.
if [[ "$MODE" == "unset" ]]; then
  awk -v k="$KEY" 'index($0, k "=") != 1' "$ENV_FILE" > "$TMP"
  ACTION="removed"
else
  awk -v k="$KEY" -v pair="$PAIR" '
    index($0, k "=") == 1 && !done { print pair; done = 1; next }
    { print }
    END { if (!done) print pair }
  ' "$ENV_FILE" > "$TMP"
  ACTION="set"
fi

# Preserve the original mode — a .env is frequently chmod 600 and must not widen.
if command -v chmod >/dev/null 2>&1; then
  chmod --reference="$ENV_FILE" "$TMP" 2>/dev/null \
    || chmod "$(stat -f '%Lp' "$ENV_FILE" 2>/dev/null || echo 600)" "$TMP" 2>/dev/null \
    || true
fi

mv "$TMP" "$ENV_FILE"
trap - EXIT

echo "ENV_SET: $KEY ($ACTION)"
