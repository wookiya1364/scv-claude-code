#!/usr/bin/env bash
# update.sh — /scv:update 의 엔진: SCV 버전 진단, 그리고 본체 · 모드 올리기 (올리기는 0.94.1+).
#
# 진단(인자 없음)은 읽기만 한다 — 설치 버전(plugin.json)과 저장소의 가장 높은 정식 태그를 견준다. 최신 버전은 git 으로
# 읽는다(gh 가 없어도 된다 — git 은 SCV 의 필수 도구). 올리기(apply)는 Claude Code CLI(`claude plugin …`)로만 한다 —
# 슬래시 명령과 달리 터미널 세션과 클로드 앱 세션 둘 다에서 돈다. 플러그인 폴더 · 목록 파일을 직접 고치지 않고,
# 프로젝트 파일은 건드리지 않는다. 본체 다음에 설치된 모드까지 올린다(모드 엔진 scripts/mods.sh 를 이어 부른다).
#
# 흐름(순수 단계는 가운데, 부수효과는 양 끝):
#   read_latest_tags(부수) → update_latest_version(순수) → read_installed(부수) → update_plan(순수)
#     → run_steps(부수) → read_installed(부수) → update_summary(순수) → run_mods_update(부수)
#
# Usage:
#   update.sh           # 진단만 (아무것도 바꾸지 않음)
#   update.sh apply     # 진단 + 본체 올리기 + 설치된 모드 올리기
#
# Env (시험용):
#   SCV_CLAUDE_BIN            claude 실행 파일 (기본 claude)
#   SCV_UPDATE_GIT_BIN        git 실행 파일 (기본 git) — 태그 목록 읽기
#   SCV_UPDATE_PLUGIN_ROOT    플러그인 뿌리 (기본: 이 스크립트의 윗 폴더) — 설치 버전 · 이름 · 저장소 주소를 읽는 곳
#
# Output (stdout, parseable, 한 줄에 하나):
#   INSTALLED_VERSION: <x.y.z>
#   MARKETPLACE_NAME: <name>            (marketplace.json 의 첫 "name")
#   PLUGIN_NAME: <name>                  (plugin.json 의 "name")
#   LATEST_VERSION: <x.y.z> | (unavailable — <이유>)
#   UP_TO_DATE: yes | no | unknown
#   — 여기까지가 진단. 아래는 apply 일 때만 —
#   CHANNEL: prod | dev | stage | other:<가지>
#   STEP: <claude plugin 인자들> ok|fail
#   DETAIL: <실패한 명령이 낸 오류 문구>
#   RESULT: <plugin> updated <old> -> <new> [<범위>] | up-to-date <ver> [<범위>] | unchanged <ver> [<범위>]
#           | failed <이유 · 단계> | skipped channel <채널> | not-installed
#   NEXT: <할 일 한 줄>
#   (이어서 모드 엔진의 줄들: MODS_MARKETPLACE: · STEP: · RESULT: · NEXT:)
#
# Exit: 진단은 늘 0. apply 는 0 성공, 1 실패(본체든 모드든), 2 사용법 오류.

set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/channel.sh
source "$SCRIPT_DIR/lib/channel.sh"
# 설치 목록 읽기(plugin_lines)를 모드 엔진과 함께 쓴다 — 범위 고르는 규칙이 한 곳에만 있게.
# shellcheck source=mods.sh
source "$SCRIPT_DIR/mods.sh"

UPDATE_ROOT="${SCV_UPDATE_PLUGIN_ROOT:-$( cd "$SCRIPT_DIR/.." && pwd )}"
UPDATE_CLAUDE_BIN="${SCV_CLAUDE_BIN:-claude}"
UPDATE_GIT_BIN="${SCV_UPDATE_GIT_BIN:-git}"

# ── 순수 단계 ────────────────────────────────────────────────────────────────

# @deterministic
# 역할: 태그 줄들에서 가장 높은 정식 버전(v숫자.숫자.숫자)을 숫자로 견줘 고른다 — 접미사 붙은 태그와 이름 태그는 세지 않는다
# 종류: 고르기
# 예: "v0.9.0\nv0.10.0\nv0.94.0-codex.1" → "0.10.0"
# update_latest_version <태그 줄들> → x.y.z | 빈 값. 줄은 태그 이름만이어도, ls-remote 꼴("<sha>\trefs/tags/<tag>")이어도 된다.
update_latest_version() {
  printf '%s\n' "$1" \
    | sed -n 's|^.*refs/tags/||; s|^[[:space:]]*||; s|[[:space:]]*$||; s|^v\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)$|\1|p' \
    | sort -t. -k1,1n -k2,2n -k3,3n | tail -1
}

