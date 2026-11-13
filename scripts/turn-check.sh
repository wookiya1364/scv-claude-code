#!/usr/bin/env bash
# turn-check.sh — 턴 끝 계획 기록 검사의 어댑터: 사진 찍기 · 영수증 · 판정 · 선택 답 기록.
# 무언가를 고친 턴은 계획에 기록이 남아야 끝난다(scv_settings.json SCV_TURN_PLAN_CHECK=on, 기본 켬).
#
#   turn-check.sh start   --dir <턴 폴더> | --session <세션>            (표준 입력: 이번 턴 사용자 원문)
#   turn-check.sh touch   --dir <턴 폴더> [--kind write|shell|read] <경로>…  (도구 앞: 쓴 파일 · 셸 앞 모습을 적음)
#   turn-check.sh receipt --dir <턴 폴더>            (표준 입력: 도구가 돌릴 명령 글)
#   turn-check.sh end     --dir <턴 폴더> [--transcript <대화 기록 파일>]   → TURN_PLAN: pass|block|pass-unrecorded|off · TURN_PLAN_REASON: …
#   turn-check.sh choice  --question <질문> --answer <답>
#   turn-check.sh step    --dir <턴 폴더> --tool <도구 이름>   (도구 앞: 단계 보고 도구면 표시)
#   turn-check.sh info                               → TURN_ID: … · TURN_REQ: … (plan-link 이 읽음)
#   turn-check.sh close   --dir <턴 폴더> --kind startup|resume|clear|compact   (세션 시작 훅: 새로 열기 · 다시 열기면 앞 턴을 끝난 것으로 표시)
#
# 사람의 말이 왔는데 앞 턴이 아직 끝나지 않았으면(끝 표시 없음) start 는 새로 시작하지 않고 그 턴을 이어 간다 — 일하는 도중에
# 온 말과 사용자가 멈춘 턴 뒤의 말이 그렇다. 끝 표시는 end 가 통과를 낼 때와 close 가 남긴다.
#
# 호스트 설정 경로(SCV_GUARD_EXEMPT — 래퍼가 도구 앞 훅에 넘김)는 바뀐 파일에서 뺀다.
# 작업 공간 = 이 프로젝트 + SCV_WORKSPACE_REPOS(절대 경로를 : 로 이음) + 그 턴에 쓰기 도구 · 셸 명령이 건드린 저장소.
# 세는 파일 = 바뀐 파일 중 이 세션이 쓴 것(mine): 쓰기 도구에 적힌 파일 + 셸 명령 앞과 다음 도구 앞(또는 턴 끝) 모습의 차이.
# 읽기 도구는 세지 않는다. 계획 20261109-wookiya1364-turn-check-own-files.
# SCV 폴더(scv/)나 그 바로 아래 폴더를 다른 저장소로 연결(symlink)해 둔 프로젝트는, 연결이 가리키는 실제 폴더 안의 파일도 '일'로 세지 않는다(0.88.2+).
# git 저장소는 바뀐 파일 해시 + HEAD, git 아닌 폴더는 파일 목록 · 수정 시각 · 크기로 찍는다.
# 셸 명령의 비교 구간에 다른 세션이 같은 폴더를 고치면 그 파일은 섞인다(계획의 한계). 어떤 실패도 세션을 막지 않는다 — 판단할 수 없으면 pass.
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
usage() { sed -n '5,12p' "${BASH_SOURCE[0]}" | sed 's/^#   //' >&2; exit 2; }

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

