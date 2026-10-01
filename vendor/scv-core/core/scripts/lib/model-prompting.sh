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

# ---------------------------------------------------------------- 첫 턴 안내 (v0.61.0+)
# 매 턴 훅은 모델이 거르지 못하는 통로다(0.60.2 실측: 둘째 턴 훅의 경로 · 명령을 받자 원문을 읽었다). 훅 입력에는 모델
# 이름이 없으므로, help 가 마지막으로 본 모델의 원문 경로 · 표시 명령 기록(.help-guide-last)을 새 컨텍스트의 첫 턴에 싣는다.
# 기록: 첫 줄 = 모델 id 또는 "none", 둘째 줄부터 = help 가 낸 GUIDE_FILE · GUIDE_MARK_CMD 줄.

# @pure
# <스위치 on|off> <읽음 0|1> <가이드 경고 예약됨 0|1> <기록 전문> → 매 턴 훅이 실을 블록 (싣지 않으면 빈 값).
scv_mp_first_turn_lines() {
  local sw="${1:-on}" read="${2:-0}" warned="${3:-0}" rec="${4:-}" model detail d
  [[ "$sw" == "on" && "$read" != "1" && "$warned" != "1" ]] || return 0
  model="${rec%%$'\n'*}"; detail=""; [[ "$rec" == *$'\n'* ]] && detail="${rec#*$'\n'}"
  model="${model//[[:space:]]/}"
  [[ -n "$model" && "$model" != "none" && -n "${detail//[[:space:]]/}" ]] || return 0
  printf '%s\n' "[SCV 가이드] 이 컨텍스트에서 아직 이 모델의 프롬프팅 가이드 원문을 읽지 않았다 — 답하기 전에 아래 원문을 끝까지 읽고 아래 명령을 실행하라(지난 모델 $model 기준 — 지금 모델이 다르면 help 의 GUIDE 줄을 따르라)."
  while IFS= read -r d || [[ -n "$d" ]]; do [[ -n "${d//[[:space:]]/}" ]] && printf '  %s\n' "$d"; done <<< "$detail"
  return 0
}

# ---------------------------------------------------------------- 매 턴 1:1 비교 · 등록 (v0.62.0+)
# 모든 사용자 메시지(길이와 무관)를 그 모델 버전의 요구 항목 목록과 1:1 비교해 등록하게 하고, 등록 전 파일 쓰기와 등록 · 인용
# 없는 종료를 막는다. 목록은 래퍼 데이터: 가이드 폴더의 checklist-<키>.tsv — "<id>\t<label>\t<원문 인용>" (# 줄은 주석).
# 제출(등록) 형식: 줄마다 "<id>\t<msg|ctx|asked|na>\t<값>", 그리고 "rewrite\t-\t<다시 쓴 요청>" 한 줄. na = 이번 요청에 해당 없음(값에 이유).

# @pure
# <색인 텍스트> → 공통(*) 행의 키 또는 빈 값.
scv_mp_common_key() {
  local index="${1:-}" mid key rest
  while IFS=$'\t' read -r mid key rest || [[ -n "$mid" ]]; do
    if [[ "$mid" == "*" && -n "$key" ]]; then printf '%s' "$key"; return 0; fi
  done <<< "$index"
  return 0
}

