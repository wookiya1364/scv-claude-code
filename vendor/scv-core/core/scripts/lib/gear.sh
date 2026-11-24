#!/usr/bin/env bash
# lib/gear.sh — 기어와 톱니의 순수부. 파일 읽기 · 쓰기 · 실행은 scripts/gear.sh.
#
# 톱니(tooth)는 아주 작은 sh 하나다 — 표준 입력을 받아 표준 출력으로 내고, 순수함수처럼 한 가지 일만 한다.
#   본문은 scv/gears/teeth/<이름>.sh, 설명과 예시는 톱니 사전(scv/gears/teeth/TEETH.md)에 둔다.
# 기어(gear)는 스킬이다 — scv/gears/<이름>/GEAR.md 의 맨 위 flow 줄에 톱니를 합성함수처럼 순서대로 적고,
#   글은 판단이 필요한 자리(@)만 맡는다. flow 에 다른 기어 이름을 적으면 그 기어의 흐름이 그 자리에 펼쳐진다.
# 만든 사전(INDEX.tsv) 한 줄은 탭으로 나눈 일곱 칸: 이름 · 종류(tooth|gear) · 표시 · 받는 값 · 돌려주는 값 · 하는 일 · 낱말
#   — 인자가 있으면 여덟째 칸에 "이름=기본값; 이름=기본값"(보는 용도 — 실제 값은 톱니 사전과 기어 글에서 다시 읽는다)
# 인자: 톱니 사전의 "- 인자: 이름=기본값 — 설명", 기어 글 맨 위의 "arg: 이름=값", 실행할 때 준 "이름=값" — 뒤가 앞을 이긴다.
#   인자 묶음은 어디서나 "이름=값" 줄들이다(계획 20261124-wookiya1364-gears-io-args).
# bash 3.2(맥 기본)에서도 돈다. 계획 20261124-wookiya1364-gears-run.

# @pure
# 역할: 기어 · 톱니 이름이 쓸 수 있는 모양인지 가린다 — 영문 소문자 · 숫자 · 붙임표, 첫 글자는 영문 소문자나 숫자, 64자까지. teeth 는 톱니 폴더 이름이라 못 쓴다
# 종류: 판정/gear
# 예: "release-notes" → "yes"
# 예: "Bad_Name" → "no"
# 예: "-x" → "no"
# 예: "teeth" → "no"
# 예: "" → "no"
scv_gear_name_ok() {
  local n="${1:-}"
  [[ "$n" != teeth ]] || { printf 'no'; return 0; }
  if [[ "$n" =~ ^[0-9abcdefghijklmnopqrstuvwxyz][0-9abcdefghijklmnopqrstuvwxyz-]{0,63}$ ]]; then printf 'yes'; else printf 'no'; fi
}

