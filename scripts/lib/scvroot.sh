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
#   scv_init_paths [target]
#     Derive RAW_DIR / STATE_FILE / PROMOTE_DIR / ARCHIVE_DIR and export SCV_DIR
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

scv_init_paths() {
  local target="${1:-}" root=""
  if [[ -n "$target" ]]; then
    root="$(scv_target_path "$target")" || root=""
  fi
  [[ -z "$root" ]] && root="$(scv_root_dir)"

  RAW_DIR="${RAW_DIR:-$root/raw}"
  STATE_FILE="${STATE_FILE:-$root/readpath.json}"
  PROMOTE_DIR="${PROMOTE_DIR:-$root/promote}"
  ARCHIVE_DIR="${ARCHIVE_DIR:-$root/archive}"
  export SCV_DIR="$root" RAW_DIR STATE_FILE PROMOTE_DIR ARCHIVE_DIR
}
