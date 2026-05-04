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
# shellcheck source=lib/pr-platform.sh
source "$SCRIPT_DIR/lib/pr-platform.sh"

# Load project .env so SCV_ATTACHMENTS_* vars are visible
env_load 2>/dev/null || true

ARCHIVE_DIR="${ARCHIVE_DIR:-scv/archive}"
ARTIFACTS_DIR="${ARTIFACTS_DIR:-.scv-pr-artifacts}"
TEST_RESULTS_DIR="${TEST_RESULTS_DIR:-test-results}"
VIDEO_PLACEHOLDER="<!-- SCV_VIDEO_PLACEHOLDER -->"
ATTACHMENTS_BRANCH="${SCV_ATTACHMENTS_BRANCH:-scv-attachments}"

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
FEATURE_ARCH_FILE="$TARGET_DIR/FEATURE_ARCHITECTURE.md"

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

# ---- collect videos from test-results/ (SCV's standard video folder) ----
# SCV's standard E2E framework is Playwright (Step 5b). Playwright's default
# output folder is test-results/. Other frameworks (Cypress, etc.) work too
# as long as their videos land here — Cypress users redirect via the
# `videosFolder` option in cypress.config. See work.md Step 5b for full stance.
VIDEOS=()
if [[ -d "$TEST_RESULTS_DIR" ]]; then
  while IFS= read -r f; do
    [[ -f "$f" ]] && VIDEOS+=("$f")
  done < <(find "$TEST_RESULTS_DIR" -type f \( -iname '*.webm' -o -iname '*.mp4' \) 2>/dev/null | LC_ALL=C sort)
fi

# ---- generate GIFs from videos (if ffmpeg available) ----
# GitHub renders ![](.gif) inline in PR body but does NOT render <video> or
# bare .webm/.mp4 URLs as inline player (only drag-drop user-attachments do).
# So we make a silent GIF preview alongside each video — body has both:
#   - inline GIF (auto-render in PR body)
#   - link to .webm (click → browser native player, with audio)
GIFS=()
GIF_BY_VIDEO=()  # parallel to VIDEOS — empty string if no GIF for that index
GIF_WIDTH="${SCV_GIF_WIDTH:-480}"
GIF_FPS="${SCV_GIF_FPS:-10}"
GIF_MAX_SECONDS="${SCV_GIF_MAX_SECONDS:-60}"

