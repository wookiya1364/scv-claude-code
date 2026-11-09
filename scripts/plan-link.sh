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
#   plan-link.sh progress <A> --step <N> [--state doing|done|blocked] --note "<한 일>" [--accept-conflict]
#                                                                  (0.87.0+ 계획 안 일의 진행 한 줄 — 대시보드가 이 줄로 단계를 센다)
#   append · progress 는 0.87.0+ 부터 적으려는 글이 계획의 Non-Goals 와 겹치면 종료 코드 3 (사용자에게 물은 뒤 --accept-conflict)
#   plan-link.sh exempt --kind release|sync --why "<이유>"         (0.87.0+ 계획 없이 해도 되는 정한 예외)
#
# 턴 끝 계획 기록 검사(turn-check.sh)가 켜진 턴이면 기록 줄마다 "요청: <원문 앞부분> (요청 <번호>)" 가 붙는다.
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

# @effect usage
# 이유: 사용법을 표준 오류에 쓰고 끝낸다
usage() {
  sed -n '6,11p' "${BASH_SOURCE[0]}" | sed 's/^#   //' >&2
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

# @effect write_plan
# 이유: 계획 파일에 쓴다 — 바뀐 것이 없으면 쓰지 않는다
write_plan() {
  local file="$1" before="$2" after="$3"
  [[ "$after" == "$before" ]] && return 0
  printf '%s' "$after" > "$file"
}

[[ $# -ge 2 ]] || usage
CMD="$1"; shift
CMD_ARG1=""
if [[ "$CMD" == exempt ]]; then CMD_ARG1="$1"; shift; fi
[[ -n "${PROMOTE_DIR:-}" && -n "${ARCHIVE_DIR:-}" ]] || scv_init_paths ""
DAY="${SCV_TODAY:-$(date +%Y-%m-%d)}"
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
    NA="$(scv_plan_history_add "$NA" "$ENTRY"; printf x)"; NA="${NA%x}"
    write_plan "$FA" "$TA" "$NA"
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
    echo "RESUMED: $A (from $B · $(scv_plan_fm_get "$TA" resume_at)단계부터)"
    ;;

  progress)
    A="$1"; shift; STEPN=""; NOTE=""; PSTATE=done; ACCEPT=0
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
    echo "PROGRESS: $A (${STEPN}단계 $PSTATE: $NOTE)"
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
    echo "EXEMPT: $KIND — $WHY"
    ;;

  *) usage ;;
esac
