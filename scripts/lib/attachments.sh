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

# Defaults — loaded after .env so caller can override
ATTACHMENTS_BRANCH="${SCV_ATTACHMENTS_BRANCH:-scv-attachments}"
RETENTION_DAYS="${SCV_ATTACHMENTS_RETENTION_DAYS:-3}"

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
  # 'never' retention → no cleanup
  if [[ "${RETENTION_DAYS:-3}" == "never" ]]; then
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
  local wt; wt=$(mktemp -d -t scv-attachments.XXXXXX)
  if git ls-remote --exit-code --heads origin "$ATTACHMENTS_BRANCH" >/dev/null 2>&1; then
    git fetch origin "$ATTACHMENTS_BRANCH" >/dev/null 2>&1 || true
    git worktree add "$wt" "origin/$ATTACHMENTS_BRANCH" >/dev/null 2>&1
    (cd "$wt" && git checkout -B "$ATTACHMENTS_BRANCH" >/dev/null 2>&1)
  else
    git worktree add --detach "$wt" >/dev/null 2>&1
    (
      cd "$wt"
      git checkout --orphan "$ATTACHMENTS_BRANCH" >/dev/null 2>&1
      git rm -rf . >/dev/null 2>&1 || true
      cat > README.md <<'README_EOF'
# SCV PR Attachments

This branch is auto-managed by the SCV plugin. PR media (videos, screenshots)
are stored here, embedded into PR bodies via raw URLs.

After PR merge + N days (configurable in `.env` `SCV_ATTACHMENTS_RETENTION_DAYS`,
default 3), each slug folder is deleted automatically.

**Do not commit to this branch manually** — `scripts/pr-helper.sh` handles it.
README_EOF
      cat > manifest.json <<'MANIFEST_EOF'
{
  "version": 1,
  "entries": {}
}
MANIFEST_EOF
      git add README.md manifest.json
      git commit -q -m "Initialize scv-attachments orphan branch"
    )
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
  local slug="$1" pr_number="$2"; shift 2
  local files=("$@")
  [[ ${#files[@]} -eq 0 ]] && return 0

  local owner_repo
  if ! owner_repo=$(_get_github_owner_repo); then
    echo "ERROR: not a GitHub remote — git-orphan backend requires github.com origin" >&2
    return 1
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    echo "ERROR: python3 is required for manifest management" >&2
    return 1
  fi

  local wt; wt=$(_orphan_worktree_open)

  # Copy files into <slug>/
  local dst="$wt/$slug"
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
    urls+=("https://github.com/${owner_repo}/raw/${ATTACHMENTS_BRANCH}/${slug}/${base}")
  done

  if [[ ${#copied_files[@]} -eq 0 ]]; then
    _orphan_worktree_close "$wt"
    echo "ERROR: no files were uploadable (all skipped due to size limit)" >&2
    return 1
  fi

  # Update manifest via python3 (handles JSON safely)
  local now_iso; now_iso=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  python3 - "$wt/manifest.json" "$slug" "$pr_number" "$now_iso" <<'PY'
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
    echo "ERROR: failed to update manifest.json" >&2
    return 1
  fi

  # Commit + push from worktree
  local push_ok=1
  (
    cd "$wt"
    git add "$slug/" manifest.json
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

  # Local cleanup of source files (per spec: "PR 올린 후 삭제")
  for f in "${copied_files[@]}"; do
    rm -f "$f"
  done

  return 0
}

_attachments_git_orphan_cleanup_stale() {
  command -v gh >/dev/null 2>&1 || return 0   # silently skip if gh missing
  command -v python3 >/dev/null 2>&1 || return 0

  local owner_repo
  _get_github_owner_repo >/dev/null || return 0

  if ! git ls-remote --exit-code --heads origin "$ATTACHMENTS_BRANCH" >/dev/null 2>&1; then
    return 0   # nothing to clean
  fi

  local wt; wt=$(_orphan_worktree_open)

  if [[ ! -f "$wt/manifest.json" ]]; then
    _orphan_worktree_close "$wt"
    return 0
  fi

  # Read manifest, compute stale slugs (state ≠ OPEN AND closedAt + N일 < now)
  local stale_slugs
  stale_slugs=$(python3 - "$wt/manifest.json" "$RETENTION_DAYS" <<'PY'
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
    rm -rf "$wt/$slug"
    echo "DELETED $slug"
    python3 - "$wt/manifest.json" "$slug" <<'PY'
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
  if ! git ls-remote --exit-code --heads origin "$ATTACHMENTS_BRANCH" >/dev/null 2>&1; then
    echo "active=0 stale=0 total_size_bytes=0"
    return 0
  fi
  local wt; wt=$(_orphan_worktree_open)

  local active=0
  if [[ -f "$wt/manifest.json" ]] && command -v python3 >/dev/null 2>&1; then
    active=$(python3 -c "import json; print(len(json.load(open('$wt/manifest.json')).get('entries', {})))")
  fi
  local size; size=$(du -sb "$wt" 2>/dev/null | awk '{print $1}')
  # stale count: requires gh API per-entry; deferred to v0.4 caching.
  echo "active=${active:-0} stale=? total_size_bytes=${size:-0}"

  _orphan_worktree_close "$wt"
}
