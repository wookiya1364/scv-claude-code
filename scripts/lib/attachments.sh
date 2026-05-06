#!/usr/bin/env bash
# scripts/lib/attachments.sh — backend abstraction for PR media attachments.
#
# Backends:
#   git-orphan (default, v0.3)  — pushes binaries to a 'scv-attachments' orphan
#                                 branch in the same repo. PR body links to
#                                 GitHub raw URLs. Auto-cleanup after PR merge
#                                 + N days (manifest + gh API).
#   s3        (v0.4 — stub returns warning + falls back to git-orphan)
#   r2        (v0.4 — stub returns warning + falls back to git-orphan)
#
# Public API (sourced by pr-helper.sh, status.sh):
#
#   attachments_upload <slug> <pr_number> <file...>
#     stdout: one URL per file (in same order). exit 0 on success, ≠0 on fail.
#     Side effects: pushes binaries to backend. Removes local source files
#     after successful upload (caller-aware: don't pass files you still need).
#
#   attachments_cleanup_stale
#     Reads manifest, queries `gh pr view` for each entry, deletes folders +
#     manifest entries whose PR is non-OPEN AND closedAt+retention has passed.
#     Outputs "DELETED <slug>" lines for each cleanup. No fail = silent OK.
#
#   attachments_status
#     stdout: "active=N stale=N total_size_bytes=N" — single line for
#     /scv:status to surface. (stale count is "?" in v0.3 — gh API per-call
#     too costly; v0.4 will cache.)
#
# Configuration via env vars (loaded from project .env via lib/env.sh):
#   SCV_ATTACHMENTS_BACKEND=git-orphan|s3|r2  (default: git-orphan)
#   SCV_ATTACHMENTS_RETENTION_DAYS=N|never    (default: 3)
#   SCV_ATTACHMENTS_BRANCH=scv-attachments    (git-orphan only)
#
# Dependencies: git, gh CLI (for cleanup), python3 (manifest JSON manipulation).

# Source pr-platform abstraction (v0.5+). Used for raw URL construction —
# GitHub uses /raw/, GitLab uses /-/raw/. Idempotent if already sourced.
if ! declare -F pr_raw_url >/dev/null 2>&1; then
  _SCV_LIB_DIR_ATT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
  if [[ -f "$_SCV_LIB_DIR_ATT/pr-platform.sh" ]]; then
    # shellcheck source=pr-platform.sh
    source "$_SCV_LIB_DIR_ATT/pr-platform.sh"
  fi
fi

# Defaults — note these are captured at SOURCE time. Functions below re-read
# the SCV_ATTACHMENTS_* vars at CALL time so .env loaded after sourcing this
# library still takes effect (e.g., pr-helper.sh sources lib then env_load).
ATTACHMENTS_BRANCH_DEFAULT="scv-attachments"
RETENTION_DAYS_DEFAULT="3"

# ============================================================================
# Public API — backend dispatch
# ============================================================================

attachments_upload() {
  local backend="${SCV_ATTACHMENTS_BACKEND:-git-orphan}"
  case "$backend" in
    git-orphan) _attachments_git_orphan_upload "$@" ;;
    s3)
      echo "WARN: s3 backend not yet implemented (planned for v0.4). Falling back to git-orphan." >&2
      _attachments_git_orphan_upload "$@"
      ;;
    r2)
      echo "WARN: r2 backend not yet implemented (planned for v0.4). Falling back to git-orphan." >&2
      _attachments_git_orphan_upload "$@"
      ;;
    *)
      echo "ERROR: unknown SCV_ATTACHMENTS_BACKEND='$backend' (expected: git-orphan|s3|r2)" >&2
      return 1
      ;;
  esac
}

attachments_cleanup_stale() {
  # Re-read env at call time (caller may have loaded .env after sourcing lib)
  local retention="${SCV_ATTACHMENTS_RETENTION_DAYS:-$RETENTION_DAYS_DEFAULT}"
  if [[ "$retention" == "never" ]]; then
    return 0
  fi
  local backend="${SCV_ATTACHMENTS_BACKEND:-git-orphan}"
  case "$backend" in
    git-orphan|s3|r2) _attachments_git_orphan_cleanup_stale "$@" ;;
    *) return 0 ;;
  esac
}

