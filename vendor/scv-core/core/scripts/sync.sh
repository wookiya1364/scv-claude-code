#!/usr/bin/env bash
# Sync SCV template into an existing project, honoring frontmatter merge_policy.
#
# Template layout (SCV owns only scv/; the root is user-owned and never
# touched. Settings live under scv/, so the root has no SCV-owned file.
# down at the root and therefore SCV owns):
#   template/scv/SCV.md             → project scv/SCV.md   (merge-on-markers)
#   template/scv/*.md                  → project scv/*.md
#   template/scv/promote/*             → project scv/promote/    (preserved)
#   template/scv/archive/*             → project scv/archive/    (preserved)
#   template/scv/raw/*                 → project scv/raw/        (preserved)
#
# Rules:
#   - overwrite          Replace file wholesale
#   - preserve           Never change (unless --force <rel_path>)
#   - merge-on-markers   Replace file, but restore PROJECT:LOCAL block from local
#
# SCV.md is always merge-on-markers (its spec is baked into this script).
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
STANDARD_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
TEMPLATE_DIR="$STANDARD_ROOT/template"

# shellcheck source=lib/yaml.sh
source "$SCRIPT_DIR/lib/yaml.sh"
# shellcheck source=lib/merge.sh
source "$SCRIPT_DIR/lib/merge.sh"
# shellcheck source=lib/host-profile.sh
source "$SCRIPT_DIR/lib/host-profile.sh"

PROJECT_DIR="."
DRY_RUN=0
FORCE_FILES=()
JOIN_ROOT=""
JOIN_ID=""
JOIN_ROLE=""
JOIN_WS=""

