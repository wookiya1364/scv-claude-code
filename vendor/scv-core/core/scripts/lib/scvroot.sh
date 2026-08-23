#!/usr/bin/env bash
# scvroot.sh — locate the scv/ directory for the CURRENT context, so SCV works
# in a monorepo that holds MULTIPLE scv/ dirs: a micro scv per sub-project
# (FE/scv, BE/scv, AI/scv) plus a macro umbrella scv at the repo root (root/scv).
#
# Design intent (per the multi-scv model):
#   - Which scv/ a command operates on is CONTEXT-driven, not a single global
#     setting. Run a command from FE/ → FE/scv (micro); from the repo root →
#     root/scv (macro). That falls out of CWD-based resolution for free.
#   - An explicit module target arg (e.g. `/scv:status FE`) overrides CWD when
#     you want to address a sibling module without cd-ing.
#   - SCV_DIR (env) is only a quiet last-resort escape hatch — NOT the primary
#     mechanism (it would pin every command to one scv and break micro/macro).
#
# Public API (sourced; no side effects on source):
#
#   scv_target_path <arg>
#     Echo the scv/ path an explicit module arg resolves to, or return 1.
#       "FE"      → FE/scv   (if FE/scv exists)
#       "FE/scv"  → FE/scv   (a path whose basename is scv and which exists)
#     Callers use this to peel an optional leading module target off "$@".
#
#   scv_root_dir
#     Echo the auto-resolved scv/ dir (no explicit target). Precedence:
#       1. CWD:      ./scv exists (micro when in a module dir, macro at root).
#       2. Walk up:  nearest ancestor with a marked scv/ (session in a subdir).
#       3. SCV_DIR:  env override to an existing non-default dir (fallback).
#       4. Default:  "scv" (relative) — legacy standalone behavior, unchanged.
#     Steps 1 & 4 return the RELATIVE string "scv" so standalone repos behave
#     exactly as before.
#
#   scv_autosync [scv_dir]
#     Refresh the project's workflow docs when the stamped template version is
#     behind the payload's. Detailed contract at the function below.
#
#   scv_init_paths [target]
#     Runs scv_autosync on the resolved root, then derives
#     RAW_DIR / STATE_FILE / PROMOTE_DIR / ARCHIVE_DIR and exports SCV_DIR
#     from (target ? scv_target_path : scv_root_dir) — but only for vars the
#     caller hasn't already set, so an explicit `RAW_DIR=... bash readpath.sh`
#     still wins (env-override convention).

# Return 0 if $1 is a directory that looks like an SCV root (has a known child).
_scv_is_root() {
  local d="$1"
  [[ -d "$d" ]] || return 1
  [[ -d "$d/raw" || -d "$d/promote" || -d "$d/archive" || -f "$d/PROMOTE.md" ]]
}

scv_target_path() {
  local t="${1:-}"
  [[ -n "$t" ]] || return 1
  t="${t%/}"                              # tolerate a trailing slash
  local out=""
  if [[ -d "$t/scv" ]]; then              # "FE" → FE/scv  (and "." → ./scv)
    out="$t/scv"
  elif [[ -d "$t" && "$(basename "$t")" == "scv" ]]; then   # "FE/scv" → itself
    out="$t"
  else
    return 1
  fi
  out="${out#./}"                         # normalize "./scv" → "scv" (target ".")
  printf '%s\n' "$out"
}

