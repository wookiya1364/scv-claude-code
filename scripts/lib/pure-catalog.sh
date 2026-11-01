#!/usr/bin/env bash
# lib/pure-catalog.sh — 순수함수 사전의 판정부. 글을 받아 글을 낸다.
#
# 계약: core/contracts/purity.md "사전 — 만들기 전에 찾아 재사용한다"
#
# 파일을 읽고 쓰는 일, 함수를 실제로 불러 보는 일은 scripts/pure-catalog.sh 가 맡는다.
# 여기 있는 것은 그 사이의 변환뿐이다:
#
#   pc_kinds_from_contract  계약 글   → 종류 표 (종류 · 파일 · 하는 일)
#   pc_extract_entries      스크립트  → 함수 항목 (파일 · 층 · 이름 · 역할 · 종류 · 예시)
#   pc_validate_entries     항목 + 종류 표 → 빈 칸 · 모르는 종류
#   pc_split_example        예시 한 줄 → 인자 · 기대 출력 · 기대 종료 코드
#   pc_duplicate_pairs      지문 줄들 → 지문이 같은 짝
#   pc_mutual_pairs         방향 있는 짝 → 양쪽 다 성립하는 짝
#   pc_lang_of              파일 경로 → 언어 표시(확장자)
#   pc_text_duplicates      항목들 → 예시 글이 같은 짝 + 같은/다른 언어
#   pc_allowed_filter       짝 + 예외 목록 → 남는 짝 · 이유 없는 예외
#   pc_render_catalog       항목 + 종류 표 → 사전 파일 글들
#   pc_oversize_files       사전 파일 글들 + 한도 → 한도를 넘은 파일
#
# 항목 한 줄은 탭으로 나뉜다: 파일 · 층 · 이름 · 역할 · 종류 · 예시들(\x1f 로 이음)
# bash 3.2 에서 돈다 — 연관 배열 · ${x,,} 같은 bash 4 기능을 쓰지 않는다.

PC_SEP=$'\x1f'

# awk 프로그램은 함수 밖에 둔다 — 비교 부등호가 순수 검사기의 리다이렉션 탐지에 걸리지
# 않게(다른 lib 과 같은 방식). awk 는 LC_ALL=C 로 부른다 — 맥 awk 는 en_US 같은 로캘에서
# 문자열 같음(==)을 strcoll 로 보아 서로 다른 한글을 같다고 한다(2026-11-01 맥 CI 에서 확인).

_PC_AWK_PC_KINDS_FROM_CONTRACT='
    /^\| 종류 \| 파일 \| 하는 일 \|/ { on = 1; next }
    on && /^\|---/ { next }
    on && /^\|/ {
      line = $0
      sub(/^\|[[:space:]]*/, "", line); sub(/[[:space:]]*\|[[:space:]]*$/, "", line)
      n = split(line, c, /[[:space:]]*\|[[:space:]]*/)
      if (n >= 3) printf "%s\t%s\t%s\n", c[1], c[2], c[3]
      next
    }
    on { exit }
'

