#!/usr/bin/env bash
# scripts/lib/pr-platform.sh — PR / MR backend abstraction (v0.5.0+)
#
# Public API (callable by scripts/pr-helper.sh):
#   pr_create <title> <body_file> <base_branch> <head_branch>
#     stdout: <PR/MR web URL on success>
#     return: 0 on success, non-zero on failure (with stderr message)
#
#   pr_update_body <pr_number> <body_file>
#     stdout: nothing on success
#     return: 0 on success, non-zero on failure
#     (For GitHub: <pr_number> is the PR number. For GitLab: it's the MR iid.
#      Both are the trailing path segment of the URL returned by pr_create.)
#
#   pr_get_owner_repo
#     stdout: "owner/repo" (GitHub) or URL-encoded "namespace%2Fproject" (GitLab)
#     return: 0 on success
#     (Used by attachments_upload to construct raw URLs etc.)
#
# Backend dispatch:
#   SCV_PR_PLATFORM=github|gitlab → use that backend explicitly.
#   Otherwise: auto-detect from `git remote get-url origin`:
#     - host contains "github.com" → github
#     - host contains "gitlab.com" → gitlab
#     - anything else → github (safe default; user can override via env)
#
#   Self-hosted GitLab (e.g., gitlab.your-company.com): set
#     SCV_PR_PLATFORM=gitlab + GITLAB_HOST=https://gitlab.your-company.com
#
# Required env per backend:
#   github: gh CLI authenticated (gh auth status)
#   gitlab: GITLAB_TOKEN (Personal Access Token; scope: api + write_repository)
#           GITLAB_HOST (optional; default https://gitlab.com)
#
# Dependencies: git; gh CLI (github backend); curl + jq (gitlab backend).

# ============================================================================
# Backend resolution
# ============================================================================

_pr_detect_platform() {
  local origin
  origin=$(git remote get-url origin 2>/dev/null) || { echo "github"; return 0; }
  case "$origin" in
    *gitlab.com*|*gitlab:*) echo "gitlab" ;;
    *github.com*|*github:*) echo "github" ;;
    *) echo "github" ;;
  esac
}

_pr_resolve_platform() {
  local p="${SCV_PR_PLATFORM:-}"
  if [[ -z "$p" ]]; then
    p=$(_pr_detect_platform)
  fi
  case "$p" in
    github|gitlab) echo "$p" ;;
    *) echo "github" ;;
  esac
}

# ============================================================================
# Public API — dispatch
# ============================================================================

pr_create() {
  local title="$1" body_file="$2" base="$3" head="$4"
  local platform; platform=$(_pr_resolve_platform)
  case "$platform" in
    github) _pr_github_create "$title" "$body_file" "$base" "$head" ;;
    gitlab) _pr_gitlab_create "$title" "$body_file" "$base" "$head" ;;
  esac
}

pr_update_body() {
  local pr_number="$1" body_file="$2"
  local platform; platform=$(_pr_resolve_platform)
  case "$platform" in
    github) _pr_github_update_body "$pr_number" "$body_file" ;;
    gitlab) _pr_gitlab_update_body "$pr_number" "$body_file" ;;
  esac
}

pr_get_owner_repo() {
  local platform; platform=$(_pr_resolve_platform)
  case "$platform" in
    github) _pr_github_owner_repo ;;
    gitlab) _pr_gitlab_project_path ;;
  esac
}

# Construct a raw-content URL for <path> on <branch>. Used by attachments
# upload to embed raw video / GIF URLs into PR/MR bodies.
#   GitHub: https://github.com/<owner>/<repo>/raw/<branch>/<path>
#   GitLab: <host>/<namespace>/<project>/-/raw/<branch>/<path>
pr_raw_url() {
  local branch="$1" path="$2"
  local platform; platform=$(_pr_resolve_platform)
  case "$platform" in
    github) _pr_github_raw_url "$branch" "$path" ;;
    gitlab) _pr_gitlab_raw_url "$branch" "$path" ;;
  esac
}

_pr_github_raw_url() {
  local branch="$1" path="$2"
  local owner_repo
  owner_repo=$(_pr_github_owner_repo) || return 1
  echo "https://github.com/${owner_repo}/raw/${branch}/${path}"
}

