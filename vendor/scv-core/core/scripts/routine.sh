#!/usr/bin/env bash
# routine.sh — action:routine entry point (list / prepare / lint).
#
# A routine is ONE markdown file under scv/routines/<name>.md whose frontmatter
# declares: name / cadence / guardrails / exit / report. The body is a one
# sentence~paragraph TASK (plan-grammar: task + guardrails + exit criteria —
# never a step list). See the seeded scv/routines/README.md for the convention.
#
# Subcommands / flags:
#   --list           Table of defined routines (NAME / CADENCE / REPORT).
#   <name>           Parse scv/routines/<name>.md and emit prepare signals.
#   --lint <file>    Frontmatter schema check for a routine file (exit 1 on
#                    violations). All five keys are required.
#
# Exit codes:
#   0 — list/prepare/lint succeeded
#   1 — routine not found (available list printed) / lint violations / bad flag
#       (bare no-arg invocation prints usage and exits 0, same as -h)
#
# Deliberately NOT here: any scheduling. SCV never registers cron entries,
# starts daemons, or loops — the trailing guidance block is text for the USER
# to act on in their host. cadence is a suggestion, not a registration.
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/yaml.sh
source "$SCRIPT_DIR/lib/yaml.sh"
# shellcheck source=lib/scvroot.sh
source "$SCRIPT_DIR/lib/scvroot.sh"

usage() {
  cat <<'EOF'
Usage: routine.sh --list
       routine.sh <name>
       routine.sh --lint <file>

Defines nothing, schedules nothing: lists routines under scv/routines/,
or parses one routine md (frontmatter + task body) for Claude Code.
EOF
}

# ---------- shared helpers ----------

routine_body() {
  # Prints the markdown body AFTER the frontmatter block.
  awk '
    BEGIN { fences = 0 }
    /^---[[:space:]]*$/ { if (fences < 2) { fences++; next } }
    fences >= 2 { print }
  ' "$1"
}

