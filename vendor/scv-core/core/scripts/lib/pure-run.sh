#!/usr/bin/env bash
# lib/pure-run.sh — 셸이 아닌 사전 함수(TS/JS · 파이썬 · 러스트)를 서로의 예시 입력으로 실제로 돌려 중복을 가리는 순수부(0.95.0+).
#
# 왜: 사전 중복 검사는 셸 함수만 실제로 돌리고, 다른 언어는 작성자가 적은 예시 글끼리만 견줬다. 같은 일을 하는 두 함수에
# 서로 다른 예시를 달면 그대로 지나갔다 — 재사용을 확인하는 검사가 작성자의 손에 달려 있었다. 그래서 같은 언어 짝마다
# 한쪽 예시의 입력을 다른 쪽 함수에 넣어 보고, 두 방향 모두 상대가 적어 둔 출력과 같으면 중복으로 본다.
# 여기는 짝 고르기 · 실행 목록 · 판정만 한다. 실행(node · python3 · rustc)은 pure-run.sh(효과부)가 한다.
# 계획 20261117-wookiya1364-checks-not-comments 5단계.

# @pure
# 역할: 사전 파일 경로의 확장자로, 실제로 돌릴 수 있는 언어 이름(js · py · rs)을 낸다 — 못 돌리는 언어는 빈 값
# 종류: 판정
# 예: "src/a.ts" → "js"
# 예: "lib/b.mjs" → "js"
# 예: "app/c.py" → "py"
# 예: "src/d.rs" → "rs"
# 예: "x/e.go" → ""
scv_prun_lang() {
  case "${1:-}" in
    *.ts|*.tsx|*.mts|*.cts|*.js|*.mjs|*.cjs|*.jsx) printf 'js' ;;
    *.py) printf 'py' ;;
    *.rs) printf 'rs' ;;
    *) printf '' ;;
  esac
}

# @pure
# 역할: 예시 한 줄("입력 → 출력")의 입력 낱말 수를 센다 — 따옴표 안 공백은 한 낱말
# 종류: 세기
# 예: '"a b" 2 → "x"' → "2"
# 예: '1 → 2' → "1"
# 예: '→ 0' → "0"
scv_prun_argc() {
  local args="${1%%→*}" n=0 q="" c i word=0
  for (( i = 0; i < ${#args}; i++ )); do
    c="${args:i:1}"
    if [[ -n "$q" ]]; then [[ "$c" == "$q" ]] && q=""; continue; fi
    case "$c" in
      '"'|"'") q="$c"; (( word )) || { word=1; n=$(( n + 1 )); } ;;
      ' '|$'\t') word=0 ;;
      *) (( word )) || { word=1; n=$(( n + 1 )); } ;;
    esac
  done
  printf '%s' "$n"
}

_SCV_PRUN_AWK_PAIRS='NF == 2 { n[$1]++; key[$1, n[$1]] = $2 }
    END { for (k in n) for (i = 1; i <= n[k]; i++) for (j = i + 1; j <= n[k]; j++) print key[k, i] "\t" key[k, j] }'
_SCV_PRUN_AWK_VERDICT='NF == 3 {
      k = ($1 < $2) ? $1 "\t" $2 : $2 "\t" $1
      seen[k] = 1
      if ($3 == "err") { bad[k] = 1; un[$1] = 1 }
      else if ($3 != "ok") bad[k] = 1
      else ok[k, $1] = 1
    }
    END {
      for (k in seen) { split(k, p, "\t"); if (!(k in bad) && ok[k, p[1]] && ok[k, p[2]]) print "dup\t" k }
      for (u in un) print "unrun\t" u
    }'

# @deterministic
# 역할: 사전 항목들에서, 같은 언어로 돌릴 수 있고 첫 예시의 입력 낱말 수가 같은 함수 짝을 고른다
# 종류: 고르기
# 예: $'a.ts\tpure\tf\tr\t다듬기\t" a " → "a"\nb.ts\tpure\tg\tr\t다듬기\t"x " → "x"' → $'f\tg'
# 예: $'a.ts\tpure\tf\tr\t다듬기\t" a " → "a"\nb.py\tpure\tg\tr\t다듬기\t"x " → "x"' → ""
# 예: $'a.py\tpure\tf\tr\t세기\t1 2 → 3\nb.py\tpure\tg\tr\t세기\t"x" → 1' → ""
# <사전 항목 줄들(파일 · 층 · 이름 · 역할 · 종류 · 예시들)> → "가<탭>나" 줄들 | 빈 값.
scv_prun_pairs() {
  local line file tier name role kind exs lang argc rows="" a b
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    IFS=$'\x1d' read -r file tier name role kind exs <<< "${line//$'\t'/$'\x1d'}"
    lang="$(scv_prun_lang "$file")"; [[ -n "$lang" && -n "$name" && -n "$exs" ]] || continue
    argc="$(scv_prun_argc "${exs%%$'\x1f'*}")"
    rows+="$lang:$argc"$'\t'"$name"$'\n'
  done <<< "${1:-}"
  printf '%s' "$rows" | LC_ALL=C awk -F'\t' "$_SCV_PRUN_AWK_PAIRS" | LC_ALL=C sort
}

# @deterministic
# 역할: 실행 결과 줄들(부른 함수 · 예시 주인 · ok|diff|err)로, 두 방향 모두 상대 예시의 출력을 낸 짝과 돌리지 못한 함수를 가린다
# 종류: 판정
# 예: $'f\tg\tok\ng\tf\tok' → $'dup\tf\tg'
# 예: $'f\tg\tok\ng\tf\tdiff' → ""
# 예: $'f\tg\terr\ng\tf\tok' → $'unrun\tf'
# <"부른<탭>주인<탭>결과" 줄들> → "dup<탭>가<탭>나" · "unrun<탭>이름" 줄들 | 빈 값.
scv_prun_verdict() {
  printf '%s\n' "${1:-}" | LC_ALL=C awk -F'\t' "$_SCV_PRUN_AWK_VERDICT" | LC_ALL=C sort
}