# Returns a URL-decoded "namespace/project" path (no URL encoding) — for use
# in raw URL construction where slashes must remain as path separators.
_pr_gitlab_project_path_plain() {
  local origin
  origin=$(git remote get-url origin 2>/dev/null) || return 1
  local path
  case "$origin" in
    git@*:*)
      path=${origin#*:}
      ;;
    https://*|http://*|ssh://*)
      path=${origin#*://}
      path=${path#*/}
      ;;
    *)
      return 1
      ;;
  esac
  printf '%s\n' "${path%.git}"
}

_pr_gitlab_raw_url() {
  local branch="$1" path="$2"
  local host project
  host=$(_pr_gitlab_host)
  project=$(_pr_gitlab_project_path_plain) || return 1
  echo "${host}/${project}/-/raw/${branch}/${path}"
}

# ============================================================================
# GitHub backend (uses gh CLI)
# ============================================================================

_pr_github_owner_repo() {
  local origin
  origin=$(git remote get-url origin 2>/dev/null) || return 1
  case "$origin" in
    *github.com[/:]*)
      local path=${origin#*github.com}
      path=${path#:}
      path=${path#/}
      path=${path%.git}
      printf '%s\n' "$path"
      ;;
    *) return 1 ;;
  esac
}

_pr_github_create() {
  local title="$1" body_file="$2" base="$3" head="$4"
  gh pr create --base "$base" --head "$head" --title "$title" --body-file "$body_file"
}

_pr_github_update_body() {
  local pr_number="$1" body_file="$2"
  local owner_repo
  owner_repo=$(_pr_github_owner_repo) || return 1
  # `gh pr edit` returns exit 1 due to GraphQL Projects (classic) deprecation
  # warning even when body update succeeds. Use `gh api PATCH` directly.
  gh api -X PATCH "repos/${owner_repo}/pulls/${pr_number}" -F body=@"$body_file" --silent
}

# ============================================================================
# GitLab backend (uses curl + REST API v4)
# ============================================================================

_pr_gitlab_host() {
  echo "${GITLAB_HOST:-https://gitlab.com}"
}

# Returns URL-encoded "namespace/project" (e.g., "wookiya1364%2Fscv-test-pr-flow")
# from the git remote origin URL. Strips .git suffix.
_pr_gitlab_project_path() {
  local origin
  origin=$(git remote get-url origin 2>/dev/null) || return 1

  # Strip protocol/user@host part to get "namespace/project[.git]"
  local path
  case "$origin" in
    git@*:*)
      # SSH: git@gitlab.com:wookiya1364/scv-test.git
      path=${origin#*:}
      ;;
    https://*|http://*|ssh://*)
      # Strip scheme + host:port → keep path
      path=${origin#*://}
      path=${path#*/}
      ;;
    *)
      echo "ERROR: cannot parse GitLab origin URL: $origin" >&2
      return 1
      ;;
  esac

  path=${path%.git}
  # URL-encode slashes for path parameter
  printf '%s\n' "$path" | sed 's|/|%2F|g'
}

_pr_gitlab_token() {
  local t="${GITLAB_TOKEN:-}"
  if [[ -z "$t" ]]; then
    echo "ERROR: GITLAB_TOKEN env var not set (Personal Access Token; scope: api + write_repository)" >&2
    return 1
  fi
  echo "$t"
}

_pr_gitlab_create() {
  local title="$1" body_file="$2" base="$3" head="$4"
  command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required for GitLab backend" >&2; return 1; }
  command -v curl >/dev/null 2>&1 || { echo "ERROR: curl required for GitLab backend" >&2; return 1; }

  local host project token
  host=$(_pr_gitlab_host)
  project=$(_pr_gitlab_project_path) || return 1
  token=$(_pr_gitlab_token) || return 1

  local payload
  payload=$(jq -n \
    --arg sb "$head" \
    --arg tb "$base" \
    --arg tt "$title" \
    --rawfile dsc "$body_file" \
    '{source_branch:$sb, target_branch:$tb, title:$tt, description:$dsc, remove_source_branch:false}')

  local response http_code
  response=$(curl -sS \
    -X POST \
    -H "PRIVATE-TOKEN: $token" \
    -H "Content-Type: application/json" \
    --data "$payload" \
    -o /tmp/scv-gitlab-resp.$$.json \
    -w "%{http_code}" \
    "${host}/api/v4/projects/${project}/merge_requests" 2>&1)
  http_code="$response"

  if [[ "$http_code" != "201" && "$http_code" != "200" ]]; then
    local err_body; err_body=$(cat /tmp/scv-gitlab-resp.$$.json 2>/dev/null)
    echo "ERROR: GitLab MR create failed (HTTP $http_code): $err_body" >&2
    rm -f /tmp/scv-gitlab-resp.$$.json
    return 1
  fi

  local web_url
  web_url=$(jq -r '.web_url // empty' /tmp/scv-gitlab-resp.$$.json 2>/dev/null)
  rm -f /tmp/scv-gitlab-resp.$$.json
  if [[ -z "$web_url" ]]; then
    echo "ERROR: GitLab MR create — no web_url in response" >&2
    return 1
  fi
  echo "$web_url"
}

_pr_gitlab_update_body() {
  local pr_number="$1" body_file="$2"
  command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required for GitLab backend" >&2; return 1; }
  command -v curl >/dev/null 2>&1 || { echo "ERROR: curl required for GitLab backend" >&2; return 1; }

  local host project token
  host=$(_pr_gitlab_host)
  project=$(_pr_gitlab_project_path) || return 1
  token=$(_pr_gitlab_token) || return 1

  local payload
  payload=$(jq -n --rawfile dsc "$body_file" '{description:$dsc}')

  local http_code
  http_code=$(curl -sS \
    -X PUT \
    -H "PRIVATE-TOKEN: $token" \
    -H "Content-Type: application/json" \
    --data "$payload" \
    -o /dev/null \
    -w "%{http_code}" \
    "${host}/api/v4/projects/${project}/merge_requests/${pr_number}")

  if [[ "$http_code" != "200" ]]; then
    echo "ERROR: GitLab MR body update failed (HTTP $http_code)" >&2
    return 1
  fi
}