scv_root_dir() {
  # 1. CWD/scv — context-driven default (micro in a module dir, macro at root).
  #    Returned relative for byte-identical standalone behavior. No marker
  #    requirement (a brand-new project may have an empty scv/).
  if [[ -d "scv" ]]; then
    printf 'scv\n'
    return 0
  fi

  # 2. Walk up parents for a marked scv/ (session opened inside a deeper subdir),
  #    but never cross the current git repo boundary — otherwise an outer repo's
  #    scv/ could be silently read/written/moved from an unrelated inner repo.
  local top; top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  local d; d="$(dirname "$PWD")"
  while [[ -n "$d" && "$d" != "/" ]]; do
    # only inspect dirs INSIDE the current git repo — never attach an outer
    # (unrelated) repo's scv/. If we know the repo root, break once we'd step
    # above it (or start above it, e.g. CWD is itself a nested inner repo).
    if [[ -n "$top" && "$d" != "$top" && "$d" != "$top"/* ]]; then break; fi
    if _scv_is_root "$d/scv"; then
      printf '%s\n' "$d/scv"
      return 0
    fi
    [[ -n "$top" && "$d" == "$top" ]] && break   # reached the repo root
    d="$(dirname "$d")"
  done

  # 3. SCV_DIR env — quiet fallback only (opt-in escape hatch, not required).
  if [[ -n "${SCV_DIR:-}" && "${SCV_DIR}" != "scv" && -d "${SCV_DIR}" ]]; then
    printf '%s\n' "${SCV_DIR}"
    return 0
  fi

  # 4. Legacy default — unchanged. Callers building "$root/raw" get "scv/raw".
  printf 'scv\n'
}


# ---- automatic template refresh ---------------------------------------------
# scv_autosync [scv_dir]
#   Close the gap between the project's stamped template version and the
#   payload's, the moment any action touches the project.
#
#   Why here and not in the update action: plugin payloads are cached per
#   version, so at update time the running session still holds the OLD
#   payload's sync — calling it there would lay down the old template and
#   report success. Only after a reload does any code see the new payload, and
#   the first action that runs is the first honest chance to migrate. This
#   hook is that chance.
#
#   It never hydrates (no SCV.md and no PROMOTE.md → not adopted → no-op), and
#   it never auto-migrates a pre-2.x project: the 2.0.0 retirement pass deletes
#   seven user-authored docs, and the sync protocol requires offering a
#   DECISIONS.md hand-off first — a conversation this hook must not skip. Those
#   projects get one pointer line instead. 2.x → 2.y is refreshed in place;
#   sync's dirty-refusal keeps local edits safe, and sync re-stamps the index
#   when done, so one run converges and the next call is a no-op.
#
#   A failed refresh warns and returns 0 — a migration problem must never
#   brick the action that tripped it. Opt out with SCV_AUTOSYNC=off (process
#   environment only, same reasoning as SCV_GUARD). All reporting goes to
#   stderr: callers parse this library's users' stdout.
# 번호 비교와 갱신 판단은 순수 라이브러리가 맡는다. 이 파일은 파일을 읽어 그
# 함수들에 넘기는 바깥층이다 — 경계를 넘지 말 것.
# shellcheck source=template-digest.sh
source "$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )/template-digest.sh"

# 예전 이름을 쓰는 호출부가 남아 있어도 깨지지 않게 남겨 둔다.
_scv_ver_lt() { scv_ver_lt "$@"; }

scv_autosync() {
  [[ -n "${SCV_AUTOSYNC_RUNNING:-}" ]] && return 0
  # Claim the whole process tree, not just the sync invocation: one action
  # script spawns several helpers (status → readpath ×4), each of which
  # sources this library. Without the export every helper re-ran the check —
  # and when the refresh could not complete, re-ran the refresh — turning one
  # action into N attempts and N stderr reports. One action, one check.
  #
  # 이 선언이 opt-out 검사보다 먼저 온다는 것이 중요하다. 끈 상태에서도 한 번은
  # 판단해서 어긋남을 알려야 하는데, 가드를 여기서 잡지 않으면 그 한 줄이 한
  # 액션에 여러 번 찍힌다.
  export SCV_AUTOSYNC_RUNNING=1

  # 자동 갱신을 껐다 — 파일은 건드리지 않는다. 다만 판단은 해서, 정말로 어긋나
  # 있으면 한 줄로 알린다. 껐다는 사실을 잊으면 영원히 모르는 것이 지금까지의
  # 가장 큰 구멍이었다. 어긋나지 않았으면 아무 말도 하지 않는다.
  local muted=0
  [[ "${SCV_AUTOSYNC:-on}" == "off" ]] && muted=1

  local root="${1:-}"
  [[ -n "$root" ]] || root="$(scv_root_dir)"
  [[ -d "$root" ]] || return 0

  local lib_dir payload_root
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  payload_root="$(cd "$lib_dir/../.." && pwd)"
  # 배포본이 불완전하다 — 예전에는 조용히 넘어갔다. 갱신이 영영 안 도는데 아무도
  # 모르는 상태라, 이름을 대고 말한다.
  if [[ ! -f "$payload_root/TEMPLATE_VERSION" || ! -f "$payload_root/scripts/sync.sh" ]]; then
    echo "scv: this SCV payload is incomplete (no TEMPLATE_VERSION or scripts/sync.sh at $payload_root) — template refresh cannot run; reinstall or update the plugin." >&2
    return 0
  fi
  local remote
  remote="$(tr -d '[:space:]' < "$payload_root/TEMPLATE_VERSION")"
  if [[ -z "$remote" ]]; then
    echo "scv: this SCV payload's TEMPLATE_VERSION is empty — template refresh cannot run; reinstall or update the plugin." >&2
    return 0
  fi

  # 배포본의 템플릿 지문. 갱신 여부는 번호가 아니라 이 값으로 판단한다 —
  # 번호를 올리는 것을 잊어도 내용이 바뀌었으면 반드시 갱신된다.
  local remote_digest=""
  [[ -f "$payload_root/TEMPLATE_DIGEST" ]] \
    && remote_digest="$(tr -d '[:space:]' < "$payload_root/TEMPLATE_DIGEST")"

  local index="$root/SCV.md" local_v="" local_d=""
  if [[ -f "$index" ]]; then
    local_v="$(sed -n 's/.*<!-- STANDARD:VERSION -->\(.*\)<!-- \/STANDARD:VERSION -->.*/\1/p' "$index" | head -n 1 | tr -d '[:space:]')"
    local_d="$(sed -n 's/.*<!-- STANDARD:DIGEST -->\(.*\)<!-- \/STANDARD:DIGEST -->.*/\1/p' "$index" | head -n 1 | tr -d '[:space:]')"
    # 템플릿 기본값이 그대로면 아직 안 찍힌 것이다.
    [[ "$local_d" == "UNSET" ]] && local_d=""
  fi
  if [[ -z "$local_v" ]]; then
    if [[ -f "$index" ]]; then
      # SCV.md exists but carries no readable stamp — a damaged or hand-edited
      # 2.x index, not a pre-2.x legacy. Calling it "legacy" would send the
      # user into a migration they do not need; restamping is what fixes it.
      echo "scv: $index carries no readable template stamp — run the sync action once to restamp it." >&2
    elif [[ -f "$root/PROMOTE.md" ]]; then
      # Hydrated but no SCV.md at all = pre-2.x legacy. Point, never act.
      echo "scv: this project's workflow docs predate template 2.0 — run the sync action once for the interactive migration." >&2
    fi
    return 0
  fi
  case "$local_v" in
    [2-9].*|[1-9][0-9]*.*) : ;;
    *) echo "scv: template $local_v predates 2.0 — run the sync action once for the interactive migration." >&2
       return 0 ;;
  esac

  # 판단은 순수 함수 한 번이다. 규칙은 세 줄 —
  #   1. 배포본이 프로젝트보다 오래된 번호면 절대 되돌리지 않는다. 없애면 두 대의
  #      기계가 서로의 템플릿을 무한히 뒤집는다.
  #   2. 지문이 다르면 갱신한다. 번호가 같아도 갱신한다.   (이번에 생긴 경로)
  #   3. 번호가 다르면 갱신한다. 지문이 같아도 갱신한다.   (예전 경로 그대로)
  # 지문은 번호를 대체하지 않고 더한다.
  local decision
  decision="$(scv_template_decide "$local_d" "$remote_digest" "$local_v" "$remote")"
  case "$decision" in
    skip:same)
      return 0 ;;
    skip:backward)
      echo "scv: this project's template ($local_v) is newer than this payload's ($remote) — update the plugin; nothing was changed." >&2
      return 0 ;;
    refresh|refresh:version|refresh:unstamped)
      if (( muted )); then
        local gap="$local_v → $remote"
        [[ "$local_v" == "$remote" ]] && gap="content changed, version still $remote"
        echo "scv: workflow docs are OUT OF DATE [$gap] — automatic refresh is off (SCV_AUTOSYNC=off); run the sync action to close it." >&2
        return 0
      fi ;;
    *)
      echo "scv: unexpected template decision [$decision] — nothing was changed; run the sync action by hand." >&2
      return 0 ;;
  esac

  local proj out
  proj="$(dirname "$root")"
  if out="$(bash "$payload_root/scripts/sync.sh" --project-dir "$proj" 2>&1)"; then
    # Exit 0 is not success — sync exits 0 after refusing every file. Say what
    # actually happened, from what it reported. When anything was refused the
    # stamp did not advance, so "will retry" is a fact, not a hope.
    local refused=0
    printf '%s\n' "$out" | grep -qE '^  (DIRTY|WARN|UNKNOWN)' && refused=1
    # 무엇 때문에 갱신했는지 말한다. 번호가 같은데 갱신되는 경우가 이제 정상이라
    # "2.3.0 → 2.3.0" 만 찍으면 사용자가 오해한다. 번호가 실제로 다를 때의 문구는
    # 그대로 둔다 — 기존 계약이고 테스트가 그 모양을 검사한다.
    local what="$local_v → $remote"
    if [[ "$local_v" == "$remote" ]]; then
      what="content changed at $remote (version unchanged)"
    fi
    if [[ $refused -eq 0 ]]; then
      echo "scv: workflow docs refreshed $what (automatic; the sync action re-runs this by hand)" >&2
    else
      echo "scv: template refresh $what was PARTIAL — the files below were skipped, and the next action retries:" >&2
      printf '%s\n' "$out" | grep -E '^  (DIRTY|WARN|UNKNOWN)' >&2 || true
    fi
  else
    echo "scv: automatic template refresh $local_v → $remote failed — run the sync action by hand; the current action continues." >&2
  fi
  return 0
}

