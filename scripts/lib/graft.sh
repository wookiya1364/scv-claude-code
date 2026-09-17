#!/usr/bin/env bash
# graft.sh (lib) — Graft 어댑터의 순수부 (v0.51.0+).
#
# 왜 있나: Graft(코드 그래프 엔진)는 "지금 코드가 무엇에 의존하는지" 를 안다 — 자체 그래프(이력)와 겹치지 않는다.
# 필수가 아닌 선택 제공자로 붙인다: 있으면 회귀 앞단에 정적 영향 범위(blast), 계획·구현 헤더에 관련 코드 후보(ask).
# 여기의 함수는 문자열만 받아 문자열만 낸다. graft 실행·PATH·파일은 scripts/graft.sh (효과부) 가 한다.
#
# 레코드 구분자는 단위 구분자(US, 0x1f).  blast 요약: "<files>US<symbols>US<path:count …>"  ·  ask 후보: "<path:line>US<label>" 줄들.

# jq 프로그램 — 함수 밖 상수(순수성 검사기는 함수 본문만 본다). Graft 의 JSON 스키마는 문서화돼 있지 않아
# 흔한 모양 둘을 받는다: files[]{path,symbols[]} · impacted[]{file,symbol} / results[]{path,line,label,score} · nodes[]{file,line,name,score}.
# 구분자는 jq 문자열 이스케이프(\u001f)로 적는다 — 소스 파일에 제어 문자를 넣지 않는다.
_SCV_GRAFT_JQ_BLAST='
  def per_file:
    if (.files? | type) == "array" then [ .files[] | {p: (.path // .file // ""), n: ((.symbols // .impacted // []) | length)} ]
    elif (.impacted? | type) == "array" then ([ .impacted[] | (.file // .path // "") ] | group_by(.) | map({p: .[0], n: length}))
    else null end;
  (per_file) as $pf
  | if $pf == null then (if (keys | length) == 0 then "0\u001f0\u001f" else "?\u001f?\u001f" + (tojson | length | tostring) + "B" end)
    else ($pf | map(select(.p != ""))) as $f
      | ($f | length | tostring) + "\u001f" + ($f | map(.n) | add // 0 | tostring) + "\u001f"
        + ($f | sort_by([-.n, .p]) | .[:10] | map("\(.p):\(.n)") | join(" "))
    end'
_SCV_GRAFT_JQ_ASK='
  def rows:
    if (.results? | type) == "array" then [ .results[] | {p: (.path // .file // ""), l: (.line // 0), t: (.label // .name // .symbol // ""), s: (.score // 0)} ]
    elif (.nodes? | type) == "array" then [ .nodes[] | {p: (.file // .path // ""), l: (.line // 0), t: (.name // .label // .symbol // ""), s: (.score // 0)} ]
    else [] end;
  rows | map(select(.p != "")) | sort_by([-.s, .p, .l]) | .[:$n] | .[] | "\(.p):\(.l)\u001f\(.t)"'

# @pure
# <graft 실행 파일 있음 0|1> <graft/ 그래프 있음 0|1> <스위치 auto|off|''> → absent | no-graph | ready | off
scv_graft_status() {
  local has_bin="${1:-0}" has_graph="${2:-0}" sw="${3:-auto}"
  sw="${sw//[[:space:]\"\']/}"
  if [[ "$sw" == [oO][fF][fF] ]]; then printf 'off'; return 0; fi   # bash 3.2 에는 ${var,,} 가 없다
  (( has_bin )) || { printf 'absent'; return 0; }
  (( has_graph )) || { printf 'no-graph'; return 0; }
  printf 'ready'
}

# @deterministic
# <blast JSON> → "files US symbols US top". 모르는 모양이면 "? US ? US <N>B", 빈 객체면 "0 US 0 US". 깨진 JSON 이면 빈 출력.
scv_graft_blast_summary() {
  local json="${1:-}"; [[ -n "$json" ]] || json="{}"
  printf '%s' "$json" | jq -r "$_SCV_GRAFT_JQ_BLAST" 2>/dev/null || true
}

# @deterministic
# <ask JSON> [n=10] → "path:line US label" 줄들, 점수 내림차순 상위 n. 후보 없음·깨진 JSON 이면 빈 출력.
scv_graft_ask_summary() {
  local json="${1:-}" n="${2:-10}"; [[ -n "$json" ]] || json="{}"
  [[ "$n" =~ ^[0-9]+$ ]] || n=10
  printf '%s' "$json" | jq -r --argjson n "$n" "$_SCV_GRAFT_JQ_ASK" 2>/dev/null || true
}

# @pure
# <blast 요약 레코드> → 사람이 읽을 줄들.
scv_graft_render_blast() {
  local rec="${1:-}" us=$'\x1f' files symbols top
  [[ -n "$rec" ]] || return 0
  IFS="$us" read -r files symbols top <<<"$rec"
  if [[ "$files" == "?" ]]; then printf '  요약 불가 — 원문 %s\n' "$top"; return 0; fi
  printf '  닿는 파일 %s · 심볼 %s\n' "$files" "$symbols"
  [[ -n "$top" ]] && printf '  상위: %s\n' "$top"
  return 0
}

# @pure
# <ask 후보 줄들> → 사람이 읽을 줄들. 없으면 "(후보 없음)".
scv_graft_render_ask() {
  local lines="${1:-}" us=$'\x1f' line pl label
  if [[ -z "${lines//[[:space:]]/}" ]]; then printf '  (후보 없음)\n'; return 0; fi
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    pl="${line%%"$us"*}"; label="${line#*"$us"}"
    printf '  %s — %s\n' "$pl" "$label"
  done <<<"$lines"
}
