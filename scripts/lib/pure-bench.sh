#!/usr/bin/env bash
# pure-bench.sh (lib) — 재는 명령의 판단. 순수 함수만 둔다.
#
# 이 파일의 함수는 글만 받고 글만 낸다. 파일도, 시각도, 실행도 만지지 않는다.
# 사전을 읽고 명령을 돌려 재는 일은 바깥(core/scripts/pure-bench.sh)이 맡는다.
# 계약: core/contracts/composition.md · 계획: 20261111-wookiya1364-pure-bench-and-gate
#
# pb_targets 는 예시를 나누는 pc_split_example(lib/pure-catalog.sh)을 다시 쓴다 — 그 파일을 먼저 source 한다.

# 1배 입력 = 사전의 예시를 이만큼 되풀이한 것. 4배 입력은 그 네 배.
# 예시 그대로(두세 줄)는 너무 작아 함수를 부르는 값만 재진다.
PB_BASE_REPEAT=25

# @pure
# 역할: 예시의 인자 글에서 여러 줄 값은 줄을, 여러 줄 값이 없으면 낱말이 여럿인 값은 낱말을 N번 되풀이한다(늘릴 값이 없으면 그대로 내고 1)
# 종류: 변환
# 예: $'$\'a\\nb\' "x y"' 2 → $'$\'a\\nb\\na\\nb\' "x y"'
# 예: '"x y" k' 2 → '"x y x y" k'
# 예: '"1.2.3" k' 2 → '"1.2.3" k' [1]
pb_scale_args() {
  local args="${1:-}" times="${2:-1}" mode out i n c q open body rep k join did
  n=${#args}
  for mode in lines words; do
    out=""; q=""; body=""; open=""; did=0; i=0
    while [[ $i -lt $n ]]; do
      c="${args:i:1}"
      if [[ -z "$q" ]]; then
        if [[ "$c" == '$' && "${args:i+1:1}" == "'" ]]; then q=ds; open="\$'"; body=""; i=$((i + 2)); continue
        elif [[ "$c" == "'" ]]; then q=s; open="'"; body=""
        elif [[ "$c" == '"' ]]; then q=d; open='"'; body=""
        elif [[ "$c" == '\' ]]; then out+="$c${args:i+1:1}"; i=$((i + 1))
        else out+="$c"
        fi
      elif [[ "$c" == '\' && "$q" != s ]]; then
        body+="$c${args:i+1:1}"; i=$((i + 1))
      elif [[ ( "$q" == d && "$c" == '"' ) || ( "$q" != d && "$c" == "'" ) ]]; then
        # 값 하나가 끝났다 — 이 차례(mode)에 늘릴 값인가
        if [[ $mode == lines && $q == ds && "$body" == *'\n'* ]]; then
          join='\n'; [[ "$body" != *'\n' ]] || join=""
        elif [[ $mode == words && "$body" == *[![:space:]]*' '*[![:space:]]* ]]; then
          join=' '
        else
          join="-"
        fi
        if [[ "$join" == "-" ]]; then rep="$body"
        else
          rep=""; for (( k = 0; k < times; k++ )); do rep+="$body$join"; done
          [[ -z "$join" ]] || rep="${rep%"$join"}"
          did=1
        fi
        out+="$open$rep"; if [[ $q == d ]]; then out+='"'; else out+="'"; fi
        q=""
      else
        body+="$c"
      fi
      i=$((i + 1))
    done
    [[ -z "$q" ]] || out+="$open$body"   # 닫히지 않은 따옴표는 그대로 둔다
    if [[ $did -eq 1 ]]; then printf '%s' "$out"; return 0; fi
  done
  printf '%s' "$args"; return 1
}

# @pure
# 역할: 사전 글에서 잴 목록 "함수<탭>파일<탭>언어<탭>1배 인자<탭>4배 인자<탭>늘림(1/0)" 줄들을 낸다(둘째 인자에 이름 목록을 주면 그 함수만, 예시 없는 함수는 뺀다)
# 종류: 꺼내기/measure
# 예: $'### f\n- 역할: 센다\n- 위치: scripts/lib/a.sh · @pure · sh\n- 예: `"1.2" → "2"`' "" → $'f\tscripts/lib/a.sh\tsh\t"1.2"\t"1.2"\t0'
# 예: $'### f\n- 위치: lib/a.sh · @pure · sh\n- 예: `"a" → "1"`\n### g\n- 위치: lib/a.sh · @pure · sh\n- 예: `"b" → "1"`' "g" → $'g\tlib/a.sh\tsh\t"b"\t"b"\t0'
pb_targets() {
  local catalog="${1:-}" only="${2:-}" line name="" file="" lang="" ex split args a1 a4 ok seen=""
  while IFS= read -r line; do
    case "$line" in
      '### '*) name="${line#\#\#\# }"; file=""; lang=""; seen="" ;;
      '- 위치: '*)
        file="${line#- 위치: }"; lang="${file##* · }"; file="${file%% · *}" ;;
      '- 예: `'*)
        [[ -n "$name" && -z "$seen" ]] || continue
        seen=1
        if [[ -n "$only" ]]; then case $'\n'"$only"$'\n' in *$'\n'"$name"$'\n'*) ;; *) continue ;; esac; fi
        ex="${line#- 예: \`}"; ex="${ex%\`}"
        split="$(pc_split_example "$ex")" || continue
        args="${split%%$'\t'*}"
        ok=1
        a1="$(pb_scale_args "$args" "$PB_BASE_REPEAT")" || ok=0
        a4="$(pb_scale_args "$args" "$(( PB_BASE_REPEAT * 4 ))")" || ok=0
        printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$name" "$file" "$lang" "$a1" "$a4" "$ok" ;;
    esac
  done <<< "$catalog"
}

# ---------------------------------------------------------------- 잰 글을 값으로
# 순수성 검사는 꺾쇠(크다 · 작다)를 파일 쓰기 · 읽기로 본다. 그래서 견주기는 셸의 정수 계산으로 하고,
# awk 를 쓰는 함수(외부 도구 — @deterministic)에서는 꺾쇠를 쓰지 않는다.