# @effect record_roots
# 이유: SCV 폴더와 그 바로 아래 폴더 중 연결(symlink)인 것이 가리키는 실제 경로를 읽는다 — 기록 폴더를 다른 저장소에 둔 프로젝트용
record_roots() {
  local base d r
  base="$(dirname "$PROMOTE")"
  for d in "$base" "$base"/*; do
    [[ -L "$d" && -d "$d" ]] || continue
    r="$(cd "$d" 2>/dev/null && pwd -P)" && [[ -n "$r" ]] && printf '%s\n' "$r"
  done
  return 0
}

# @effect head_of
# 이유: git 저장소의 HEAD 를 읽는다
head_of() { git -C "$1" rev-parse HEAD 2>/dev/null || true; }

# @pure
# 역할: 폴더 경로를 사진 파일 이름으로 바꾼다 — 슬래시 · 빈칸을 밑줄로
# 종류: 변환
# 예: "/Users/a/b c" → "_Users_a_b_c"
key_of() {
  # / 와 빈칸은 한 바이트 글자다 — 바이트 단위로 바꿔도 같은 글이 나온다.
  # 옛 셸은 바꿀 곳이 많은 긴 글을 통째로 바꾸면 길이의 제곱으로 느려서, 128바이트씩 잘라 바꾼다(새 셸은 4096바이트씩).
  local LC_ALL=C s="$1" c out="" i=0 n step=128
  [[ ${BASH_VERSINFO[0]} -ge 4 ]] && step=4096
  n=${#s}
  while [[ $i -lt $n ]]; do
    c="${s:i:step}"; c="${c//\//_}"; out+="${c// /_}"; i=$((i + step))
  done
  printf '%s' "$out"
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
# 이유: 진행 중 계획 파일들과, 이번 턴에 보관한 계획 파일들을 읽는다
plan_texts() {
  local f
  for f in "$PROMOTE"/*/PLAN.md; do [[ -f "$f" ]] && cat "$f" && printf '\n'; done
  # 이번 턴에 보관한 계획의 글도 읽는다(0.91.2+) — 턴 도중 보관하면 그 턴에 남긴 기록이 진행 중 자리에서 사라져
  # "기록 없음"으로 막혔다. 보관 기록 파일이 턴 시작 표시보다 새것인 계획만 본다(예전에 보관된 것은 읽지 않는다).
  [[ -n "${S:-}" && -f "$S/id" ]] || return 0
  for f in "$ARCHIVE"/*/ARCHIVED_AT.md; do
    [[ -f "$f" && "$f" -nt "$S/id" && -f "${f%/*}/PLAN.md" ]] && cat "${f%/*}/PLAN.md" && printf '\n'
  done
  return 0
}

# @effect active_plans
# 이유: 계획 파일들을 읽어 진행 중(in_progress · testing) 계획 이름을 최근에 고친 것부터 낸다
active_plans() {
  local f st
  for f in $(ls -t "$PROMOTE"/*/PLAN.md 2>/dev/null); do
    st="$(scv_plan_fm_get "$(cat "$f")" status)"
    [[ "$st" == in_progress || "$st" == testing ]] && basename "$(dirname "$f")"
  done
}

# @effect step_call_lines
# 이유: 대화 기록 파일의 끝 8 ~ 9MB 에서 단계 보고 도구의 이름과 도구 호출 표시가 함께 든 줄의 끝 쪽(200줄)을 읽는다
# 끝 쪽만 읽는 것은 이 길이 대시보드를 켠 세션에서 턴마다 돌기 때문이다. 맥에서 30MB 를 통째로 훑으면 0.28초,
# tail -c 로 끝을 자르면 0.58초, dd 로 끝 16MB 를 건너뛰어 읽으면 0.16초였다(2026-11-13 실측) — 그래서 dd 로 건너뛴다.
# 이번 턴의 호출은 파일의 끝 쪽에 있다(이 저장소의 긴 턴이 1.5MB 안팎). 잘린 첫 줄은 세는 함수가 버린다.
step_call_lines() {
  local f="$1" sz skip=0
  sz="$(wc -c < "$f" 2>/dev/null | tr -d '[:space:]')"
  [[ "$sz" =~ ^[0-9]+$ ]] || return 0
  (( sz > 8388608 )) && skip=$(( sz / 1048576 - 8 ))
  dd if="$f" bs=1048576 skip="$skip" 2>/dev/null | LC_ALL=C grep -F -- "$2" | LC_ALL=C grep -F -- 'tool_use' | tail -n 200
}

