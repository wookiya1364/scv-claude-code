#!/usr/bin/env bash
# graph.sh (lib) — SCV 자체 그래프의 순수부 (v0.51.0+).
#
# 왜 있나: 계획서의 "전체 구조" 그림과 수정 범위 조회에 필요한 그래프를 외부 스킬 없이,
# SCV 가 이미 가진 재료만으로 만든다 — 문서의 링크, 보관된 계획이 건드린 파일, 결정 로그의
# 참조, 같은 계획에서 함께 바뀐 파일 쌍. 여기의 함수는 문자열만 받아 문자열만 낸다.
# 파일 읽기·쓰기·시각은 scripts/graph.sh (효과부) 가 한다.
#
# 레코드 구분자는 \x1f (단위 구분자). 줄 하나가 레코드 하나.
#   links    : "<doc>\x1f<target>"
#   touches  : "<slug>\x1f<epic>\x1f<title>\x1f<active 0|1>\x1f<files, 공백 구분>"
#   refs     : "<decision title>\x1f<plan slug>"
#   cochange : "<a>\x1f<b>\x1f<weight>\x1f<evidence slugs, 공백 구분>"
#
# graph.json (version 1):
#   { version, built_at, sources:{docs,plans,decisions},
#     nodes:[{id,label,kind:doc|file|plan|decision,community,degree,missing?,active?,epic?}],
#     links:[{source,target,kind:link|touches|refers|cochange,weight,evidence:[]}],
#     god_nodes:[id…], communities:{label:[id…]} }

# 함수 밖의 상수 — 순수성 검사기는 함수 본문만 보므로, 리다이렉션처럼 보이는 문자와 jq 프로그램은 여기에 둔다.
_SCV_GRAPH_ANGLES=$'\x3c\x3e'   # "<>" — 자리표시자·글롭 문자 집합의 일부