# @deterministic
# 역할: 시간 재는 명령의 출력 글에서 "벽시계 초<탭>CPU 초<탭>메모리 MB"를 낸다(BSD · GNU 두 꼴, 없는 값은 -)
# 종류: 꺼내기/measure
# 예: $'real 1.50\nuser 0.40\nsys 0.10\n  2621440  maximum resident set size' → $'1.50\t0.50\t2.5'
# 예: $'\tUser time (seconds): 0.40\n\tSystem time (seconds): 0.10\n\tElapsed (wall clock) time (h:mm:ss or m:ss): 0:01.50\n\tMaximum resident set size (kbytes): 2560' → $'1.50\t0.50\t2.5'
# 예: $'real 0.30\nuser 0.00\nsys 0.00' → $'0.30\t0.00\t-'
pb_parse_time() {
  LC_ALL=C awk '
    $1 == "real" { wall = $2; hw = 1 }
    $1 == "user" { u = $2; hc = 1 }
    $1 == "sys"  { s = $2; hc = 1 }
    /maximum resident set size/ { rss = $1 / 1048576; hr = 1 }
    /User time \(seconds\)/ { u = $NF; hc = 1 }
    /System time \(seconds\)/ { s = $NF; hc = 1 }
    /Elapsed \(wall clock\) time/ {
      t = $NF; wall = 0
      while ((k = index(t, ":")) != 0) { wall = wall * 60 + substr(t, 1, k - 1); t = substr(t, k + 1) }
      wall = wall * 60 + t; hw = 1
    }
    /Maximum resident set size \(kbytes\)/ { rss = $NF / 1024; hr = 1 }
    END {
      a = "-"; b = "-"; c = "-"
      if (hw) a = sprintf("%.2f", wall)
      if (hc) b = sprintf("%.2f", u + s)
      if (hr) c = sprintf("%.1f", rss)
      printf "%s\t%s\t%s", a, b, c
    }' <<< "${1:-}"
}

# @deterministic
# 역할: 셸의 times 출력 글(분 · 초 꼴 네 값)을 모두 더한 초로 낸다
# 종류: 변환
# 예: $'0m0.010s 0m0.020s\n0m1.000s 0m0.500s' → "1.530"
# 예: $'1m2.000s 0m0.000s\n0m0.000s 0m0.000s' → "62.000"
pb_times_secs() {
  LC_ALL=C awk '{ for (i = 1; i != NF + 1; i++) { m = index($i, "m"); if (m != 0) t += substr($i, 1, m - 1) * 60 + substr($i, m + 1) } } END { printf "%.3f", t }' <<< "${1:-}"
}

