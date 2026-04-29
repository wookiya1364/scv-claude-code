#!/usr/bin/env bash
# pr-helper.sh — Assemble a PR body for an archived plan and (optionally)
# create the PR via `gh pr create`.
#
# v0.3.0 scope: screenshots (PNG/JPG, committed to PR branch in
# .scv-pr-artifacts/) + videos (.webm/.mp4, pushed to scv-attachments orphan
# branch via lib/attachments.sh, kept out of PR branch git history).
#
# Behavior:
#   1. Resolve scv/archive/<slug>/ via work.sh-style fuzzy match
#   2. Read PLAN.md / TESTS.md / ARCHIVED_AT.md → assemble markdown body
#   3. Move test-results/ PNGs into .scv-pr-artifacts/<slug>/ (committed)
#   4. Collect test-results/ videos (.webm/.mp4) — handled by attachments lib
#   5. Stage + commit screenshots
#   6. Push current branch, ensure epic base branch exists
#   7. attachments_cleanup_stale (self-amortizing cleanup of merged old PRs)
#   8. gh pr create with placeholder body
#   9. attachments_upload <slug> <pr_number> <videos...>
#  10. gh pr edit — replace placeholder with actual video URLs
#  11. Print PR URL on stdout
#
# Internal API: this script is called by /scv:work Step 9d (commands/work.md).
# Users do NOT invoke it directly.

set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/yaml.sh
source "$SCRIPT_DIR/lib/yaml.sh"
# shellcheck source=lib/env.sh
source "$SCRIPT_DIR/lib/env.sh"
# shellcheck source=lib/attachments.sh
source "$SCRIPT_DIR/lib/attachments.sh"

# Load project .env so SCV_ATTACHMENTS_* vars are visible
env_load 2>/dev/null || true

ARCHIVE_DIR="${ARCHIVE_DIR:-scv/archive}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-.scv-pr-artifacts}"
TEST_RESULTS_DIR="${TEST_RESULTS_DIR:-test-results}"
VIDEO_PLACEHOLDER="<!-- SCV_VIDEO_PLACEHOLDER -->"

usage() {
  cat <<'EOF'
Usage: pr-helper.sh <slug> [--dry-run] [--no-push] [--no-create]

Internal helper used by /scv:work Step 9d. Builds a PR body from an archived
plan and (by default) creates the PR via gh.

Arguments:
  <slug>           Archive slug (or substring — fuzzy match like work.sh).

Options:
  --dry-run        Print the assembled PR body to stdout. No file changes,
                   no git/gh operations. Useful for previewing.
  --no-push        Skip `git push` (commit only). Body printed.
  --no-create      Skip `gh pr create` (commit + push, no PR). Body printed.
EOF
}

DRY_RUN=0
NO_PUSH=0
NO_CREATE=0
SLUG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)   DRY_RUN=1; shift ;;
    --no-push)   NO_PUSH=1; shift ;;
    --no-create) NO_CREATE=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    -*)          echo "Unknown flag: $1" >&2; exit 1 ;;
    *)
      if [[ -z "$SLUG" ]]; then SLUG="$1"
      else echo "Multiple slug arguments not supported: $1" >&2; exit 1
      fi
      shift ;;
  esac
done

if [[ -z "$SLUG" ]]; then
  echo "ERROR: <slug> is required" >&2
  usage >&2
  exit 1
fi

