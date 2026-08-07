#!/usr/bin/env bash
# bash 4+ required (author slugging). macOS ships 3.2 — auto-escalate to brew bash.
if (( BASH_VERSINFO[0] < 4 )); then
  for _b in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    [[ -x "$_b" ]] && exec "$_b" "$0" "$@"
  done
  echo "Error: SCV requires bash 4+. Install via 'brew install bash'." >&2
  exit 1
fi

# journal-append.sh — append one turn to the committed team journal (v0.22.0+).
#
# Writes to scv/journal/<YYYYMMDD>-<author>.md as a `### [HH:MM:SS] <speaker>`
# block. Per-day, PER-AUTHOR files: two people journaling on the same day write
# two different files, so concurrent multi-user work can never git-conflict on
# the journal.
#
# REDACTION IS BUILT IN — nothing is written without passing the filter:
#   password/passwd/pwd/secret/token/api[_-]?key = or : <value>  → [REDACTED]
#   Bearer <token>                                               → Bearer [REDACTED]
#   AKIA<AWS-access-key-id>                                      → [REDACTED]
# The filter is a heuristic: secrets outside these patterns can still leak.
# The "no secrets in committed files" rule (scv/journal/README.md, same as
# scv/raw/) applies on top of it.
#
# Usage:
#   journal-append.sh [--speaker NAME] [--author NAME] [--redact-only] [TEXT...]
#
#   TEXT...        turn content; when absent, stdin is read instead.
#   --speaker      block attribution inside the file (default: user).
#   --author       file attribution override; default resolves via
#                  lib/author.sh (git config user.name → GIT_AUTHOR_NAME →
#                  USER → unknown), slugged for the filename.
#   --redact-only  print the redacted text to stdout and exit WITHOUT writing
#                  any file. Used by protocols (e.g. /scv:help conversation
#                  persistence) that write their own files but must route the
#                  content through this same redaction filter first.
#
# Env:
#   SCV_JOURNAL_DIR   target dir (default: scv/journal, relative to cwd).
#
# Output (append mode): "JOURNAL_FILE: <path>" on success.
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/author.sh
source "$SCRIPT_DIR/lib/author.sh"

SPEAKER="user"
AUTHOR=""
REDACT_ONLY=0
TEXT_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --speaker)
      [[ $# -ge 2 && -n "${2:-}" ]] || { echo "✖ --speaker requires NAME" >&2; exit 2; }
      SPEAKER="$2"; shift 2 ;;
    --author)
      [[ $# -ge 2 && -n "${2:-}" ]] || { echo "✖ --author requires NAME" >&2; exit 2; }
      AUTHOR="$2"; shift 2 ;;
    --redact-only) REDACT_ONLY=1; shift ;;
    -h|--help) sed -n '12,40p' "$0"; exit 0 ;;
    --) shift; TEXT_ARGS+=("$@"); break ;;
    *) TEXT_ARGS+=("$1"); shift ;;
  esac
done

