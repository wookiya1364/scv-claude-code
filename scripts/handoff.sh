#!/usr/bin/env bash
# handoff.sh — cross-repo handoff producer/util for nested multi-repo SCV.
#
# Writes a handoff (+ decision + conversation) into the workspace ROOT scv repo
# and commits it LOCALLY. Pushing is a SEPARATE, consent-gated step (`push`).
#
# Subcommands:
#   write   Create/update a handoff in the root (commits locally; does NOT push).
#   push    Push the root repo. Call ONLY after explicit user consent.
#   list    List handoffs in the root (local-only), filtered by --to <repo_id>.
#   adopt   Consumer side: scaffold a local promote folder from a root handoff.
#   mark    Set a handoff's lifecycle status (open|claimed|done) in the root + commit.
#
# Mode behavior (resolved per-call, local files only — see lib/workspace.sh):
#   SINGLE  write/list are no-ops (exit 0 with a notice). Byte-identical world.
#   ROOT/CHILD  active.
#
# Graceful degrade: if the workspace root is unreachable, write/push fail with a
# clear message and a non-zero exit — local SCV is never affected.

set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/workspace.sh
source "$SCRIPT_DIR/lib/workspace.sh"
# shellcheck source=lib/yaml.sh
source "$SCRIPT_DIR/lib/yaml.sh"

die() { echo "✖ $*" >&2; exit 1; }

_md_section() {
  # Print the body under the first "## <...h...>" header until the next "## " header.
  local file="$1" h="$2"
  awk -v h="$h" '
    {
      if ($0 ~ /^## /) {
        if (index($0, h) > 0) { p = 1; next }
        else if (p) { exit }
      }
      if (p) print
    }' "$file"
}

resolve_root() {
  # Print absolute path to the root scv working copy (clone a URL into cache if
  # needed). Return 1 when unresolvable so callers can degrade.
  local root ws cache
  root="$(scv_root)"
  [[ -n "$root" ]] || return 1
  if [[ -d "$root" ]]; then
    ( cd "$root" && pwd )
    return 0
  fi
  # Treat as a git URL → local cache clone.
  ws="$(scv_workspace)"; ws="${ws:-default}"
  cache="${SCV_CACHE_DIR:-$HOME/.cache/scv}/$ws/root"
  if [[ -d "$cache/.git" ]]; then
    git -C "$cache" pull --rebase --autostash >/dev/null 2>&1 || true
    echo "$cache"
    return 0
  fi
  mkdir -p "$(dirname "$cache")"
  if git clone "$root" "$cache" >/dev/null 2>&1; then
    echo "$cache"
    return 0
  fi
  return 1
}

