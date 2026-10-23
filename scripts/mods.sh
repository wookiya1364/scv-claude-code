#!/usr/bin/env bash
# mods.sh — /scv:mods · /scv:mods-install · /scv:mods-remove 의 엔진: SCV 모드 업데이트 · 목록 · 설치 · 삭제.
#
# 모드(예: scv-dashboard — 데스크톱 앱의 SCV 칸)는 별도 마켓(기본 wookiya1364/scv-mods, 공개 — 로그인 없이 설치)에서 오는 Claude Code
# 플러그인이다. 사람이 기억해야 했던 일 — 마켓 추가 · 설치 · 마켓 갱신 + 업데이트 두 줄 · 인증 · 다시 불러오기 — 을
# 한 명령으로 묶는다. 바꾸는 일은 모두 Claude Code CLI(`claude plugin …`)로만 하고 ~/.claude/plugins 를 직접 고치지
# 않는다. 프로젝트 파일은 건드리지 않는다.
#
# 흐름(순수 단계는 가운데, 부수효과는 양 끝):
#   read_state(부수) → mods_plan(순수) → run_steps(부수) → read_state(부수) → mods_summary(순수)
#
# Usage (사람은 인자를 치지 않는다 — 스킬이 선택 창에서 고른 이름을 넘긴다):
#   mods.sh                 # /scv:mods — 설치된 모드 전부 업데이트, 그다음 목록
#   mods.sh list            # 목록만 (아무것도 바꾸지 않음)
#   mods.sh candidates      # /scv:mods-install 의 보기: 설치 가능한 모드 (마켓이 없으면 먼저 추가)
#   mods.sh install <mod>
#   mods.sh update  [<mod>]
#   mods.sh remove  <mod>
#
# Env:
#   SCV_MODS_MARKETPLACE  마켓 출처 (기본 wookiya1364/scv-mods). 마켓 이름은 마지막 경로 조각.
#   SCV_CLAUDE_BIN        claude 실행 파일 (기본 claude) — 시험용.
#
# Output (stdout, parseable, 한 줄에 하나):
#   MODS_MARKETPLACE: <name> (<source>) present|absent
#   MOD: <name> installed <version>|available
#   STEP: <claude plugin 인자들> ok|fail
#   RESULT: <name> installed <ver> | updated <old> -> <new> | up-to-date <ver> | removed | failed <reason>
#           | renamed <new> | gone          (새로고침 때 새로 받은 마켓에 없는 모드 — 업데이트하지 않는다)
#   NEXT: <할 일 한 줄>                    (인증 · 다시 불러오기)
#
# Exit: 0 성공, 1 실패(단계 실패 · 상태를 못 읽음), 2 사용법 오류.

set -uo pipefail

CLAUDE_BIN="${SCV_CLAUDE_BIN:-claude}"
MKT_SOURCE="${SCV_MODS_MARKETPLACE:-wookiya1364/scv-mods}"
MKT_NAME="${MKT_SOURCE##*/}"; MKT_NAME="${MKT_NAME%.git}"

usage() { echo 'usage: mods.sh [list | candidates | install <mod> | update [<mod>] | remove <mod>]' >&2; exit 2; }

# ── 순수 단계 ────────────────────────────────────────────────────────────────

# mods_plan <op> <mod> <mkt_name> <mkt_source> <mkt_present:0|1> <installed_lines>
#   installed_lines: "<mod> <version>" 줄들 (이 마켓의 설치된 모드)
#   → stdout: 실행할 claude plugin 인자 줄들 (탭 없이 공백 구분, 순서대로)
mods_plan() {
  local op=$1 mod=$2 name=$3 src=$4 present=$5 installed=$6
  local has_mod=0
  if [[ -n "$mod" ]] && printf '%s\n' "$installed" | awk -v m="$mod" '$1 == m { f = 1 } END { exit !f }'; then has_mod=1; fi
  case "$op" in
    list) return 0 ;;
    install)
      if [[ $present -eq 0 ]]; then echo "marketplace add $src"; fi
      if [[ $has_mod -eq 1 ]]; then
        echo "marketplace update $name"; echo "update $mod@$name"
      else
        [[ $present -eq 1 ]] && echo "marketplace update $name"
        echo "install $mod@$name"
      fi ;;
    update)
      [[ $present -eq 1 ]] || return 0
      echo "marketplace update $name"
      if [[ -n "$mod" ]]; then
        [[ $has_mod -eq 1 ]] && echo "update $mod@$name"
      else
        printf '%s\n' "$installed" | awk -v n="$name" 'NF { print "update " $1 "@" n }'
      fi ;;
    remove)
      [[ $has_mod -eq 1 ]] && echo "uninstall $mod@$name" ;;
  esac
  return 0
}

