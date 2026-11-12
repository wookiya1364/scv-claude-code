#!/usr/bin/env bash
# lib/pipe-arrange.sh — 엮음 고르기 명령(pipe-arrange.sh)의 순수 함수.
# 계약 contracts/composition.md · 계획 20261112-wookiya1364-pipe-arrange.
#
# 줄 단위로 흘려보내는 단계들의 순서를, 단계마다 한 번 잰 값(걸린 시간 · 통과 비율)으로 계산한다.
# 이론: 고르는 단계는 "(통과 비율 − 1) ÷ 걸린 시간"이 작은 것부터 놓는다(순서 정하기의 비율 규칙 — 단계들이
# 서로 독립일 때 증명된 결과). 엮음의 예상 시간 = Σ 단계 시간 × 그 단계까지 살아남은 줄의 비율.
#
# 줄 모양
#   단계 줄:  이름<탭>종류<탭>명령<탭>뒤        종류: map(바꾸기) · filter(고르기) · head(앞의 N줄) · collect(모아야 하는 단계)
#             뒤: 이 단계가 그 뒤에 있어야 하는 단계의 이름(after 선언), 없으면 "-" (빈 칸은 두지 않는다 — 탭이 겹치면 칸이 접힌다)
#   잰 줄:    단계 줄<탭>걸린 시간(초)<탭>통과 비율
# head 와 collect 는 넘지 않는 벽이다. 순서는 벽 사이의 구간 안에서만 바꾼다.
#
# 이 파일의 함수는 lib/pure-bench.sh 의 pb_to_milli 를 쓴다 — 부르는 쪽이 먼저 읽어 둔다.

# @pure
# 역할: 단계 글(한 줄에 "이름<탭>종류<탭>명령[<탭>after:이름]")을 단계 줄들로 가린다 — 빈 줄과 # 줄은 버리고, 틀린 줄이 있으면 "오류: …" 한 줄과 1
# 종류: 꺼내기/arrange
# 예: $'# 주석\nup\tmap\ttr a-z A-Z\n\nkeep\tfilter\tgrep 7\tafter:up' → $'up\tmap\ttr a-z A-Z\t-\nkeep\tfilter\tgrep 7\tup'
# 예: $'top\thead\t100' → $'top\thead\t100\t-'
# 예: $'up\tmop\ttr a b' → "오류: 2번째 칸은 map · filter · head · collect 가운데 하나여야 한다 — up" [1]
# 예: $'a\tmap\tcat\na\tfilter\tgrep x' → "오류: 이름이 겹친다 — a" [1]
# 예: $'top\thead\t많이' → "오류: head 의 3번째 칸은 줄 수(숫자)여야 한다 — top" [1]
# 예: $'k\tfilter\tgrep x\tafter:없는것' → "오류: after 가 가리키는 단계가 없다 — k" [1]
pa_parse_steps() {
  local line name kind cmd extra after out="" names=" " TAB=$'\t'
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "${line//[[:space:]]/}" && "${line#"${line%%[![:space:]]*}"}" != "#"* ]] || continue
    name="${line%%"$TAB"*}"; line="${line#*"$TAB"}"
    kind="${line%%"$TAB"*}"; line="${line#*"$TAB"}"
    cmd="${line%%"$TAB"*}"; extra=""; [[ "$line" != *"$TAB"* ]] || extra="${line#*"$TAB"}"
    case "$kind" in map|filter|head|collect) ;; *) printf '오류: 2번째 칸은 map · filter · head · collect 가운데 하나여야 한다 — %s' "$name"; return 1 ;; esac
    [[ -n "$name" && "$name" != *" "* && -n "$cmd" ]] || { printf '오류: 이름(빈칸 없이) · 종류 · 명령 세 칸이 있어야 한다 — %s' "${name:-?}"; return 1; }
    [[ "$names" != *" $name "* ]] || { printf '오류: 이름이 겹친다 — %s' "$name"; return 1; }
    [[ "$kind" != head || "$cmd" =~ ^[0-9]+$ ]] || { printf '오류: head 의 3번째 칸은 줄 수(숫자)여야 한다 — %s' "$name"; return 1; }
    after="-"
    if [[ "$extra" == after:* ]]; then
      after="${extra#after:}"
      [[ "$names" == *" $after "* ]] || { printf '오류: after 가 가리키는 단계가 없다 — %s' "$name"; return 1; }
    fi
    names+="$name "
    out+="${out:+$'\n'}$name$TAB$kind$TAB$cmd$TAB$after"
  done <<< "${1:-}"
  printf '%s' "$out"
}