# @pure
# 역할: 잰 CPU 초와 되풀이 수를 보고 다음 되풀이 수를 낸다 — 0.2초에 못 미치면 0.3초가 되도록 늘린다(2000번까지)
# 종류: 세기
# 예: 0.010 5 → "150"
# 예: 0.250 5 → "5"
# 예: 0.000 5 → "2000"
pb_reps_next() {
  local c="${1:-0}" r="${2:-1}" whole frac ms num n
  whole="${c%%.*}"; frac=0; [[ "$c" != *.* ]] || frac="${c#*.}"
  frac="${frac}000"; frac="${frac:0:3}"
  (( ms = 10#${whole:-0} * 1000 + 10#$frac ))
  if [[ $ms -ge 200 ]]; then printf '%s' "$r"; return 0; fi
  n=2000
  if [[ $ms -ne 0 ]]; then (( num = r * 300 + ms - 1 )); (( n = num / ms )); fi
  [[ $n -le 2000 ]] || n=2000
  [[ $n -ge $r ]] || n="$r"
  printf '%s' "$n"
}

# @deterministic
# 역할: 맥의 그래픽 장치 정보 글에서 "사용률 %<탭>쓰는 메모리 MB"를 낸다(값이 없으면 빈 글)
# 종류: 꺼내기/measure
# 예: '"PerformanceStatistics" = {"In use system memory"=104857600,"Device Utilization %"=42}' → $'42\t100.0'
# 예: 'no gpu here' → ""
pb_parse_ioreg() {
  LC_ALL=C awk '
    match($0, /"Device Utilization %"=[0-9]+/) && u == "" { u = substr($0, RSTART, RLENGTH); sub(/.*=/, "", u) }
    match($0, /"In use system memory"=[0-9]+/) && m == "" { m = substr($0, RSTART, RLENGTH); sub(/.*=/, "", m) }
    END { if (u != "" && m != "") printf "%d\t%.1f", u, m / 1048576 }' <<< "${1:-}"
}

# @pure
# 역할: nvidia-smi 의 "사용률, 메모리 MiB" 줄들에서 "사용률 %<탭>쓰는 메모리 MB"를 낸다(장치가 여럿이면 사용률은 가장 큰 값, 메모리는 합)
# 종류: 꺼내기/measure
# 예: '35, 1024' → $'35\t1024.0'
# 예: $'10, 100\n90, 200' → $'90\t300.0'
# 예: '' → ""
pb_parse_nvidia() {
  local u m rest top="" sum=0 n=0
  while IFS=', ' read -r u m rest; do
    [[ "$u" =~ ^[0-9]+$ && "$m" =~ ^[0-9]+$ ]] || continue
    [[ -n "$top" && "$top" -ge "$u" ]] || top="$u"
    (( sum = sum + m )); (( n = n + 1 ))
  done <<< "${1:-}"
  [[ $n -eq 0 ]] || printf '%s\t%s.0' "$top" "$sum"
}

# @pure
# 역할: GPU 표본 줄들("사용률<탭>메모리 MB")과 시작 전 메모리 · 시작 전 사용률에서 "평균 사용률 %<탭>늘어난 메모리 MB<탭>오른 사용률 %p"를 낸다(표본이 없으면 "-" 셋)
# 종류: 세기
# 예: $'40\t1100.0\n60\t1300.0' 1000.0 10 → $'50\t300.0\t40'
# 예: $'10\t1000.0' 1000.0 15 → $'10\t0.0\t0'
# 예: '' 1000.0 0 → $'-\t-\t-'
pb_gpu_summary() {
  local u m t n=0 s=0 top=0 base="${2:-0}" before="${3:-0}" half avg d rise
  [[ "$base" == *.* ]] || base="${base}.0"
  base="${base%%.*}${base#*.}"
  [[ "$before" =~ ^[0-9]+$ ]] || before=0
  while IFS=$'\t' read -r u m; do
    [[ "$u" =~ ^[0-9]+$ && "$m" =~ ^[0-9]+(\.[0-9])?$ ]] || continue
    [[ "$m" == *.* ]] || m="${m}.0"
    t="${m%%.*}${m#*.}"                       # 십분의 일 MB 를 정수로
    [[ $((10#$top)) -ge $((10#$t)) ]] || top="$t"
    (( s = s + u )); (( n = n + 1 ))
  done <<< "${1:-}"
  if [[ $n -eq 0 ]]; then printf -- '-\t-\t-'; return 0; fi
  (( half = n / 2 )); (( avg = s + half )); (( avg = avg / n ))
  (( d = 10#$top - 10#$base )); [[ $d -ge 0 ]] || d=0
  (( rise = avg - before )); [[ $rise -ge 0 ]] || rise=0
  printf '%s\t%s.%s\t%s' "$avg" "$(( d / 10 ))" "$(( d % 10 ))" "$rise"
}

# ---------------------------------------------------------------- 판정 잣대와 배수

# @pure
# 역할: 소수 글을 천분의 일 단위 정수로 바꾼다(소수 셋째 자리까지, 숫자가 아니면 빈 글과 1)
# 종류: 변환
# 예: 22.286 → "22286"
# 예: 0.5 → "500"
# 예: 3 → "3000"
# 예: - → "" [1]
pb_to_milli() {
  local v="${1:-}" whole frac
  [[ "$v" =~ ^[0-9]+(\.[0-9]+)?$ ]] || return 1
  whole="${v%%.*}"; frac=0; [[ "$v" != *.* ]] || frac="${v#*.}"
  frac="${frac}000"; frac="${frac:0:3}"
  printf '%s' "$(( 10#$whole * 1000 + 10#$frac ))"
}

# @pure
# 역할: 1배 값과 4배 값에서 배수를 소수 한 자리로 낸다(한쪽이 숫자가 아니거나 1배 값이 0이면 "-")
# 종류: 세기
# 예: 22.286 386.600 → "17.3"
# 예: 4.492 13.739 → "3.1"
# 예: 5 - → "-"
# 예: 0.000 3.0 → "-"
pb_scale_ratio() {
  local a b half r
  a="$(pb_to_milli "${1:-}")" && b="$(pb_to_milli "${2:-}")" || { printf -- '-'; return 0; }
  [[ $a -ne 0 ]] || { printf -- '-'; return 0; }
  (( half = a / 2 )); (( r = b * 10 + half )); (( r = r / a ))
  printf '%s.%s' "$(( r / 10 ))" "$(( r % 10 ))"
}

# GPU 를 썼다고 보는 선: 메모리가 200MB 넘게 늘었거나, 사용률이 시작 전보다 30%p 넘게 올랐다.
# 근거(2026-11-11 이 맥의 실측): 아무 일도 안 할 때 메모리 +0 ~ 56MB · 사용률 7 ~ 17%, GPU 작업은 +1078 ~ 1204MB · 35 ~ 92%.
PB_GPU_MEM_MB=200
PB_GPU_RISE=30

# @pure
# 역할: 잰 값(벽시계 · CPU 초 · GPU 메모리 증가 · GPU 사용률 오름)과 컴퓨터의 붐빔(100 = 한가함)을 보고 판정 잣대 이름을 낸다 — cpu | wall-gpu | unmeasured
# 종류: 판정
# 예: 1.00 0.98 0.0 4 100 → "cpu"
# 예: 8.40 0.80 1171.0 78 100 → "wall-gpu"
# 예: 8.40 0.80 - - 100 → "unmeasured"
# 예: 0.01 0.00 - - 100 → "unmeasured"
# 예: 2.00 0.98 0.0 4 210 → "cpu"
pb_pick_measure() {
  local wall cpu mem rise="${4:--}" load="${5:-100}" lhs rhs
  wall="$(pb_to_milli "${1:-}")" || { printf unmeasured; return 0; }
  cpu="$(pb_to_milli "${2:-}")" || cpu=0
  # GPU 를 썼다 — 벽시계와 GPU 값으로 본다
  if mem="$(pb_to_milli "${3:-}")"; then
    if [[ $mem -ge $(( PB_GPU_MEM_MB * 1000 )) ]]; then printf wall-gpu; return 0; fi
    if [[ "$rise" =~ ^[0-9]+$ && $rise -ge $PB_GPU_RISE ]]; then printf wall-gpu; return 0; fi
  fi
  # 너무 짧아 잴 수 없다
  if [[ $wall -lt 50 && $cpu -lt 20 ]]; then printf unmeasured; return 0; fi
  # 벽시계가 CPU 시간보다 훨씬 크다(붐빔을 빼고도 1.5배) — 다른 곳에서 일했다는 신호
  [[ "$load" =~ ^[0-9]+$ && $load -ge 100 ]] || load=100
  (( lhs = wall * 10000 )); (( rhs = 150 * cpu * load ))
  if [[ $wall -ge 500 && $lhs -ge $rhs ]]; then
    if [[ "${3:--}" == "-" ]]; then printf unmeasured; else printf wall-gpu; fi
    return 0
  fi
  printf cpu
}

# ---------------------------------------------------------------- 엮은 함수와 표

# @deterministic
# 역할: 함수 본문 글("@@ 이름" 줄 뒤에 본문)과 사전의 이름 목록에서, 사전 함수마다 본문이 부르는 다른 사전 함수를 "함수<탭>부르는 함수들(빈칸으로 나눔)" 줄로 낸다(부르는 것이 없으면 뺀다)
# 종류: 꺼내기/measure
# 예: $'@@ f\n  g "$1" | h\n  # i 는 주석\n@@ g\n  echo x\n@@ z\n  f' $'f\ng\nh\ni' → $'f\tg h'
pb_calls() {
  local names="${2:-}"
  LC_ALL=C awk -v names="${names//$'\n'/ }" '
    function flush(   k, out) {
      if (cur == "" || !(cur in known)) return
      out = ""
      for (k = 1; k != cnt + 1; k++) out = out (out == "" ? "" : " ") order[k]
      if (out != "") printf "%s\t%s\n", cur, out
    }
    BEGIN { n = split(names, a, " "); for (i = 1; i != n + 1; i++) if (a[i] != "") known[a[i]] = 1 }
    /^@@ / { flush(); cur = substr($0, 4); cnt = 0; split("", seen); next }
    /^[ \t]*#/ { next }
    {
      line = $0; gsub(/[^A-Za-z0-9_]+/, " ", line); m = split(line, w, " ")
      for (i = 1; i != m + 1; i++) if ((w[i] in known) && w[i] != cur && !(w[i] in seen)) { seen[w[i]] = 1; order[++cnt] = w[i] }
    }
    END { flush() }' <<< "${1:-}"
}

# @pure
# 역할: "함수<탭>부르는 함수들" 줄들에서 다른 사전 함수를 N개(기본 2) 이상 부르는 줄만 낸다 — 엮은 함수
# 종류: 고르기
# 예: $'f\tg h\nk\tg' → $'f\tg h'
# 예: $'f\tg h\nk\tg' 1 → $'f\tg h\nk\tg'
pb_composed() {
  local lines="${1:-}" min="${2:-2}" name callees w n
  while IFS=$'\t' read -r name callees; do
    [[ -n "$name" ]] || continue
    n=0; for w in $callees; do n=$((n + 1)); done
    [[ $n -ge $min ]] && printf '%s\t%s\n' "$name" "$callees"
  done <<< "$lines"
  return 0
}

# @pure
# 역할: 사전 글에서 "함수<탭>하는 일(짧게)" 줄들을 낸다 — 잴 목록과 같은 차례(예시 있는 함수만, 이름 목록을 주면 그 함수만), 하는 일은 풀이 앞까지 · 여덟 낱말까지
# 종류: 꺼내기/measure
# 예: $'### f\n- 역할: 글을 낱말들로 나눈다 — 2자 이상(빈칸으로 이음)\n- 위치: lib/a.sh · @pure · sh\n- 예: `"a" → "1"`\n### g\n- 역할: 없다\n- 위치: lib/a.sh · @pure · sh' "" → $'f\t글을 낱말들로 나눈다'
# 예: $'### f\n- 역할: 하나 둘 셋 넷 다섯 여섯 | 일곱 여덟 아홉\n- 위치: lib/a.sh · @pure · sh\n- 예: `"a" → "1"`' "" → $'f\t하나 둘 셋 넷 다섯 여섯 / 일곱…'
pb_roles() {
  local catalog="${1:-}" only="${2:-}" line name="" role="" seen="" w out k bar=/     # 표의 칸을 깨는 세로줄은 빗금으로 (bash 3.2 는 바꿀 글에 적은 역빗금을 그대로 남긴다)
  while IFS= read -r line; do
    case "$line" in
      '### '*) name="${line#\#\#\# }"; role=""; seen="" ;;
      '- 역할: '*) role="${line#- 역할: }" ;;
      '- 예: `'*)
        [[ -n "$name" && -z "$seen" ]] || continue
        seen=1
        if [[ -n "$only" ]]; then case $'\n'"$only"$'\n' in *$'\n'"$name"$'\n'*) ;; *) continue ;; esac; fi
        role="${role%% — *}"; role="${role%%(*}"; role="${role//|/$bar}"
        out=""; k=0
        for w in $role; do k=$((k + 1)); [[ $k -le 8 ]] || { out="${out}…"; break; }; out="${out:+$out }$w"; done
        printf '%s\t%s\n' "$name" "${out:--}" ;;
    esac
  done <<< "$catalog"
}

# @pure
# 역할: 한 함수의 1배 줄과 4배 줄(재는 명령 fn 의 줄, 4배는 없어도 됨)과 하는 일 글을 표의 한 줄로 잇는다 — "함수<탭>잣대<탭>1배 ms<탭>4배 ms<탭>배수<탭>메모리 MB<탭>부른 횟수 1배<탭>4배<탭>상태<탭>하는 일"
# 종류: 조립/measure
# 예: $'f\t1\t14\t22.286\t0.32\t2.9\t7\t0.0\t0\tok\tcpu' $'f\t4\t5\t386.600\t1.95\t3.1\t14\t15.9\t0\tok\tcpu' "글을 나눈다" → $'f\tcpu\t22.286\t386.600\t17.3\t2.9\t0\t0\tok\t글을 나눈다'
# 예: $'g\t1\t60\t1.500\t0.31\t2.4\t7\t0.0\t1\tok\tcpu' $'g\t4\t-\t-\t-\t-\t-\t-\t-\tnot-scalable\t-' → $'g\tcpu\t1.500\t-\t-\t2.4\t1\t-\tnot-scalable\t-'
pb_row() {
  local n s r ms1 w m g gm e1 st nm x ms4="-" e4="-" st4=""
  IFS=$'\t' read -r n s r ms1 w m g gm e1 st nm <<< "${1:-}"
  [[ -z "${2:-}" ]] || IFS=$'\t' read -r x x x ms4 x x x x e4 st4 x <<< "$2"
  [[ "$st" != ok || -z "$st4" || "$st4" == ok ]] || st="$st4"
  x="${3:-}"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' "$n" "${nm:--}" "$ms1" "$ms4" "$(pb_scale_ratio "$ms1" "$ms4")" "$m" "$e1" "$e4" "$st" "${x:--}"
}

# 입력을 4배로 늘렸을 때 시간이 이 배수를 넘으면 '입력이 커지면 위험한 함수'로 적는다(2026-11-11 사용자 결정).
PB_SCALE_LIMIT=8

# @pure
# 역할: 표의 줄들(pb_row 의 줄)과 잰 환경 한 줄에서 사람이 읽는 표 글을 만든다 — 표 · 비고 · 끝의 셈(잰 수 · 못 잰 수와 이유)
# 종류: 조립/measure
# 예: $'f\tcpu\t22.286\t386.600\t17.3\t2.9\t0\t0\tok\t글을 나눈다' 'bash 3.2' → $'잰 환경: bash 3.2\n\n| 함수 | 하는 일 | 잣대 | 한 번(ms) | 4배 입력(ms) | 배수 | 메모리(MB) | 부른 횟수 | 비고 |\n|---|---|---|---|---|---|---|---|---|\n| f | 글을 나눈다 | cpu | 22.286 | 386.600 | 17.3 | 2.9 | 0 → 0 | 배수 한도(8배) 넘음 |\n\n잰 함수 1 · 못 잰 함수 0 · 늘려 재지 못함 0 · 배수 한도 넘음 1 · 입력만큼 부름 0'
pb_render() {
  local rows="${1:-}" env="${2:-}" n nm ms1 ms4 ratio mem e1 e4 st role note r
  local ok=0 bad=0 noscale=0 over=0 grow=0 why_load=0 why_lang=0 why_meas=0 tail=""
  printf '잰 환경: %s\n\n| 함수 | 하는 일 | 잣대 | 한 번(ms) | 4배 입력(ms) | 배수 | 메모리(MB) | 부른 횟수 | 비고 |\n|---|---|---|---|---|---|---|---|---|\n' "$env"
  while IFS=$'\t' read -r n nm ms1 ms4 ratio mem e1 e4 st role; do
    [[ -n "$n" ]] || continue
    note=""
    case "$st" in
      load-failed) bad=$((bad + 1)); why_load=$((why_load + 1)); note="불러오지 못함" ;;
      too-slow)
        if [[ "$ms1" == "-" ]]; then bad=$((bad + 1)); why_meas=$((why_meas + 1)); note="너무 오래 걸려 끊음"
        else ok=$((ok + 1)); over=$((over + 1)); note="4배 입력에서 너무 오래 걸려 끊음 · 배수 한도(${PB_SCALE_LIMIT}배) 넘음"; fi ;;
      not-shell)   bad=$((bad + 1)); why_lang=$((why_lang + 1)); note="셸 함수 아님" ;;
      *)
        if [[ "$nm" == unmeasured ]]; then bad=$((bad + 1)); why_meas=$((why_meas + 1)); note="재지 못함"
        else
          ok=$((ok + 1))
          [[ "$st" != not-scalable ]] || { noscale=$((noscale + 1)); note="늘려 재지 못함"; }
          if r="$(pb_to_milli "$ratio")" && [[ $r -gt $(( PB_SCALE_LIMIT * 1000 )) ]]; then over=$((over + 1)); note="${note:+$note · }배수 한도(${PB_SCALE_LIMIT}배) 넘음"; fi
          if [[ "$e1" =~ ^[0-9]+$ && "$e4" =~ ^[0-9]+$ && $e4 -gt $e1 ]]; then grow=$((grow + 1)); note="${note:+$note · }입력만큼 부름"; fi
        fi ;;
    esac
    printf '| %s | %s | %s | %s | %s | %s | %s | %s → %s | %s |\n' "$n" "${role:--}" "$nm" "$ms1" "$ms4" "$ratio" "$mem" "$e1" "$e4" "$note"
  done <<< "$rows"
  [[ $bad -eq 0 ]] || tail="(불러오지 못함 $why_load · 셸 함수 아님 $why_lang · 재지 못함 $why_meas)"
  printf '\n잰 함수 %s · 못 잰 함수 %s%s · 늘려 재지 못함 %s · 배수 한도 넘음 %s · 입력만큼 부름 %s' "$ok" "$bad" "$tail" "$noscale" "$over" "$grow"
}

