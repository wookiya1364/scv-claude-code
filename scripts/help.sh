#!/usr/bin/env bash
# Self-onboarding output for the SCV plugin.
# Prints: overview, command list, current project diagnosis, next action.
set -uo pipefail

VERBOSE=0
for a in "$@"; do
  case "$a" in
    --verbose|-v) VERBOSE=1 ;;
  esac
done

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# Plugin root (contains scripts/, template/, commands/, ...). When run as a
# slash command, $CLAUDE_PLUGIN_ROOT is set; fall back to ../ of SCRIPT_DIR.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"

# --- Fixed overview (always shown) -------------------------------------------
cat <<'EOF'
╔══════════════════════════════════════════════════════════════════════╗
║  SCV — Standard · Cowork · Verify                                     ║
╚══════════════════════════════════════════════════════════════════════╝

Core idea (S·C·V)
  S  Standard — humans fill design docs through dialogue (scv/INTAKE.md)
  C  Cowork   — drop into scv/raw, promote to scv/promote/ for team handoff
  V  Verify   — implement → E2E → Slack/Discord report each Phase

Workflow (default = adoption / --new = greenfield)
  ① hydrate         → copy the empty template into the project
  ② .env setup      → NOTIFIER_PROVIDER=slack|discord, tokens/channels
  ③ scv/raw/        → drop existing material (notes, sketches, PDFs) — optional
  ④ /scv:promote    → raw → scv/promote/<YYYYMMDD>-<author>-<slug>/ (PLAN + TESTS)
  ⑤ /scv:work       → implement · test · move to archive on pass
  (opt) INTAKE.md   → for new projects (--new), fill standard docs via dialogue
  (opt) /ralph-loop → external template (copy ralph-template-scv.md → ~/.claude/ralph-template.md)
  (opt) /scv:regression → periodic / pre-release accumulated regression. Optional pre-flight before ⑤'s archive too.

Commands
  /scv:help       This screen (current state + next step)
  /scv:status     scv/raw/ change detection + active promote plans + graph status
  /scv:promote    scv/raw/ → scv/promote/<YYYYMMDD>-<author>-<slug>/ + graph refresh
  /scv:work       Implement promote plan → test → optionally archive
  /scv:regression Run accumulated archived regression + auto-skip supersedes/obsolete + failure triage
  /scv:report     Phase report to Slack/Discord (with artifacts)
  /scv:sync       Safe merge on template version bump

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
fi

# --- Dynamic diagnosis of current project ------------------------------------
PROJECT_PWD="$(pwd)"
echo "──────────────────────────────────────────────────────────────────────"
echo " Current project diagnosis ($PROJECT_PWD)"
echo "──────────────────────────────────────────────────────────────────────"

HYDRATED=0
ENV_SET=0
RAW_COUNT=0
DRAFT_DOCS=()
ACTIVE_DOCS=()
NA_DOCS=()

# Hydration check (SCV owns scv/ only — root CLAUDE.md is user-owned)
if [[ -f "scv/CLAUDE.md" && -f "scv/INTAKE.md" ]]; then
  HYDRATED=1
  echo "  [✓] hydrate complete (scv/CLAUDE.md + scv/INTAKE.md exist)"
else
  echo "  [✗] hydrate not done (scv/CLAUDE.md / scv/INTAKE.md missing)"
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
if [[ -f "$HOME/.claude/skills/graphify/SKILL.md" ]]; then
  GRAPHIFY_PRESENT=1
elif compgen -G "$HOME/.claude/plugins/cache/*/skills/graphify/SKILL.md" >/dev/null 2>&1; then
  GRAPHIFY_PRESENT=1
fi
if [[ $GRAPHIFY_PRESENT -eq 1 ]]; then
  printf '    [✓] %-8s — %s\n' "graphify" "Claude Code skill — token-efficient graph queries (/scv:promote, /scv:work)"
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

