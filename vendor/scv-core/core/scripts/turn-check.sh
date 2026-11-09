#!/usr/bin/env bash
# turn-check.sh — 턴 끝 계획 기록 검사의 어댑터: 사진 찍기 · 영수증 · 판정 · 선택 답 기록.
# 무언가를 고친 턴은 계획에 기록이 남아야 끝난다(scv_settings.json SCV_TURN_PLAN_CHECK=on, 기본 켬).
#
#   turn-check.sh start   --dir <턴 폴더> | --session <세션>            (표준 입력: 이번 턴 사용자 원문)
#   turn-check.sh touch   --dir <턴 폴더> <경로>…    (도구 앞: 처음 건드리는 저장소를 더 찍음)
#   turn-check.sh receipt --dir <턴 폴더>            (표준 입력: 도구가 돌릴 명령 글)
#   turn-check.sh end     --dir <턴 폴더>            → TURN_PLAN: pass|block|pass-unrecorded|off · TURN_PLAN_REASON: …
#   turn-check.sh choice  --question <질문> --answer <답>
#   turn-check.sh step    --dir <턴 폴더> --tool <도구 이름>   (도구 앞: 단계 보고 도구면 표시)
#   turn-check.sh info                               → TURN_ID: … · TURN_REQ: … (plan-link 이 읽음)
#
# 호스트 설정 경로(SCV_GUARD_EXEMPT — 래퍼가 도구 앞 훅에 넘김)는 바뀐 파일에서 뺀다.
# 작업 공간 = 이 프로젝트 + SCV_WORKSPACE_REPOS(절대 경로를 : 로 이음) + 그 턴에 도구가 경로로 건드린 저장소.
# git 저장소는 바뀐 파일 해시 + HEAD, git 아닌 폴더는 파일 목록 · 수정 시각 · 크기로 찍는다.
# 같은 폴더에서 동시에 도는 두 세션은 구분하지 못한다(계획의 한계). 어떤 실패도 세션을 막지 않는다 — 판단할 수 없으면 pass.
# 순수부: lib/turn-check.sh. 계획 20261109-wookiya1364-turn-plan-check.
set -uo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/turn-check.sh
source "$SCRIPT_DIR/lib/turn-check.sh"
# shellcheck source=lib/plan-link.sh
source "$SCRIPT_DIR/lib/plan-link.sh"
# shellcheck source=lib/settings.sh
source "$SCRIPT_DIR/lib/settings.sh" 2>/dev/null || true
# 호스트 프로필(래퍼 파일)을 읽되, 환경에 직접 준 값이 있으면 그것을 쓴다(시험 · 다른 호스트).
_tc_e1="${SCV_STEP_TOOL:-}"; _tc_e2="${SCV_STEP_TOOL_ON_FILE:-}"; _tc_e3="${SCV_STEP_TOOL_ON_MARK:-}"
# shellcheck source=lib/host-profile.sh
source "$SCRIPT_DIR/lib/host-profile.sh" 2>/dev/null || true
[[ -n "$_tc_e1" ]] && SCV_STEP_TOOL="$_tc_e1"
[[ -n "$_tc_e2" ]] && SCV_STEP_TOOL_ON_FILE="$_tc_e2"
[[ -n "$_tc_e3" ]] && SCV_STEP_TOOL_ON_MARK="$_tc_e3"

PROJECT="$(pwd -P)"
JDIR="${SCV_JOURNAL_DIR:-scv/journal}"
PROMOTE="${PROMOTE_DIR:-scv/promote}"
ARCHIVE="${ARCHIVE_DIR:-scv/archive}"
MAX_FILES="${SCV_TURN_SNAP_MAX:-20000}"

# @effect usage
# 이유: 사용법을 표준 오류에 쓰고 끝낸다
usage() { sed -n '5,10p' "${BASH_SOURCE[0]}" | sed 's/^#   //' >&2; exit 2; }

# @effect setting
# 이유: 설정 파일에서 값을 읽는다
setting() {
  local v=""
  declare -F settings_get >/dev/null 2>&1 && v="$(settings_get "$1" 2>/dev/null | tr -d '"' | tr -d "'" || true)"
  printf '%s' "${v:-${2:-}}"
}