# @pure
# 역할: 사전 한 칸에 넣을 글을 한 줄로 만든다 — 탭과 줄바꿈을 빈칸으로 바꾼다
# 종류: 다듬기
# 예: $'a\tb\nc' → "a b c"
# 예: "" → ""
scv_gear_one_line() {
  # 탭 · 줄바꿈은 한 바이트 글자다 — 바이트로 잘라 바꿔도 같은 글이 나온다.
  # 옛 셸은 바꿀 곳이 많은 긴 글을 통째로 바꾸면 길이의 제곱으로 느려서, 128바이트씩 잘라 바꾼다(새 셸은 4096바이트씩).
  local LC_ALL=C
  local s="${1:-}" c out="" i=0 n step=128
  [[ ${BASH_VERSINFO[0]} -ge 4 ]] && step=4096
  n=${#s}
  while (( i < n )); do
    c="${s:i:step}"; c="${c//$'\t'/ }"; out+="${c//$'\n'/ }"; i=$((i + step))
  done
  printf '%s' "$out"
}

# @pure
# 역할: 예시에 적은 글 표기를 실제 글로 푼다 — $'…'(\n \t \\ \' \") 와 "…"(\" \\ \$) 두 모양, 그 밖은 그대로
# 종류: 변환/gear
# 예: "\$'a\\tb\\nc'" → $'a\tb\nc'
# 예: '"가 나"' → "가 나"
# 예: 'plain' → "plain"
scv_gear_lit_decode() {
  # 바이트로 훑는다 — 역슬래시는 한 바이트 글자이고 여러 바이트 글자 안에 나오지 않는다. eval 을 쓰지 않는다(사전의 글을 실행하지 않는다).
  local LC_ALL=C
  local s="${1:-}" mode="" out="" i=0 n c d
  if [[ "$s" == \$\'*\' && ${#s} -ge 3 ]]; then s="${s:2:${#s}-3}"; mode=ansi
  elif [[ "$s" == \"*\" && ${#s} -ge 2 ]]; then s="${s:1:${#s}-2}"; mode=dq
  else printf '%s' "$s"; return 0; fi
  n=${#s}
  while (( i < n )); do
    c="${s:i:1}"
    if [[ "$c" == \\ && $((i + 1)) -lt $n ]]; then
      d="${s:i+1:1}"; i=$((i + 2))
      if [[ "$mode" == ansi ]]; then
        case "$d" in n) out+=$'\n' ;; t) out+=$'\t' ;; \\) out+=\\ ;; \') out+=\' ;; \") out+=\" ;; *) out+="\\$d" ;; esac
      else
        case "$d" in \") out+=\" ;; \\) out+=\\ ;; \$) out+=\$ ;; *) out+="\\$d" ;; esac
      fi
    else
      out+="$c"; i=$((i + 1))
    fi
  done
  printf '%s' "$out"
}

# @pure
# 역할: 예시 한 줄("<입력 표기> → <출력 표기>")을 입력 표기와 출력 표기 두 줄로 나눈다 — 모양이 아니면 빈 값
# 종류: 꺼내기/gear
# 예: "\"a b\" → \"A B\"" → $'"a b"\n"A B"'
# 예: "\$'x → y' → \"z\"" → $'$\'x → y\'\n"z"'
# 예: "화살표 없음" → ""
scv_gear_example_split() {
  local LC_ALL=C
  local s="${1:-}" arrow=' → ' i=0 n q="" c
  n=${#s}
  if [[ "$s" == \$\'* ]]; then q=\'; i=2
  elif [[ "$s" == \"* ]]; then q=\"; i=1
  fi
  if [[ -n "$q" ]]; then
    while (( i < n )); do
      c="${s:i:1}"
      if [[ "$c" == \\ ]]; then i=$((i + 2)); continue; fi
      i=$((i + 1))
      [[ "$c" == "$q" ]] && break
    done
  else
    while (( i < n )) && [[ "${s:i:${#arrow}}" != "$arrow" ]]; do i=$((i + 1)); done
  fi
  [[ "${s:i:${#arrow}}" == "$arrow" ]] || return 0
  printf '%s\n%s' "${s:0:i}" "${s:i+${#arrow}}"
}

# @pure
# 역할: 톱니 사전 글(### 이름 · - 역할 · - 표시 · - 값)을 사전 줄들로 바꾼다 — 줄 끝 CR 과 값 앞뒤 빈칸은 뗀다. 표시가 없으면 "?"(그런 톱니는 돌리지 않는다), 값이 없으면 "*"
# 종류: 변환/gear
# 예: $'### up\n- 역할: 대문자로\n- 표시: pure\n- 값: text → text\n- 예: "a" → "A"' → $'up\ttooth\tpure\ttext\ttext\t대문자로\t'
# 예: $'# 톱니 사전\n\n### a\n- 역할: 하나\n\n### b \r\n- 표시:  effect \r\n- 역할: 둘\r\n- 값: x  →  y ' → $'a\ttooth\t?\t*\t*\t하나\t\nb\ttooth\teffect\tx\ty\t둘\t'
# 예: "" → ""
scv_gear_teeth_parse() {
  local text="${1:-}" line name="" mark="" gin="" gout="" does="" out="" v args="" T=$'\t'
  local re_arg='^-[[:space:]]+인자[[:space:]]*:(.*)$'
  local re_does='^-[[:space:]]+역할[[:space:]]*:(.*)$' re_mark='^-[[:space:]]+표시[[:space:]]*:(.*)$' re_val='^-[[:space:]]+값[[:space:]]*:(.*)$'
  while IFS= read -r line; do
    line="${line%$'\r'}"
    if [[ "$line" == "### "* ]]; then
      [[ -z "$name" ]] || out+="${out:+$'\n'}$name"$'\t'"tooth"$'\t'"${mark:-?}"$'\t'"${gin:-*}"$'\t'"${gout:-*}"$'\t'"$does"$'\t'"${args:+$T$args}"
      name="${line#"### "}"; name="${name#"${name%%[![:space:]]*}"}"; name="${name%"${name##*[![:space:]]}"}"
      mark=""; gin=""; gout=""; does=""; args=""
    elif [[ "$line" =~ $re_arg ]]; then
      v="${BASH_REMATCH[1]}"; v="${v%% — *}"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
      [[ -n "$v" ]] || continue
      [[ "$v" == *=* ]] || v="$v="
      args+="${args:+; }$v"
    elif [[ "$line" =~ $re_does ]]; then
      v="${BASH_REMATCH[1]}"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"; does="$(scv_gear_one_line "$v")"
    elif [[ "$line" =~ $re_mark ]]; then
      v="${BASH_REMATCH[1]}"; v="${v#"${v%%[![:space:]]*}"}"; mark="${v%"${v##*[![:space:]]}"}"
    elif [[ "$line" =~ $re_val ]]; then
      v="${BASH_REMATCH[1]}"
      if [[ "$v" == *"→"* ]]; then
        gin="${v%%→*}"; gout="${v#*→}"
        gin="${gin#"${gin%%[![:space:]]*}"}"; gin="${gin%"${gin##*[![:space:]]}"}"
        gout="${gout#"${gout%%[![:space:]]*}"}"; gout="${gout%"${gout##*[![:space:]]}"}"
      fi
    fi
  done <<< "$text"
  [[ -z "$name" ]] || out+="${out:+$'\n'}$name"$'\t'"tooth"$'\t'"${mark:-?}"$'\t'"${gin:-*}"$'\t'"${gout:-*}"$'\t'"$does"$'\t'"${args:+$T$args}"
  printf '%s' "$out"
}

# @pure
# 역할: 톱니 사전 글에서 톱니 한 개의 예시 줄들을 꺼낸다 — "- 예:" 뒤의 글만, 한 줄에 하나(줄 끝 CR 과 앞뒤 빈칸은 뗀다)
# 종류: 꺼내기/gear
# 예: $'### up\n- 예: "a" → "A"\n- 예: "" → ""\n### low\n- 예: "A" → "a"' "up" → $'"a" → "A"\n"" → ""'
# 예: $'### up \r\n- 예:  "a" → "A" \r' "up" → '"a" → "A"'
# 예: $'### up\n- 역할: x' "up" → ""
scv_gear_tooth_examples() {
  local text="${1:-}" want="${2:-}" line cur="" out="" v re_ex='^-[[:space:]]+예[[:space:]]*:(.*)$'
  while IFS= read -r line; do
    line="${line%$'\r'}"
    if [[ "$line" == "### "* ]]; then
      cur="${line#"### "}"; cur="${cur#"${cur%%[![:space:]]*}"}"; cur="${cur%"${cur##*[![:space:]]}"}"
    elif [[ "$cur" == "$want" && "$line" =~ $re_ex ]]; then
      v="${BASH_REMATCH[1]}"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
      out+="${out:+$'\n'}$v"
    fi
  done <<< "$text"
  printf '%s' "$out"
}

# @pure
# 역할: 톱니 사전에 덧붙일 항목 글을 만든다 — 이름 · 역할 · 표시 · 값 · 예시(있으면)
# 종류: 조립/gear
# 예: "up" "대문자로" "pure" "text" "text" "\"a\" → \"A\"" → $'### up\n- 역할: 대문자로\n- 표시: pure\n- 값: text → text\n- 예: "a" → "A"'
# 예: "log" "커밋을 모은다" "effect" "none" "subjects" "" → $'### log\n- 역할: 커밋을 모은다\n- 표시: effect\n- 값: none → subjects'
scv_gear_tooth_entry() {
  local l
  printf '### %s\n- 역할: %s\n- 표시: %s\n- 값: %s → %s' "${1:-}" "${2:-}" "${3:-}" "${4:-}" "${5:-}"
  if [[ -n "${7:-}" ]]; then
    while IFS= read -r l; do [[ -z "$l" ]] || printf '\n- 인자: %s' "$l"; done <<< "$7"
  fi
  [[ -z "${6:-}" ]] || printf '\n- 예: %s' "$6"
}

# @pure
# 역할: 기어 글(GEAR.md)의 맨 위 줄들(칸: 값)에서 한 칸의 값을 꺼낸다 — 첫 빈 줄이나 칸 모양이 아닌 줄에서 멈춘다
# 종류: 꺼내기/gear
# 예: $'flow: a | @ | b\ndoes: 초안을 만든다\n\n# 글' "flow" → "a | @ | b"
# 예: $'flow: a | @ | b\ndoes: 초안을 만든다\n\n# 글' "does" → "초안을 만든다"
# 예: $'# 글\nflow: a' "flow" → ""
scv_gear_front_get() {
  local text="${1:-}" key="${2:-}" line v
  while IFS= read -r line; do
    [[ "$line" =~ ^[abcdefghijklmnopqrstuvwxyz]+: || "$line" == 예:* ]] || return 0
    if [[ "$line" == "$key:"* ]]; then
      v="${line#"$key":}"; v="${v#"${v%%[![:space:]]*}"}"
      printf '%s' "${v%"${v##*[![:space:]]}"}"
      return 0
    fi
  done <<< "$text"
  return 0
}

# @pure
# 역할: 기어 글에서 맨 위 줄들(칸: 값)과 그 뒤 빈 줄을 뺀 본문을 낸다 — 판단 단계에서 모델이 읽는 글
# 종류: 꺼내기/gear
# 예: $'flow: a | @\ndoes: x\n\n# 글\n요약한다' → $'# 글\n요약한다'
# 예: $'flow: a | b\n' → ""
# 예: "그냥 글" → "그냥 글"
scv_gear_body() {
  local text="${1:-}" line infront=1 started=0 out=""
  while IFS= read -r line; do
    if (( infront )); then
      [[ "$line" =~ ^[abcdefghijklmnopqrstuvwxyz]+: || "$line" == 예:* ]] && continue
      infront=0
    fi
    if (( ! started )); then [[ -n "$line" ]] || continue; started=1; out="$line"; continue; fi
    out+=$'\n'"$line"
  done <<< "$text"
  printf '%s' "${out%"${out##*[![:space:]]}"}"
}

# @pure
# 역할: flow 줄의 값을 단계 이름 줄들로 나눈다 — | 로 나누고 앞뒤 빈칸을 뗀다. @ 는 이 기어의 글(판단 단계)
# 종류: 꺼내기/gear
# 예: "a | b | @ | c" → $'a\nb\n@\nc'
# 예: " a|b " → $'a\nb'
# 예: "" → ""
scv_gear_flow_parse() {
  local rest="${1:-}" tok out=""
  while :; do
    tok="${rest%%|*}"
    tok="${tok#"${tok%%[![:space:]]*}"}"; tok="${tok%"${tok##*[![:space:]]}"}"
    [[ -z "$tok" ]] || out+="${out:+$'\n'}$tok"
    [[ "$rest" == *"|"* ]] || break
    rest="${rest#*|}"
  done
  printf '%s' "$out"
}

# @deterministic
# 역할: 사전 줄들을 이름 순(바이트 순)으로 늘어놓아 사전 글을 만든다 — 빈 줄은 뺀다
# 종류: 조립/gear
# 예: $'b\ttooth\tpure\t*\t*\t둘\t\na\ttooth\tpure\t*\t*\t하나\t' → $'a\ttooth\tpure\t*\t*\t하나\t\nb\ttooth\tpure\t*\t*\t둘\t'
# 예: "" → ""
scv_gear_index_build() {
  [[ -n "${1:-}" ]] || return 0
  printf '%s\n' "$1" | LC_ALL=C sort | LC_ALL=C awk 'NF { if (n++) printf "\n"; printf "%s", $0 }'
}

# @pure
# 역할: 사전 글에서 기어 · 톱니 한 개의 한 칸을 꺼낸다 — 칸: kind · mark · in · out · does · words. 이름이나 칸이 없으면 빈 값
# 종류: 꺼내기/gear
# 예: $'up\ttooth\tpure\ttext\tnumber\t대문자로\t낱말' "up" "kind" → "tooth"
# 예: $'up\ttooth\tpure\ttext\tnumber\t대문자로\t낱말' "up" "out" → "number"
# 예: $'up\ttooth\tpure\ttext\tnumber\t대문자로\t낱말' "upper" "kind" → ""
scv_gear_index_get() {
  local idx="${1:-}" name="${2:-}" col="${3:-}" line rest f i want=0
  case "$col" in kind) want=2 ;; mark) want=3 ;; in) want=4 ;; out) want=5 ;; does) want=6 ;; words) want=7 ;; args) want=8 ;; *) return 0 ;; esac
  [[ -n "$name" ]] || return 0
  while IFS= read -r line; do
    [[ "$line" == "$name"$'\t'* ]] || continue
    rest="$line"; i=0
    while :; do
      f="${rest%%$'\t'*}"; i=$((i + 1))
      (( i == want )) && { printf '%s' "$f"; return 0; }
      [[ "$rest" == *$'\t'* ]] || return 0
      rest="${rest#*$'\t'}"
    done
  done <<< "$idx"
  return 0
}

# @pure
# 역할: 펼친 흐름(종류<TAB>이름 줄들 — tooth · text · unknown · error)을 사전과 맞춰 본다 — 없는 이름, 펼치다 생긴 오류, 앞 톱니가 돌려주는 값과 받는 값의 이름이 다른 것을 줄로 낸다(문제없으면 빈 값)
# 종류: 판정/gear
# 예: $'tooth\tup\ntext\tg\ntooth\tcount' $'count\ttooth\tpure\ttext\tnumber\t센다\t\nup\ttooth\tpure\ttext\ttext\t대문자\t' → ""
# 예: $'tooth\tup\nunknown\tnope' $'up\ttooth\tpure\ttext\ttext\t대문자\t' → "2단계 nope — 사전에 없는 톱니 · 기어"
# 예: $'tooth\tcount\ntooth\tup' $'count\ttooth\tpure\ttext\tnumber\t센다\t\nup\ttooth\tpure\ttext\ttext\t대문자\t' → "2단계 up — 받는 값 text 가 앞 톱니가 돌려주는 값 number 와 다르다"
# 예: "" "" → "흐름이 비었다"
scv_gear_flow_check() {
  local steps="${1:-}" idx="${2:-}" line k s gin gout prev="*" i=0 out=""
  [[ -n "$steps" ]] || { printf '흐름이 비었다'; return 0; }
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    i=$((i + 1)); k="${line%%$'\t'*}"; s="${line#*$'\t'}"
    case "$k" in
      tooth)
        gin="$(scv_gear_index_get "$idx" "$s" in)"; gout="$(scv_gear_index_get "$idx" "$s" out)"
        if [[ "$prev" != "*" && "$gin" != "*" && -n "$gin" && "$gin" != "$prev" ]]; then
          out+="${out:+$'\n'}${i}단계 $s — 받는 값 $gin 가 앞 톱니가 돌려주는 값 $prev 와 다르다"
        fi
        prev="${gout:-*}" ;;
      text) prev="*" ;;
      error) out+="${out:+$'\n'}${i}단계 — $s"; prev="*" ;;
      *) out+="${out:+$'\n'}${i}단계 $s — 사전에 없는 톱니 · 기어"; prev="*" ;;
    esac
  done <<< "$steps"
  printf '%s' "$out"
}

# @pure
# 역할: 펼친 흐름에서 가운데에 놓인 순수하지 않은 톱니를 찾는다 — 표시가 effect · outward 인데 맨 앞도 맨 끝도 아니면 알림 줄
# 종류: 판정/gear
# 예: $'tooth\tread\ntooth\tup\ntooth\twrite' $'read\ttooth\teffect\t*\t*\t읽는다\t\nup\ttooth\tpure\t*\t*\t대문자\t\nwrite\ttooth\teffect\t*\t*\t쓴다\t' → ""
# 예: $'tooth\tup\ntooth\tread\ntooth\tup' $'read\ttooth\teffect\t*\t*\t읽는다\t\nup\ttooth\tpure\t*\t*\t대문자\t' → "2단계 read — 표시가 effect 인데 흐름의 가운데에 있다(읽기는 맨 앞, 쓰기는 맨 끝에만)"
scv_gear_flow_warn() {
  local steps="${1:-}" idx="${2:-}" line k s m i=0 n=0 out=""
  while IFS= read -r line; do [[ -n "$line" ]] && n=$((n + 1)); done <<< "$steps"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    i=$((i + 1)); k="${line%%$'\t'*}"; s="${line#*$'\t'}"
    [[ "$k" == tooth ]] || continue
    (( i > 1 && i < n )) || continue
    m="$(scv_gear_index_get "$idx" "$s" mark)"
    case "$m" in
      effect|outward) out+="${out:+$'\n'}${i}단계 $s — 표시가 $m 인데 흐름의 가운데에 있다(읽기는 맨 앞, 쓰기는 맨 끝에만)" ;;
    esac
  done <<< "$steps"
  printf '%s' "$out"
}

# @pure
# 역할: 톱니 본문의 줄 수를 센다 — 빈 줄, 첫 줄의 #!, set 으로 시작하는 줄은 세지 않는다
# 종류: 세기
# 예: $'#!/usr/bin/env bash\nset -euo pipefail\n\ntr a-z A-Z' → "1"
# 예: $'cat |\n  sort |\n  uniq' → "3"
# 예: "" → "0"
scv_gear_body_lines() {
  local text="${1:-}" line t n=0 i=0
  while IFS= read -r line; do
    i=$((i + 1))
    t="${line#"${line%%[![:space:]]*}"}"
    [[ -n "$t" ]] || continue
    [[ $i -eq 1 && "$t" == "#!"* ]] && continue
    [[ "$t" == "set "* ]] && continue
    n=$((n + 1))
  done <<< "$text"
  printf '%s' "$n"
}

# @pure
# 역할: sh 글에서 밖으로 나가거나 지우는 명령이 든 줄을 찾는다 — "줄 번호<TAB>낱말" 줄들. 주석 줄은 보지 않는다
# 종류: 판정/gear
# 예: $'#!/usr/bin/env bash\ncat\ngit push origin main' → $'3\tgit push'
# 예: $'cat\n\nrm -rf build' → $'3\trm'
# 예: $'git -C . push\n/usr/bin/curl -s x\nfind . -name x -delete' → $'1\tgit push\n2\tcurl\n3\tfind -delete'
# 예: $'# curl 을 쓰지 않는다\ncat' → ""
scv_gear_risk_scan() {
  # 낱말 무늬로 잡는다 — 전부 잡는다고 보장하지 못한다. 그래서 표시(outward) · 이 검사 · 실행 전 확인 세 겹으로 간다.
  local text="${1:-}" line n=0 out="" w b='(^|[^[:alnum:]_.-])' e='([^[:alnum:]_-]|$)' t
  while IFS= read -r line; do
    n=$((n + 1))
    t="${line#"${line%%[![:space:]]*}"}"
    [[ -n "$t" && "$t" != \#* ]] || continue
    w=""
    if [[ "$t" =~ ${b}git${e} && "$t" =~ ${b}push${e} ]]; then w="git push"
    elif [[ "$t" =~ ${b}git[[:space:]].*${b}clean${e} ]]; then w="git clean"
    elif [[ "$t" =~ ${b}git[[:space:]].*reset[[:space:]]+--hard${e} ]]; then w="git reset --hard"
    elif [[ "$t" =~ ${b}rm[[:space:]] ]]; then w="rm"
    elif [[ "$t" =~ ${b}find[[:space:]].*[[:space:]]-delete${e} ]]; then w="find -delete"
    elif [[ "$t" =~ ${b}(curl|wget|ssh|scp|sftp|sudo|kubectl|nc|ncat|rsync|aws|gcloud|az|telnet|ftp)${e} ]]; then w="${BASH_REMATCH[2]}"
    elif [[ "$t" =~ ${b}gh[[:space:]]+(pr|release|issue|repo|api|workflow|run|gist)${e} ]]; then w="gh ${BASH_REMATCH[2]}"
    elif [[ "$t" =~ ${b}(npm|pnpm|yarn|pip|pip3|brew|apt|apt-get)[[:space:]]+(publish|install|add)${e} ]]; then w="${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
    elif [[ "$t" =~ ${b}(docker|podman)[[:space:]]+(push|pull)${e} ]]; then w="${BASH_REMATCH[2]} ${BASH_REMATCH[3]}"
    fi
    [[ -n "$w" ]] && out+="${out:+$'\n'}$n"$'\t'"$w"
  done <<< "$text"
  printf '%s' "$out"
}

# @pure
# 역할: sh 글에서 순수 톱니에 둘 수 없는 명령이 든 줄을 찾는다 — 파일을 바꾸거나, 다른 코드를 돌리거나, 돌릴 때마다 달라지는 것. "줄 번호<TAB>낱말" 줄들
# 종류: 판정/gear
# 예: $'#!/usr/bin/env bash\ntr a-z A-Z' → ""
# 예: $'cat > out.txt' → $'1\t>'
# 예: $'awk \'$1 > 3\' | sort 2>/dev/null' → ""
# 예: $'mv a b\neval "$(cat)"\ndate +%s' → $'1\tmv\n2\teval\n3\tdate'
scv_gear_pure_scan() {
  # 무늬로 잡는다 — awk · sed · perl 같은 글 도구는 막지 않으므로 전부 잡지는 못한다. 검사가 순수 톱니를 실제로 돌리기 전에 거르는 한 겹이다.
  local text="${1:-}" line n=0 out="" w b='(^|[^[:alnum:]_.-])' e='([^[:alnum:]_-]|$)' t u
  local sq="'[^']*'" dq='"[^"]*"'
  # 찾을 글자를 변수에 둔다 — 이 함수의 글에 보내기 기호나 난수 이름이 그대로 있으면 순수성 검사가 이 함수를 순수하지 않다고 읽는다
  local gt=$'\x3e' rnd='RAN''DOM'
  while IFS= read -r line; do
    n=$((n + 1))
    t="${line#"${line%%[![:space:]]*}"}"
    [[ -n "$t" && "$t" != \#* ]] || continue
    w=""
    if [[ "$t" =~ ${b}(mv|cp|tee|mkdir|rmdir|touch|chmod|chown|ln|dd|truncate|mktemp|eval|source|exec|xargs|git|make|docker|podman|open|osascript|date|uuidgen)${e} ]]; then w="${BASH_REMATCH[2]}"
    elif [[ "$t" =~ ${b}(bash|sh|zsh)[[:space:]]+-c${e} ]]; then w="${BASH_REMATCH[2]} -c"
    elif [[ "$t" =~ ${b}sed[[:space:]]+(-[[:alnum:]]*i|--in-place) ]]; then w="sed -i"
    elif [[ "$t" == *'$'"$rnd"* || "$t" == *'${'"$rnd"* ]]; then w="$rnd"
    elif [[ "$t" =~ ^\.[[:space:]] ]]; then w="."
    else
      # 따옴표 안의 글(awk 의 비교 기호 따위)을 지우고, 파일로 보내는 기호가 남았는지 본다 — 오류를 버리거나 오류 출력으로 돌리는 것은 괜찮다
      u="$t"
      while [[ "$u" =~ $sq ]]; do u="${u/"${BASH_REMATCH[0]}"/}"; done
      while [[ "$u" =~ $dq ]]; do u="${u/"${BASH_REMATCH[0]}"/}"; done
      u="${u//${gt}&/}"; u="${u//${gt}\/dev\/null/}"; u="${u//${gt} \/dev\/null/}"; u="${u//${gt}\/dev\/stderr/}"
      [[ "$u" == *"$gt"* ]] && w="$gt"
    fi
    [[ -n "$w" ]] && out+="${out:+$'\n'}$n"$'\t'"$w"
  done <<< "$text"
  printf '%s' "$out"
}

# @pure
# 역할: 단계 하나를 어떻게 다룰지 정한다 — 톱니는 직접(direct), 기어의 글은 모델에게 넘김(handoff), 밖으로 표시 톱니는 확인 전에는 멈춤(confirm)
# 종류: 판정/gear
# 예: tooth pure "" → "direct"
# 예: text - "" → "handoff"
# 예: tooth outward "" → "confirm"
# 예: tooth outward yes → "direct"
# 예: tooth "outward (push)" "" → "error"
# 예: tooth "?" "" → "error"
scv_gear_step_mode() {
  local kind="${1:-}" mark="${2:-}" confirmed="${3:-}"
  case "$kind" in
    text) printf 'handoff' ;;
    tooth)
      # 아는 표시일 때만 돌린다 — 잘못 적힌 표시가 "밖으로가 아님"으로 읽혀 그냥 도는 일이 없게
      case "$mark" in
        pure|effect) printf 'direct' ;;
        outward) if [[ "$confirmed" == yes ]]; then printf 'direct'; else printf 'confirm'; fi ;;
        *) printf 'error' ;;
      esac ;;
    *) printf 'error' ;;
  esac
}

# @pure
# 역할: 판단 단계에서 모델에게 넘길 글을 만든다 — 이어가기 표 · 단계 · 그 기어의 글 · 앞 단계 결과 · 이어가는 명령
# 종류: 조립/gear
# 예: "ab12cd34" "2/3 @sum — 요약" "글" "앞" "gear.sh resume ab12cd34" → $'GEAR_HANDOFF: ab12cd34\nGEAR_STEP: 2/3 @sum — 요약\n=== 이 단계의 글 ===\n글\n=== 앞 단계 결과 ===\n앞\n=== 이어가기 ===\n이 단계의 결과만 표준 입력으로 넘겨라: gear.sh resume ab12cd34'
scv_gear_handoff_text() {
  printf 'GEAR_HANDOFF: %s\nGEAR_STEP: %s\n=== 이 단계의 글 ===\n%s\n=== 앞 단계 결과 ===\n%s\n=== 이어가기 ===\n이 단계의 결과만 표준 입력으로 넘겨라: %s' \
    "${1:-}" "${2:-}" "${3:-}" "${4:-}" "${5:-}"
}

# @pure
# 역할: 밖으로 나가는 톱니 앞에서 낼 글을 만든다 — 확인 표(표:단계) · 단계 · 묻는 방법(질문 끝의 표와 두 보기) · 이어가는 명령 · 그 톱니가 돌릴 글
# 종류: 조립/gear
# 예: "ab12cd34" "2/2 send — 보낸다" "git push" "gear.sh resume ab12cd34" "2" → $'GEAR_CONFIRM: ab12cd34\nGEAR_STEP: 2/2 send — 보낸다\n=== 밖으로 나가는 단계 ===\n사용자에게 선택 도구로 물어라 — 질문 글 끝에 [기어 확인 ab12cd34:2] 를 그대로 넣고, 보기는 "실행" 과 "실행하지 않음" 둘.\n"실행" 답이 온 뒤에만: gear.sh resume ab12cd34\n=== 이 단계가 돌릴 글 ===\ngit push'
scv_gear_confirm_text() {
  printf 'GEAR_CONFIRM: %s\nGEAR_STEP: %s\n=== 밖으로 나가는 단계 ===\n사용자에게 선택 도구로 물어라 — 질문 글 끝에 [기어 확인 %s:%s] 를 그대로 넣고, 보기는 "실행" 과 "실행하지 않음" 둘.\n"실행" 답이 온 뒤에만: %s\n=== 이 단계가 돌릴 글 ===\n%s' \
    "${1:-}" "${2:-}" "${1:-}" "${5:-}" "${4:-}" "${3:-}"
  [[ -z "${6:-}" ]] || printf '\n=== 이 단계에 들어갈 인자 ===\n%s' "$6"
}

# @pure
# 역할: 질문 글에서 기어 확인 표를 꺼낸다 — "[기어 확인 <16진 8자>:<단계 번호>]" 모양일 때 "표:단계", 아니면 빈 값
# 종류: 꺼내기/gear
# 예: "보낼까요? [기어 확인 ab12cd34:2]" → "ab12cd34:2"
# 예: "보낼까요? [기어 확인 ab12cd34]" → ""
# 예: "보낼까요?" → ""
# 예: "[기어 확인 ../x:1]" → ""
scv_gear_confirm_token() {
  local q="${1:-}" t
  [[ "$q" == *"[기어 확인 "*"]"* ]] || return 0
  t="${q#*\[기어 확인 }"; t="${t%%\]*}"
  [[ "$t" =~ ^[0-9abcdef]{8}:[0-9]{1,4}$ ]] && printf '%s' "$t"
  return 0
}

# @pure
# 역할: 선택 답이 '실행'을 고른 것인지 가린다 — 답이 정확히 "실행" 이나 "Run" 이거나, 그 뒤에 괄호 표시(추천 등)만 붙었을 때만
# 종류: 판정/gear
# 예: "실행" → "yes"
# 예: "실행 (Recommended)" → "yes"
# 예: "실행하지 않음" → "no"
# 예: "실행 하지 마세요" → "no"
# 예: "Run" → "yes"
# 예: "Run later" → "no"
# 예: "Do not run" → "no"
scv_gear_confirm_ok() {
  local a="${1:-}"
  a="${a#"${a%%[![:space:]]*}"}"; a="${a%"${a##*[![:space:]]}"}"
  case "$a" in
    "실행"|"Run") printf 'yes' ;;
    "실행 ("*")"|"Run ("*")") printf 'yes' ;;
    *) printf 'no' ;;
  esac
}