routine_files() {
  # Direct children of ROUTINES_DIR, README.md excluded, sorted.
  local f
  shopt -s nullglob
  for f in "$ROUTINES_DIR"/*.md; do
    [[ "$(basename "$f")" == "README.md" ]] && continue
    printf '%s\n' "$f"
  done | LC_ALL=C sort
  shopt -u nullglob
}

print_available() {
  # Bullet list "  - <name> (<cadence>)" of defined routines, to stdout.
  local f name cadence n=0
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    name="$(yaml_get "$f" "name")"
    [[ -z "$name" ]] && name="$(basename "$f" .md)"
    cadence="$(yaml_get "$f" "cadence")"
    printf '  - %s (%s)\n' "$name" "${cadence:-?}"
    n=$((n + 1))
  done < <(routine_files)
  if [[ $n -eq 0 ]]; then
    echo "  (no routines defined — create scv/routines/<name>.md;"
    echo "   convention: scv/routines/README.md, starter templates:"
    echo "   SCV Core template/scv/routines/examples/)"
  fi
}

# ---------- lint ----------

cmd_lint() {
  local f="$1" violations=0 report val
  if [[ ! -f "$f" ]]; then
    echo "✖ no such file: $f" >&2
    return 1
  fi
  for key in name cadence report; do
    val="$(yaml_get "$f" "$key")"
    if [[ -z "$val" ]]; then
      echo "✖ $f: missing required key '$key'"
      violations=$((violations + 1))
    fi
  done
  for key in guardrails exit; do
    if [[ -z "$(yaml_get_list "$f" "$key")" ]]; then
      echo "✖ $f: missing or empty list '$key'"
      violations=$((violations + 1))
    fi
  done
  report="$(yaml_get "$f" "report")"
  if [[ -n "$report" ]] && ! printf ' %s ' "always on-failure never" | grep -qF " $report "; then
    echo "✖ $f: invalid report '$report' (expected: always | on-failure | never)"
    violations=$((violations + 1))
  fi
  if [[ -z "$(routine_body "$f" | grep -v '^[[:space:]]*$' | head -1)" ]]; then
    echo "✖ $f: empty task body (write the task as one sentence~paragraph)"
    violations=$((violations + 1))
  fi
  if [[ $violations -gt 0 ]]; then
    echo "→ $violations violation(s) in $f"
    return 1
  fi
  echo "ROUTINE_LINT: ok — $f"
}

# ---------- list ----------

cmd_list() {
  echo "MODE: list"
  echo "ROUTINES_DIR: $ROUTINES_DIR"
  local files n
  files="$(routine_files)"
  n="$(printf '%s\n' "$files" | grep -c . || true)"
  echo "ROUTINES: $n"
  echo ""
  if [[ "$n" -eq 0 ]]; then
    echo "(no routines defined — create scv/routines/<name>.md;"
    echo " convention: scv/routines/README.md, starter templates:"
    echo " SCV Core template/scv/routines/examples/)"
    return 0
  fi
  printf '%-28s %-10s %s\n' "NAME" "CADENCE" "REPORT"
  local f name cadence report
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    name="$(yaml_get "$f" "name")"
    [[ -z "$name" ]] && name="$(basename "$f" .md)"
    cadence="$(yaml_get "$f" "cadence")"
    report="$(yaml_get "$f" "report")"
    printf '%-28s %-10s %s\n' "$name" "${cadence:-?}" "${report:-?}"
  done <<< "$files"
  echo ""
  echo "Run one with: action:routine <name>"
  echo "(cadence is a suggestion — scheduling is host-owned, SCV registers nothing)"
}

# ---------- prepare ----------

cmd_prepare() {
  local name="$1" file="" f
  # Exact basename match first, then frontmatter `name:` match.
  if [[ -f "$ROUTINES_DIR/$name.md" ]]; then
    file="$ROUTINES_DIR/$name.md"
  else
    while IFS= read -r f; do
      [[ -z "$f" ]] && continue
      if [[ "$(yaml_get "$f" "name")" == "$name" ]]; then
        file="$f"
        break
      fi
    done < <(routine_files)
  fi

  if [[ -z "$file" ]]; then
    {
      echo "✖ routine not found: $name"
      echo "  available routines:"
      print_available
    } >&2
    return 1
  fi

  local rname cadence report
  rname="$(yaml_get "$file" "name")"
  [[ -z "$rname" ]] && rname="$(basename "$file" .md)"
  cadence="$(yaml_get "$file" "cadence")"
  report="$(yaml_get "$file" "report")"

  echo "MODE: prepare"
  echo "ROUTINE: $rname"
  echo "FILE: $file"
  echo "CADENCE: ${cadence:-(unset)}"
  echo "REPORT: ${report:-(unset)}"
  echo "GUARDRAILS:"
  local line any=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    printf '  - %s\n' "$line"
    any=1
  done < <(yaml_get_list "$file" "guardrails")
  [[ $any -eq 0 ]] && echo "  (none declared — treat as malformed; see scv/routines/README.md)"
  echo "EXIT:"
  any=0
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    printf '  - %s\n' "$line"
    any=1
  done < <(yaml_get_list "$file" "exit")
  [[ $any -eq 0 ]] && echo "  (none declared — treat as malformed; see scv/routines/README.md)"
  echo ""
  echo "=== task ==="
  routine_body "$file"
  echo ""
  echo "=== host scheduling examples (guidance only — SCV never schedules) ==="
  echo "  - host agent loop: re-run \"action:routine $rname\" with your host's"
  echo "    recurring-prompt feature (suggested cadence: ${cadence:-1d})"
  echo "  - cron (user-registered): 0 9 * * *  cd <project-root> && <host-agent-cli> \"action:routine $rname\""
  echo "  - CI schedule: a scheduled pipeline job that runs \"action:routine $rname\""
  echo "  (registration is always YOUR action on the host — SCV registers nothing)"
}

# ---------- main ----------

# Optional leading module target (monorepo, e.g. `routine FE --list` or
# `routine FE dead-code`). A single bare arg is always a routine NAME —
# a target is only peeled when another arg follows it.
SCV_TARGET=""
if [[ $# -ge 2 && "${1:-}" != -* ]] && scv_target_path "$1" >/dev/null 2>&1; then
  SCV_TARGET="$1"
  shift
fi
scv_init_paths "$SCV_TARGET"
ROUTINES_DIR="${ROUTINES_DIR:-$SCV_DIR/routines}"

case "${1:-}" in
  --list)
    cmd_list
    ;;
  --lint)
    [[ $# -ge 2 && -n "${2:-}" ]] || { echo "✖ --lint requires FILE" >&2; usage >&2; exit 1; }
    cmd_lint "$2"
    exit $?
    ;;
  -h|--help|"")
    usage
    ;;
  -*)
    echo "Unknown flag: $1" >&2
    usage >&2
    exit 1
    ;;
  *)
    cmd_prepare "$1"
    exit $?
    ;;
esac