attachments_status() {
  local backend="${SCV_ATTACHMENTS_BACKEND:-git-orphan}"
  case "$backend" in
    git-orphan|s3|r2) _attachments_git_orphan_status "$@" ;;
    *) echo "active=? stale=? total_size_bytes=?" ;;
  esac
}

# ============================================================================
# git-orphan backend
# ============================================================================

# Parse origin remote URL → "owner/repo". Supports https + ssh forms.
# Returns 0 + prints "owner/repo" on GitHub remote, returns 1 otherwise.
_get_github_owner_repo() {
  local url; url=$(git remote get-url origin 2>/dev/null || echo "")
  if [[ "$url" =~ github\.com[:/]([^/]+)/([^/.]+) ]]; then
    local owner="${BASH_REMATCH[1]}"
    local repo="${BASH_REMATCH[2]}"
    repo="${repo%.git}"
    echo "$owner/$repo"
    return 0
  fi
  return 1
}

# Open a worktree at the orphan branch. Creates the branch if absent.
# Echoes the worktree path. Caller MUST call _orphan_worktree_close when done.
_orphan_worktree_open() {
  local ATTACHMENTS_BRANCH="${SCV_ATTACHMENTS_BRANCH:-$ATTACHMENTS_BRANCH_DEFAULT}"
  local wt; wt=$(mktemp -d -t scv-attachments.XXXXXX)

  # Defensive cleanup of any leftover local branch / worktree from prior runs.
  # Without this, if origin has the branch deleted but local branch lingers
  # (e.g., user previously deleted origin manually), `git checkout --orphan`
  # silently fails and pushes the stale local branch back to origin — losing
  # any new commits made on detached HEAD.
  local existing_wt
  existing_wt=$(git worktree list --porcelain 2>/dev/null \
    | awk -v b="refs/heads/$ATTACHMENTS_BRANCH" '
        /^worktree / {p=$2}
        /^branch / && $2==b {print p}
      ')
  if [[ -n "$existing_wt" ]]; then
    git worktree remove --force "$existing_wt" >/dev/null 2>&1 || true
  fi

  if git ls-remote --exit-code --heads origin "$ATTACHMENTS_BRANCH" >/dev/null 2>&1; then
    git fetch origin "$ATTACHMENTS_BRANCH" >/dev/null 2>&1 || true
    # Update local tracking ref to remote state (handles case where remote
    # was deleted then recreated — local origin/<branch> may be stale).
    git update-ref "refs/remotes/origin/$ATTACHMENTS_BRANCH" \
      "$(git ls-remote origin "$ATTACHMENTS_BRANCH" | awk '{print $1}')" 2>/dev/null || true
    # Reset local branch to match origin (or create new if absent).
    git branch -D "$ATTACHMENTS_BRANCH" >/dev/null 2>&1 || true
    git worktree add "$wt" "origin/$ATTACHMENTS_BRANCH" >/dev/null 2>&1
    (cd "$wt" && git checkout -B "$ATTACHMENTS_BRANCH" "origin/$ATTACHMENTS_BRANCH" >/dev/null 2>&1)

    # Auto-migrate v0.3.0 layout → v0.3.1 layout:
    #   root/manifest.json + root/<slug>/  →  scv/manifest.json + scv/<slug>/
    # Centralizes all SCV-managed files under the scv/ subdirectory so the
    # orphan branch root stays empty (only README.md), matching how SCV
    # organizes things on the user's main branch (everything under scv/).
    # Idempotent — skipped once scv/manifest.json exists.
    if [[ -f "$wt/manifest.json" && ! -f "$wt/scv/manifest.json" ]]; then
      if (
        cd "$wt"
        mkdir -p scv
        git mv manifest.json scv/manifest.json >/dev/null 2>&1 || exit 1
        # Move every root-level directory (slug folders) into scv/.
        # Skip 'scv' itself, README.md, and dot-entries.
        for entry in *; do
          [[ "$entry" == "scv" ]] && continue
          [[ "$entry" == "README.md" ]] && continue
          if [[ -d "$entry" ]]; then
            git mv "$entry" "scv/$entry" >/dev/null 2>&1 || exit 1
          fi
        done
        git commit -q -m "Migrate v0.3.0 layout → scv/ subdirectory (v0.3.1)"
        git push origin "$ATTACHMENTS_BRANCH" >/dev/null 2>&1
      ); then
        echo "Migrated v0.3.0 layout → scv/ on $ATTACHMENTS_BRANCH" >&2
      fi
    fi
  else
    # Origin doesn't have it — create fresh orphan. Delete any stale local
    # branch first (it would block `git checkout --orphan`).
    git branch -D "$ATTACHMENTS_BRANCH" >/dev/null 2>&1 || true
    # Also clear stale remote-tracking ref if any.
    git update-ref -d "refs/remotes/origin/$ATTACHMENTS_BRANCH" 2>/dev/null || true

    git worktree add --detach "$wt" >/dev/null 2>&1
    (
      cd "$wt"
      git checkout --orphan "$ATTACHMENTS_BRANCH" >/dev/null 2>&1 || {
        echo "ERROR: failed to create orphan branch in worktree" >&2
        exit 1
      }
      git rm -rf . >/dev/null 2>&1 || true
      cat > README.md <<'README_EOF'
# SCV PR Attachments

This branch is auto-managed by the SCV plugin. PR media (videos, screenshots)
are stored here, embedded into PR bodies via raw URLs.

After PR merge + N days (configurable in `.env` `SCV_ATTACHMENTS_RETENTION_DAYS`,
default 3), each slug folder is deleted automatically.

All SCV-managed state lives under the `scv/` subdirectory (`scv/manifest.json`
+ `scv/<slug>/...`). Root stays clean except for this README.

**Do not commit to this branch manually** — `scripts/pr-helper.sh` handles it.
README_EOF
      mkdir -p scv
      cat > scv/manifest.json <<'MANIFEST_EOF'
{
  "version": 1,
  "entries": {}
}
MANIFEST_EOF
      git add README.md scv/manifest.json
      git commit -q -m "Initialize scv-attachments orphan branch"
    ) || {
      _orphan_worktree_close "$wt"
      return 1
    }
  fi
  echo "$wt"
}

# Tear down a worktree opened by _orphan_worktree_open.
_orphan_worktree_close() {
  local wt="$1"
  [[ -z "$wt" ]] && return 0
  git worktree remove --force "$wt" 2>/dev/null || true
  rm -rf "$wt" 2>/dev/null || true
}

_attachments_git_orphan_upload() {
  local ATTACHMENTS_BRANCH="${SCV_ATTACHMENTS_BRANCH:-$ATTACHMENTS_BRANCH_DEFAULT}"
  local slug="$1" pr_number="$2"; shift 2
  local files=("$@")
  [[ ${#files[@]} -eq 0 ]] && return 0

  # Sanity check: origin must be configured. Owner_repo extraction is
  # delegated to pr-platform abstraction (v0.5+ supports GitHub + GitLab) at
  # the raw-URL site below — extraction failure here is non-fatal because
  # tests / sandbox runs may use bare repos where the URL doesn't match
  # github/gitlab patterns.
  if ! git remote get-url origin >/dev/null 2>&1; then
    echo "ERROR: git remote 'origin' not configured" >&2
    return 1
  fi
  local owner_repo=""
  if declare -F pr_get_owner_repo >/dev/null 2>&1; then
    owner_repo=$(pr_get_owner_repo 2>/dev/null) || true
  else
    owner_repo=$(_get_github_owner_repo 2>/dev/null) || true
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required for manifest management" >&2
    return 1
  fi

  local wt; wt=$(_orphan_worktree_open)

  # Copy files into <slug>/
  local dst="$wt/scv/$slug"
  mkdir -p "$dst"
  local urls=()
  local copied_files=()
  for f in "${files[@]}"; do
    [[ -f "$f" ]] || continue
    # Size guard
    local size_bytes; size_bytes=$(wc -c <"$f" 2>/dev/null | tr -d ' ')
    local size_mb=$((size_bytes / 1024 / 1024))
    if [[ $size_mb -gt 100 ]]; then
      echo "ERROR: $f is ${size_mb}MB (>100MB git limit). Skipping." >&2
      continue
    elif [[ $size_mb -gt 50 ]]; then
      echo "WARN: $f is ${size_mb}MB (>50MB warn threshold). Pushing anyway." >&2
    fi
    local base; base=$(basename "$f")
    cp "$f" "$dst/$base"
    copied_files+=("$f")
    # Use /raw/ URL — redirects to raw.githubusercontent.com which serves the
    # binary directly with correct MIME. Two reasons:
    #  - For .gif: markdown ![](url) inline-renders image (blob URL would be
    #    a HTML page, can't be rendered as image)
    #  - For .webm/.mp4: clicking opens browser native HTML5 player in new tab
    #    (blob URL only shows "View raw" link, GitHub doesn't render inline
    #    video player for repo content — only user-attachments domain does)
    # Raw URL via platform abstraction (v0.5+). Falls back to GitHub-hardcoded
    # form if pr_raw_url isn't available (defensive — should always be sourced).
    if declare -F pr_raw_url >/dev/null 2>&1; then
      urls+=("$(pr_raw_url "$ATTACHMENTS_BRANCH" "scv/${slug}/${base}")")
    else
      urls+=("https://github.com/${owner_repo}/raw/${ATTACHMENTS_BRANCH}/scv/${slug}/${base}")
    fi
  done

  if [[ ${#copied_files[@]} -eq 0 ]]; then
    _orphan_worktree_close "$wt"
    echo "ERROR: no files were uploadable (all skipped due to size limit)" >&2
    return 1
  fi

  # Update manifest via python3 (handles JSON safely)
  local now_iso; now_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  python3 - "$wt/scv/manifest.json" "$slug" "$pr_number" "$now_iso" <<'PY'
import json, sys
mf, slug, pr, now = sys.argv[1:]
try:
    with open(mf) as f: m = json.load(f)
except Exception:
    m = {"version": 1, "entries": {}}
m.setdefault("entries", {})[slug] = {"pr_number": int(pr), "created_at": now}
with open(mf, "w") as f:
    json.dump(m, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
  local mf_rc=$?
  if [[ $mf_rc -ne 0 ]]; then
    _orphan_worktree_close "$wt"
    echo "ERROR: failed to update scv/manifest.json" >&2
    return 1
  fi

  # Commit + push from worktree
  local push_ok=1
  (
    cd "$wt"
    git add "scv/$slug/" scv/manifest.json
    if git diff --cached --quiet; then
      echo "(no new attachments to push)"
      exit 0
    fi
    git commit -q -m "Add attachments for $slug (PR #$pr_number)"
    git push origin "$ATTACHMENTS_BRANCH" >/dev/null 2>&1 || exit 1
  ) || push_ok=0

  _orphan_worktree_close "$wt"

  if [[ $push_ok -eq 0 ]]; then
    echo "ERROR: failed to push $ATTACHMENTS_BRANCH to origin" >&2
    return 1
  fi

  # Output URLs (one per line, same order as inputs that were copied)
  printf '%s\n' "${urls[@]}"

  # Local cleanup of source files (per spec: "delete after PR upload")
  for f in "${copied_files[@]}"; do
    rm -f "$f"
  done

  return 0
}

# Count stale entries in an scv/manifest.json by querying gh API per pr_number.
# Echoes the integer count on stdout. Returns:
#   - 0 (printed "0") if retention is 'never' or non-integer (nothing stale by definition).
#   - empty stdout if gh / python3 / manifest unavailable (caller treats as unknown).
_compute_stale_count() {
  local manifest="$1" retention="$2"
  command -v gh >/dev/null 2>&1 || return 0
  command -v python3 >/dev/null 2>&1 || return 0
  [[ -f "$manifest" ]] || return 0
  python3 - "$manifest" "$retention" <<'PY'
import json, sys, subprocess, datetime as dt
mf, retention_str = sys.argv[1], sys.argv[2]
try:
    retention = int(retention_str)
except ValueError:
    print(0); sys.exit(0)
with open(mf) as f:
    m = json.load(f)
now = dt.datetime.now(dt.timezone.utc)
count = 0
for slug, e in m.get("entries", {}).items():
    pr = e.get("pr_number")
    if not pr:
        continue
    try:
        out = subprocess.run(
            ["gh", "pr", "view", str(pr), "--json", "state,closedAt"],
            capture_output=True, text=True, check=True, timeout=10
        ).stdout
        pr_info = json.loads(out)
    except Exception:
        continue
    if pr_info.get("state") == "OPEN":
        continue
    closed_at = pr_info.get("closedAt")
    if not closed_at:
        continue
    try:
        closed_dt = dt.datetime.fromisoformat(closed_at.replace("Z", "+00:00"))
    except Exception:
        continue
    if (now - closed_dt).days >= retention:
        count += 1
print(count)
PY
}

_attachments_git_orphan_cleanup_stale() {
  local ATTACHMENTS_BRANCH="${SCV_ATTACHMENTS_BRANCH:-$ATTACHMENTS_BRANCH_DEFAULT}"
  local RETENTION_DAYS="${SCV_ATTACHMENTS_RETENTION_DAYS:-$RETENTION_DAYS_DEFAULT}"
  command -v gh >/dev/null 2>&1 || return 0   # silently skip if gh missing
  command -v python3 >/dev/null 2>&1 || return 0

  local owner_repo
  _get_github_owner_repo >/dev/null || return 0

  if ! git ls-remote --exit-code --heads origin "$ATTACHMENTS_BRANCH" >/dev/null 2>&1; then
    return 0   # nothing to clean
  fi

  local wt; wt=$(_orphan_worktree_open)

  if [[ ! -f "$wt/scv/manifest.json" ]]; then
    _orphan_worktree_close "$wt"
    return 0
  fi

  # Read manifest, compute stale slugs (state ≠ OPEN AND closedAt + N days < now)
  local stale_slugs
  stale_slugs=$(python3 - "$wt/scv/manifest.json" "$RETENTION_DAYS" <<'PY'
import json, sys, subprocess, datetime as dt
mf, retention_str = sys.argv[1], sys.argv[2]
try:
    retention = int(retention_str)
except ValueError:
    sys.exit(0)   # 'never' or malformed → no cleanup

with open(mf) as f:
    m = json.load(f)
now = dt.datetime.now(dt.timezone.utc)
stale = []
for slug, e in m.get("entries", {}).items():
    pr = e.get("pr_number")
    if not pr:
        continue
    try:
        out = subprocess.run(
            ["gh", "pr", "view", str(pr), "--json", "state,closedAt"],
            capture_output=True, text=True, check=True, timeout=10
        ).stdout
        pr_info = json.loads(out)
    except Exception:
        continue   # 404 / network error → keep entry
    if pr_info.get("state") == "OPEN":
        continue   # PR still open → keep
    closed_at = pr_info.get("closedAt")
    if not closed_at:
        continue
    try:
        closed_dt = dt.datetime.fromisoformat(closed_at.replace("Z", "+00:00"))
    except Exception:
        continue
    age_days = (now - closed_dt).days
    if age_days >= retention:
        stale.append(slug)
print("\n".join(stale))
PY
)

  if [[ -z "$stale_slugs" ]]; then
    _orphan_worktree_close "$wt"
    return 0   # nothing stale
  fi

  # Delete stale folders + manifest entries
  while IFS= read -r slug; do
    [[ -z "$slug" ]] && continue
    rm -rf "$wt/scv/$slug"
    echo "DELETED $slug"
    python3 - "$wt/scv/manifest.json" "$slug" <<'PY'
import json, sys
mf, slug = sys.argv[1:]
with open(mf) as f: m = json.load(f)
m.get("entries", {}).pop(slug, None)
with open(mf, "w") as f:
    json.dump(m, f, indent=2, ensure_ascii=False)
    f.write("\n")
PY
  done <<< "$stale_slugs"

  # Commit + push cleanup
  (
    cd "$wt"
    git add -A
    if git diff --cached --quiet; then
      exit 0
    fi
    git commit -q -m "Cleanup stale attachments (retention=${RETENTION_DAYS}d)"
    git push origin "$ATTACHMENTS_BRANCH" >/dev/null 2>&1 || true
  )

  _orphan_worktree_close "$wt"
}

_attachments_git_orphan_status() {
  local ATTACHMENTS_BRANCH="${SCV_ATTACHMENTS_BRANCH:-$ATTACHMENTS_BRANCH_DEFAULT}"
  local RETENTION_DAYS="${SCV_ATTACHMENTS_RETENTION_DAYS:-$RETENTION_DAYS_DEFAULT}"
  if ! git ls-remote --exit-code --heads origin "$ATTACHMENTS_BRANCH" >/dev/null 2>&1; then
    echo "active=0 stale=0 total_size_bytes=0"
    return 0
  fi

  # Cache lookup. Key = owner/repo + retention (different retention →
  # different stale count). Invalidated on SHA mismatch (push happened) or
  # TTL expiry. Graceful degrade to "?" if gh / python3 missing or any error.
  local stale_count="?"
  local owner_repo head_sha cache_file
  local ttl="${SCV_STATUS_CACHE_TTL:-300}"
  owner_repo=$(_get_github_owner_repo 2>/dev/null || echo "")
  head_sha=$(git ls-remote origin "$ATTACHMENTS_BRANCH" 2>/dev/null | awk '{print $1}')
  if [[ -n "$head_sha" && -n "$owner_repo" ]]; then
    cache_file="/tmp/scv-attachments-status-${owner_repo//\//_}-${RETENTION_DAYS}.json"
    if [[ -f "$cache_file" ]] && command -v python3 >/dev/null 2>&1; then
      local cached_age cached_sha cached_stale
      cached_age=$(( $(date +%s) - $(stat -c %Y "$cache_file" 2>/dev/null || echo 0) ))
      cached_sha=$(python3 -c "import json,sys;sys.stdout.write(str(json.load(open('$cache_file')).get('head_sha','')))" 2>/dev/null)
      cached_stale=$(python3 -c "import json,sys;sys.stdout.write(str(json.load(open('$cache_file')).get('stale','?')))" 2>/dev/null)
      if [[ "$cached_sha" == "$head_sha" && "$cached_age" -lt "$ttl" && "$cached_stale" =~ ^[0-9]+$ ]]; then
        stale_count="$cached_stale"
      fi
    fi
  fi

  local wt; wt=$(_orphan_worktree_open)

  local active=0
  if [[ -f "$wt/scv/manifest.json" ]] && command -v python3 >/dev/null 2>&1; then
    active=$(python3 -c "import json; print(len(json.load(open('$wt/scv/manifest.json')).get('entries', {})))")
  fi
  local size; size=$(du -sb "$wt" 2>/dev/null | awk '{print $1}')

  # Cache miss → compute fresh count via gh API + write cache.
  if [[ "$stale_count" == "?" ]]; then
    local fresh_count
    fresh_count=$(_compute_stale_count "$wt/scv/manifest.json" "$RETENTION_DAYS" 2>/dev/null)
    if [[ "$fresh_count" =~ ^[0-9]+$ ]]; then
      stale_count="$fresh_count"
      if [[ -n "$cache_file" && -n "$head_sha" ]]; then
        printf '{"head_sha":"%s","stale":%d}\n' "$head_sha" "$stale_count" \
          > "$cache_file" 2>/dev/null || true
      fi
    fi
  fi

  echo "active=${active:-0} stale=${stale_count} total_size_bytes=${size:-0}"
  _orphan_worktree_close "$wt"
}
