#!/usr/bin/env bash
# Self-onboarding output for the SCV plugin.
# Prints: overview, skill list, current project diagnosis, next action.
set -uo pipefail

VERBOSE=0
HAS_CONTEXT=0
# v0.9.0+: collect non-flag args as the "conversation argument" (free-form text
# the user typed after /scv:help). If empty, /scv:help runs in diagnosis mode.
# If non-empty, /scv:help enters conversation mode (the help protocol handles).
CONV_ARG=""
for a in "$@"; do
  case "$a" in
    --verbose|-v) VERBOSE=1 ;;
    --with-context) HAS_CONTEXT=1 ;;
    *) HAS_CONTEXT=1; CONV_ARG="${CONV_ARG:+$CONV_ARG }$a" ;;
  esac
done

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# Resolve the installed plugin from this script. Claude Code does not guarantee a
# plugin-root environment variable for skill execution.
PLUGIN_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Multi-repo workspace awareness (no-op / silent for single repos).
# shellcheck source=lib/workspace.sh
source "$SCRIPT_DIR/lib/workspace.sh"
# shellcheck source=lib/scvroot.sh
source "$SCRIPT_DIR/lib/scvroot.sh"
# Help is usually the first action a session runs, so it is the first honest
# chance to close a template-version gap (see scv_autosync's header). It does
# not use scv_init_paths, hence the explicit call.
scv_autosync "$(scv_root_dir)"
# shellcheck source=lib/host-profile.sh
source "$SCRIPT_DIR/lib/host-profile.sh"

# Emit only control-plane context for normal host use. Direct argv callers keep
# the legacy echo for compatibility, but template-string adapters pass the
# fixed --with-context flag and retain raw text solely in prompt data.
if [[ $HAS_CONTEXT -eq 1 ]]; then
  echo "ARG_CONTEXT: provided"
else
  echo "ARG_CONTEXT: none"
fi
if [[ -n "$CONV_ARG" ]]; then
  echo "ARG_CONVERSATION: ${CONV_ARG}"
elif [[ $HAS_CONTEXT -eq 1 ]]; then
  echo "ARG_CONVERSATION: (provided by host prompt)"
else
  echo "ARG_CONVERSATION:"
fi

# Unfinished conversations = active files in scv/conversations/ (NOT under archive/).
# v0.9.0+: persisted by /scv:help conversation mode.
# v0.22.0+: the directory is COMMITTED (redaction-filtered) — the pre-0.22.0
# gitignored scv/.conversations/ is detected below for migration.
CONV_DIR="scv/conversations"

# The helper is strictly read-only, including argument-bearing diagnosis. The
# host protocol creates a conversation file only after the user explicitly
# chooses to start or resume one.
if [[ -d "$CONV_DIR" ]]; then
  # Top-level *.md only, excluding the safety README that v0.9.2+ auto-creates.
  UNFINISHED=$(find "$CONV_DIR" -maxdepth 1 -type f -name '*.md' \
                 ! -name 'README.md' 2>/dev/null | sort)
else
  UNFINISHED=""
fi
if [[ -n "$UNFINISHED" ]]; then
  echo "UNFINISHED_CONVERSATIONS:"
  printf '  %s\n' $UNFINISHED
else
  echo "UNFINISHED_CONVERSATIONS: (none)"
fi