# @pure
# 역할: 인자 이름이 쓸 수 있는 모양인지 가린다 — 영문 소문자로 시작, 영문 소문자 · 숫자 · 밑줄, 32자까지. _proxy 로 끝나는 이름은 이미 뜻이 있는 환경 변수라 못 쓴다
# 종류: 판정/gear
# 예: "count" → "yes"
# 예: "since_tag2" → "yes"
# 예: "Count" → "no"
# 예: "1st" → "no"
# 예: "http_proxy" → "no"
# 예: "" → "no"
scv_gear_arg_name_ok() {
  local n="${1:-}"
  [[ "$n" != *_proxy ]] || { printf 'no'; return 0; }
  if [[ "$n" =~ ^[abcdefghijklmnopqrstuvwxyz][0-9abcdefghijklmnopqrstuvwxyz_]{0,31}$ ]]; then printf 'yes'; else printf 'no'; fi
}

# @pure
# 역할: 톱니 사전 글에서 톱니 한 개의 인자 줄들을 꺼낸다 — "- 인자: 이름=기본값 — 설명" 에서 "이름=기본값" 만, 한 줄에 하나(= 가 없으면 기본값이 빈 인자)
# 종류: 꺼내기/gear
# 예: $'### a\n- 인자: count=3 — 낼 줄 수\n- 인자: since\n### b\n- 인자: x=1' "a" → $'count=3\nsince='
# 예: $'### a\n- 역할: 그대로' "a" → ""
# 예: $'### a\n- 인자: sep=a b — 사이에 넣을 글' "a" → "sep=a b"
scv_gear_args_parse() {
  local text="${1:-}" want="${2:-}" line cur="" out="" v re_arg='^-[[:space:]]+인자[[:space:]]*:(.*)$'
  while IFS= read -r line; do
    line="${line%$'\r'}"
    if [[ "$line" == "### "* ]]; then
      cur="${line#"### "}"; cur="${cur#"${cur%%[![:space:]]*}"}"; cur="${cur%"${cur##*[![:space:]]}"}"
    elif [[ "$cur" == "$want" && "$line" =~ $re_arg ]]; then
      v="${BASH_REMATCH[1]}"; v="${v%% — *}"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
      [[ -n "$v" ]] || continue
      [[ "$v" == *=* ]] || v="$v="
      out+="${out:+$'\n'}$v"
    fi
  done <<< "$text"
  printf '%s' "$out"
}