# @effect enabled
# 이유: 설정을 읽어 검사가 켜졌는지 본다
enabled() { [[ "$(setting SCV_TURN_PLAN_CHECK on)" != off ]]; }

# @effect stat_lines
# 이유: 파일 시스템에서 수정 시각 · 크기를 읽는다(맥 BSD stat · 리눅스 GNU stat 모두)
stat_lines() {
  if stat -f '%m' . >/dev/null 2>&1; then xargs -0 stat -f $'%N\t%m:%z' 2>/dev/null
  else xargs -0 stat -c $'%n\t%Y:%s' 2>/dev/null; fi
}

# @effect snap_root
# 이유: 폴더 하나를 읽어 "경로<TAB>지문" 줄들로 찍는다 — git 이면 바뀐 파일 해시, 아니면 모든 파일의 시각 · 크기
snap_root() {
  local root="$1" files n
  if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    files="$( { git -C "$root" diff --name-only HEAD 2>/dev/null; git -C "$root" ls-files -o --exclude-standard 2>/dev/null; } | LC_ALL=C sort -u)"
    [[ -n "$files" ]] || return 0
    : > "$TMPF"
    ( cd "$root" || exit 0
      while IFS= read -r f; do
        if [[ -f "$f" ]]; then printf '%s\n' "$f" >> "$TMPF"; else printf '%s\tgone\n' "$f"; fi
      done <<< "$files"
      [[ -s "$TMPF" ]] && paste "$TMPF" <(git hash-object --stdin-paths < "$TMPF" 2>/dev/null)
    ) 2>/dev/null
  else
    n="$(cd "$root" && find . \( -name node_modules -o -name .git -o -name scv -o -name .venv -o -name dist -o -name build \) -prune -o -type f -print 2>/dev/null | head -n $((MAX_FILES + 1)) | wc -l | tr -d ' ')"
    (( n > MAX_FILES )) && { printf '@too-many\t%s\n' "$n"; return 0; }
    ( cd "$root" && find . \( -name node_modules -o -name .git -o -name scv -o -name .venv -o -name dist -o -name build \) -prune -o -type f -print0 2>/dev/null | stat_lines | sed 's#^\./##' )
  fi | LC_ALL=C sort
}

# @effect head_of
# 이유: git 저장소의 HEAD 를 읽는다
head_of() { git -C "$1" rev-parse HEAD 2>/dev/null || true; }

# @pure
# 역할: 폴더 경로를 사진 파일 이름으로 바꾼다 — 슬래시 · 빈칸을 밑줄로
# 종류: 변환
# 예: "/Users/a/b c" → "_Users_a_b_c"
key_of() {
  local k="${1//\//_}"
  printf '%s' "${k// /_}"
}

# @effect take_snap
# 이유: 폴더를 찍어 턴 폴더에 사진 · HEAD 를 쓴다(이미 찍었으면 그대로 둔다)
take_snap() {
  local root="$1" k; k="$(key_of "$root")"
  [[ -f "$S/snap.$k" ]] && return 0
  snap_root "$root" > "$S/snap.$k" 2>/dev/null || : > "$S/snap.$k"
  head_of "$root" > "$S/head.$k"
  grep -qxF "$root" "$S/roots" 2>/dev/null || printf '%s\n' "$root" >> "$S/roots"
}

# @effect plan_texts
# 이유: 진행 중 계획 파일들을 읽는다
plan_texts() { local f; for f in "$PROMOTE"/*/PLAN.md; do [[ -f "$f" ]] && cat "$f" && printf '\n'; done; }

# @effect active_plans
# 이유: 계획 파일들을 읽어 진행 중(in_progress · testing) 계획 이름을 최근에 고친 것부터 낸다
active_plans() {
  local f st
  for f in $(ls -t "$PROMOTE"/*/PLAN.md 2>/dev/null); do
    st="$(scv_plan_fm_get "$(cat "$f")" status)"
    [[ "$st" == in_progress || "$st" == testing ]] && basename "$(dirname "$f")"
  done
}

