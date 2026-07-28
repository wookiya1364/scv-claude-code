#!/usr/bin/env bash
# Minimal YAML frontmatter parser (bash + awk only).
# Assumptions:
#   - Frontmatter is at the top of the file, delimited by --- lines
#   - Only flat key:value pairs (no nested mappings)
#   - List values support inline ([a, b]) and block (- item) form

yaml_extract() {
  # Prints frontmatter body (between --- lines) to stdout
  local file="$1"
  awk '
    BEGIN { in_fm = 0; started = 0 }
    /^---[[:space:]]*$/ {
      if (!started) { started = 1; in_fm = 1; next }
      else if (in_fm) { in_fm = 0; exit }
    }
    in_fm { print }
  ' "$file"
}

yaml_get() {
  # Usage: yaml_get <file> <key>
  # Prints scalar value (double-quotes stripped). Empty if not found.
  local file="$1" key="$2"
  yaml_extract "$file" | awk -v k="$key" '
    $1 == k":" {
      val = ""
      for (i=2; i<=NF; i++) val = val (i>2 ? " " : "") $i
      gsub(/^"/, "", val); gsub(/"$/, "", val)
      print val
      exit
    }
  '
}

yaml_get_list() {
  # Usage: yaml_get_list <file> <key>
  # Prints list items one per line. Supports inline and block form.
  local file="$1" key="$2"
  yaml_extract "$file" | awk -v k="$key" '
    BEGIN { in_block = 0 }
    {
      if (in_block) {
        if ($0 ~ /^[[:space:]]*-[[:space:]]+/) {
          sub(/^[[:space:]]*-[[:space:]]+/, "")
          gsub(/^"/, ""); gsub(/"$/, "")
          if ($0 != "") print
          next
        } else if ($0 ~ /^[^[:space:]-]/) {
          in_block = 0
        }
      }
      if ($1 == k":") {
        rest = ""
        for (i=2; i<=NF; i++) rest = rest (i>2 ? " " : "") $i
        if (rest ~ /^\[.*\]$/) {
          gsub(/^\[[[:space:]]*/, "", rest); gsub(/[[:space:]]*\]$/, "", rest)
          n = split(rest, arr, /[[:space:]]*,[[:space:]]*/)
          for (i=1; i<=n; i++) {
            v = arr[i]
            gsub(/^"/, "", v); gsub(/"$/, "", v)
            if (v != "") print v
          }
          in_block = 0
        } else if (rest == "") {
          in_block = 1
        }
      }
    }
  '
}

yaml_has_key() {
  # Returns 0 if key exists in frontmatter, 1 otherwise
  local file="$1" key="$2"
  yaml_extract "$file" | awk -v k="$key" '$1 == k":" { found=1; exit } END { exit !found }'
}