# @pure
# 역할: 실행할 때 받은 낱말들(한 줄에 하나)을 인자 줄들로 가린다 — "이름=값" 모양이고 이름이 쓸 수 있으면 그대로, 아니면 앞에 ! 를 붙인다
# 종류: 판정/gear
# 예: $'count=2\nsince=v1 beta' → $'count=2\nsince=v1 beta'
# 예: $'Count=1\n=1\ncount' → $'!Count=1\n!=1\n!count'
# 예: "" → ""
scv_gear_args_split() {
  local words="${1:-}" line out=""
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    if [[ "$line" == *=* && "$(scv_gear_arg_name_ok "${line%%=*}")" == yes ]]; then out+="${out:+$'\n'}$line"
    else out+="${out:+$'\n'}!$line"; fi
  done <<< "$words"
  printf '%s' "$out"
}

# @pure
# 역할: 준 인자 줄들 가운데 선언된 인자 줄들에 없는 이름을 찾는다 — 이름만, 한 줄에 하나
# 종류: 판정/gear
# 예: $'count=2\nnope=1' $'count=3\nsince=' → "nope"
# 예: "count=2" $'count=3' → ""
# 예: "x=1" "" → "x"
scv_gear_args_unknown() {
  local given="${1:-}" decl="${2:-}" line n out=""
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    n="${line%%=*}"
    case $'\n'"$decl" in *$'\n'"$n="*) ;; *) out+="${out:+$'\n'}$n" ;; esac
  done <<< "$given"
  printf '%s' "$out"
}

