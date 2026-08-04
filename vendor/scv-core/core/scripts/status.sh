#!/usr/bin/env bash
# bash 4+ required (associative arrays). macOS ships 3.2 — auto-escalate to brew bash.
if (( BASH_VERSINFO[0] < 4 )); then
  for _b in /opt/homebrew/bin/bash /usr/local/bin/bash; do
    [[ -x "$_b" ]] && exec "$_b" "$0" "$@"
  done
  echo "Error: SCV requires bash 4+. Install via 'brew install bash'." >&2
  exit 1
fi

# status.sh — human-readable SCV project status.
#
# Shows:
#   1. Raw changes since last scv/readpath.json snapshot (added / modified / removed)
#   2. Active plans under scv/promote/
#
# Flags:
#   --ack        After printing diff, overwrite scv/readpath.json with current state
#                (useful to defer /scv:promote without the banner nagging)
#   --verbose    Show every changed path (default: collapse if >10 per bucket)
#
# Exit codes:
#   0 — printed status successfully (regardless of whether changes found)

set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
READPATH="$SCRIPT_DIR/readpath.sh"
# shellcheck source=lib/yaml.sh
source "$SCRIPT_DIR/lib/yaml.sh"
# shellcheck source=lib/env.sh
source "$SCRIPT_DIR/lib/env.sh"
# shellcheck source=lib/attachments.sh
source "$SCRIPT_DIR/lib/attachments.sh"
# shellcheck source=lib/workspace.sh
source "$SCRIPT_DIR/lib/workspace.sh"
# shellcheck source=lib/scvroot.sh
source "$SCRIPT_DIR/lib/scvroot.sh"
# shellcheck source=lib/host-profile.sh
source "$SCRIPT_DIR/lib/host-profile.sh"
env_load 2>/dev/null || true

ACK=0
VERBOSE=0
SCV_TARGET=""

for a in "$@"; do
  case "$a" in
    --ack)     ACK=1 ;;
    --verbose) VERBOSE=1 ;;
    -h|--help)
      sed -n '2,20p' "$0"; exit 0 ;;
    -*) echo "Unknown flag: $a" >&2; exit 1 ;;
    *)
      if [[ -z "$SCV_TARGET" ]] && scv_target_path "$a" >/dev/null 2>&1; then
        SCV_TARGET="$a"
      else
        echo "Unknown arg: $a (expected a module dir like 'FE' that contains scv/)" >&2; exit 1
      fi
      ;;
  esac
done

# Resolve scv/ for this context (optional module target, e.g. `status FE`).
scv_init_paths "$SCV_TARGET"
# Keep the workspace section (below) consistent with the resolved scv root:
# workspace.sh froze WS_INDEX/WS_MANIFEST from SCV_DIR at source time (before
# scv_init_paths re-resolved it), so re-derive them here.
WS_INDEX="$(scv_state_index_path "$SCV_DIR")"
WS_MANIFEST="$SCV_DIR/WORKSPACE.yaml"

PROJECT_PWD="$(pwd)"

echo "──────────────────────────────────────────────────────────────────────"
echo " SCV Status — $PROJECT_PWD"
echo "──────────────────────────────────────────────────────────────────────"
echo ""

# ---------- [1] raw diff ----------

echo "[scv/raw — changes since last index]"

if [[ ! -d "$RAW_DIR" ]]; then
  echo "  (directory does not exist — run /scv:help to check hydrate status)"
