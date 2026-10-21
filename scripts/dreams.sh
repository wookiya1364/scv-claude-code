#!/usr/bin/env bash
# dreams.sh — 드림(프롬프트 코치)의 효과부 (v0.69.0+). 규칙 전문: protocols/dreams.md. 계산은 모두 lib/dreams.sh 의 순수부.
#
#   dreams.sh [--auto] [--dir <세션 기록 폴더>]...
#
# 입구: 세션 기록(JSONL — 폴더 바로 아래 *.jsonl 하나가 세션 하나)과 scv/archive/*/ARCHIVED_AT.md 를 읽기만 한다. 기록 폴더는 --dir
# 로 준 것들, 없으면 SCV 가 세션마다 남긴 대화 기록 경로(${SCV_JOURNAL_DIR:-scv/journal}/.help-turns/<세션>/.help-transcript)의
# 폴더들(실사용 보고와 같은 방식). 기록 속 NUL 은 읽을 때 지운다.
# 판정자: 개선점마다 호스트 설정의 판정자 명령(SCV_JUDGE_COMMAND)에 가린 발췌만 보낸다. 답은 사용자 캐시
# (${XDG_CACHE_HOME:-~/.cache}/scv/dreams-judge.v1.tsv — 질문 글의 해시와 답)에 두어 같은 발췌는 다시 묻지 않는다. 판정자가 없거나 ·
# 끄거나(SCV_DREAMS_JUDGE=off) · 실패하거나 · 답이 깨지면 그 칸은 '조언 없음(이유)'이고 보고서는 그대로 나온다.
# 출구: scv/dreams/<YYYYMMDD-HHMMSS>.html 과 scv/dreams/latest.json({date, report, summary, announced}). --auto(훅이 배경으로
# 띄움)이고 사람 질의가 하나라도 있으면 announced=false — 다음 사람 턴의 매 턴 훅이 요약을 한 줄 싣고 true 로 바꾼다. 직접 실행이면
# 요약을 바로 찍고 true.
# 한 번에 하나: scv/dreams/.lock(이 프로세스 번호를 가리키는 심볼릭 링크). 살아 있는 프로세스의 잠금이면 아무것도 하지 않고 끝내고,
# 죽은 프로세스의 잠금이면 치우고 돈다. --auto 는 잠금을 잡은 뒤 scv/dreams/.last 에 오늘 날짜를 적는다(날짜 바뀜 발동의 기준).
# 설정 SCV_DREAMS=off 면 직접 실행은 '꺼져 있음' 한 줄, --auto 는 아무것도 하지 않는다.
# 보고서 · 요약 · 판정자 입력에는 경로 · 메일 · 비밀값 · 세션 id 를 넣지 않는다(발췌는 가림 + 길이 제한, 세션은 순번).
# 종료 코드: 0(보고함 · 꺼짐 · 이미 도는 중 · --auto 의 모든 경우) · 1(직접 실행에서 scv 폴더 · jq 없음) · 2(사용법 오류).
set -u
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/show-real.sh
source "$SCRIPT_DIR/lib/show-real.sh"
# shellcheck source=lib/model-prompting.sh
source "$SCRIPT_DIR/lib/model-prompting.sh"
# shellcheck source=lib/dreams.sh
source "$SCRIPT_DIR/lib/dreams.sh"
# shellcheck source=lib/host-profile.sh
source "$SCRIPT_DIR/lib/host-profile.sh" 2>/dev/null || true
# shellcheck source=lib/settings.sh
source "$SCRIPT_DIR/lib/settings.sh" 2>/dev/null || true

AUTO=0; DIRS_IN=()
usage() {
  [[ -n "${1:-}" ]] && echo "dreams: $1" >&2
  echo "usage: dreams.sh [--auto] [--dir <folder>]..." >&2
  exit 2
}
while [[ $# -gt 0 ]]; do
  case "$1" in
    --auto) AUTO=1; shift ;;
    --dir) [[ $# -ge 2 ]] || usage; DIRS_IN+=("$2"); shift 2 ;;
    --dir=*) DIRS_IN+=("${1#--dir=}"); shift ;;
    -h|--help) awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"; exit 0 ;;
    *) usage "unknown argument" ;;
  esac
done
_say() { (( AUTO )) || printf '%s\n' "$1"; }
_get() { declare -F settings_get >/dev/null 2>&1 || return 0; settings_get "$1" 2>/dev/null || true; }

[[ -d scv ]] || { _say "드림: SCV 프로젝트가 아니다(scv 폴더 없음)"; (( AUTO )) && exit 0; exit 1; }
[[ "$(scv_dreams_switch "$(_get SCV_DREAMS)")" == "on" ]] || { _say "드림: 꺼져 있음 (SCV_DREAMS=off)"; exit 0; }
command -v jq >/dev/null 2>&1 || { _say "드림: jq 가 필요하다"; (( AUTO )) && exit 0; exit 1; }