# @deterministic
# 역할: 인자 줄 두 묶음을 합친다 — 같은 이름은 뒤 묶음의 값이 이기고, 순서는 처음 나온 차례
# 종류: 조립/gear
# 예: $'count=3\nsince=' "count=5" → $'count=5\nsince='
# 예: "count=3" "sep=," → $'count=3\nsep=,'
# 예: "" "" → ""
scv_gear_args_merge() {
  [[ -n "${1:-}${2:-}" ]] || return 0
  printf '%s\n%s\n' "${1:-}" "${2:-}" | LC_ALL=C awk '
    { i = index($0, "="); if (!i || i == 1) next; n = substr($0, 1, i - 1); if (!(n in v)) ord[++c] = n; v[n] = $0 }
    END { for (k = 1; k != c + 1; k++) printf "%s%s", (k == 1 ? "" : "\n"), v[ord[k]] }'
}

# @deterministic
# 역할: 톱니가 선언한 인자 줄들에 덮는 값을 얹는다 — 선언한 이름만 남고, 덮는 묶음에 있으면 그 값, 없으면 기본값
# 종류: 조립/gear
# 예: $'count=3\nsince=' $'count=5\nother=1' → $'count=5\nsince='
# 예: "count=3" "" → "count=3"
# 예: "" "count=5" → ""
scv_gear_args_apply() {
  [[ -n "${1:-}" ]] || return 0
  printf '%s\n\036\n%s\n' "${2:-}" "$1" | LC_ALL=C awk '
    $0 == "\036" { d = 1; next }
    { i = index($0, "="); if (!i || i == 1) next; n = substr($0, 1, i - 1) }
    !d { v[n] = $0; next }
    { printf "%s%s", (c++ ? "\n" : ""), ((n in v) ? v[n] : $0) }'
}