# @pure
# 역할: 한 단계의 순위 값 "(통과 비율 − 1) ÷ 걸린 시간"을 천 배 한 정수로 낸다 — 작을수록 앞에 놓는다(시간이 0이면 0.001초로 본다)
# 종류: 세기/arrange
# 예: 0.030 0.41 → "-19666"
# 예: 0.134 1.00 → "0"
# 예: 0 0.5 → "-500000"
# 예: 0.5 1.20 → "400"
# 예: x 1 → "0"
pa_rank() {
  local c r
  c="$(pb_to_milli "${1:-}")" && r="$(pb_to_milli "${2:-}")" || { printf '0'; return 0; }
  [[ $c -ne 0 ]] || c=1
  printf '%s' "$(( (r - 1000) * 1000 / c ))"
}

# @pure
# 역할: 잰 줄들에서 더 빠를 순서를 이름 한 줄씩 낸다 — 벽(head · collect) 사이 구간마다, 놓을 수 있는 단계 가운데 순위 값이 가장 작은 것부터. 바꾸기끼리의 순서와 after 선언은 지킨다. 둘째 인자가 mild 면 바꾸기도 벽으로 본다(이어진 고르기끼리만 바꾼다)
# 종류: 고르기/arrange
# 예: $'up\tmap\tA\t-\t0.134\t1.00\ntag\tmap\tB\t-\t0.083\t1.00\nkeep\tfilter\tC\t-\t0.032\t0.41' → $'keep\nup\ntag'
# 예: $'up\tmap\tA\t-\t0.134\t1.00\ntag\tmap\tB\t-\t0.083\t1.00\nkeep\tfilter\tC\tup\t0.032\t0.41' → $'up\nkeep\ntag'
# 예: $'up\tmap\tA\t-\t0.1\t1.00\nk1\tfilter\tB\t-\t0.05\t0.5\ntop\thead\t10\t-\t0\t0.1\nk2\tfilter\tC\t-\t0.01\t0.1' → $'k1\nup\ntop\nk2'
# 예: $'up\tmap\tA\t-\t0.1\t1.00\nsrt\tcollect\tsort\t-\t0.2\t1.00\nk\tfilter\tC\t-\t0.01\t0.1' → $'up\nsrt\nk'
# 예: $'k1\tfilter\tA\t-\t0.10\t0.9\nk2\tfilter\tB\t-\t0.01\t0.1\nup\tmap\tC\t-\t0.1\t1.00\nk3\tfilter\tD\t-\t0.01\t0.1' "mild" → $'k2\nk1\nup\nk3'
# 예: "" → ""
pa_order() {
  local mode="${2:-}" name kind cmd after t r n=0 i best bestr first=1 start end wall nextmap d
  local -a names=() kinds=() afters=() ranks=() placed=() dep=()
  while IFS=$'\t' read -r name kind cmd after t r; do
    [[ -n "$name" ]] || continue
    [[ "$after" != "-" ]] || after=""
    names[n]="$name"; kinds[n]="$kind"; afters[n]="$after"; ranks[n]="$(pa_rank "$t" "$r")"; placed[n]=0; dep[n]=-1; n=$((n + 1))
  done <<< "${1:-}"
  # after 선언이 가리키는 단계의 번호를 한 번만 찾아 둔다(선언이 있는 단계만)
  for (( i = 0; i != n; i++ )); do
    [[ -n "${afters[i]}" ]] || continue
    for (( d = 0; d != i; d++ )); do [[ "${names[d]}" != "${afters[i]}" ]] || { dep[i]=$d; break; }; done
  done
  start=0
  while [[ $start -lt $n ]]; do
    # 구간의 끝: 다음 벽의 자리(벽이 없으면 끝). 벽 자체는 제자리에 둔다.
    end=$start
    while [[ $end -lt $n ]]; do
      wall=0
      case "${kinds[end]}" in head|collect) wall=1 ;; map) [[ "$mode" != mild ]] || wall=1 ;; esac
      [[ $wall -eq 0 ]] || break
      end=$((end + 1))
    done
    # 바꾸기는 저희끼리의 순서를 지킨다 — 놓을 수 있는 바꾸기는 아직 안 놓인 첫 바꾸기 하나뿐이다
    nextmap=$start
    while [[ $nextmap -lt $end && "${kinds[nextmap]}" != map ]]; do nextmap=$((nextmap + 1)); done
    while :; do
      best=-1; bestr=0
      for (( i = start; i != end; i++ )); do
        [[ ${placed[i]} -eq 0 ]] || continue
        [[ "${kinds[i]}" != map || $i -eq $nextmap ]] || continue
        # after 선언: 그 단계가 이 구간에 있고 아직 안 놓였으면 놓을 수 없다
        d=${dep[i]}
        [[ $d -lt $start || ${placed[d]} -eq 1 ]] || continue
        if [[ $best -eq -1 || ${ranks[i]} -lt $bestr ]]; then best=$i; bestr=${ranks[i]}; fi
      done
      [[ $best -ne -1 ]] || break
      placed[best]=1
      if [[ $best -eq $nextmap ]]; then
        nextmap=$((nextmap + 1))
        while [[ $nextmap -lt $end && "${kinds[nextmap]}" != map ]]; do nextmap=$((nextmap + 1)); done
      fi
      if [[ $first -eq 1 ]]; then first=0; else printf '\n'; fi
      printf '%s' "${names[best]}"
    done
    if [[ $end -lt $n ]]; then
      if [[ $first -eq 1 ]]; then first=0; else printf '\n'; fi
      printf '%s' "${names[end]}"
    fi
    start=$((end + 1))
  done
}