else
  FIRST_RUN=0
  [[ ! -f "$STATE_FILE" ]] && FIRST_RUN=1

  DIFF_OUT=$(RAW_DIR="$RAW_DIR" STATE_FILE="$STATE_FILE" bash "$READPATH" diff || true)

  if [[ -z "$DIFF_OUT" ]]; then
    echo "  no changes since last index."
  else
    if [[ $FIRST_RUN -eq 1 ]]; then
      echo "  (first run — no scv/readpath.json yet; treating all raw files as NEW)"
    fi

    # Count + render each bucket
    A_LINES=$(printf '%s\n' "$DIFF_OUT" | grep -E '^A	' || true)
    M_LINES=$(printf '%s\n' "$DIFF_OUT" | grep -E '^M	' || true)
    R_LINES=$(printf '%s\n' "$DIFF_OUT" | grep -E '^R	' || true)
    A_N=$( [[ -z "$A_LINES" ]] && echo 0 || printf '%s\n' "$A_LINES" | wc -l )
    M_N=$( [[ -z "$M_LINES" ]] && echo 0 || printf '%s\n' "$M_LINES" | wc -l )
    R_N=$( [[ -z "$R_LINES" ]] && echo 0 || printf '%s\n' "$R_LINES" | wc -l )

    render_bucket() {
      local label="$1" lines="$2" count="$3" formatter="$4"
      echo "  $label $count"
      [[ $count -eq 0 ]] && return
      local shown=0
      local limit=10
      [[ $VERBOSE -eq 1 ]] && limit=1000000
      while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        shown=$((shown+1))
        if [[ $shown -gt $limit ]]; then
          local rest=$((count - limit))
          echo "    … (+$rest more — rerun with --verbose to see all)"
          break
        fi
        "$formatter" "$line"
      done <<< "$lines"
    }

    fmt_A() {
      local p s m
      IFS=$'\t' read -r _ p s m <<< "$1"
      printf '    · %s  (%s bytes)\n' "$p" "$s"
    }
    fmt_M() {
      local p os ns om nm
      IFS=$'\t' read -r _ p os ns om nm <<< "$1"
      printf '    · %s  (%s → %s bytes)\n' "$p" "$os" "$ns"
    }
    fmt_R() {
      local p s m
      IFS=$'\t' read -r _ p s m <<< "$1"
      printf '    · %s  (was %s bytes)\n' "$p" "$s"
    }

    render_bucket "+ added   :" "$A_LINES" "$A_N" fmt_A
    render_bucket "* modified:" "$M_LINES" "$M_N" fmt_M
    render_bucket "- removed :" "$R_LINES" "$R_N" fmt_R

    echo ""
    echo "  → Review & refine : /scv:promote"
    echo "  → Or defer        : /scv:status --ack   (marks current state as baseline)"
  fi

  # ---------- raw lifecycle: unused vs consumed (scv/raw/stale) ----------
  # unused  = never consumed by any promote (lives outside scv/raw/stale/)
  # consumed = moved to scv/raw/stale/ by promote Step 8, with ref_docs
  #            provenance (which slugs used it) in scv/readpath.json

  UNUSED_LIST=$(RAW_DIR="$RAW_DIR" STATE_FILE="$STATE_FILE" bash "$READPATH" unused 2>/dev/null || true)
  UNUSED_N=$( [[ -z "$UNUSED_LIST" ]] && echo 0 || printf '%s\n' "$UNUSED_LIST" | grep -c . )
  REFS_OUT=$(RAW_DIR="$RAW_DIR" STATE_FILE="$STATE_FILE" bash "$READPATH" refs 2>/dev/null || true)
  REFS_N=$( [[ -z "$REFS_OUT" ]] && echo 0 || printf '%s\n' "$REFS_OUT" | grep -c . )

  echo ""
  echo "  unused (never promoted): $UNUSED_N"
  if [[ $UNUSED_N -gt 0 ]]; then
    shown=0; limit=10; [[ $VERBOSE -eq 1 ]] && limit=1000000
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      shown=$((shown+1))
      if [[ $shown -gt $limit ]]; then
        echo "    … (+$((UNUSED_N - limit)) more — rerun with --verbose to see all)"
        break
      fi
      echo "    · $line"
    done <<< "$UNUSED_LIST"
  fi
  echo "  consumed (scv/raw/stale): $REFS_N"
  if [[ $REFS_N -gt 0 ]]; then
    shown=0; limit=5; [[ $VERBOSE -eq 1 ]] && limit=1000000
    while IFS=$'\t' read -r p slugs _cmt _at; do
      [[ -z "$p" ]] && continue
      shown=$((shown+1))
      if [[ $shown -gt $limit ]]; then
        echo "    … (+$((REFS_N - limit)) more — rerun with --verbose to see all)"
        break
      fi
      echo "    · $p  ← ${slugs:-?}"
    done <<< "$REFS_OUT"

    # Content staleness — consumed docs mentioning files changed since their
    # ref_commit. Heuristic; semantic verification happens in /scv:promote.
    OUTDATED_OUT=$(RAW_DIR="$RAW_DIR" STATE_FILE="$STATE_FILE" bash "$READPATH" outdated 2>/dev/null || true)
    OC_LINES=$(printf '%s\n' "$OUTDATED_OUT" | grep -E '^OUTDATED-CANDIDATE	' || true)
    if [[ -n "$OC_LINES" ]]; then
      OC_N=$(printf '%s\n' "$OC_LINES" | grep -c .)
      echo "  outdated candidates: $OC_N  (mention files changed since consumption)"
      while IFS=$'\t' read -r _ p hint; do
        [[ -z "$p" ]] && continue
        echo "    ! $p  ($hint)"
      done <<< "$OC_LINES"
      echo "    → verify against current code before reusing these docs"
    fi
  fi

  if [[ $ACK -eq 1 ]]; then
    echo ""
    echo "[--ack] updating $STATE_FILE ..."
    RAW_DIR="$RAW_DIR" STATE_FILE="$STATE_FILE" bash "$READPATH" update
  fi