# @deterministic
# 역할: 본체를 올리려면 실행할 claude plugin 인자 줄을 순서대로 정한다 — 올릴 것이 없으면 0줄
# 종류: 계획
# 예: ("apply", "user 0.85.2", "0.94.0", "scv", "scv-claude-code", "prod") → "marketplace update scv-claude-code\nupdate scv@scv-claude-code -s user"
# update_plan <op> <설치 줄들 "범위 버전"> <최신|빈 값> <플러그인> <마켓> <채널>
#   운영 채널이 아니면 0줄. 최신을 못 읽었으면(빈 값) 모든 범위를 올린다 — 명령줄이 스스로 판단하고 결과는 앞뒤 버전으로 본다.
update_plan() {
  local op=$1 installed=$2 latest=$3 plugin=$4 mkt=$5 channel=$6
  [[ "$op" == apply && "$channel" == prod ]] || return 0
  printf '%s\n' "$installed" | awk -v l="$latest" -v p="$plugin" -v m="$mkt" '
    NF && (l == "" || $2 != l) { n++; S[n] = $1 }
    END { if (!n) exit
          print "marketplace update " m
          for (i = 1; i != n + 1; i++) print "update " p "@" m ((S[i] == "-" || S[i] == "") ? "" : " -s " S[i]) }'
}

# @deterministic
# 역할: 본체의 범위별 앞뒤 버전을 견줘 결과 줄과 다음 행동 줄을 정한다
# 종류: 판정
# 예: ("scv", "user 0.85.2", "user 0.94.0", "", "prod", "0.94.0") → "RESULT: scv updated 0.85.2 -> 0.94.0 [user]\nNEXT: 새 세션을 열면 …"
# update_summary <플러그인> <앞 줄들 "범위 버전"> <뒤 줄들> <실패한 단계|빈 값> <채널> [<최신>] [<마켓>]
update_summary() {
  local plugin=$1 before=$2 after=$3 failed=$4 channel=$5 latest=${6:-} mkt=${7:-}
  if [[ "$channel" != prod ]]; then
    echo "RESULT: $plugin skipped channel $channel"
    echo "NEXT: 개발 · 스테이징 채널 설치본은 /scv:update 로 올리지 않는다 — 채널은 /scv:channel 로 바꾼다"
    return 0
  fi
  if [[ -n "$failed" ]]; then
    echo "RESULT: $plugin failed $failed"
    echo "NEXT: '$failed' 단계가 실패했다 — 위 DETAIL 의 오류를 고친 뒤 다시 실행한다 (터미널에서 직접: claude plugin $failed)"
    return 0
  fi
  if [[ -z "$(printf '%s' "$before" | tr -d '[:space:]')" ]]; then
    echo "RESULT: $plugin not-installed"
    echo "NEXT: 이 마켓에서 설치된 $plugin 이(가) 없다 — 설치: claude plugin install $plugin@$mkt"
    return 0
  fi
  UPDATE_AFTER="$after" UPDATE_BEFORE="$before" awk -v p="$plugin" -v l="$latest" '
    BEGIN {
      arrow = sprintf(" %c%c ", 45, 62)   # 화살표 — 꺾쇠 글자를 코드에 적지 않는다(순수성 검사)
      n = split(ENVIRON["UPDATE_AFTER"], A, "\n")
      for (i = 1; i != n + 1; i++) { split(A[i], f, " "); if (f[1] != "") new[f[1]] = f[2] }
      n = split(ENVIRON["UPDATE_BEFORE"], B, "\n")
      for (i = 1; i != n + 1; i++) {
        split(B[i], f, " "); if (f[1] == "") continue
        s = f[1]; old = f[2]; tag = (s == "-") ? "" : " [" s "]"
        if (!(s in new)) { print "RESULT: " p " failed not-installed-after-run" tag; continue }
        if (old != new[s]) { print "RESULT: " p " updated " old arrow new[s] tag; changed = 1 }
        else if (l != "" && old != l) { print "RESULT: " p " unchanged " old tag; behind = 1 }
        else print "RESULT: " p " up-to-date " old tag
      }
      if (changed) print "NEXT: 새 세션을 열면 올라간 버전이 적용된다 (열린 터미널 세션은 /reload-plugins 로도 된다)"
      if (behind) print "NEXT: 새 태그 " l " 은(는) 있는데 마켓에는 아직 올라오지 않았다 — 몇 분 뒤 다시 실행한다"
    }'
}

