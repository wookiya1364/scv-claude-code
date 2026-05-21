#!/usr/bin/env bash
# apply-model-policy.sh — apply a model policy to every commands/*.md frontmatter.
#
# Usage:
#   apply-model-policy.sh --policy <name>
#   apply-model-policy.sh --from-env [--project-dir <dir>]
#
# Policies:
#   recommended       — per-command mapping (default; matches v0.11.5 baseline)
#   all-opus          — every command uses opus
#   all-sonnet        — every command uses sonnet
#   all-haiku         — every command uses haiku
#   session-default   — remove model: line entirely (use Claude Code session model)
#
# Idempotent: running twice with the same policy produces no diff.
# Never uses placeholder substitution — only real shell values.

set -euo pipefail

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMANDS_DIR="$PLUGIN_ROOT/commands"

COMMANDS=(status report update install-deps set-models sync help promote codegen regression work)

# recommended policy mapping (single source of truth)
recommended_for() {
  case "$1" in
    status|report|update|install-deps|set-models) echo "haiku" ;;
    sync|help|promote|codegen|regression|work) echo "opus" ;;
    *) echo "" ;;
  esac
}

valid_policy() {
  case "$1" in
    recommended|all-opus|all-sonnet|all-haiku|session-default) return 0 ;;
    *) return 1 ;;
  esac
}

resolve_model() {
  local policy="$1" cmd="$2"
  case "$policy" in
    recommended) recommended_for "$cmd" ;;
    all-opus) echo "opus" ;;
    all-sonnet) echo "sonnet" ;;
    all-haiku) echo "haiku" ;;
    session-default) echo "" ;;
  esac
}

update_file() {
  local cmd="$1" target="$2"
  local file="$COMMANDS_DIR/$cmd.md"

  if [[ ! -f "$file" ]]; then
    echo "  $cmd: SKIP (file not found: $file)" >&2
    return 0
  fi

  local has_line current
  if grep -qE '^model: ' "$file"; then
    has_line=1
    current="$(grep -E '^model: ' "$file" | head -n1 | sed 's/^model: *//')"
  else
    has_line=0
    current=""
  fi

  if [[ -z "$target" ]]; then
    # session-default: ensure no model: line
    if [[ "$has_line" == "1" ]]; then
      sed -i.bak '/^model: /d' "$file"
      rm -f "$file.bak"
      echo "  $cmd: removed (was: $current)"
    else
      echo "  $cmd: ok (no model line)"
    fi
    return 0
  fi

  if [[ "$has_line" == "1" ]]; then
    if [[ "$current" == "$target" ]]; then
      echo "  $cmd: ok ($current)"
      return 0
    fi
    sed -i.bak "s/^model: .*/model: $target/" "$file"
    rm -f "$file.bak"
    echo "  $cmd: $current -> $target"
  else
    # Insert "model: $target" before the closing --- of frontmatter (the 2nd --- line)
    awk -v target="$target" '
      BEGIN { fm = 0; inserted = 0 }
      {
        if ($0 == "---") {
          fm++
          if (fm == 2 && !inserted) {
            print "model: " target
            inserted = 1
          }
        }
        print
      }
    ' "$file" > "$file.tmp"
    mv "$file.tmp" "$file"
    echo "  $cmd: added model: $target"
  fi
}

POLICY=""
PROJECT_DIR="${SCV_PROJECT_DIR:-$PWD}"
FROM_ENV=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --policy)
      if [[ $# -lt 2 ]]; then
        echo "error: --policy requires a value" >&2
        exit 2
      fi
      POLICY="$2"
      shift 2
      ;;
    --from-env)
      FROM_ENV=1
      shift
      ;;
    --project-dir)
      if [[ $# -lt 2 ]]; then
        echo "error: --project-dir requires a value" >&2
        exit 2
      fi
      PROJECT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      sed -n '2,18p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ "$FROM_ENV" == "1" ]]; then
  ENV_FILE="$PROJECT_DIR/.env"
  if [[ ! -f "$ENV_FILE" ]]; then
    echo "no .env at $ENV_FILE — skipping model policy apply."
    exit 0
  fi
  POLICY="$(grep -E '^SCV_MODEL_POLICY=' "$ENV_FILE" | tail -n1 | sed 's/^SCV_MODEL_POLICY=//' | tr -d '"' | tr -d "'" | tr -d '[:space:]')"
  if [[ -z "$POLICY" ]]; then
    echo "SCV_MODEL_POLICY not set in $ENV_FILE — skipping."
    exit 0
  fi
fi

if [[ -z "$POLICY" ]]; then
  echo "usage: $0 --policy <recommended|all-opus|all-sonnet|all-haiku|session-default> | --from-env" >&2
  exit 2
fi

if ! valid_policy "$POLICY"; then
  echo "error: invalid policy '$POLICY'" >&2
  echo "valid: recommended | all-opus | all-sonnet | all-haiku | session-default" >&2
  exit 2
fi

echo "Applying model policy: $POLICY"
echo "Target dir: $COMMANDS_DIR"
for cmd in "${COMMANDS[@]}"; do
  target="$(resolve_model "$POLICY" "$cmd")"
  update_file "$cmd" "$target"
done
echo "Done."