# @pure
# 역할: 엮은 함수 줄들("함수<탭>부르는 함수들")과 표의 줄들에서 엮은 함수의 표 글을 만든다 — 묶음 전체의 값과 부르는 함수들 값의 합을 나란히
# 종류: 조립/measure
# 예: $'f\tg h' $'f\tcpu\t10.000\t50.000\t5.0\t2.9\t0\t0\tok\t셋을 잇는다\ng\tcpu\t1.500\t6.000\t4.0\t2.4\t1\t1\tok\t-\nh\tcpu\t2.000\t-\t-\t2.4\t0\t-\tnot-scalable\t-' → $'| 엮은 함수 | 하는 일 | 부르는 함수 | 묶음 한 번(ms) | 부품 합(ms) | 4배 배수 | 부른 횟수 |\n|---|---|---|---|---|---|---|\n| f | 셋을 잇는다 | g · h | 10.000 | 3.500 | 5.0 | 0 → 0 |'
pb_render_composed() {
  local calls="${1:-}" rows="${2:-}" name callees c sum part n nm ms1 ms4 ratio mem e1 e4 st role got list hit
  printf '| 엮은 함수 | 하는 일 | 부르는 함수 | 묶음 한 번(ms) | 부품 합(ms) | 4배 배수 | 부른 횟수 |\n|---|---|---|---|---|---|---|'
  while IFS=$'\t' read -r name callees; do
    [[ -n "$name" ]] || continue
    sum=0; list=""
    for c in $callees; do
      list="${list:+$list · }$c"; got=""
      while IFS=$'\t' read -r n nm part ms4 ratio mem e1 e4 st role; do
        [[ "$n" == "$c" ]] || continue
        if part="$(pb_to_milli "$part")"; then got=1; (( sum = sum + part )); fi
        break
      done <<< "$rows"
      [[ -n "$got" ]] || { sum=-1; break; }
    done
    if [[ $sum -eq -1 ]]; then part="-"; else part="$(( sum / 1000 )).$(printf '%03d' "$(( sum % 1000 ))")"; fi
    hit=""
    while IFS=$'\t' read -r n nm ms1 ms4 ratio mem e1 e4 st role; do [[ "$n" == "$name" ]] && { hit=1; break; }; done <<< "$rows"
    [[ -n "$hit" ]] || continue
    printf '\n| %s | %s | %s | %s | %s | %s | %s → %s |' "$name" "${role:--}" "$list" "$ms1" "$part" "$ratio" "$e1" "$e4"
  done <<< "$calls"
}