fi

echo ""

# ---------- [2] promote plans ----------

echo "[scv/promote — active plans]"

if [[ ! -d "$PROMOTE_DIR" ]]; then
  echo "  (directory does not exist)"
else
  count=0
  # Flat .md files (legacy / simple plans)
  for f in "$PROMOTE_DIR"/*.md; do
    [[ -f "$f" ]] || continue
    count=$((count+1))
    echo "  · $f"
  done
  # Directory-based plans — prefer PLAN.md, fall back to index.md
  for d in "$PROMOTE_DIR"/*/; do
    [[ -d "$d" ]] || continue
    if [[ -f "${d}PLAN.md" ]]; then
      count=$((count+1))
      echo "  · ${d}PLAN.md"
    elif [[ -f "${d}index.md" ]]; then
      count=$((count+1))
      echo "  · ${d}index.md"
    fi
  done
  [[ $count -eq 0 ]] && echo "  (empty)"
fi

echo ""

# ---------- [3] docs graph ----------

echo "[docs graph (graphify skill)]"
# Skill presence
GRAPHIFY_SKILL="missing"
scv_graph_skill_available && GRAPHIFY_SKILL="available"
# Graph status
if [[ "$GRAPHIFY_SKILL" == "missing" ]]; then
  echo "  skill not installed — /scv:promote will run without graph optimization"
else
  GRAPH_DIR=".graphify/docs/graphify-out"
  if [[ ! -d "$GRAPH_DIR" ]]; then
    echo "  status: missing  — /scv:promote will build on first run"
  elif [[ ! -f "$STATE_FILE" ]]; then
    echo "  status: built    (no readpath baseline yet)"
  else
    # BSD/GNU portable mtime in epoch seconds.
    graph_mt=$(stat -c %Y "$GRAPH_DIR" 2>/dev/null || stat -f %m "$GRAPH_DIR" 2>/dev/null || echo 0)
    state_mt=$(stat -c %Y "$STATE_FILE" 2>/dev/null || stat -f %m "$STATE_FILE" 2>/dev/null || echo 0)
    if [[ "$graph_mt" -ge "$state_mt" ]]; then
      echo "  status: built    (up to date with readpath baseline)"
    else
      echo "  status: stale    — /scv:promote will auto-refresh"
    fi
  fi
fi

echo ""

# ---------- [4] archive ----------

echo "[scv/archive — completed plans]"

if [[ ! -d "$ARCHIVE_DIR" ]]; then
  echo "  (directory does not exist)"
