#!/usr/bin/env bash
# Environment loading and validation utilities.

env_load() {
  # Load .env from current working directory (project root) if present.
  # Values with spaces should be quoted in .env.
  #
  # A user .env may reference unset vars (e.g. DATABASE_URL=...${DB_USER}...) or
  # hold a $-containing secret. Sourcing it while a caller has `set -u` (nounset)
  # active would ABORT the whole script — and a `|| true` on the caller does NOT
  # catch a nounset abort. So relax nounset only around the source, then restore.
  if [[ -f "./.env" ]]; then
    local _u_was_set=0
    [[ -o nounset ]] && _u_was_set=1
    set -a
    set +u
    # shellcheck disable=SC1091
    source "./.env"
    set +a
    (( _u_was_set )) && set -u
  fi
}

env_require() {
  # Usage: env_require VAR1 VAR2 ...
  # Returns non-zero and prints missing vars to stderr.
  local missing=()
  for var in "$@"; do
    if [[ -z "${!var:-}" ]]; then
      missing+=("$var")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "✖ Missing required env vars: ${missing[*]}" >&2
    return 1
  fi
  return 0
}

env_default() {
  # Usage: env_default VAR default_value
  # Sets VAR to default_value if empty.
  local var="$1" default="$2"
  if [[ -z "${!var:-}" ]]; then
    export "$var"="$default"
  fi
}