# ---------------------------------------------------------------- 앞뒤 견주기와 한도
# 한도(2026-11-11 사용자 결정) — 기준은 "고치기 전의 같은 함수를 같은 입력으로 돌린 값".
PB_TIME_LIMIT_PCT=120      # 시간: 앞뒤 가운데값 비율이 1.2배를 넘으면
PB_MEM_LIMIT_PCT=120       # 메모리: 1.2배를 넘고
PB_MEM_MIN_TENTHS=10       #         1MB 넘게 늘면 (십분의 일 MB)

# @pure
# 역할: 빈칸으로 나눈 수들의 가운데값을 소수 셋째 자리로 낸다(짝수 개면 가운데 둘의 평균, 수가 없으면 "-")
# 종류: 세기
# 예: "3.000 1.000 2.000" → "2.000"
# 예: "4.0 1.0 3.0 2.0" → "2.500"
# 예: "" → "-"
pb_median() {
  local v m a=() i j t n mid
  for v in ${1:-}; do m="$(pb_to_milli "$v")" || continue; a+=("$m"); done
  n=${#a[@]}
  [[ $n -ne 0 ]] || { printf -- '-'; return 0; }
  for (( i = 1; i != n; i++ )); do
    t=${a[i]}; j=$i
    while [[ $j -ne 0 && ${a[j-1]} -gt $t ]]; do a[j]=${a[j-1]}; j=$((j - 1)); done
    a[j]=$t
  done
  mid=$(( n / 2 ))
  if [[ $(( n % 2 )) -eq 1 ]]; then m=${a[mid]}; else (( m = a[mid-1] + a[mid] )); (( m = m / 2 )); fi
  printf '%s.%03d' "$(( m / 1000 ))" "$(( m % 1000 ))"
}

# @pure
# 역할: 앞 값과 뒤 값에서 뒤 ÷ 앞을 소수 둘째 자리로 낸다(한쪽이 숫자가 아니거나 앞 값이 0이면 "-")
# 종류: 세기
# 예: 3.000 3.750 → "1.25"
# 예: 10 9 → "0.90"
# 예: 0 5 → "-"
pb_ratio() {
  local a b half r
  a="$(pb_to_milli "${1:-}")" && b="$(pb_to_milli "${2:-}")" || { printf -- '-'; return 0; }
  [[ $a -ne 0 ]] || { printf -- '-'; return 0; }
  (( half = a / 2 )); (( r = b * 100 + half )); (( r = r / a ))
  printf '%s.%02d' "$(( r / 100 ))" "$(( r % 100 ))"
}

# @pure
# 역할: 번갈아 잰 앞 값들과 뒤 값들에서, 마지막 두 쌍이 모두 "뒤가 앞의 절반 이하"이면 1 을 낸다 — 뚜렷이 빨라진 함수는 남은 쌍을 재지 않아도 된다
# 종류: 판정
# 예: "100.0 98.0" "10.0 12.0" → "1"
# 예: "100.0 98.0" "10.0 60.0" → "0"
# 예: "100.0" "10.0" → "0"
# 예: "30.0 100.0 98.0" "29.0 10.0 12.0" → "1"
# 예: "100.0 -" "10.0 12.0" → "0"
# 느려졌거나 비슷한 함수에서는 0 이다 — 그때는 정한 쌍을 다 잰다(느려진 것을 놓치지 않는다).
pb_pairs_enough() {
  local v nb=0 na=0 b1="" b2="" a1="" a2="" x y
  for v in ${1:-}; do b1="$b2"; b2="$v"; nb=$((nb + 1)); done
  for v in ${2:-}; do a1="$a2"; a2="$v"; na=$((na + 1)); done
  [[ $nb -ge 2 && $nb -eq $na ]] || { printf '0'; return 0; }
  x="$(pb_to_milli "$b1")" && y="$(pb_to_milli "$a1")" && [[ $(( y * 2 )) -le $x ]] || { printf '0'; return 0; }
  x="$(pb_to_milli "$b2")" && y="$(pb_to_milli "$a2")" && [[ $(( y * 2 )) -le $x ]] || { printf '0'; return 0; }
  printf '1'
}

# @pure
# 역할: 4배 배수 값이 한도(8배)를 넘거나 한도 시간에 끊긴 값(too-slow)이면 1 을 낸다 — 뒤 값이 이럴 때만 앞의 4배 값이 판정에 쓰인다
# 종류: 판정
# 예: 9.1 → "1"
# 예: 8.0 → "0"
# 예: too-slow → "1"
# 예: - → "0"
pb_scale_over() {
  local v="${1:-}" x
  [[ "$v" != too-slow ]] || { printf '1'; return 0; }
  x="$(pb_to_milli "$v")" && [[ $x -gt $(( PB_SCALE_LIMIT * 1000 )) ]] && { printf '1'; return 0; }
  printf '0'
}

# @pure
# 역할: 한 함수의 앞뒤 잰 줄("함수<탭>상태<탭>잣대<탭>앞 값<탭>뒤 값<탭>부른 횟수 앞<탭>뒤<탭>메모리 앞<탭>뒤<탭>4배 배수 앞<탭>뒤")을 한도로 가려 "함수<탭>판정<탭>이유들"을 낸다 — 판정: pass | fail | new | skipped-different-answer | unmeasured | not-reached
# 종류: 판정
# 예: $'f\tok\tcpu\t3.000\t3.450\t0\t0\t2.4\t2.5\t-\t-' → $'f\tpass\t-'
# 예: $'f\tok\tcpu\t3.000\t3.750\t0\t0\t2.4\t2.5\t-\t-' → $'f\tfail\ttime=1.25'
# 예: $'f\tok\tcpu\t3.000\t3.000\t1\t2\t8.0\t10.0\t4.0\t9.1' → $'f\tfail\tcalls=1:2 mem=8.0:10.0 scale=4.0:9.1'
# 예: $'f\tok\tcpu\t3.000\t3.000\t0\t0\t1.2\t1.5\t9.0\t9.5' → $'f\tpass\t-'
# 예: $'f\tdifferent-answer\t-\t-\t-\t-\t-\t-\t-\t-\t-' → $'f\tskipped-different-answer\t-'
# 예: $'f\tok\tcpu\t3.000\t3.000\t0\t0\t2.4\t2.5\ttoo-slow\t9.1' → $'f\tpass\t-'
# 예: $'f\tok\tcpu\t3.000\t3.000\t0\t0\t2.4\t2.5\t4.0\ttoo-slow' → $'f\tfail\tscale=4.0:too-slow'
# 예: $'f\tok\tcpu\ttoo-slow\t3.000\t0\t0\t-\t2.5\ttoo-slow\ttoo-slow' → $'f\tpass\t-'
pb_compare() {
  local n st nm b a eb ea mb ma sb sa why="" r x y lim
  IFS=$'\t' read -r n st nm b a eb ea mb ma sb sa <<< "${1:-}"
  case "$st" in
    different-answer) printf '%s\tskipped-different-answer\t-' "$n"; return 0 ;;
    not-reached)      printf '%s\tnot-reached\t-' "$n"; return 0 ;;
    new|ok) ;;
    *)                printf '%s\tunmeasured\t%s' "$n" "${st:--}"; return 0 ;;
  esac
  if [[ "$st" == ok ]]; then
    [[ "$nm" != unmeasured ]] || { printf '%s\tunmeasured\t-' "$n"; return 0; }
    # 시간 — 앞이 한도 시간에 끊기고(too-slow) 뒤는 쟀으면 더 느려진 것이 아니다
    if [[ "$b" == too-slow ]] && pb_to_milli "$a" >/dev/null; then :
    elif x="$(pb_to_milli "$b")" && y="$(pb_to_milli "$a")"; then
      (( lim = x * PB_TIME_LIMIT_PCT )); (( r = y * 100 ))
      [[ $r -le $lim ]] || why="time=$(pb_ratio "$b" "$a")"
    else printf '%s\tunmeasured\t-' "$n"; return 0; fi
    # 다른 프로그램을 부른 횟수 — 1번이라도 늘면
    if [[ "$eb" =~ ^[0-9]+$ && "$ea" =~ ^[0-9]+$ && $ea -gt $eb ]]; then why="${why:+$why }calls=$eb:$ea"; fi
    # 메모리 — 1.2배를 넘고 1MB 넘게
    if x="$(pb_to_milli "$mb")" && y="$(pb_to_milli "$ma")"; then
      (( lim = x * PB_MEM_LIMIT_PCT )); (( r = y * 100 ))
      if [[ $r -gt $lim && $(( y - x )) -gt $(( PB_MEM_MIN_TENTHS * 100 )) ]]; then why="${why:+$why }mem=$mb:$ma"; fi
    fi
  fi
  # 입력 4배 배수 — 새로 한도를 넘거나, 이미 넘던 것이 1.2배 넘게 더 나빠지면.
  # too-slow 는 그 실행이 한도 시간에 끊겼다는 뜻이다(0.91.2+): 앞만 끊겼으면 이미 넘던 것이고 뒤는 끝냈으니 통과,
  # 뒤만 끊겼으면 한도 넘음, 둘 다 끊겼으면 견줄 수 없어 가리지 않는다.
  if [[ "$sa" == too-slow ]]; then
    [[ "$sb" == too-slow ]] || why="${why:+$why }scale=${sb:--}:too-slow"
  elif y="$(pb_to_milli "$sa")" && [[ $y -gt $(( PB_SCALE_LIMIT * 1000 )) ]]; then
    if [[ "$sb" == too-slow ]]; then :
    elif x="$(pb_to_milli "$sb")" && [[ $x -gt $(( PB_SCALE_LIMIT * 1000 )) ]]; then
      (( lim = x * PB_TIME_LIMIT_PCT )); (( r = y * 100 ))
      [[ $r -le $lim ]] || why="${why:+$why }scale=$sb:$sa"
    else
      why="${why:+$why }scale=${sb:--}:$sa"
    fi
  fi
  if [[ -n "$why" ]]; then printf '%s\tfail\t%s' "$n" "$why"
  elif [[ "$st" == new ]]; then printf '%s\tnew\t-' "$n"
  else printf '%s\tpass\t-' "$n"; fi
}