# ---------------------------------------------------------------- 잠금(한 번에 하나)
OUT="scv/dreams"
mkdir -p "$OUT" 2>/dev/null || { _say "드림: 출력 폴더를 만들지 못했다"; exit 0; }
[[ -f "$OUT/.gitignore" ]] || printf '.lock\n.last\n*.tmp\n' > "$OUT/.gitignore" 2>/dev/null || true
LOCK="$OUT/.lock"
if ! ln -s "$$" "$LOCK" 2>/dev/null; then
  _p="$(readlink "$LOCK" 2>/dev/null || true)"
  if [[ "$_p" =~ ^[0-9]+$ ]] && kill -0 "$_p" 2>/dev/null; then _say "드림: 이미 도는 중 — 끝나면 보고서가 나온다"; exit 0; fi
  [[ "$(readlink "$LOCK" 2>/dev/null || true)" == "$_p" ]] && rm -f "$LOCK" 2>/dev/null
  ln -s "$$" "$LOCK" 2>/dev/null || { _say "드림: 이미 도는 중 — 끝나면 보고서가 나온다"; exit 0; }
fi
trap '[[ "$(readlink "$LOCK" 2>/dev/null)" == "$$" ]] && rm -f "$LOCK"' EXIT
(( AUTO )) && [[ ! -L "$OUT/.last" ]] && { date +%Y%m%d > "$OUT/.last" 2>/dev/null || true; }