# @pure
# 역할: 잰 줄들에서, 이어진 고르기끼리만 바꾼 순서를 낸다 — 고르기를 바꾸기 앞으로 당긴 순서의 답이 달라졌을 때 쓰는 덜 과감한 순서
# 종류: 고르기/arrange
# 예: $'k1\tfilter\tA\t-\t0.10\t0.9\nk2\tfilter\tB\t-\t0.01\t0.1\nup\tmap\tC\t-\t0.1\t1.00' → $'k2\nk1\nup'
# 예: $'up\tmap\tA\t-\t0.134\t1.00\nkeep\tfilter\tC\t-\t0.032\t0.41' → $'up\nkeep'
pa_order_mild() { pa_order "${1:-}" mild; }

# @pure
# 역할: 잰 줄들과 순서(이름 한 줄씩)에서 그 엮음의 예상 시간(초, 소수 셋째 자리)을 계산한다 — Σ 단계 시간 × 그 단계까지 살아남은 줄의 비율. head 는 살아남은 비율을 그 값으로 깎는다
# 종류: 세기/arrange
# 예: $'up\tmap\tA\t-\t0.134\t1.00\ntag\tmap\tB\t-\t0.083\t1.00\nkeep\tfilter\tC\t-\t0.032\t0.41' $'up\ntag\nkeep' → "0.249"
# 예: $'up\tmap\tA\t-\t0.134\t1.00\ntag\tmap\tB\t-\t0.083\t1.00\nkeep\tfilter\tC\t-\t0.032\t0.41' $'keep\nup\ntag' → "0.121"
# 예: $'up\tmap\tA\t-\t0.100\t1.00\ntop\thead\t10\t-\t0\t0.10\nk\tfilter\tC\t-\t0.050\t0.50' $'up\ntop\nk' → "0.105"
# 예: "" "" → "0.000"
pa_expected() {
  local o name kind cmd after t r alive=1000000 sum=0 c x n=0 i NL=$'\n' TAB=$'\t' blob=$'\n' hit
  local -a kinds=() cs=() xs=()
  # 잰 줄은 한 번만 읽어 둔다. 이름 → 번호는 "<줄바꿈>이름<탭>번호" 글에서 찾는다(순서의 이름마다 줄들을 다시 읽지 않는다).
  while IFS=$'\t' read -r name kind cmd after t r; do
    [[ -n "$name" ]] || continue
    c="$(pb_to_milli "$t")" || c=0
    x="$(pb_to_milli "$r")" || x=1000
    kinds[n]="$kind"; cs[n]=$c; xs[n]=$x; blob+="$name$TAB$n$NL"; n=$((n + 1))
  done <<< "${1:-}"
  while IFS= read -r o; do
    [[ -n "$o" && "$blob" == *"$NL$o$TAB"* ]] || continue
    hit="${blob#*"$NL$o$TAB"}"; i="${hit%%"$NL"*}"
    (( sum += cs[i] * alive / 1000 ))
    if [[ "${kinds[i]}" == head ]]; then [[ $(( xs[i] * 1000 )) -ge $alive ]] || alive=$(( xs[i] * 1000 ))
    else alive=$(( alive * xs[i] / 1000 )); fi
  done <<< "${2:-}"
  # sum 은 백만분의 일 초 — 천분의 일 초로 반올림해 적는다
  (( sum = (sum + 500) / 1000 ))
  printf '%s.%03d' "$(( sum / 1000 ))" "$(( sum % 1000 ))"
}