# Redaction filter. Case-insensitive via per-char bracket classes (portable
# across GNU and BSD sed — no GNU-only s///I flag). Hardened after adversarial
# review: sensitive keys match with optional quotes around the key AND the
# value ("password": "x", 'pwd': x), URL userinfo (scheme://user:pw@host) is
# masked, Authorization/X-Api-Key headers are masked, and a line consisting of
# only a sensitive key + separator redacts the FOLLOWING line (multiline
# key:\nvalue form) via awk carry-over. Heuristic by contract — secrets outside
# these shapes can still slip through; never paste raw credentials.
scv_redact() {
  local KEYS='([Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Pp][Aa][Ss][Ss][Ww][Dd]|[Pp][Ww][Dd]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Tt][Oo][Kk][Ee][Nn]|[Aa][Pp][Ii][_-]?[Kk][Ee][Yy]|[Aa][Cc][Cc][Ee][Ss][Ss][_-]?[Tt][Oo][Kk][Ee][Nn])'
  sed -E \
    -e 's/((["'\'']?)'"$KEYS"'(["'\'']?)[[:space:]]*[=:][[:space:]]*)["'\'']?[^"'\''[:space:]]+["'\'']?/\1[REDACTED]/g' \
    -e 's/[Bb][Ee][Aa][Rr][Ee][Rr][[:space:]]+[A-Za-z0-9._~+\/=-]+/Bearer [REDACTED]/g' \
    -e 's/([Aa][Uu][Tt][Hh][Oo][Rr][Ii][Zz][Aa][Tt][Ii][Oo][Nn](["'\'']?)[[:space:]]*:[[:space:]]*)[^[:space:]].*/\1[REDACTED]/' \
    -e 's/([Xx]-[Aa][Pp][Ii]-[Kk][Ee][Yy](["'\'']?)[[:space:]]*:?[[:space:]]+)[^[:space:]]+/\1[REDACTED]/g' \
    -e 's|(://)[^/@[:space:]]+@|\1[REDACTED]@|g' \
    -e 's/AKIA[A-Z0-9]{8,}/[REDACTED]/g' \
  | awk -v keys='^[[:space:]]*["'\'']?([Pp][Aa][Ss][Ss][Ww][Oo][Rr][Dd]|[Pp][Aa][Ss][Ss][Ww][Dd]|[Pp][Ww][Dd]|[Ss][Ee][Cc][Rr][Ee][Tt]|[Tt][Oo][Kk][Ee][Nn]|[Aa][Pp][Ii][_-]?[Kk][Ee][Yy]|[Aa][Cc][Cc][Ee][Ss][Ss][_-]?[Tt][Oo][Kk][Ee][Nn])["'\'']?[[:space:]]*[=:][[:space:]]*$' '
      pending && $0 !~ /^[[:space:]]*$/ { print "[REDACTED]"; pending = 0; next }
      { print }
      $0 ~ keys { pending = 1 }
    '
}

# Gather input: args win; else stdin.
if [[ ${#TEXT_ARGS[@]} -gt 0 ]]; then
  RAW_TEXT="${TEXT_ARGS[*]}"
else
  RAW_TEXT="$(cat)"
fi

REDACTED_TEXT="$(printf '%s\n' "$RAW_TEXT" | scv_redact)"

if [[ $REDACT_ONLY -eq 1 ]]; then
  printf '%s\n' "$REDACTED_TEXT"
  exit 0
fi

if [[ -z "${RAW_TEXT//[[:space:]]/}" ]]; then
  echo "✖ nothing to append (empty input)" >&2
  exit 1
fi

[[ -n "$AUTHOR" ]] || AUTHOR="$(scv_author)"
AUTHOR="$(scv_author_slug "$AUTHOR")"

# The speaker label is caller-controlled text that lands in the heading —
# it passes the same redaction filter as the body.
SPEAKER="$(printf '%s\n' "$SPEAKER" | scv_redact)"

JOURNAL_DIR="${SCV_JOURNAL_DIR:-scv/journal}"
if [[ -L "$JOURNAL_DIR" ]]; then
  echo "✖ $JOURNAL_DIR is a symlink — refusing to write through it (fail-closed)" >&2
  exit 1
fi
mkdir -p "$JOURNAL_DIR"

DAY="$(date +%Y%m%d)"
TODAY="$(date +%Y-%m-%d)"
NOW="$(date +%H:%M:%S)"
FILE="$JOURNAL_DIR/${DAY}-${AUTHOR}.md"

if [[ ! -f "$FILE" ]]; then
  {
    printf '# Journal — %s — %s\n' "$TODAY" "$AUTHOR"
    printf '\n'
    printf '> append-only · via journal-append.sh (redaction built in) · see scv/journal/README.md\n'
  } > "$FILE"
fi

{
  printf '\n### [%s] %s\n\n' "$NOW" "$SPEAKER"
  printf '%s\n' "$REDACTED_TEXT"
} >> "$FILE"

echo "JOURNAL_FILE: $FILE"
