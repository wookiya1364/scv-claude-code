#!/usr/bin/env bash
# attachment-scope.sh — which test-results/ files belong to THIS plan (v0.32.0+).
#
# PR and report attachments used to be "everything in test-results/", and
# Playwright keeps only the last run there — so after an accumulated regression
# the PR carried other features' videos. Default scope is now `slug`: a file
# belongs to the plan when its path under test-results/ contains the slug
# (the per-slug E2E spec convention names Playwright's output folders after
# the spec file, so <slug>.spec.ts → test-results/<slug>-<title>-<project>/).
#
#   attachment_scope_mode                 → slug | all
#   attachment_scope_filter <slug>        stdin: paths → stdout: the ones in scope
#   attachment_scope_resolve_slug [slug]  → explicit > $SCV_ATTACHMENTS_SLUG >
#                                           the single active promote plan > ""
#   attachment_scope_read_test_command <TESTS.md> → the `## How to run` block
#
# Mode: read through the one settings entrance (environment → secret → plain →
# default), never by reaching into a file here. `.env` is not a settings store
# any more — settings live in scv/scv_settings.json. Only `all` (any case) turns
# the filter off; anything else means `slug`.

attachment_scope_mode() {
  local v="${SCV_ATTACHMENTS_SCOPE:-}"
  if [[ -z "$v" ]]; then
    if ! declare -F settings_get >/dev/null 2>&1; then
      local _d
      _d="$( cd "$( dirname "${BASH_SOURCE[0]}" )" 2>/dev/null && pwd )" || _d=""
      # shellcheck source=settings.sh
      [[ -n "$_d" && -f "$_d/settings.sh" ]] && source "$_d/settings.sh"
    fi
    declare -F settings_get >/dev/null 2>&1 && v="$(settings_get SCV_ATTACHMENTS_SCOPE 2>/dev/null)"
  fi
  v="$(printf '%s' "$v" | tr -d '"[:space:]' | tr -d "'" | tr '[:upper:]' '[:lower:]')"
  if [[ "$v" == "all" ]]; then echo all; else echo slug; fi
}

# @pure
attachment_scope_filter() {
  local slug="$1" line
  if [[ -z "$slug" ]]; then cat; return 0; fi
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    case "$line" in *"$slug"*) printf '%s\n' "$line" ;; esac
  done
  return 0   # the last `read` returns 1 at EOF — callers under `set -e`/pipefail must see success
}

# Slug for a caller that has none of its own (the report action is phase-level).
# A single active plan under <scv>/promote/ is unambiguous; zero or several is
# not, and the caller falls back to the legacy "all" collection with a notice.
attachment_scope_resolve_slug() {
  local explicit="${1:-}"
  if [[ -n "$explicit" ]]; then printf '%s\n' "$explicit"; return 0; fi
  if [[ -n "${SCV_ATTACHMENTS_SLUG:-}" ]]; then printf '%s\n' "$SCV_ATTACHMENTS_SLUG"; return 0; fi
  local pdir="${PROMOTE_DIR:-scv/promote}" plans=() d
  for d in "$pdir"/*/; do
    [[ -f "${d}PLAN.md" ]] && plans+=("$(basename "$d")")
  done
  if [[ ${#plans[@]} -eq 1 ]]; then printf '%s\n' "${plans[0]}"; return 0; fi
  printf '\n'
}

# Same extraction as regression.sh: first fenced block under `## How to run`
# (or the legacy Korean heading), else the section's plain text.
attachment_scope_read_test_command() {
  local tests="$1"
  [[ -f "$tests" ]] || return 1
  awk '
    BEGIN { in_section=0; in_fence=0; has_fence=0; buf=""; plain="" }
    /^## /{ if (in_section) { exit } }
    /^## (How to run|실행 방법)[[:space:]]*$/ { in_section=1; next }
    in_section {
      if (!in_fence && /^[[:space:]]*```/) { in_fence=1; has_fence=1; next }
      if (in_fence && /^[[:space:]]*```[[:space:]]*$/) { in_fence=0; next }
      if (in_fence) { buf = buf $0 "\n"; next }
      if (!has_fence && $0 !~ /^[[:space:]]*$/ && $0 !~ /^<!--/) { plain = plain $0 "\n" }
    }
    END { if (buf != "") { printf "%s", buf; exit } if (plain != "") { printf "%s", plain } }
  ' "$tests"
}
