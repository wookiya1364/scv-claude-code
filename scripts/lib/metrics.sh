#!/usr/bin/env bash
# lib/metrics.sh — 과정 계기판의 순수부. 문자열을 받아 문자열을 낸다.
#
# 이미 디스크에 있는 기록(아카이브 색인 · 계획서 · 대화 파일 · 결정 로그)을
# 효과층(metrics.sh)이 문자열로 읽어 넘기면, 여기 함수들이 레코드 → 지표 → 표로
# 바꾼다. 파일·시각·난수·네트워크·외부 명령을 만지지 않는다 — bash 3.2 내장만.
#
# 레코드 형식(탭 구분, 한 줄 한 레코드):
#   색인   : slug \t status \t obsoleted_by
#   계획   : conv1,conv2 \t supersedes_n \t has_purity(0|1)
#   결정   : slug|unmatched \t verdict \t minutes
#   지표   : slug \t value|none
#   요약   : n \t m \t sum \t avg10 \t med10     (x10 = 소수 한 자리 고정)
#
# 계약: core/contracts/purity.md

# ---------------------------------------------------------------- 내부 도우미

# @pure
# <문자열> → 앞뒤 공백을 뗀 문자열.
scv_mx_trim() {
  local s="${1:-}"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# @pure
# <값> → 뒤따르는 " # 주석" 과 감싼 따옴표를 뗀 값. 첫 낱말만 남기지 않는다 —
# 경로에 공백은 없지만 제목에는 있다.
scv_mx_strip_comment() {
  local v="${1:-}"
  v="${v%%[[:space:]]#*}"
  v="$(scv_mx_trim "$v")"
  v="${v#\"}"; v="${v%\"}"
  v="${v#\'}"; v="${v%\'}"
  printf '%s' "$v"
}

# ---------------------------------------------------------------- 시각

# @pure
# "YYYY-MM-DD HH:MM" → 1970-01-01 00:00 기준 분(정수). 형식이 아니면 빈 값.
# days-from-civil 공식 — date 를 부르지 않는다.
scv_mx_civil_to_minutes() {
  local s="${1:-}" y m d hh mi era yoe doy doe days
  [[ "$s" =~ ^([0-9]{4})-([0-9]{2})-([0-9]{2})\ ([0-9]{2}):([0-9]{2})$ ]] || return 0
  y=$((10#${BASH_REMATCH[1]})); m=$((10#${BASH_REMATCH[2]})); d=$((10#${BASH_REMATCH[3]}))
  hh=$((10#${BASH_REMATCH[4]})); mi=$((10#${BASH_REMATCH[5]}))
  (( m >= 1 && m <= 12 && d >= 1 && d <= 31 && hh <= 23 && mi <= 59 )) || return 0
  (( m <= 2 )) && y=$(( y - 1 ))
  era=$(( y / 400 ))
  yoe=$(( y - era * 400 ))
  if (( m > 2 )); then doy=$(( (153 * (m - 3) + 2) / 5 + d - 1 )); else doy=$(( (153 * (m + 9) + 2) / 5 + d - 1 )); fi
  doe=$(( yoe * 365 + yoe / 4 - yoe / 100 + doy ))
  days=$(( era * 146097 + doe - 719468 ))
  printf '%s' $(( days * 1440 + hh * 60 + mi ))
}

# ---------------------------------------------------------------- 파싱

# @pure
# <INDEX.yaml 텍스트> → 색인 레코드 줄들 (slug \t status \t obsoleted_by).
scv_mx_parse_index() {
  local text="${1:-}" line key val slug="" status="" obs="" out=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="$(scv_mx_trim "$line")"
    [[ -z "$line" || "$line" == \#* ]] && continue
    if [[ "$line" == "- slug:"* ]]; then
      [[ -n "$slug" ]] && out+="$slug	$status	$obs"$'\n'
      slug="$(scv_mx_strip_comment "${line#- slug:}")"; status=""; obs=""
      continue
    fi
    [[ -n "$slug" ]] || continue
    key="${line%%:*}"; val="${line#*:}"
    case "$key" in
      status)       status="$(scv_mx_strip_comment "$val")" ;;
      obsoleted_by) obs="$(scv_mx_strip_comment "$val")" ;;
    esac
  done <<< "$text"
  [[ -n "$slug" ]] && out+="$slug	$status	$obs"$'\n'
  printf '%s' "$out"
}

# @pure
# <PLAN.md 텍스트> → 계획 레코드 한 줄 (conv1,conv2 \t supersedes_n \t has_purity).
# 프런트매터의 raw_sources(블록·인라인) 중 conversations/ 경로만, supersedes 의
# 항목 수, 본문에 "## 순수함수 · 파이프라인" 헤딩이 있는지.
scv_mx_parse_plan() {
  local text="${1:-}" line t key in_fm=0 fm_seen=0 list="" convs="" sup_n=0 purity=0 item inline
  while IFS= read -r line || [[ -n "$line" ]]; do
    if (( ! fm_seen )); then
      if (( ! in_fm )); then
        [[ "$line" == "---" ]] && in_fm=1
        continue
      fi
      if [[ "$line" == "---" ]]; then in_fm=0; fm_seen=1; continue; fi
      t="$(scv_mx_trim "$line")"
      [[ -z "$t" || "$t" == \#* ]] && continue
      if [[ "$t" == "- "* ]]; then
        [[ -n "$list" ]] || continue
        item="$(scv_mx_strip_comment "${t#- }")"
        [[ -z "$item" ]] && continue
        case "$list" in
          raw_sources) [[ "$item" == *conversations/* ]] && convs+="${convs:+,}$item" ;;
          supersedes)  sup_n=$(( sup_n + 1 )) ;;
        esac
        continue
      fi
      if [[ "$line" == [a-z_]*:* ]]; then
        list=""
        key="${line%%:*}"; inline="$(scv_mx_strip_comment "${line#*:}")"
        case "$key" in
          raw_sources|supersedes)
            if [[ -z "$inline" ]]; then
              list="$key"
            elif [[ "$inline" == \[*\] ]]; then
              inline="${inline#[}"; inline="${inline%]}"
              local parts=()
              IFS=',' read -r -a parts <<< "$inline"
              # bash 3.2 + set -u: 빈 배열의 "${a[@]}" 는 unbound — ${a[@]+"${a[@]}"} 꼴로 편다
              for item in ${parts[@]+"${parts[@]}"}; do
                item="$(scv_mx_strip_comment "$item")"
                [[ -z "$item" ]] && continue
                case "$key" in
                  raw_sources) [[ "$item" == *conversations/* ]] && convs+="${convs:+,}$item" ;;
                  supersedes)  sup_n=$(( sup_n + 1 )) ;;
                esac
              done
            fi ;;
        esac
      fi
      continue
    fi
    [[ "$line" == "## 순수함수 · 파이프라인"* ]] && purity=1
  done <<< "$text"
  # 첫 필드가 비면 read 가 앞 탭을 공백으로 보고 잘라 필드가 밀린다 — 빈 값은 "-" 로 낸다
  printf '%s\t%s\t%s\n' "${convs:--}" "$sup_n" "$purity"
}

# @pure
# <계획서에 적힌 대화 경로> → SCV_DIR 기준 후보 경로 두 줄: 그대로(앞의 scv/ 는 뗀다),
# conversations/archive/<basename>. 실존 확인은 효과층이 한다.
scv_mx_resolve_conv_path() {
  local p="${1:-}" rel base
  [[ -n "$p" ]] || return 0
  rel="${p#scv/}"
  base="${p##*/}"
  printf '%s\n%s\n' "$rel" "conversations/archive/$base"
}

# @pure
# <대화 파일 텍스트> → "## Turn N —" 헤딩 수. 코드 블록(```) 안은 세지 않는다.
scv_mx_count_turns() {
  local text="${1:-}" line n=0 fence=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == '```'* ]]; then fence=$(( 1 - fence )); continue; fi
    (( fence )) && continue
    [[ "$line" =~ ^##[[:space:]]+Turn[[:space:]]+[0-9]+ ]] && n=$(( n + 1 ))
  done <<< "$text"
  printf '%s' "$n"
}

# @pure
# <DECISIONS.md 텍스트> → 결정 레코드 줄들 (slug|unmatched \t verdict \t minutes).
# 헤더 "## [YYYY-MM-DD HH:MM] author — title" 만 엔트리다 — 템플릿 행([YYYY-…])은
# 시각이 아니라서 버려지고, 그 아래 verdict/refs 도 함께 버려진다.
scv_mx_parse_decisions() {
  local text="${1:-}" line mins="" verdict="" slug="" valid=0 out="" v
  _scv_mx_flush() {
    if (( valid )) && [[ -n "$verdict" ]]; then
      out+="${slug:-unmatched}	$verdict	$mins"$'\n'
    fi
  }
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "## ["* ]]; then
      _scv_mx_flush
      valid=0; verdict=""; slug=""; mins=""
      if [[ "$line" =~ ^##\ \[([0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2})\] ]]; then
        mins="$(scv_mx_civil_to_minutes "${BASH_REMATCH[1]}")"
        [[ -n "$mins" ]] && valid=1
      fi
      continue
    fi
    (( valid )) || continue
    if [[ "$line" == "- verdict:"* && -z "$verdict" ]]; then
      v="$(scv_mx_trim "${line#- verdict:}")"
      verdict="${v%%[[:space:]|]*}"
      continue
    fi
    if [[ "$line" == "- refs:"* && -z "$slug" ]]; then
      if [[ "$line" =~ scv/(promote|archive)/([^/[:space:]]+)/ ]]; then
        slug="${BASH_REMATCH[2]}"
      fi
    fi
  done <<< "$text"
  _scv_mx_flush
  unset -f _scv_mx_flush
  printf '%s' "$out"
}

# ---------------------------------------------------------------- 지표

# @pure
# <색인 레코드들> <결정 레코드들> → 지표 줄들 (slug \t minutes|none).
# 같은 slug 의 가장 이른 adopted 시각과, 그 뒤 가장 이른 archived 시각의 차.
scv_mx_metric_lead_time() {
  local index="${1:-}" decisions="${2:-}" line slug verdict mins rest out="" i
  local slugs=() adopted=() archived=()
  while IFS=$'\t' read -r slug verdict mins || [[ -n "$slug" ]]; do
    [[ -z "$slug" || "$slug" == "unmatched" || -z "$mins" ]] && continue
    [[ "$verdict" == "adopted" || "$verdict" == "archived" ]] || continue
    local found=-1
    for (( i = 0; i < ${#slugs[@]}; i++ )); do [[ "${slugs[$i]}" == "$slug" ]] && { found=$i; break; }; done
    if (( found < 0 )); then slugs+=("$slug"); adopted+=(""); archived+=(""); found=$(( ${#slugs[@]} - 1 )); fi
    if [[ "$verdict" == "adopted" ]]; then
      [[ -z "${adopted[$found]}" || mins -lt ${adopted[$found]} ]] && adopted[$found]="$mins"
    else
      [[ -z "${archived[$found]}" || mins -lt ${archived[$found]} ]] && archived[$found]="$mins"
    fi
  done <<< "$decisions"
  while IFS=$'\t' read -r slug rest || [[ -n "$slug" ]]; do
    [[ -z "$slug" ]] && continue
    local a="" b=""
    for (( i = 0; i < ${#slugs[@]}; i++ )); do [[ "${slugs[$i]}" == "$slug" ]] && { a="${adopted[$i]}"; b="${archived[$i]}"; break; }; done
    if [[ -n "$a" && -n "$b" && b -ge a ]]; then out+="$slug	$(( b - a ))"$'\n'; else out+="$slug	none"$'\n'; fi
  done <<< "$index"
  printf '%s' "$out"
}

# @pure
# <색인 레코드들> <slug\tsupersedes_n 줄들> → 지표 줄들 (slug \t 0|1).
# 1 = 누군가의 obsoleted_by 대상이거나 supersedes 가 비어 있지 않다 (합집합).
scv_mx_metric_followup() {
  local index="${1:-}" sups="${2:-}" line slug status obs n targets=" " out="" v
  while IFS=$'\t' read -r slug status obs || [[ -n "$slug" ]]; do
    [[ -n "$obs" ]] && targets+="$obs "
  done <<< "$index"
  local sup_slugs=" "
  while IFS=$'\t' read -r slug n || [[ -n "$slug" ]]; do
    [[ -n "$slug" && "$n" =~ ^[0-9]+$ ]] && (( n > 0 )) && sup_slugs+="$slug "
  done <<< "$sups"
  while IFS=$'\t' read -r slug status obs || [[ -n "$slug" ]]; do
    [[ -z "$slug" ]] && continue
    v=0
    [[ "$targets" == *" $slug "* || "$sup_slugs" == *" $slug "* ]] && v=1
    out+="$slug	$v"$'\n'
  done <<< "$index"
  printf '%s' "$out"
}

# @pure
# <지표 줄들 (slug \t value|none)> → 요약 한 줄 (n \t m \t sum \t avg10 \t med10).
# n = 값이 있는 계획 수, m = 전체. avg10·med10 은 소수 한 자리를 정수로 (x10).
# none 만 있으면 avg10·med10 은 빈 값.
scv_mx_aggregate() {
  local lines="${1:-}" slug v n=0 m=0 sum=0 i j tmp avg10="" med10=""
  local vals=()
  while IFS=$'\t' read -r slug v || [[ -n "$slug" ]]; do
    [[ -z "$slug" ]] && continue
    m=$(( m + 1 ))
    [[ "$v" =~ ^[0-9]+$ ]] || continue
    n=$(( n + 1 )); sum=$(( sum + v )); vals+=("$v")
  done <<< "$lines"
  if (( n > 0 )); then
    # 삽입 정렬 — sort 를 부르지 않는다 (n 은 계획 수, 수백을 넘지 않는다)
    for (( i = 1; i < n; i++ )); do
      tmp=${vals[$i]}; j=$(( i - 1 ))
      # bash 3.2 는 단락 평가 뒤에도 vals[-1] 첨자를 오류로 본다 — 조건을 둘로 나눈다
      while (( j >= 0 )); do
        (( vals[j] > tmp )) || break
        vals[$(( j + 1 ))]=${vals[$j]}; j=$(( j - 1 ))
      done
      vals[$(( j + 1 ))]=$tmp
    done
    avg10=$(( (sum * 10 + n / 2) / n ))
    if (( n % 2 )); then med10=$(( vals[n / 2] * 10 )); else med10=$(( (vals[n / 2 - 1] + vals[n / 2]) * 5 )); fi
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$n" "$m" "$sum" "$avg10" "$med10"
}

# @pure
# <x10 정수> → "d.d". 빈 값이면 "—".
scv_mx_fmt10() {
  local x="${1:-}"
  [[ "$x" =~ ^[0-9]+$ ]] || { printf '%s' "—"; return 0; }
  printf '%s.%s' $(( x / 10 )) $(( x % 10 ))
}

# @pure
# <턴 요약> <리드타임 요약> <후속 요약> <순수 요약> → 표 텍스트 (파이프 구분, 네 지표 한 줄씩).
scv_mx_render_table() {
  local t="${1:-}" l="${2:-}" f="${3:-}" p="${4:-}" n m sum avg10 med10
  printf '%s\n' "지표 | 값 | 적용 범위 | 중앙값"
  IFS=$'\t' read -r n m sum avg10 med10 <<< "$t"
  printf '%s\n' "계획당 대화 턴 수 | 평균 $(scv_mx_fmt10 "$avg10") | $n/$m | $(scv_mx_fmt10 "$med10")"
  IFS=$'\t' read -r n m sum avg10 med10 <<< "$l"
  printf '%s\n' "승인→보관 리드타임(분) | 평균 $(scv_mx_fmt10 "$avg10") | $n/$m | $(scv_mx_fmt10 "$med10")"
  IFS=$'\t' read -r n m sum avg10 med10 <<< "$f"
  printf '%s\n' "후속 재발률 | $sum/$m | $n/$m | —"
  IFS=$'\t' read -r n m sum avg10 med10 <<< "$p"
  printf '%s\n' "순수 절 보유율 | $sum/$m | $n/$m | —"
}

# @pure
# <지표 이름> <지표 줄들> → TSV 행들 (metric \t slug \t value).
scv_mx_render_tsv() {
  local name="${1:-}" lines="${2:-}" slug v
  while IFS=$'\t' read -r slug v || [[ -n "$slug" ]]; do
    [[ -z "$slug" ]] && continue
    printf '%s\t%s\t%s\n' "$name" "$slug" "$v"
  done <<< "$lines"
}
