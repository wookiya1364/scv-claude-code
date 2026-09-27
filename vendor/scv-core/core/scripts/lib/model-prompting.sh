#!/usr/bin/env bash
# lib/model-prompting.sh — 모델별 프롬프팅의 순수부. 문자열을 받아 문자열을 낸다.
#
# help 가 "지금 모델의 공식 프롬프팅 가이드 원문을 읽어야 하나" 를 정하는 데 쓴다. 코어는 모델
# 이름을 모른다 — 래퍼가 싣는 색인(INDEX.tsv)을 데이터로만 읽는다. 원문 파일과 색인은 래퍼에 있고,
# 호스트 프로필의 SCV_PROMPTING_GUIDES 가 그 폴더를 알려 준다.
#
# 색인 형식 (탭 구분, # 로 시작하는 줄과 빈 줄은 무시):
#   <모델 id>  <키>  <파일>  <원본 주소>  <가져온 날짜 YYYY-MM-DD>
#   *          <키>  <파일>  <원본 주소>  <날짜>        — 모든 모델에 붙는 공통 원문(있으면)
#   @refresh   <갱신 명령의 스크립트 경로(색인 폴더 기준)>
#
# 읽음 기록 (.help-guide, 한 줄): <규약 지문>\x1f<정규화 모델 id>
#   규약 지문(help 표식의 nonce)은 컨텍스트에 묶인 값이다 — 세션 전환 · 압축 · /clear · 재개 · 종료 훅의
#   흐려짐 판정에서 비워지고, 규약을 다시 읽을 때(mark) 새로 생긴다. 그래서 "같은 지문" = "같은 컨텍스트".
#
# 계약: core/contracts/purity.md · 규약: protocols/help/prompt-refine.md

_SCV_MP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
# shellcheck source=metrics.sh
source "$_SCV_MP_LIB_DIR/metrics.sh"   # scv_mx_civil_to_minutes — 날짜 산술을 한 곳에서