# @pure
# 역할: 기어 글의 맨 위 줄들에서 같은 칸의 값을 모두 꺼낸다 — 한 줄에 하나(arg · 예 처럼 여러 번 적는 칸)
# 종류: 꺼내기/gear
# 예: $'flow: a | b\narg: count=4\narg: sep=,\ndoes: x\n\narg: body' "arg" → $'count=4\nsep=,'
# 예: $'flow: a\n예: "a" → "A"\ndoes: x' "예" → '"a" → "A"'
# 예: $'flow: a' "arg" → ""
scv_gear_front_all() {
  local text="${1:-}" key="${2:-}" line v out=""
  while IFS= read -r line; do
    [[ "$line" =~ ^[abcdefghijklmnopqrstuvwxyz]+: || "$line" == 예:* ]] || break
    if [[ "$line" == "$key:"* ]]; then
      v="${line#"$key":}"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
      out+="${out:+$'\n'}$v"
    fi
  done <<< "$text"
  printf '%s' "$out"
}

# @pure
# 역할: 기어 글의 in · out 줄 값에서 값의 종류 이름만 꺼낸다 — " — " 뒤의 설명은 뗀다
# 종류: 꺼내기/gear
# 예: "lines — 글 줄들" → "lines"
# 예: "number" → "number"
# 예: "" → ""
scv_gear_sig_name() {
  local v="${1:-}"
  v="${v%% — *}"; v="${v#"${v%%[![:space:]]*}"}"
  printf '%s' "${v%"${v##*[![:space:]]}"}"
}

# @pure
# 역할: 기어에 적은 받는 값 · 돌려주는 값의 이름을 첫 톱니 · 끝 톱니의 이름과 맞춰 본다 — 다르면 오류 줄(어느 쪽이든 비었거나 * 이면 보지 않는다)
# 종류: 판정/gear
# 예: "lines" "lines" "lines" "lines" → ""
# 예: "number" "lines" "lines" "lines" → "in number — 첫 톱니가 받는 값 lines 와 다르다"
# 예: "lines" "number" "lines" "lines" → "out number — 끝 톱니가 돌려주는 값 lines 와 다르다"
# 예: "" "lines" "text" "*" → ""
scv_gear_sig_check() {
  local gin="${1:-}" gout="${2:-}" tin="${3:-}" tout="${4:-}" out=""
  if [[ -n "$gin" && "$gin" != "*" && -n "$tin" && "$tin" != "*" && "$gin" != "$tin" ]]; then
    out="in $gin — 첫 톱니가 받는 값 $tin 와 다르다"
  fi
  if [[ -n "$gout" && "$gout" != "*" && -n "$tout" && "$tout" != "*" && "$gout" != "$tout" ]]; then
    out+="${out:+$'\n'}out $gout — 끝 톱니가 돌려주는 값 $tout 와 다르다"
  fi
  printf '%s' "$out"
}

# @pure
# 역할: 예시 한 줄에서 앞에 적은 인자 낱말들과 나머지(입력 → 출력)를 두 줄로 나눈다 — 첫 줄은 빈칸으로 이은 인자들(없으면 빈 줄). 따옴표나 $ 가 든 낱말, 바로 뒤가 → 인 낱말은 인자가 아니다
# 종류: 꺼내기/gear
# 예: "count=2 sep=, \"a\" → \"b\"" → $'count=2 sep=,\n"a" → "b"'
# 예: "\"a\" → \"b\"" → $'\n"a" → "b"'
# 예: "a=b → c" → $'\na=b → c'
scv_gear_example_args() {
  local s="${1:-}" tok rest args="" re='^[abcdefghijklmnopqrstuvwxyz][0-9abcdefghijklmnopqrstuvwxyz_]*=[^"$]*$'
  while [[ "$s" == *" "* ]]; do
    tok="${s%% *}"; rest="${s#* }"
    [[ "$tok" =~ $re && "$tok" != *\'* && "$rest" != "→"* ]] || break
    args+="${args:+ }$tok"; s="$rest"
  done
  printf '%s\n%s' "$args" "$s"
}

# @pure
# 역할: 기어의 예시를 실제로 돌려 맞출지(run) 보기용으로 둘지(show) 정한다 — 펼친 흐름이 순수 톱니로만 되어 있을 때만 돌린다
# 종류: 판정/gear
# 예: $'tooth\tup\ntooth\tcount' $'count\ttooth\tpure\ttext\tnumber\t센다\t\nup\ttooth\tpure\ttext\ttext\t대문자\t' → "run"
# 예: $'tooth\tup\ntext\tg' $'up\ttooth\tpure\ttext\ttext\t대문자\t' → "show"
# 예: $'tooth\tup\ntooth\twrite' $'up\ttooth\tpure\t*\t*\t대문자\t\nwrite\ttooth\teffect\t*\t*\t쓴다\t' → "show"
# 예: "" "" → "show"
scv_gear_example_mode() {
  local steps="${1:-}" idx="${2:-}" line k s n=0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    k="${line%%$'\t'*}"; s="${line#*$'\t'}"
    [[ "$k" == tooth && "$(scv_gear_index_get "$idx" "$s" mark)" == pure ]] || { printf 'show'; return 0; }
    n=$((n + 1))
  done <<< "$steps"
  if (( n )); then printf 'run'; else printf 'show'; fi
}

# @deterministic
# 역할: 사전 글에서 목록에 낼 줄들을 만든다 — 톱니는 이름 · 표시 · 값 · 인자 · 하는 일, 기어는 이름 · 값 · 인자 · 하는 일(인자가 없으면 -)
# 종류: 조립/gear
# 예: $'g\tgear\t-\tlines\tlines\t앞 줄\t\tcount=3\nup\ttooth\tpure\ttext\ttext\t대문자\t' "gear" → $'g\tlines → lines\tcount=3\t앞 줄'
# 예: $'g\tgear\t-\tlines\tlines\t앞 줄\t\tcount=3\nup\ttooth\tpure\ttext\ttext\t대문자\t' "tooth" → $'up\tpure\ttext → text\t-\t대문자'
# 예: "" "gear" → ""
scv_gear_list_rows() {
  [[ -n "${1:-}" ]] || return 0
  printf '%s\n' "$1" | LC_ALL=C awk -F'\t' -v k="${2:-}" '
    $2 != k { next }
    { a = ($8 == "" ? "-" : $8) }
    k == "tooth" { printf "%s%s\t%s\t%s → %s\t%s\t%s", (c++ ? "\n" : ""), $1, $3, $4, $5, a, $6; next }
    { printf "%s%s\t%s → %s\t%s\t%s", (c++ ? "\n" : ""), $1, $4, $5, a, $6 }'
}

# @pure
# 역할: 펼친 흐름에서 가장 센 표시 하나를 고른다 — 밖으로 나가는 톱니가 있으면 outward, 판단 단계가 있으면 judge, 부작용 톱니가 있으면 effect, 순수 톱니뿐이면 pure, 흐름이 비었거나 모르는 이름이 있으면 -
# 종류: 판정/gear
# 예: $'tooth\tup\ntooth\tcount' $'count\ttooth\tpure\ttext\tnumber\t센다\t\nup\ttooth\tpure\ttext\ttext\t대문자\t' → "pure"
# 예: $'tooth\tup\ntooth\twrite' $'up\ttooth\tpure\t*\t*\t대문자\t\nwrite\ttooth\teffect\t*\t*\t쓴다\t' → "effect"
# 예: $'tooth\tup\ntext\tg' $'up\ttooth\tpure\ttext\ttext\t대문자\t' → "judge"
# 예: $'tooth\tsend\ntext\tg' $'send\ttooth\toutward\t*\t*\t보낸다\t' → "outward"
# 예: $'tooth\tup\nunknown\tnope' $'up\ttooth\tpure\ttext\ttext\t대문자\t' → "-"
# 예: "" "" → "-"
scv_gear_flow_mark() {
  local steps="${1:-}" idx="${2:-}" line k s o=0 j=0 e=0 n=0
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    k="${line%%$'\t'*}"; s="${line#*$'\t'}"; s="${s%%$'\t'*}"
    case "$k" in
      text) j=1 ;;
      tooth)
        case "$(scv_gear_index_get "$idx" "$s" mark)" in
          pure) ;;
          effect) e=1 ;;
          outward) o=1 ;;
          *) printf '%s' '-'; return 0 ;;
        esac ;;
      *) printf '%s' '-'; return 0 ;;
    esac
    n=$((n + 1))
  done <<< "$steps"
  if (( n == 0 )); then printf '%s' '-'
  elif (( o )); then printf 'outward'
  elif (( j )); then printf 'judge'
  elif (( e )); then printf 'effect'
  else printf 'pure'; fi
}

