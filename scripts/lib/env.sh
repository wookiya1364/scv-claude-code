#!/usr/bin/env bash
# Environment loading and validation utilities.

env_load() {
  # Load .env from current working directory (project root) if present.
  # Values with spaces should be quoted in .env.
  if [[ -f "./.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "./.env"
    set +a
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