# @effect turn_started_at
# 이유: 턴 번호 파일의 고친 시각을 읽어 UTC 글(2026-01-01T00:00:00 꼴)로 낸다(맥 BSD · 리눅스 GNU 둘 다) — 읽지 못하면 빈 글
turn_started_at() {
  local m
  if m="$(stat -f '%m' "$S/id" 2>/dev/null)" && [[ "$m" =~ ^[0-9]+$ ]]; then date -u -r "$m" +%Y-%m-%dT%H:%M:%S 2>/dev/null
  elif m="$(stat -c '%Y' "$S/id" 2>/dev/null)" && [[ "$m" =~ ^[0-9]+$ ]]; then date -u -d "@$m" +%Y-%m-%dT%H:%M:%S 2>/dev/null
  fi
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

# @effect real_path
# 이유: 파일 시스템을 읽어 경로의 실제 폴더(링크 풂)를 찾는다 — 아직 없는 파일은 폴더만 풀고, 폴더도 없으면 그대로
real_path() {
  local p="$1" d
  [[ "$p" == /* ]] || p="$PROJECT/$p"
  d="$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)" || { printf '%s' "$p"; return 0; }
  printf '%s/%s' "$d" "$(basename "$p")"
}

# @effect pend_snap
# 이유: 셸 명령이 돌기 전 저장소 모습을 '대기 사진'으로 찍어 상태 폴더에 쓴다 — 다음 도구 앞이나 턴 끝에 정산한다
pend_snap() {
  local root="$1" k; k="$(key_of "$root")"
  snap_root "$root" > "$S/pend.$k" 2>/dev/null || : > "$S/pend.$k"
  head_of "$root" > "$S/phead.$k"
  grep -qxF "$root" "$S/pend-roots" 2>/dev/null || printf '%s\n' "$root" >> "$S/pend-roots"
}

# @effect settle
# 이유: 대기 사진과 지금 모습을 견줘 앞 셸 명령이 바꾼 파일을 '내 파일'(mine)에 적고 대기 사진을 지운다
settle() {
  local root k d h0 h1
  [[ -s "$S/pend-roots" ]] || return 0
  while IFS= read -r root; do
    [[ -n "$root" ]] || continue
    k="$(key_of "$root")"
    if ! grep -q '^@too-many' "$S/pend.$k" 2>/dev/null; then
      d="$(scv_tc_diff "$(cat "$S/pend.$k" 2>/dev/null)" "$(snap_root "$root")")"
      h0="$(cat "$S/phead.$k" 2>/dev/null)"; h1="$(head_of "$root")"
      [[ -n "$h0" && "$h0" != "$h1" ]] && d="$d"$'\n'"$(git -C "$root" diff --name-only "$h0" "$h1" 2>/dev/null)"
      d="$(scv_tc_abs_paths "$root" "$d")"
      [[ -n "$d" ]] && printf '%s\n' "$d" >> "$S/mine"
    fi
    rm -f "$S/pend.$k" "$S/phead.$k"
  done < "$S/pend-roots"
  rm -f "$S/pend-roots"
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
DIR=""; SID=""; Q=""; A=""; TOOL=""; KIND="write"; TRANSCRIPT=""; PATHS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) DIR="${2:-}"; shift 2 ;;
    --session) SID="${2:-}"; shift 2 ;;
    --question) Q="${2:-}"; shift 2 ;;
    --answer) A="${2:-}"; shift 2 ;;
    --tool) TOOL="${2:-}"; shift 2 ;;
    --kind) KIND="${2:-write}"; shift 2 ;;
    --transcript) TRANSCRIPT="${2:-}"; shift 2 ;;
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
    # 원문은 저장 전에 비밀 가리개(journal-append.sh --redact-only)를 거친다 — 계획 줄에도 이 글이 붙는다.
    # 첨부 파일의 경로도 지운다(0.92.2+) — 파일을 붙여 보낸 요청은 원문에 내 컴퓨터의 경로가 들어 있다.
    REQ="$(head -c 4000 2>/dev/null | bash "$SCRIPT_DIR/journal-append.sh" --redact-only 2>/dev/null || true)"
    REQ="$(scv_tc_strip_attach "$REQ")"
    # 앞 턴이 아직 끝나지 않았으면(턴 끝이 통과를 낸 적이 없고 세션을 새로 열거나 다시 연 것도 아니면) 이 말은 그 턴의
    # 도중에 온 것이다 — 번호 · 사진 · 영수증 · 내가 쓴 파일 · 계획 기준선 · 막힌 횟수를 그대로 두고 요청 글만 잇는다.
    # 새로 시작하면 그 앞의 기록이 '앞 턴 것'이 되고, 그 턴에 보관한 계획은 시작 표시보다 옛것이 되어 읽히지 않는다.
    HAS_ID=0; [[ -s "$S/id" ]] && HAS_ID=1
    HAS_END=0; [[ -e "$S/ended" ]] && HAS_END=1
    if [[ "$(scv_tc_start_mode "$HAS_ID" "$HAS_END")" == continue ]]; then
      CUR="$(cat "$S/req" 2>/dev/null; printf x)"; CUR="${CUR%x}"
      printf '%s' "$(scv_tc_req_join "$CUR" "$REQ" 4000)" > "$S/req"
      mkdir -p "$JDIR" 2>/dev/null && printf '%s\n' "$(cd "$DIR" && pwd -P)" > "$JDIR/.turn-latest" 2>/dev/null
      exit 0
    fi
    rm -f "$S"/snap.* "$S"/head.* "$S"/pend.* "$S"/phead.* "$S/pend-roots" "$S/mine" "$S/roots" "$S/receipts" "$S/blocks" "$S/exempt" "$S/steps" "$S/ended" 2>/dev/null
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
    # 앞 셸 명령이 바꾼 파일부터 정산한다 — 읽기 도구여도 정산은 한다(셸 명령이 끝난 뒤의 첫 도구).
    settle
    case "$KIND" in
      write)
        # 쓰기 도구: 적힌 파일만 '내 파일'. 저장소는 쓰기 전에 시작 사진을 찍는다.
        for p in ${PATHS[@]+"${PATHS[@]}"}; do
          a="$(real_path "$p")"; r="$(root_of "$a")"
          [[ -z "$r" && "$a" == "$PROJECT"/* ]] && r="$PROJECT"
          [[ -n "$r" ]] && take_snap "$r"
          printf '%s\n' "$a" >> "$S/mine"
        done ;;
      shell)
        # 셸 명령: 이 프로젝트 · 이미 찍은 저장소(작업 공간 포함) · cd · -C 대상 저장소를 대기 사진으로 찍는다
        # — 명령 글에 경로가 안 보여도 작업 공간 저장소의 변경을 잡는다.
        R="$PROJECT"$'\n'
        while IFS= read -r r; do [[ -n "$r" && $'\n'"$R" != *$'\n'"$r"$'\n'* ]] && R="$R$r"$'\n'; done < "$S/roots"
        for p in ${PATHS[@]+"${PATHS[@]}"}; do
          r="$(root_of "$p")"; [[ -n "$r" && $'\n'"$R" != *$'\n'"$r"$'\n'* ]] && R="$R$r"$'\n'
        done
        while IFS= read -r r; do [[ -n "$r" ]] && { take_snap "$r"; pend_snap "$r"; }; done <<< "$R" ;;
      *) : ;;  # 읽기 · 찾기: 폴더도 파일도 세지 않는다
    esac
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

  close)
    # 세션을 새로 열거나 다시 열었다 — 앞 프로세스의 턴은 끝났다. 번호가 있을 때만 끝 표시를 남긴다.
    enabled || exit 0
    [[ "$(scv_tc_session_closes "$KIND")" == 1 ]] || exit 0
    state_dir "$DIR" || exit 0
    [[ -f "$S/id" ]] && : > "$S/ended" 2>/dev/null
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
    settle
    MINE="$(cat "$S/mine" 2>/dev/null)"
    RREC="$(record_roots)"
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
      # 호스트 설정 경로와, 다른 저장소로 연결된 기록 폴더 안의 것을 뺀다.
      xg="$(cat "$S/host-exempt" 2>/dev/null)"; rg="$(scv_tc_record_globs "$root" "$RREC")"
      [[ -n "$rg" ]] && xg="${xg:+$xg:}$rg"
      d="$(scv_tc_filter "$d" "$xg")"
      # 이 세션이 쓴 파일만 — 다른 세션이 같은 폴더에서 고친 파일은 뺀다.
      d="$(scv_tc_mine_only "$(scv_tc_abs_paths "$root" "$d")" "$MINE")"
      d="$(printf '%s' "$d" | sed "s#^${root%/}/##")"
      [[ -n "$d" ]] || continue
      pre=""; [[ "$root" == "$PROJECT" ]] || pre="$(basename "$root"):"
      while IFS= read -r f; do [[ -n "$f" ]] && CHANGED="$CHANGED$pre$f"$'\n'; done <<< "$d"
    done < "$S/roots"
    CHANGED="$(printf '%s' "$CHANGED" | LC_ALL=C sort -u | sed '/^$/d')"
    printf '%s\n' "$CHANGED" > "$S/changed" 2>/dev/null || true   # 재는 검사(pure-bench.sh turn-end)가 읽는다
    NCH=0; [[ -n "$CHANGED" ]] && NCH="$(printf '%s\n' "$CHANGED" | wc -l | tr -d ' ')"
    NEWL="$(scv_tc_new_lines "$(cat "$S/plans" 2>/dev/null)" "$(plan_texts | { t="$(cat)"; scv_tc_plan_lines "$t"; })")"
    NST="$(scv_tc_struct_count "$NEWL")"; NRQ="$(scv_tc_req_count "$NEWL" "$ID")"
    NRC="$(grep -c . "$S/receipts" 2>/dev/null || true)"; NRC="${NRC:-0}"
    EX=no; grep -q "(요청 $ID)" "$S/exempt" 2>/dev/null && EX=yes
    ACT="$(active_plans)"; NPL=0; [[ -n "$ACT" ]] && NPL="$(printf '%s\n' "$ACT" | wc -l | tr -d ' ')"
    BL="$(cat "$S/blocks" 2>/dev/null || echo 0)"
    NEED=no; (( NPL > 0 )) && NEED="$(step_needed)"
    NSTEP="$(grep -c . "$S/steps" 2>/dev/null || true)"; NSTEP="${NSTEP:-0}"
    # 단계 보고 도구를 앱이 직접 처리하는 호스트에서는 도구 앞 훅이 돌지 않아 표시가 0 이다(0.93.2). 막을 참일 때만
    # 대화 기록에서 이번 턴의 그 도구 호출을 센다 — 표시가 있거나 보고가 필요 없는 턴은 대화 기록을 열지 않는다.
    # 이번 턴이 시작된 시각은 턴 번호 파일이 만들어진 시각이다 — 턴을 시작할 때 따로 적지 않는다(시작 길에 프로그램 호출을
    # 하나 더하면 사진 0.3초 한도에 닿았다). 도중에 온 말로 이어지는 턴은 그 파일을 건드리지 않으므로 처음 시각이 남는다.
    if [[ "$NEED" == yes && "$NSTEP" == 0 && -n "$TRANSCRIPT" && -f "$TRANSCRIPT" ]]; then
      NSTEP="$(scv_tc_step_calls "$(step_call_lines "$TRANSCRIPT" "$SCV_STEP_TOOL")" "$SCV_STEP_TOOL" "$(turn_started_at)")"
    fi
    ORPH="$(orphan_return)"
    V="$(scv_tc_judge "$NCH" "$NRC" "$NST" "$NRQ" "$EX" "$NPL" "$BL" "$NEED" "$NSTEP" "$ORPH")"
    # 통과를 내면 이 턴은 끝난 것이다 — 다음에 오는 사람의 말은 새 턴으로 시작한다. 막힘이면 턴이 이어진다.
    case "$V" in pass|pass-unrecorded) : > "$S/ended" 2>/dev/null || true ;; esac
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
    # 재는 검사의 물음에 "이대로"로 답했으면 받아들인 값으로 적는다(계획이 없어도).
    # 그 물음일 때만 띄운다 — 선택 답마다 띄우면 답 17개에 1초가 더 든다(2026-11-11 시험 T12 가 잡음).
    [[ "$Q" != *"[재는 검사]"* ]] || bash "$SCRIPT_DIR/pure-bench.sh" accept --question "$Q" --answer "$A" >/dev/null 2>&1 || true
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