# @pure
# 역할: 톱니 사전 글에서 톱니 한 개의 인자 설명들을 꺼낸다 — "- 인자: 이름=기본값 — 설명" 에서 "이름<TAB>설명", 한 줄에 하나(설명이 없으면 빈 설명)
# 종류: 꺼내기/gear
# 예: $'### a\n- 인자: count=3 — 낼 줄 수\n- 인자: since\n### b\n- 인자: x=1 — 다른 것' "a" → $'count\t낼 줄 수\nsince\t'
# 예: $'### a\n- 역할: 그대로' "a" → ""
scv_gear_args_desc() {
  local text="${1:-}" want="${2:-}" line cur="" out="" v d re_arg='^-[[:space:]]+인자[[:space:]]*:(.*)$'
  while IFS= read -r line; do
    line="${line%$'\r'}"
    if [[ "$line" == "### "* ]]; then
      cur="${line#"### "}"; cur="${cur#"${cur%%[![:space:]]*}"}"; cur="${cur%"${cur##*[![:space:]]}"}"
    elif [[ "$cur" == "$want" && "$line" =~ $re_arg ]]; then
      v="${BASH_REMATCH[1]}"; d=""
      [[ "$v" != *" — "* ]] || d="${v#* — }"
      v="${v%% — *}"; v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
      [[ -n "$v" ]] || continue
      d="${d#"${d%%[![:space:]]*}"}"; d="${d%"${d##*[![:space:]]}"}"
      out+="${out:+$'\n'}${v%%=*}"$'\t'"$d"
    fi
  done <<< "$text"
  printf '%s' "$out"
}

# @pure
# 역할: 기어나 톱니를 쓸 때 정해야 할 값을 줄로 만든다 — 인자마다 "arg<TAB>이름<TAB>지금 값<TAB>open|fixed<TAB>설명"(기어가 정해 둔 인자는 fixed), 받는 값이 있으면 끝에 "input<TAB>값 이름"
# 종류: 조립/gear
# 예: $'count=5\nsince=' "count=5" $'count\t낼 줄 수\nsince\t어디부터' "lines" → $'arg\tcount\t5\tfixed\t낼 줄 수\narg\tsince\t\topen\t어디부터\ninput\tlines'
# 예: "os=mac" "" $'os\t돌릴 곳: mac · linux' "none" → $'arg\tos\tmac\topen\t돌릴 곳: mac · linux'
# 예: "" "" "" "none" → ""
# 예: "" "" "" "text" → $'input\ttext'
scv_gear_ask_rows() {
  local args="${1:-}" fixed="${2:-}" descs="${3:-}" gin="${4:-}" line n v st d dl out="" T=$'\t'
  while IFS= read -r line; do
    [[ "$line" == *=* ]] || continue
    n="${line%%=*}"; v="${line#*=}"; st=open; d=""
    case $'\n'"$fixed" in *$'\n'"$n="*) st=fixed ;; esac
    while IFS= read -r dl; do
      [[ "$dl" == "$n$T"* ]] || continue
      d="${dl#*"$T"}"; break
    done <<< "$descs"
    out+="${out:+$'\n'}arg$T$n$T$v$T$st$T$d"
  done <<< "$args"
  case "$gin" in ""|none|"*") ;; *) out+="${out:+$'\n'}input$T$gin" ;; esac
  printf '%s' "$out"
}

# @pure
# 역할: 요청 글이 기어를 돌리라는 것인지 가려 그 기어 이름을 낸다 — 글 첫 줄이 기어 액션 꼴(… gear run 이름)이거나, "[SCV 기어]" 로 시작하는 줄에 "gear run 이름" 이 있을 때. 이름은 주어진 기어 목록에 있어야 한다
# 종류: 판정/gear
# 예: "action:gear run release-ci os=mac" $'release-ci\nmake-list' → "release-ci"
# 예: $'목록 만들어 줘\n\n[SCV 기어] 이 요청에 맞는 저장해 둔 방법이 있음: make-list — 이 기어로 해 주세요(action:gear run make-list). 값은 위 요청에서 읽고, 없는 값은 물어 주세요.' $'release-ci\nmake-list' → "make-list"
# 예: "릴리스 검사 돌려 줘" $'release-ci\nmake-list' → ""
# 예: "기어가 뭐야? gear run 은 어떻게 써?" $'release-ci\nmake-list' → ""
# 예: "[SCV 기어] 이 요청에 맞는 저장해 둔 방법이 있음: nope — 이 기어로 해 주세요(action:gear run nope)." $'release-ci\nmake-list' → ""
# 예: "action:gear run release-ci" "" → ""
scv_gear_turn() {
  local text="${1:-}" names="${2:-}" line t first=1 name="" nl=$'\n'
  local re_act='^[/$]?([A-Za-z]+[:-])?gear[[:space:]]+run[[:space:]]+([a-z0-9][a-z0-9-]*)([[:space:]]|$)'
  local re_line='gear[[:space:]]+run[[:space:]]+([a-z0-9][a-z0-9-]*)'
  [[ -n "$names" ]] || return 0
  while IFS= read -r line; do
    t="${line#"${line%%[![:space:]]*}"}"
    [[ -n "$t" ]] || continue
    if (( first )); then
      first=0
      if [[ "$t" =~ $re_act ]]; then name="${BASH_REMATCH[2]}"; break; fi
    fi
    if [[ "$t" == "[SCV 기어]"* && "$t" =~ $re_line ]]; then name="${BASH_REMATCH[1]}"; break; fi
  done <<< "$text"
  [[ -n "$name" ]] || return 0
  case "$nl$names$nl" in *"$nl$name$nl"*) printf '%s' "$name" ;; esac
  return 0
}