# ---------------------------------------------------------------- 입구 1: 세션 기록
DIRS=()
_add_dir() {  # <폴더> — 실제 경로로 바꿔 한 번만 넣는다
  local d x
  d="$(cd "$1" 2>/dev/null && pwd -P)" || return 1
  for x in ${DIRS[@]+"${DIRS[@]}"}; do [[ "$x" == "$d" ]] && return 0; done
  DIRS+=("$d")
}
if [[ ${#DIRS_IN[@]} -gt 0 ]]; then
  for _d in "${DIRS_IN[@]}"; do [[ -d "$_d" ]] && _add_dir "$_d"; done
else
  for _t in "${SCV_JOURNAL_DIR:-scv/journal}"/.help-turns/*/.help-transcript; do
    [[ -f "$_t" && ! -L "$_t" ]] || continue
    _p="$(head -n 1 "$_t" 2>/dev/null)"; _d="${_p%/*}"
    [[ -n "$_p" && "$_d" != "$_p" && -d "$_d" ]] && _add_dir "$_d"
  done
fi
TAGS="${SCV_AUTO_PROMPT_TAGS:-}"; PFX="${SCV_AUTO_PROMPT_PREFIX:-}"; SFX="${SCV_AUTO_PROMPT_SUFFIX:-}"
TURNS=""; REGS=""; NS=0
for _d in ${DIRS[@]+"${DIRS[@]}"}; do
  for _f in "$_d"/*.jsonl; do
    [[ -f "$_f" && ! -L "$_f" && -r "$_f" ]] || continue
    _e="$(tr -d '\000' < "$_f" 2>/dev/null | scv_dreams_entries)"
    [[ -n "$_e" ]] || continue
    NS=$(( NS + 1 ))
    _t="$(scv_dreams_human_turns "f$NS" "$_e" "$TAGS" "$PFX" "$SFX")"; [[ -n "$_t" ]] && TURNS+="$_t"$'\n'
    _r="$(scv_dreams_register_features "f$NS" "$_e" "$TAGS" "$PFX" "$SFX")"; [[ -n "$_r" ]] && REGS+="$_r"$'\n'
  done
done

# ---------------------------------------------------------------- 입구 2: 보관 기록
_arch=""
for _a in scv/archive/*/ARCHIVED_AT.md; do
  [[ -f "$_a" && ! -L "$_a" ]] || continue
  _v="$(sed -n 's/^archived_at:[[:space:]]*//p' "$_a" 2>/dev/null | head -n 1)"
  _s="${_a%/ARCHIVED_AT.md}"; _arch+="${_s##*/}"$'\t'"$_v"$'\n'
done
ARCH="$(scv_dreams_archive_dates "$_arch")"

# ---------------------------------------------------------------- 순수 단계
OFF="$(scv_show_real_offset "$(date +%z 2>/dev/null)")"
NT="$(printf '%s' "$TURNS" | grep -c . || true)"; NR="$(printf '%s' "$REGS" | grep -c . || true)"
UNIT="$(scv_dreams_unit "$NT")"
PERIODS="$(scv_dreams_periods "$TURNS" "$ARCH" "$OFF" "$UNIT")"
DIST="$(scv_dreams_distribution "$TURNS" "$ARCH" "$OFF")"
TIPS="$(scv_dreams_tips "$REGS" "$TURNS" "$DIST")"
EVID="$(scv_dreams_evidence "$TIPS" "$TURNS")"
# 저널과 같은 가림 필터를 한 번 더 거친다(열쇠 = 값 모양의 비밀값). 필터가 없으면 순수부의 가림만으로 간다.
if [[ -n "$EVID" && -f "$SCRIPT_DIR/journal-append.sh" ]]; then
  _ev="$(printf '%s\n' "$EVID" | bash "$SCRIPT_DIR/journal-append.sh" --redact-only 2>/dev/null)" && [[ -n "$_ev" ]] && EVID="$_ev"
fi

# ---------------------------------------------------------------- 판정자(개선점마다, 캐시 먼저)
JUDGE=""
case "${SCV_JUDGE_COMMAND:-}" in
  "") ;;
  /*) JUDGE="$SCV_JUDGE_COMMAND" ;;
  *)  JUDGE="$SCRIPT_DIR/../$SCV_JUDGE_COMMAND" ;;
esac
[[ -n "$JUDGE" && -f "$JUDGE" ]] || JUDGE=""
JSW="$(scv_dreams_switch "$(_get SCV_DREAMS_JUDGE)")"
CACHE="${XDG_CACHE_HOME:-${HOME:-}/.cache}/scv/dreams-judge.v1.tsv"
_jdir="${CACHE%/*}"
ADV=""; _k=0
while IFS= read -r _tip || [[ -n "$_tip" ]]; do
  [[ -n "$_tip" ]] || continue
  _k=$(( _k + 1 ))
  if [[ "$JSW" != "on" ]]; then ADV+="$_k"$'\tnone\t꺼짐(SCV_DREAMS_JUDGE=off)\n'; continue; fi
  if [[ -z "$JUDGE" ]]; then ADV+="$_k"$'\tnone\t판정자 없음\n'; continue; fi
  _ex="$(printf '%s\n' "$EVID" | awk -F '\t' -v k="$_k" '$1 == k { sub(/^[^\t]*\t/, ""); print }')"
  _q="$(scv_dreams_judge_prompt "$_tip" "$_ex")"
  _h="$(scv_show_real_hash "$_q")"
  _hit=""; [[ -f "$CACHE" && -r "$CACHE" ]] && _hit="$(tr -d '\000' < "$CACHE" 2>/dev/null | awk -F '\t' -v h="$_h" '$1 == h { l = $0 } END { if (l != "") print l }')"
  if [[ -n "$_hit" ]]; then ADV+="$_k"$'\tok\t'"${_hit#*$'\t'}"$'\n'; continue; fi
  mkdir -p "$_jdir" 2>/dev/null || true
  _wd="$_jdir"; [[ -d "$_wd" ]] || _wd="${TMPDIR:-/tmp}"
  _rc=0; _out="$(set -o pipefail; cd "$_wd" 2>/dev/null && printf '%s\n' "$_q" | bash "$JUDGE" 2>/dev/null | tr -d '\000')" || _rc=$?
  _ans="$(scv_dreams_judge_parse "$_out")"
  if [[ -z "$_ans" ]]; then
    if (( _rc != 0 )); then ADV+="$_k"$'\tnone\t판정자 실패\n'; else ADV+="$_k"$'\tnone\t판정자 답이 깨짐\n'; fi
    continue
  fi
  # 판정자 답도 같은 가림을 거친다(발췌만 봤지만, 받은 글을 그대로 믿지 않는다).
  _r="$(scv_dreams_mask "${_ans%%$'\t'*}" 80)"; _rest="${_ans#*$'\t'}"
  _a="$(scv_dreams_mask "${_rest%%$'\t'*}" 400)"; _x="$(scv_dreams_mask "${_rest#*$'\t'}" 400)"
  ADV+="$_k"$'\tok\t'"$_r"$'\t'"$_a"$'\t'"$_x"$'\n'
  { printf '%s\t%s\t%s\t%s\n' "$_h" "$_r" "$_a" "$_x" >> "$CACHE"; } 2>/dev/null || true
done <<< "$TIPS"

# ---------------------------------------------------------------- 출구: 보고서 · 요약
STAMP="$(date +%Y%m%d-%H%M%S)"; NAME="$STAMP.html"; _n=1
while [[ -e "$OUT/$NAME" ]]; do _n=$(( _n + 1 )); NAME="$STAMP-$_n.html"; done
REL="$OUT/$NAME"
SUMMARY="$(scv_dreams_render_summary "$PERIODS" "$TIPS" "$REL" "$NT")"
# 배경 드림이고 셀 사람 질의가 있을 때만 '안 알림' — 기록이 없는 프로젝트에서 빈 요약이 다음 턴에 끼지 않게.
_ann=true; (( AUTO && NT > 0 )) && _ann=false
if ! scv_dreams_render_html "$PERIODS" "$DIST" "$TIPS" "$EVID" "$ADV" "$(date '+%Y-%m-%d %H:%M')" "$UNIT" "$NT" "$NS" "$NR" > "$REL.tmp" 2>/dev/null \
   || ! mv -f "$REL.tmp" "$REL" 2>/dev/null; then
  rm -f "$REL.tmp" 2>/dev/null; _say "드림: 보고서를 쓰지 못했다"; exit 0
fi
jq -cn --arg d "$(date +%Y%m%d)" --arg r "$REL" --arg s "$SUMMARY" --argjson a "$_ann" \
  '{date: $d, report: $r, summary: $s, announced: $a}' > "$OUT/latest.json.tmp" 2>/dev/null \
  && mv -f "$OUT/latest.json.tmp" "$OUT/latest.json" 2>/dev/null
_say "$SUMMARY"
exit 0