# scv_template_drift — 템플릿이 어긋나 있으면 한 줄로 설명하고, 아니면 아무것도
# 내지 않는다. 읽기만 한다 — 고치지 않는다.
#
# 왜 필요한가: 자동 갱신이 스스로 닫는 경우는 이 함수가 호출될 즈음 이미 닫혀
# 있다. 그래서 여기서 무언가 나온다는 것은 "자동으로는 못 닫는 상태" 라는 뜻이다 —
# 껐거나, 배포본이 더 오래됐거나, 편집 중인 파일에 막혔거나. 사용자가 "왜 아직
# 옛날 문서지?" 라고 물을 때 답이 되는 자리다.
scv_template_drift() {
  local root="${1:-}"
  [[ -n "$root" ]] || root="$(scv_root_dir)"
  [[ -d "$root" ]] || return 0

  local lib_dir payload_root
  lib_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  payload_root="$(cd "$lib_dir/../.." && pwd)"
  [[ -f "$payload_root/TEMPLATE_VERSION" ]] || return 0

  local remote remote_digest="" index local_v="" local_d=""
  remote="$(tr -d '[:space:]' < "$payload_root/TEMPLATE_VERSION")"
  [[ -n "$remote" ]] || return 0
  [[ -f "$payload_root/TEMPLATE_DIGEST" ]] \
    && remote_digest="$(tr -d '[:space:]' < "$payload_root/TEMPLATE_DIGEST")"

  index="$root/SCV.md"
  [[ -f "$index" ]] || return 0
  local_v="$(sed -n 's/.*<!-- STANDARD:VERSION -->\(.*\)<!-- \/STANDARD:VERSION -->.*/\1/p' "$index" | head -n 1 | tr -d '[:space:]')"
  local_d="$(sed -n 's/.*<!-- STANDARD:DIGEST -->\(.*\)<!-- \/STANDARD:DIGEST -->.*/\1/p' "$index" | head -n 1 | tr -d '[:space:]')"
  [[ "$local_d" == "UNSET" ]] && local_d=""
  [[ -n "$local_v" ]] || return 0

  local decision
  decision="$(scv_template_decide "$local_d" "$remote_digest" "$local_v" "$remote")"
  case "$decision" in
    skip:same) return 0 ;;
    skip:backward)
      echo "  template: project ($local_v) is NEWER than this payload ($remote) — update the plugin" ;;
    refresh:unstamped)
      echo "  template: not yet digest-stamped — the next SCV action stamps it" ;;
    refresh)
      echo "  template: OUT OF DATE — content changed, version still $remote" ;;
    refresh:version)
      echo "  template: OUT OF DATE — $local_v → $remote" ;;
  esac
  if [[ "${SCV_AUTOSYNC:-on}" == "off" ]]; then
    echo "            automatic refresh is off (SCV_AUTOSYNC=off) — run the sync action"
  else
    echo "            the refresh could not complete on its own — run the sync action"
  fi
}

scv_init_paths() {
  local target="${1:-}" root=""
  if [[ -n "$target" ]]; then
    root="$(scv_target_path "$target")" || root=""
  fi
  [[ -z "$root" ]] && root="$(scv_root_dir)"

  scv_autosync "$root"

  RAW_DIR="${RAW_DIR:-$root/raw}"
  STATE_FILE="${STATE_FILE:-$root/readpath.json}"
  PROMOTE_DIR="${PROMOTE_DIR:-$root/promote}"
  ARCHIVE_DIR="${ARCHIVE_DIR:-$root/archive}"
  export SCV_DIR="$root" RAW_DIR STATE_FILE PROMOTE_DIR ARCHIVE_DIR
}