if [[ ${#VIDEOS[@]} -gt 0 ]] && command -v ffmpeg >/dev/null 2>&1; then
  for v in "${VIDEOS[@]}"; do
    gif_path="${v%.*}.gif"
    # Cap duration: very long recordings make huge GIFs. Trim to first N seconds.
    # Use 2-pass palette generation for reasonable quality:
    #   pass 1: generate optimized 256-color palette
    #   pass 2: encode using palette
    palette_path="${v%.*}.palette.png"
    if ffmpeg -nostdin -y -loglevel error \
         -t "$GIF_MAX_SECONDS" -i "$v" \
         -vf "fps=${GIF_FPS},scale=${GIF_WIDTH}:-1:flags=lanczos,palettegen=stats_mode=diff" \
         "$palette_path" 2>/dev/null \
       && ffmpeg -nostdin -y -loglevel error \
         -t "$GIF_MAX_SECONDS" -i "$v" -i "$palette_path" \
         -lavfi "fps=${GIF_FPS},scale=${GIF_WIDTH}:-1:flags=lanczos [x]; [x][1:v] paletteuse=dither=bayer:bayer_scale=5" \
         -loop 0 "$gif_path" 2>/dev/null \
       && [[ -f "$gif_path" ]]; then
      GIFS+=("$gif_path")
      GIF_BY_VIDEO+=("$gif_path")
      rm -f "$palette_path"
    else
      GIF_BY_VIDEO+=("")
      rm -f "$palette_path"
    fi
  done
elif [[ ${#VIDEOS[@]} -gt 0 ]]; then
  # ffmpeg missing — graceful degrade
  echo "Note: ffmpeg not found — skipping GIF preview generation. Videos will be link-only." >&2
  for v in "${VIDEOS[@]}"; do
    GIF_BY_VIDEO+=("")
  done
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

  # FEATURE_ARCHITECTURE.md (v0.7.1+) — extract ```mermaid``` fenced blocks and
  # inline them so GitHub / GitLab auto-render the diagrams in the PR / MR body.
  # The frontmatter, headings, and "Source:" line of FEATURE_ARCHITECTURE.md are
  # not included — only the Mermaid blocks themselves, prefixed with the section
  # heading they appeared under (## 1. ... / ## 2. ...).
  #
  # v0.7.2: END block guards against missing closing fence in the input —
  # if the LLM-generated FEATURE_ARCHITECTURE.md leaves a mermaid block open,
  # auto-close it so the rest of the PR body isn't swallowed into the block.
  # The mermaid renderer will mark the block as syntax-error rather than
  # corrupting the entire PR body.
  if [[ -f "$FEATURE_ARCH_FILE" ]]; then
    arch_blocks=$(awk '
      /^## [0-9]+\./ { current_heading=$0; next }
      /^```mermaid[[:space:]]*$/ { in_mermaid=1; if (current_heading) print "### " substr(current_heading, 4); print; next }
      in_mermaid && /^```[[:space:]]*$/ { print; print ""; in_mermaid=0; current_heading=""; next }
      in_mermaid { print }
      END { if (in_mermaid) { print "```"; print "" } }
    ' "$FEATURE_ARCH_FILE")
    if [[ -n "$arch_blocks" ]]; then
      echo "## Architecture diagrams"
      echo
      echo "$arch_blocks" | trim_blank_lines
      echo
    fi
  fi

  if [[ -f "$TESTS_FILE" ]]; then
    echo "## Tests"
    echo
    echo "**How to run**:"
    echo
    extract_section "$TESTS_FILE" "^## (How to run|실행 방법)" | trim_blank_lines
    echo
    echo "**Pass criteria**:"
    echo
    extract_section "$TESTS_FILE" "^## (Pass criteria|통과 판정)" | trim_blank_lines
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
      # (small files, OK to live in git history). Use absolute raw URL with
      # commit SHA so:
      #   - GitLab MR rendering resolves the image (relative paths don't
      #     work in GitLab MR descriptions, only in wikis)
      #   - GitHub doesn't trip over branch names with slashes (e.g.,
      #     'feat/foo/bar') that would produce ambiguous URL resolution
      #   - the URL stays valid even after the branch is merged/deleted
      # The actual HEAD SHA isn't known yet (the screenshot commit happens
      # later in the flow); embed a placeholder and substitute post-push.
      for src in "${SCREENSHOTS[@]}"; do
        base=$(basename "$src")
        ss_url=""
        if declare -F pr_raw_url >/dev/null 2>&1; then
          ss_url=$(pr_raw_url "__SCV_HEAD_SHA__" "$ARTIFACTS_DIR/$SLUG_NAME/$base" 2>/dev/null) || ss_url=""
        fi
        [[ -z "$ss_url" ]] && ss_url="$ARTIFACTS_DIR/$SLUG_NAME/$base"
        echo "![${base}](${ss_url})"
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
    for i in "${!VIDEOS[@]}"; do
      v="${VIDEOS[$i]}"
      gif="${GIF_BY_VIDEO[$i]:-}"
      if [[ -n "$gif" ]]; then
        echo "  · $v + GIF preview ($gif)"
      else
        echo "  · $v (no GIF — ffmpeg unavailable or conversion failed)"
      fi
    done
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

# ---- substitute screenshot SHA placeholder ----
# At body assembly the actual HEAD SHA wasn't known (screenshots committed
# in this run). Now post-push, swap __SCV_HEAD_SHA__ for the real SHA so
# the screenshot raw URLs resolve on both GitHub and GitLab.
if [[ ${#SCREENSHOTS[@]} -gt 0 ]]; then
  _ACTUAL_HEAD_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")
  if [[ -n "$_ACTUAL_HEAD_SHA" ]]; then
    sed -i "s|__SCV_HEAD_SHA__|$_ACTUAL_HEAD_SHA|g" "$TMP_BODY"
  fi
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
  if PR_URL=$(pr_create "$TITLE_PREFIX: $TITLE" "$TMP_BODY" "$BASE_BRANCH" "$CURRENT_BRANCH" 2>&1); then
    echo "PR created: $PR_URL"
  else
    echo "ERROR: PR creation failed:" >&2
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
      gif_count=${#GIFS[@]}
      total_files=$((${#VIDEOS[@]} + gif_count))
      echo "Uploading $total_files file(s) to $ATTACHMENTS_BRANCH orphan branch (${#VIDEOS[@]} video + $gif_count GIF preview)..."
      # Pass videos + gifs together — orphan upload returns URLs in input order
      VIDEO_URLS=$(attachments_upload "$SLUG_NAME" "$PR_NUMBER" "${VIDEOS[@]}" "${GIFS[@]}" 2>&1)
      upload_rc=$?
      if [[ $upload_rc -eq 0 && -n "$VIDEO_URLS" ]]; then
        # Build markdown — pair each video with its GIF preview by basename.
        # GitHub renders ![](.gif) inline as image (silent preview); .webm/.mp4
        # gets a clickable link (browser native player on click, with audio).
        declare -A url_by_filename=()
        while IFS= read -r u; do
          [[ -z "$u" ]] && continue
          fname="${u##*/}"
          url_by_filename["$fname"]="$u"
        done <<< "$VIDEO_URLS"

        VIDEO_MD=""
        for i in "${!VIDEOS[@]}"; do
          v="${VIDEOS[$i]}"
          v_base=$(basename "$v")
          v_url="${url_by_filename[$v_base]:-}"
          gif_path="${GIF_BY_VIDEO[$i]:-}"
          gif_url=""
          if [[ -n "$gif_path" ]]; then
            gif_base=$(basename "$gif_path")
            gif_url="${url_by_filename[$gif_base]:-}"
          fi

          # Inline GIF preview (auto-renders silently in PR body)
          if [[ -n "$gif_url" ]]; then
            VIDEO_MD+="![${v_base}](${gif_url})"$'\n\n'
          fi
          # Link to full video (audio + full quality)
          if [[ -n "$v_url" ]]; then
            if [[ -n "$gif_url" ]]; then
              VIDEO_MD+="- [▶ ${v_base}](${v_url}) — full video with audio (click to play in browser)"$'\n'
            else
              VIDEO_MD+="- [▶ ${v_base}](${v_url}) — click to play in browser native player (install ffmpeg for inline GIF previews)"$'\n'
            fi
          fi
        done

        # Replace placeholder in body file using Python (simpler escape handling)
        UPDATED_BODY=$(mktemp)
        python3 - "$TMP_BODY" "$UPDATED_BODY" "$VIDEO_PLACEHOLDER" "$VIDEO_MD" <<'PY'
import sys
src, dst, placeholder, replacement = sys.argv[1:]
with open(src) as f: body = f.read()
body = body.replace(placeholder, replacement.rstrip("\n"))
with open(dst, "w") as f: f.write(body)
PY
        # Update PR/MR body via platform abstraction. For GitHub: gh api PATCH
        # (avoids gh pr edit's exit 1 from GraphQL Projects deprecation). For
        # GitLab: curl PUT /merge_requests/<iid>.
        if pr_update_body "$PR_NUMBER" "$UPDATED_BODY" 2>/dev/null; then
          echo "PR body updated with ${#VIDEOS[@]} video link(s)"
        else
          echo "WARN: failed to update PR body with video links" >&2
          echo "  Updated body kept at: $UPDATED_BODY (manually copy if needed)" >&2
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