# v0.22.0+ — legacy gitignored conversation dir detection (read-only). The
# help protocol proposes migrating these files (through the redaction filter)
# into the committed scv/conversations/.
LEGACY_CONV_DIR="scv/.conversations"
if [[ -d "$LEGACY_CONV_DIR" ]]; then
  LEGACY_CONV_N=$(find "$LEGACY_CONV_DIR" -type f -name '*.md' \
                    ! -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')
  echo "LEGACY_CONVERSATIONS: $LEGACY_CONV_DIR (${LEGACY_CONV_N:-0} file(s)) — migration to scv/conversations/ recommended"
else
  echo "LEGACY_CONVERSATIONS: (none)"
fi
echo ""

# v0.10.0+: archive index for retrospective queries.
# Emitted only when the host reports conversation context. The help protocol
# classifies the prompt argument as "future-leaning" (build
# something new — Mode B) vs "retrospective" (find / show past work — Mode B').
# For retrospective intent it uses this index + targeted grep on PLAN.md to
# answer; future-leaning ignores the index entirely.
ARCHIVE_DIR="scv/archive"
if [[ $HAS_CONTEXT -eq 1 ]]; then
  if [[ -d "$ARCHIVE_DIR" ]]; then
    # Newest archives first, capped at 30 entries to keep prompt size bounded.
    echo "ARCHIVE_INDEX:"
    found_any=0
    # v0.11.0+ — INDEX.yaml fast path (frontmatter-only, no PLAN.md body reads).
    # Falls back to per-folder PLAN.md scan when INDEX is absent.
    index_file="$ARCHIVE_DIR/INDEX.yaml"
    if [[ -f "$index_file" ]]; then
      # Parse INDEX entries; derive created date from slug's YYYYMMDD prefix.
      INDEX_OUT=$(awk '
        function print_entry() {
          created = substr(slug, 1, 4) "-" substr(slug, 5, 2) "-" substr(slug, 7, 2)
          printf "  %s | %s | %s\n", slug, (title == "" ? "<no title>" : title), created
        }
        /^  - slug:/ {
          if (slug != "") print_entry()
          slug = $3; title = ""
          next
        }
        /^    title:/ {
          line = $0
          sub(/^[[:space:]]*title:[[:space:]]*"?/, "", line)
          sub(/"$/, "", line)
          title = line
        }
        END { if (slug != "") print_entry() }
      ' "$index_file" | sort -r | head -30)
      if [[ -n "$INDEX_OUT" ]]; then
        printf '%s\n' "$INDEX_OUT"
        found_any=1
      fi
    else
      while IFS= read -r dir; do
        [[ -z "$dir" ]] && continue
        folder=$(basename "$dir")
        plan="$dir/PLAN.md"
        if [[ -f "$plan" ]]; then
          title=$(grep -m1 '^title:' "$plan" 2>/dev/null \
            | sed 's/^title:[[:space:]]*//; s/^["'"'"']//; s/["'"'"']$//')
          created=$(grep -m1 '^created_at:' "$plan" 2>/dev/null \
            | sed 's/^created_at:[[:space:]]*//')
          printf '  %s | %s | %s\n' "$folder" "${title:-<no title>}" "${created:-<no date>}"
        else
          printf '  %s | <no PLAN.md>\n' "$folder"
        fi
        found_any=1
      done < <(find "$ARCHIVE_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
                | sort -r | head -30)
    fi
    if [[ "$found_any" -eq 0 ]]; then
      echo "  (empty)"
    fi
  else
    echo "ARCHIVE_INDEX: (no archive yet)"
  fi
  echo ""
fi

# --- Fixed overview (always shown) -------------------------------------------
cat <<'EOF'
╔══════════════════════════════════════════════════════════════════════╗
║  SCV — Standard · Cowork · Verify                                     ║
╚══════════════════════════════════════════════════════════════════════╝

Core idea (S·C·V)
  S  Standard — one shared plan grammar: PLAN + TESTS per promote folder
  C  Cowork   — drop into scv/raw, promote to scv/promote/ for team handoff
  V  Verify   — implement → E2E → Slack/Discord report each Phase

Workflow
  ① hydrate         → copy the empty template into the project
  ② .env setup      → NOTIFIER_PROVIDER=slack|discord, tokens/channels
  ③ scv/raw/        → drop existing material (notes, sketches, PDFs) — optional
  ④ /scv:promote    → raw → scv/promote/<YYYYMMDD>-<author>-<slug>/ (PLAN + TESTS)
  ⑤ /scv:work       → implement · test · move to archive on pass
  (opt) loop harness → external template (copy loop-runner.md → <host-config>/loop-template.md)
  (opt) /scv:regression → periodic / pre-release accumulated regression. Optional pre-flight before ⑤'s archive too.

Skills
  /scv:help       This screen (current state + next step)
  /scv:status     scv/raw/ change detection + active promote plans + graph status
  /scv:promote    scv/raw/ → scv/promote/<YYYYMMDD>-<author>-<slug>/ + graph refresh
  /scv:work       Implement promote plan → test → optionally archive
  /scv:codegen    TDD-first variant of /scv:work — TESTS drives code (Red→Green per case)
  /scv:regression Run accumulated archived regression + auto-skip supersedes/obsolete + failure triage
  /scv:report     Phase report to Slack/Discord (with artifacts)
  /scv:sync       Safe merge on template version bump
  /scv:workspace  Multi-repo setup: join an umbrella / create a root / detach (interactive, no flags)
  /scv:handoff    Multi-repo: declare another repo needs corresponding dev (→ root scv repo)
  action:routine    Run a named maintenance routine from scv/routines/ (--list to enumerate)
  /scv:update     Claude Code marketplace update guide
  /scv:set-models Explain Claude Code session-level model selection compatibility

EOF

# --- Raw change banner (quick read of scv/readpath.json) ---------------------
# Only show when there are changes and readpath.sh is present.
READPATH_SH="$PLUGIN_ROOT/scripts/readpath.sh"
if [[ -x "$READPATH_SH" ]] && [[ -d "scv/raw" ]]; then
  COUNTS=$(bash "$READPATH_SH" status-counts 2>/dev/null || true)
  # parses "added=N modified=N removed=N total=N"
  TOTAL=$(printf '%s' "$COUNTS" | sed -n 's/.*total=\([0-9]*\).*/\1/p')
  TOTAL=${TOTAL:-0}
  if [[ "$TOTAL" -gt 0 ]]; then
    ADDED=$(printf '%s' "$COUNTS" | sed -n 's/.*added=\([0-9]*\).*/\1/p')
    MODIFIED=$(printf '%s' "$COUNTS" | sed -n 's/.*modified=\([0-9]*\).*/\1/p')
    REMOVED=$(printf '%s' "$COUNTS" | sed -n 's/.*removed=\([0-9]*\).*/\1/p')
    echo ""
    echo "[scv/raw] ${ADDED:-0} added · ${MODIFIED:-0} modified · ${REMOVED:-0} removed → /scv:status or /scv:promote"
  fi
  # Lifecycle summary: docs still outside scv/raw/stale/ were never consumed
  # by any promote — surface them even when the change-window diff is quiet.
  LC_COUNTS=$(bash "$READPATH_SH" lifecycle-counts 2>/dev/null || true)
  UNUSED=$(printf '%s' "$LC_COUNTS" | sed -n 's/.*unused=\([0-9]*\).*/\1/p')
  UNUSED=${UNUSED:-0}
  if [[ "$UNUSED" -gt 0 ]]; then
    echo "[scv/raw] ${UNUSED} doc(s) never promoted (outside scv/raw/stale/) → /scv:status for the list"
  fi
fi

# --- Dynamic diagnosis of current project ------------------------------------
PROJECT_PWD="$(pwd)"
echo "──────────────────────────────────────────────────────────────────────"
echo " Current project diagnosis ($PROJECT_PWD)"
echo "──────────────────────────────────────────────────────────────────────"

# --- Pre-flight banner: surface missing core deps immediately (v0.11.5+) -----
# Without this, dependency issues only showed up below the hydration/.env block,
# so first-time users on Ubuntu/Alpine without curl/jq could miss them.
_scv_pre_probe_missing=()
for _cmd in git gh curl jq; do
  command -v "$_cmd" >/dev/null 2>&1 || _scv_pre_probe_missing+=("$_cmd")
done
if [[ ${#_scv_pre_probe_missing[@]} -gt 0 ]]; then
  echo
  echo "  ⚠  Missing dependencies: ${_scv_pre_probe_missing[*]}"
  echo "     Run '/scv:install-deps' for OS-specific install commands."
  echo "     (Detailed check appears below.)"
  echo
fi
unset _scv_pre_probe_missing _cmd

HYDRATED=0
STATE_CONFLICT=0
STATE_POINTER_BROKEN=0
ENV_SET=0
RAW_COUNT=0

# Hydration check. A wrapper-declared legacy index is accepted for reads until
# its adapter migrates the project to the shared SCV.md index.
SCV_INDEX_PATH="$(scv_state_index_path scv)"
SCV_INDEX_CONFLICTS="$(scv_state_index_conflicts scv)"
SCV_BROKEN_POINTERS="$(scv_state_index_broken_pointers scv)"
if [[ -n "$SCV_BROKEN_POINTERS" ]]; then
  STATE_POINTER_BROKEN=1
  STATE_CONFLICT=1
  echo "STATE_INDEX_BROKEN_POINTER:"
  printf '  %s\n' "$SCV_BROKEN_POINTERS"
fi
if [[ -n "$SCV_INDEX_CONFLICTS" ]]; then
  STATE_CONFLICT=1
  echo "STATE_INDEX_CONFLICT:"
  printf '  %s\n' "$SCV_INDEX_CONFLICTS"
fi
if [[ -f "$SCV_INDEX_PATH" && -f "scv/PROMOTE.md" ]]; then
  HYDRATED=1
  echo "  [✓] hydrate complete ($SCV_INDEX_PATH + scv/PROMOTE.md exist)"
else
  echo "  [✗] hydrate not done ($SCV_INDEX_PATH / scv/PROMOTE.md missing)"
fi

# .env check
if [[ -f ".env" ]]; then
  if grep -q "^NOTIFIER_PROVIDER=" .env 2>/dev/null; then
    prov=$(grep "^NOTIFIER_PROVIDER=" .env | head -1 | cut -d= -f2)
    token_ok=0
    case "$prov" in
      slack)   grep -q "^SLACK_BOT_TOKEN=xoxb-" .env 2>/dev/null && token_ok=1 ;;
      discord) grep -q "^DISCORD_BOT_TOKEN=.\+" .env 2>/dev/null && ! grep -q "^DISCORD_BOT_TOKEN=REPLACE" .env && token_ok=1 ;;
    esac
    if [[ $token_ok -eq 1 ]]; then
      ENV_SET=1
      echo "  [✓] .env configured (NOTIFIER_PROVIDER=$prov, token present)"
    else
      echo "  [△] .env present but token unset (NOTIFIER_PROVIDER=$prov)"
    fi
  else
    echo "  [△] .env present but NOTIFIER_PROVIDER missing"
  fi
elif [[ -f ".env.example.scv" ]]; then
  echo "  [✗] .env missing — run 'cp .env.example.scv .env' (or 'cat .env.example.scv >> .env' to append) and fill in values"
else
  echo "  [✗] .env.example.scv also missing (hydrate required)"
fi

# --- Dependency check (v0.5.1+) ----------------------------------------------
# Detects external CLI tools SCV uses. `required` = breaks core flows when
# missing. `recommended` = breaks one platform/feature. `optional` = graceful
# degrade (SCV still works, just without that feature).
DEP_MISSING_HARD=()
DEP_MISSING_SOFT=()
echo "  Dependency check:"

_scv_check_dep() {
  local cmd="$1" tier="$2" desc="$3"
  if command -v "$cmd" >/dev/null 2>&1; then
    printf '    [✓] %-8s — %s\n' "$cmd" "$desc"
    return
  fi
  case "$tier" in
    required|recommended)
      printf '    [✗] %-8s — %s\n' "$cmd" "$desc"
      DEP_MISSING_HARD+=("$cmd")
      ;;
    optional)
      printf '    [△] %-8s — %s (optional, graceful degrade)\n' "$cmd" "$desc"
      DEP_MISSING_SOFT+=("$cmd")
      ;;
  esac
}

_scv_check_dep git     required    "git operations (core)"
_scv_check_dep gh      recommended "GitHub PR auto-create (SCV_PR_PLATFORM=github)"
_scv_check_dep glab    recommended "GitLab MR auth (preferred over GITLAB_TOKEN .env)"
_scv_check_dep curl    recommended "GitLab MR + Slack/Discord HTTP"
_scv_check_dep jq      recommended "JSON parsing for GitLab MR + Notifier"
_scv_check_dep ffmpeg  optional    "PR video → GIF inline preview"
_scv_check_dep python3 optional    "attachments_status cache parsing"
unset -f _scv_check_dep

# graphify (Claude Code skill — different distribution channel than system CLIs)
GRAPHIFY_PRESENT=0
scv_graph_skill_available && GRAPHIFY_PRESENT=1
if [[ $GRAPHIFY_PRESENT -eq 1 ]]; then
  printf '    [✓] %-8s — %s\n' "graphify" 'Claude Code skill — token-efficient graph queries (/scv:promote, /scv:work)'
else
  printf '    [△] %-8s — %s (optional, graceful degrade)\n' "graphify" "Claude Code skill — token-efficient graph queries"
  echo "        Install: https://github.com/safishamsi/graphify"
fi

if [[ ${#DEP_MISSING_HARD[@]} -gt 0 || ${#DEP_MISSING_SOFT[@]} -gt 0 ]]; then
  ALL_MISSING=("${DEP_MISSING_HARD[@]}" "${DEP_MISSING_SOFT[@]}")
  echo "    Install hint: run '/scv:install-deps' for OS-specific commands, or:"
  echo "      macOS:          brew install ${ALL_MISSING[*]}"
  echo "      Debian/Ubuntu:  sudo apt install ${ALL_MISSING[*]}"
  if printf '%s\n' "${ALL_MISSING[@]}" | grep -qx gh; then
    echo "    (gh on Debian/Ubuntu needs the GitHub apt repo — see https://github.com/cli/cli/blob/trunk/docs/install_linux.md)"
  fi
  if printf '%s\n' "${ALL_MISSING[@]}" | grep -qx glab; then
    echo "    (glab — install via https://gitlab.com/gitlab-org/cli/-/blob/main/docs/installation.md, then run 'glab auth login')"
  fi
fi

# Raw inventory
if [[ -d "scv/raw" ]]; then
  RAW_COUNT=$(find scv/raw -type f ! -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')
  if [[ "$RAW_COUNT" -gt 0 ]]; then
    echo "  [i] scv/raw has $RAW_COUNT item(s) — consider /scv:promote to refine"
  fi
fi

# Raw changes since last index (reuses readpath.sh earlier banner logic)
RAW_CHANGES_TOTAL=0
if [[ -x "$READPATH_SH" && -d "scv/raw" ]]; then
  COUNTS2=$(bash "$READPATH_SH" status-counts 2>/dev/null || true)
  RAW_CHANGES_TOTAL=$(printf '%s' "$COUNTS2" | sed -n 's/.*total=\([0-9]*\).*/\1/p')
  RAW_CHANGES_TOTAL=${RAW_CHANGES_TOTAL:-0}
fi

# Active promote plans (dir-based with PLAN.md)
ACTIVE_PLANS=()
if [[ -d "scv/promote" ]]; then
  for d in scv/promote/*/; do
    [[ -d "$d" && -f "${d}PLAN.md" ]] || continue
    ACTIVE_PLANS+=("$(basename "$d")")
  done
fi
if [[ ${#ACTIVE_PLANS[@]} -gt 0 ]]; then
  echo "  [i] scv/promote has ${#ACTIVE_PLANS[@]} active plan(s): ${ACTIVE_PLANS[0]}${ACTIVE_PLANS[1]+ …}"
fi

# Archive count (info-only)
ARCHIVED_COUNT=0
if [[ -d "scv/archive" ]]; then
  for d in scv/archive/*/; do
    [[ -d "$d" ]] && ARCHIVED_COUNT=$((ARCHIVED_COUNT+1))
  done
  if [[ "$ARCHIVED_COUNT" -gt 0 ]]; then
    echo "  [i] scv/archive has $ARCHIVED_COUNT completed plan(s) stored"
  fi
fi

# Workspace (multi-repo nesting). Silent for single repos → single-repo output
# stays byte-identical. WS_MODE / WS_INCOMING are reused by Recommended next action.
WS_MODE="$(scv_resolve_mode 2>/dev/null || echo SINGLE)"
WS_INCOMING=0
if [[ "$WS_MODE" == "CHILD" ]]; then
  WS_ID="$(scv_repo_id)"
  echo "  [i] Workspace: CHILD · repo_id: ${WS_ID:-?} · role: $(scv_role) · root: $(scv_root)"
  if scv_root_reachable; then
    WS_INCOMING=$("$SCRIPT_DIR/handoff.sh" list --to "$WS_ID" 2>/dev/null | grep -c '^' || true)
    echo "      incoming handoffs addressed to this repo: $WS_INCOMING"
  else
    echo "      (workspace root not synced locally — 'git pull' the root to see handoffs)"
  fi
elif [[ "$WS_MODE" == "ROOT" ]]; then
  WS_MEMBERS=$(grep -cE '^[[:space:]]*-[[:space:]]*id:' "$WS_MANIFEST" 2>/dev/null || echo 0)
  WS_OPEN=$(find scv/handoffs/raw -name 'HANDOFF-*.md' 2>/dev/null | wc -l | tr -d ' ')
  echo "  [i] Workspace: ROOT (umbrella) · members: $WS_MEMBERS · handoffs: ${WS_OPEN:-0}"
fi

echo ""
echo "──────────────────────────────────────────────────────────────────────"
echo " Recommended next action"
echo "──────────────────────────────────────────────────────────────────────"

# --- Recommend next step based on state --------------------------------------
if [[ $STATE_POINTER_BROKEN -eq 1 ]]; then
  cat <<'EOF'
  State-index pointer is broken. Read-only diagnosis is available, but SCV
  will not hydrate, sync, migrate, or recreate state automatically.
  Restore scv/SCV.md or restore the legacy state file from its backup.
EOF
elif [[ $STATE_CONFLICT -eq 1 ]]; then
  cat <<'EOF'
  State-index conflict detected. Read-only diagnosis is available, but SCV
  will not hydrate, sync, migrate, or choose one file automatically.
  Reconcile the listed files explicitly before any mutating action.
EOF
elif [[ $HYDRATED -eq 0 ]]; then
  cat <<EOF
  This directory is not hydrated yet.

  Hydrate seeds only the SCV workflow files (scv/SCV.md, scv/PROMOTE.md,
  scv/REPORTING.md, scv/raw/, promote/, archive/) — /scv:promote and
  /scv:work are usable right away on new and existing projects alike.

    bash "$PLUGIN_ROOT/scripts/hydrate.sh" init .

  Run /scv:help again afterwards to see the next step.
EOF
elif [[ $ENV_SET -eq 0 ]]; then
  cat <<'EOF'
  Configure .env. The SCV Notifier variables live in `.env.example.scv`.

  1. If no .env yet:    cp .env.example.scv .env
     If .env exists:    cat .env.example.scv >> .env   (append SCV vars only)
  2. Set NOTIFIER_PROVIDER (slack or discord)
  3. Fill in the matching Bot token and SLACK_CHANNEL_ID_* (or DISCORD_*)
  4. Run /scv:help again
EOF
elif [[ "$RAW_CHANGES_TOTAL" -gt 0 ]]; then
  cat <<EOF
  Detected changes in scv/raw/ ($RAW_CHANGES_TOTAL item(s) total).

  Use this command to refine into a promote plan:

      /scv:promote

  Or to inspect the diff first:

      /scv:status

  (To only mark current state as baseline and defer planning: /scv:status --ack)
EOF
elif [[ ${#ACTIVE_PLANS[@]} -gt 0 ]]; then
  FIRST_SLUG="${ACTIVE_PLANS[0]}"
  if [[ ${#ACTIVE_PLANS[@]} -eq 1 ]]; then
    PLAN_HINT="Use this command to start implementation + tests:

      /scv:work $FIRST_SLUG"
  else
    PLAN_HINT="Use this command to start with the oldest plan, or /scv:status for the full list:

      /scv:work $FIRST_SLUG       # oldest plan first
      /scv:status                 # all plans + graph status"
  fi
  cat <<EOF
  ${#ACTIVE_PLANS[@]} active promote plan(s) found.

  $PLAN_HINT

  After tests pass, /scv:work asks whether to move to archive interactively.
EOF
else
  cat <<'EOF'
  Ready — no immediate action required.

  Start a new loop with one of:

  - Drop new material        : add files to scv/raw/, then /scv:help
  - Ralph Loop autoloop      : external integration using loop-runner.md
  - Manual phase report      : /scv:report "Phase 1 — ..." passed --summary "..."
EOF
fi

# Additive workspace recommendation — surfaces incoming cross-repo work regardless
# of the main next-action above. Only fires for a CHILD with pending handoffs.
if [[ "$WS_MODE" == "CHILD" && "${WS_INCOMING:-0}" -gt 0 ]]; then
  echo ""
  echo "  ⮕ Workspace: $WS_INCOMING incoming handoff(s) — another repo asked this repo for corresponding dev:"
  echo "       /scv:promote          # scaffold PLAN+TESTS from a handoff"
  echo "       /scv:codegen <slug>   # implement (TDD)"
  echo "       /scv:status           # see all incoming handoffs"
fi
if [[ "$WS_MODE" == "ROOT" && "${WS_OPEN:-0}" -gt 0 ]]; then
  echo ""
  echo "  ⮕ Workspace (umbrella): ${WS_OPEN} handoff(s) coordinating across repos."
  echo "       /scv:status           # full list with status (open/claimed/done) per target"
  echo "       Each child repo pulls this umbrella, then /scv:promote → /scv:codegen."
fi

echo ""
echo "──────────────────────────────────────────────────────────────────────"
echo " Learn more"
echo "──────────────────────────────────────────────────────────────────────"
cat <<EOF
  Each skill supports --help or -h:
    /scv:report -h
    /scv:promote --help

  Plugin root:
    $PLUGIN_ROOT

  Key documents (created under scv/ after hydrate — project-root instructions are untouched):
    $SCV_INDEX_PATH     — resolved SCV workflow index + rules
    scv/PROMOTE.md    — raw → promote → archive promotion convention

EOF
