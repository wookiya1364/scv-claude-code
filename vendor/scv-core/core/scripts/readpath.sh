#!/usr/bin/env bash
# bash 4+ required (associative arrays). macOS ships 3.2 — auto-escalate to brew bash.
if (( BASH_VERSINFO[0] < 4 )); then
  for _b in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    [[ -x "$_b" ]] && exec "$_b" "$0" "$@"
  done
  echo "Error: SCV requires bash 4+. Install via 'brew install bash'." >&2
  exit 1
fi

# readpath.sh — track the scv/raw/ lifecycle via scv/readpath.json
#
# State schema v2: alongside the per-file {size, mtime} snapshot ("files"),
# a "ref_docs" object records consumption provenance — for each doc moved to
# scv/raw/stale/ it stores which promote slugs used it ("slugs", accumulated
# across features), the git HEAD at consumption ("ref_commit"), when
# ("consumed_at"), and the pre-move path ("origin", used to remap a shared
# source that another promote folder already moved). v1 state files (no
# ref_docs) remain readable. v1 readers ignore the ref_docs block; NOTE that a
# v1 `update` rewrites the file without ref_docs — mixed-version teams should
# upgrade wrappers together.
#
# Lifecycle rule: a doc directly under scv/raw/ (outside stale/) has never
# been consumed by a promote. `consume` moves docs into scv/raw/stale/
# (content unchanged) and records provenance; docs are never deleted.
#
# Filenames: paths containing double quotes, backslashes, tabs, or newlines
# cannot be represented in the narrow no-jq state schema — `scan`/`diff` skip
# them with a stderr warning and `consume` rejects them (fail-closed).
#
# Subcommands:
#   scan                 Print current raw state as JSON to stdout (files only)
#   diff                 Compare current raw state vs scv/readpath.json,
#                        output "A|M|R <path>..." lines (one per change)
#   update               Rewrite scv/readpath.json from the current raw state.
#                        Preserves existing ref_docs entries.
#   status-counts        Print "added=N modified=N removed=N total=N"
#                        (used by /scv:help banner for a cheap summary)
#   consume <slug> <path>...
#                        Record that the raw docs at <path>... were consumed by
#                        promote folder <slug>: move each (content unchanged)
#                        under scv/raw/stale/, append <slug> to its ref_docs
#                        slugs (a doc reused by several features accumulates
#                        all their slugs), stamp ref_commit/consumed_at/origin,
#                        and rewrite the snapshot. Paths already under stale/
#                        are not moved — the slug is appended. A path that no
#                        longer exists but matches a recorded `origin` (another
#                        folder in the same promote already moved it) is
#                        remapped to its stale/ entry — no error.
#                        Output lines (tab-separated):
#                          MOVED\t<old>\t<new>
#                          KEPT\t<path>            (already under stale/)
#                          REMAPPED\t<old>\t<new>  (moved earlier; slug appended)
#                          REF\t<path>\t<slug,slug,...>
#   unused               List raw docs never consumed: files under scv/raw/
#                        excluding scv/raw/stale/, README.md, .gitkeep.
#   refs [<path>]        Print ref_docs provenance as TSV (5 columns,
#                        empty values shown as "-"):
#                        <path>\t<slug,slug>\t<ref_commit>\t<consumed_at>\t<origin>
#   lifecycle-counts     Print "unused=N stale=N"
#   outdated             Heuristic content-staleness check for consumed docs.
#                        For each ref_docs entry, compares ref_commit..HEAD and
#                        flags docs that mention repo files changed since
#                        consumption. Output lines (tab-separated):
#                          OUTDATED-CANDIDATE\t<path>\t<changed files it mentions>
#                          AGING\t<path>\t<N> commits behind
#                          FRESH\t<path>
#                          UNKNOWN\t<path>\t<reason>
#                        This is a hint only — semantic verification against
#                        the current code is Claude Code's job.
#
# Exit codes:
#   0 — success (no changes on diff, no outdated candidates, or other ops)
#   1 — usage / environment error
#   2 — diff detected changes / outdated found candidates (for scripting)
#
# Environment overrides:
#   RAW_DIR                default: scv/raw
#   STATE_FILE             default: scv/readpath.json
#   SCV_RAW_AGING_COMMITS  default: 30 (outdated: AGING threshold)
#
# Monorepo note: like every readpath caller, a nested module is addressed via
# the env overrides — e.g. `RAW_DIR=FE/scv/raw STATE_FILE=FE/scv/readpath.json
# readpath.sh consume …` from the repo root (promote.md Step 8 documents this).