else
  archived=0
  for d in "$ARCHIVE_DIR"/*/; do
    [[ -d "$d" ]] || continue
    archived=$((archived+1))
  done
  if [[ $archived -eq 0 ]]; then
    echo "  (empty — no plans archived yet)"
  else
    echo "  $archived entry(ies)"
  fi
fi

echo ""

# ---------- [5] epic progress ----------
# Aggregate every PLAN.md under archive + promote by `epic:` field.
# Reports per-epic counters: archived (kind=feature), in promote (kind=feature),
# refactor status (any kind=refactor present?), retirement count (kind=retirement).
# Skips plans without epic.

echo "[epics — progress]"

declare -A EPIC_FEAT_ARCHIVED=()
declare -A EPIC_FEAT_PROMOTE=()
declare -A EPIC_REFACTOR_ARCHIVED=()
declare -A EPIC_REFACTOR_PROMOTE=()
declare -A EPIC_RETIREMENT_DONE=()
declare -A EPIC_SLUGS=()

scan_plan() {
  local plan="$1" loc="$2"
  [[ -f "$plan" ]] || return
  local epic kind
  epic=$(yaml_get "$plan" epic)
  [[ -z "$epic" ]] && return
  kind=$(yaml_get "$plan" kind)
  [[ -z "$kind" ]] && kind="feature"
  EPIC_SLUGS["$epic"]=1
  case "$kind:$loc" in
    feature:archive)    EPIC_FEAT_ARCHIVED["$epic"]=$((${EPIC_FEAT_ARCHIVED["$epic"]:-0}+1)) ;;
    feature:promote)    EPIC_FEAT_PROMOTE["$epic"]=$((${EPIC_FEAT_PROMOTE["$epic"]:-0}+1)) ;;
    refactor:archive)   EPIC_REFACTOR_ARCHIVED["$epic"]=$((${EPIC_REFACTOR_ARCHIVED["$epic"]:-0}+1)) ;;
    refactor:promote)   EPIC_REFACTOR_PROMOTE["$epic"]=$((${EPIC_REFACTOR_PROMOTE["$epic"]:-0}+1)) ;;
    retirement:archive) EPIC_RETIREMENT_DONE["$epic"]=$((${EPIC_RETIREMENT_DONE["$epic"]:-0}+1)) ;;
  esac
}

shopt -s nullglob
for d in "$ARCHIVE_DIR"/*/; do scan_plan "${d}PLAN.md" "archive"; done
for d in "$PROMOTE_DIR"/*/; do scan_plan "${d}PLAN.md" "promote"; done
shopt -u nullglob

if [[ ${#EPIC_SLUGS[@]} -eq 0 ]]; then
  echo "  (no epics — no PLAN.md frontmatter has 'epic:' field)"
else
  # Sort epic slugs for stable output
  for epic in $(printf '%s\n' "${!EPIC_SLUGS[@]}" | LC_ALL=C sort); do
    feat_arc=${EPIC_FEAT_ARCHIVED["$epic"]:-0}
    feat_prm=${EPIC_FEAT_PROMOTE["$epic"]:-0}
    feat_total=$((feat_arc + feat_prm))
    refac_arc=${EPIC_REFACTOR_ARCHIVED["$epic"]:-0}
    refac_prm=${EPIC_REFACTOR_PROMOTE["$epic"]:-0}
    ret_done=${EPIC_RETIREMENT_DONE["$epic"]:-0}

    # State summary
    state=""
    if [[ $feat_prm -gt 0 ]]; then
      state="${feat_arc}/${feat_total} archived, ${feat_prm} in promote"
    else
      state="${feat_arc}/${feat_total} archived"
    fi
    if [[ $refac_arc -gt 0 ]]; then
      state="${state}, refactor done"
    elif [[ $refac_prm -gt 0 ]]; then
      state="${state}, refactor in progress"
    elif [[ $feat_arc -gt 0 && $feat_prm -eq 0 ]]; then
      state="${state}, refactor pending"
    fi
    if [[ $ret_done -gt 0 ]]; then
      state="${state}, ${ret_done} retirement"
    fi

    # Status icon
    icon="·"
    if [[ $refac_arc -gt 0 && $feat_prm -eq 0 ]]; then
      icon="✓"     # epic complete (all features archived + refactor done)
    elif [[ $feat_prm -gt 0 || $refac_prm -gt 0 ]]; then
      icon="…"     # in progress
    elif [[ $feat_arc -gt 0 && $refac_arc -eq 0 ]]; then
      icon="!"     # features all archived but refactor pending
    fi
    echo "  $icon epic $epic: $state"
  done
fi

echo ""

# ---------- [6] PR attachments (orphan branch storage) ----------
echo "[scv-attachments — PR media storage]"
backend="${SCV_ATTACHMENTS_BACKEND:-git-orphan}"
retention="${SCV_ATTACHMENTS_RETENTION_DAYS:-3}"
echo "  backend: $backend · retention: ${retention} day(s)"
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  status_line=$(attachments_status 2>/dev/null || echo "active=? stale=? total_size_bytes=?")
  active=$(printf '%s' "$status_line" | sed -n 's/.*active=\([^ ]*\).*/\1/p')
  stale=$(printf '%s' "$status_line" | sed -n 's/.*stale=\([^ ]*\).*/\1/p')
  total=$(printf '%s' "$status_line" | sed -n 's/.*total_size_bytes=\([0-9]*\).*/\1/p')
  total_mb="?"
  if [[ -n "$total" && "$total" =~ ^[0-9]+$ ]]; then
    total_mb=$((total / 1024 / 1024))MB
  fi
  echo "  active: ${active:-?} entries · stale: ${stale:-?} · total: $total_mb"