# ---- resolve target archive folder (fuzzy) ----
resolve_archive() {
  local slug="$1"
  if [[ -d "$ARCHIVE_DIR/$slug" ]]; then
    echo "$ARCHIVE_DIR/$slug"
    return 0
  fi
  local hits=()
  while IFS= read -r d; do
    [[ -d "$d" ]] || continue
    local name; name=$(basename "$d")
    [[ "$name" == *"$slug"* ]] && hits+=("$d")
  done < <(find "$ARCHIVE_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort)
  if [[ ${#hits[@]} -eq 1 ]]; then echo "${hits[0]}"; return 0; fi
  if [[ ${#hits[@]} -gt 1 ]]; then printf '%s\n' "${hits[@]}"; return 2; fi
  return 1
}

if resolved=$(resolve_archive "$SLUG"); then
  TARGET_DIR="$resolved"
else
  rc=$?
  if [[ $rc -eq 2 ]]; then
    echo "ERROR: ambiguous slug '$SLUG'; multiple matches:" >&2
    echo "$resolved" >&2
  else
    echo "ERROR: no archive folder matches '$SLUG' under $ARCHIVE_DIR" >&2
  fi
  exit 1
fi

SLUG_NAME=$(basename "$TARGET_DIR")
PLAN_FILE="$TARGET_DIR/PLAN.md"
TESTS_FILE="$TARGET_DIR/TESTS.md"
ARCHIVED_AT_FILE="$TARGET_DIR/ARCHIVED_AT.md"

if [[ ! -f "$PLAN_FILE" ]]; then
  echo "ERROR: $PLAN_FILE not found" >&2
  exit 1
fi

# ---- extract metadata ----
TITLE=$(yaml_get "$PLAN_FILE" title)
[[ -z "$TITLE" ]] && TITLE="$SLUG_NAME"
EPIC=$(yaml_get "$PLAN_FILE" epic)
KIND=$(yaml_get "$PLAN_FILE" kind)
[[ -z "$KIND" ]] && KIND="feature"

# ---- collect screenshots from test-results/ ----
SCREENSHOTS=()
if [[ -d "$TEST_RESULTS_DIR" ]]; then
  while IFS= read -r f; do
    [[ -f "$f" ]] && SCREENSHOTS+=("$f")
  done < <(find "$TEST_RESULTS_DIR" -type f \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' \) 2>/dev/null | LC_ALL=C sort)
fi

# ---- collect videos from test-results/ ----
VIDEOS=()
if [[ -d "$TEST_RESULTS_DIR" ]]; then
  while IFS= read -r f; do
    [[ -f "$f" ]] && VIDEOS+=("$f")
  done < <(find "$TEST_RESULTS_DIR" -type f \( -iname '*.webm' -o -iname '*.mp4' \) 2>/dev/null | LC_ALL=C sort)
fi

# ---- helpers for body assembly ----

extract_section() {
  # extract_section <md-file> <heading-pattern>
  # Prints the body of the first matching ## heading until next ## .
  local file="$1" hp="$2"
  awk -v hp="$hp" '
    /^## / { if (in_section) exit; if ($0 ~ hp) { in_section=1; next } }
    in_section { print }
  ' "$file"
}

trim_blank_lines() {
  awk 'NF { p=1 } p { print }' | awk 'BEGIN{n=0} {l[n++]=$0} END{while(n>0 && l[n-1]==""){n--} for(i=0;i<n;i++) print l[i]}'
}

# ---- assemble PR body ----
TMP_BODY=$(mktemp)
{
  # Title is part of `gh pr create --title`, not body
  echo "## Summary"
  echo
  extract_section "$PLAN_FILE" "^## Summary" | trim_blank_lines
  echo
  echo "## Goals / Non-Goals"
  echo
  extract_section "$PLAN_FILE" "^## Goals / Non-Goals" | trim_blank_lines
  echo
  echo "## Steps"
  echo
  extract_section "$PLAN_FILE" "^## Steps" | trim_blank_lines
  echo

  if [[ -f "$TESTS_FILE" ]]; then
    echo "## Tests"
    echo
    echo "**실행 방법**:"
    echo
    extract_section "$TESTS_FILE" "^## 실행 방법" | trim_blank_lines
    echo
    echo "**통과 판정**:"
    echo
    extract_section "$TESTS_FILE" "^## 통과 판정" | trim_blank_lines
    echo
  fi

  if [[ ${#SCREENSHOTS[@]} -gt 0 || ${#VIDEOS[@]} -gt 0 ]]; then
    echo "## Test evidence"
    echo
    if [[ ${#VIDEOS[@]} -gt 0 ]]; then
      echo "### Videos"
      echo
      # Video URLs are filled in *after* PR creation (need PR number for manifest).
      # During PR creation, this placeholder line is in the body. After
      # attachments_upload returns URLs, we `gh pr edit` to replace it.
      echo "$VIDEO_PLACEHOLDER"
      echo
    fi
    if [[ ${#SCREENSHOTS[@]} -gt 0 ]]; then
      echo "### Screenshots"
      echo
      # Screenshots stay in .scv-pr-artifacts/<slug>/ committed to PR branch
      # (small files, OK to live in git history).
      for src in "${SCREENSHOTS[@]}"; do
        base=$(basename "$src")
        echo "![${base}]($ARTIFACTS_DIR/$SLUG_NAME/$base)"
        echo
      done
    fi
  fi

  # Refs (jira / linear / pr / etc.)
  refs_block=$(awk '
    /^## / { if (in_refs) exit }
    /^---$/ { fm++ }
    fm==1 && /^refs:[[:space:]]*$/ { in_block=1; next }
    fm==1 && in_block && /^[^ ]/ { in_block=0 }
    fm==1 && in_block { print }
  ' "$PLAN_FILE")
  if [[ -n "$refs_block" ]]; then
    echo "## External refs"
    echo
    echo '```yaml'
    echo "$refs_block" | trim_blank_lines
    echo '```'
    echo
  fi

  if [[ -f "$ARCHIVED_AT_FILE" ]]; then
    archived_at=$(yaml_get "$ARCHIVED_AT_FILE" archived_at)
    archived_by=$(yaml_get "$ARCHIVED_AT_FILE" archived_by)
    echo "---"
    echo
    echo "🗂  Archived ${archived_at:-?} by ${archived_by:-?} · plan: \`$TARGET_DIR/PLAN.md\`"
    if [[ -n "$EPIC" ]]; then
      echo "🎯  Epic: \`$EPIC\` · kind: \`$KIND\`"
    fi
  fi
} > "$TMP_BODY"

# ---- dry-run path ----
if [[ $DRY_RUN -eq 1 ]]; then
  echo "=== PR title ==="
  if [[ "$KIND" == "refactor" ]]; then
    echo "refactor: $TITLE"
  elif [[ "$KIND" == "retirement" ]]; then
    echo "chore: $TITLE"
  else
    echo "feat: $TITLE"
  fi
  echo ""
  echo "=== PR base branch ==="
  if [[ -n "$EPIC" ]]; then
    echo "epic/$EPIC"
  else
    echo "main"
  fi
  echo ""
  echo "=== Screenshots to attach ==="
  if [[ ${#SCREENSHOTS[@]} -gt 0 ]]; then
    printf '  · %s\n' "${SCREENSHOTS[@]}"
  else
    echo "  (none in $TEST_RESULTS_DIR)"
  fi
  echo ""
  echo "=== Videos to attach (via $ATTACHMENTS_BRANCH orphan branch) ==="
  if [[ ${#VIDEOS[@]} -gt 0 ]]; then
    printf '  · %s\n' "${VIDEOS[@]}"
    echo "  (each → https://github.com/<owner>/<repo>/raw/$ATTACHMENTS_BRANCH/$SLUG_NAME/<file>)"
  else
    echo "  (none in $TEST_RESULTS_DIR)"
  fi
  echo ""
  echo "=== PR body ==="
  cat "$TMP_BODY"
  rm -f "$TMP_BODY"
  exit 0
fi

# ---- move screenshots into committable location ----
DEST_ARTIFACTS_DIR="$ARTIFACTS_DIR/$SLUG_NAME"
if [[ ${#SCREENSHOTS[@]} -gt 0 ]]; then
  mkdir -p "$DEST_ARTIFACTS_DIR"
  for src in "${SCREENSHOTS[@]}"; do
    base=$(basename "$src")
    mv "$src" "$DEST_ARTIFACTS_DIR/$base"
  done
  echo "Moved ${#SCREENSHOTS[@]} screenshot(s) → $DEST_ARTIFACTS_DIR/"
fi

# ---- determine branches ----
if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git not available" >&2
  rm -f "$TMP_BODY"
  exit 1
fi

CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)
if [[ -z "$CURRENT_BRANCH" || "$CURRENT_BRANCH" == "HEAD" ]]; then
  echo "ERROR: not on a named branch (detached HEAD?)" >&2
  rm -f "$TMP_BODY"
  exit 1
fi

if [[ -n "$EPIC" ]]; then
  BASE_BRANCH="epic/$EPIC"
else
  BASE_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')
  [[ -z "$BASE_BRANCH" ]] && BASE_BRANCH="main"
fi

if [[ "$CURRENT_BRANCH" == "$BASE_BRANCH" ]]; then
  echo "ERROR: current branch ($CURRENT_BRANCH) equals base branch ($BASE_BRANCH). Switch to a feature branch first." >&2
  rm -f "$TMP_BODY"
  exit 1
fi

# ---- stage + commit ----
git add "$TARGET_DIR" 2>/dev/null || true
[[ -d "$DEST_ARTIFACTS_DIR" ]] && git add "$DEST_ARTIFACTS_DIR" 2>/dev/null
if git diff --cached --quiet; then
  echo "(no staged changes — assuming already committed)"
else
  COMMIT_PREFIX="feat"
  [[ "$KIND" == "refactor" ]] && COMMIT_PREFIX="refactor"
  [[ "$KIND" == "retirement" ]] && COMMIT_PREFIX="chore"
  git commit -q -m "$COMMIT_PREFIX: $TITLE

Archived $SLUG_NAME (${KIND}${EPIC:+, epic=$EPIC})."
  echo "Committed: $COMMIT_PREFIX: $TITLE"
fi

# ---- push current + ensure base branch exists on remote ----
if [[ $NO_PUSH -eq 0 ]]; then
  # Ensure base branch exists on origin (create from origin/main if missing)
  if [[ -n "$EPIC" ]]; then
    if ! git ls-remote --exit-code --heads origin "$BASE_BRANCH" >/dev/null 2>&1; then
      echo "Creating remote $BASE_BRANCH from origin/main ..."
      git fetch origin main >/dev/null 2>&1 || true
      git push origin "origin/main:refs/heads/$BASE_BRANCH" 2>&1 || {
        echo "ERROR: failed to create $BASE_BRANCH on origin" >&2
        rm -f "$TMP_BODY"
        exit 1
      }
    fi
  fi
  echo "Pushing $CURRENT_BRANCH to origin ..."
  git push -u origin "$CURRENT_BRANCH" 2>&1 || {
    echo "ERROR: git push failed" >&2
    rm -f "$TMP_BODY"
    exit 1
  }
fi

# ---- create PR ----
if [[ $NO_CREATE -eq 0 ]]; then
  if ! command -v gh >/dev/null 2>&1; then
    echo "ERROR: gh CLI not available — cannot create PR. Install: https://cli.github.com/" >&2
    echo "PR body saved at: $TMP_BODY"
    exit 1
  fi

  # Self-amortizing cleanup of stale attachments before adding new ones
  if [[ ${#VIDEOS[@]} -gt 0 ]]; then
    echo "Cleaning up stale attachments (retention=${SCV_ATTACHMENTS_RETENTION_DAYS:-3} days)..."
    attachments_cleanup_stale 2>&1 | sed 's/^/  /' || true
  fi

  TITLE_PREFIX="feat"
  [[ "$KIND" == "refactor" ]] && TITLE_PREFIX="refactor"
  [[ "$KIND" == "retirement" ]] && TITLE_PREFIX="chore"
  if PR_URL=$(gh pr create --base "$BASE_BRANCH" --head "$CURRENT_BRANCH" \
       --title "$TITLE_PREFIX: $TITLE" --body-file "$TMP_BODY" 2>&1); then
    echo "PR created: $PR_URL"
  else
    echo "ERROR: gh pr create failed:" >&2
    echo "$PR_URL" >&2
    echo "PR body saved at: $TMP_BODY"
    exit 1
  fi

  # ---- Phase 2: upload videos + edit PR body to replace placeholder ----
  if [[ ${#VIDEOS[@]} -gt 0 ]]; then
    # Extract PR number from URL (last path segment)
    PR_NUMBER="${PR_URL##*/}"
    if [[ ! "$PR_NUMBER" =~ ^[0-9]+$ ]]; then
      echo "WARN: could not parse PR number from URL '$PR_URL' — skipping video attach" >&2
    else
      echo "Uploading ${#VIDEOS[@]} video(s) to $ATTACHMENTS_BRANCH orphan branch..."
      VIDEO_URLS=$(attachments_upload "$SLUG_NAME" "$PR_NUMBER" "${VIDEOS[@]}" 2>&1)
      upload_rc=$?
      if [[ $upload_rc -eq 0 && -n "$VIDEO_URLS" ]]; then
        # Build markdown video block from URLs
        VIDEO_MD=""
        while IFS= read -r url; do
          [[ -z "$url" ]] && continue
          base="${url##*/}"
          VIDEO_MD+="![${base}](${url})"$'\n\n'
        done <<< "$VIDEO_URLS"

        # Replace placeholder in body file using Python (simpler escape handling)
        UPDATED_BODY=$(mktemp)
        python3 - "$TMP_BODY" "$UPDATED_BODY" "$VIDEO_PLACEHOLDER" "$VIDEO_MD" <<'PY'
import sys
src, dst, placeholder, replacement = sys.argv[1:]
with open(src) as f: body = f.read()
body = body.replace(placeholder, replacement.rstrip("\n"))
with open(dst, "w") as f: f.write(body)
PY
        if gh pr edit "$PR_NUMBER" --body-file "$UPDATED_BODY" >/dev/null 2>&1; then
          echo "PR body updated with ${#VIDEOS[@]} video link(s)"
        else
          echo "WARN: failed to update PR body with video links" >&2
        fi
        rm -f "$UPDATED_BODY"
      else
        echo "WARN: video upload failed:" >&2
        echo "$VIDEO_URLS" | sed 's/^/  /' >&2
        echo "PR body still has placeholder — remove manually if desired." >&2
      fi
    fi
  fi
fi

rm -f "$TMP_BODY"
exit 0