# @pure
# 역할: 사용자가 받아들인 이유들과 지금의 이유들을 견줘, 지금 것이 모두 받아들인 범위 안이면 참 — 시간 · 배수는 받아들인 값의 2배까지, 메모리는 1.2배까지, 부른 횟수는 받아들인 수까지
# 종류: 판정
# 예: "time=1.35" "time=1.40" → ""
# 예: "time=1.35" "time=3.00" → "" [1]
# 예: "mem=1.9:37.0" "mem=1.9:50.0" → "" [1]
# 예: "time=1.35" "time=1.30 calls=1:2" → "" [1]
# 예: "calls=1:100 mem=1.9:37.0" "calls=1:100" → ""
pb_accept_covers() {
  local acc=" ${1:-} " cur="${2:-}" r kind val was x y lim
  for r in $cur; do
    kind="${r%%=*}"; val="${r##*[=:]}"
    case "$acc" in *" $kind="*) ;; *) return 1 ;; esac
    was="${acc##* $kind=}"; was="${was%% *}"; was="${was##*:}"
    if [[ "$kind" == calls ]]; then
      [[ "$val" =~ ^[0-9]+$ && "$was" =~ ^[0-9]+$ && $val -le $was ]] || return 1
    else
      # 시간 비율은 붐비는 컴퓨터에서 크게 흔들린다(다른 프로그램을 많이 부르는 함수는 같은 코드가 54배 ~ 96배로 재졌다) —
      # 받아들인 값의 2배까지는 같은 변경으로 본다. 메모리는 흔들림이 작아 1.2배까지.
      [[ "$val" != "$was" ]] || continue      # 끊김(too-slow)처럼 숫자가 아닌 값은 같을 때만 같은 변경이다
      x="$(pb_to_milli "$was")" && y="$(pb_to_milli "$val")" || return 1
      if [[ "$kind" == mem ]]; then (( lim = x * 120 )); else (( lim = x * 200 )); fi
      [[ $(( y * 100 )) -le $lim ]] || return 1
    fi
  done
  return 0
}