_PC_AWK_PC_EXTRACT_ENTRIES='
    # 주석 앞머리를 떼고 본문을 낸다. 주석이 아니면 "\001". 언어 목록 없이 앞머리 모양만 안다:
    # # · // · /// · /* · * · */ · -- · ; · % · 작은따옴표(VB).
    function body(line,   v, re) {
      v = line
      re = "^[[:space:]]*(///?|/[*]+|[*]/|[*]|#+|--|;+|%+|\047)"
      if (!match(v, re)) return "\001"
      v = substr(v, RSTART + RLENGTH)
      sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
      return v
    }
    function reset() { tier = ""; name = ""; role = ""; kind = ""; ex = "" }
    function grab(v, key) {
      if (index(v, key ":") != 1) return ""
      v = substr(v, length(key) + 2)
      sub(/^[[:space:]]+/, "", v); sub(/[[:space:]]+$/, "", v)
      return v
    }
    function emit(n) { printf "%s\t%s\t%s\t%s\t%s\t%s\n", file, tier, n, role, kind, ex }
    BEGIN { reset() }
    {
      c = body($0)
      if (c != "\001") {
        if (c ~ /^@(pure|deterministic)([[:space:]]+[A-Za-z_][A-Za-z0-9_.:$-]*)?$/) {
          if (tier != "" && name != "") emit(name)
          reset()
          tier = (c ~ /^@pure/) ? "pure" : "deterministic"
          if (c ~ /[[:space:]]/) { name = c; sub(/^@[a-z]+[[:space:]]+/, "", name) }
          next
        }
        v = grab(c, "역할"); if (v != "") { role = v; next }
        v = grab(c, "종류"); if (v != "") { kind = v; next }
        v = grab(c, "예");   if (v != "") { ex = (ex == "" ? v : ex sep v); next }
        next
      }
      if ($0 ~ /^[[:space:]]*$/) { if (tier == "") reset(); next }
      if (tier != "" && name != "") { emit(name); reset(); next }
      if (tier != "" && $0 ~ /^[a-zA-Z_][a-zA-Z0-9_]*\(\)[[:space:]]*\{/) {
        n = $0; sub(/\(\).*/, "", n); gsub(/[[:space:]]/, "", n)
        emit(n)
      }
      reset()
    }
    END { if (tier != "" && name != "") emit(name) }
'

_PC_AWK_PC_RENDER_CATALOG='
    BEGIN {
      nk = split(ENVIRON["PC_KINDS"], kl, "\n")
      for (i = 1; i <= nk; i++) {
        if (kl[i] == "") continue
        split(kl[i], c, "\t"); slug[c[1]] = c[2]; desc[c[1]] = c[3]; order[++no] = c[1]
      }
      # 다른 언어 짝(같은 입출력을 언어마다 따로 두는 함수) — 서로의 항목에 적는다
      nt = split(ENVIRON["PC_TWINS"], tl, "\n")
      for (i = 1; i <= nt; i++) {
        if (tl[i] == "") continue
        split(tl[i], c, "\t")
        # 짝 줄은 "이름" 또는 "이름 (언어)" — 열쇠는 이름만
        ka = c[1]; sub(/ \(.*$/, "", ka); kb = c[2]; sub(/ \(.*$/, "", kb)
        twin[ka] = (ka in twin ? twin[ka] ", " : "") c[2]
        twin[kb] = (kb in twin ? twin[kb] ", " : "") c[1]
      }
    }
    NF >= 3 && $3 != "" {
      kind = $5; base = kind; sub_ = ""
      if (index(kind, "/") > 0) { base = substr(kind, 1, index(kind, "/") - 1); sub_ = substr(kind, index(kind, "/") + 1) }
      if (!(base in slug)) next
      f = slug[base] (sub_ != "" ? "-" sub_ : "") ".md"
      label = base (sub_ != "" ? "/" sub_ : "")
      if (!(f in cnt)) { files[++nf] = f; flabel[f] = label; fbase[f] = base }
      cnt[f]++
      lang = $1; sub(/^.*\//, "", lang); if (index(lang, ".") > 0) sub(/^.*\./, "", lang)
      body = "### " $3 "\n- 역할: " $4 "\n- 위치: " $1 " · @" $2 " · " lang
      if ($3 in twin) body = body "\n- 다른 언어 짝: " twin[$3]
      ne = split($6, exs, sep)
      for (j = 1; j <= ne; j++) body = body "\n- 예: `" exs[j] "`"
      rkey[f, cnt[f]] = $3; rbody[f, cnt[f]] = body
      total++
    }
    END {
      print "@@FILE INDEX.md"
      print "# 순수함수 사전 — 차례"
      print ""
      print "> 생성물 — 손으로 고치지 말 것. 다시 만들기: `bash core/scripts/pure-catalog.sh build`"
      print ">"
      print "> 새 함수를 만들기 전에: 아래에서 종류를 고르고, 그 종류 파일 하나만 연다."
      print ""
      print "| 종류 | 하는 일 | 개수 | 파일 |"
      print "|---|---|---|---|"
      for (o = 1; o <= no; o++) {
        # 같은 종류의 파일들을 파일 이름순으로
        m = 0
        for (i = 1; i <= nf; i++) if (fbase[files[i]] == order[o]) sel[++m] = files[i]
        for (a = 1; a <= m; a++) for (b = a + 1; b <= m; b++) if (sel[b] < sel[a]) { t = sel[a]; sel[a] = sel[b]; sel[b] = t }
        for (a = 1; a <= m; a++) printf "| %s | %s | %d | [%s](%s) |\n", flabel[sel[a]], ((flabel[sel[a]] in desc) ? desc[flabel[sel[a]]] : desc[order[o]]), cnt[sel[a]], sel[a], sel[a]
      }
      print ""
      printf "전체 %d개\n", total
      for (o = 1; o <= no; o++) {
        m = 0
        for (i = 1; i <= nf; i++) if (fbase[files[i]] == order[o]) sel[++m] = files[i]
        for (a = 1; a <= m; a++) for (b = a + 1; b <= m; b++) if (sel[b] < sel[a]) { t = sel[a]; sel[a] = sel[b]; sel[b] = t }
        for (a = 1; a <= m; a++) {
          f = sel[a]; n = cnt[f]
          for (x = 1; x <= n; x++) { key[x] = rkey[f, x]; val[x] = rbody[f, x] }
          for (x = 1; x <= n; x++) for (y = x + 1; y <= n; y++) if (key[y] < key[x]) { t = key[x]; key[x] = key[y]; key[y] = t; t = val[x]; val[x] = val[y]; val[y] = t }
          print "@@FILE " f
          printf "# %s — %s\n\n", flabel[f], ((flabel[f] in desc) ? desc[flabel[f]] : desc[order[o]])
          printf "> 생성물 — 원본은 각 함수 위 주석(역할 · 종류 · 예). %d개.\n", n
          for (x = 1; x <= n; x++) { print ""; print val[x] }
        }
      }
    }
'

_PC_AWK_PC_TEXT_DUPLICATES='
    # 줄: 이름 · 언어 · 입력 · 출력. 같은 (입력, 출력) 을 가진 이름들이 후보, 같은 입력에 다른 출력이 있으면 아님.
    NF >= 4 {
      if (!($1 in ord)) { ord[$1] = ++no; nm[no] = $1; lang[$1] = $2 }
      nr++; rn[nr] = $1; ra[nr] = $3; re[nr] = $4
      if ($3 != "" && $3 != "\047\047" && $3 != "\"\"") {
        k = $3 SUBSEP $4
        if (!((k, $1) in seen)) { seen[k, $1] = 1; bucket[k] = bucket[k] SUBSEP $1 }
      }
    }
    END {
      for (k in bucket) {
        m = split(substr(bucket[k], 2), bl, SUBSEP)
        for (x = 1; x <= m; x++) for (y = x + 1; y <= m; y++) {
          p = bl[x]; q = bl[y]
          if (ord[q] < ord[p]) { t = p; p = q; q = t }
          cand[p SUBSEP q] = 1
        }
      }
      for (i = 1; i <= nr; i++) for (j = 1; j <= nr; j++)
        if (rn[i] != rn[j] && ra[i] == ra[j] && re[i] != re[j]) {
          p = rn[i]; q = rn[j]
          if (ord[q] < ord[p]) { t = p; p = q; q = t }
          clash[p SUBSEP q] = 1
        }
      for (a = 1; a <= no; a++) for (b = a + 1; b <= no; b++) {
        pq = nm[a] SUBSEP nm[b]
        if ((pq in cand) && !(pq in clash))
          printf "%s\t%s\t%s\n", nm[a], nm[b], (lang[nm[a]] == lang[nm[b]] ? "same" : "cross")
      }
    }
'

_PC_AWK_PC_OVERSIZE_FILES='
    /^@@FILE / { if (f != "" && n > lim) printf "%s\t%d\n", f, n; f = substr($0, 8); n = 0; next }
    { n++ }
    END { if (f != "" && n > lim) printf "%s\t%d\n", f, n }
'

# @deterministic
# 역할: 계약 문서의 종류 표에서 종류 · 파일 이름 · 하는 일을 탭으로 뽑는다
# 종류: 꺼내기
# 예: <<< $'x\n| 종류 | 파일 | 하는 일 |\n|---|---|---|\n| 세기 | count | 센다 |\n\ny' → $'세기\tcount\t센다'
pc_kinds_from_contract() {
  LC_ALL=C awk "$_PC_AWK_PC_KINDS_FROM_CONTRACT"
}

# @deterministic
# 역할: 소스 글에서 표식(어떤 주석 모양이든 '@pure 이름', 셸은 이름 없이도) 달린 함수마다 역할 · 종류 · 예시를 뽑아 항목 줄로 낸다
# 종류: 꺼내기
# 예: "lib/a.sh" <<< $'# @pure\n# 역할: 센다\n# 종류: 세기\n# 예: "a" → "1"\nf() {\n}' → $'lib/a.sh\tpure\tf\t센다\t세기\t"a" → "1"'
# 예: "src/a.ts" <<< $'// @pure add\n// 역할: 더한다\n// 종류: 세기\n// 예: 1 2 → 3\nexport const add = (a, b) => a + b' → $'src/a.ts\tpure\tadd\t더한다\t세기\t1 2 → 3'
# 예: "A.java" <<< $'/**\n * @deterministic clamp\n * 역할: 범위로 자른다\n * 종류: 다듬기\n * 예: 5 0 3 → 3\n */\nint clamp(int v, int lo, int hi)' → $'A.java\tdeterministic\tclamp\t범위로 자른다\t다듬기\t5 0 3 → 3'
pc_extract_entries() {
  LC_ALL=C awk -v file="${1:-}" -v sep="$PC_SEP" "$_PC_AWK_PC_EXTRACT_ENTRIES"
}

# @pure
# 역할: 항목마다 빠진 칸(역할 · 종류 · 예)과 종류 표에 없는 종류를 위반 줄로 낸다
# 종류: 판정
# 예: $'a.sh\tpure\tf\t\t세기\tx' $'세기\tcount\t센다' → $'f\ta.sh\t역할 없음'
# 예: $'a.sh\tpure\tf\t센다\t뭐\tx' $'세기\tcount\t센다' → $'f\ta.sh\t모르는 종류: 뭐'
# 예: $'a.sh\tpure\tf\t센다\t세기/json\tx' $'세기\tcount\t센다' → ""
pc_validate_entries() {
  local entries="${1:-}" kinds="${2:-}" file tier name role kind ex base sub known k
  local line
  while IFS= read -r line; do
    IFS=$'\x1d' read -r file tier name role kind ex <<< "${line//$'\t'/$'\x1d'}"
    [[ -n "$name" ]] || continue
    [[ -n "$role" ]] || printf '%s\t%s\t역할 없음\n' "$name" "$file"
    [[ -n "$ex" ]]   || printf '%s\t%s\t예 없음\n' "$name" "$file"
    if [[ -z "$kind" ]]; then
      printf '%s\t%s\t종류 없음\n' "$name" "$file"; continue
    fi
    base="${kind%%/*}"; sub=""
    [[ "$kind" == */* ]] && sub="${kind#*/}"
    known=0
    while IFS=$'\t' read -r k _; do
      [[ "$k" == "$base" ]] && known=1
    done <<< "$kinds"
    if [[ $known -eq 0 ]]; then
      printf '%s\t%s\t모르는 종류: %s\n' "$name" "$file" "$kind"
    elif [[ -n "$sub" && ! "$sub" =~ ^[a-z0-9-]+$ ]]; then
      printf '%s\t%s\t세부 종류는 영문 소문자 · 숫자 · - 만: %s\n' "$name" "$file" "$sub"
    fi
  done <<< "$entries"
}

# @pure
# 역할: 예시 한 줄을 인자 · 기대 출력 · 기대 종료 코드 · 파이프 여부(1/0) 네 칸(탭)으로 나눈다
# 종류: 꺼내기
# 예: '"a" "b" → "ab"' → $'"a" "b"\t"ab"\t0\t0'
# 예: '"0.9" "1.0" → [1]' → $'"0.9" "1.0"\t\'\'\t1\t0'
# 예: '<<< "x" → "1" [2]' → $'<<< "x"\t"1"\t2\t0'
# 예: '"a|b" x | head → "a"' → $'"a|b" x | head\t"a"\t0\t1'
pc_split_example() {
  local ex="${1:-}" args expect status=0 i=0 n q="" c at=-1 pipe=0
  n=${#ex}
  # 따옴표 밖의 첫 → 가 경계다. 예시 글 자체에 → 가 들어 있어도 따옴표 안이면 건너뛴다.
  while [[ $i -lt $n ]]; do
    c="${ex:i:1}"
    case "$q" in
      s)  [[ "$c" == "'" ]] && q="" ;;
      d)  if [[ "$c" == '\' ]]; then i=$((i + 1)); elif [[ "$c" == '"' ]]; then q=""; fi ;;
      ds) if [[ "$c" == '\' ]]; then i=$((i + 1)); elif [[ "$c" == "'" ]]; then q=""; fi ;;
      *)
        if [[ "${ex:i}" == →* ]]; then at=$i; break
        elif [[ "$c" == "'" ]]; then q=s
        elif [[ "$c" == '"' ]]; then q=d
        elif [[ "$c" == '$' && "${ex:i+1:1}" == "'" ]]; then q=ds; i=$((i + 1))
        elif [[ "$c" == '\' ]]; then i=$((i + 1))
        elif [[ "$c" == '|' ]]; then pipe=1
        fi ;;
    esac
    i=$((i + 1))
  done
  [[ $at -ge 0 ]] || { printf '%s\t\t\n' "$ex"; return 1; }
  args="${ex:0:at}"; expect="${ex:at}"; expect="${expect#→}"
  args="${args%"${args##*[![:space:]]}"}"; args="${args#"${args%%[![:space:]]*}"}"
  expect="${expect%"${expect##*[![:space:]]}"}"; expect="${expect#"${expect%%[![:space:]]*}"}"
  if [[ "$expect" =~ ^(.*[^[:space:]])?[[:space:]]*\[(-?[0-9]+)\]$ ]]; then
    status="${BASH_REMATCH[2]}"; expect="${BASH_REMATCH[1]}"
  fi
  [[ -n "$expect" ]] || expect="''"
  printf '%s\t%s\t%s\t%s\n' "$args" "$expect" "$status" "$pipe"
}

# @pure
# 역할: '지문<탭>함수' 줄들에서 지문이 같은 함수 짝을 들어온 순서대로 낸다
# 종류: 고르기
# 예: $'k1\tb\nk2\tc\nk1\ta' → $'b\ta'
# 예: $'k1\ta\nk2\tb' → ""
pc_duplicate_pairs() {
  local lines="${1:-}" key name i j n=0 a b
  local -a keys=() names=()
  while IFS=$'\t' read -r key name; do
    [[ -n "$name" ]] || continue
    keys[n]="$key"; names[n]="$name"; n=$((n + 1))
  done <<< "$lines"
  for (( i = 0; i != n; i++ )); do
    for (( j = i + 1; j != n; j++ )); do
      [[ "${keys[i]}" == "${keys[j]}" ]] || continue
      a="${names[i]}"; b="${names[j]}"
      printf '%s\t%s\n' "$a" "$b"
    done
  done
}

# @pure
# 역할: 방향 있는 '가<탭>나' 줄들에서 양쪽 방향이 다 있는 짝만 한 번씩 낸다
# 종류: 고르기
# 예: $'a\tb\na\tc\nb\ta' → $'a\tb'
# 예: $'a\tb' → ""
pc_mutual_pairs() {
  local lines="${1:-}" x y i j n=0
  local -a xs=() ys=()
  while IFS=$'\t' read -r x y; do
    [[ -n "$y" ]] || continue
    xs[n]="$x"; ys[n]="$y"; n=$((n + 1))
  done <<< "$lines"
  for (( i = 0; i != n; i++ )); do
    for (( j = i + 1; j != n; j++ )); do
      [[ "${xs[j]}" == "${ys[i]}" && "${ys[j]}" == "${xs[i]}" ]] && printf '%s\t%s\n' "${xs[i]}" "${ys[i]}"
    done
  done
}

# @pure
# 역할: 파일 경로의 확장자로 언어 표시를 낸다 — 언어 목록 없이, 확장자가 없으면 파일 이름
# 종류: 꺼내기
# 예: "src/date.ts" → "ts"
# 예: "lib/a.b/Makefile" → "Makefile"
# 예: "x.tar.gz" → "gz"
pc_lang_of() {
  local f="${1##*/}"
  [[ "$f" == *.* ]] && f="${f##*.}"
  printf '%s' "$f"
}

# @deterministic
# 역할: 항목들의 예시를 글로 비교해, 같은 입력에 같은 출력인 예시를 공유하고 어긋남이 없는 함수 짝을 같은 언어(same) · 다른 언어(cross) 표시와 함께 낸다
# 종류: 고르기
# 예: $'a.ts\tpure\tfmt\tr\t변환\t"2026-01-02" → "26/01/02"\nb.py\tpure\tfmt_date\tr\t변환\t"2026-01-02" → "26/01/02"' → $'fmt\tfmt_date\tcross'
# 예: $'a.ts\tpure\tf\tr\t다듬기\t" a " → "a"\nb.ts\tpure\tg\tr\t다듬기\t" a " → "a"\x1f"b " → "B"\nc.rs\tpure\th\tr\t다듬기\t"b " → "b"' → $'f\tg\tsame'
# 빈 입력('' · "")만 같은 예시는 증거로 치지 않는다 — 빈 값에 빈 값을 내는 함수는 흔하다.
pc_text_duplicates() {
  local entries="${1:-}" line file tier name role kind exs ex split args expect st rows=""
  while IFS= read -r line; do
    IFS=$'\x1d' read -r file tier name role kind exs <<< "${line//$'\t'/$'\x1d'}"
    [[ -n "$name" && -n "$exs" ]] || continue
    while IFS= read -r ex; do
      [[ -n "$ex" ]] || continue
      split="$(pc_split_example "$ex")" || continue
      IFS=$'\x1d' read -r args expect st _ <<< "${split//$'\t'/$'\x1d'}"
      rows+="$name"$'\x1d'"$(pc_lang_of "$file")"$'\x1d'"$args"$'\x1d'"$expect [$st]"$'\n'
    done <<< "${exs//$PC_SEP/$'\n'}"
  done <<< "$entries"
  # 짝 찾기는 awk 한 번 — 함수 240개를 셸 반복으로 서로 견주면 몇 분이 걸렸다(2026-11-01).
  printf '%s' "$rows" | LC_ALL=C awk -F'\035' "$_PC_AWK_PC_TEXT_DUPLICATES"
}

# @pure
# 역할: 짝 목록에서 예외 목록에 이유와 함께 적힌 짝을 빼고, 이유 없는 예외는 따로 표시한다
# 종류: 고르기
# 예: $'a\tb\nc\td' $'b\ta\t줄바꿈 처리가 다름' → $'c\td'
# 예: $'a\tb' $'a\tb\t' → $'!이유없음\ta\tb\na\tb'
pc_allowed_filter() {
  local pairs="${1:-}" allowed="${2:-}" a b x y why ok
  local line
  while IFS= read -r line; do
    IFS=$'\x1d' read -r x y why <<< "${line//$'\t'/$'\x1d'}"
    [[ -n "$x" && "$x" != \#* ]] || continue
    [[ -n "${why// /}" ]] || printf '!이유없음\t%s\t%s\n' "$x" "$y"
  done <<< "$allowed"
  while IFS=$'\t' read -r a b; do
    [[ -n "$a" ]] || continue
    ok=0
    while IFS= read -r line; do
      IFS=$'\x1d' read -r x y why <<< "${line//$'\t'/$'\x1d'}"
      [[ -n "${why// /}" ]] || continue
      { [[ "$x" == "$a" && "$y" == "$b" ]] || [[ "$x" == "$b" && "$y" == "$a" ]]; } && ok=1
    done <<< "$allowed"
    [[ $ok -eq 1 ]] || printf '%s\t%s\n' "$a" "$b"
  done <<< "$pairs"
}

# @deterministic
# 역할: 항목 · 종류 표 · 다른 언어 짝으로 사전 파일들(차례 + 종류별)의 글을 만든다. 파일마다 '@@FILE 이름' 줄로 시작, 항목에 언어 표시
# 종류: 조립
# 예: $'lib/a.sh\tpure\tf\t센다\t세기\t"a" → "1"' $'세기\tcount\t센다' → $'@@FILE INDEX.md\n# 순수함수 사전 — 차례\n\n> 생성물 — 손으로 고치지 말 것. 다시 만들기: `bash core/scripts/pure-catalog.sh build`\n>\n> 새 함수를 만들기 전에: 아래에서 종류를 고르고, 그 종류 파일 하나만 연다.\n\n| 종류 | 하는 일 | 개수 | 파일 |\n|---|---|---|---|\n| 세기 | 센다 | 1 | [count.md](count.md) |\n\n전체 1개\n@@FILE count.md\n# 세기 — 센다\n\n> 생성물 — 원본은 각 함수 위 주석(역할 · 종류 · 예). 1개.\n\n### f\n- 역할: 센다\n- 위치: lib/a.sh · @pure · sh\n- 예: `"a" → "1"`'
pc_render_catalog() {
  local entries="${1:-}" kinds="${2:-}" twins="${3:-}"
  printf '%s\n' "$entries" | PC_KINDS="$kinds" PC_TWINS="$twins" LC_ALL=C awk -F'\t' -v sep="$PC_SEP" "$_PC_AWK_PC_RENDER_CATALOG"
}

# @deterministic
# 역할: 사전 파일 글들에서 줄 수가 한도를 넘는 파일 이름과 줄 수를 낸다
# 종류: 고르기
# 예: $'@@FILE a.md\n1\n2\n3\n@@FILE b.md\n1' "2" → $'a.md\t3'
pc_oversize_files() {
  printf '%s\n' "${1:-}" | LC_ALL=C awk -v lim="${2:-400}" "$_PC_AWK_PC_OVERSIZE_FILES"
}