# mods_split <installed_lines> <catalog_lines>
#   catalog_lines: "plugin <name>" · "rename <old> <new>" 줄들 (받아 둔 마켓 목록). 비어 있으면(못 읽음) 전부 keep.
#   → stdout: "keep <mod> <version>" · "renamed <mod> <new>" · "gone <mod>" 줄들
mods_split() {
  local installed=$1 catalog=$2
  if [[ -z "$catalog" ]]; then printf '%s\n' "$installed" | awk 'NF { print "keep " $0 }'; return 0; fi
  # 여러 줄 값은 -v 대신 환경으로 넘긴다 — BSD awk 는 -v 값의 줄바꿈을 거부한다.
  printf '%s\n' "$installed" | MODS_CAT="$catalog" awk '
    BEGIN { n = split(ENVIRON["MODS_CAT"], L, "\n"); for (i = 1; i <= n; i++) { split(L[i], f, " ")
              if (f[1] == "plugin") p[f[2]] = 1; else if (f[1] == "rename") r[f[2]] = f[3] } }
    NF { if ($1 in p) print "keep " $0; else if ($1 in r) print "renamed " $1 " " r[$1]; else print "gone " $1 }'
}

# mods_moved <split_lines> <installed_after_lines> → 마켓에서 빠진 모드의 RESULT: / NEXT: 줄들
mods_moved() {
  local split=$1 after=$2 line kind m new need=0
  while IFS= read -r line; do
    read -r kind m new <<<"$line"
    case "$kind" in
      renamed) echo "RESULT: $m renamed $new"
               printf '%s\n' "$after" | awk -v n="$new" '$1 == n { f = 1 } END { exit !f }' || need=1 ;;
      gone)    echo "RESULT: $m gone"; need=1 ;;
    esac
  done <<<"$split"
  if [[ $need -eq 1 ]]; then
    echo "NEXT: 마켓에서 이름이 바뀌었거나 빠진 모드다 — /scv:mods-install 로 새 모드를 설치하고, 목록에 옛 모드가 남아 있으면 /scv:mods-remove 로 지운다"
  fi
  return 0
}

# mods_drop_moved <installed_lines> <split_lines> → 옮겨진(renamed · gone) 모드를 뺀 설치 줄들
mods_drop_moved() {
  printf '%s\n' "$1" | MODS_SPLIT="$2" awk '
    BEGIN { n = split(ENVIRON["MODS_SPLIT"], L, "\n"); for (i = 1; i <= n; i++) { split(L[i], f, " "); if (f[1] == "renamed" || f[1] == "gone") d[f[2]] = 1 } }
    NF && !($1 in d)'
}

