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
#   --mark KIND    mark this turn as meaningful: plan | blocker | pivot.
#                  (decision entries index themselves — see scripts/decisions-append.sh.)
#                  Its byte position is recorded in scv/INDEX.tsv so it can
#                  be read back without scanning the journal. Unknown kinds are
#                  ignored — the journal write itself never fails on this.
#   --key NAME     the name you will look it up by (defaults to the mark kind).
#                  The newest record for a key wins.
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
MARK=""
KEY=""
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
    --mark)
      [[ $# -ge 2 && -n "${2:-}" ]] || { echo "✖ --mark requires KIND" >&2; exit 2; }
      MARK="$2"; shift 2 ;;
    --key)
      [[ $# -ge 2 && -n "${2:-}" ]] || { echo "✖ --key requires NAME" >&2; exit 2; }
      KEY="$2"; shift 2 ;;
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

# 쓰기 직전 크기가 이 항목의 시작 위치다. 재고 나서 쓴다 — 순서가 바뀌면
# 오프셋이 한 항목만큼 어긋난다.
OFFSET_BEFORE=0
[[ -f "$FILE" ]] && OFFSET_BEFORE="$(wc -c < "$FILE" 2>/dev/null | tr -d '[:space:]')"
[[ "$OFFSET_BEFORE" =~ ^[0-9]+$ ]] || OFFSET_BEFORE=0

{
  printf '\n### [%s] %s\n\n' "$NOW" "$SPEAKER"
  printf '%s\n' "$REDACTED_TEXT"
} >> "$FILE"

# 표시가 붙었으면 위치를 색인에 적는다.
#
# 색인은 편의지 필수가 아니다 — 여기서 무엇이 잘못돼도 저널 기록은 이미 끝났고
# 이 스크립트는 성공으로 끝난다.
if [[ -n "$MARK" ]]; then
  _idx_lib="$SCRIPT_DIR/lib/record-index.sh"
  if [[ -f "$_idx_lib" ]]; then
    # shellcheck source=lib/record-index.sh
    source "$_idx_lib" 2>/dev/null || true
  fi
  if declare -F record_index_entry >/dev/null 2>&1; then
    OFFSET_AFTER="$(wc -c < "$FILE" 2>/dev/null | tr -d '[:space:]')"
    if [[ "$OFFSET_AFTER" =~ ^[0-9]+$ ]] && (( OFFSET_AFTER > OFFSET_BEFORE )); then
      LENGTH=$(( OFFSET_AFTER - OFFSET_BEFORE ))
      # 요약은 본문 첫 줄. 이미 redaction 을 거친 텍스트에서 뽑는다 —
      # 원문에서 뽑으면 비밀값이 색인으로 샌다.
      SUMMARY="$(printf '%s' "$REDACTED_TEXT" | head -n 1 | cut -c1-120)"
      RECORD="$(record_index_entry "$MARK" "${KEY:-$MARK}" "$FILE" \
                  "$OFFSET_BEFORE" "$LENGTH" "$NOW" "$SUMMARY")"
      if [[ -n "$RECORD" ]]; then
        INDEX_FILE="${SCV_DIR:-scv}/INDEX.tsv"
        if [[ ! -L "$INDEX_FILE" ]]; then
          # $(...) 가 끝 줄바꿈을 지우므로 여기서 다시 붙인다. 안 붙이면 레코드가
          # 이어붙어 색인 전체를 못 읽는다.
          printf '%s\n' "$RECORD" >> "$INDEX_FILE" 2>/dev/null || true
          echo "JOURNAL_MARK: ${MARK} key=${KEY:-$MARK} at ${OFFSET_BEFORE}+${LENGTH}"
        fi
      else
        echo "scv: unknown journal mark [$MARK] — the turn was journaled, but not indexed." >&2
      fi
    fi
  fi
fi

echo "JOURNAL_FILE: $FILE"
