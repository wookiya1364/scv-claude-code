#!/usr/bin/env bash
# Marker-based block merge utilities.
#
# Marker format:
#   <!-- NAME START [optional suffix] -->
#   ...content...
#   <!-- NAME END -->
#
# The functions use substring matching, so start_pattern can include any
# identifying suffix to disambiguate multiple blocks in the same file.

replace_marker_block() {
  # Usage: replace_marker_block <file> <start_pattern> <end_pattern> <new_content>
  # Replaces content between first line matching start_pattern and first
  # subsequent line matching end_pattern. Preserves the marker lines themselves.
  # Returns 0 on success, 1 if start marker not found.
  local file="$1" start_pat="$2" end_pat="$3" content="$4"
  local tmp; tmp=$(mktemp)
  awk -v start="$start_pat" -v end="$end_pat" -v c="$content" '
    BEGIN { in_block = 0; found = 0 }
    {
      if (!in_block && index($0, start) > 0) {
        print $0
        print c
        in_block = 1
        found = 1
        next
      }
      if (in_block && index($0, end) > 0) {
        print $0
        in_block = 0
        next
      }
      if (!in_block) print $0
    }
    END { exit (found ? 0 : 1) }
  ' "$file" > "$tmp"
  local rc=$?
  if [[ $rc -eq 0 ]]; then
    mv "$tmp" "$file"
    return 0
  else
    rm -f "$tmp"
    return 1
  fi
}

extract_marker_block() {
  # Usage: extract_marker_block <file> <start_pattern> <end_pattern>
  # Prints content between marker lines (excluding markers).
  local file="$1" start_pat="$2" end_pat="$3"
  awk -v start="$start_pat" -v end="$end_pat" '
    BEGIN { in_block = 0 }
    {
      if (!in_block && index($0, start) > 0) { in_block = 1; next }
      if (in_block && index($0, end) > 0) { in_block = 0; next }
      if (in_block) print
    }
  ' "$file"
}

has_marker_block() {
  # Usage: has_marker_block <file> <start_pattern>
  local file="$1" start_pat="$2"
  grep -qF "$start_pat" "$file" 2>/dev/null
}

extract_simple_marker() {
  # Usage: extract_simple_marker <file> <open_tag> <close_tag>
  # Prints value between <!-- OPEN -->VALUE<!-- CLOSE --> on a single line.
  # Prints empty if not found.
  local file="$1" open="$2" close="$3"
  awk -v o="$open" -v cl="$close" '
    {
      oi = index($0, o)
      if (oi > 0) {
        rem = substr($0, oi + length(o))
        ci = index(rem, cl)
        if (ci > 0) {
          print substr(rem, 1, ci - 1)
          exit
        }
      }
    }
  ' "$file"
}

replace_simple_marker() {
  # Usage: replace_simple_marker <file> <open_tag> <close_tag> <new_value>
  # Replaces content between <!-- OPEN -->VALUE<!-- CLOSE --> on a single line.
  local file="$1" open="$2" close="$3" value="$4"
  # Use Python-like escape via awk to avoid sed regex collision with dashes/slashes
  local tmp; tmp=$(mktemp)
  awk -v o="$open" -v cl="$close" -v v="$value" '
    {
      line = $0
      oi = index(line, o)
      if (oi > 0) {
        ci = index(substr(line, oi + length(o)), cl)
        if (ci > 0) {
          pre = substr(line, 1, oi + length(o) - 1)
          post = substr(line, oi + length(o) + ci - 1)
          print pre v post
          next
        }
      }
      print line
    }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}
