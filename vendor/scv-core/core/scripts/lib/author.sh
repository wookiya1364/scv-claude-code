# lib/author.sh — single source of truth for author attribution (v0.22.0+).
#
# Every journal / DECISIONS / TODO record is author-attributed (anonymous
# entries are forbidden by the journal invariants), so author resolution must
# be identical everywhere. Resolution order:
#
#   1. git config user.name          (repo-local wins over global, as git does)
#   2. $GIT_AUTHOR_NAME              (env fallback — CI / hooks without config)
#   3. $USER                         (OS login name)
#   4. "unknown"                     (last resort — never an empty author)
#
# scv_author_slug turns the resolved name into a filename-safe slug:
# lowercased, whitespace → dash, ASCII punctuation → dash, dashes squeezed and
# trimmed. Non-ASCII characters (e.g. Korean names) are KEPT as-is — they are
# valid filename characters and stripping them would collapse distinct authors
# into "unknown".
#
# Usage:  source lib/author.sh; AUTHOR="$(scv_author)"

scv_author_raw() {
  local name=""
  if command -v git >/dev/null 2>&1; then
    name="$(git config user.name 2>/dev/null || true)"
  fi
  if [[ -z "$name" ]]; then
    name="${GIT_AUTHOR_NAME:-}"
  fi
  if [[ -z "$name" ]]; then
    name="${USER:-}"
  fi
  if [[ -z "$name" ]]; then
    name="unknown"
  fi
  printf '%s\n' "$name"
}

scv_author_slug() {
  local in="${1:-}" out="" ch i
  in="${in,,}"   # lowercase (ASCII; multibyte chars pass through unchanged)
  for (( i = 0; i < ${#in}; i++ )); do
    ch="${in:i:1}"
    case "$ch" in
      [a-z0-9._-]) out+="$ch" ;;
      *)
        # Any other ASCII char (space, /, :, quotes, control chars, ...) is
        # unsafe or ambiguous in a filename → dash. Non-ASCII (한글 etc.) kept.
        if [[ "$ch" == [[:ascii:]] ]]; then
          out+="-"
        else
          out+="$ch"
        fi
        ;;
    esac
  done
  while [[ "$out" == *--* ]]; do out="${out//--/-}"; done
  out="${out#-}"
  out="${out%-}"
  [[ -n "$out" ]] || out="unknown"
  printf '%s\n' "$out"
}

# Resolved + slugged author, ready for filenames and record attribution.
scv_author() {
  scv_author_slug "$(scv_author_raw)"
}
