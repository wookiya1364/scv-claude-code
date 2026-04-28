#!/usr/bin/env bash
# readpath.sh — track changes in scv/raw/ via scv/readpath.json
#
# Subcommands:
#   scan                 Print current raw state as JSON to stdout
#   diff                 Compare current raw state vs scv/readpath.json,
#                        output "A|M|R <path>..." lines (one per change)
#   update               Overwrite scv/readpath.json with current state
#   status-counts        Print "added=N modified=N removed=N total=N"
#                        (used by /scv:help banner for a cheap summary)
#
# Exit codes:
#   0 — success (no changes on diff, or other ops)
#   1 — usage / environment error
#   2 — diff detected changes (for scripting)
#
# Environment overrides:
#   RAW_DIR       default: scv/raw
#   STATE_FILE    default: scv/readpath.json

set -uo pipefail

RAW_DIR="${RAW_DIR:-scv/raw}"
STATE_FILE="${STATE_FILE:-scv/readpath.json}"

usage() {
  cat <<'EOF'
Usage: readpath.sh <subcommand>

Subcommands:
  scan               Print current raw state as JSON to stdout.
  diff               Compare current raw vs STATE_FILE (exit 2 on changes).
                     Output lines (tab-separated):
                       A\t<path>\t<size>\t<mtime>
                       M\t<path>\t<old_size>\t<new_size>\t<old_mtime>\t<new_mtime>
                       R\t<path>\t<old_size>\t<old_mtime>
  update             Overwrite STATE_FILE with current state.
  status-counts      Print "added=N modified=N removed=N total=N".

Env vars (override defaults):
  RAW_DIR      default: scv/raw
  STATE_FILE   default: scv/readpath.json
EOF
}

# ---------- helpers ----------

iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
file_size() { wc -c <"$1" 2>/dev/null | tr -d ' '; }
file_mtime_iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null; }

# Scan raw dir → TSV "path<tab>size<tab>mtime" lines (sorted by path)
scan_tsv() {
  local dir="$1"
  [[ ! -d "$dir" ]] && return 0
  while IFS= read -r f; do
    [[ "$f" == "$dir/README.md" ]] && continue
    local s m
    s=$(file_size "$f")
    m=$(file_mtime_iso "$f")
    printf '%s\t%s\t%s\n' "$f" "$s" "$m"
  done < <(find "$dir" -type f 2>/dev/null | LC_ALL=C sort)
}

# TSV on stdin → JSON on stdout
tsv_to_json() {
  local now="$1"
  printf '{\n  "version": 1,\n  "updated_at": "%s",\n  "files": {' "$now"
  local first=1
  while IFS=$'\t' read -r path size mtime; do
    [[ -z "$path" ]] && continue
    if [[ $first -eq 1 ]]; then
      first=0
      printf '\n'
    else
      printf ',\n'
    fi
    printf '    "%s": { "size": %s, "mtime": "%s" }' "$path" "$size" "$mtime"
  done
  if [[ $first -eq 0 ]]; then
    printf '\n  }\n}\n'
  else
    printf ' }\n}\n'
  fi
}