# @pure
# 역할: 단계 줄들과 순서에서, 줄을 흘려보내는 셸 한 줄을 만든다 — 명령을 " | " 로 잇고 head 는 head -n N 으로 쓴다
# 종류: 조립/arrange
# 예: $'up\tmap\ttr a-z A-Z\t-\nkeep\tfilter\tgrep 7\t-\ntop\thead\t100\t-' $'keep\nup\ntop' → "grep 7 | tr a-z A-Z | head -n 100"
# 예: $'up\tmap\ttr a-z A-Z\t-' "up" → "tr a-z A-Z"
pa_pipeline() {
  local o name kind cmd rest out="" n=0 i NL=$'\n' TAB=$'\t' blob=$'\n' hit
  local -a cmds=()
  while IFS=$'\t' read -r name kind cmd rest; do
    [[ -n "$name" ]] || continue
    [[ "$kind" != head ]] || cmd="head -n $cmd"
    cmds[n]="$cmd"; blob+="$name$TAB$n$NL"; n=$((n + 1))
  done <<< "${1:-}"
  while IFS= read -r o; do
    [[ -n "$o" && "$blob" == *"$NL$o$TAB"* ]] || continue
    hit="${blob#*"$NL$o$TAB"}"; i="${hit%%"$NL"*}"
    out+="${out:+ | }${cmds[i]}"
  done <<< "${2:-}"
  printf '%s' "$out"
}