# mods_summary <op> <mod> <before_lines> <after_lines> <failed_step> <fail_text>
#   before/after: "<mod> <version>" 줄들. failed_step 이 비어 있지 않으면 실패.
#   → stdout: RESULT: / NEXT: 줄들
mods_summary() {
  local op=$1 mod=$2 before=$3 after=$4 failed=$5 ftext=$6
  local targets m old new
  if [[ -n "$failed" ]]; then
    echo "RESULT: ${mod:-all} failed $failed"
    # 마켓 단계는 저장소를 받는다 — 'not found' 도 권한 없음일 수 있다. 모드 단계의 'not found' 는 마켓에 그
    # 이름이 없다는 뜻(이름이 바뀌었거나 빠짐)이라 인증 안내가 원인과 맞지 않는다.
    local auth='auth|permission denied|could not read|403|terminal prompts disabled'
    if [[ "$failed" != marketplace* ]] && ! printf '%s' "$ftext" | grep -qiE "$auth" \
        && printf '%s' "$ftext" | grep -qiE 'not found'; then
      echo "NEXT: ${failed#* } 은(는) 모드 마켓에 없다 — 이름이 바뀌었거나 빠졌다: /scv:mods-install 로 새 모드를 설치하고, 목록에 옛 모드가 남아 있으면 /scv:mods-remove 로 지운다"
    elif printf '%s' "$ftext" | grep -qiE "$auth|not found|404|repository"; then
      echo "NEXT: 모드 마켓($MKT_SOURCE)을 읽지 못했다 — 비공개 마켓이면 이 컴퓨터에 github 읽기 권한을 준다: gh auth login 다음 gh auth setup-git (또는 SSH 키), 그 뒤 다시 실행"
    fi
    return 0
  fi
  [[ "$op" == list ]] && return 0
  if [[ -n "$mod" ]]; then targets="$mod"; else targets="$(printf '%s\n' "$before" | awk 'NF { print $1 }')"; fi
  if [[ -z "$targets" ]]; then echo "RESULT: none (설치된 모드 없음)"; return 0; fi
  for m in $targets; do
    old="$(printf '%s\n' "$before" | awk -v m="$m" '$1 == m { print $2 }')"
    new="$(printf '%s\n' "$after"  | awk -v m="$m" '$1 == m { print $2 }')"
    case "$op" in
      remove)
        if [[ -z "$old" ]]; then echo "RESULT: $m not-installed"
        elif [[ -z "$new" ]]; then echo "RESULT: $m removed"
        else echo "RESULT: $m failed still-installed"; fi ;;
      install|update)
        if [[ -z "$new" ]]; then
          if [[ "$op" == update && -z "$old" ]]; then echo "RESULT: $m not-installed (설치: /scv:mods-install)"
          else echo "RESULT: $m failed not-installed-after-run"; fi
        elif [[ -z "$old" ]]; then echo "RESULT: $m installed $new"
        elif [[ "$old" == "$new" ]]; then echo "RESULT: $m up-to-date $new"
        else echo "RESULT: $m updated $old -> $new"; fi ;;
    esac
  done
  if [[ "$(printf '%s\n' "$before" | awk 'NF' | sort)" != "$(printf '%s\n' "$after" | awk 'NF' | sort)" ]]; then
    echo "NEXT: 열린 세션에서 /reload-plugins 를 실행하거나 새 세션을 연다 — 그래야 바뀐 모드가 돈다"
  fi
}

# ── 부수효과 (양 끝) ─────────────────────────────────────────────────────────