# Parse STATE_FILE → TSV on stdout (sorted by path)
state_to_tsv() {
  local f="${1:-$STATE_FILE}"
  [[ ! -f "$f" ]] && return 0
  # Match lines like:   "<path>": { "size": N, "mtime": "..." }
  grep -E '^ *"[^"]+": *\{ *"size":' "$f" 2>/dev/null | while IFS= read -r line; do
    local path size mtime rest
    # Extract path: leading whitespace + "path":
    path=${line#*\"}
    path=${path%%\"*}
    size=$(printf '%s' "$line" | sed -n 's/.*"size": *\([0-9]*\).*/\1/p')
    mtime=$(printf '%s' "$line" | sed -n 's/.*"mtime": *"\([^"]*\)".*/\1/p')
    printf '%s\t%s\t%s\n' "$path" "$size" "$mtime"
  done | LC_ALL=C sort
}

# Compute diff: current TSV file ($1) vs previous TSV file ($2)
# Emits A/M/R lines to stdout. Returns 0 if no changes, 2 if any.
compute_diff() {
  local cur="$1" prev="$2"
  local had_change=0

  declare -A cs cm ps pm
  while IFS=$'\t' read -r p s m; do
    [[ -z "$p" ]] && continue
    cs[$p]="$s"; cm[$p]="$m"
  done < "$cur"
  while IFS=$'\t' read -r p s m; do
    [[ -z "$p" ]] && continue
    ps[$p]="$s"; pm[$p]="$m"
  done < "$prev"

  local p
  for p in $(printf '%s\n' "${!cs[@]}" | LC_ALL=C sort); do
    if [[ -z "${ps[$p]+x}" ]]; then
      printf 'A\t%s\t%s\t%s\n' "$p" "${cs[$p]}" "${cm[$p]}"
      had_change=1
    elif [[ "${ps[$p]}" != "${cs[$p]}" ]] || [[ "${pm[$p]}" != "${cm[$p]}" ]]; then
      printf 'M\t%s\t%s\t%s\t%s\t%s\n' "$p" "${ps[$p]}" "${cs[$p]}" "${pm[$p]}" "${cm[$p]}"
      had_change=1
    fi
  done
  for p in $(printf '%s\n' "${!ps[@]}" | LC_ALL=C sort); do
    if [[ -z "${cs[$p]+x}" ]]; then
      printf 'R\t%s\t%s\t%s\n' "$p" "${ps[$p]}" "${pm[$p]}"
      had_change=1
    fi
  done

  return $(( had_change * 2 ))
}

# ---------- subcommands ----------

cmd_scan() {
  local t
  t=$(mktemp)
  scan_tsv "$RAW_DIR" > "$t"
  tsv_to_json "$(iso_now)" < "$t"
  rm -f "$t"
}

cmd_diff() {
  local cur prev
  cur=$(mktemp); prev=$(mktemp)
  scan_tsv "$RAW_DIR" > "$cur"
  state_to_tsv "$STATE_FILE" > "$prev"
  compute_diff "$cur" "$prev"
  local rc=$?
  rm -f "$cur" "$prev"
  return $rc
}

cmd_update() {
  local dir
  dir=$(dirname "$STATE_FILE")
  [[ -n "$dir" && ! -d "$dir" ]] && mkdir -p "$dir"
  local t
  t=$(mktemp)
  scan_tsv "$RAW_DIR" > "$t"
  tsv_to_json "$(iso_now)" < "$t" > "$STATE_FILE"
  rm -f "$t"
  echo "Updated: $STATE_FILE"
}

cmd_status_counts() {
  local cur prev
  cur=$(mktemp); prev=$(mktemp)
  scan_tsv "$RAW_DIR" > "$cur"
  state_to_tsv "$STATE_FILE" > "$prev"
  local diff_out
  diff_out=$(compute_diff "$cur" "$prev" || true)
  rm -f "$cur" "$prev"

  local a=0 m=0 r=0 total=0
  if [[ -n "$diff_out" ]]; then
    a=$(printf '%s\n' "$diff_out" | grep -c '^A	' || true)
    m=$(printf '%s\n' "$diff_out" | grep -c '^M	' || true)
    r=$(printf '%s\n' "$diff_out" | grep -c '^R	' || true)
  fi
  total=$((a + m + r))
  printf 'added=%d modified=%d removed=%d total=%d\n' "$a" "$m" "$r" "$total"
}

# ---------- main ----------

case "${1:-}" in
  scan)            cmd_scan ;;
  diff)            cmd_diff; exit $? ;;
  update)          cmd_update ;;
  status-counts)   cmd_status_counts ;;
  -h|--help|"")    usage; exit 0 ;;
  *) echo "Unknown subcommand: $1" >&2; usage >&2; exit 1 ;;
esac