# @pure
# 역할: '입력이 커지면 위험한 함수' 기준 목록(이름 줄들)과 지금 한도를 넘는 이름들에서 새 목록을 낸다 — 줄어든 이름은 내리고, 새로 넘는 이름은 "@@new 이름" 줄로 알린다(목록에는 넣지 않는다)
# 종류: 고르기
# 예: $'a\nb' $'a\nb' → $'a\nb'
# 예: $'a\nb' $'a' → "a"
# 예: $'a\nb' $'a\nb\nc' → $'a\nb\n@@new c'
pb_baseline_next() {
  local base=$'\n'"${1:-}"$'\n' now=$'\n'"${2:-}"$'\n' n out=""
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    case "$now" in *$'\n'"$n"$'\n'*) out+="$n"$'\n' ;; esac
  done <<< "${1:-}"
  while IFS= read -r n; do
    [[ -n "$n" ]] || continue
    case "$base" in *$'\n'"$n"$'\n'*) ;; *) out+="@@new $n"$'\n' ;; esac
  done <<< "${2:-}"
  printf '%s' "${out%$'\n'}"
}

# @pure
# 역할: 판정 줄들("함수<탭>판정<탭>이유들")에서 한도를 넘은 것마다 사람이 읽는 한 줄을 만든다 — 실제 앞뒤 값으로
# 종류: 조립/measure
# 예: $'f\tfail\ttime=1.25 calls=1:100 mem=1.9:37.0\ng\tpass\t-' → "f — 시간 1.25배 · 다른 프로그램을 부른 횟수 1번 → 100번 · 메모리 1.9MB → 37.0MB"
# 예: $'f\tfail\tscale=4.0:too-slow' → "f — 입력 4배에 걸리는 시간 4.0배 → 끊김"
pb_fail_lines() {
  local n v why r kind val line x y
  while IFS=$'\t' read -r n v why; do
    [[ "$v" == fail ]] || continue
    line=""
    for r in $why; do
      kind="${r%%=*}"; val="${r#*=}"
      case "$kind" in
        time)  line="${line:+$line · }시간 ${val}배" ;;
        calls) line="${line:+$line · }다른 프로그램을 부른 횟수 ${val%%:*}번 → ${val##*:}번" ;;
        mem)   line="${line:+$line · }메모리 ${val%%:*}MB → ${val##*:}MB" ;;
        scale) x="${val%%:*}"; y="${val##*:}"
               if [[ "$x" == too-slow ]]; then x="끊김"; else x="${x}배"; fi
               if [[ "$y" == too-slow ]]; then y="끊김"; else y="${y}배"; fi
               line="${line:+$line · }입력 4배에 걸리는 시간 $x → $y" ;;
      esac
    done
    printf '%s — %s\n' "$n" "$line"
  done <<< "${1:-}"
  return 0
}