# @pure
# 경로 문자열 정규화 — "./" 와 "a/../" 를 접는다. 선행 "/" 는 유지하지 않는다(저장소 상대 경로만 다룬다).
scv_graph_normpath() {
  local p="${1:-}" seg out=() IFS='/'
  read -r -a segs <<<"$p"
  for seg in "${segs[@]}"; do
    case "$seg" in
      ''|'.') ;;
      '..') (( ${#out[@]} )) && unset 'out[${#out[@]}-1]' ;;
      *) out+=("$seg") ;;
    esac
  done
  local IFS='/'; printf '%s' "${out[*]}"
}

# @pure
# 토큰 하나가 저장소 상대 파일 경로처럼 보이는가. need_slash=1 이면 슬래시가 있어야 한다.
#   제외: URL(://) · 절대 경로 · 글롭·자리표시자(*<>{}) · 확장자 없음 · 확장자가 숫자로 시작(버전)
scv_graph_is_path() {
  local t="${1:-}" need_slash="${2:-0}"
  t="${t#./}"
  [[ -n "$t" ]] || return 1
  [[ "$t" == *"://"* || "$t" == /* ]] && return 1
  local bad='*{} '"$_SCV_GRAPH_ANGLES"
  [[ "$t" == *["$bad"]* ]] && return 1
  local re_path='^[A-Za-z0-9_@.+~-]+(/[A-Za-z0-9_@.+~-]+)*\.[A-Za-z][A-Za-z0-9]{0,7}$'
  [[ "$t" =~ $re_path ]] || return 1
  (( need_slash )) && [[ "$t" != */* ]] && return 1
  return 0
}

# @pure
# <문서 경로> <마크다운 본문> → "doc\x1ftarget" 줄들. 상대 .md 링크만, 앵커·URL·이미지·절대 경로 제외.
scv_graph_doc_links() {
  local doc="${1:-}" s="${2:-}" us=$'\x1f' dir prefix target rest
  dir="${doc%/*}"; [[ "$dir" == "$doc" ]] && dir="."
  local re_link='^(.*)\]\(([^)]*)\)(.*)$' re_img='!\[[^]]*$' line
  # 줄 단위로 본다 — 문서 전체에 탐욕 정규식을 반복하면 문서 길이의 제곱으로 느려진다.
  while IFS= read -r line; do
    [[ "$line" == *"]("* ]] || continue
    s="$line"
    while [[ "$s" =~ $re_link ]]; do
      prefix="${BASH_REMATCH[1]}"; target="${BASH_REMATCH[2]}"; s="$prefix"
      [[ "$prefix" =~ $re_img ]] && continue                        # 이미지
      target="${target%%#*}"; target="${target%% *}"                # 앵커 · "path title" 제목
      [[ -n "$target" ]] || continue
      [[ "$target" == *"://"* || "$target" == mailto:* || "$target" == /* ]] && continue
      [[ "$target" == *.md ]] || continue
      printf '%s%s%s\n' "$doc" "$us" "$(scv_graph_normpath "$dir/$target")"
    done
  done <<<"$s"
}

# awk — PLAN.md 본문에서 관심 있는 것만 레코드로 뽑는다 (한 프로세스, C 속도). 함수 밖 상수(순수성 검사기).
#   T<us>title · E<us>epic · S<us>scope 항목 · B<us>백틱 토큰
_SCV_GRAPH_AWK_PLAN='
  BEGIN { fm=0; inscope=0; cur="" }
  FNR==1 && FILENAME != "" && FILENAME != "-" { fm=0; inscope=0; printf "F%s%s\n", us, FILENAME }
  /^---$/ { fm++; next }
  fm==1 {
    if ($0 ~ /^title:/) { t=$0; sub(/^title:[ \t]*/, "", t); sub(/^"/, "", t); sub(/"[ \t]*$/, "", t); printf "T%s%s\n", us, t; inscope=0; next }
    if ($0 ~ /^epic:/)  { e=$0; sub(/^epic:[ \t]*/, "", e); sub(/[ \t#].*$/, "", e); printf "E%s%s\n", us, e; inscope=0; next }
    if ($0 ~ /^scope:/) { inscope=1; next }
    if ($0 ~ /^[ \t]*- / && inscope) { it=$0; sub(/^[ \t]*- [ \t]*/, "", it); sub(/^"/, "", it); sub(/"[ \t]*$/, "", it); sub(/[ \t]*#.*$/, "", it); printf "S%s%s\n", us, it; next }
    if ($0 ~ /^[A-Za-z_]+:/) { inscope=0 }
    next
  }
  fm>=2 && index($0, "`") {
    line=$0
    while ((i=index(line, "`")) != 0) {
      rest=substr(line, i+1); j=index(rest, "`"); if (j==0) break
      printf "B%s%s\n", us, substr(rest, 1, j-1); line=substr(rest, j+1)
    }
  }'

# @deterministic
# <슬러그> <PLAN.md 본문> → "slug\x1fepic\x1ftitle\x1ffiles". files 는 공백 구분, 첫 등장 순서, 중복 제거
# (정렬은 그래프를 만드는 jq 가 한다). frontmatter scope: 항목 — 토큰 중 경로 모양(확장자 필요, 슬래시 불필요)만.
# 본문 백틱 안 — 슬래시 있는 경로만. awk 한 번 + 토큰 검증만 셸에서 — 계획마다 줄 단위 셸 루프를 돌면 1초가 넘는다.
scv_graph_plan_touches() {
  local slug="${1:-}" text="${2:-}" us=$'\x1f' recs
  recs="$(printf '%s\n' "$text" | awk -v us="$us" "$_SCV_GRAPH_AWK_PLAN")"
  scv_graph_plan_records "$slug" "$recs"
}

# @pure
# <슬러그> <awk 레코드들(T/E/S/B)> → "slug\x1fepic\x1ftitle\x1ffiles" — 토큰 검증과 중복 제거만 한다.
scv_graph_plan_records() {
  local slug="${1:-}" recs="${2:-}" us=$'\x1f' rec kind val tok title="" epic=""
  local -a files=() uniq=()
  while IFS= read -r rec; do
    [[ -n "$rec" ]] || continue
    kind="${rec%%"$us"*}"; val="${rec#*"$us"}"
    case "$kind" in
      T) title="$val" ;;
      E) epic="$val" ;;
      S) for tok in $val; do
           tok="${tok%%[·,;:]}"; tok="${tok#\`}"; tok="${tok%\`}"; tok="${tok%\)}"; tok="${tok#\(}"
           scv_graph_is_path "$tok" 0 && files+=("${tok#./}")
         done ;;
      B) scv_graph_is_path "$val" 1 && files+=("${val#./}") ;;
    esac
  done <<<"$recs"
  local f
  for f in "${files[@]}"; do
    [[ -n "$f" ]] || continue
    [[ " ${uniq[*]} " == *" $f "* ]] && continue
    uniq+=("$f")
  done
  printf '%s%s%s%s%s%s%s' "$slug" "$us" "$epic" "$us" "$title" "$us" "${uniq[*]}"
}

# @pure
# 여러 계획의 awk 레코드(F<us>path 로 경계) → touches 줄들 "slug\x1fepic\x1ftitle\x1factive\x1ffiles".
# active 는 경로에 /promote/ 가 있으면 1. 한 번의 awk 로 55개 계획을 처리하려고 있다.
scv_graph_plans_batch() {
  local recs="${1:-}" us=$'\x1f' rec cur="" buf="" slug active line
  emit() {
    [[ -n "$cur" ]] || return 0
    slug="${cur%/PLAN.md}"; slug="${slug##*/}"; active=0; [[ "$cur" == */promote/* ]] && active=1
    line="$(scv_graph_plan_records "$slug" "$buf")"
    printf '%s%s%s%s%s\n' "${line%"$us"*}" "$us" "$active" "$us" "${line##*"$us"}"
  }
  while IFS= read -r rec; do
    if [[ "$rec" == F"$us"* ]]; then emit; cur="${rec#F"$us"}"; buf=""; continue; fi
    buf+="$rec"$'\n'
  done <<<"$recs"
  emit
  unset -f emit
}

# @pure
# <DECISIONS.md 본문> → "decision title\x1fplan slug" 줄들. 제목은 "## [시각] 작성자 — 제목" 의 제목.
scv_graph_decision_refs() {
  local text="${1:-}" us=$'\x1f' line title="" rest
  while IFS= read -r line; do
    if [[ "$line" == "## ["* ]]; then
      title="${line#\#\# }"; [[ "$title" == *" — "* ]] && title="${title#* — }"
      continue
    fi
    [[ "$line" == "- refs:"* ]] || continue
    rest="${line#- refs:}"
    local re_ref='scv/(archive|promote)/([^/[:space:],]+)/PLAN\.md(.*)$'
    while [[ "$rest" =~ $re_ref ]]; do
      [[ -n "$title" ]] && printf '%s%s%s\n' "$title" "$us" "${BASH_REMATCH[2]}"
      rest="${BASH_REMATCH[3]}"
    done
  done <<<"$text"
}

# @pure
# <kind> <id> [epic] → 군집 라벨. 파일·문서는 상위 두 폴더, 계획은 epic 아니면 슬러그 연월(YYYY-MM), 결정은 "decisions".
scv_graph_community() {
  local kind="${1:-}" id="${2:-}" epic="${3:-}" a b
  case "$kind" in
    plan)
      [[ -n "$epic" ]] && { printf '%s' "$epic"; return 0; }
      [[ "$id" =~ ^([0-9]{4})([0-9]{2}) ]] && { printf '%s-%s' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"; return 0; }
      printf 'plans' ;;
    decision) printf 'decisions' ;;
    *)
      if [[ "$id" == */*/* ]]; then a="${id%%/*}"; b="${id#*/}"; b="${b%%/*}"; printf '%s/%s' "$a" "$b"
      elif [[ "$id" == */* ]]; then printf '%s' "${id%%/*}"
      else printf '.'; fi ;;
  esac
}

# jq 공용 — 동시변경: [{slug, files:[…]}] → [{a,b,weight,evidence:[slug…]}] (a<b, 정렬)
_SCV_GRAPH_JQ_COCHANGE='
  def cochange: [ .[] as $p | ($p.files | unique) as $f
                  | range(0; $f|length) as $i | range($i+1; $f|length) as $j
                  | {a: $f[$i], b: $f[$j], slug: $p.slug} ]
                | group_by([.a,.b]) | map({a: .[0].a, b: .[0].b, weight: length, evidence: (map(.slug)|unique)})
                | sort_by([.a,.b]);'

_SCV_GRAPH_JQ_COCHANGE_MAIN='
    [ split("\n")[] | select(length>0) | split($us) | {slug: .[0], files: (.[-1] | split(" ") | map(select(length>0)))} ]
    | cochange | .[] | [.a, .b, (.weight|tostring), (.evidence|join(" "))] | join($us)'

# @deterministic
# touches 줄들("slug\x1f…\x1ffiles" 또는 "slug\x1ffiles") → cochange 줄들.
scv_graph_cochange() {
  local text="${1:-}"
  printf '%s\n' "$text" | jq -Rrs --arg us $'\x1f' "$_SCV_GRAPH_JQ_COCHANGE""$_SCV_GRAPH_JQ_COCHANGE_MAIN"
}

_SCV_GRAPH_JQ_GOD='
    ( [ (.links // [])[] | .source, .target ] | group_by(.) | map({key: .[0], value: length}) | from_entries ) as $d
    | [ (.nodes // [])[] | {id: .id, degree: ($d[.id] // 0)} ]
    | sort_by([-.degree, .id]) | .[:$n] | .[] | .id'

# @deterministic
# <graph json> [n=10] → 차수 내림차순·동률 id 순 상위 n 개 id, 한 줄에 하나.
scv_graph_god_nodes() {
  local json="${1:-}" n="${2:-10}"; [[ -n "$json" ]] || json="{}"
  printf '%s' "$json" | jq -r --argjson n "$n" "$_SCV_GRAPH_JQ_GOD"
}

_SCV_GRAPH_JQ_BUILD='
    def lines($s): [ $s | split("\n")[] | select(length>0) ];
    def comm(kind; id; epic):
      if kind=="plan" then (if epic != "" then epic elif (id|test("^[0-9]{6}")) then (id[0:4]+"-"+id[4:6]) else "plans" end)
      elif kind=="decision" then "decisions"
      else (id | split("/") | if length>=3 then (.[0]+"/"+.[1]) elif length==2 then .[0] else "." end) end;
    (lines($links)   | map(split($us) | {doc: .[0], target: .[1]}))                                   as $L
    | (lines($touches) | map(split($us) | {slug: .[0], epic: .[1], title: .[2], active: (.[3]=="1"),
                                          files: (.[4] // "" | split(" ") | map(select(length>0)))})) as $T
    | (lines($refs)    | map(split($us) | {decision: .[0], slug: .[1]}))                              as $R
    | (lines($exists)  | map({key: ., value: true}) | from_entries)                                   as $E
    | (lines($docs))                                                                                  as $D
    | ($T | cochange)                                                                                 as $C
    | ( [ $D[] | {id: ., kind: "doc"} ]
      + [ $L[] | .target | {id: ., kind: (if endswith(".md") then "doc" else "file" end)} ]
      + [ $T[] | .files[] | {id: ., kind: "file"} ]
      + [ $T[] | {id: .slug, kind: "plan", label: .title, epic: .epic, active: .active} ]
      + [ $R[] | {id: ("decision:" + .decision), kind: "decision", label: .decision} ] )
      | group_by(.id) | map( (map(select(.kind=="plan" or .kind=="decision")) | .[0]) // .[0] )        as $N0
    | ( [ $L[] | {source: .doc, target: .target, kind: "link", weight: 1, evidence: []} ]
      + [ $T[] | .slug as $s | .files[] | {source: $s, target: ., kind: "touches", weight: 1, evidence: []} ]
      + [ $R[] | {source: ("decision:" + .decision), target: .slug, kind: "refers", weight: 1, evidence: []} ]
      + [ $C[] | {source: .a, target: .b, kind: "cochange", weight: .weight, evidence: .evidence} ] )
      | unique_by([.kind, .source, .target]) | sort_by([.kind, .source, .target])                      as $LINKS
    | ( [ $LINKS[] | .source, .target ] | group_by(.) | map({key: .[0], value: length}) | from_entries ) as $DEG
    | ( $N0 | map( .id as $id
          | . + {community: comm(.kind; $id; (.epic // "")),
                 degree: ($DEG[$id] // 0)}
          | if (.kind=="file" or .kind=="doc") and ($E[$id] != true) then . + {missing: true} else . end
          | if .label == null then . + {label: $id} else . end )
        | sort_by(.id) )                                                                               as $NODES
    | { version: 1, built_at: $built_at,
        sources: { docs: $globs, plans: ($T|length), decisions: ($R | map(.decision) | unique | length) },
        nodes: $NODES, links: $LINKS,
        god_nodes: ($NODES | sort_by([-.degree, .id]) | .[:10] | map(.id)),
        communities: ($NODES | group_by(.community) | map({key: .[0].community, value: (map(.id)|sort)}) | from_entries) }'

# @deterministic
# <links> <touches> <refs> <exists 줄들> <docs 줄들> <docs globs> <built_at> → graph.json 텍스트.
scv_graph_build() {
  local links="${1:-}" touches="${2:-}" refs="${3:-}" exists="${4:-}" docs="${5:-}" globs="${6:-}" built_at="${7:-}"
  jq -cn --arg us $'\x1f' --arg links "$links" --arg touches "$touches" --arg refs "$refs" \
        --arg exists "$exists" --arg docs "$docs" --arg globs "$globs" --arg built_at "$built_at" "$_SCV_GRAPH_JQ_COCHANGE""$_SCV_GRAPH_JQ_BUILD"
}

_SCV_GRAPH_JQ_REPORT='
    "# SCV graph report",
    "",
    "Built: \(.built_at) · nodes \(.nodes|length) · links \(.links|length)",
    "",
    "## Sources",
    "",
    "- docs: \(.sources.docs)",
    "- plans: \(.sources.plans) · decisions: \(.sources.decisions)",
    "",
    "## Communities",
    "",
    ( .communities | to_entries | sort_by(-(.value|length), .key) | .[] | "- \(.key) (\(.value|length)): \(.value[:6] | join(", "))\(if (.value|length) > 6 then ", …" else "" end)" ),
    "",
    "## God Nodes",
    "",
    ( .nodes as $n | .god_nodes | to_entries[] | .value as $id | "\(.key+1). `\($id)` — \( ([$n[] | select(.id==$id) | .degree] | .[0]) // 0 ) edges (\( ([$n[] | select(.id==$id) | .kind] | .[0]) // "?" ))" ),
    "",
    "## Co-change pairs",
    "",
    ( [ .links[] | select(.kind=="cochange") ] | sort_by([-.weight, .source, .target]) | .[:20] | .[] | "- `\(.source)` ↔ `\(.target)` ×\(.weight) (\(.evidence|join(", ")))" ),
    "",
    "## Missing paths",
    "",
    ( [ .nodes[] | select(.missing==true) | .id ] | if length==0 then "- (none)" else .[] | "- \(.)" end )
  '

# @deterministic
# <graph json> → GRAPH_REPORT.md 텍스트.
scv_graph_report() {
  local json="${1:-}"; [[ -n "$json" ]] || json="{}"
  printf '%s' "$json" | jq -r "$_SCV_GRAPH_JQ_REPORT"
}

_SCV_GRAPH_JQ_NONEMPTY='select(length>0)'

_SCV_GRAPH_JQ_IMPACT='
    . as $g
    | [ $paths[] | . as $p
        | ($g.nodes | map(select(.id==$p)) | .[0]) as $node
        | { path: $p, known: ($node != null),
            cochange: ([ $g.links[] | select(.kind=="cochange" and (.source==$p or .target==$p))
                         | {id: (if .source==$p then .target else .source end), weight, evidence} ]
                       | map(select(.id as $n | ($g.nodes[] | select(.id==$n) | .missing) != true))
                       | sort_by([-.weight, .id])),
            plans: ([ $g.links[] | select(.kind=="touches" and .target==$p) | .source ] | unique
                    | map(. as $s | ($g.nodes[] | select(.id==$s)) | {id, title: .label, active: (.active // false)})),
            docs: ([ $g.links[] | select(.kind=="link" and (.source==$p or .target==$p))
                     | (if .source==$p then .target else .source end) ] | unique) }
        | .decisions = ([ .plans[].id ] as $ps | [ $g.links[] | select(.kind=="refers" and (.target as $t | $ps | index($t))) | .source | ltrimstr("decision:") ] | unique) ]
    | if $mode == "json" then tojson
      else .[] |
        if (.known|not) and (.cochange|length)==0 and (.plans|length)==0 and (.docs|length)==0 then "▸ \(.path) — 근거 없음"
        else
          "▸ \(.path)",
          "  함께 바뀜: " + (if (.cochange|length)==0 then "(없음)" else (.cochange | map("\(.id) ×\(.weight) (\(.evidence|join(" ")))") | join(" · ")) end),
          "  계획: " + (if (.plans|length)==0 then "(없음)" else (.plans | map("\(.id) (\(.title)\(if .active then ", active" else "" end))") | join(" · ")) end),
          "  결정: " + (if (.decisions|length)==0 then "(없음)" else (.decisions | join(" · ")) end),
          "  문서: " + (if (.docs|length)==0 then "(없음)" else (.docs | join(" · ")) end)
        end
      end'

# @deterministic
# <graph json> <text|json> <path…> → 영향 조회. 텍스트는 경로마다 한 블록, 모르는 경로는 "근거 없음".
scv_graph_impact() {
  local json="${1:-}" mode="${2:-text}"; shift 2 || true; [[ -n "$json" ]] || json="{}"
  local paths_json
  paths_json="$(printf '%s\n' "$@" | jq -R "$_SCV_GRAPH_JQ_NONEMPTY" | jq -s '.')"
  printf '%s' "$json" | jq -r --argjson paths "$paths_json" --arg mode "$mode" "$_SCV_GRAPH_JQ_IMPACT"
}

# @pure
# <graph 존재 0|1> <graph mtime> <재료 최신 mtime> → missing | stale | built
scv_graph_status_of() {
  local exists="${1:-0}" gm="${2:-0}" sm="${3:-0}"
  (( exists )) || { printf 'missing'; return 0; }
  [[ "$gm" =~ ^[0-9]+$ ]] || gm=0; [[ "$sm" =~ ^[0-9]+$ ]] || sm=0
  if (( gm >= sm )); then printf 'built'; else printf 'stale'; fi
}