usage() {
  cat <<'EOF'
Usage: sync.sh [--project-dir PATH] [--dry-run] [--force FILE ...]

Syncs the current team standard template into an existing project.
Respects frontmatter merge_policy on each template file.

Options:
  --project-dir PATH   Target project directory (default: cwd).
  --dry-run            Print planned actions without modifying files.
  --force FILE         Force-overwrite a file whose merge_policy is 'preserve'.
                       Use the relative path under the project.
                       May be passed multiple times.

Workspace join (multi-repo):
  --join ROOT_URL      Make this repo a CHILD of the workspace whose umbrella
                       scv repo is ROOT_URL (a git URL or local path). Stamps
                       the SCV:WORKSPACE block in scv/SCV.md and exits — no
                       template merge. Re-runnable; clearing it detaches.
  --id ID              Workspace-global repo id (default: project dir basename).
  --role ROLE          Repo role (e.g. frontend, backend, ai-agent).
  --workspace NAME     Workspace name (optional, for cache namespacing).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir)
      [[ $# -ge 2 && -n "${2:-}" ]] \
        || { echo "✖ --project-dir requires PATH" >&2; usage >&2; exit 2; }
      PROJECT_DIR="$2"; shift 2 ;;
    --dry-run)     DRY_RUN=1; shift ;;
    --force)
      [[ $# -ge 2 && -n "${2:-}" ]] \
        || { echo "✖ --force requires FILE" >&2; usage >&2; exit 2; }
      FORCE_FILES+=("$2"); shift 2 ;;
    --join)
      [[ $# -ge 2 && -n "${2:-}" ]] \
        || { echo "✖ --join requires ROOT_URL" >&2; usage >&2; exit 2; }
      JOIN_ROOT="$2"; shift 2 ;;
    --id)
      [[ $# -ge 2 && -n "${2:-}" ]] \
        || { echo "✖ --id requires ID" >&2; usage >&2; exit 2; }
      JOIN_ID="$2"; shift 2 ;;
    --role)
      [[ $# -ge 2 && -n "${2:-}" ]] \
        || { echo "✖ --role requires ROLE" >&2; usage >&2; exit 2; }
      JOIN_ROLE="$2"; shift 2 ;;
    --workspace)
      [[ $# -ge 2 && -n "${2:-}" ]] \
        || { echo "✖ --workspace requires NAME" >&2; usage >&2; exit 2; }
      JOIN_WS="$2"; shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "Unknown flag: $1" >&2; usage >&2; exit 2 ;;
  esac
done

CANONICAL_STATE_INDEX="$PROJECT_DIR/scv/$SCV_STATE_INDEX"
BROKEN_POINTERS="$(scv_state_index_broken_pointers "$PROJECT_DIR/scv")"
if [[ -n "$BROKEN_POINTERS" ]]; then
  echo "✖ SCV state-index pointer is broken; no files changed." >&2
  printf '%s\n' "$BROKEN_POINTERS" | sed 's/^/  /' >&2
  echo "  Restore scv/$SCV_STATE_INDEX or restore the legacy state file from its backup." >&2
  exit 4
fi
LOCAL_STATE_INDEX="$(scv_state_index_path "$PROJECT_DIR/scv")"
if [[ ! -f "$LOCAL_STATE_INDEX" ]]; then
  echo "✖ $PROJECT_DIR does not look like a hydrated project (missing scv/SCV.md)" >&2
  echo "  Use hydrate.sh init <dir> for new projects." >&2
  exit 1
fi

INDEX_CONFLICTS="$(scv_state_index_conflicts "$PROJECT_DIR/scv")"
if [[ -n "$INDEX_CONFLICTS" ]]; then
  echo "✖ SCV state-index conflict; no files changed." >&2
  printf '%s\n' "$INDEX_CONFLICTS" | sed 's/^/  /' >&2
  echo "  Reconcile the files manually, or let the wrapper replace a verified legacy file with a pointer." >&2
  exit 3
fi

# One-time, non-destructive migration: seed the shared state index from a
# wrapper-declared legacy index. The legacy file is intentionally left intact;
# the adapter may back it up and replace it with a pointer after this succeeds.
if [[ "$LOCAL_STATE_INDEX" != "$CANONICAL_STATE_INDEX" && ! -f "$CANONICAL_STATE_INDEX" ]]; then
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "MIGRATE   ${LOCAL_STATE_INDEX#"$PROJECT_DIR/"} → scv/$SCV_STATE_INDEX (legacy preserved)"
  else
    cp "$LOCAL_STATE_INDEX" "$CANONICAL_STATE_INDEX"
    echo "✓ migrated legacy state to scv/$SCV_STATE_INDEX (legacy file preserved)"
    LOCAL_STATE_INDEX="$CANONICAL_STATE_INDEX"
  fi
fi

# --join: stamp the SCV:WORKSPACE block (make this repo a workspace CHILD) and exit.
# Focused operation — does NOT run the template merge.
if [[ -n "$JOIN_ROOT" ]]; then
  STATE_INDEX="$LOCAL_STATE_INDEX"
  [[ -z "$JOIN_ID" ]] && JOIN_ID="$(basename "$(cd "$PROJECT_DIR" && pwd)")"
  if [[ $DRY_RUN -eq 1 ]]; then
    if [[ "$LOCAL_STATE_INDEX" != "$CANONICAL_STATE_INDEX" && ! -f "$CANONICAL_STATE_INDEX" ]]; then
      STATE_INDEX="$CANONICAL_STATE_INDEX"
    fi
    echo "JOIN      ${STATE_INDEX#"$PROJECT_DIR/"} (workspace block)"
    echo "  repo_id=$JOIN_ID role=${JOIN_ROLE:-<unset>} root=$JOIN_ROOT workspace=${JOIN_WS:-<unset>}"
    echo "(dry-run mode — no files modified)"
    exit 0
  fi
  body=$(printf '```yaml\nrepo_id: %s\nrole: %s\nroot: %s\nworkspace: %s\n```' \
    "$JOIN_ID" "$JOIN_ROLE" "$JOIN_ROOT" "$JOIN_WS")
  if has_marker_block "$STATE_INDEX" "SCV:WORKSPACE START"; then
    replace_marker_block "$STATE_INDEX" "SCV:WORKSPACE START" "SCV:WORKSPACE END" "$body"
  else
    {
      echo ""
      echo "## SCV workspace (multi-repo nesting)"
      echo ""
      echo "<!-- SCV:WORKSPACE START -->"
      echo "$body"
      echo "<!-- SCV:WORKSPACE END -->"
    } >> "$STATE_INDEX"
  fi
  echo "✓ Joined workspace as CHILD: repo_id=$JOIN_ID role=${JOIN_ROLE:-<unset>} root=$JOIN_ROOT"
  echo "  Detach anytime by clearing root: in scv/SCV.md's SCV:WORKSPACE block."
  exit 0
fi

REMOTE_VERSION=$(tr -d '[:space:]' < "$STANDARD_ROOT/TEMPLATE_VERSION")
# 템플릿 내용의 지문. 자동 갱신은 번호가 아니라 이 값으로 판단하고, 동기화가 끝나면
# 이 값을 프로젝트 인덱스에 찍는다. 배포본에 없으면(구형 배포본) 빈 값으로 두고,
# 판단 쪽이 예전처럼 번호로만 보게 한다.
REMOTE_DIGEST=""
[[ -f "$STANDARD_ROOT/TEMPLATE_DIGEST" ]] \
  && REMOTE_DIGEST=$(tr -d '[:space:]' < "$STANDARD_ROOT/TEMPLATE_DIGEST")
LOCAL_VERSION=$(extract_simple_marker "$LOCAL_STATE_INDEX" "<!-- STANDARD:VERSION -->" "<!-- /STANDARD:VERSION -->" 2>/dev/null | tr -d '[:space:]' || true)
[[ -z "$LOCAL_VERSION" ]] && LOCAL_VERSION="unknown"

echo "Standard version: local=$LOCAL_VERSION → remote=$REMOTE_VERSION"
echo "Project dir: $(cd "$PROJECT_DIR" && pwd)"
[[ $DRY_RUN -eq 1 ]] && echo "(dry-run mode — no files modified)"
echo

CHANGES=()

# No backups. This script used to copy every file it changed into
# .scv-backup/<timestamp>/ — an untracked snapshot directory that its own
# retired-docs pass below already contradicted ("git history is the recovery
# path"). One file held two answers to "how do I get the old content back",
# and the copies were gitignored, so they piled up invisibly.
#
# The honest rule replaces it: a file git can restore may be replaced, and a
# file git cannot restore is refused by name. Tracked-and-modified, staged,
# untracked, and gitignored all refuse — so does every differing file in a
# project that is not a git work tree, because there the old content would
# have nowhere to survive. `--force <file>` overrides, same as for preserve.
#
# One deliberate exception: the retired-docs pass below deletes its seven
# files unconditionally. That is a recorded user decision, and it is not a
# hole this rule forgot — the sync protocol requires the interactive
# migration to offer moving their content into DECISIONS.md BEFORE this
# script runs, and the automatic refresh never reaches a pre-2.x project at
# all. The version gate on that pass is what keeps the exception narrow.
GIT_WORKTREE=0
if git -C "$PROJECT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  GIT_WORKTREE=1
fi

# is_dirty asks one question: can git give back the bytes this script is about
# to destroy? It answers by comparing the worktree CONTENT against HEAD — not
# by reading `git status`. Status lies in exactly the cases that matter: a
# symlinked path reports clean while cp would write through the link into a
# file git never stored, and `update-index --assume-unchanged` reports clean
# while the local content exists only on disk. Content against HEAD has no
# such blind spots: untracked, ignored, and assume-unchanged all simply fail
# to match, and land on the refuse side.
#
# The comparison neutralizes the STANDARD:VERSION / SYNCED_AT stamp spans,
# because sync itself maintains those — without this, the stamp write from one
# refresh makes the file read as dirty on the next, and two payload bumps in a
# row deadlock on sync's own footprints.
#
# Sets DIRTY_KIND so the report can say the right thing: "modified" (a commit
# exists to diff against) vs "unrestorable" (git holds no copy at all).
DIRTY_KIND=""
is_dirty() {
  local f="$1"
  DIRTY_KIND="unrestorable"
  [[ -L "$f" ]] && return 0                       # writes would go through the link
  [[ $GIT_WORKTREE -eq 1 ]] || return 0
  local rel="${f#"$PROJECT_DIR"/}"
  local head_blob
  if ! head_blob="$(git -C "$PROJECT_DIR" rev-parse -q --verify "HEAD:$rel" 2>/dev/null)"; then
    return 0                                      # never committed → nothing to restore from
  fi
  if git -C "$PROJECT_DIR" cat-file blob "$head_blob" 2>/dev/null | _stamp_neutral \
       | cmp -s - <(_stamp_neutral < "$f"); then
    return 1                                      # worktree == HEAD (stamps aside) → replace freely
  fi
  DIRTY_KIND="modified"
  return 0
}

# Version/date stamps are maintained by the stamping block at the end of this
# script, not by the merge — so for equality questions they are noise.
# A pure stdin→stdout filter, deliberately taking no filename: GNU sed treats
# "-" as stdin while BSD sed opens a file named "-", so a filename argument is
# a portability trap. Callers redirect.
_stamp_neutral() {
  sed -e 's|<!-- STANDARD:VERSION -->.*<!-- /STANDARD:VERSION -->|@STAMP@|' \
      -e 's|<!-- STANDARD:SYNCED_AT -->.*<!-- /STANDARD:SYNCED_AT -->|@STAMP@|' \
      -e 's|<!-- STANDARD:DIGEST -->.*<!-- /STANDARD:DIGEST -->|@STAMP@|'
}

# refuse_if_dirty <dst> <display> — returns 0 (and records the refusal) when
# the write must not happen. Reported in dry-run too: it is a prediction.
REFUSALS=0
refuse_if_dirty() {
  local dst="$1" display="$2"
  is_forced "$display" && return 1
  is_dirty "$dst" || return 1
  REFUSALS=$((REFUSALS + 1))
  if [[ -L "$dst" ]]; then
    CHANGES+=("DIRTY     $display  (symlink — content not touched; sync never writes through a link)")
  elif [[ "$DIRTY_KIND" == "modified" ]]; then
    CHANGES+=("DIRTY     $display  (uncommitted changes — content not touched; commit or discard them and re-run sync, or --force '$display')")
  else
    CHANGES+=("DIRTY     $display  (git holds no copy to restore from — content not touched; commit it first, or --force '$display')")
  fi
  return 0
}

is_forced() {
  local name="$1"
  for f in "${FORCE_FILES[@]:-}"; do
    [[ "$f" == "$name" ]] && return 0
  done
  return 1
}

# merge-on-markers: copy template, restore local marker blocks that are
# project-owned (never overwritten by a template update).
#   PROJECT:LOCAL  — project-specific SCV-scope rules
#   SCV:WORKSPACE  — multi-repo nesting identity (a child's join must survive sync)
apply_merge_on_markers() {
  local src="$1" dst="$2"
  local pl="" ws="" pl_have=0 ws_have=0 preserved_status=""
  preserved_status="$(yaml_get "$dst" "status")"
  if has_marker_block "$dst" "PROJECT:LOCAL START"; then
    pl=$(extract_marker_block "$dst" "PROJECT:LOCAL START" "PROJECT:LOCAL END"); pl_have=1
  fi
  if has_marker_block "$dst" "SCV:WORKSPACE START"; then
    ws=$(extract_marker_block "$dst" "SCV:WORKSPACE START" "SCV:WORKSPACE END"); ws_have=1
  fi
  cp "$src" "$dst"
  if [[ -n "$preserved_status" ]]; then
    local status_tmp
    status_tmp="$(mktemp)"
    awk -v value="$preserved_status" '
      BEGIN { fences = 0; replaced = 0 }
      /^---[[:space:]]*$/ { fences++; print; next }
      fences == 1 && !replaced && /^status:[[:space:]]*/ {
        print "status: " value
        replaced = 1
        next
      }
      { print }
    ' "$dst" > "$status_tmp"
    mv "$status_tmp" "$dst"
  fi
  if [[ $pl_have -eq 1 ]]; then
    replace_marker_block "$dst" "PROJECT:LOCAL START" "PROJECT:LOCAL END" "$pl" || true
  fi
  if [[ $ws_have -eq 1 ]]; then
    replace_marker_block "$dst" "SCV:WORKSPACE START" "SCV:WORKSPACE END" "$ws" || true
  fi
}

# Process a single template file relative to the project root.
# Arg 1: absolute path to template file
# Arg 2: relative subdirectory under PROJECT_DIR (empty string for root, or "scv")
process_template_file() {
  local tmpl="$1"
  local rel_dir="$2"
  local bn
  bn=$(basename "$tmpl")

  local dst_dir
  if [[ -z "$rel_dir" ]]; then
    dst_dir="$PROJECT_DIR"
  else
    dst_dir="$PROJECT_DIR/$rel_dir"
  fi
  local dst="$dst_dir/$bn"
  local display
  if [[ -z "$rel_dir" ]]; then
    display="$bn"
  else
    display="$rel_dir/$bn"
  fi

  # A symlinked scv/ directory routes every write into a tree this script does
  # not own — the retired-doc pass already fails closed on it, and the template
  # pass must too. One WARN, then nothing.
  if [[ -L "$PROJECT_DIR/scv" ]]; then
    if [[ ${SCV_LINK_WARNED:-0} -eq 0 ]]; then
      CHANGES+=("WARN      scv/  (symlinked directory — template refresh skipped; resolve the link and re-run sync)")
      SCV_LINK_WARNED=1
    fi
    return 0
  fi

  mkdir -p "$dst_dir"

  # A dangling symlink fails the -f test and would read as NEW — and cp would
  # then create a file at the link's target, outside anything git tracks here.
  if [[ -L "$dst" ]]; then
    REFUSALS=$((REFUSALS + 1))
    CHANGES+=("DIRTY     $display  (symlink — content not touched; sync never writes through a link)")
    return 0
  fi

  if [[ ! -f "$dst" ]]; then
    CHANGES+=("NEW       $display")
    if [[ $DRY_RUN -eq 0 ]]; then
      cp "$tmpl" "$dst"
    fi
    return 0
  fi

  local policy
  policy=$(yaml_get "$tmpl" "merge_policy")
  [[ -z "$policy" ]] && policy="preserve"

  # Files that carry no frontmatter get their policy by basename: SCV.md is
  # markdown but its spec is baked into this script, and the example settings are
  # an env file with nowhere to declare one. Overwrite on the latter is what
  # makes an old copy learn about new options; the dirty refusal above still
  # protects an edit git cannot give back.
  case "$bn" in
    SCV.md)           policy="merge-on-markers" ;;
  esac

  if cmp -s "$tmpl" "$dst"; then
    return
  fi

  case "$policy" in
    overwrite)
      refuse_if_dirty "$dst" "$display" && return 0
      CHANGES+=("OVERWRITE $display")
      if [[ $DRY_RUN -eq 0 ]]; then
        cp "$tmpl" "$dst"
      fi
      ;;
    preserve)
      if is_forced "$display"; then
        CHANGES+=("FORCED    $display  (preserve overridden)")
        if [[ $DRY_RUN -eq 0 ]]; then
          cp "$tmpl" "$dst"
        fi
      else
        CHANGES+=("SKIP      $display  (preserve)")
      fi
      ;;
    merge-on-markers)
      # "Differs from the template" is the wrong question for a merge file:
      # hydrate stamps version/date markers into the copy, so an untouched
      # project differs from the raw template forever — and right after
      # hydrate the file is also still untracked, which read as DIRTY and
      # drowned a project's very first sync in refusals. Ask the real
      # question: would the merge change this file? Simulate it, neutralize
      # the stamp spans, and compare.
      local sim; sim="$(mktemp)"
      cp "$dst" "$sim"
      apply_merge_on_markers "$tmpl" "$sim"
      if cmp -s <(_stamp_neutral < "$sim") <(_stamp_neutral < "$dst"); then
        rm -f "$sim"
        return 0
      fi
      rm -f "$sim"
      # The merge keeps PROJECT:LOCAL blocks but loses any local edit outside
      # them, so the same refusal applies to the whole file.
      refuse_if_dirty "$dst" "$display" && return 0
      CHANGES+=("MERGE     $display  (PROJECT:LOCAL preserved)")
      if [[ $DRY_RUN -eq 0 ]]; then
        apply_merge_on_markers "$tmpl" "$dst"
      fi
      ;;
    *)
      CHANGES+=("UNKNOWN   $display  (unknown merge_policy='$policy', skipped)")
      ;;
  esac
}

shopt -s nullglob
# .md files under template/scv/ (incl. scv/SCV.md; merge-on-markers by basename rule)
for tmpl in "$TEMPLATE_DIR/scv"/*.md; do
  process_template_file "$tmpl" "scv"
done
shopt -u nullglob

# scv/raw/README.md — the raw lifecycle guide (unused vs stale/) must reach
# existing projects too; without this, pre-0.21.0 installs keep a README that
# contradicts the stale-move behavior their upgraded core now performs.
if [[ -f "$TEMPLATE_DIR/scv/raw/README.md" ]]; then
  process_template_file "$TEMPLATE_DIR/scv/raw/README.md" "scv/raw"
fi

# scv/journal/README.md — the journal usage guide (v0.22.0+, merge_policy:
# preserve). Same explicit-line propagation as raw/README.md so pre-0.22.0
# projects receive the journal via sync; its siblings DECISIONS.md / TODO.md
# ride the top-level scv/*.md glob above.
if [[ -f "$TEMPLATE_DIR/scv/journal/README.md" ]]; then
  process_template_file "$TEMPLATE_DIR/scv/journal/README.md" "scv/journal"
fi

# scv/routines/README.md — the routine convention guide (v0.22.0+,
# merge_policy: overwrite). Same explicit-line propagation as raw/README.md:
# ONLY the README travels — routine files are user-owned, and the example
# routine templates (template/scv/routines/examples/) never leave core.
if [[ -f "$TEMPLATE_DIR/scv/routines/README.md" ]]; then
  process_template_file "$TEMPLATE_DIR/scv/routines/README.md" "scv/routines"
fi


# Retired standard docs (TEMPLATE_VERSION 2.0.0) — deleted from existing
# projects, deliberately WITHOUT backup (user decision; git history is the
# recovery path). Only these exact seven filenames, only directly under scv/.
# The sync.md protocol instructs Claude Code to offer moving user-authored
# content into DECISIONS.md BEFORE this runs. Symlinks are never followed or
# deleted (fail-closed): the link target may be a file SCV does not own.
#
# One-time migration, twice guarded:
# - Version gate: runs only while the project's stamped template version is
#   pre-2.x ("unknown" = never-synced legacy). Once 2.0.0 is stamped, these
#   seven names belong to the user again — a recreated file is never re-deleted.
# - A symlinked scv/ DIRECTORY disables the pass entirely: every dst path
#   would resolve through the link into a tree SCV does not own.
RETIRED_DOCS=(DOMAIN.md ARCHITECTURE.md DESIGN.md AGENTS.md TESTING.md INTAKE.md RALPH_PROMPT.md)
case "$LOCAL_VERSION" in
  [2-9].*|[1-9][0-9]*.*) RETIRE_PASS=0 ;;
  *)                     RETIRE_PASS=1 ;;
esac
if [[ $RETIRE_PASS -eq 1 && -L "$PROJECT_DIR/scv" ]]; then
  CHANGES+=("WARN      scv/  (symlinked directory — retired-doc migration skipped; resolve the link and re-run sync)")
  RETIRE_PASS=0
fi
if [[ $RETIRE_PASS -eq 1 ]]; then
  for retired in "${RETIRED_DOCS[@]}"; do
    dst="$PROJECT_DIR/scv/$retired"
    if [[ -L "$dst" ]]; then
      CHANGES+=("WARN      scv/$retired  (symlink — retired doc NOT deleted; remove it manually)")
      continue
    fi
    [[ -f "$dst" ]] || continue
    CHANGES+=("DELETED   scv/$retired")
    if [[ $DRY_RUN -eq 0 ]]; then
      rm -f "$dst"
    fi
  done
fi

# Stamp scv/SCV.md version markers (root instruction files stay untouched).
# Marker names kept as STANDARD:* for backward compatibility.
#
# Only when NOTHING was refused. The stamp is the automatic refresh's gate:
# advancing it while a DIRTY file kept the old template would mark the
# migration complete when it is not — the refusal would never be retried, the
# stale file would stay stale forever, and every report would read healthy. A
# refused run leaves the stamp alone so the gap stays open and the next action
# tries again. The stamp write itself also respects the refusal rule: a dirty
# or symlinked SCV.md is not written at all, because "content not touched"
# must stay true for the marker spans too.
# Deliberately NOT gated on is_dirty: right after this run's own merge, the
# file is uncommitted by sync's doing, and refusing to stamp then would leave
# the gap open forever on a perfectly clean project. REFUSALS covers the case
# that matters — a user-dirty SCV.md was refused above, so REFUSALS is nonzero
# and the stamp stays put. The write is recorded in the report: the spans are
# SCV-maintained metadata, and anything a user parked inside them is replaced,
# so "(none)" must never be the whole story.
if [[ $DRY_RUN -eq 0 && $REFUSALS -eq 0 && -f "$PROJECT_DIR/scv/SCV.md" \
      && ! -L "$PROJECT_DIR/scv/SCV.md" && ! -L "$PROJECT_DIR/scv" ]]; then
  CURRENT_STAMP="$(extract_simple_marker "$PROJECT_DIR/scv/SCV.md" "<!-- STANDARD:VERSION -->" "<!-- /STANDARD:VERSION -->" 2>/dev/null | tr -d '[:space:]' || true)"
  if [[ "$CURRENT_STAMP" != "$REMOTE_VERSION" ]]; then
    CHANGES+=("STAMP     scv/SCV.md  (template version ${CURRENT_STAMP:-unset} → $REMOTE_VERSION)")
  fi
  replace_simple_marker "$PROJECT_DIR/scv/SCV.md" \
    "<!-- STANDARD:VERSION -->" "<!-- /STANDARD:VERSION -->" "$REMOTE_VERSION"
  replace_simple_marker "$PROJECT_DIR/scv/SCV.md" \
    "<!-- STANDARD:SYNCED_AT -->" "<!-- /STANDARD:SYNCED_AT -->" "$(date +%Y-%m-%d)"
  # 지문은 배포본이 실제로 들고 있을 때만 찍는다. 구형 배포본이 빈 값을 찍어
  # 프로젝트의 멀쩡한 지문을 지우면, 다음 갱신이 "지문 없음" 으로 오인한다.
  if [[ -n "$REMOTE_DIGEST" ]]; then
    CURRENT_DIGEST="$(extract_simple_marker "$PROJECT_DIR/scv/SCV.md" "<!-- STANDARD:DIGEST -->" "<!-- /STANDARD:DIGEST -->" 2>/dev/null | tr -d '[:space:]' || true)"
    if [[ "$CURRENT_DIGEST" != "$REMOTE_DIGEST" ]]; then
      CHANGES+=("STAMP     scv/SCV.md  (template digest ${CURRENT_DIGEST:-unset} → ${REMOTE_DIGEST:0:12}…)")
    fi
    replace_simple_marker "$PROJECT_DIR/scv/SCV.md" \
      "<!-- STANDARD:DIGEST -->" "<!-- /STANDARD:DIGEST -->" "$REMOTE_DIGEST"
  fi
fi

# 새로 생긴 설정 키를 프로젝트 설정에 더한다. 사용자가 이미 정한 값은 절대
# 바꾸지 않는다 — 업데이트할 때마다 설정이 되돌아가면 곤란하다. 설정 파일이
# 아직 없으면 아무것도 하지 않는다.
if [[ $DRY_RUN -eq 0 && -f "$STANDARD_ROOT/scripts/settings-merge.sh" ]]; then
  MERGE_OUT="$(bash "$STANDARD_ROOT/scripts/settings-merge.sh" --project-dir "$PROJECT_DIR" 2>&1 || true)"
  if printf '%s' "$MERGE_OUT" | grep -q '^added '; then
    CHANGES+=("SETTINGS  $(printf '%s' "$MERGE_OUT" | head -n 1)")
  fi
fi

echo "Changes:"
if [[ ${#CHANGES[@]} -eq 0 ]]; then
  echo "  (none)"
else
  for c in "${CHANGES[@]}"; do
    echo "  $c"
  done
fi

if [[ $DRY_RUN -eq 1 ]]; then
  echo
  echo "(dry-run) re-run without --dry-run to apply."
fi