else
  echo "  (not in a git repo — skipped)"
fi

echo ""

# ---------- [7] workspace handoffs (multi-repo) ----------
# Additive + gated: printed only in a nested workspace (ROOT/CHILD). A plain
# single repo never enters this block, so its [1]..[6] output is byte-identical.
# Non-network: shows only handoffs already synced locally (user pulls explicitly).
if scv_is_multi; then
  echo "[scv workspace — cross-repo handoffs]"
  wsmode="$(scv_resolve_mode)"
  if [[ "$wsmode" == "ROOT" ]]; then
    # Umbrella: handoffs live in THIS repo — show a coordination overview.
    echo "  mode: ROOT (umbrella) · workspace: $(scv_workspace)"
    all="$("$SCRIPT_DIR/handoff.sh" list 2>/dev/null)"
    if [[ -n "$all" ]]; then
      n=$(printf '%s\n' "$all" | grep -c .)
      summary="$(printf '%s\n' "$all" | awk -F'|' 'NF{c[$3]++} END{printf "open %d · claimed %d · done %d", c["open"]+0, c["claimed"]+0, c["done"]+0}')"
      echo "  handoffs ($n) — $summary"
      echo "  per target repo:"
      printf '%s\n' "$all" | awk -F'|' 'NF{c[$2]++} END{for(r in c) printf "    → %s: %d\n", r, c[r]}' | sort
      while IFS='|' read -r hid to st title; do
        [[ -z "$hid" ]] && continue
        echo "    · [$st → $to] $hid"
        echo "        $title"
      done <<< "$all"
      echo "  (each child repo pulls this umbrella, then /scv:promote → /scv:codegen)"
    else
      echo "  no handoffs yet."
    fi
  else
    # Child: show handoffs addressed to me (requires the external root synced locally).
    myid="$(scv_repo_id)"; myid="${myid:-?}"
    echo "  mode: CHILD · repo_id: $myid · root: $(scv_root)"
    if scv_root_reachable; then
      incoming="$("$SCRIPT_DIR/handoff.sh" list --to "$myid" 2>/dev/null)"
      if [[ -n "$incoming" ]]; then
        n=$(printf '%s\n' "$incoming" | grep -c .)
        echo "  incoming ($n) — corresponding dev requested of this repo:"
        while IFS='|' read -r hid _to st title; do
          [[ -z "$hid" ]] && continue
          echo "    · [$st] $hid"
          echo "        $title"
        done <<< "$incoming"
        echo "  → adopt one: /scv:promote (handoff) then /scv:codegen"
      else
        echo "  no incoming handoffs addressed to '$myid'."
      fi
    else
      echo "  (workspace root not synced locally — 'git pull' the root, or check root: path)"
    fi
  fi
  echo ""
fi