# ── 부수효과 (양 끝) ─────────────────────────────────────────────────────────

# @effect read_latest_tags
# 이유: 네트워크로 저장소의 태그 목록을 받아 온다
# read_latest_tags <owner/repo> → ls-remote 줄들. 실패하면 1(출력 없음).
read_latest_tags() {
  GIT_TERMINAL_PROMPT=0 "$UPDATE_GIT_BIN" -c http.lowSpeedLimit=1 -c http.lowSpeedTime=15 \
    ls-remote --tags --refs "https://github.com/$1.git" 2>/dev/null
}

# @effect read_installed
# 이유: claude plugin list 를 실행해 설치 목록을 읽는다
# read_installed <플러그인> <마켓> → "범위 버전" 줄들 (다른 프로젝트의 project · local 설치본은 빠진다). 못 읽으면 1.
read_installed() {
  local inst
  inst="$("$UPDATE_CLAUDE_BIN" plugin list --json 2>/dev/null)" || return 1
  plugin_lines "$inst" "=$1@$2" "$(here_dirs)" | awk 'NF { print $3, $2 }'
}

# @effect read_channel
# 이유: claude plugin marketplace list 를 실행해 이 마켓이 어느 가지에서 받는지 읽는다
# read_channel <마켓> → prod | dev | stage | other:<가지>. 못 읽으면 1.
read_channel() {
  local mk ref
  mk="$("$UPDATE_CLAUDE_BIN" plugin marketplace list --json 2>/dev/null)" || return 1
  ref="$(printf '%s' "$mk" | jq -r --arg n "$1" '.[] | select(.name == $n) | .ref // ""' 2>/dev/null | head -1)"
  scv_channel_of_ref "$ref"
}

# @effect update_run_steps
# 이유: claude plugin 명령을 차례로 실행해 설치본을 바꾼다
# update_run_steps <명령 줄들> → STEP: 줄들. 실패하면 DETAIL: 줄들과 마지막 줄 "FAILED <단계>" 를 내고 1 — 뒤 단계는 실행하지 않는다.
update_run_steps() {
  local step out
  while IFS= read -r step; do
    [[ -n "$step" ]] || continue
    # shellcheck disable=SC2086 # 단계는 공백으로 나뉜 인자다(값에 공백 없음).
    if out="$("$UPDATE_CLAUDE_BIN" plugin $step 2>&1)"; then echo "STEP: $step ok"
    else
      echo "STEP: $step fail"
      printf '%s\n' "$out" | awk 'NF { print "DETAIL: " $0 }' | head -5
      echo "FAILED $step"
      return 1
    fi
  done <<<"$1"
  return 0
}

# @effect run_mods_update
# 이유: 모드 엔진을 실행해 설치된 모드를 올린다
# run_mods_update → 모드 엔진의 출력 줄들 그대로, 종료 코드도 그대로.
run_mods_update() {
  # 이 엔진을 돌린 그 셸로 부른다 — 기본 셸(3.2)로 불렸으면 모드 엔진도 3.2 로 돈다.
  SCV_CLAUDE_BIN="$UPDATE_CLAUDE_BIN" "${BASH:-bash}" "$SCRIPT_DIR/mods.sh" update
}

# @effect update_field
# 이유: 플러그인 뿌리의 json 파일을 읽는다
# update_field <파일> <열쇠> → 그 열쇠의 첫 값 (없으면 빈 값)
update_field() {
  [[ -f "$1" ]] || return 0
  grep -m1 "\"$2\"" "$1" 2>/dev/null | sed -E 's/.*"'"$2"'":[[:space:]]*"([^"]+)".*/\1/'
}

# ── 진입 ────────────────────────────────────────────────────────────────────