# @effect step_needed
# 이유: 호스트 설정 파일을 읽어 대시보드(단계 보고 도구)가 켜졌는지 본다 — 래퍼가 준 파일 · 표시가 없으면 "no"
step_needed() {
  local f="${SCV_STEP_TOOL_ON_FILE:-}"
  [[ -n "${SCV_STEP_TOOL:-}" && -n "$f" ]] || { printf 'no'; return 0; }
  f="${f/#\~/$HOME}"
  [[ -f "$f" ]] || { printf 'no'; return 0; }
  scv_tc_step_on "$(head -c 262144 "$f" 2>/dev/null)" "${SCV_STEP_TOOL_ON_MARK:-}"
}

# @effect orphan_return
# 이유: 계획 파일들을 읽어, 보류시킨 계획(paused_by)이 이미 보관됐는데 아직 보류인 계획이 있으면 그 보관된 계획 이름을 낸다
orphan_return() {
  local f t by
  for f in "$PROMOTE"/*/PLAN.md; do
    [[ -f "$f" ]] || continue
    t="$(cat "$f")"
    [[ "$(scv_plan_fm_get "$t" status)" == paused ]] || continue
    by="$(scv_plan_fm_get "$t" paused_by)"
    [[ -n "$by" && ! -d "$PROMOTE/$by" && -d "$ARCHIVE/$by" ]] && { printf '%s' "$by"; return 0; }
  done
}

# @effect state_dir
# 이유: 턴 폴더 안 상태 폴더 경로를 정하고 만든다 — 링크면 쓰지 않는다
state_dir() {
  local d="$1"
  [[ -n "$d" && ! -L "$d" ]] || return 1
  S="$d/.turn-plan"
  [[ ! -L "$S" ]] || return 1
  mkdir -p "$S" 2>/dev/null
}

# @effect root_of
# 이유: 경로가 든 git 저장소 맨 위를 찾는다(파일 시스템을 읽음)
root_of() {
  local p="$1" d
  [[ "$p" == /* ]] || p="$PROJECT/$p"
  d="$p"; [[ -d "$d" ]] || d="$(dirname "$d")"
  while [[ -n "$d" && ! -d "$d" ]]; do d="$(dirname "$d")"; done
  git -C "$d" rev-parse --show-toplevel 2>/dev/null || true
}

TMPF="$(mktemp 2>/dev/null || echo /tmp/scv-tc.$$)"
trap 'rm -f "$TMPF"' EXIT

[[ $# -ge 1 ]] || usage
CMD="$1"; shift
DIR=""; SID=""; Q=""; A=""; TOOL=""; PATHS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) DIR="${2:-}"; shift 2 ;;
    --session) SID="${2:-}"; shift 2 ;;
    --question) Q="${2:-}"; shift 2 ;;
    --answer) A="${2:-}"; shift 2 ;;
    --tool) TOOL="${2:-}"; shift 2 ;;
    *) PATHS+=("$1"); shift ;;
  esac
done

# --session 만 주면 그 세션의 턴 폴더(저널/.help-turns/<세션>, 없으면 저널 폴더)를 쓴다 — 훅마다 같은 자리.
if [[ -z "$DIR" ]]; then
  if [[ -n "$SID" && -d "$JDIR/.help-turns/$SID" ]]; then DIR="$JDIR/.help-turns/$SID"; else DIR="$JDIR"; fi
fi

case "$CMD" in
  start)
    enabled || exit 0
    state_dir "$DIR" || exit 0
    rm -f "$S"/snap.* "$S"/head.* "$S/roots" "$S/receipts" "$S/blocks" "$S/exempt" "$S/steps" 2>/dev/null
    # 원문은 저장 전에 비밀 가리개(journal-append.sh --redact-only)를 거친다 — 계획 줄에도 이 글이 붙는다.
    REQ="$(head -c 4000 2>/dev/null | bash "$SCRIPT_DIR/journal-append.sh" --redact-only 2>/dev/null || true)"
    printf '%s' "$REQ" > "$S/req"
    od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n' > "$S/id"
    [[ -s "$S/id" ]] || printf '%08x' "$$" > "$S/id"
    : > "$S/receipts"; printf '0' > "$S/blocks"
    take_snap "$PROJECT"
    IFS=':' read -r -a WS <<< "$(setting SCV_WORKSPACE_REPOS "")"
    for r in ${WS[@]+"${WS[@]}"}; do [[ "$r" == /* && -d "$r" ]] && take_snap "$r"; done
    plan_texts | { t="$(cat)"; scv_tc_plan_lines "$t"; } > "$S/plans"
    mkdir -p "$JDIR" 2>/dev/null && printf '%s\n' "$(cd "$DIR" && pwd -P)" > "$JDIR/.turn-latest" 2>/dev/null
    exit 0
    ;;

  touch)
    enabled || exit 0
    state_dir "$DIR" || exit 0
    [[ -f "$S/id" ]] || exit 0
    [[ -n "${SCV_GUARD_EXEMPT:-}" ]] && printf '%s' "$SCV_GUARD_EXEMPT" > "$S/host-exempt"
    for p in ${PATHS[@]+"${PATHS[@]}"}; do
      r="$(root_of "$p")"; [[ -n "$r" ]] && take_snap "$r"
    done
    exit 0
    ;;

  receipt)
    enabled || exit 0
    state_dir "$DIR" || exit 0
    [[ -f "$S/id" ]] || exit 0
    [[ -n "${SCV_GUARD_EXEMPT:-}" ]] && printf '%s' "$SCV_GUARD_EXEMPT" > "$S/host-exempt"
    C="$(head -c 65536 2>/dev/null || true)"
    R="$(scv_tc_receipt "$C")"
    [[ -n "$R" ]] && printf '%s\n' "$R" >> "$S/receipts"
    exit 0
    ;;

  step)
    enabled || exit 0
    state_dir "$DIR" || exit 0
    [[ -f "$S/id" ]] || exit 0
    [[ -n "${SCV_STEP_TOOL:-}" && "$TOOL" == "$SCV_STEP_TOOL" ]] && printf '%s\n' "$TOOL" >> "$S/steps"
    exit 0
    ;;

  info)
    D="$(cat "$JDIR/.turn-latest" 2>/dev/null || true)"
    [[ -n "$D" && -f "$D/.turn-plan/id" ]] || exit 0
    printf 'TURN_ID: %s\n' "$(cat "$D/.turn-plan/id")"
    printf 'TURN_REQ: %s\n' "$(tr '\n\r\t' '   ' < "$D/.turn-plan/req" | head -c 400)"
    printf 'TURN_DIR: %s\n' "$D"
    exit 0
    ;;

  end)
    enabled || { echo "TURN_PLAN: off"; exit 0; }
    state_dir "$DIR" || { echo "TURN_PLAN: pass"; exit 0; }
    [[ -f "$S/id" ]] || { echo "TURN_PLAN: pass"; exit 0; }
    ID="$(cat "$S/id")"
    CHANGED=""
    while IFS= read -r root; do
      [[ -n "$root" ]] || continue
      k="$(key_of "$root")"
      start_snap="$(cat "$S/snap.$k" 2>/dev/null)"
      grep -q '^@too-many' <<< "$start_snap" && continue
      end_snap="$(snap_root "$root")"
      d="$(scv_tc_diff "$start_snap" "$end_snap")"
      h0="$(cat "$S/head.$k" 2>/dev/null)"; h1="$(head_of "$root")"
      [[ -n "$h0" && "$h0" != "$h1" ]] && d="$d"$'\n'"$(git -C "$root" diff --name-only "$h0" "$h1" 2>/dev/null)"
      d="$(scv_tc_filter "$d" "$(cat "$S/host-exempt" 2>/dev/null)")"
      [[ -n "$d" ]] || continue
      pre=""; [[ "$root" == "$PROJECT" ]] || pre="$(basename "$root"):"
      while IFS= read -r f; do [[ -n "$f" ]] && CHANGED="$CHANGED$pre$f"$'\n'; done <<< "$d"
    done < "$S/roots"
    CHANGED="$(printf '%s' "$CHANGED" | LC_ALL=C sort -u | sed '/^$/d')"
    NCH=0; [[ -n "$CHANGED" ]] && NCH="$(printf '%s\n' "$CHANGED" | wc -l | tr -d ' ')"
    NEWL="$(scv_tc_new_lines "$(cat "$S/plans" 2>/dev/null)" "$(plan_texts | { t="$(cat)"; scv_tc_plan_lines "$t"; })")"
    NST="$(scv_tc_struct_count "$NEWL")"; NRQ="$(scv_tc_req_count "$NEWL" "$ID")"
    NRC="$(grep -c . "$S/receipts" 2>/dev/null || true)"; NRC="${NRC:-0}"
    EX=no; grep -q "(요청 $ID)" "$S/exempt" 2>/dev/null && EX=yes
    ACT="$(active_plans)"; NPL=0; [[ -n "$ACT" ]] && NPL="$(printf '%s\n' "$ACT" | wc -l | tr -d ' ')"
    BL="$(cat "$S/blocks" 2>/dev/null || echo 0)"
    NEED=no; (( NPL > 0 )) && NEED="$(step_needed)"
    NSTEP="$(grep -c . "$S/steps" 2>/dev/null || true)"; NSTEP="${NSTEP:-0}"
    ORPH="$(orphan_return)"
    V="$(scv_tc_judge "$NCH" "$NRC" "$NST" "$NRQ" "$EX" "$NPL" "$BL" "$NEED" "$NSTEP" "$ORPH")"
    case "$V" in
      pass) echo "TURN_PLAN: pass" ;;
      pass-unrecorded)
        echo "TURN_PLAN: pass-unrecorded"
        line="$(date +%Y-%m-%dT%H:%M:%S) 계획 기록 없음 · 파일 ${NCH}개 · $(scv_tc_req_tag "$ID" "$(cat "$S/req" 2>/dev/null)")"
        printf '%s\n' "$line" >> "$JDIR/.turn-plan.log" 2>/dev/null || true
        slug="$(printf '%s\n' "$ACT" | head -n 1)"
        if [[ -n "$slug" && -f "$PROMOTE/$slug/PLAN.md" ]]; then
          t="$(cat "$PROMOTE/$slug/PLAN.md"; printf x)"; t="${t%x}"
          n="$(scv_plan_history_add "$t" "**${SCV_TODAY:-$(date +%Y-%m-%d)} 기록 없음** — 파일 ${NCH}개를 바꾼 턴이 계획 기록 없이 끝남"$'\n'"$(scv_tc_req_tag "$ID" "$(cat "$S/req" 2>/dev/null)")"; printf x)"
          printf '%s' "${n%x}" > "$PROMOTE/$slug/PLAN.md"
        fi
        ;;
      block*)
        printf '%s' "$((BL + 1))" > "$S/blocks"
        echo "TURN_PLAN: block"
        slug="$(printf '%s\n' "$ACT" | head -n 1)"
        case "$V" in "block step") slug="$SCV_STEP_TOOL" ;; "block return") slug="$ORPH" ;; esac
        msg="$(scv_tc_block_msg "${V#block }" "$slug" "$NCH" "$SCRIPT_DIR/plan-link.sh")"
        printf 'TURN_PLAN_REASON: %s\n' "${msg//$'\n'/ / }"
        printf 'TURN_PLAN_FILES: %s\n' "$(printf '%s' "$CHANGED" | head -n 5 | tr '\n' ' ')"
        printf 'TURN_PLAN_ID: %s\n' "$ID"
        ;;
    esac
    exit 0
    ;;

  choice)
    enabled || exit 0
    [[ -n "$Q$A" ]] || exit 0
    slug="$(active_plans | head -n 1)"
    [[ -n "$slug" ]] || exit 0
    f="$PROMOTE/$slug/PLAN.md"
    t="$(cat "$f"; printf x)"; t="${t%x}"
    e="$(scv_tc_choice_entry "${SCV_TODAY:-$(date +%Y-%m-%d)}" "$(date +%H:%M)" "$Q" "$A")"
    n="$(scv_plan_history_add "$t" "$e"; printf x)"
    printf '%s' "${n%x}" > "$f"
    echo "CHOICE_RECORDED: $slug"
    ;;

  *) usage ;;
esac
