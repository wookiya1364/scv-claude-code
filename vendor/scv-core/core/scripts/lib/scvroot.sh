#!/usr/bin/env bash
# scvroot.sh — locate the scv/ directory for the CURRENT context, so SCV works
# in a monorepo that holds MULTIPLE scv/ dirs: a micro scv per sub-project
# (FE/scv, BE/scv, AI/scv) plus a macro umbrella scv at the repo root (root/scv).
#
# Design intent (per the multi-scv model):
#   - Which scv/ a command operates on is CONTEXT-driven, not a single global
#     setting. Run a command from FE/ → FE/scv (micro); from the repo root →
#     root/scv (macro). That falls out of CWD-based resolution for free.
#   - An explicit module target arg (e.g. `/scv:status FE`) overrides CWD when
#     you want to address a sibling module without cd-ing.
#   - SCV_DIR (env) is only a quiet last-resort escape hatch — NOT the primary
#     mechanism (it would pin every command to one scv and break micro/macro).
#
# Public API (sourced; no side effects on source):
#
#   scv_target_path <arg>
#     Echo the scv/ path an explicit module arg resolves to, or return 1.
#       "FE"      → FE/scv   (if FE/scv exists)
#       "FE/scv"  → FE/scv   (a path whose basename is scv and which exists)
#     Callers use this to peel an optional leading module target off "$@".
#
#   scv_root_dir
#     Echo the auto-resolved scv/ dir (no explicit target). Precedence:
#       1. CWD:      ./scv exists (micro when in a module dir, macro at root).
#       2. Walk up:  nearest ancestor with a marked scv/ (session in a subdir).
#       3. SCV_DIR:  env override to an existing non-default dir (fallback).
#       4. Default:  "scv" (relative) — legacy standalone behavior, unchanged.
#     Steps 1 & 4 return the RELATIVE string "scv" so standalone repos behave
#     exactly as before.
#
#   scv_autosync [scv_dir]
#     Refresh the project's workflow docs when the stamped template version is
#     behind the payload's. Detailed contract at the function below.
#
#   scv_init_paths [target]
#     Runs scv_autosync on the resolved root, then derives
#     RAW_DIR / STATE_FILE / PROMOTE_DIR / ARCHIVE_DIR and exports SCV_DIR
#     from (target ? scv_target_path : scv_root_dir) — but only for vars the
#     caller hasn't already set, so an explicit `RAW_DIR=... bash readpath.sh`
#     still wins (env-override convention).

# Return 0 if $1 is a directory that looks like an SCV root (has a known child).
_scv_is_root() {
  local d="$1"
  [[ -d "$d" ]] || return 1
  [[ -d "$d/raw" || -d "$d/promote" || -d "$d/archive" || -f "$d/PROMOTE.md" ]]
}

scv_target_path() {
  local t="${1:-}"
  [[ -n "$t" ]] || return 1
  t="${t%/}"                              # tolerate a trailing slash
  local out=""
  if [[ -d "$t/scv" ]]; then              # "FE" → FE/scv  (and "." → ./scv)
    out="$t/scv"
  elif [[ -d "$t" && "$(basename "$t")" == "scv" ]]; then   # "FE/scv" → itself
    out="$t"
  else
    return 1
  fi
  out="${out#./}"                         # normalize "./scv" → "scv" (target ".")
  printf '%s\n' "$out"
}