set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/env.sh
source "$SCRIPT_DIR/lib/env.sh"
# shellcheck source=lib/scvroot.sh
source "$SCRIPT_DIR/lib/scvroot.sh"
env_load 2>/dev/null || true

# Resolve the scv/ location (monorepo-nested aware) → derive RAW_DIR/STATE_FILE.
# An explicit RAW_DIR/STATE_FILE passed by a caller still wins (env-override).
# This is what lets a bare `readpath.sh update` (promote Step 8) write to a
# nested scv/ (e.g. FE/scv) instead of silently targeting a nonexistent root scv/.
scv_init_paths

usage() {
  cat <<'EOF'
Usage: readpath.sh <subcommand>

Subcommands:
  scan               Print current raw state as JSON to stdout (files only).
  diff               Compare current raw vs STATE_FILE (exit 2 on changes).
                     Output lines (tab-separated):
                       A\t<path>\t<size>\t<mtime>
                       M\t<path>\t<old_size>\t<new_size>\t<old_mtime>\t<new_mtime>
                       R\t<path>\t<old_size>\t<old_mtime>
  update             Rewrite STATE_FILE from current state (keeps ref_docs).
  status-counts      Print "added=N modified=N removed=N total=N".
  consume <slug> <path>...
                     Move consumed docs under RAW_DIR/stale/ and append <slug>
                     to their ref_docs provenance (accumulates across features).
  unused             List docs never consumed (under RAW_DIR, outside stale/).
  refs [<path>]      Print ref_docs provenance TSV: path, slugs, commit,
                     consumed_at, origin ("-" for empty values).
  lifecycle-counts   Print "unused=N stale=N".
  outdated           Flag consumed docs that mention files changed since their
                     ref_commit (exit 2 when any OUTDATED-CANDIDATE).

Env vars (override defaults):
  RAW_DIR                default: scv/raw
  STATE_FILE             default: scv/readpath.json
  SCV_RAW_AGING_COMMITS  default: 30
EOF
}

# ---------- helpers ----------

iso_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
file_size() { wc -c <"$1" 2>/dev/null | tr -d ' '; }
file_mtime_iso() { date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null; }

# Collapse "//" and "/./", strip leading "./" and trailing "/" — so path
# variants of the same file cannot create duplicate provenance entries.
normalize_rel_path() {
  local p="$1"
  p="${p#./}"
  while [[ "$p" == *"//"* ]]; do p="${p//\/\//\/}"; done
  while [[ "$p" == *"/./"* ]]; do p="${p//\/.\///}"; done
  p="${p%/}"
  printf '%s' "$p"
}

