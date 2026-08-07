#!/usr/bin/env bash
# guidance-filter.sh — SCV guidance-ablation injection filter (v0.22.0+).
#
# Protocol markdown separates deterministic CONTRACT text from behavioral
# GUIDANCE coaching with HTML-comment markers:
#
#   <!-- SCV:GUIDANCE -->
#   ...coaching lines (safe to omit from the injected prompt)...
#   <!-- /SCV:GUIDANCE -->
#
# Classification rule (docs/guidance-ablation.md): if deleting a block does
# NOT change the produced artifacts' shape, paths, or invariants (generated
# file list, frontmatter schema, script call sequence), it is GUIDANCE.
# Everything else is CONTRACT and must stay outside the markers.
#
# Modes (from --mode, else $SCV_GUIDANCE, default full):
#   full     — emit the protocol byte-identical (markers included; they are
#              HTML comments, invisible in every markdown render).
#   minimal  — emit the protocol with every GUIDANCE block (markers + body)
#              removed. The protocol FILE itself is never modified unless
#              --in-place is passed on a materialized (wrapper-owned) copy.
#
# Fail-closed: EVERY invocation validates the markers of EVERY input file
# before producing any output or rewriting any file. An unpaired, nested, or
# malformed marker aborts with a clear file:line error, stdout stays empty,
# and no file is rewritten — a partial injection is never produced.
#
# Usage:
#   guidance-filter.sh [--mode full|minimal] FILE          # filtered → stdout
#   guidance-filter.sh [--mode full|minimal] --in-place FILE...
#   guidance-filter.sh --lint FILE...                      # validate + stats
set -uo pipefail

OPEN_MARKER='<!-- SCV:GUIDANCE -->'
CLOSE_MARKER='<!-- /SCV:GUIDANCE -->'

usage() {
  echo "Usage: guidance-filter.sh [--mode full|minimal] [--in-place|--lint] FILE..." >&2
}

MODE="${SCV_GUIDANCE:-full}"
ACTION="stdout"   # stdout | in-place | lint
FILES=()
while (( $# )); do
  case "$1" in
    --mode)     MODE="${2:-}"; shift 2 ;;
    --mode=*)   MODE="${1#*=}"; shift ;;
    --in-place) ACTION="in-place"; shift ;;
    --lint)     ACTION="lint"; shift ;;
    -h|--help)  usage; exit 0 ;;
    -*)         echo "guidance-filter: unknown flag: $1" >&2; usage; exit 2 ;;
    *)          FILES+=("$1"); shift ;;
  esac
done

if [[ "$ACTION" != "lint" && "$MODE" != "full" && "$MODE" != "minimal" ]]; then
  echo "guidance-filter: invalid SCV_GUIDANCE mode: '$MODE' (expected full|minimal)" >&2
  exit 2