# Document status
if [[ $HYDRATED -eq 1 ]]; then
  for doc in INTAKE PROMOTE DOMAIN ARCHITECTURE DESIGN AGENTS TESTING REPORTING RALPH_PROMPT; do
    f="scv/$doc.md"
    [[ ! -f "$f" ]] && continue
    st=$(awk '/^---[[:space:]]*$/{c++; next} c==1 && /^status:/{print $2; exit}' "$f" | tr -d '[:space:]')
    case "$st" in
      draft)   DRAFT_DOCS+=("$doc") ;;
      active)  ACTIVE_DOCS+=("$doc") ;;
      N/A|na)  NA_DOCS+=("$doc") ;;
      *)       DRAFT_DOCS+=("$doc") ;;
    esac
  done

  if [[ ${#DRAFT_DOCS[@]} -eq 0 ]]; then
    # No docs in draft state — adoption mode is operating normally. Compress
    # to one line so first-time users don't read N/A as "9 things I owe".
    # In adoption mode, N/A is the steady state.
    printf '  Standard docs: %d active, %d N/A — adoption mode default. Lift any N/A doc to draft only when you decide to document that subsystem.\n' \
      "${#ACTIVE_DOCS[@]}" "${#NA_DOCS[@]}"
  else
    # At least one doc is in draft state — the user is actively filling
    # something, so show the breakdown so the "needs filling" hint surfaces.
    echo "  Document status:"
    if [[ ${#ACTIVE_DOCS[@]} -gt 0 ]]; then
      printf '    active  : %s\n' "${ACTIVE_DOCS[*]}"
    fi
    printf '    draft   : %s  ← needs filling\n' "${DRAFT_DOCS[*]}"
    if [[ ${#NA_DOCS[@]} -gt 0 ]]; then
      printf '    N/A     : %s\n' "${NA_DOCS[*]}"
    fi
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

echo ""
echo "──────────────────────────────────────────────────────────────────────"
echo " Recommended next action"
echo "──────────────────────────────────────────────────────────────────────"

# --- Recommend next step based on state --------------------------------------
if [[ $HYDRATED -eq 0 ]]; then
  cat <<EOF
  This directory is not hydrated yet. Pick one of two modes.

  ── default · adoption mode (recommended) — apply SCV to an existing project ──
  Standard docs seed with status: N/A and /scv:promote, /scv:work are
  usable right away. Document only the scope you need.

    bash "$PLUGIN_ROOT/scripts/hydrate.sh" init .

  ── --new · greenfield mode — fill all standard docs via INTAKE for a new project ──
  Standard docs seed with status: draft and /scv:help walks you through
  the INTAKE protocol filling DOMAIN / ARCHITECTURE / ... one at a time.
  Use this only when truly starting from zero.

    bash "$PLUGIN_ROOT/scripts/hydrate.sh" init . --new

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
elif [[ ${#DRAFT_DOCS[@]} -gt 0 ]]; then
  active_list="${ACTIVE_DOCS[*]:-(none)}"
  cat <<EOF
  Standard document status:
    active : $active_list
    draft  : ${DRAFT_DOCS[*]}

  Run INTAKE. Claude will first ask whether to resume or start over.

  - Phrase to give Claude (copyable):

    "Read scv/INTAKE.md and follow the §1 'resume check' procedure to
     verify current status first, then ask whether to [A] resume or
     [B] start over before doing anything. Don't jump straight to step 0."

  - Drop any existing raw material into scv/raw/ so Claude can reference it.
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
      /scv:status               # all plans + graph status"
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
  - Ralph Loop autoloop      : /ralph-loop  (external command — needs ralph-template-scv.md)
  - Manual phase report      : /scv:report "Phase 1 — ..." passed --summary "..."
EOF
fi

echo ""
echo "──────────────────────────────────────────────────────────────────────"
echo " Learn more"
echo "──────────────────────────────────────────────────────────────────────"
cat <<EOF
  Each command supports --help or -h:
    /scv:report -h
    /scv:promote --help

  Plugin root:
    $PLUGIN_ROOT

  Key documents (created under scv/ after hydrate — root CLAUDE.md is untouched by SCV):
    scv/CLAUDE.md     — SCV workflow index + rules
    scv/INTAKE.md     — Dialogue protocol (project bootstrap order)
    scv/PROMOTE.md    — raw → promote → archive promotion convention

EOF
