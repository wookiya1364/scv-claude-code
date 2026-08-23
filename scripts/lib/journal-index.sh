#!/usr/bin/env bash
# journal-index.sh — 저널에서 의미 있는 항목만 찾아 읽기 위한 색인. 순수부.
#
# 저널은 모든 턴을 그대로 쌓는다. 지난 이야기를 찾으려고 파일 전체를 읽으면
# 컨텍스트가 그만큼 찬다. 표시된 항목의 **위치**를 따로 적어 두고, 읽을 때는
# 저널을 훑지 않고 그 구간만 읽는다.
#
# 이 파일의 함수는 전부 순수하다 — 색인 텍스트와 문자열만 다루고 파일을 열지
# 않는다. 파일을 여는 것은 journal-append.sh 와 journal-read.sh 가 맡는다.
# core/contracts/purity.md 의 계약이고, check-purity.sh 가 기계로 강제한다.
#
# 색인 형식: 탭 구분 한 줄에 하나. append-only.
#   <표시>\t<키>\t<파일>\t<오프셋>\t<길이>\t<시각>\t<한 줄 요약>

# 알려진 표시. 이 밖의 값은 조용히 무시한다 — 저널 기록 자체는 막지 않는다.
SCV_JOURNAL_MARKS="decision plan blocker pivot"

# journal_mark_normalize <표시>
#
# 알려진 표시면 소문자로 정규화해 낸다. 아니면 빈 값.
#
# 대소문자와 앞뒤 공백만 허용 오차로 둔다. 오타를 알아서 고쳐 주지 않는다 —
# 그러면 무엇이 기록됐는지 부르는 쪽이 모르게 된다.
# @pure
journal_mark_normalize() {
  local m="${1:-}" k
  # 앞뒤 공백만 떼어 낸다. 가운데 공백까지 지우면 "de cision" 이 조용히
  # "decision" 이 되어, 무엇이 기록됐는지 부르는 쪽이 모르게 된다.
  m="${m#"${m%%[![:space:]]*}"}"
  m="${m%"${m##*[![:space:]]}"}"
  m="${m,,}"          # bash 4+ 소문자 확장 — 외부 도구가 필요 없다
  [[ -n "$m" ]] || return 0
  for k in $SCV_JOURNAL_MARKS; do
    [[ "$k" == "$m" ]] && { printf '%s\n' "$k"; return 0; }
  done
  return 0
}

# journal_index_record <표시> <키> <파일> <오프셋> <길이> <시각> <요약>
#
# 색인 한 줄을 만든다. 필드에 탭이나 줄바꿈이 들어가면 공백으로 바꾼다 —
# 한 줄 한 레코드라는 형식이 깨지면 색인 전체를 못 읽는다.
#
# 표시가 알려진 것이 아니거나 오프셋·길이가 숫자가 아니면 빈 값을 낸다.
# 부르는 쪽은 빈 값이면 색인에 적지 않는다.
# @pure
journal_index_record() {
  local mark key file off len ts summary
  mark="$(journal_mark_normalize "${1:-}")"
  [[ -n "$mark" ]] || return 0
  key="${2:-}"; file="${3:-}"; off="${4:-}"; len="${5:-}"; ts="${6:-}"; summary="${7:-}"
  [[ -n "$key" && -n "$file" ]] || return 0
  [[ "$off" =~ ^[0-9]+$ && "$len" =~ ^[1-9][0-9]*$ ]] || return 0

  # 한 줄 한 레코드라는 형식이 깨지면 색인 전체를 못 읽는다.
  key="${key//$'\t'/ }";     key="${key//$'\n'/ }";     key="${key//$'\r'/ }"
  file="${file//$'\t'/ }";   file="${file//$'\n'/ }";   file="${file//$'\r'/ }"
  ts="${ts//$'\t'/ }";       ts="${ts//$'\n'/ }";       ts="${ts//$'\r'/ }"
  summary="${summary//$'\t'/ }"; summary="${summary//$'\n'/ }"; summary="${summary//$'\r'/ }"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$mark" "$key" "$file" "$off" "$len" "$ts" "$summary"
}

# journal_index_lookup <색인텍스트> <키>
#
# 그 키의 레코드를 낸다. 없으면 빈 값.
#
# 같은 키가 여러 번 나오면 **마지막 것이 이긴다** — 나중 기록이 그 주제의 최신
# 상태다. 색인은 append-only 이므로 옛 기록도 남아 있지만 읽히는 것은 최신이다.
# @pure
journal_index_lookup() {
  local index="${1:-}" want="${2:-}" line found=""
  [[ -n "$index" && -n "$want" ]] || return 0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    local rest="${line#*$'\t'}"          # 표시를 떼고
    local key="${rest%%$'\t'*}"          # 키만
    [[ "$key" == "$want" ]] && found="$line"
  done <<< "$index"
  [[ -n "$found" ]] && printf '%s\n' "$found"
  return 0
}

# journal_index_filter <색인텍스트> <표시>
#
# 그 표시가 붙은 레코드들을 낸다. 표시가 비어 있으면 전부.
# 같은 키의 옛 레코드는 걸러 낸다 — 최신 하나만 남는다.
# @pure
journal_index_filter() {
  local index="${1:-}" want="${2:-}" line
  [[ -n "$index" ]] || return 0
  want="$(journal_mark_normalize "$want")"

  local keys="" out=""
  # 뒤에서 앞으로 볼 수 없으므로, 최신이 이기도록 두 번 지난다.
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    local mark="${line%%$'\t'*}"
    [[ -z "$want" || "$mark" == "$want" ]] || continue
    local rest="${line#*$'\t'}"
    local key="${rest%%$'\t'*}"
    keys="$keys$key"$'\n'
  done <<< "$index"

  local seen=""
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    local mark="${line%%$'\t'*}"
    [[ -z "$want" || "$mark" == "$want" ]] || continue
    local rest="${line#*$'\t'}"
    local key="${rest%%$'\t'*}"
    # 이 키의 마지막 등장인가
    local after="${index#*"$line"}"
    case $'\n'"$after" in
      *$'\n'*$'\t'"$key"$'\t'*) continue ;;
    esac
    case $'\n'"$seen" in *$'\n'"$key"$'\n'*) continue ;; esac
    seen="$seen$key"$'\n'
    out="$out$line"$'\n'
  done <<< "$index"
  [[ -n "$out" ]] && printf '%s' "$out"
  return 0
}

# journal_index_fields <레코드>
#
# 레코드를 개행 구분 필드로 낸다: 표시·키·파일·오프셋·길이·시각·요약.
# 부르는 쪽이 `read -r` 로 받아 쓴다.
# @pure
journal_index_fields() {
  local line="${1:-}"
  [[ -n "$line" ]] || return 0
  local IFS=$'\t'
  local -a f
  read -r -a f <<< "$line"
  local i
  for i in 0 1 2 3 4 5 6; do
    printf '%s\n' "${f[$i]:-}"
  done
}