# @pure
# <코어 루트> <프로필 값> → 가이드 폴더 후보들(한 줄에 하나, 앞에서부터 시도). 절대 경로면 그것 하나. 상대 경로면 코어 루트
# 기준과, 그 위로 세 단계까지 — 클로드 래퍼는 플러그인 최상위 기준 값(prompting)을 쓰는데 훅은 벤더 코어에서 돈다.
scv_mp_guides_candidates() {
  local root="${1:-}" v="${2:-}" up="" i
  [[ -n "$v" ]] || return 0
  case "$v" in /*) printf '%s\n' "$v"; return 0 ;; esac
  root="${root%/}"
  for i in 0 1 2 3; do
    printf '%s%s/%s\n' "$root" "$up" "$v"
    up="$up/.."
  done
  return 0
}

# @pure
# <공통 목록 tsv> <모델 목록 tsv> → 병합된 "id\tlabel" 줄들. 주석 · 빈 줄 · 형식이 깨진 줄(id · label 없음)은 버린다.
# 순서: 공통 순서대로, 같은 id 는 모델 쪽 label 이 이긴다, 그 뒤 모델에만 있는 항목. id 는 소문자 · 숫자 · - 만.
scv_mp_checklist_merge() {
  local common="${1:-}" model="${2:-}" id label rest out="" mids="" mlabels="" line
  _ok_id() { [[ -n "$1" ]] || return 1; local t="${1//[a-z0-9-]/}"; [[ -z "$t" ]]; }
  while IFS=$'\t' read -r id label rest || [[ -n "$id" ]]; do
    [[ -z "$id" || "$id" == \#* || -z "$label" ]] && continue; _ok_id "$id" || continue
    mids="$mids|$id|"; mlabels="$mlabels$id"$'\t'"$label"$'\n'
  done <<< "$model"
  while IFS=$'\t' read -r id label rest || [[ -n "$id" ]]; do
    [[ -z "$id" || "$id" == \#* || -z "$label" ]] && continue; _ok_id "$id" || continue
    [[ "$out" == *$'\n'"$id"$'\t'* || "$out" == "$id"$'\t'* ]] && continue
    if [[ "$mids" == *"|$id|"* ]]; then
      line="$(printf '%s' "$mlabels" | while IFS=$'\t' read -r a b; do [[ "$a" == "$id" ]] && { printf '%s' "$b"; break; }; done)"
      out="$out$id"$'\t'"$line"$'\n'
    else
      out="$out$id"$'\t'"$label"$'\n'
    fi
  done <<< "$common"
  while IFS=$'\t' read -r id label || [[ -n "$id" ]]; do
    [[ -z "$id" ]] && continue
    [[ "$out" == *$'\n'"$id"$'\t'* || "$out" == "$id"$'\t'* ]] && continue
    out="$out$id"$'\t'"$label"$'\n'
  done <<< "$mlabels"
  printf '%s' "$out"
}

# @pure
# <병합 목록> <제출 텍스트> → 문제 줄들(없으면 빈 값 = 통과): "missing <id>" · "bad-status <id>" · "empty <id>" · "missing rewrite".
scv_mp_register_problems() {
  local list="${1:-}" sub="${2:-}" id label st val seen="" rw=0 out=""
  while IFS=$'\t' read -r id st val || [[ -n "$id" ]]; do
    [[ -z "$id" || "$id" == \#* ]] && continue
    if [[ "$id" == "rewrite" ]]; then [[ -n "${val//[[:space:]]/}" ]] && rw=1; continue; fi
    case "$st" in
      msg|ctx|asked|na) [[ -n "${val//[[:space:]]/}" ]] && seen="$seen|$id|" || out="${out}empty $id"$'\n' ;;
      *) out="${out}bad-status $id"$'\n' ;;
    esac
  done <<< "$sub"
  while IFS=$'\t' read -r id label || [[ -n "$id" ]]; do
    [[ -z "$id" ]] && continue
    [[ "$seen" == *"|$id|"* ]] && continue
    [[ "$out" == *" $id"$'\n'* ]] && continue
    out="${out}missing $id"$'\n'
  done <<< "$list"
  (( rw )) || out="${out}missing rewrite"$'\n'
  printf '%s' "$out"
}

# @pure
# <제출 텍스트> → 다시 쓴 요청 한 줄(rewrite 행의 값) 또는 빈 값.
scv_mp_register_rewrite() {
  local sub="${1:-}" id st val
  while IFS=$'\t' read -r id st val || [[ -n "$id" ]]; do
    [[ "$id" == "rewrite" && -n "${val//[[:space:]]/}" ]] && { printf '%s' "$val"; return 0; }
  done <<< "$sub"
  return 0
}

# ---------------------------------------------------------------- 자동 입력 턴 (v0.63.0+)
# 호스트가 스스로 보낸 입력(배경 작업 완료 알림 등)은 사람 턴이 아니다 — 태그 이름은 래퍼 호스트 설정 SCV_AUTO_PROMPT_TAGS 가 준다.

# @pure
# <프롬프트> <태그 이름 목록(공백으로 나눔)> → auto | human. 입력이 태그 블록과 공백만으로 이뤄질 때만 auto — 앞뒤 공백을 빼고
# 목록의 "<이름>" · "<이름 " 으로 시작하고 "</이름>" 으로 끝나며, 어느 닫는 태그 뒤에도(공백 다음) 태그가 아닌 글이 오지 않아야
# 한다. 알림 앞 · 뒤 · 사이에 사람이 쓴 글이 있으면 사람 턴이다(그 요청은 등록돼야 한다). 실제 알림 입력은 태그 블록 하나뿐이다
# (2026-10-01 작업 기록 7건으로 확인). 판별이 틀리면 안전한 쪽(이전 동작)으로 간다.
# 속도: 앞뒤는 1024자 창에서만 보고(공백 제거 관용구는 공백이 길면 제곱 시간 — 창을 넘는 공백이면 사람 턴), 닫는 태그 뒤 검사는
# 정규식 검색 한 번(64KB 에 약 12ms, bash 3.2 · 5 측정 — 패턴으로 잘라 내기는 같은 길이에 약 2초라 쓰지 않는다).
# 태그 이름은 영문 · 숫자 · _ · - 만 받는다(정규식 · 글로브 글자가 든 이름은 무시). 꺾쇠는 글자 코드로 적는다(순수성 검사가
# < > 를 리다이렉션으로 본다). 목록은 직접 나눈다 — 따옴표 없는 전개는 글로브를 탄다.
scv_mp_prompt_kind() {
  local p="${1:-}" list="${2:-}" rest t lt=$'\x3c' gt=$'\x3e' w=1024 s e re names="" head=0 tail=0
  s="${p:0:$w}"; e="$p"; [[ ${#p} -gt $w ]] && e="${p:${#p}-$w}"
  s="${s#"${s%%[![:space:]]*}"}"; e="${e%"${e##*[![:space:]]}"}"
  [[ -n "$s" && -n "$e" ]] || { printf 'human'; return 0; }
  rest="$list"
  while [[ -n "$rest" ]]; do
    rest="${rest#"${rest%%[![:space:]]*}"}"
    [[ -n "$rest" ]] || break
    t="${rest%%[[:space:]]*}"; rest="${rest#"$t"}"
    [[ "$t" =~ ^[A-Za-z0-9_-]+$ ]] || continue
    names="$names $t"
    [[ "$s" == "$lt$t$gt"* || "$s" == "$lt$t "* ]] && head=1
    [[ "$e" == *"$lt/$t$gt" ]] && tail=1
  done
  (( head && tail )) || { printf 'human'; return 0; }
  for t in $names; do
    re="$lt/$t$gt[[:space:]]*[^[:space:]$lt]"
    [[ "$p" =~ $re ]] && { printf 'human'; return 0; }
  done
  printf 'auto'
}

# ---------------------------------------------------------------- 다시 쓴 요청의 SCV 원칙 (v0.63.0+)
# 원칙 문구는 contracts/rewrite-principle.md 한 곳에만 있다. 여기는 그 본문을 받아 고르고 붙이는 판단만 한다.

# @pure
# <코어 루트> → 원칙 파일 후보(한 줄에 하나): 코어 루트 아래, 그다음 래퍼가 벤더링한 코어 아래 —
# 투영된 플러그인 루트에서 도는 스크립트도 벤더 사본의 원칙 파일을 찾는다.
scv_mp_principle_candidates() {
  local root="${1:-}"
  [[ -n "$root" ]] || return 0
  root="${root%/}"
  printf '%s\n' "$root/contracts/rewrite-principle.md" "$root/vendor/scv-core/core/contracts/rewrite-principle.md"
}

# @pure
# <SCV_LANG 값> → 원칙 구역 이름(korean | english | japanese | 소문자 그대로). 짧은 표기(ko · en · ja)도 받는다.
scv_mp_principle_lang() {
  local v
  v="$(scv_mp_normalize_id "${1:-}")"; v="${v//\"/}"; v="${v//\'/}"
  case "$v" in
    ko|kr|korean) printf 'korean' ;;
    en|english|"") printf 'english' ;;
    ja|jp|japanese) printf 'japanese' ;;
    *) printf '%s' "$v" ;;
  esac
}

# @pure
# <원칙 파일 본문> <구역 이름> → 그 구역(표식 줄 + 전문, 끝 줄바꿈 없음). 없으면 빈 값.
scv_mp_principle_pick() {
  # 꺾쇠는 글자 코드로 적는다 — 순수성 검사가 < > 를 파일 리다이렉션으로 본다(scv_mp_answer_shows_rewrite 와 같은 방식).
  local body="${1:-}" want="${2:-}" line name on=0 out="" open=$'\x3c'"!-- principle:" close=" --"$'\x3e'
  [[ -n "$want" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "$open"*"$close" ]]; then
      (( on )) && break
      name="${line#"$open"}"; name="${name%"$close"}"
      [[ "$name" == "$want" ]] && on=1
      continue
    fi
    (( on )) && out="$out$line"$'\n'
  done <<< "$body"
  printf '%s' "${out%$'\n'}"
}

# @pure
# <원칙 파일 본문> <SCV_LANG 값> → 그 언어의 구역. 구역이 없는 언어는 english 구역, 그것도 없으면 빈 값.
scv_mp_principle_section() {
  local body="${1:-}" lang out
  lang="$(scv_mp_principle_lang "${2:-}")"
  out="$(scv_mp_principle_pick "$body" "$lang")"
  [[ -n "$out" ]] || out="$(scv_mp_principle_pick "$body" english)"
  printf '%s' "$out"
}

# @pure
# <구역> → 표식(첫 줄 "tag: " 뒤). 표식 줄이 없으면 빈 값.
scv_mp_principle_tag() {
  local first="${1:-}"
  first="${first%%$'\n'*}"
  case "$first" in "tag: "?*) printf '%s' "${first#tag: }" ;; esac
  return 0
}

# @pure
# <구역> → 원칙 전문(표식 줄을 뺀 나머지). 표식 줄이 없으면 구역 전체.
scv_mp_principle_text() {
  local sec="${1:-}" first
  first="${sec%%$'\n'*}"
  case "$first" in
    "tag: "*) [[ "$sec" == *$'\n'* ]] && printf '%s' "${sec#*$'\n'}" ;;
    *) printf '%s' "$sec" ;;
  esac
  return 0
}

# @pure
# <다시 쓴 요청> <스위치 on|off> <표식> → REWRITE 줄 값. off · 표식 없음 · 요청 없음이면 요청 그대로(이 기능 전과 같다).
scv_mp_rewrite_tagged() {
  local rw="${1:-}" sw="${2:-on}" tag="${3:-}"
  if [[ "$sw" == "on" && -n "$tag" && -n "$rw" ]]; then printf '%s %s' "$rw" "$tag"; else printf '%s' "$rw"; fi
}

# @pure
# <답 본문> <다시 쓴 요청> → 1(코드 블록 밖 인용 줄에 다시 쓴 요청이 보인다) | 0. 인용 줄이 "다시 쓴 요청" · "Rewritten request"
# 라벨을 담거나, 다시 쓴 요청의 앞 16글자(공백 제외)를 담으면 보인 것으로 본다.
scv_mp_answer_shows_rewrite() {
  local text="${1:-}" rw="${2:-}" line t fence=0 q=$'\x3e' key="" flat
  key="${rw//[[:space:]]/}"; key="${key:0:16}"
  while IFS= read -r line || [[ -n "$line" ]]; do
    t="${line#"${line%%[![:space:]]*}"}"
    if [[ "$t" == '```'* ]]; then fence=$(( 1 - fence )); continue; fi
    (( fence )) && continue
    [[ "${t:0:1}" == "$q" ]] || continue
    case "$t" in *"다시 쓴 요청"*|*"Rewritten request"*) printf '1'; return 0 ;; esac
    flat="${t//[[:space:]]/}"
    [[ -n "$key" && "$flat" == *"$key"* ]] && { printf '1'; return 0; }
  done <<< "$text"
  printf '0'
}

# @pure
# <등록됨 0|1> <보임 0|1|""(답을 못 얻음)> <이미 계속 중 0|1> → ok | block | warn.
# 계속 중이면 절대 막지 않는다(같은 턴 한 번) — 다음 턴 경고로 넘긴다. 답을 못 얻었으면 "보임" 은 판정하지 않는다.
scv_mp_stop_gate() {
  local reg="${1:-0}" shown="${2:-}" active="${3:-0}" bad=0
  [[ "$reg" == "1" ]] || bad=1
  [[ "$shown" == "0" ]] && bad=1
  (( bad )) || { printf 'ok'; return 0; }
  [[ "$active" == "1" ]] && printf 'warn' || printf 'block'
}

# @pure
# <스위치> <토큰> <모델 id 또는 ""> <병합 목록 또는 ""> <스크립트 경로> → 매 턴 훅이 싣는 블록(스위치 off · 토큰 없음이면 빈 값).
# 토큰은 싣지 않는다 — 같은 상태면 출력이 늘 같아야 한다(등록은 표 파일을 스스로 읽는다).
scv_mp_turn_block() {
  local sw="${1:-on}" tok="${2:-}" model="${3:-}" list="${4:-}" cmd="${5:-model-prompting.sh}" id label items="" q=$'\x3e'
  [[ "$sw" == "on" && -n "$tok" ]] || return 0
  local mid="${model:-{지금 모델 id\}}"
  printf '%s\n' "[SCV 프롬프트] 이 턴 메시지(짧아도)를 모델 가이드 요구 항목과 1:1 비교 · 등록한 뒤 일하라 — 등록 전 파일 쓰기는 거절, 등록 · 인용 없는 종료는 차단."
  printf '%s\n' "  항목마다 msg · ctx(출처) · na(이유) · asked(못 찾은 것 중 가장 영향 큰 하나만, 추천 답과 함께) → bash \"$cmd\" register --model \"$mid\" (stdin \"id | 상태 | 값\" 줄들 + \"rewrite | - | 다시 쓴 요청\") → 결론 바로 뒤 '$q **다시 쓴 요청**: …' 인용(ctx · asked 항목 표시), 그것으로 일한다."
  if [[ -n "$model" && -n "$list" ]]; then
    while IFS=$'\t' read -r id label || [[ -n "$id" ]]; do [[ -n "$id" ]] && items="$items$id($label) "; done <<< "$list"
    printf '%s\n' "  항목 [$model — 다르면 checklist --model]: ${items% }"
  else
    printf '%s\n' "  항목: bash \"$cmd\" checklist --model \"{지금 모델 id}\""
  fi
  return 0
}

# @pure
# <제출 텍스트> → 탭 구분으로 맞춘 제출. 탭이 없는 줄은 " | " 로 나눈다(앞 두 번만 — 값에는 | 가 들어갈 수 있다). 앞뒤 공백은 잘라낸다.
scv_mp_register_normalize() {
  local sub="${1:-}" line a b c sep=" | "
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "${line//[[:space:]]/}" ]] && continue
    if [[ "$line" != *$'\t'* && "$line" == *"$sep"*"$sep"* ]]; then
      a="${line%%"$sep"*}"; line="${line#*"$sep"}"; b="${line%%"$sep"*}"; c="${line#*"$sep"}"
    else
      IFS=$'\t' read -r a b c <<< "$line"
    fi
    a="${a#"${a%%[![:space:]]*}"}"; a="${a%"${a##*[![:space:]]}"}"
    b="${b#"${b%%[![:space:]]*}"}"; b="${b%"${b##*[![:space:]]}"}"
    c="${c#"${c%%[![:space:]]*}"}"; c="${c%"${c##*[![:space:]]}"}"
    printf '%s\t%s\t%s\n' "$a" "$b" "$c"
  done <<< "$sub"
  return 0
}
