#!/usr/bin/env bash
# plan-link.sh — 계획 밖 요구를 계획 파일에 남긴다: 같은 목표면 기존 계획에 단계를 넣고,
# 다른 목표면 기존 계획 A 를 보류로 바꾸고 새 계획 B 에 "끝나면 A 로 돌아감"을 적는다.
# B 가 끝나면 A 를 다시 진행 중으로 돌린다. 판단(같은 목표인가)은 모델이, 기록과 대조는 이 스크립트가 한다.
#
#   plan-link.sh append <A> --after <N> --step "<단계 글>" --why "<이유>"
#   plan-link.sh append <A> --redo <N> --why "<이유>"
#   plan-link.sh check-before <A> <B>
#   plan-link.sh pause <A> --by <B> --resume-at <N> --why "<이유>" [--accept-conflict]
#   plan-link.sh check-after <B> --changed <파일> [--changed <파일> …]
#   plan-link.sh resume <B> [--changed <파일> …] [--accept-overlap]
#   plan-link.sh split <A> --with <B> --at <N> --files <B 가 고칠 파일> [--files …] [--own <A 가 고칠 파일> …] --why "<이유>"
#   plan-link.sh join <A>
#   plan-link.sh progress <A> --step <N> [--state doing|done|blocked] --note "<한 일>" [--accept-conflict]
#                                                                  (0.87.4+ 상태 기본은 doing — 단계가 끝났을 때만 done)
#                                                                  (0.87.0+ 계획 안 일의 진행 한 줄 — 대시보드가 이 줄로 단계를 센다)
#   append · progress 는 0.87.0+ 부터 적으려는 글이 계획의 Non-Goals 와 겹치면 종료 코드 3 (사용자에게 물은 뒤 --accept-conflict)
#   겹침 = 그 Non-Goals 항목 낱말의 절반 이상이 적으려는 글에 있음(0.88.2+ — 낱말 하나만 같은 글은 통과)
#   plan-link.sh exempt --kind release|sync --why "<이유>"         (0.87.0+ 계획 없이 해도 되는 정한 예외)
#   split · join 은 두 일을 가르고 합친다: 두 일이 같은 파일을 고치지 않을 때만, 하던 계획 A 를 따로 만든 폴더(git worktree)로
#   보내 이어 가게 하고 새 계획 B 는 원래 폴더에서 한다. 가를 때 A 의 확인 명령(TESTS.md 의 실행 블록 · --verify)을 돌려
#   결과를 계획 폴더에 적어 두고, 합친 뒤 다시 돌려 "이름: 값" 줄끼리 비교한다. 겹치거나 고칠 파일을 모르면 종료 코드 3
#   (아무것도 만들지 않음 — 지금처럼 pause). 합칠 때 같은 줄 충돌이면 종료 코드 3(아무것도 바꾸지 않음).
#   가르기는 원래 폴더의 작업 파일 · 색인 · 가지를 건드리지 않고, 합치기는 커밋을 만들지 않는다(달라진 파일만 작업 파일에 옮긴다).
#   따로 만든 폴더와 가지는 지우지 않는다. SCV_NOW 로 시각을 고정할 수 있다(시험).
#
# 턴 끝 계획 기록 검사(turn-check.sh)가 켜진 턴이면 기록 줄마다 "요청: <원문 앞부분> (요청 <번호>)" 가 붙는다.
# 기록을 실제로 남긴 명령은 그 턴의 영수증도 스스로 남긴다(0.92.2+) — 도구 앞 훅은 명령 글의 첫 줄이 정해진 꼴일 때만
# 영수증을 남겨, 경로를 변수에 담거나 다른 명령 뒤에 이어 돌린 기록이 "기록 없음"으로 막혔다.
# 계획 이름은 promote/ 에서 먼저, 없으면 archive/ 에서 찾는다(끝난 B 는 보관돼 있다).
# PROMOTE_DIR · ARCHIVE_DIR 를 주면 그대로 쓴다(모노레포 · 시험). SCV_TODAY 로 날짜를 고정할 수 있다(시험).
#
# 종료 코드: 0 해냄 · 3 충돌/겹침이 있어 아무 파일도 바꾸지 않음 · 1 오류 · 2 사용법
# 순수부: lib/plan-link.sh. 계획 20261109-wookiya1364-plan-pause-and-return.
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/plan-link.sh
source "$SCRIPT_DIR/lib/plan-link.sh"
# shellcheck source=lib/scvroot.sh
source "$SCRIPT_DIR/lib/scvroot.sh"
# shellcheck source=lib/turn-check.sh
source "$SCRIPT_DIR/lib/turn-check.sh"
# 가르기 · 합치기만 쓰는 lib/attachment-scope.sh 는 그 갈래에서 읽는다 — 매번 도는 갈래의 시작 시간을 늘리지 않는다.
# 버전 비교(scv_ver_lt)는 lib/scvroot.sh 가 읽는 lib/template-digest.sh 의 것이다.