# @effect update_main
# 이유: 진단 줄을 내고, apply 면 설치본을 올린다
update_main() {
  local op=${1:-check}
  case "$op" in check|apply) ;; *) echo 'usage: update.sh [apply]' >&2; return 2 ;; esac

  local pj="$UPDATE_ROOT/.claude-plugin/plugin.json" mj="$UPDATE_ROOT/.claude-plugin/marketplace.json"
  local installed plugin mkt repo tags latest=""
  installed="$(update_field "$pj" version)"; plugin="$(update_field "$pj" name)"; mkt="$(update_field "$mj" name)"
  repo="$(update_field "$pj" homepage | sed -E 's|https?://github.com/||; s|/$||; s|\.git$||')"
  echo "INSTALLED_VERSION: ${installed:-(not found)}"
  echo "MARKETPLACE_NAME: ${mkt:-(unknown)}"
  echo "PLUGIN_NAME: ${plugin:-(unknown)}"
  if [[ -z "$repo" ]]; then
    echo "LATEST_VERSION: (unavailable — homepage not parseable from plugin.json)"
    echo "UP_TO_DATE: unknown"
  elif ! tags="$(read_latest_tags "$repo")"; then
    echo "LATEST_VERSION: (unavailable — could not read the tags of https://github.com/$repo with git; check the network, or see https://github.com/$repo/releases)"
    echo "UP_TO_DATE: unknown"
  else
    latest="$(update_latest_version "$tags")"
    if [[ -z "$latest" ]]; then
      echo "LATEST_VERSION: (unavailable — https://github.com/$repo has no release tag yet)"
      echo "UP_TO_DATE: unknown"
    else
      echo "LATEST_VERSION: $latest"
      if [[ "$installed" == "$latest" ]]; then echo "UP_TO_DATE: yes"; else echo "UP_TO_DATE: no"; fi
    fi
  fi
  [[ "$op" == apply ]] || return 0

  if [[ -z "$plugin" || -z "$mkt" ]]; then
    echo "RESULT: ${plugin:-scv} failed plugin-metadata-missing"
    echo "NEXT: 플러그인 이름이나 마켓 이름을 읽지 못했다 — 플러그인을 다시 설치한다"
    return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    echo "RESULT: $plugin failed jq-missing"; echo "NEXT: jq 를 설치한다 (/scv:install-deps)"; return 1
  fi
  if ! command -v "$UPDATE_CLAUDE_BIN" >/dev/null 2>&1; then
    echo "RESULT: $plugin failed claude-cli-missing"
    echo "NEXT: claude 명령줄을 찾지 못했다 — 터미널에서 직접: claude plugin marketplace update $mkt 다음 claude plugin update $plugin@$mkt"
    return 1
  fi

  local channel before after steps out failed="" rc=0
  if ! channel="$(read_channel "$mkt")" || ! before="$(read_installed "$plugin" "$mkt")"; then
    echo "RESULT: $plugin failed state-unreadable"
    echo "NEXT: claude plugin list --json 이 읽히지 않는다 — Claude Code 버전을 확인한다"
    return 1
  fi
  echo "CHANNEL: $channel"
  steps="$(update_plan apply "$before" "$latest" "$plugin" "$mkt" "$channel")"
  after="$before"
  if [[ -n "$steps" ]]; then
    if out="$(update_run_steps "$steps")"; then
      printf '%s\n' "$out"
      after="$(read_installed "$plugin" "$mkt")" || after="$before"
    else
      printf '%s\n' "$out" | grep -v '^FAILED '
      failed="$(printf '%s\n' "$out" | sed -n 's/^FAILED //p' | tail -1)"
    fi
  fi
  out="$(update_summary "$plugin" "$before" "$after" "$failed" "$channel" "$latest" "$mkt")"
  printf '%s\n' "$out"
  printf '%s\n' "$out" | grep -qE '^RESULT: [^ ]+ (failed|not-installed)' && rc=1

  # 본체가 어떻게 끝났든 모드는 올린다 — 두 결과는 따로 보고하고, 한쪽이라도 실패면 종료 코드는 실패.
  run_mods_update || rc=1
  return $rc
}

# source 될 때는(시험) 함수만 싣는다.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then update_main "$@"; exit $?; fi