# Filenames the narrow no-jq state schema cannot represent safely.
is_unsafe_name() {
  local p="$1"
  [[ "$p" == *'"'* || "$p" == *'\'* || "$p" == *$'\t'* || "$p" == *$'\n'* ]]
}

# Fail-closed: refuse when any existing component of the path is a symlink
# (a symlinked subdir under raw/ or stale/ would redirect the move outside
# the tree). Non-existent components cannot be symlinks and are fine.
assert_no_symlink_components() {
  local path="$1" label="$2" cur="" part
  local -a parts=()
  IFS=/ read -ra parts <<< "$path"
  for part in "${parts[@]}"; do
    [[ -z "$part" ]] && continue
    cur="${cur:+$cur/}$part"
    if [[ -L "$cur" ]]; then
      echo "consume: refusing symlinked path component in $label: $cur" >&2
      exit 1
    fi
  done
}

# Scan raw dir → TSV "path<tab>size<tab>mtime" lines (sorted by path)
scan_tsv() {
  local dir="$1"
  [[ ! -d "$dir" ]] && return 0
  while IFS= read -r f; do
    [[ "$f" == "$dir/README.md" ]] && continue
    [[ "${f##*/}" == ".gitkeep" ]] && continue
    if is_unsafe_name "$f"; then
      echo "readpath: skipping unsafe filename (quote/backslash/control char): $f" >&2
      continue
    fi
    local s m
    s=$(file_size "$f")
    m=$(file_mtime_iso "$f")
    # File vanished (or stat failed) mid-scan — skip rather than emit a
    # malformed row.
    [[ -z "$s" || -z "$m" ]] && continue
    printf '%s\t%s\t%s\n' "$f" "$s" "$m"
  done < <(find "$dir" -type f 2>/dev/null | LC_ALL=C sort)
}

# TSV on stdin → JSON on stdout (files-only preview; `scan` output)
tsv_to_json() {
  local now="$1"
  printf '{\n  "version": 2,\n  "updated_at": "%s",\n  "files": {' "$now"
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

# Parse STATE_FILE "files" entries → TSV on stdout (sorted by path)
state_to_tsv() {
  local f="${1:-$STATE_FILE}"
  [[ ! -f "$f" ]] && return 0
  # Parse both the compact writer format and legacy pretty-printed JSON where
  # size/mtime occupy separate lines. This deliberately handles the narrow,
  # versioned readpath schema without requiring jq or network dependencies.
  # ref_docs entries never carry size/mtime, so they are naturally skipped.
  awk '
    function quoted_key(line, out) {
      out = line
      sub(/^[[:space:]]*"/, "", out)
      sub(/".*$/, "", out)
      return out
    }
    function maybe_emit() {
      if (path != "" && size != "" && mtime != "") {
        printf "%s\t%s\t%s\n", path, size, mtime
        path = ""; size = ""; mtime = ""
      }
    }
    /^[[:space:]]*"[^"]+"[[:space:]]*:[[:space:]]*\{/ {
      key = quoted_key($0)
      if (key != "files") {
        maybe_emit()
        path = key
        size = ""; mtime = ""
      }
    }
    path != "" && /"size"[[:space:]]*:[[:space:]]*[0-9]+/ {
      value = $0
      sub(/^.*"size"[[:space:]]*:[[:space:]]*/, "", value)
      sub(/[^0-9].*$/, "", value)
      size = value
    }
    path != "" && /"mtime"[[:space:]]*:[[:space:]]*"[^"]*"/ {
      value = $0
      sub(/^.*"mtime"[[:space:]]*:[[:space:]]*"/, "", value)
      sub(/".*$/, "", value)
      mtime = value
    }
    { maybe_emit() }
    END { maybe_emit() }
  ' "$f" | LC_ALL=C sort
}

# Parse STATE_FILE "ref_docs" entries → TSV on stdout (sorted by path):
#   <path>\t<slugs>\t<ref_commit>\t<consumed_at>\t<origin>
# Empty values are emitted as "-" so consecutive tabs never collapse under
# IFS-whitespace field splitting (readers translate "-" back to empty).
# Handles both the compact one-line writer format and pretty-printed variants
# (e.g. after `jq .`) via brace-depth tracking, including multi-line slugs
# arrays — mirroring state_to_tsv's tolerance for reformatted state files.
refdocs_to_tsv() {
  local f="${1:-$STATE_FILE}"
  [[ ! -f "$f" ]] && return 0
  awk '
    function quoted_key(line, out) {
      out = line
      sub(/^[[:space:]]*"/, "", out)
      sub(/".*$/, "", out)
      return out
    }
    function count_ch(str, ch,   n, i) {
      n = 0
      for (i = 1; i <= length(str); i++) if (substr(str, i, 1) == ch) n++
      return n
    }
    function collect_slugs(str,   tmp, tok) {
      if (index(str, "]") > 0) {
        str = substr(str, 1, index(str, "]") - 1)
        inslugs = 0
      }
      tmp = str
      while (match(tmp, /"[^"]*"/)) {
        tok = substr(tmp, RSTART + 1, RLENGTH - 2)
        if (tok != "") slugs = (slugs == "" ? tok : slugs "," tok)
        tmp = substr(tmp, RSTART + RLENGTH)
      }
    }
    function grab_str(line, key,   s) {
      if (match(line, "\"" key "\"[[:space:]]*:[[:space:]]*\"[^\"]*\"")) {
        s = substr(line, RSTART, RLENGTH)
        sub(/^.*:[[:space:]]*"/, "", s)
        sub(/"$/, "", s)
        return s
      }
      return "\001"
    }
    function fields_from(line,   v) {
      v = grab_str(line, "ref_commit");  if (v != "\001") commit = v
      v = grab_str(line, "consumed_at"); if (v != "\001") at = v
      v = grab_str(line, "origin");      if (v != "\001") origin = v
      if (match(line, /"slugs"[[:space:]]*:[[:space:]]*\[/)) {
        slugs = ""
        inslugs = 1
        collect_slugs(substr(line, RSTART + RLENGTH))
      } else if (inslugs) {
        collect_slugs(line)
      }
    }
    function emit() {
      if (path != "") {
        printf "%s\t%s\t%s\t%s\t%s\n", path, \
          (slugs == "" ? "-" : slugs), (commit == "" ? "-" : commit), \
          (at == "" ? "-" : at), (origin == "" ? "-" : origin)
      }
      path = ""; slugs = ""; commit = ""; at = ""; origin = ""; inslugs = 0
    }
    !inref && /"ref_docs"[[:space:]]*:[[:space:]]*\{/ {
      inref = 1
      depth = 1
      rest = $0
      sub(/^.*"ref_docs"[[:space:]]*:[[:space:]]*\{/, "", rest)
      depth += count_ch(rest, "{") - count_ch(rest, "}")
      if (depth <= 0) inref = 0
      next
    }
    inref {
      if (depth == 1 && $0 ~ /^[[:space:]]*"[^"]+"[[:space:]]*:[[:space:]]*\{/) {
        emit()
        path = quoted_key($0)
      }
      if (path != "") fields_from($0)
      depth += count_ch($0, "{") - count_ch($0, "}")
      if (depth <= 1 && path != "" && index($0, "}") > 0) emit()
      if (depth <= 0) { emit(); inref = 0 }
      next
    }
    END { emit() }
  ' "$f" | LC_ALL=C sort
}

# Translate the TSV "-" placeholder back to an empty value.
unplaceholder() { [[ "$1" == "-" ]] && printf '' || printf '%s' "$1"; }

# Load ref_docs entries from STATE_FILE into the RD_* globals.
load_refdocs() {
  declare -gA RD_SLUGS=() RD_COMMIT=() RD_AT=() RD_ORIGIN=()
  local f="${1:-$STATE_FILE}"
  [[ -f "$f" ]] || return 0
  local p slugs cmt at origin
  while IFS=$'\t' read -r p slugs cmt at origin; do
    [[ -z "$p" ]] && continue
    RD_SLUGS[$p]="$(unplaceholder "${slugs:-}")"
    RD_COMMIT[$p]="$(unplaceholder "${cmt:-}")"
    RD_AT[$p]="$(unplaceholder "${at:-}")"
    RD_ORIGIN[$p]="$(unplaceholder "${origin:-}")"
  done < <(refdocs_to_tsv "$f")
}

# Rewrite STATE_FILE: fresh files snapshot + ref_docs from the RD_* globals.
# Callers must load_refdocs (and optionally merge) first. ref_docs entries are
# provenance and are kept even if the underlying file was removed by hand.
write_state() {
  local dir
  dir=$(dirname "$STATE_FILE")
  [[ -n "$dir" && ! -d "$dir" ]] && mkdir -p "$dir"
  local t
  t=$(mktemp)
  scan_tsv "$RAW_DIR" > "$t"
  local now
  now=$(iso_now)
  {
    printf '{\n  "version": 2,\n  "updated_at": "%s",\n  "files": {' "$now"
    local first=1 path size mtime
    while IFS=$'\t' read -r path size mtime; do
      [[ -z "$path" ]] && continue
      if [[ $first -eq 1 ]]; then first=0; printf '\n'; else printf ',\n'; fi
      printf '    "%s": { "size": %s, "mtime": "%s" }' "$path" "$size" "$mtime"
    done < "$t"
    if [[ $first -eq 0 ]]; then printf '\n  },\n'; else printf ' },\n'; fi
    printf '  "ref_docs": {'
    first=1
    local p s slugs_json
    while IFS= read -r p; do
      [[ -z "$p" ]] && continue
      if [[ $first -eq 1 ]]; then first=0; printf '\n'; else printf ',\n'; fi
      slugs_json=""
      if [[ -n "${RD_SLUGS[$p]:-}" ]]; then
        local -a _sl=()
        IFS=',' read -ra _sl <<< "${RD_SLUGS[$p]}"
        for s in "${_sl[@]}"; do
          [[ -z "$s" ]] && continue
          [[ -n "$slugs_json" ]] && slugs_json+=", "
          slugs_json+="\"$s\""
        done
      fi
      printf '    "%s": { "slugs": [%s], "ref_commit": "%s", "consumed_at": "%s", "origin": "%s" }' \
        "$p" "$slugs_json" "${RD_COMMIT[$p]:-}" "${RD_AT[$p]:-}" "${RD_ORIGIN[$p]:-}"
    done < <(printf '%s\n' "${!RD_SLUGS[@]}" | LC_ALL=C sort)
    if [[ $first -eq 0 ]]; then printf '\n  }\n}\n'; else printf ' }\n}\n'; fi
  } > "$STATE_FILE"
  rm -f "$t"
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

  # while-read (not for-in-$()) so paths with spaces survive word splitting.
  local p
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    if [[ -z "${ps[$p]+x}" ]]; then
      printf 'A\t%s\t%s\t%s\n' "$p" "${cs[$p]}" "${cm[$p]}"
      had_change=1
    elif [[ "${ps[$p]}" != "${cs[$p]}" ]] || [[ "${pm[$p]}" != "${cm[$p]}" ]]; then
      printf 'M\t%s\t%s\t%s\t%s\t%s\n' "$p" "${ps[$p]}" "${cs[$p]}" "${pm[$p]}" "${cm[$p]}"
      had_change=1
    fi
  done < <(printf '%s\n' "${!cs[@]}" | LC_ALL=C sort)
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    if [[ -z "${cs[$p]+x}" ]]; then
      printf 'R\t%s\t%s\t%s\n' "$p" "${ps[$p]}" "${pm[$p]}"
      had_change=1
    fi
  done < <(printf '%s\n' "${!ps[@]}" | LC_ALL=C sort)

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
  load_refdocs "$STATE_FILE"
  write_state
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

cmd_unused() {
  [[ -d "$RAW_DIR" ]] || return 0
  local f
  while IFS= read -r f; do
    [[ "$f" == "$RAW_DIR/README.md" ]] && continue
    [[ "${f##*/}" == ".gitkeep" ]] && continue
    [[ "$f" == "$RAW_DIR/stale/"* ]] && continue
    printf '%s\n' "$f"
  done < <(find "$RAW_DIR" -type f 2>/dev/null | LC_ALL=C sort)
}

cmd_refs() {
  local want="${1:-}"
  [[ -n "$want" ]] && want="$(normalize_rel_path "$want")"
  local p slugs cmt at origin
  while IFS=$'\t' read -r p slugs cmt at origin; do
    [[ -z "$p" ]] && continue
    [[ -n "$want" && "$p" != "$want" ]] && continue
    printf '%s\t%s\t%s\t%s\t%s\n' "$p" "${slugs:--}" "${cmt:--}" "${at:--}" "${origin:--}"
  done < <(refdocs_to_tsv "$STATE_FILE")
  return 0
}

cmd_lifecycle_counts() {
  local unused stale
  unused=$(cmd_unused | grep -c . || true)
  stale=0
  if [[ -d "$RAW_DIR/stale" ]]; then
    stale=$(find "$RAW_DIR/stale" -type f ! -name .gitkeep 2>/dev/null | grep -c . || true)
  fi
  printf 'unused=%d stale=%d\n' "$unused" "$stale"
}

cmd_consume() {
  local slug="${1:-}"
  [[ -n "$slug" ]] || { echo "consume: missing <slug>" >&2; exit 1; }
  [[ "$slug" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || {
    echo "consume: invalid slug '$slug' (allowed: alnum plus . _ -)" >&2; exit 1
  }
  shift
  [[ $# -ge 1 ]] || { echo "consume: need at least one <path>" >&2; exit 1; }
  [[ -d "$RAW_DIR" ]] || { echo "consume: raw dir not found: $RAW_DIR" >&2; exit 1; }

  local stale_prefix="$RAW_DIR/stale"

  # Provenance is needed during preflight (origin remap for shared sources).
  load_refdocs "$STATE_FILE"

  local -a srcs=() dests=() modes=()   # mode: move | kept | remap
  declare -A reserved=() seen_src=()

  # Preflight — validate every path and reserve destinations before any move,
  # so a bad argument aborts the whole call instead of leaving a half-move.
  local p e best best_at
  for p in "$@"; do
    p="$(normalize_rel_path "$p")"
    if is_unsafe_name "$p"; then
      echo "consume: refusing filename with quote/backslash/control char: $p" >&2; exit 1
    fi
    case "/$p/" in
      */../*) echo "consume: refusing path with '..': $p" >&2; exit 1 ;;
    esac
    [[ "$p" == "$RAW_DIR/"* ]] || { echo "consume: not under $RAW_DIR/: $p" >&2; exit 1; }
    [[ "$p" == "$RAW_DIR/README.md" ]] && { echo "consume: README.md is not consumable" >&2; exit 1; }
    if [[ -n "${seen_src[$p]:-}" ]]; then
      echo "consume: duplicate path argument: $p" >&2; exit 1
    fi
    seen_src[$p]=1

    local dest mode
    if [[ ! -e "$p" && ! -L "$p" ]]; then
      # Shared source another promote folder already consumed? Remap via the
      # recorded origin (latest consumed_at wins when several match).
      best=""; best_at=""
      for e in "${!RD_ORIGIN[@]}"; do
        if [[ "${RD_ORIGIN[$e]}" == "$p" ]]; then
          if [[ -z "$best" || "${RD_AT[$e]:-}" > "$best_at" ]]; then
            best="$e"; best_at="${RD_AT[$e]:-}"
          fi
        fi
      done
      if [[ -n "$best" ]]; then
        dest="$best"; mode="remap"
      else
        echo "consume: not a regular file: $p" >&2; exit 1
      fi
    else
      [[ -L "$p" ]] && { echo "consume: refusing symlink: $p" >&2; exit 1; }
      [[ -f "$p" ]] || { echo "consume: not a regular file: $p" >&2; exit 1; }
      assert_no_symlink_components "$p" "source"
      if [[ "$p" == "$stale_prefix/"* ]]; then
        dest="$p"; mode="kept"
      else
        local rel="${p#"$RAW_DIR"/}"
        dest="$stale_prefix/$rel"
        assert_no_symlink_components "$(dirname "$dest")" "destination"
        if [[ -e "$dest" || -n "${reserved[$dest]:-}" ]]; then
          # Collision → suffix -2, -3, … before the extension.
          local base="$dest" ext="" n=2 cand
          if [[ "${dest##*/}" == *.* ]]; then
            ext=".${dest##*.}"
            base="${dest%"$ext"}"
          fi
          while :; do
            cand="${base}-${n}${ext}"
            [[ ! -e "$cand" && -z "${reserved[$cand]:-}" ]] && break
            n=$((n + 1))
          done
          dest="$cand"
        fi
        mode="move"
      fi
    fi
    reserved[$dest]=1
    srcs+=("$p")
    dests+=("$dest")
    modes+=("$mode")
  done

  mkdir -p "$stale_prefix"

  local now commit
  now=$(iso_now)
  commit=$(git rev-parse --short HEAD 2>/dev/null || true)

  local i src dest cur o
  for i in "${!srcs[@]}"; do
    src="${srcs[$i]}"
    dest="${dests[$i]}"
    case "${modes[$i]}" in
      move)
        mkdir -p "$(dirname "$dest")"
        if ! mv "$src" "$dest"; then
          echo "consume: move failed: $src -> $dest (snapshot not rewritten; already-moved files stay in stale/)" >&2
          exit 1
        fi
        printf 'MOVED\t%s\t%s\n' "$src" "$dest"
        ;;
      kept)
        printf 'KEPT\t%s\n' "$dest"
        ;;
      remap)
        printf 'REMAPPED\t%s\t%s\n' "$src" "$dest"
        ;;
    esac

    # Merge slug into the destination entry (dedupe, order-preserving).
    cur="${RD_SLUGS[$dest]:-}"
    if [[ -n "$cur" ]]; then
      case ",$cur," in
        *",$slug,"*) : ;;
        *) cur="$cur,$slug" ;;
      esac
    else
      cur="$slug"
    fi
    # Defensive: if an entry was somehow recorded under the source path,
    # migrate its slugs to the destination entry.
    if [[ "$src" != "$dest" && -n "${RD_SLUGS[$src]:-}" ]]; then
      local -a _old=()
      IFS=',' read -ra _old <<< "${RD_SLUGS[$src]}"
      for o in "${_old[@]}"; do
        [[ -z "$o" ]] && continue
        case ",$cur," in
          *",$o,"*) : ;;
          *) cur="$cur,$o" ;;
        esac
      done
      unset "RD_SLUGS[$src]" "RD_COMMIT[$src]" "RD_AT[$src]" "RD_ORIGIN[$src]"
    fi
    RD_SLUGS[$dest]="$cur"
    [[ -n "$commit" ]] && RD_COMMIT[$dest]="$commit"
    RD_AT[$dest]="$now"
    if [[ "${modes[$i]}" == "move" ]]; then
      RD_ORIGIN[$dest]="$src"
    fi
    printf 'REF\t%s\t%s\n' "$dest" "${RD_SLUGS[$dest]}"
  done

  write_state
  echo "Updated: $STATE_FILE"
}

cmd_outdated() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "(not inside a git repo — outdated check skipped)"
    return 0
  fi
  local any=0
  local aging_threshold="${SCV_RAW_AGING_COMMITS:-30}"
  local p slugs cmt at origin changed hits top extra behind
  while IFS=$'\t' read -r p slugs cmt at origin; do
    [[ -z "$p" ]] && continue
    cmt="$(unplaceholder "${cmt:-}")"
    if [[ ! -f "$p" ]]; then
      printf 'UNKNOWN\t%s\t(file missing)\n' "$p"
      continue
    fi
    if [[ -z "$cmt" ]] || ! git cat-file -e "${cmt}^{commit}" 2>/dev/null; then
      printf 'UNKNOWN\t%s\t(no resolvable ref_commit)\n' "$p"
      continue
    fi
    changed=$(git diff --name-only "$cmt"..HEAD 2>/dev/null || true)
    if [[ -z "$changed" ]]; then
      printf 'FRESH\t%s\n' "$p"
      continue
    fi
    # Path-looking tokens in the doc, intersected with files changed since
    # ref_commit. Heuristic only — Claude Code verifies semantically.
    # The changed list travels via a temp file (NR==FNR), NOT `awk -v`:
    # BSD/macOS awk rejects newlines in -v values ("newline in string").
    local changed_f
    changed_f=$(mktemp)
    printf '%s\n' "$changed" > "$changed_f"
    hits=$(grep -IoE '[A-Za-z0-9_@][A-Za-z0-9_.@/-]*\.[A-Za-z0-9_]+' "$p" 2>/dev/null \
      | LC_ALL=C sort -u | head -500 \
      | awk '
          NR == FNR { if ($0 != "") c[++n] = $0; next }
          {
            for (i = 1; i <= n; i++) {
              if (c[i] == $0 || substr(c[i], length(c[i]) - length($0)) == "/" $0) {
                print c[i]
                break
              }
            }
          }' "$changed_f" - | LC_ALL=C sort -u)
    rm -f "$changed_f"
    if [[ -n "$hits" ]]; then
      any=1
      top=$(printf '%s\n' "$hits" | head -3 | paste -sd, -)
      extra=$(printf '%s\n' "$hits" | grep -c .)
      [[ $extra -gt 3 ]] && top="$top(+$((extra - 3)))"
      printf 'OUTDATED-CANDIDATE\t%s\t%s\n' "$p" "$top"
      continue
    fi
    behind=$(git rev-list --count "$cmt"..HEAD 2>/dev/null || echo 0)
    if [[ "$behind" -gt "$aging_threshold" ]]; then
      printf 'AGING\t%s\t%s commits behind\n' "$p" "$behind"
    else
      printf 'FRESH\t%s\n' "$p"
    fi
  done < <(refdocs_to_tsv "$STATE_FILE")
  [[ $any -eq 1 ]] && return 2
  return 0
}

# ---------- main ----------

case "${1:-}" in
  scan)             cmd_scan ;;
  diff)             cmd_diff; exit $? ;;
  update)           cmd_update ;;
  status-counts)    cmd_status_counts ;;
  consume)          shift; cmd_consume "$@" ;;
  unused)           cmd_unused ;;
  refs)             shift || true; cmd_refs "${1:-}" ;;
  lifecycle-counts) cmd_lifecycle_counts ;;
  outdated)         cmd_outdated; exit $? ;;
  -h|--help|"")     usage; exit 0 ;;
  *) echo "Unknown subcommand: $1" >&2; usage >&2; exit 1 ;;
esac