# @pure
# <원시 모델 id> → 정규화 id: 앞뒤 공백 제거 · 소문자 · 끝의 "[…]" 표기(예: 컨텍스트 길이) 제거.
# bash 3.2 에는 ${v,,} 가 없어 글자 표로 바꾼다. 글자 범위([A-Z])는 쓰지 않는다 — bash 3.2 는 UTF-8
# 지역 설정에서 [A-Z] 가 소문자까지 맞춰 id 를 망가뜨린다(리뷰가 재현: 소문자가 통째로 빠짐). 대문자 26자를 그대로 적는다.
scv_mp_normalize_id() {
  local s="${1:-}" up="ABCDEFGHIJKLMNOPQRSTUVWXYZ" lo="abcdefghijklmnopqrstuvwxyz" out="" c i head
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  s="${s%%\[*}"
  s="${s%"${s##*[![:space:]]}"}"
  for (( i = 0; i < ${#s}; i++ )); do
    c="${s:i:1}"
    case "$up" in
      *"$c"*) head="${up%%"$c"*}"; out+="${lo:${#head}:1}" ;;
      *) out+="$c" ;;
    esac
  done
  printf '%s' "$out"
}

# @pure
# <정규화 id> <색인 텍스트> → "<키>\t<파일>\t<가져온 날짜>" (정확히 일치하는 첫 행) 또는 빈 값.
# 접두어로 맞추지 않는다 — 앞이 같은 id(예: "x-5" 와 "x-5-5")가 있기 때문이다.
scv_mp_lookup() {
  local id="${1:-}" index="${2:-}" mid key file src fetched
  [[ -n "$id" ]] || return 0
  while IFS=$'\t' read -r mid key file src fetched || [[ -n "$mid" ]]; do
    [[ -z "$mid" || "$mid" == \#* || "$mid" == "*" || "$mid" == @* ]] && continue
    if [[ "$(scv_mp_normalize_id "$mid")" == "$id" && -n "$key" && -n "$file" ]]; then
      printf '%s\t%s\t%s' "$key" "$file" "$fetched"
      return 0
    fi
  done <<< "$index"
  return 0
}

# @pure
# <색인 텍스트> → 공통 원문 "<파일>\t<가져온 날짜>" 또는 빈 값.
scv_mp_common() {
  local index="${1:-}" mid key file src fetched
  while IFS=$'\t' read -r mid key file src fetched || [[ -n "$mid" ]]; do
    if [[ "$mid" == "*" && -n "$file" ]]; then printf '%s\t%s' "$file" "$fetched"; return 0; fi
  done <<< "$index"
  return 0
}

# @pure
# <색인 텍스트> <이름> → "@<이름>" 행의 값 (예: refresh → 갱신 스크립트 경로) 또는 빈 값.
scv_mp_meta() {
  local index="${1:-}" name="${2:-}" mid val rest
  [[ -n "$name" ]] || return 0
  while IFS=$'\t' read -r mid val rest || [[ -n "$mid" ]]; do
    if [[ "$mid" == "@$name" && -n "$val" ]]; then printf '%s' "$val"; return 0; fi
  done <<< "$index"
  return 0
}

# @pure
# <읽음 기록 한 줄> → "<지문>\x1f<모델 id>" (깨졌으면 빈 필드).
scv_mp_read_parse() {
  local s="${1:-}" us=$'\x1f' nonce="" model=""
  if [[ "$s" == *"$us"* ]]; then nonce="${s%%"$us"*}"; model="${s#*"$us"}"; model="${model%%"$us"*}"; fi
  nonce="${nonce//[[:space:]]/}"; model="${model//[[:space:]]/}"
  printf '%s%s%s' "$nonce" "$us" "$model"
}

# @pure
# <색인에 행이 있나 0|1> <읽음 기록(파싱됨)> <지금 규약 지문> <지금 정규화 id> → load | loaded | none
#   none   : 행이 없다(모름 · 색인에 없음 · 끔).
#   loaded : 이 컨텍스트(같은, 비어 있지 않은 지문)에서 같은 모델 원문을 이미 읽었다.
#   load   : 그 밖 — 처음, 모델이 바뀜, 컨텍스트가 바뀜(지문이 다르거나 비었음), 기록이 지워짐·깨짐.
scv_mp_decision() {
  local have="${1:-0}" rec="${2:-}" nonce="${3:-}" id="${4:-}" us=$'\x1f' rnonce rmodel
  if [[ "$have" != "1" || -z "$id" ]]; then printf 'none'; return 0; fi
  rnonce="${rec%%"$us"*}"; rmodel="${rec#*"$us"}"
  if [[ -n "$rnonce" && "$rnonce" == "$nonce" && -n "$rmodel" && "$rmodel" == "$id" ]]; then printf 'loaded'; else printf 'load'; fi
}

# @pure
# <읽음 기록 한 줄> <옛 지문> <새 지문> → 새 지문으로 바꾼 기록 한 줄, 또는 빈 값(바꾸지 않음).
# 규약을 다시 읽어 지문이 새로 생길 때(help-state.sh mark) 부른다: 같은 턴에 — 같은 컨텍스트에서 — 원문을 먼저
# 읽고 표시했다면 기록의 지문은 옛 지문(빈 값일 수 있다)과 같다. 그 기록만 새 지문으로 옮긴다.
scv_mp_restamp() {
  local line="${1:-}" old="${2:-}" new="${3:-}" us=$'\x1f' rec rnonce rmodel
  [[ -n "$new" && "$line" == *"$us"* ]] || return 0
  rec="$(scv_mp_read_parse "$line")"; rnonce="${rec%%"$us"*}"; rmodel="${rec#*"$us"}"
  [[ -n "$rmodel" && "$rnonce" == "$old" ]] || return 0
  printf '%s%s%s' "$new" "$us" "$rmodel"
}

# @pure
# <이름> → 색인 폴더 안의 평범한 파일 이름이면 그대로, 아니면 빈 값. 경로 구분자 · 점으로 시작 · ".." 금지 —
# 색인은 래퍼가 싣는 데이터지만, 그 값을 모델에게 "읽으라" 는 경로와 명령으로 내보내므로 폴더 밖을 가리키지 못하게 한다.
scv_mp_safe_name() {
  local n="${1:-}" ok="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-" c i
  [[ -n "$n" && "$n" != .* && "$n" != *..* ]] || return 0
  for (( i = 0; i < ${#n}; i++ )); do
    c="${n:i:1}"
    case "$ok" in *"$c"*) ;; *) return 0 ;; esac
  done
  printf '%s' "$n"
}

# @pure
# <가져온 날짜 YYYY-MM-DD> <오늘 YYYY-MM-DD> → 경과 일수(정수) 또는 빈 값(형식 오류).
scv_mp_age_days() {
  local a b
  a="$(scv_mx_civil_to_minutes "${1:-} 00:00")"; b="$(scv_mx_civil_to_minutes "${2:-} 00:00")"
  [[ -n "$a" && -n "$b" ]] || return 0
  (( b >= a )) || { printf '0'; return 0; }
  printf '%s' $(( (b - a) / 1440 ))
}

# @pure
# <결정> <키> <모델 원문 경로> <공통 원문 경로> <경과 일수> <기준 일수> <갱신 스크립트 경로> <빠진 파일>
#   → help 출력 줄들:
#   GUIDE: none | GUIDE: loaded <키> | GUIDE: load <키>
#   GUIDE_FILE: <경로>            (load 일 때, 모델 원문 다음 공통 원문)
#   GUIDE_STALE: <n> days old (limit <기준>) — refresh: bash "<스크립트>"   (경과가 기준을 넘을 때)
#   GUIDE_MISSING: <파일>        (색인엔 있는데 디스크에 없을 때 — 결정은 none)
scv_mp_guide_lines() {
  local dec="${1:-none}" key="${2:-}" mfile="${3:-}" cfile="${4:-}" age="${5:-}" max="${6:-90}" refresh="${7:-}" missing="${8:-}"
  [[ "$max" =~ ^[0-9]+$ ]] || max=90
  if [[ -n "$missing" ]]; then
    printf 'GUIDE: none\nGUIDE_MISSING: %s\n' "$missing"
    return 0
  fi
  case "$dec" in
    load)
      printf 'GUIDE: load %s\n' "$key"
      [[ -n "$mfile" ]] && printf 'GUIDE_FILE: %s\n' "$mfile"
      [[ -n "$cfile" ]] && printf 'GUIDE_FILE: %s\n' "$cfile" ;;
    loaded) printf 'GUIDE: loaded %s\n' "$key" ;;
    *) printf 'GUIDE: none\n'; return 0 ;;
  esac
  if [[ "$age" =~ ^[0-9]+$ ]] && (( age > max )); then
    if [[ -n "$refresh" ]]; then printf 'GUIDE_STALE: %s days old (limit %s) — refresh: bash "%s"\n' "$age" "$max" "$refresh"
    else printf 'GUIDE_STALE: %s days old (limit %s)\n' "$age" "$max"; fi
  fi
  return 0
}

# @pure
# <스위치 값> → on|off (기본 on; "off" 만 끈다, 대소문자·따옴표·공백 무시).
scv_mp_switch() {
  local v
  v="$(scv_mp_normalize_id "${1:-}")"; v="${v//\"/}"; v="${v//\'/}"; v="${v//[[:space:]]/}"
  if [[ "$v" == "off" ]]; then printf 'off'; else printf 'on'; fi
}

# @pure
# <코어 루트> <프로필 값> → 색인 폴더 경로. 절대 경로면 그대로, 상대면 코어 루트 기준. 빈 값이면 빈 값.
scv_mp_guides_dir() {
  local root="${1:-}" v="${2:-}"
  [[ -n "$v" ]] || return 0
  case "$v" in
    /*) printf '%s' "$v" ;;
    *) printf '%s/%s' "${root%/}" "$v" ;;
  esac
}

# @pure
# <답한 모델 id(대화 기록에서)> → 저널 화자 이름: "assistant" 또는 "assistant · <id>".
# id 는 글자·숫자·. _ : - [ ] 만 남긴다 — 제목 줄에 들어가는 값이라 다른 글자는 버린다. 64자까지.
scv_mp_speaker_label() {
  local raw="${1:-}" out="" c i
  for (( i = 0; i < ${#raw} && ${#out} < 64; i++ )); do
    c="${raw:i:1}"
    case "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:[]-" in *"$c"*) out+="$c" ;; esac
  done
  if [[ -n "$out" ]]; then printf 'assistant · %s' "$out"; else printf 'assistant'; fi
}

# ---------------------------------------------------------------- 결과로 판정 (v0.60.0+)
# help 가 원문을 읽으라고 한 턴에 읽음 표시가 없거나, 다시 쓴 요청을 기록했는데 답에 인용이 없으면
# 멈춤 훅이 다음 턴 경고를 예약한다. 판정은 여기, 읽고 쓰기는 model-prompting.sh stop.
# 이번 턴 기록 (.help-guide-turn, 한 줄): <지문>\x1f<정규화 모델 id>\x1f<결정 load|loaded>\x1f<키>

# @pure
# <턴 기록 한 줄> → "<지문>\x1f<모델>\x1f<결정>\x1f<키>" (결정이 load|loaded 가 아니면 빈 값).
scv_mp_turn_parse() {
  local s="${1:-}" us=$'\x1f' nonce model dec key rest
  [[ "$s" == *"$us"*"$us"* ]] || return 0
  nonce="${s%%"$us"*}"; rest="${s#*"$us"}"
  model="${rest%%"$us"*}"; rest="${rest#*"$us"}"
  dec="${rest%%"$us"*}"; key=""; [[ "$rest" == *"$us"* ]] && key="${rest#*"$us"}"
  key="${key%%"$us"*}"
  case "$dec" in load|loaded) ;; *) return 0 ;; esac
  [[ -n "$model" ]] || return 0
  printf '%s%s%s%s%s%s%s' "$nonce" "$us" "$model" "$us" "$dec" "$us" "$key"
}

# @pure
# <턴 기록(파싱됨)> <읽음 기록(파싱됨)> <지금 지문> → 1(이 컨텍스트에서 그 모델을 읽음) | 0.
# 읽음 기록의 지문이 턴 기록의 지문 또는 지금 지문과 같아야 한다 — 멈춤 훅의 드리프트 재설정이 지금 지문을
# 먼저 비웠을 수 있고, 규약 재표시가 지문을 옮겼을 수 있어서 둘 다 본다. 빈 지문은 증거가 아니다.
scv_mp_was_read() {
  local turn="${1:-}" rec="${2:-}" cur="${3:-}" us=$'\x1f' tnonce tmodel rnonce rmodel
  tnonce="${turn%%"$us"*}"; tmodel="${turn#*"$us"}"; tmodel="${tmodel%%"$us"*}"
  rnonce="${rec%%"$us"*}"; rmodel="${rec#*"$us"}"; rmodel="${rmodel%%"$us"*}"
  if [[ -n "$rnonce" && -n "$rmodel" && "$rmodel" == "$tmodel" ]] \
     && { [[ "$rnonce" == "$tnonce" ]] || [[ "$rnonce" == "$cur" ]]; }; then
    printf '1'
  else
    printf '0'
  fi
}

# @pure
# <이번 턴 대화 블록 텍스트> → 1(다시 쓴 요청 단락이 있다) | 0. 라벨은 영문 또는 한국어.
scv_mp_rewrite_recorded() {
  local text="${1:-}" line
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      "**Rewritten request**:"*|"**다시 쓴 요청**:"*) printf '1'; return 0 ;;
    esac
  done <<< "$text"
  printf '0'
}

# @pure
# <턴 기록 한 줄> <옛 지문> <새 지문> → 지문만 바꾼 줄 (옛 지문이 맞지 않거나 형식이 아니면 빈 값).
# help-state mark 가 같은 턴에 규약을 다시 읽어 지문을 바꿀 때, 이번 턴 기록도 새 지문으로 옮긴다.
scv_mp_turn_restamp() {
  local line="${1:-}" old="${2:-}" new="${3:-}" us=$'\x1f' t tn
  [[ -n "$new" ]] || return 0
  t="$(scv_mp_turn_parse "$line")"; [[ -n "$t" ]] || return 0
  tn="${t%%"$us"*}"; [[ "$tn" == "$old" ]] || return 0
  printf '%s%s%s' "$new" "$us" "${t#*"$us"}"
}

# @pure
# <답 본문> → 1(코드 블록 밖에 '>' 로 시작하는 인용 줄이 있다) | 0.
scv_mp_answer_has_quote() {
  local text="${1:-}" line fence=0 t q=$'\x3e'   # q = 인용 표시 문자 (순수성 검사가 글자 그대로를 방향 기호로 본다)
  while IFS= read -r line || [[ -n "$line" ]]; do
    t="${line#"${line%%[![:space:]]*}"}"
    if [[ "$t" == '```'* ]]; then fence=$(( 1 - fence )); continue; fi
    (( fence )) && continue
    [[ "${t:0:1}" == "$q" ]] && { printf '1'; return 0; }
  done <<< "$text"
  printf '0'
}

# @pure
# <결정> <읽음 0|1> <다시 쓴 요청 기록됨 0|1> <답 인용 있음 0|1|""(답을 못 얻음)> → 판정 줄들: unread · unshown (없으면 빈 값).
scv_mp_turn_verdict() {
  local dec="${1:-}" read="${2:-0}" recorded="${3:-0}" quoted="${4:-}"
  case "$dec" in load|loaded) ;; *) return 0 ;; esac
  [[ "$dec" == "load" && "$read" != "1" ]] && printf 'unread\n'
  [[ "$recorded" == "1" && "$quoted" == "0" ]] && printf 'unshown\n'
  return 0
}

# @pure
# <판정 줄들> <키> [<상세 줄들>] → 다음 턴에 실을 경고 문장들 (매 턴 훅이 지시 바로 뒤에 한 번 싣는다).
# 상세 줄(v0.60.1+)은 help 가 그 턴에 실제로 낸 `GUIDE_FILE:` · `GUIDE_MARK_CMD:` 줄 — 안 읽음 경고 뒤에 두 칸 들여 붙여,
# help 출력을 보지 않고도 경고만으로 따라 할 수 있게 한다. 들여 쓴 줄은 초기화 때 경고와 함께 남는다(scv_mp_warn_keep).
scv_mp_warn_lines() {
  local verdicts="${1:-}" key="${2:-?}" detail="${3:-}" v d
  while IFS= read -r v || [[ -n "$v" ]]; do
    case "$v" in
      unread)  printf '%s\n' "[SCV 가이드] 직전 턴에 help 가 이 모델의 프롬프팅 가이드 원문($key)을 읽으라고 했지만 읽음 표시가 없다 — 이번 턴에 아래 원문을 끝까지 읽고 아래 명령을 실행한 뒤, 그 가이드로 요청을 다시 써라."
               while IFS= read -r d || [[ -n "$d" ]]; do [[ -n "${d//[[:space:]]/}" ]] && printf '  %s\n' "$d"; done <<< "$detail" ;;
      unshown) printf '%s\n' "[SCV 가이드] 직전 턴에 다시 쓴 요청을 기록만 하고 답에 보이지 않았다 — 이번 턴에는 결론 바로 뒤에 인용 블록으로 보여라." ;;
    esac
  done <<< "$verdicts"
  return 0
}

# @pure
# <경고 파일 내용> → 초기화(재개 · 압축 · 지우기) 뒤에도 남길 줄들: `[SCV 가이드]` 로 시작하는 줄과 그 뒤에 이어지는 두 칸
# 들여 쓴 줄. 나머지(규약 지문 · 답 모양 경고)는 버린다 — 규약은 어차피 다시 읽히지만, 가이드 원문을 건너뛴 사실은
# 초기화로 사라지지 않는다(0.60.0 실측: 재개 훅이 경고를 지워 다음 턴 모델에게 닿지 않았다).
scv_mp_warn_keep() {
  local text="${1:-}" line keep=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "[SCV 가이드]"* ]]; then keep=1; printf '%s\n' "$line"; continue; fi
    if (( keep )) && [[ "$line" == "  "* ]]; then printf '%s\n' "$line"; continue; fi
    keep=0
  done <<< "$text"
  return 0
}
