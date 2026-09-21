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
  # hits[] 는 graft 0.18 에서 실물로 확인한 모양이다 — pointer "경로:L12-L34", title "이름 · 종류".
  # results[] / nodes[] 는 그 전의 추정이며, 다른 판이 그 모양을 쓸 경우를 위해 남겨 둔다.
  def ptr_path: (. // "") | split(":") | .[0];
  def ptr_line: [ (. // "") | scan("L([0-9]+)") | .[0] ] | (.[0] // "0") | tonumber;
  def head_title: (. // "") | split(" \u00b7 ") | .[0];
  def rows:
    if (.hits? | type) == "array" then [ .hits[] | {p: (.path // (.pointer | ptr_path) // ""), l: (.line // (.pointer | ptr_line)), t: (.name // (.title | head_title) // ""), s: (.score // 0)} ]
    elif (.results? | type) == "array" then [ .results[] | {p: (.path // .file // ""), l: (.line // 0), t: (.label // .name // .symbol // ""), s: (.score // 0)} ]
    elif (.nodes? | type) == "array" then [ .nodes[] | {p: (.file // .path // ""), l: (.line // 0), t: (.name // .label // .symbol // ""), s: (.score // 0)} ]
    else [] end;
  rows | map(select(.p != "")) | sort_by([-.s, .p, .l]) | .[:$n] | .[] | "\(.p):\(.l)\u001f\(.t)"'

# ---------------------------------------------------------------- 안내 (0.55.0)
# Graft 가 없을 때 계획·구현 헤더에 한 줄로 알린다 — 무엇이 좋아지는지 + 설치 명령. 강제가 아니다:
# 묻지도 막지도 않는다. 이 저장소처럼 Graft 가 지원하지 않는 언어만 있는 프로젝트에서는 침묵한다
# (설치해도 빈 결과가 나오면 신뢰를 잃는다). 문구와 설치 명령은 여기 한 곳에만 있다(4조) —
# install-deps 와 프로토콜은 이 상수와 이 함수의 출력을 그대로 쓴다.

# 설치 명령 — install-deps.sh 도 이 상수를 찍는다. 두 곳에 각각 적지 않는다.
SCV_GRAFT_INSTALL_CMD='npm i -g @nanonets/graft && graft init --no-hooks --no-statusline && graft telemetry disable'
# 그래프만 없을 때(no-graph) 의 명령.
SCV_GRAFT_INIT_CMD='graft init --no-hooks --no-statusline'
# Graft 가 인덱싱하는 언어의 파일 확장자. 출처: github.com/nanonets/graft README (2026-09-21 확인, 23개 언어) —
# 확인법: README 의 세 층(완전·넓은·LSP) 중 앞 둘의 언어를 아래 두 줄과 대조한다 — LSP 층은 위 언어의 정밀도
# 옵션이라 새 언어를 더하지 않는다. 다를 때만 값을 고치고, 같으면 확인 날짜만 갱신한다.
# 완전 지원: TS/JS(JSX/TSX) · Python · Go · Java · Kotlin · PHP · Swift · R,
# 넓은 지원: Rust · C · C++ · C# · Ruby · Scala · Elixir · Solidity · OCaml · Zig · Dart · Clojure · Nix · Lua.
# 셸(bash)은 목록에 없다 — 이 저장소에서는 안내가 나오지 않는 것이 맞다. 목록이 낡으면 여기 한 줄만 고친다.
SCV_GRAFT_LANG_EXTS='ts tsx js jsx mjs cjs py go java kt kts php swift r R rs c h cpp cc cxx hpp hh cs rb scala ex exs sol ml mli zig dart clj cljs cljc nix lua'
# awk 프로그램은 함수 밖 상수 — 비교 연산자를 순수성 검사기가 리다이렉션으로 오해하지 않게.
_SCV_GRAFT_AWK_HIST='{ n=split($0, a, "/"); f=a[n]; d=index(f, "."); if (d==0) next; sub(/^.*\./, "", f); if (f=="") next; c[f]++ } END { for (e in c) print e "\t" c[e] }'

# @deterministic
# 표준입력: 파일 경로 한 줄에 하나 → "<확장자>\t<개수>" 줄들 (순서 불정). 확장자 없는 파일은 뺀다.
scv_graft_ext_histogram() {
  awk "$_SCV_GRAFT_AWK_HIST"
}

# @pure
# <히스토그램 텍스트> [지원 확장자 목록=SCV_GRAFT_LANG_EXTS] → 지원 언어 파일 수(정수).
scv_graft_supported_count() {
  local hist="${1:-}" exts=" ${2:-$SCV_GRAFT_LANG_EXTS} " ext n total=0
  while IFS=$'\t' read -r ext n; do
    [[ -n "$ext" && "$n" =~ ^[0-9]+$ ]] || continue
    [[ "$exts" == *" $ext "* ]] && total=$(( total + n ))
  done <<<"$hist"
  printf '%s' "$total"
}

# @pure
# <GRAFT_STATUS> <지원 언어 파일 수> → 안내 한 줄, 또는 빈 문자열. absent/no-graph 이고 지원 파일이 1개 이상일 때만.
scv_graft_notice() {
  local status="${1:-absent}" n="${2:-0}"
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  (( n > 0 )) || return 0
  case "$status" in
    absent)   printf 'Graft 가 있으면 계획·구현 헤더에 관련 코드 후보와 변경 영향 범위가 붙습니다 (이 저장소는 지원 언어 파일 %s개). 설치: %s' "$n" "$SCV_GRAFT_INSTALL_CMD" ;;
    no-graph) printf 'Graft 는 있지만 이 저장소에 그래프가 없습니다 — 만들면 계획·구현 헤더에 관련 코드 후보가 붙습니다 (지원 언어 파일 %s개). 실행: %s' "$n" "$SCV_GRAFT_INIT_CMD" ;;
    *) ;;
  esac
  return 0
}

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