# @pure
# 역할: 잰 줄들과 고른 순서에서 규칙으로 알 수 있는 것을 한 줄씩 낸다 — 앞으로 당긴 고르기, 합칠 수 있는 이어진 바꾸기, 일찍 끝나는 앞의 N줄. 없으면 "규칙으로 더 볼 것이 없음"
# 종류: 조립/arrange
# 예: $'up\tmap\tA\t-\t0.134\t1.00\ntag\tmap\tB\t-\t0.083\t1.00\nkeep\tfilter\tC\t-\t0.032\t0.41' $'keep\nup\ntag' → $'고르기 keep 을 바꾸기 앞으로 당김 — 통과 비율 0.41\n이어진 바꾸기 2개(up · tag) — 한 명령으로 합칠 수 있으면 입력을 한 번만 훑는다'
# 예: $'k\tfilter\tA\t-\t0.1\t0.5\ntop\thead\t10\t-\t0\t0.1' $'k\ntop' → "앞의 10줄만 쓴다 — 흘려보내면 앞 단계가 일찍 끝난다"
# 예: $'k\tfilter\tA\t-\t0.1\t0.5\nup\tmap\tB\t-\t0.1\t1.00' $'k\nup' → "규칙으로 더 볼 것이 없음"
pa_hints() {
  local name kind cmd after t r o n=0 m=0 i p out="" run="" runn=0 maxmap=-1 NL=$'\n' TAB=$'\t' blob=$'\n' hit
  local -a names=() kinds=() cmds=() ratios=() pos=() ord=()
  while IFS=$'\t' read -r name kind cmd after t r; do
    [[ -n "$name" ]] || continue
    names[n]="$name"; kinds[n]="$kind"; cmds[n]="$cmd"; ratios[n]="$r"; pos[n]=-1; blob+="$name$TAB$n$NL"; n=$((n + 1))
  done <<< "${1:-}"
  # 고른 순서에서의 자리(pos)와, 자리마다의 단계 번호(ord)
  while IFS= read -r o; do
    [[ -n "$o" && "$blob" == *"$NL$o$TAB"* ]] || continue
    hit="${blob#*"$NL$o$TAB"}"; i="${hit%%"$NL"*}"
    pos[i]=$m; ord[m]=$i; m=$((m + 1))
  done <<< "${2:-}"
  # 1) 처음 순서에서 앞에 있던 바꾸기를 넘어 앞으로 온 고르기 — 앞의 바꾸기들 가운데 가장 뒤 자리(maxmap)만 기억한다
  for (( i = 0; i != n; i++ )); do
    if [[ "${kinds[i]}" == map ]]; then
      [[ ${pos[i]} -le $maxmap ]] || maxmap=${pos[i]}
    elif [[ "${kinds[i]}" == filter && ${pos[i]} -ne -1 && $maxmap -gt ${pos[i]} ]]; then
      out+="${out:+$NL}고르기 ${names[i]} 을 바꾸기 앞으로 당김 — 통과 비율 ${ratios[i]}"
    fi
  done
  # 2) 고른 순서에서 이어진 바꾸기, 3) 앞의 N줄
  for (( p = 0; p != m; p++ )); do
    i=${ord[p]}
    if [[ "${kinds[i]}" == map ]]; then run+="${run:+ · }${names[i]}"; runn=$((runn + 1)); continue; fi
    [[ $runn -lt 2 ]] || out+="${out:+$NL}이어진 바꾸기 ${runn}개($run) — 한 명령으로 합칠 수 있으면 입력을 한 번만 훑는다"
    run=""; runn=0
    [[ "${kinds[i]}" != head ]] || out+="${out:+$NL}앞의 ${cmds[i]}줄만 쓴다 — 흘려보내면 앞 단계가 일찍 끝난다"
  done
  [[ $runn -lt 2 ]] || out+="${out:+$NL}이어진 바꾸기 ${runn}개($run) — 한 명령으로 합칠 수 있으면 입력을 한 번만 훑는다"
  printf '%s' "${out:-규칙으로 더 볼 것이 없음}"
}