cmd_write() {
  local TO="" SLUG="" TITLE="" FROM="" DECISION="needed" FROM_SLUG="" BODY_FILE="" WHY_FILE="" REF_PR=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --to)        TO="$2"; shift 2 ;;
      --slug)      SLUG="$2"; shift 2 ;;
      --title)     TITLE="$2"; shift 2 ;;
      --from)      FROM="$2"; shift 2 ;;
      --decision)  DECISION="$2"; shift 2 ;;
      --from-slug) FROM_SLUG="$2"; shift 2 ;;
      --body-file) BODY_FILE="$2"; shift 2 ;;
      --why-file)  WHY_FILE="$2"; shift 2 ;;
      --ref-pr)    REF_PR="$2"; shift 2 ;;
      *) die "unknown flag: $1" ;;
    esac
  done

  if [[ "$(scv_resolve_mode)" == "SINGLE" ]]; then
    echo "single-repo: no workspace to propagate to — handoff skipped."
    exit 0
  fi

  [[ -n "$TO" ]]    || die "--to <repo_id> required"
  [[ -n "$SLUG" ]]  || die "--slug <slug> required"
  [[ -n "$TITLE" ]] || die "--title <title> required"
  [[ -n "$FROM" ]]  || FROM="$(scv_repo_id)"
  [[ -n "$FROM" ]]  || FROM="$(basename "$(pwd)")"
  case "$DECISION" in needed|maybe|not-needed) ;; *) die "--decision must be needed|maybe|not-needed" ;; esac

  local ROOT
  ROOT="$(resolve_root)" || die "cannot reach workspace root ($(scv_root)). Re-run when reachable — local work is unaffected (graceful degrade)."

  local DATE TODAY AUTHOR hid did
  DATE="$(date +%Y%m%d)"
  TODAY="$(date +%Y-%m-%d)"
  AUTHOR="$(git config user.name 2>/dev/null || echo unknown)"
  hid="${DATE}-${FROM}-${SLUG}__to-${TO}"
  did="${DATE}-${SLUG}"

  local HD="$ROOT/scv/handoffs"
  if [[ -f "$HD/promote/HANDOFF-$hid.md" ]] || ls "$HD"/archive/*/"HANDOFF-$hid.md" >/dev/null 2>&1; then
    die "handoff $hid is already claimed/archived in root — use a new slug or supersede it."
  fi
  mkdir -p "$HD/raw" "$ROOT/scv/decisions" "$ROOT/scv/conversations"

  local hf="$HD/raw/HANDOFF-$hid.md"
  local df="$ROOT/scv/decisions/$did.md"
  local cf="$ROOT/scv/conversations/$did.md"

  {
    echo "---"
    echo "handoff_id: $hid"
    echo "from_repo: $FROM"
    [[ -n "$FROM_SLUG" ]] && echo "from_slug: $FROM_SLUG"
    echo "to_repo: $TO"
    echo "decision: $DECISION"
    echo "status: open"
    echo "title: $TITLE"
    echo "created_at: $TODAY"
    echo "created_by: $AUTHOR"
    echo "conversation: conversations/$did.md"
    echo "refs:"
    if [[ -n "$FROM_SLUG" ]]; then
      echo "  - type: handoff-origin"
      echo "    id: $FROM_SLUG"
      [[ -n "$REF_PR" ]] && echo "    url: $REF_PR"
    fi
    echo "  - type: scv-decision"
    echo "    url: decisions/$did.md"
    echo "---"
    echo ""
    echo "# $TITLE"
    echo ""
    if [[ -n "$BODY_FILE" && -f "$BODY_FILE" ]]; then
      cat "$BODY_FILE"
    else
      echo "## What $TO must build"
      echo "(describe the corresponding development required)"
      echo ""
      echo "## Acceptance for the receiving repo"
      echo "- (seed the consumer's TESTS.md here)"
    fi
    echo ""
    echo "## Next step (receiving repo)"
    echo "\`/scv:promote\` from this handoff, then \`/scv:codegen\`."
  } > "$hf"

  {
    echo "---"
    echo "decision_id: $did"
    echo "decided_by: $AUTHOR"
    echo "decided_at: $TODAY"
    echo "verdict: $DECISION"
    echo "from_repo: $FROM"
    echo "targets: [$TO]"
    echo "handoffs: [$hid]"
    echo "---"
    echo ""
    echo "# Decision: $TITLE"
    echo ""
    if [[ -n "$WHY_FILE" && -f "$WHY_FILE" ]]; then
      cat "$WHY_FILE"
    else
      echo "## What was decided"
      echo "$TITLE"
      echo ""
      echo "## Why"
      echo "(rationale)"
    fi
  } > "$df"

  {
    echo "# Conversation — $did"
    echo ""
    if [[ -n "$WHY_FILE" && -f "$WHY_FILE" ]]; then
      cat "$WHY_FILE"
    else
      echo "(record the dialogue that led to this decision here)"
    fi
  } > "$cf"

  # Stage EXPLICIT paths only — never `git add -A` (keeps local-only files out).
  git -C "$ROOT" add \
    "scv/handoffs/raw/HANDOFF-$hid.md" \
    "scv/decisions/$did.md" \
    "scv/conversations/$did.md" 2>/dev/null || true

  if git -C "$ROOT" diff --cached --quiet 2>/dev/null; then
    echo "ℹ no changes to commit (handoff already up to date): $hid"
  elif git -C "$ROOT" commit -m "handoff($hid): $TITLE" >/dev/null 2>&1; then
    echo "✓ committed handoff to root: $hid"
  else
    echo "⚠ wrote files but commit failed — check git identity in the root repo ($ROOT)."
  fi

  echo "HANDOFF_ID: $hid"
  echo "ROOT: $ROOT"
  echo "FILES:"
  echo "  $hf"
  echo "  $df"
  echo "  $cf"
  echo "PUSH: pending — after explicit user consent, run: handoff.sh push"
}

cmd_push() {
  local ROOT
  ROOT="$(resolve_root)" || die "cannot reach workspace root."
  if git -C "$ROOT" push 2>&1; then
    echo "✓ pushed workspace root."
  else
    die "push failed (check remote/auth). Files remain committed locally in $ROOT."
  fi
}

cmd_list() {
  local FILTER=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --to) FILTER="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  # list is non-network: only what is already synced locally (user pulls explicitly).
  local mode; mode="$(scv_resolve_mode)"
  local d
  if [[ "$mode" == "ROOT" ]]; then
    d="$SCV_DIR/handoffs/raw"            # umbrella: handoffs live in THIS repo
  elif [[ "$mode" == "CHILD" ]]; then
    local ROOT; ROOT="$(scv_root_path)" || return 0
    d="$ROOT/scv/handoffs/raw"
  else
    return 0                              # SINGLE
  fi
  [[ -d "$d" ]] || return 0
  shopt -s nullglob
  local f to st title hid
  for f in "$d"/HANDOFF-*.md; do
    to="$(yaml_get "$f" to_repo)"
    [[ -n "$FILTER" && "$to" != "$FILTER" ]] && continue
    hid="$(yaml_get "$f" handoff_id)"
    st="$(yaml_get "$f" status)"
    title="$(yaml_get "$f" title)"
    echo "$hid|$to|$st|$title"
  done
  shopt -u nullglob
}

cmd_adopt() {
  # Consumer side: scaffold a LOCAL promote folder from an incoming root handoff.
  # Local-only (no root write, no git) — then the user runs /scv:codegen <slug>.
  local HID="" AUTHOR=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --author) AUTHOR="$2"; shift 2 ;;
      -*) die "unknown flag: $1" ;;
      *) HID="$1"; shift ;;
    esac
  done
  [[ -n "$HID" ]] || die "usage: handoff.sh adopt <handoff_id> [--author <name>]"
  [[ "$(scv_resolve_mode)" != "SINGLE" ]] || die "single-repo: nothing to adopt (not a workspace child)."

  local ROOT
  ROOT="$(scv_root_path)" || die "workspace root not synced locally — 'git pull' the root first."
  local hf="$ROOT/scv/handoffs/raw/HANDOFF-$HID.md"
  [[ -f "$hf" ]] || die "handoff not found in synced root: $HID (run /scv:status to see what is synced)."

  local myid to title from
  myid="$(scv_repo_id)"
  to="$(yaml_get "$hf" to_repo)"
  if [[ -n "$myid" && -n "$to" && "$to" != "$myid" ]]; then
    die "handoff $HID is addressed to '$to', not this repo ('$myid')."
  fi
  title="$(yaml_get "$hf" title)"
  from="$(yaml_get "$hf" from_repo)"
  [[ -n "$AUTHOR" ]] || AUTHOR="$(git config user.name 2>/dev/null || echo unknown)"

  local base rest slugpart authslug DATE TODAY localslug dir
  base="${HID%%__to-*}"        # <date>-<from>-<slug>
  rest="${base#*-}"            # <from>-<slug>
  slugpart="${rest#*-}"        # <slug>
  authslug="$(printf '%s' "$AUTHOR" | tr '[:upper:] ' '[:lower:]-')"
  DATE="$(date +%Y%m%d)"; TODAY="$(date +%Y-%m-%d)"
  localslug="${DATE}-${authslug}-${slugpart}"
  dir="${PROMOTE_DIR:-scv/promote}/$localslug"
  [[ -e "$dir" ]] && die "promote folder already exists: $dir"
  mkdir -p "$dir"

  local whatbuild accept
  whatbuild="$(_md_section "$hf" "must build")"
  accept="$(_md_section "$hf" "Acceptance")"

  {
    echo "---"
    echo "title: $title"
    echo "slug: $localslug"
    echo "author: $AUTHOR"
    echo "created_at: $TODAY"
    echo "status: planned"
    echo "refs:"
    echo "  - type: handoff-origin"
    echo "    id: $HID"
    echo "    url: scv/handoffs/raw/HANDOFF-$HID.md"
    echo "---"
    echo ""
    echo "# $title"
    echo ""
    echo "## Summary"
    echo ""
    echo "Corresponding development for workspace handoff \`$HID\` from \`$from\`."
    echo ""
    echo "## Goals / Non-Goals"
    echo ""
    echo "- **Goals**"
    if [[ -n "$whatbuild" ]]; then
      printf '%s\n' "$whatbuild" | sed '/^[[:space:]]*$/d; s/^/  /'
    else
      echo "  - (derive from the handoff)"
    fi
    echo "- **Non-Goals**"
    echo "  - (define what is out of scope)"
    echo ""
    echo "## Approach Overview"
    echo ""
    echo "(to be refined — derived from the handoff spec)"
    echo ""
    echo "## Steps"
    echo ""
    echo "1. (define implementation steps)"
    echo ""
    echo "## Related Documents"
    echo ""
    echo "- Handoff: \`$hf\`"
    echo ""
    echo "## Risks / Open Questions"
    echo ""
    echo "- (any)"
  } > "$dir/PLAN.md"

  {
    echo "# Test Plan — $title"
    echo ""
    echo "## Overview"
    echo ""
    echo "Verifies the corresponding development requested by handoff \`$HID\` from \`$from\`."
    echo ""
    echo "## Test scenarios"
    echo ""
    echo "### T1. Satisfy the handoff acceptance criteria"
    echo ""
    if [[ -n "$accept" ]]; then
      printf '%s\n' "$accept" | sed '/^[[:space:]]*$/d'
    else
      echo "- (derive scenarios from the handoff)"
    fi
    echo ""
    echo "## How to run"
    echo ""
    echo '```bash'
    echo "# TODO: replace with this repo's real test command (kept failing until filled — TDD Red)."
    echo 'echo "define the test command for this handoff"; exit 1'
    echo '```'
    echo ""
    echo "## Pass criteria"
    echo ""
    echo "- All acceptance criteria from handoff \`$HID\` are met."
    echo ""
    echo "## Related Documents"
    echo ""
    echo "- Handoff: \`$hf\`"
  } > "$dir/TESTS.md"

  echo "✓ scaffolded promote from handoff $HID"
  echo "SLUG: $localslug"
  echo "DIR: $dir"
  echo "NEXT: refine $dir/PLAN.md + TESTS.md, then /scv:codegen $localslug (or /scv:work $localslug)"
}

cmd_mark() {
  # Set a handoff's lifecycle status in the root + local commit (push is separate).
  local HID="${1:-}" STATE="${2:-}"
  [[ -n "$HID" && -n "$STATE" ]] || die "usage: handoff.sh mark <handoff_id> <open|claimed|done>"
  case "$STATE" in open|claimed|done) ;; *) die "state must be open|claimed|done" ;; esac

  local mode; mode="$(scv_resolve_mode)"
  [[ "$mode" != "SINGLE" ]] || die "single-repo: no workspace handoffs to mark."
  local ROOT
  if [[ "$mode" == "ROOT" ]]; then
    ROOT="$(pwd)"
  else
    ROOT="$(resolve_root)" || die "cannot reach workspace root."
  fi
  local hf="$ROOT/scv/handoffs/raw/HANDOFF-$HID.md"
  [[ -f "$hf" ]] || die "handoff not found in root: $HID"

  awk -v s="$STATE" 'BEGIN{d=0} /^status:[[:space:]]/ && !d {print "status: " s; d=1; next} {print}' "$hf" > "$hf.tmp" && mv "$hf.tmp" "$hf"

  git -C "$ROOT" add "scv/handoffs/raw/HANDOFF-$HID.md" 2>/dev/null || true
  if git -C "$ROOT" diff --cached --quiet 2>/dev/null; then
    echo "ℹ no change (already $STATE): $HID"
  elif git -C "$ROOT" commit -m "handoff($HID): status → $STATE" >/dev/null 2>&1; then
    echo "✓ marked $HID as $STATE in root"
  else
    echo "⚠ updated file but commit failed — check git identity in the root repo ($ROOT)."
  fi
  echo "PUSH: pending — after explicit user consent, run: handoff.sh push"
}

usage() {
  sed -n '2,20p' "$0"
}

SUB="${1:-}"; shift || true
case "$SUB" in
  write) cmd_write "$@" ;;
  push)  cmd_push "$@" ;;
  list)  cmd_list "$@" ;;
  adopt) cmd_adopt "$@" ;;
  mark)  cmd_mark "$@" ;;
  -h|--help|"") usage ;;
  *) die "unknown subcommand: $SUB (use write|push|list|adopt|mark)" ;;
esac