# read_state → stdout 첫 줄 present(0|1), 이후 "<mod> <version>" 줄들. 실패 시 1.
read_state() {
  local mk inst
  mk="$("$CLAUDE_BIN" plugin marketplace list --json 2>/dev/null)" || return 1
  inst="$("$CLAUDE_BIN" plugin list --json 2>/dev/null)" || return 1
  printf '%s' "$mk" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  if printf '%s' "$mk" | jq -e --arg n "$MKT_NAME" 'any(.[]; .name == $n)' >/dev/null 2>&1; then echo 1; else echo 0; fi
  printf '%s' "$inst" | jq -r --arg n "$MKT_NAME" '
    (if type == "object" then .installed else . end) // []
    | .[] | select((.id // "") | endswith("@" + $n))
    | "\(.id | sub("@.*$"; "")) \(.version // "unknown")"' 2>/dev/null
}

# read_catalog → 받아 둔 마켓 목록의 "plugin <name>" · "rename <old> <new>" 줄들 (읽기만 — 못 읽으면 빈 출력)
read_catalog() {
  local loc
  loc="$("$CLAUDE_BIN" plugin marketplace list --json 2>/dev/null \
    | jq -r --arg n "$MKT_NAME" '.[] | select(.name == $n) | .installLocation // empty' 2>/dev/null)"
  [[ -n "$loc" && -f "$loc/.claude-plugin/marketplace.json" ]] || return 0
  jq -r '((.plugins // [])[] | "plugin \(.name)"), ((.renames // {}) | to_entries[] | "rename \(.key) \(.value)")' \
    "$loc/.claude-plugin/marketplace.json" 2>/dev/null
}

# read_available → "<mod>" 줄들 (이 마켓에서 설치 가능한, 아직 안 깐 모드)
read_available() {
  "$CLAUDE_BIN" plugin list --json --available 2>/dev/null \
    | jq -r --arg n "$MKT_NAME" '(.available // [])[] | select(.marketplaceName == $n) | .name' 2>/dev/null
}

# print_list <present> <installed_lines> → MOD: 줄들
print_list() {
  printf '%s\n' "$2" | awk 'NF { print "MOD: " $1 " installed " $2 }'
  if [[ $1 -eq 1 ]]; then read_available | awk 'NF { print "MOD: " $1 " available" }'
  else echo "NEXT: 모드 마켓이 아직 없다 — 설치: /scv:mods-install"; fi
}

# ── 진입 ────────────────────────────────────────────────────────────────────

main() {
  local op=${1:-refresh} mod=${2:-}
  case "$op" in
    refresh|list|candidates) ;;
    install|remove) [[ -n "$mod" ]] || usage ;;
    update) ;;
    *) usage ;;
  esac
  command -v jq >/dev/null 2>&1 || { echo "RESULT: ${mod:-all} failed jq-missing"; echo "NEXT: jq 를 설치한다 (/scv:install-deps)"; return 1; }
  command -v "$CLAUDE_BIN" >/dev/null 2>&1 || { echo "RESULT: ${mod:-all} failed claude-cli-missing"; return 1; }

  local state present before
  state="$(read_state)" || { echo "RESULT: ${mod:-all} failed state-unreadable"; echo "NEXT: claude plugin list --json 이 읽히지 않는다 — Claude Code 버전을 확인한다"; return 1; }
  present="$(printf '%s\n' "$state" | sed -n 1p)"
  before="$(printf '%s\n' "$state" | sed -n '2,$p')"
  echo "MODS_MARKETPLACE: $MKT_NAME ($MKT_SOURCE) $([[ $present -eq 1 ]] && echo present || echo absent)"

  if [[ "$op" == list ]]; then
    print_list "$present" "$before"
    return 0
  fi
  if [[ "$op" == candidates ]]; then
    # 마켓이 있어도 새로 받는다 — 받아 둔 옛 목록에서 고르면 새 모드 · 바뀐 이름이 보이지 않는다.
    local first="marketplace update $MKT_NAME"
    [[ $present -eq 1 ]] || first="marketplace add $MKT_SOURCE"
    # shellcheck disable=SC2086 # 단계는 공백으로 나뉜 인자다(값에 공백 없음).
    if out="$("$CLAUDE_BIN" plugin $first 2>&1)"; then echo "STEP: $first ok"
    else echo "STEP: $first fail"; mods_summary install "" "" "" "$first" "$out"; return 1; fi
    read_available | awk 'NF { print "MOD: " $1 " available" }'
    return 0
  fi
  local relist=""
  if [[ "$op" == refresh ]]; then op=update; relist=1; fi

  local steps step out failed="" ftext="" split="" kept="$before"
  steps="$(mods_plan "$op" "$mod" "$MKT_NAME" "$MKT_SOURCE" "$present" "$before")"
  if [[ "$op" == update && $present -eq 1 ]]; then
    # 마켓을 먼저 새로 받고, 새 목록에 없는 모드(이름이 바뀌었거나 빠짐)는 업데이트하지 않는다.
    if out="$("$CLAUDE_BIN" plugin marketplace update "$MKT_NAME" 2>&1)"; then echo "STEP: marketplace update $MKT_NAME ok"
    else echo "STEP: marketplace update $MKT_NAME fail"; mods_summary "$op" "$mod" "$before" "" "marketplace update $MKT_NAME" "$out"; return 1; fi
    split="$(mods_split "$before" "$(read_catalog)")"
    kept="$(printf '%s\n' "$split" | awk '$1 == "keep" { print $2 " " $3 }')"
    if [[ -n "$mod" ]] && ! printf '%s\n' "$kept" | awk -v m="$mod" '$1 == m { f = 1 } END { exit !f }'; then
      split="$(printf '%s\n' "$split" | awk -v m="$mod" '$2 == m')"
    fi
    steps="$(mods_plan "$op" "$mod" "$MKT_NAME" "$MKT_SOURCE" "$present" "$kept" | grep -v '^marketplace ')"
  fi
  while IFS= read -r step; do
    [[ -n "$step" ]] || continue
    # shellcheck disable=SC2086 # 단계는 공백으로 나뉜 인자다(값에 공백 없음).
    if out="$("$CLAUDE_BIN" plugin $step 2>&1)"; then echo "STEP: $step ok"
    else echo "STEP: $step fail"; failed="$step"; ftext="$out"; break; fi
  done <<<"$steps"

  local after=""
  if [[ -z "$failed" ]]; then
    after="$(read_state | sed -n '2,$p')"
  fi
  local moved=""
  [[ -n "$split" && -z "$failed" ]] && moved="$(mods_moved "$split" "$after")"
  # 옮겨진 모드만 있었으면 "설치된 모드 없음" 대신 그 결과만 낸다.
  if [[ -n "$failed" || -n "$kept" || -z "$moved" ]]; then
    mods_summary "$op" "$mod" "$kept" "$(mods_drop_moved "$after" "$split")" "$failed" "$ftext"
  fi
  [[ -n "$moved" ]] && printf '%s\n' "$moved"
  [[ -z "$failed" ]] || return 1
  if [[ -n "$relist" ]]; then print_list "$present" "$after"; fi
  return 0
}

# source 될 때는(시험) 함수만 싣는다.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; exit $?; fi