# @pure
# 역할: 단계 수에서, 순서를 전부 돌려 볼 때의 가짓수(계승)를 낸다 — 20을 넘으면 "아주 많음"
# 종류: 세기/arrange
# 예: 3 → "6"
# 예: 6 → "720"
# 예: 0 → "1"
# 예: 21 → "아주 많음"
pa_count_orders() {
  local n="${1:-0}" f=1 i
  [[ "$n" =~ ^[0-9]+$ ]] || n=0
  [[ $n -le 20 ]] || { printf '아주 많음'; return 0; }
  for (( i = 2; i <= n; i++ )); do f=$(( f * i )); done
  printf '%s' "$f"
}

# @pure
# 역할: 잰 줄들 · 짜임 줄들("이름표<탭>순서 글<탭>예상<탭>잰 시간<탭>벽시계<탭>메모리<탭>답") · 도움 글 · 머리 글에서 사람이 읽는 표를 만든다
# 종류: 조립/arrange
# 예: $'keep\tfilter\tgrep 7\t-\t0.030\t0.41' $'처음\tkeep\t0.030\t0.04\t0.05\t3.1\t—' "규칙으로 더 볼 것이 없음" "입력 10줄" → $'입력 10줄\n\n| 단계 | 종류 | 한 번 잰 시간(초) | 통과 비율 | 순위 값 |\n|---|---|---|---|---|\n| keep | 고르기 | 0.030 | 0.41 | -19.66 |\n\n| 짜임 | 순서 | 예상(초) | 잰 시간(초) | 기다린 시간(초) | 메모리(MB) | 답 |\n|---|---|---|---|---|---|---|\n| 처음 | keep | 0.030 | 0.04 | 0.05 | 3.1 | — |\n\n규칙으로 본 것:\n- 규칙으로 더 볼 것이 없음'
pa_render() {
  local name kind cmd after t r k v w label order exp real wall mem ans h
  printf '%s\n\n| 단계 | 종류 | 한 번 잰 시간(초) | 통과 비율 | 순위 값 |\n|---|---|---|---|---|\n' "${4:-}"
  while IFS=$'\t' read -r name kind cmd after t r; do
    [[ -n "$name" ]] || continue
    case "$kind" in map) k="바꾸기" ;; filter) k="고르기" ;; head) k="앞의 N줄" ;; *) k="모아야 함" ;; esac
    v="$(pa_rank "$t" "$r")"; w=""
    if [[ $v -lt 0 ]]; then w="-"; v=$(( 0 - v )); fi
    printf '| %s | %s | %s | %s | %s%s.%02d |\n' "$name" "$k" "$t" "$r" "$w" "$(( v / 1000 ))" "$(( v % 1000 / 10 ))"
  done <<< "${1:-}"
  # 잰 시간 = 순서를 가리는 데 쓰는 값(CPU 가 일한 시간, GPU 를 쓴 명령은 벽시계). 기다린 시간 = 벽시계.
  printf '\n| 짜임 | 순서 | 예상(초) | 잰 시간(초) | 기다린 시간(초) | 메모리(MB) | 답 |\n|---|---|---|---|---|---|---|\n'
  while IFS=$'\t' read -r label order exp real wall mem ans; do
    [[ -n "$label" ]] || continue
    printf '| %s | %s | %s | %s | %s | %s | %s |\n' "$label" "$order" "$exp" "$real" "$wall" "$mem" "$ans"
  done <<< "${2:-}"
  printf '\n규칙으로 본 것:'
  while IFS= read -r h; do [[ -z "$h" ]] || printf '\n- %s' "$h"; done <<< "${3:-}"
}

# @pure
# 역할: 이름 한 줄씩의 순서를 "가 → 나 → 다" 한 줄로 잇는다 — 표에 적을 순서 글
# 종류: 조립/arrange
# 예: $'keep\nup\ntag' → "keep → up → tag"
# 예: "up" → "up"
# 예: "" → ""
pa_join_names() {
  local o out=""
  while IFS= read -r o; do [[ -z "$o" ]] || out+="${out:+ → }$o"; done <<< "${1:-}"
  printf '%s' "$out"
}