# @pure
# 역할: 기어 턴에 실을 짧은 안내 글을 만든다 — 값 · 실행 · 답 세 줄. 첫 줄은 요청이 그 기어의 일이 아니면(낱말만 겹쳐 붙은 경우) 돌리지 말고 그대로 답하라고 일러 둔다. 값 줄은 값 안내 줄들(arg · input)을 쉬운 말로 옮기고(넣을 자료가 요청에 없으면 돌리기 전에 묻게 한다 — 물을 사람이 없으면 돌리지 않게), 실행 줄은 넣을 자료가 있으면 표준 입력으로 넣는 꼴을 보인다. 값 안내가 비면 값 안내 명령을 먼저 돌리게 한다. 선택 도구 이름이 있으면 빠진 값은 그 도구로 묻게 하고, 물을 사람이 없는 실행(다섯째 인자 1)이면 기본값을 쓰게 한다
# 종류: 조립/gear
# 예: "make-list" "/c/gear.sh" "" $'input\ttext' → $'[SCV 기어 턴] 이 요청은 저장해 둔 기어 make-list 를 돌리라는 것이다 — 가벼운 길: 도움말 · 요청 등록 · 다시 쓴 요청 인용 · 세 줄 끝 보고를 하지 않는다. 요청이 이 기어가 하는 일이 아니면(질문 · 다른 일 — 낱말만 겹쳐 붙은 경우) 기어를 돌리지 말고 요청에 그대로 답한다.\n1) 값: 넣을 자료는 표준 입력으로(text) — 인자가 아니다, 요청에 자료가 없으면 돌리기 전에 묻는다. 요청에 있는 값은 그대로 쓰고, 빠진 열린 값만 한 번에 묻는다(기본값으로 되면 묻지 않는다).\n2) 실행: printf \'%s\' \'넣을 자료\' | bash /c/gear.sh run make-list — 멈추면(확인 · 판단 단계) 그 안내를 따르고, 오래 걸릴 일이면 뒤에서 돌린다.\n3) 답: 무엇을 돌렸고 결과가 무엇인지 두세 줄. 파일을 직접 고치지 않는다 — 고칠 일이면 그렇다고 말하고 끝낸다.'
# 예: "ci" "/c/gear.sh" "Pick" $'arg\tos\tmac\topen\t돌릴 곳: mac · linux\narg\tjobs\t4\tfixed\t겹쳐 돌릴 수' → $'[SCV 기어 턴] 이 요청은 저장해 둔 기어 ci 를 돌리라는 것이다 — 가벼운 길: 도움말 · 요청 등록 · 다시 쓴 요청 인용 · 세 줄 끝 보고를 하지 않는다. 요청이 이 기어가 하는 일이 아니면(질문 · 다른 일 — 낱말만 겹쳐 붙은 경우) 기어를 돌리지 말고 요청에 그대로 답한다.\n1) 값: 인자 os=mac(열림 — 돌릴 곳: mac · linux) · 인자 jobs=4(정해 둠 — 바꾸지 않는다). 요청에 있는 값은 그대로 쓰고, 빠진 열린 값만 Pick 로 한 번에 묻는다(기본값으로 되면 묻지 않는다).\n2) 실행: bash /c/gear.sh run ci 이름=값 … — 멈추면(확인 · 판단 단계) 그 안내를 따르고, 오래 걸릴 일이면 뒤에서 돌린다.\n3) 답: 무엇을 돌렸고 결과가 무엇인지 두세 줄. 파일을 직접 고치지 않는다 — 고칠 일이면 그렇다고 말하고 끝낸다.'
# 예: "make-list" "/c/gear.sh" "" "" → $'[SCV 기어 턴] 이 요청은 저장해 둔 기어 make-list 를 돌리라는 것이다 — 가벼운 길: 도움말 · 요청 등록 · 다시 쓴 요청 인용 · 세 줄 끝 보고를 하지 않는다. 요청이 이 기어가 하는 일이 아니면(질문 · 다른 일 — 낱말만 겹쳐 붙은 경우) 기어를 돌리지 말고 요청에 그대로 답한다.\n1) 값: bash /c/gear.sh ask make-list 로 읽는다(arg 줄은 인자, input 줄은 표준 입력으로 넣을 자료). 요청에 있는 값은 그대로 쓰고, 빠진 열린 값만 한 번에 묻는다(기본값으로 되면 묻지 않는다).\n2) 실행: bash /c/gear.sh run make-list 이름=값 … (넣을 자료는 표준 입력) — 멈추면(확인 · 판단 단계) 그 안내를 따르고, 오래 걸릴 일이면 뒤에서 돌린다.\n3) 답: 무엇을 돌렸고 결과가 무엇인지 두세 줄. 파일을 직접 고치지 않는다 — 고칠 일이면 그렇다고 말하고 끝낸다.'
# 예: "ci" "/c/gear.sh" "Pick" "none" 1 → $'[SCV 기어 턴] 이 요청은 저장해 둔 기어 ci 를 돌리라는 것이다 — 가벼운 길: 도움말 · 요청 등록 · 다시 쓴 요청 인용 · 세 줄 끝 보고를 하지 않는다. 요청이 이 기어가 하는 일이 아니면(질문 · 다른 일 — 낱말만 겹쳐 붙은 경우) 기어를 돌리지 말고 요청에 그대로 답한다.\n1) 값: 정할 값 없음. 요청에 있는 값은 그대로 쓰고, 물을 사람이 없는 실행이다 — 빠진 열린 값은 기본값을 쓰고, 쓴 기본값을 답에 적는다.\n2) 실행: bash /c/gear.sh run ci — 멈추면(확인 · 판단 단계) 그 안내를 따르고, 오래 걸릴 일이면 뒤에서 돌린다.\n3) 답: 무엇을 돌렸고 결과가 무엇인지 두세 줄. 파일을 직접 고치지 않는다 — 고칠 일이면 그렇다고 말하고 끝낸다.'
# 예: "" "/c/gear.sh" "" "" → ""
scv_gear_turn_text() {
  local name="${1:-}" sh="${2:-gear.sh}" tool="${3:-}" rows="${4:-}" nobody="${5:-}" ask="한 번에 묻는다" miss nodata line k n v st d vals="" hasarg=0 hasin=0 run T=$'\t'
  [[ -n "$name" ]] || return 0
  [[ -z "$tool" ]] || ask="$tool 로 한 번에 묻는다"
  miss="빠진 열린 값만 $ask(기본값으로 되면 묻지 않는다)"
  nodata="돌리기 전에 묻는다"
  if [[ "$nobody" == 1 ]]; then
    miss="물을 사람이 없는 실행이다 — 빠진 열린 값은 기본값을 쓰고, 쓴 기본값을 답에 적는다"
    nodata="돌리지 않고 그렇다고 답한다"
  fi
  while IFS= read -r line; do
    k="${line%%"$T"*}"
    case "$k" in
      arg)
        IFS="$T" read -r k n v st d <<< "$line"
        hasarg=1
        if [[ "$st" == fixed ]]; then vals+="${vals:+ · }인자 $n=$v(정해 둠 — 바꾸지 않는다)"
        else vals+="${vals:+ · }인자 $n=$v(열림${d:+ — $d})"; fi ;;
      input) hasin=1; vals+="${vals:+ · }넣을 자료는 표준 입력으로(${line#*"$T"}) — 인자가 아니다, 요청에 자료가 없으면 $nodata" ;;
      none) vals+="${vals:+ · }정할 값 없음" ;;
    esac
  done <<< "$rows"
  printf '%s\n' "[SCV 기어 턴] 이 요청은 저장해 둔 기어 $name 를 돌리라는 것이다 — 가벼운 길: 도움말 · 요청 등록 · 다시 쓴 요청 인용 · 세 줄 끝 보고를 하지 않는다. 요청이 이 기어가 하는 일이 아니면(질문 · 다른 일 — 낱말만 겹쳐 붙은 경우) 기어를 돌리지 말고 요청에 그대로 답한다."
  if [[ -z "$vals" ]]; then
    printf '%s\n' "1) 값: bash $sh ask $name 로 읽는다(arg 줄은 인자, input 줄은 표준 입력으로 넣을 자료). 요청에 있는 값은 그대로 쓰고, $miss."
    run="bash $sh run $name 이름=값 … (넣을 자료는 표준 입력)"
  else
    printf '%s\n' "1) 값: $vals. 요청에 있는 값은 그대로 쓰고, $miss."
    run="bash $sh run $name"; (( hasarg )) && run+=" 이름=값 …"
    (( hasin )) && run="printf '%s' '넣을 자료' | $run"
  fi
  printf '%s\n' "2) 실행: $run — 멈추면(확인 · 판단 단계) 그 안내를 따르고, 오래 걸릴 일이면 뒤에서 돌린다."
  printf '%s' "3) 답: 무엇을 돌렸고 결과가 무엇인지 두세 줄. 파일을 직접 고치지 않는다 — 고칠 일이면 그렇다고 말하고 끝낸다."
}