# @effect utf8_locale
# 이유: 지역 설정을 읽고 바꾼다 — 낱말을 바이트가 아니라 글자로 나누려고(조사 떼기 · 2자 미만 빼기). UTF-8 이 아니면 쓸 수 있는 것을 고른다
utf8_locale() {
  local x='가' l keep="${LC_ALL-}" had="${LC_ALL+y}"
  (( ${#x} == 1 )) && return 0
  for l in C.UTF-8 en_US.UTF-8 ko_KR.UTF-8; do
    { LC_ALL="$l"; } 2>/dev/null
    (( ${#x} == 1 )) && { export LC_ALL; return 0; }
  done
  if [[ -n "$had" ]]; then { LC_ALL="$keep"; } 2>/dev/null; else unset LC_ALL; fi
  return 0
}
utf8_locale

# @effect usage
# 이유: 사용법을 표준 오류에 쓰고 끝낸다
usage() {
  sed -n '6,13p' "${BASH_SOURCE[0]}" | sed 's/^#   //' >&2
  exit 2
}

# @effect find_plan
# 이유: 파일 시스템에서 계획 파일 경로를 찾는다
find_plan() {
  local slug="$1"
  if [[ -f "$PROMOTE_DIR/$slug/PLAN.md" ]]; then printf '%s' "$PROMOTE_DIR/$slug/PLAN.md"
  elif [[ -f "$ARCHIVE_DIR/$slug/PLAN.md" ]]; then printf '%s' "$ARCHIVE_DIR/$slug/PLAN.md"
  else echo "✖ 계획을 찾을 수 없다: $slug ($PROMOTE_DIR · $ARCHIVE_DIR)" >&2; return 1
  fi
}

# @effect read_plan
# 이유: 계획 파일을 읽는다(끝 줄바꿈까지 그대로)
read_plan() {
  local t; t="$(cat "$1"; printf x)"; printf '%s' "${t%x}"
}

# @pure
# 역할: 계획 글의 제목(title 칸)을 낸다 — 없으면 대신 받은 이름(폴더 이름)
# 종류: 꺼내기
# 예: $'---\ntitle: 로그 정리\n---' "b" → "로그 정리"
# 예: "# b" "b" → "b"
plan_title() {
  local t; t="$(scv_plan_fm_get "${1:-}" title)"; printf '%s' "${t:-${2:-}}"
}

# @effect turn_info
# 이유: 이번 턴 상태(요청 번호 · 원문 · 턴 폴더)를 turn-check.sh 로 읽는다
turn_info() {
  local out; out="$(bash "$SCRIPT_DIR/turn-check.sh" info 2>/dev/null || true)"
  TURN_ID="$(printf '%s\n' "$out" | sed -n 's/^TURN_ID: //p' | head -n 1)"
  TURN_REQ="$(printf '%s\n' "$out" | sed -n 's/^TURN_REQ: //p' | head -n 1)"
  TURN_DIR="$(printf '%s\n' "$out" | sed -n 's/^TURN_DIR: //p' | head -n 1)"
  TAG="$(scv_tc_req_tag "$TURN_ID" "$TURN_REQ")"
}

# @effect leave_receipt
# 이유: 기록을 실제로 남긴 뒤 이번 턴의 영수증 파일에 한 줄을 더한다 — 턴 끝 검사가 명령 글의 모양(변수에 담은 경로 · 다른 명령 뒤 · 둘째 줄)에 기대지 않게
leave_receipt() {
  [[ -n "$TURN_DIR" && -d "$TURN_DIR/.turn-plan" && ! -L "$TURN_DIR/.turn-plan" && -f "$TURN_DIR/.turn-plan/id" ]] || return 0
  printf 'plan-link %s (ran)\n' "$1" >> "$TURN_DIR/.turn-plan/receipts" 2>/dev/null || true
}

# @effect write_plan
# 이유: 계획 파일에 쓴다 — 바뀐 것이 없으면 쓰지 않는다
write_plan() {
  local file="$1" before="$2" after="$3"
  [[ "$after" == "$before" ]] && return 0
  printf '%s' "$after" > "$file"
}

# @effect git_can_split
# 이유: 깃의 버전을 읽는다 — 합침을 객체로만 계산하는 명령(merge-tree --write-tree)은 2.38 부터 있다
git_can_split() {
  local v; v="$(git version 2>/dev/null | awk '{print $3}')"
  [[ -n "$v" ]] && ! scv_ver_lt "$v" "2.38.0"
}

# @effect snapshot_commit
# 이유: 깃 폴더의 지금 상태(커밋하지 않은 것 · 새 파일 포함, 무시 목록은 지킴)를 임시 색인으로 나무로 만들어 커밋 객체 하나를 쓴다 — 작업 파일 · 원래 색인 · 가지는 건드리지 않는다. 넷째 값으로 자리를 주면 그 임시 색인을 거기에 남긴다
snapshot_commit() {
  local root="$1" parent="$2" msg="$3" keep="${4:-}" idx gitdir tree
  gitdir="$(git -C "$root" rev-parse --absolute-git-dir 2>/dev/null)" || return 1
  idx="$(mktemp)"
  if [[ -f "$gitdir/index" ]]; then cp "$gitdir/index" "$idx"; else : > "$idx"; fi
  [[ -s "$idx" ]] || rm -f "$idx"
  GIT_INDEX_FILE="$idx" git -C "$root" add -A >/dev/null 2>&1 || { rm -f "$idx"; return 1; }
  tree="$(GIT_INDEX_FILE="$idx" git -C "$root" write-tree 2>/dev/null)" || { rm -f "$idx"; return 1; }
  if [[ -n "$keep" ]]; then mv -f "$idx" "$keep"; else rm -f "$idx"; fi
  GIT_AUTHOR_NAME=scv GIT_AUTHOR_EMAIL=scv@localhost GIT_COMMITTER_NAME=scv GIT_COMMITTER_EMAIL=scv@localhost \
    git -C "$root" commit-tree "$tree" -p "$parent" -m "$msg"
}

# @effect run_verify
# 이유: 계획의 확인 명령을 저장소 폴더에서 돌려, 끝 코드를 적은 첫 줄과 출력을 결과 파일에 쓴다
run_verify() {
  local root="$1" cmd="$2" out="$3" now="$4" tmp rc=0
  tmp="$(mktemp)"
  ( cd "$root" && bash -c "$cmd" ) > "$tmp" 2>&1 || rc=$?
  { printf '# 확인 명령 끝 코드 %s · %s\n' "$rc" "$now"; cat "$tmp"; } > "$out"
  rm -f "$tmp"
}

[[ $# -ge 2 ]] || usage
CMD="$1"; shift
CMD_ARG1=""
if [[ "$CMD" == exempt ]]; then CMD_ARG1="$1"; shift; fi
[[ -n "${PROMOTE_DIR:-}" && -n "${ARCHIVE_DIR:-}" ]] || scv_init_paths ""
DAY="${SCV_TODAY:-$(date +%Y-%m-%d)}"
NOW="${SCV_NOW:-$DAY $(date +%H:%M)}"
TURN_ID=""; TURN_REQ=""; TURN_DIR=""; TAG=""
turn_info

case "$CMD" in
  append)
    A="$1"; shift; AFTER=""; STEP=""; REDO=""; WHY=""; ACCEPT=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --after) AFTER="${2:-}"; shift 2 ;;
        --step) STEP="${2:-}"; shift 2 ;;
        --redo) REDO="${2:-}"; shift 2 ;;
        --why) WHY="${2:-}"; shift 2 ;;
        --accept-conflict) ACCEPT=1; shift ;;
        *) usage ;;
      esac
    done
    [[ -n "$WHY" ]] || usage
    [[ -z "$TAG" ]] || WHY="$WHY"$'\n'"$TAG"
    FA="$(find_plan "$A")" || exit 1
    TA="$(read_plan "$FA"; printf x)"; TA="${TA%x}"
    if [[ -n "$STEP" ]]; then
      OUT="$(scv_tc_nongoal_hits "$TA" "${STEP%% — *}")"
      if [[ -n "$OUT" && "$ACCEPT" -eq 0 ]]; then
        printf '%s\n' "$OUT"
        echo "STOPPED: 계획이 하지 않기로 한 일과 겹친다 — 다른 목표면 pause 로 새 계획, 같은 목표가 맞으면 사용자에게 물은 뒤 --accept-conflict 로 다시" >&2
        exit 3
      fi
    fi
    if [[ -n "$REDO" ]]; then
      STEP="$(scv_plan_redo_step "$TA" "$REDO")"
      [[ -n "$STEP" ]] || { echo "✖ $A 에 ${REDO}단계가 없다" >&2; exit 1; }
      AFTER=99999
      ENTRY="**$DAY 다시 하기** — ${REDO}단계를 바뀐 요건으로 다시 함"$'\n'"새 단계: ${STEP%% — *}"$'\n'"이유: $WHY"
    else
      [[ -n "$STEP" && "$AFTER" =~ ^[0-9]+$ ]] || usage
      ENTRY="**$DAY 추가** — ${AFTER}단계 뒤에 새 단계"$'\n'"새 단계: ${STEP%% — *}"$'\n'"이유: $WHY"
    fi
    NA="$(scv_plan_insert_step "$TA" "$AFTER" "$STEP"; printf x)"; NA="${NA%x}"
    [[ -n "$REDO" ]] || { NA="$(scv_plan_shift_progress "$NA" "$AFTER"; printf x)"; NA="${NA%x}"; }
    NA="$(scv_plan_history_add "$NA" "$ENTRY"; printf x)"; NA="${NA%x}"
    write_plan "$FA" "$TA" "$NA"
    leave_receipt append
    echo "APPENDED: $A (${ENTRY%%$'\n'*})"
    ;;

  check-before)
    A="$1"; B="${2:-}"; [[ -n "$B" ]] || usage
    FA="$(find_plan "$A")" || exit 1; FB="$(find_plan "$B")" || exit 1
    OUT="$(scv_plan_conflict_before "$(read_plan "$FA")" "$(read_plan "$FB")")"
    if [[ -n "$OUT" ]]; then printf '%s\n' "$OUT"; exit 3; fi
    echo "NO_CONFLICT: $A ↔ $B"
    ;;

  pause)
    A="$1"; shift; B=""; AT=""; WHY=""; ACCEPT=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --by) B="${2:-}"; shift 2 ;;
        --resume-at) AT="${2:-}"; shift 2 ;;
        --why) WHY="${2:-}"; shift 2 ;;
        --accept-conflict) ACCEPT=1; shift ;;
        *) usage ;;
      esac
    done
    [[ -n "$B" && -n "$WHY" && "$AT" =~ ^[0-9]+$ ]] || usage
    [[ -z "$TAG" ]] || WHY="$WHY"$'\n'"$TAG"
    FA="$(find_plan "$A")" || exit 1; FB="$(find_plan "$B")" || exit 1
    TA="$(read_plan "$FA"; printf x)"; TA="${TA%x}"; TB="$(read_plan "$FB"; printf x)"; TB="${TB%x}"
    if [[ "$(scv_plan_fm_get "$TA" status)" == paused ]]; then
      echo "✖ $A 는 이미 보류다 (paused_by: $(scv_plan_fm_get "$TA" paused_by))" >&2; exit 1
    fi
    OUT="$(scv_plan_conflict_before "$TA" "$TB")"
    if [[ -n "$OUT" && "$ACCEPT" -eq 0 ]]; then
      printf '%s\n' "$OUT"
      echo "STOPPED: 충돌이 있어 아무것도 바꾸지 않았다 — 사용자에게 물은 뒤 --accept-conflict 로 다시" >&2
      exit 3
    fi
    NA="$(scv_plan_mark_pause "$TA" "$B" "$(plan_title "$TB" "$B")" "$AT" "$DAY" "$WHY"; printf x)"; NA="${NA%x}"
    NB="$(scv_plan_link_return "$TB" "$A" "$(plan_title "$TA" "$A")" "$DAY" "$WHY"; printf x)"; NB="${NB%x}"
    write_plan "$FA" "$TA" "$NA"; write_plan "$FB" "$TB" "$NB"
    leave_receipt pause
    echo "PAUSED: $A (by $B · ${AT}단계에서 재개)"
    echo "LINKED: $B → return_to $A"
    ;;

  check-after|resume)
    B="$1"; shift; FILES=""; ACCEPT=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --changed) FILES="$FILES${FILES:+$'\n'}${2:-}"; shift 2 ;;
        --accept-overlap) ACCEPT=1; shift ;;
        *) usage ;;
      esac
    done
    FB="$(find_plan "$B")" || exit 1
    TB="$(read_plan "$FB"; printf x)"; TB="${TB%x}"
    A="$(scv_plan_fm_get "$TB" return_to)"
    if [[ -z "$A" ]]; then echo "NO_RETURN: $B 에 return_to 가 없다 — 돌아갈 계획 없음"; exit 0; fi
    FA="$(find_plan "$A")" || { echo "⚠ return_to 가 가리키는 계획이 없다: $A — 복귀 건너뜀" >&2; exit 0; }
    TA="$(read_plan "$FA"; printf x)"; TA="${TA%x}"
    OUT="$(scv_plan_conflict_after "$TA" "$FILES")"
    if [[ "$CMD" == check-after ]]; then
      if [[ -n "$OUT" ]]; then printf '%s\n' "$OUT"; exit 3; fi
      echo "NO_OVERLAP: $B → $A"; exit 0
    fi
    if [[ -n "$OUT" && "$ACCEPT" -eq 0 ]]; then
      printf '%s\n' "$OUT"
      echo "STOPPED: 겹침이 있어 아무것도 바꾸지 않았다 — 사용자에게 물은 뒤 --accept-overlap 로 다시" >&2
      exit 3
    fi
    if [[ "$(scv_plan_fm_get "$TA" status)" != paused || "$(scv_plan_fm_get "$TA" paused_by)" != "$B" ]]; then
      echo "NOT_PAUSED_BY: $A 는 $B 때문에 보류된 계획이 아니다 — 바꾸지 않음"; exit 0
    fi
    NA="$(scv_plan_mark_resume "$TA" "$(plan_title "$TB" "$B")" "$DAY"; printf x)"; NA="${NA%x}"
    write_plan "$FA" "$TA" "$NA"
    leave_receipt resume
    echo "RESUMED: $A (from $B · $(scv_plan_fm_get "$TA" resume_at)단계부터)"
    ;;

  progress)
    A="$1"; shift; STEPN=""; NOTE=""; PSTATE=doing; ACCEPT=0
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --step) STEPN="${2:-}"; shift 2 ;;
        --note) NOTE="${2:-}"; shift 2 ;;
        --state) PSTATE="${2:-}"; shift 2 ;;
        --accept-conflict) ACCEPT=1; shift ;;
        *) usage ;;
      esac
    done
    [[ "$STEPN" =~ ^[0-9]+[a-z]?$ && -n "$NOTE" ]] || usage
    case "$PSTATE" in doing|done|blocked) ;; *) usage ;; esac
    FA="$(find_plan "$A")" || exit 1
    TA="$(read_plan "$FA"; printf x)"; TA="${TA%x}"
    OUT="$(scv_tc_nongoal_hits "$TA" "$NOTE")"
    if [[ -n "$OUT" && "$ACCEPT" -eq 0 ]]; then
      printf '%s\n' "$OUT"
      echo "STOPPED: 계획이 하지 않기로 한 일과 겹친다 — 계획 밖 일이면 사용자에게 물어 append · pause 로, 같은 일이 맞으면 물은 뒤 --accept-conflict 로 다시" >&2
      exit 3
    fi
    NA="$(scv_plan_history_add "$TA" "$(scv_tc_progress_entry "$DAY" "$STEPN" "$PSTATE" "$NOTE" "$TAG")"; printf x)"; NA="${NA%x}"
    write_plan "$FA" "$TA" "$NA"
    leave_receipt progress
    echo "PROGRESS: $A (${STEPN}단계 $PSTATE: $NOTE)"
    ;;

  split)
    # shellcheck source=lib/attachment-scope.sh
    source "$SCRIPT_DIR/lib/attachment-scope.sh"
    A="$1"; shift; B=""; AT=""; WHY=""; VERIFY=""; DIR=""; FILES=""; OWN=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --with) B="${2:-}"; shift 2 ;;
        --at) AT="${2:-}"; shift 2 ;;
        --why) WHY="${2:-}"; shift 2 ;;
        --files) FILES="$FILES${FILES:+$'\n'}${2:-}"; shift 2 ;;
        --own) OWN="$OWN${OWN:+$'\n'}${2:-}"; shift 2 ;;
        --verify) VERIFY="${2:-}"; shift 2 ;;
        --dir) DIR="${2:-}"; shift 2 ;;
        *) usage ;;
      esac
    done
    [[ -n "$B" && -n "$WHY" && "$AT" =~ ^[0-9]+$ ]] || usage
    [[ -z "$TAG" ]] || WHY="$WHY"$'\n'"$TAG"
    FA="$(find_plan "$A")" || exit 1; FB="$(find_plan "$B")" || exit 1
    TA="$(read_plan "$FA"; printf x)"; TA="${TA%x}"; TB="$(read_plan "$FB"; printf x)"; TB="${TB%x}"
    if [[ -n "$(scv_plan_fm_get "$TA" split_with)" ]]; then
      echo "✖ $A 는 이미 갈라져 있다 (split_with: $(scv_plan_fm_get "$TA" split_with)) — 둘까지만 다룬다" >&2; exit 1
    fi
    ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "✖ 깃 저장소 안이 아니다 — 가르지 않는다" >&2; exit 1; }
    OUT="$(scv_plan_split_check "$TA" "$OWN" "$FILES")"
    git_can_split || OUT="$OUT${OUT:+$'\n'}알 수 없음 · 깃이 2.38 보다 낮아 합침을 미리 계산할 수 없다"
    if [[ -n "$OUT" ]]; then
      printf '%s\n' "$OUT"
      echo "STOPPED: 가르지 않았다(아무것도 만들지 않음) — 지금처럼 멈추고 돌아오기(pause)로 간다" >&2
      exit 3
    fi
    [[ -n "$VERIFY" ]] || VERIFY="$(attachment_scope_read_test_command "$(dirname "$FA")/TESTS.md" 2>/dev/null || true)"
    if [[ -z "${VERIFY//[[:space:]]/}" ]]; then
      echo "✖ $A 의 확인 명령이 없다(TESTS.md 의 실행 블록, 또는 --verify) — 가르지 않는다" >&2; exit 1
    fi
    DIR="${DIR:-$(dirname "$ROOT")/$(basename "$ROOT").split-$A}"; BR="scv-split/$A"
    if [[ -e "$DIR" ]]; then echo "✖ 따로 만들 폴더의 자리에 이미 무엇이 있다: $DIR" >&2; exit 1; fi
    if git -C "$ROOT" show-ref --verify --quiet "refs/heads/$BR"; then echo "✖ 가지가 이미 있다: $BR" >&2; exit 1; fi
    HEADC="$(git -C "$ROOT" rev-parse --verify -q HEAD)" || { echo "✖ 커밋이 하나도 없는 저장소다 — 가르지 않는다" >&2; exit 1; }
    RES="$(dirname "$FA")/split-result.txt"
    run_verify "$ROOT" "$VERIFY" "$RES" "$NOW"
    BASE="$(snapshot_commit "$ROOT" "$HEADC" "scv split: $A")" || { echo "✖ 지금 상태를 사진으로 남기지 못했다" >&2; exit 1; }
    if ! git -C "$ROOT" worktree add -q -b "$BR" "$DIR" "$BASE" >/dev/null 2>&1; then
      echo "✖ 폴더를 따로 만들지 못했다: $DIR" >&2; exit 1
    fi
    # 계획 파일에는 저장소 옆자리면 저장소 기준(../이름)으로 적는다 — 이 컴퓨터의 전체 경로를 기록에 남기지 않는다.
    DIR_NOTE="$DIR"
    [[ "$(dirname "$DIR")" == "$(dirname "$ROOT")" ]] && DIR_NOTE="../$(basename "$DIR")"
    NA="$(scv_plan_mark_split "$TA" "$B" "$(plan_title "$TB" "$B")" "$AT" "$NOW" "$WHY" "$DIR_NOTE" "$BR" "$BASE"; printf x)"; NA="${NA%x}"
    NB="$(scv_plan_mark_split "$TB" "$A" "$(plan_title "$TA" "$A")" "$AT" "$NOW" "$WHY"; printf x)"; NB="${NB%x}"
    write_plan "$FA" "$TA" "$NA"; write_plan "$FB" "$TB" "$NB"
    leave_receipt split
    RTEXT="$(cat "$RES")"
    echo "SPLIT: $A ↔ $B (${AT}단계에서 가름)"
    echo "FOLDER: $DIR (가지 $BR)"
    echo "RESULT: $RES (끝 코드 $(scv_plan_result_code "$RTEXT"))"
    [[ -n "$(scv_plan_result_values "$RTEXT")" ]] || echo "비교할 값이 없음 — 통과 여부만 비교함"
    ;;

  join)
    # shellcheck source=lib/attachment-scope.sh
    source "$SCRIPT_DIR/lib/attachment-scope.sh"
    A="$1"; shift; VERIFY=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --verify) VERIFY="${2:-}"; shift 2 ;;
        *) usage ;;
      esac
    done
    FA="$(find_plan "$A")" || exit 1
    TA="$(read_plan "$FA"; printf x)"; TA="${TA%x}"
    B="$(scv_plan_fm_get "$TA" split_with)"; DIR="$(scv_plan_fm_get "$TA" split_dir)"
    BASE="$(scv_plan_fm_get "$TA" split_base)"; BR="$(scv_plan_fm_get "$TA" split_branch)"
    if [[ -z "$B" || -z "$DIR" || -z "$BASE" ]]; then
      echo "NOT_SPLIT: $A 는 따로 만든 폴더로 갈라진 계획이 아니다 — 바꾸지 않음"; exit 0
    fi
    ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "✖ 깃 저장소 안이 아니다" >&2; exit 1; }
    [[ "$DIR" == /* ]] || DIR="$ROOT/$DIR"
    [[ -d "$DIR" ]] || { echo "✖ 따로 만든 폴더가 없다: $DIR" >&2; exit 1; }
    DIR="$(cd "$DIR" && pwd -P)"
    git_can_split || { echo "✖ 깃이 2.38 보다 낮아 합침을 미리 계산할 수 없다" >&2; exit 1; }
    # 두 폴더의 지금 상태를 가를 때 사진의 자식으로 남기면, 세 갈래 합침의 공통 조상이 가를 때 사진이 된다.
    # 원래 폴더의 사진을 만든 임시 색인은 남겨 둔다 — 합친 결과를 작업 파일에 옮길 때 깃이 그것으로 "지금과 같은지"를 본다.
    IDX="$(mktemp)"
    OURS="$(snapshot_commit "$ROOT" "$BASE" "scv join: 원래 폴더" "$IDX")" || { rm -f "$IDX"; echo "✖ 원래 폴더의 지금 상태를 사진으로 남기지 못했다" >&2; exit 1; }
    THEIRS="$(snapshot_commit "$DIR" "$BASE" "scv join: 따로 만든 폴더")" || { rm -f "$IDX"; echo "✖ 따로 만든 폴더의 지금 상태를 사진으로 남기지 못했다" >&2; exit 1; }
    MRC=0; MERGED="$(git -C "$ROOT" merge-tree --write-tree --name-only "$OURS" "$THEIRS" 2>/dev/null)" || MRC=$?
    if (( MRC == 1 )); then
      rm -f "$IDX"
      printf '%s\n' "$MERGED" | awk 'NR == 1 { next } /^$/ { exit } { print "충돌 · " $0 }'
      echo "STOPPED: 같은 줄을 두 쪽이 다르게 고쳤다 — 아무것도 바꾸지 않았다. 충돌을 푼 뒤 다시 합친다" >&2
      exit 3
    elif (( MRC != 0 )); then
      rm -f "$IDX"; echo "✖ 합침을 계산하지 못했다(깃 끝 코드 $MRC)" >&2; exit 1
    fi
    TREE="${MERGED%%$'\n'*}"
    MOVED="$(git -C "$ROOT" diff --no-renames --name-only "$OURS" "$TREE" | wc -l | tr -d ' ')"
    git -C "$ROOT" update-ref "refs/scv/join/$A" "$OURS" 2>/dev/null || true
    # 합친 나무로 작업 파일을 옮긴다: 원래 폴더의 사진에서 합친 나무로 가는 두 나무 옮기기를 임시 색인으로 한다 —
    # 달라진 파일만 쓰고 지우며, 사진을 찍은 뒤 작업 파일이 바뀌었으면 깃이 멈춘다. 커밋 · 원래 색인 · 가지는 그대로다.
    if ! GIT_INDEX_FILE="$IDX" git -C "$ROOT" read-tree -m -u "$OURS" "$TREE" >/dev/null 2>&1; then
      rm -f "$IDX"; echo "✖ 합친 결과를 작업 파일에 옮기지 못했다 — 사진을 찍은 뒤 파일이 바뀐 것으로 보임. 아무 계획 파일도 바꾸지 않았다" >&2; exit 1
    fi
    rm -f "$IDX"
    [[ -n "$VERIFY" ]] || VERIFY="$(attachment_scope_read_test_command "$(dirname "$FA")/TESTS.md" 2>/dev/null || true)"
    OLD="$(cat "$(dirname "$FA")/split-result.txt" 2>/dev/null || true)"; NEW=""
    if [[ -n "${VERIFY//[[:space:]]/}" ]]; then
      RES="$(dirname "$FA")/join-result.txt"
      run_verify "$ROOT" "$VERIFY" "$RES" "$NOW"
      NEW="$(cat "$RES")"
    fi
    DIFF="$(scv_plan_results_diff "$OLD" "$NEW")"
    NOTE=""
    [[ -n "$(scv_plan_result_values "$OLD")$(scv_plan_result_values "$NEW")" ]] || NOTE="비교할 값이 없음 — 통과 여부만 비교함"
    COUNT=0; FLAT=""
    while IFS= read -r LINE; do
      [[ -n "$LINE" ]] || continue
      COUNT=$((COUNT + 1)); FLAT="$FLAT${FLAT:+ · }$LINE"
    done <<< "$DIFF"
    TB=""; FB="$(find_plan "$B" 2>/dev/null)" || FB=""
    if [[ -n "$FB" ]]; then TB="$(read_plan "$FB"; printf x)"; TB="${TB%x}"; fi
    NA="$(scv_plan_mark_join "$TA" "$B" "$(plan_title "$TB" "$B")" "$NOW" "$DIFF" "$NOTE"; printf x)"; NA="${NA%x}"
    if (( COUNT )); then
      NA="$(scv_plan_insert_step "$NA" 99999 "다시 하기: 달라진 결과 맞추기 — $FLAT"; printf x)"; NA="${NA%x}"
      # 더한 단계의 번호를 머리말에 적는다(joined_redo) — 창이 그 단계를 합친 기록 안에 그리고, 일이 그 단계에 서 있다고 본다
      REDO=0; while IFS= read -r ROW; do [[ -n "$ROW" ]] && REDO="${ROW%%$'\t'*}"; done <<< "$(scv_plan_steps "$NA")"
      NA="$(scv_plan_fm_set "$NA" joined_redo "$REDO"; printf x)"; NA="${NA%x}"
    fi
    write_plan "$FA" "$TA" "$NA"
    if [[ -n "$FB" ]]; then
      NB="$(scv_plan_mark_join "$TB" "$A" "$(plan_title "$TA" "$A")" "$NOW" "$DIFF" "$NOTE"; printf x)"; NB="${NB%x}"
      write_plan "$FB" "$TB" "$NB"
    fi
    leave_receipt join
    echo "같은 줄 충돌 없음"
    [[ -z "$NOTE" ]] || echo "$NOTE"
    if (( COUNT )); then echo "달라진 결과 ${COUNT}개: $FLAT"; else echo "달라진 결과 없음"; fi
    echo "JOINED: $A ↔ $B (바뀐 파일 ${MOVED}개를 원래 폴더의 작업 파일에 옮김 — 커밋하지 않음)"
    echo "KEPT: $DIR · 가지 $BR — 지울지는 사용자에게 묻는다"
    ;;

  exempt)
    KIND=""; WHY=""
    set -- "$CMD_ARG1" "$@"
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --kind) KIND="${2:-}"; shift 2 ;;
        --why) WHY="${2:-}"; shift 2 ;;
        *) usage ;;
      esac
    done
    [[ -n "$WHY" ]] || usage
    if [[ "$(scv_tc_exempt_ok "$KIND")" != yes ]]; then
      echo "✖ 예외는 release · sync 만 된다 (받은 값: ${KIND:-빈 값}) — 그 밖의 일은 계획을 만든다" >&2; exit 2
    fi
    ENTRY="$(scv_tc_exempt_entry "$DAY" "$KIND" "$WHY" "$TAG")"
    if [[ -n "$TURN_DIR" && -d "$TURN_DIR/.turn-plan" && ! -L "$TURN_DIR/.turn-plan" ]]; then
      printf '%s\n' "$ENTRY" >> "$TURN_DIR/.turn-plan/exempt"
    fi
    for FA in "$PROMOTE_DIR"/*/PLAN.md; do
      [[ -f "$FA" ]] || continue
      TA="$(read_plan "$FA"; printf x)"; TA="${TA%x}"
      case "$(scv_plan_fm_get "$TA" status)" in in_progress|testing) ;; *) continue ;; esac
      NA="$(scv_plan_history_add "$TA" "$ENTRY"; printf x)"; NA="${NA%x}"
      write_plan "$FA" "$TA" "$NA"; break
    done
    leave_receipt exempt
    echo "EXEMPT: $KIND — $WHY"
    ;;

  *) usage ;;
esac