fi
[[ ${#FILES[@]} -gt 0 ]] || { usage; exit 2; }
if [[ "$ACTION" == "stdout" && ${#FILES[@]} -ne 1 ]]; then
  echo "guidance-filter: stdout mode takes exactly one FILE (use --in-place for many)" >&2
  exit 2
fi
for f in "${FILES[@]}"; do
  [[ -f "$f" ]] || { echo "guidance-filter: file not found: $f" >&2; exit 2; }
done

# Validate one file's markers. Prints "<guidance_lines> <total_lines>" on
# success (marker lines excluded from both counts); a clear error to stderr
# and exit 3 on any unpaired / nested / malformed marker.
lint_file() {
  local file="$1"
  # Case-mismatched marker variants would silently survive the filter (and leak
  # into deck renders) — reject them outright instead of ignoring them.
  local bad_case
  bad_case="$(grep -inE '<!--[ \t]*/?[ \t]*scv:guidance[ \t]*-->' "$file" | grep -v 'SCV:GUIDANCE' | head -3 || true)"
  if [[ -n "$bad_case" ]]; then
    printf '✖ %s: case-mismatched SCV:GUIDANCE marker (markers are case-sensitive):\n%s\n' \
      "$file" "$bad_case" >&2
    return 1
  fi
  awk -v open="$OPEN_MARKER" -v close_m="$CLOSE_MARKER" -v fname="$file" '
    {
      line = $0
      gsub(/^[ \t]+/, "", line); gsub(/[ \t]+$/, "", line)
      if (index($0, "SCV:GUIDANCE") > 0) {
        if (line == open) {
          if (depth == 1) {
            printf "guidance-filter: %s:%d: nested SCV:GUIDANCE open marker (block opened at line %d is still open)\n", fname, NR, open_line > "/dev/stderr"
            bad = 1; exit 3
          }
          depth = 1; open_line = NR
        } else if (line == close_m) {
          if (depth == 0) {
            printf "guidance-filter: %s:%d: SCV:GUIDANCE close marker without a matching open marker\n", fname, NR > "/dev/stderr"
            bad = 1; exit 3
          }
          depth = 0
        } else {
          printf "guidance-filter: %s:%d: malformed SCV:GUIDANCE marker line (must be exactly the open or close marker): %s\n", fname, NR, $0 > "/dev/stderr"
          bad = 1; exit 3
        }
      } else {
        total++
        if (depth == 1) guidance++
      }
    }
    END {
      if (bad) exit 3
      if (depth == 1) {
        printf "guidance-filter: %s:%d: SCV:GUIDANCE block opened at line %d is never closed\n", fname, open_line, open_line > "/dev/stderr"
        exit 3
      }
      printf "%d %d\n", guidance + 0, total + 0
    }
  ' "$file"
}

# Emit the file filtered per MODE to stdout (validation must already be done).
filter_file() {
  local file="$1"
  if [[ "$MODE" == "full" ]]; then
    cat "$file"
    return 0
  fi
  # Buffered emit so a source file WITHOUT a trailing newline is reproduced
  # byte-exactly (streaming print would append one — content outside the
  # markers must never be altered).
  local noeol=0
  [[ -n "$(tail -c 1 "$file")" ]] && noeol=1
  awk -v open="$OPEN_MARKER" -v close_m="$CLOSE_MARKER" -v noeol="$noeol" '
    {
      line = $0
      gsub(/^[ \t]+/, "", line); gsub(/[ \t]+$/, "", line)
      if (line == open)    { skip = 1; next }
      if (line == close_m) { skip = 0; next }
      if (!skip) { kept[++n] = $0 }
    }
    END {
      for (i = 1; i <= n; i++) {
        if (i < n || !noeol) print kept[i]
        else printf "%s", kept[i]
      }
    }
  ' "$file"
}

# Pass 1 — validate ALL files before any output / rewrite (fail-closed).
STATS=()
for f in "${FILES[@]}"; do
  if ! stat_line="$(lint_file "$f")"; then
    exit 3
  fi
  STATS+=("$stat_line")
done

# Pass 2 — act.
case "$ACTION" in
  lint)
    i=0
    for f in "${FILES[@]}"; do
      g="${STATS[$i]% *}"
      t="${STATS[$i]#* }"
      ratio=$(awk -v g="$g" -v t="$t" 'BEGIN { if (t > 0) printf "%.1f", g * 100 / t; else printf "0.0" }')
      echo "GUIDANCE_LINT: OK file=$f guidance_lines=$g total_lines=$t ratio=${ratio}%"
      i=$((i + 1))
    done
    ;;
  stdout)
    filter_file "${FILES[0]}"
    ;;
  in-place)
    # full mode keeps every file byte-identical — validation only.
    if [[ "$MODE" == "minimal" ]]; then
      for f in "${FILES[@]}"; do
        tmp="$(mktemp "${f}.guidance.XXXXXX")"
        if ! filter_file "$f" > "$tmp"; then
          rm -f "$tmp"
          echo "guidance-filter: failed to filter: $f" >&2
          exit 1
        fi
        mv "$tmp" "$f"
      done
    fi
    ;;
esac
exit 0