scv_root_dir() {
  # 1. CWD/scv — context-driven default (micro in a module dir, macro at root).
  #    Returned relative for byte-identical standalone behavior. No marker
  #    requirement (a brand-new project may have an empty scv/).
  if [[ -d "scv" ]]; then
    printf 'scv\n'
    return 0
  fi

  # 2. Walk up parents for a marked scv/ (session opened inside a deeper subdir),
  #    but never cross the current git repo boundary — otherwise an outer repo's
  #    scv/ could be silently read/written/moved from an unrelated inner repo.
  local top; top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  local d; d="$(dirname "$PWD")"
  while [[ -n "$d" && "$d" != "/" ]]; do
    # only inspect dirs INSIDE the current git repo — never attach an outer
    # (unrelated) repo's scv/. If we know the repo root, break once we'd step
    # above it (or start above it, e.g. CWD is itself a nested inner repo).
    if [[ -n "$top" && "$d" != "$top" && "$d" != "$top"/* ]]; then break; fi
    if _scv_is_root "$d/scv"; then
      printf '%s\n' "$d/scv"
      return 0
    fi
    [[ -n "$top" && "$d" == "$top" ]] && break   # reached the repo root
    d="$(dirname "$d")"
  done

  # 3. SCV_DIR env — quiet fallback only (opt-in escape hatch, not required).
  if [[ -n "${SCV_DIR:-}" && "${SCV_DIR}" != "scv" && -d "${SCV_DIR}" ]]; then
    printf '%s\n' "${SCV_DIR}"
    return 0
  fi

  # 4. Legacy default — unchanged. Callers building "$root/raw" get "scv/raw".
  printf 'scv\n'
}


# ---- automatic template refresh ---------------------------------------------
# scv_autosync [scv_dir]
#   Close the gap between the project's stamped template version and the
#   payload's, the moment any action touches the project.
#
#   Why here and not in the update action: plugin payloads are cached per
#   version, so at update time the running session still holds the OLD
#   payload's sync — calling it there would lay down the old template and
#   report success. Only after a reload does any code see the new payload, and
#   the first action that runs is the first honest chance to migrate. This
#   hook is that chance.
#
#   It never hydrates (no SCV.md and no PROMOTE.md → not adopted → no-op), and
#   it never auto-migrates a pre-2.x project: the 2.0.0 retirement pass deletes
#   seven user-authored docs, and the sync protocol requires offering a
#   DECISIONS.md hand-off first — a conversation this hook must not skip. Those
#   projects get one pointer line instead. 2.x → 2.y is refreshed in place;
#   sync's dirty-refusal keeps local edits safe, and sync re-stamps the index
#   when done, so one run converges and the next call is a no-op.
#
#   A failed refresh warns and returns 0 — a migration problem must never
#   brick the action that tripped it. Opt out with SCV_AUTOSYNC=off (process
#   environment only, same reasoning as SCV_GUARD). All reporting goes to
#   stderr: callers parse this library's users' stdout.
# _scv_ver_lt A B — true when A is numerically older than B on the first three
# dot-separated fields. Pure bash: `sort -V` is not everywhere this ships.
_scv_ver_lt() {
  local a1 a2 a3 arest b1 b2 b3 brest
  IFS='.-' read -r a1 a2 a3 arest <<< "$1."
  IFS='.-' read -r b1 b2 b3 brest <<< "$2."
  a1="${a1//[!0-9]/}"; a2="${a2//[!0-9]/}"; a3="${a3//[!0-9]/}"
  b1="${b1//[!0-9]/}"; b2="${b2//[!0-9]/}"; b3="${b3//[!0-9]/}"
  local a=$(( ${a1:-0}*1000000 + ${a2:-0}*1000 + ${a3:-0} ))
  local b=$(( ${b1:-0}*1000000 + ${b2:-0}*1000 + ${b3:-0} ))
  (( a < b )) && return 0
  (( a > b )) && return 1
  # Numeric tie: semver orders a prerelease below its release, so
  # 2.1.0-rc1 < 2.1.0. Two prereleases tie conservatively (not older).
  [[ -n "${arest%.}" && -z "${brest%.}" ]]
}

scv_autosync() {
  [[ "${SCV_AUTOSYNC:-on}" == "off" ]] && return 0
  [[ -n "${SCV_AUTOSYNC_RUNNING:-}" ]] && return 0
  # Claim the whole process tree, not just the sync invocation: one action
  # script spawns several helpers (status → readpath ×4), each of which
  # sources this library. Without the export every helper re-ran the check —
  # and when the refresh could not complete, re-ran the refresh — turning one
  # action into N attempts and N stderr reports. One action, one check.
  export SCV_AUTOSYNC_RUNNING=1
  local root="${1:-}"
  [[ -n "$root" ]] || root="$(scv_root_dir)"
  [[ -d "$root" ]] || return 0

  local lib_dir payload_root
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  payload_root="$(cd "$lib_dir/../.." && pwd)"
  [[ -f "$payload_root/TEMPLATE_VERSION" && -f "$payload_root/scripts/sync.sh" ]] || return 0
  local remote
  remote="$(tr -d '[:space:]' < "$payload_root/TEMPLATE_VERSION")"
  [[ -n "$remote" ]] || return 0

  local index="$root/SCV.md" local_v=""
  if [[ -f "$index" ]]; then
    local_v="$(sed -n 's/.*<!-- STANDARD:VERSION -->\(.*\)<!-- \/STANDARD:VERSION -->.*/\1/p' "$index" | head -n 1 | tr -d '[:space:]')"
  fi
  if [[ -z "$local_v" ]]; then
    if [[ -f "$index" ]]; then
      # SCV.md exists but carries no readable stamp — a damaged or hand-edited
      # 2.x index, not a pre-2.x legacy. Calling it "legacy" would send the
      # user into a migration they do not need; restamping is what fixes it.
      echo "scv: $index carries no readable template stamp — run the sync action once to restamp it." >&2
    elif [[ -f "$root/PROMOTE.md" ]]; then
      # Hydrated but no SCV.md at all = pre-2.x legacy. Point, never act.
      echo "scv: this project's workflow docs predate template 2.0 — run the sync action once for the interactive migration." >&2
    fi
    return 0
  fi
  [[ "$local_v" == "$remote" ]] && return 0
  case "$local_v" in
    [2-9].*|[1-9][0-9]*.*) : ;;
    *) echo "scv: template $local_v predates 2.0 — run the sync action once for the interactive migration." >&2
       return 0 ;;
  esac
  # Direction matters: refresh only UPWARD. A session holding an older payload
  # than the one that stamped the project (a teammate updated first, this
  # plugin has not reloaded yet) must not "refresh" the docs backward — that
  # would be two machines silently reverting each other's templates forever.
  if ! _scv_ver_lt "$local_v" "$remote"; then
    echo "scv: this project's template ($local_v) is newer than this payload's ($remote) — update the plugin; nothing was changed." >&2
    return 0
  fi

  local proj out
  proj="$(dirname "$root")"
  if out="$(bash "$payload_root/scripts/sync.sh" --project-dir "$proj" 2>&1)"; then
    # Exit 0 is not success — sync exits 0 after refusing every file. Say what
    # actually happened, from what it reported. When anything was refused the
    # stamp did not advance, so "will retry" is a fact, not a hope.
    local refused=0
    printf '%s\n' "$out" | grep -qE '^  (DIRTY|WARN|UNKNOWN)' && refused=1
    if [[ $refused -eq 0 ]]; then
      echo "scv: workflow docs refreshed $local_v → $remote (automatic; the sync action re-runs this by hand)" >&2
    else
      echo "scv: template refresh $local_v → $remote was PARTIAL — the files below were skipped, and the next action retries:" >&2
      printf '%s\n' "$out" | grep -E '^  (DIRTY|WARN|UNKNOWN)' >&2 || true
    fi
  else
    echo "scv: automatic template refresh $local_v → $remote failed — run the sync action by hand; the current action continues." >&2
  fi
  return 0
}

scv_init_paths() {
  local target="${1:-}" root=""
  if [[ -n "$target" ]]; then
    root="$(scv_target_path "$target")" || root=""
  fi
  [[ -z "$root" ]] && root="$(scv_root_dir)"

  scv_autosync "$root"

  RAW_DIR="${RAW_DIR:-$root/raw}"
  STATE_FILE="${STATE_FILE:-$root/readpath.json}"
  PROMOTE_DIR="${PROMOTE_DIR:-$root/promote}"
  ARCHIVE_DIR="${ARCHIVE_DIR:-$root/archive}"
  export SCV_DIR="$root" RAW_DIR STATE_FILE PROMOTE_DIR ARCHIVE_DIR
}