# @pure
# 역할: 앞뒤 잰 줄들과 판정 줄들에서 사람이 읽는 표 글을 만든다 — 함수 · 판정 · 앞뒤 값 · 비율 · 부른 횟수 · 메모리 · 4배 배수, 끝에 셈
# 종류: 조립/measure
# 예: $'f\tok\tcpu\t3.000\t3.750\t0\t0\t2.4\t2.5\t-\t-' $'f\tfail\ttime=1.25' → $'| 함수 | 판정 | 앞(ms) | 뒤(ms) | 비율 | 부른 횟수 | 메모리(MB) | 4배 배수 |\n|---|---|---|---|---|---|---|---|\n| f | 한도 넘음 | 3.000 | 3.750 | 1.25 | 0 → 0 | 2.4 → 2.5 | - → - |\n\n견준 함수 1 · 통과 0 · 한도 넘음 1 · 받아들임 0 · 새 함수 0 · 답이 달라 뺌 0 · 재지 못함 0'
pb_render_compare() {
  local lines="${1:-}" verdicts="${2:-}" n st nm b a eb ea mb ma sb sa vn v why word r
  local total=0 pass=0 failn=0 acc=0 new=0 diff=0 bad=0
  printf '| 함수 | 판정 | 앞(ms) | 뒤(ms) | 비율 | 부른 횟수 | 메모리(MB) | 4배 배수 |\n|---|---|---|---|---|---|---|---|\n'
  while IFS=$'\t' read -r n st nm b a eb ea mb ma sb sa && IFS=$'\t' read -r vn v why <&3; do
    [[ -n "$n" ]] || continue
    total=$((total + 1))
    case "$v" in
      pass)     pass=$((pass + 1)); word="통과" ;;
      fail)     failn=$((failn + 1)); word="한도 넘음" ;;
      accepted) acc=$((acc + 1)); word="받아들임" ;;
      new)      new=$((new + 1)); word="새 함수" ;;
      skipped-different-answer) diff=$((diff + 1)); word="답이 달라 뺌" ;;
      *)        bad=$((bad + 1)); word="재지 못함" ;;
    esac
    r="$(pb_ratio "$b" "$a")"
    # 한도 시간에 끊긴 값은 빈칸이 아니라 '끊김'이라고 적는다
    [[ "$b" != too-slow ]] || b="끊김"; [[ "$sb" != too-slow ]] || sb="끊김"; [[ "$sa" != too-slow ]] || sa="끊김"
    printf '| %s | %s | %s | %s | %s | %s → %s | %s → %s | %s → %s |\n' "$n" "$word" "$b" "$a" "$r" "$eb" "$ea" "$mb" "$ma" "$sb" "$sa"
  done <<< "$lines" 3<<< "$verdicts"
  printf '\n견준 함수 %s · 통과 %s · 한도 넘음 %s · 받아들임 %s · 새 함수 %s · 답이 달라 뺌 %s · 재지 못함 %s' "$total" "$pass" "$failn" "$acc" "$new" "$diff" "$bad"
}

# ---------------------------------------------------------------- 무엇을 견줄지 · 멈출 때의 글

# @deterministic
# 역할: 앞 코드와 뒤 코드의 함수 본문 글("@@ 이름" 줄 뒤에 본문)을 견줘 본문이 달라졌거나 새로 생긴 함수 이름을 낸다
# 종류: 비교
# 예: $'@@ f\n a\n@@ g\n b' $'@@ f\n a\n@@ g\n c\n@@ h\n d' → $'g\nh'
# 예: $'@@ f\n a' $'@@ f\n a' → ""
pb_changed_names() {
  LC_ALL=C awk '
    $0 == "@@@@" { second = 1; cur = ""; next }
    /^@@ / { cur = substr($0, 4); if (second && !(cur in seen)) { seen[cur] = 1; order[++n] = cur } next }
    cur == "" { next }
    second { now[cur] = now[cur] "\n" $0; next }
    { old[cur] = old[cur] "\n" $0; had[cur] = 1 }
    END { for (i = 1; i != n + 1; i++) { k = order[i]; if (!(k in had) || old[k] != now[k]) print k } }' <<< "${1:-}"$'\n@@@@\n'"${2:-}"
}

# @pure
# 역할: 엮은 함수 줄들("함수<탭>부르는 함수들")에서, 주어진 이름들 가운데 하나라도 부르는 엮은 함수의 이름을 낸다
# 종류: 고르기
# 예: $'f\tg h\nk\tx y' $'h\nz' → "f"
# 예: $'f\tg h' $'q' → ""
pb_callers() {
  local names=$'\n'"${2:-}"$'\n' name callees c
  while IFS=$'\t' read -r name callees; do
    [[ -n "$name" ]] || continue
    for c in $callees; do
      case "$names" in *$'\n'"$c"$'\n'*) printf '%s\n' "$name"; break ;; esac
    done
  done <<< "${1:-}"
  return 0
}

# @pure
# 역할: '한도를 넘은 것' 줄들("함수<탭>이유들")과 선택 창의 질문 · 답에서 사용자가 받아들인 줄만 낸다 — 질문에 [재는 검사] 와 그 함수 이름이 있고 답이 "이대로"로 시작할 때
# 종류: 고르기
# 예: $'f\ttime=1.35\ng\tcalls=1:2' "[재는 검사] f — 시간 1.35배. 어떻게 할까요?" "이대로 둠" → $'f\ttime=1.35'
# 예: $'f\ttime=1.35' "[재는 검사] f — 시간 1.35배" "고침 (추천)" → ""
# 예: $'f\ttime=1.35' "다른 질문 f" "이대로 둠" → ""
pb_accept_pick() {
  local q="${2:-}" a="${3:-}" name why
  [[ "$q" == *"[재는 검사]"* && "$a" == "이대로"* ]] || return 0
  while IFS=$'\t' read -r name why; do
    [[ -n "$name" ]] || continue
    [[ "$q" =~ (^|[^A-Za-z0-9_])$name([^A-Za-z0-9_]|$) ]] && printf '%s\t%s\n' "$name" "$why"
  done <<< "${1:-}"
  return 0
}

# @pure
# 역할: 한도를 넘은 것의 사람이 읽는 줄들에서, 멈춘 턴에 모델이 받을 글을 만든다 — 선택 창으로 실제 앞뒤 값을 넣어 묻게 한다
# 종류: 조립/measure
# 예: "f — 시간 1.25배" → "[SCV 재는 검사] 고친 순수함수가 고치기 전보다 한도를 넘었다: f — 시간 1.25배. 고칠 수 있으면 원인을 고쳐라. 고치지 않을 것이면 선택 창으로 사용자에게 물어라 — 함수마다 질문 하나, 질문은 '[재는 검사] 함수 이름 —' 으로 시작하고 위의 실제 앞뒤 값을 쉬운 말로 적는다. 첫 보기(추천)는 '고침', 둘째 보기는 '이대로 둠'(맞는 변경이라 받아들임). 끄기: SCV_PURE_BENCH=off."
pb_block_text() {
  local lines="${1:-}"
  lines="${lines%$'\n'}"
  printf '[SCV 재는 검사] 고친 순수함수가 고치기 전보다 한도를 넘었다: %s. 고칠 수 있으면 원인을 고쳐라. 고치지 않을 것이면 선택 창으로 사용자에게 물어라 — 함수마다 질문 하나, 질문은 '"'"'[재는 검사] 함수 이름 —'"'"' 으로 시작하고 위의 실제 앞뒤 값을 쉬운 말로 적는다. 첫 보기(추천)는 '"'"'고침'"'"', 둘째 보기는 '"'"'이대로 둠'"'"'(맞는 변경이라 받아들임). 끄기: SCV_PURE_BENCH=off.' "${lines//$'\n'/ / }"
}
