#!/usr/bin/env bash
# gear.sh — 기어(스킬)와 톱니(아주 작은 sh)를 만들고 · 검사하고 · 돌린다 (계획 20261124-wookiya1364-gears-run).
#
# 되풀이되는 작업에서 정해진 흐름은 톱니가 돌고, 모델은 판단이 필요한 자리의 글과 앞 단계 결과만 읽게 한다.
# 모두 프로젝트의 scv/gears/ 안에만 있다 — 호스트의 스킬 폴더에는 아무것도 쓰지 않는다.
#
#   gear.sh list                         기어와 톱니를 보여 준다(없으면 "기어 없음" 한 줄)
#   gear.sh new <이름> --kind tooth [--does "<하는 일>"] [--mark pure|effect|outward] [--in <받는 값>] [--out <돌려주는 값>]
#                      [--arg '<이름>=<기본값> — <설명>']… [--example '[<이름>=<값>…] <입력 표기> → <출력 표기>']
#   gear.sh new <이름> --kind gear --flow "<톱니> | <톱니> | @ | <톱니>" [--does "<하는 일>"] [--words "<낱말들>"]
#                      [--in <받는 값>] [--out <돌려주는 값>] [--arg <이름>=<값>]… [--example '…']
#                                        뼈대 파일을 쓰고 사전을 다시 만든다 (@ 는 이 기어의 글 — 판단 단계).
#                                        기어의 --in · --out 을 안 주면 첫 · 끝 톱니의 값 이름으로 채운다
#   gear.sh ask <이름>                    쓸 때 정해야 할 값을 줄로 낸다 — arg<TAB>이름<TAB>지금 값<TAB>open|fixed<TAB>설명, input<TAB>받는 값 (없으면 none)
#   gear.sh index                        톱니 사전과 기어 글에서 사전(INDEX.tsv)을 다시 만든다
#   gear.sh check                        사전 · 파일 · 흐름 · 순수 톱니의 예시 · 표시 없는 위험 명령을 검사한다
#   gear.sh run <이름> [<인자>=<값>]…      기어나 톱니를 돌린다 — 처음 입력은 표준 입력, 조절 값은 이름 붙은 인자
#   gear.sh resume <표>                   멈춘 실행을 잇는다 — 판단 단계 뒤에는 그 단계의 결과를 표준 입력으로(인자는 처음 준 그대로)
#   gear.sh detect [--kind human|auto]   매 턴 훅이 부른다 — 표준 입력의 요청 글을 지난 요청 · 기어 사전과 맞춰 보고, 겹칠 때만
#                                        알림 한 줄을 낸 뒤 요청을 기록에 쌓는다(계획 gears-detect). 겹치지 않으면 아무것도 내지 않는다
#   gear.sh decline                      방금 알린 요청을 "기어로 만들지 않음"으로 적는다 — 그 요청은 다시 알리지 않는다
#   gear.sh confirm --question <글> --answer <글>
#                                        선택 답 훅이 부른다 — 질문에 [기어 확인 <표>] 가 있고 답이 "실행"이면 확인으로 적는다
#
# 자리:  scv/gears/teeth/<톱니>.sh      톱니 본문 — 표준 입력 → 표준 출력, 한 가지 일만. 주석 없이 본문만 둔다
#        scv/gears/teeth/TEETH.md       톱니 사전(원본) — 톱니마다 역할 · 표시 · 값 · 예시
#        scv/gears/<기어>/GEAR.md        기어 — 맨 위 flow · in · out · arg · 예 · does · words 줄, 그 아래 판단 단계의 글
# 인자:  톱니 사전의 "- 인자: 이름=기본값" → 기어 글의 "arg: 이름=값"(바깥 기어가 안쪽을 이긴다) → 실행할 때 준 값. 뒤가 이긴다.
#        톱니는 자기가 선언한 인자만 같은 이름의 환경 변수로 받는다. 어느 톱니도 선언하지 않은 이름을 주면 돌리지 않는다(2).
# 값:    기어 글의 in · out 은 값의 종류 이름(고정된 값이 아니다), 예 는 "이 입력이면 이 출력"의 한 가지 경우다.
#        순수 톱니로만 된 기어의 예시는 검사가 실제로 돌려 맞춰 보고, 판단 단계나 순수하지 않은 톱니가 있으면 보기용으로 둔다.
#        scv/gears/INDEX.tsv            만든 사전 — 이 스크립트가 쓴다(손으로 고치지 않는다)
# 실행: 톱니는 앞 단계의 출력을 입력으로 받아 바로 돈다. 판단 단계(@)에서는 그 기어의 글 · 앞 결과 · 이어가기 표만 내고
#       멈춘다(종료 코드 10). 밖으로 표시(outward) 톱니 앞에서는 돌리지 않고 멈춘다(11) — 사용자의 "실행" 답이 적힌 뒤에만 잇는다.
# 상태: 실행 도중의 상태는 기록 폴더의 숨김 자리(<저널>/.gear-run/<표>/)에 둔다 — 훅과 같은 자리를 보고, 커밋되지 않는다.
# 표시: pure(받은 값으로 계산만 — 예시가 하나 이상) · effect(프로젝트 안 파일 읽기 · 쓰기) · outward(push · 네트워크 · 삭제 — 실행 전 확인)
# 검사는 순수 톱니를 예시 입력으로 실제로 돌린다 — 위험 명령이 잡힌 톱니는 돌리지 않는다.
# Exit: 0 끝 · 1 검사 실패나 단계 실패 · 2 잘못된 인자 · 모르는 표 · 10 판단 단계에서 멈춤 · 11 확인이 필요해 멈춤
set -uo pipefail
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
# shellcheck source=lib/gear.sh
source "$SCRIPT_DIR/lib/gear.sh"

GDIR="${SCV_GEARS_DIR:-scv/gears}"
TDIR="$GDIR/teeth"
TDICT="$TDIR/TEETH.md"
JDIR="${SCV_JOURNAL_DIR:-scv/journal}"
STATE="${SCV_GEAR_STATE_DIR:-$JDIR/.gear-run}"
MAXLINES="${SCV_GEAR_TOOTH_MAX_LINES:-12}"
EXSECS="${SCV_GEAR_EXAMPLE_SECONDS:-5}"
SELF="bash \"$SCRIPT_DIR/gear.sh\""

# @effect usage
# 이유: 쓰는 법을 표준 오류에 쓰고 종료 코드 2 로 끝낸다
usage() {
  sed -n '6,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

# @effect die
# 이유: 오류 한 줄을 표준 오류에 쓰고 주어진 종료 코드로 끝낸다
die() { printf 'GEAR_ERROR: %s\n' "$2" >&2; exit "$1"; }

# @effect teeth_text
# 이유: 톱니 사전 파일을 읽는다(없으면 빈 값)
teeth_text() { [[ -f "$TDICT" ]] && cat "$TDICT"; return 0; }

# @effect flat_walk
# 이유: 기어 글 파일들을 읽어 흐름을 펼친다 — 톱니는 그대로, @ 는 그 기어의 글, 다른 기어 이름은 그 기어의 흐름으로(되돌아오거나 8단을 넘으면 오류 줄). 톱니 줄의 셋째 칸은 그 단계에 걸린 기어들의 arg 줄(바깥 기어가 안쪽을 이긴다 — 줄 사이는 \037)
flat_walk() {
  local g="$1" tidx="$2" depth="$3" seen="$4" ov="${5:-}" text tok own ovcol
  (( depth <= 8 )) || { printf 'error\t%s — 흐름이 너무 깊다(8단 넘음)\n' "$g"; return 0; }
  case " $seen " in *" $g "*) printf 'error\t%s — 흐름이 자기 자신으로 돌아온다\n' "$g"; return 0 ;; esac
  [[ -f "$GDIR/$g/GEAR.md" ]] || { printf 'unknown\t%s\n' "$g"; return 0; }
  text="$(cat "$GDIR/$g/GEAR.md")"
  [[ -n "$(scv_gear_flow_parse "$(scv_gear_front_get "$text" flow)")" ]] || { printf 'error\t%s — 맨 위에 flow 줄이 없다\n' "$g"; return 0; }
  # 인자 줄이 하나도 없으면(대부분의 기어) 합치는 프로그램을 띄우지 않는다
  own=""; [[ "$text" != *$'\n'"arg:"* ]] || own="$(scv_gear_front_all "$text" arg)"
  [[ -z "$own" ]] || ov="$(scv_gear_args_merge "$own" "$ov")"
  ovcol=""; [[ -z "$ov" ]] || ovcol="$(printf '%s' "$ov" | tr '\n' '\037')"
  while IFS= read -r tok; do
    [[ -n "$tok" ]] || continue
    if [[ "$tok" == "@" ]]; then printf 'text\t%s\n' "$g"
    elif [[ -n "$(scv_gear_index_get "$tidx" "$tok" kind)" ]]; then printf 'tooth\t%s\t%s\n' "$tok" "$ovcol"
    elif [[ "$(scv_gear_name_ok "$tok")" == yes && -f "$GDIR/$tok/GEAR.md" ]]; then flat_walk "$tok" "$tidx" $((depth + 1)) "$seen $g" "$ov"
    else printf 'unknown\t%s\n' "$tok"
    fi
  done <<< "$(scv_gear_flow_parse "$(scv_gear_front_get "$text" flow)")"
  return 0
}

# @effect flat_flow
# 이유: 기어 글 파일들을 읽어 펼친 흐름(종류 · 이름 두 칸)을 낸다
flat_flow() { flat_walk "$1" "$2" "$3" "$4" "" | cut -f1,2; }

# @effect step_ov
# 이유: 펼친 흐름(flat_walk 의 출력)에서 한 단계에 걸린 기어들의 인자 줄들을 꺼낸다(글을 읽기만 한다)
step_ov() { printf '%s\n' "$1" | sed -n "${2}p" | cut -s -f3 | tr '\037' '\n'; }

# @effect flow_decl
# 이유: 톱니 사전 글에서, 펼친 흐름의 톱니들이 선언한 인자 줄들을 모은다(같은 이름은 처음 것) — 글을 읽기만 한다
flow_decl() {
  local steps="$1" dict="$2" line acc=""
  [[ "$dict" == *인자* ]] || return 0
  while IFS= read -r line; do
    [[ "$line" == tooth$'\t'* ]] || continue
    line="${line#*$'\t'}"
    acc="$(scv_gear_args_merge "$(scv_gear_args_parse "$dict" "${line%%$'\t'*}")" "$acc")"
  done <<< "$steps"
  printf '%s' "$acc"
}

# @effect gear_lines
# 이유: 기어 글 파일들을 읽어 기어의 사전 줄들을 낸다 — 받는 값 · 돌려주는 값은 펼친 흐름의 첫 톱니 · 끝 톱니에서
gear_lines() {
  local tidx="$1" light="${2:-}" f d name text walk flat first last gin gout dict i line acc fm T=$'\t'
  dict="$(teeth_text)"
  for f in "$GDIR"/*/GEAR.md; do
    [[ -f "$f" ]] || continue
    d="${f%/GEAR.md}"; name="${d##*/}"
    [[ "$name" != teeth ]] || continue
    text="$(cat "$f")"
    walk="$(flat_walk "$name" "$tidx" 1 "" "")"; flat="$(printf '%s\n' "$walk" | cut -f1,2)"
    first="$(printf '%s\n' "$flat" | sed -n $'s/^tooth\t//p' | head -n 1)"
    last="$(printf '%s\n' "$flat" | sed -n $'s/^tooth\t//p' | tail -n 1)"
    # 기어 글에 적은 값 이름이 먼저다 — 없으면 첫 · 끝 톱니에서
    gin="$(scv_gear_sig_name "$(scv_gear_front_get "$text" in)")"; gout="$(scv_gear_sig_name "$(scv_gear_front_get "$text" out)")"
    [[ -n "$gin" ]] || gin="$(scv_gear_index_get "$tidx" "$first" in)"
    [[ -n "$gout" ]] || gout="$(scv_gear_index_get "$tidx" "$last" out)"
    # 인자: 흐름의 톱니들이 선언한 것에 기어들의 arg 줄을 얹은 값(보는 용도)
    acc=""; i=0
    while IFS= read -r line; do
      [[ -z "$light" && "$dict" == *인자* ]] || break
      i=$((i + 1)); [[ "$line" == tooth$'\t'* ]] || continue
      line="${line#*$'\t'}"
      acc="$(scv_gear_args_merge "$acc" "$(scv_gear_args_apply "$(scv_gear_args_parse "$dict" "${line%%$'\t'*}")" "$(step_ov "$walk" "$i")")")"
    done <<< "$walk"
    acc="${acc//$'\n'/; }"; acc="$(scv_gear_one_line "$acc")"
    # 0.102.0+ — 셋째 칸: 펼친 흐름에서 가장 센 표시(pure | effect | outward | judge, 깨진 흐름은 -). 가벼운 사전(run)은 재지 않는다
    fm="-"; [[ -n "$light" ]] || fm="$(scv_gear_flow_mark "$flat" "$tidx")"
    printf '%s\tgear\t%s\t%s\t%s\t%s\t%s%s\n' "$name" "$fm" "${gin:-*}" "${gout:-*}" \
      "$(scv_gear_one_line "$(scv_gear_front_get "$text" does)")" "$(scv_gear_one_line "$(scv_gear_front_get "$text" words)")" "${acc:+$T$acc}"
  done
  return 0
}

# @effect built_index
# 이유: 톱니 사전과 기어 글 파일들을 읽어 지금의 사전 글을 만든다(파일은 쓰지 않는다)
built_index() {
  local tidx; tidx="$(scv_gear_teeth_parse "$(teeth_text)")"
  scv_gear_index_build "$(printf '%s\n%s' "$tidx" "$(gear_lines "$tidx" "${1:-}")")"
}

# @effect write_index
# 이유: 사전 글을 사전 파일에 쓴다 — 기어도 톱니도 없으면 빈 파일
write_index() {
  local idx; idx="$(built_index)"
  mkdir -p "$GDIR" || return 1
  if [[ -n "$idx" ]]; then printf '%s\n' "$idx" > "$GDIR/INDEX.tsv"; else : > "$GDIR/INDEX.tsv"; fi
}

# @effect new_token
# 이유: 난수 장치를 읽어 이어가기 표(16진 8자)를 만든다
new_token() {
  local t; t="$(od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d ' \n')"
  [[ ${#t} -eq 8 ]] || t="$(printf '%08x' "$(( ($$ * 65537 + RANDOM) & 0xffffffff ))")"
  printf '%s' "$t"
}

# @effect tooth_block
# 이유: 톱니 파일을 읽어, 이 톱니를 돌리면 안 되는 까닭을 한 줄로 낸다(돌려도 되면 빈 값) — 이름 · 사전의 중복 · 표시 · 파일 · 위험 명령 · 순수 톱니에 둘 수 없는 명령
tooth_block() {
  local tidx="$1" s="$2" m c r body a
  [[ "$(scv_gear_name_ok "$s")" == yes ]] || { printf '쓸 수 없는 톱니 이름'; return 0; }
  c="$(printf '%s\n' "$tidx" | LC_ALL=C awk -F'\t' -v n="$s" '$1 == n' | grep -c .)"
  [[ "$c" == 1 ]] || { printf '톱니 사전에 %s번 적혀 있다(한 번만 적는다)' "$c"; return 0; }
  m="$(scv_gear_index_get "$tidx" "$s" mark)"
  case "$m" in pure|effect|outward) ;; *) printf '표시가 pure · effect · outward 중 하나가 아니다(지금: %s)' "$m"; return 0 ;; esac
  [[ -f "$TDIR/$s.sh" ]] || { printf '톱니 파일이 없다'; return 0; }
  while IFS= read -r a; do
    [[ -n "$a" ]] || continue
    [[ "$(scv_gear_arg_name_ok "${a%%=*}")" == yes ]] || { printf "쓸 수 없는 인자 이름 '%s'(영문 소문자로 시작 · 소문자 · 숫자 · 밑줄, _proxy 로 끝나면 안 됨)" "${a%%=*}"; return 0; }
  done <<< "$(scv_gear_args_parse "$(teeth_text)" "$s")"
  body="$(cat "$TDIR/$s.sh")"
  if [[ "$m" != outward ]]; then
    r="$(scv_gear_risk_scan "$body")"
    [[ -z "$r" ]] || { printf '밖으로 나가거나 지우는 명령(%s번째 줄 %s)이 있는데 표시가 outward 가 아니다' "${r%%$'\t'*}" "$(printf '%s' "${r#*$'\t'}" | head -n 1)"; return 0; }
  fi
  if [[ "$m" == pure ]]; then
    r="$(scv_gear_pure_scan "$body")"
    [[ -z "$r" ]] || { printf '순수 톱니에 둘 수 없는 명령(%s번째 줄 %s)이 있다 — 파일을 바꾸거나 다른 코드를 돌리거나 매번 달라진다. 표시를 effect 로 바꾸거나 톱니를 나눠라' "${r%%$'\t'*}" "$(printf '%s' "${r#*$'\t'}" | head -n 1)"; return 0; }
  fi
  return 0
}

# @effect tooth_run
# 이유: 톱니를 돌린다 — 그 톱니에 들어갈 인자 줄들(파일)만 환경 변수로 넘기고, 흐름의 다른 톱니가 선언한 이름(파일)은 환경에서 지운다
tooth_run() {
  local f="$1" infile="$2" outfile="$3" errfile="$4" argsfile="${5:-}" namesfile="${6:-}" line
  local -a e=()
  if [[ -n "$namesfile" && -f "$namesfile" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do [[ -z "$line" ]] || e+=(-u "$line"); done < "$namesfile"
  fi
  if [[ -n "$argsfile" && -f "$argsfile" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do [[ -z "$line" ]] || e+=("$line"); done < "$argsfile"
  fi
  env ${e[@]+"${e[@]}"} bash "$f" < "$infile" > "$outfile" 2> "$errfile"
}

# @effect kill_tree
# 이유: 프로세스와 그 자식들을 죽인다(자식부터) — 끊긴 톱니가 띄운 명령이 남아 계속 돌지 않게. 자식을 찾는 도구(pgrep)가 없으면 자신만 죽인다
kill_tree() {
  local p="$1" c
  if command -v pgrep >/dev/null 2>&1; then
    for c in $(pgrep -P "$p" 2>/dev/null); do kill_tree "$c"; done
  fi
  kill -9 "$p" 2>/dev/null
  return 0
}

# @effect run_example
# 이유: 톱니를 예시 입력으로 실제로 돌려 출력 파일에 받는다(인자 줄 파일이 있으면 그 값으로) — 정한 시간(초)을 넘기면 죽이고 124 를 낸다. 시간을 넘겼는지는 지킴이가 죽이기 전에 남긴 표시 파일로 안다(지킴이가 아직 살아 있는지로 가리면 죽인 직후에 틀린다)
run_example() {
  local f="$1" infile="$2" outfile="$3" argsfile="${4:-}" pid w rc mark="$3.timeout"
  rm -f "$mark"
  tooth_run "$f" "$infile" "$outfile" /dev/null "$argsfile" "" & pid=$!
  ( sleep "$EXSECS"; : > "$mark"; kill_tree "$pid" ) >/dev/null 2>&1 & w=$!
  wait "$pid" 2>/dev/null; rc=$?
  kill "$w" 2>/dev/null; wait "$w" 2>/dev/null
  if [[ -e "$mark" ]]; then rc=124; rm -f "$mark"; fi
  return "$rc"
}

# @effect lint_teeth
# 이유: 톱니 파일들을 읽고 · 문법을 검사하고 · 순수 톱니를 예시 입력으로 실제로 돌려 문제 줄들을 낸다(알림은 GEAR_WARN)
lint_teeth() {
  local tidx="$1" dict line name mark f body r ex k parts in_lit out_lit want got rc why tmp seen=" " out="" decl ea exargs u
  dict="$(teeth_text)"
  tmp="$(mktemp -d 2>/dev/null)" || tmp=""
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    name="${line%%$'\t'*}"; mark="$(scv_gear_index_get "$line" "$name" mark)"
    case "$seen" in *" $name "*) continue ;; esac
    seen+="$name "
    f="$TDIR/$name.sh"
    why="$(tooth_block "$tidx" "$name")"
    if [[ -n "$why" ]]; then
      # 위험 명령은 줄마다 따로 알린다 — 그 밖은 까닭 한 줄. 어느 쪽이든 이 톱니는 예시로도 돌리지 않는다.
      r=""; [[ -f "$f" && "$mark" != outward ]] && r="$(scv_gear_risk_scan "$(cat "$f")")"
      if [[ "$why" == "밖으로 나가거나"* && -n "$r" ]]; then
        while IFS= read -r ex; do
          [[ -n "$ex" ]] && out+="GEAR_RISK: $name:${ex%%$'\t'*} ${ex#*$'\t'} — 밖으로 나가거나 지우는 명령인데 표시가 outward 가 아니다"$'\n'
        done <<< "$r"
      else
        out+="GEAR_BAD: $name — $why"$'\n'
      fi
      continue
    fi
    bash -n "$f" 2>/dev/null || { out+="GEAR_BAD: $name — 톱니 문법 오류"$'\n'; continue; }
    body="$(cat "$f")"
    r="$(scv_gear_body_lines "$body")"
    (( r <= MAXLINES )) || out+="GEAR_WARN: $name — 본문 ${r}줄(한도 ${MAXLINES}줄) — 한 톱니는 한 가지 일만, 나눌 수 있는지 보라"$'\n'
    [[ "$mark" == pure ]] || continue
    ex="$(scv_gear_tooth_examples "$dict" "$name")"
    if [[ -z "$ex" ]]; then out+="GEAR_BAD: $name — 예시가 없다(순수 톱니는 '- 예: <입력> → <출력>' 이 하나 이상)"$'\n'; continue; fi
    [[ -n "$tmp" ]] || { out+="GEAR_BAD: $name — 예시를 돌릴 임시 자리를 만들지 못했다"$'\n'; continue; }
    decl="$(scv_gear_args_parse "$dict" "$name")"
    k=0
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      k=$((k + 1))
      ea="$(scv_gear_example_args "$line")"; exargs="${ea%%$'\n'*}"; exargs="${exargs// /$'\n'}"
      parts="$(scv_gear_example_split "${ea#*$'\n'}")"
      if [[ -z "$parts" ]]; then out+="GEAR_EXAMPLE: $name — 예시 $k 의 모양이 '<입력> → <출력>' 이 아니다"$'\n'; continue; fi
      u="$(scv_gear_args_unknown "$exargs" "$decl")"
      if [[ -n "$u" ]]; then out+="GEAR_EXAMPLE: $name — 예시 $k: 이 톱니가 선언하지 않은 인자 $(scv_gear_one_line "$u")"$'\n'; continue; fi
      in_lit="${parts%%$'\n'*}"; out_lit="${parts#*$'\n'}"
      want="$(scv_gear_lit_decode "$out_lit")"
      scv_gear_lit_decode "$in_lit" > "$tmp/in"
      scv_gear_args_apply "$decl" "$exargs" > "$tmp/args"
      run_example "$f" "$tmp/in" "$tmp/out" "$tmp/args"; rc=$?
      got="$(cat "$tmp/out" 2>/dev/null)"
      if (( rc == 124 )); then out+="GEAR_EXAMPLE: $name — 예시 $k: ${EXSECS}초 안에 끝나지 않았다"$'\n'
      elif (( rc != 0 )); then out+="GEAR_EXAMPLE: $name — 예시 $k: 종료 코드 $rc"$'\n'
      elif [[ "$got" != "$want" ]]; then out+="GEAR_EXAMPLE: $name — 예시 $k: 기대 [$(scv_gear_one_line "${want:0:60}")] 실제 [$(scv_gear_one_line "${got:0:60}")]"$'\n'
      fi
    done <<< "$ex"
  done <<< "$tidx"
  [[ -z "$tmp" ]] || rm -rf "$tmp"
  for f in "$TDIR"/*.sh; do
    [[ -f "$f" ]] || continue
    name="${f##*/}"; name="${name%.sh}"
    [[ -n "$(scv_gear_index_get "$tidx" "$name" kind)" ]] || out+="GEAR_BAD: $name — 톱니 파일은 있는데 톱니 사전(teeth/TEETH.md)에 없다"$'\n'
  done
  printf '%s' "$out"
}

# @effect lint_gears
# 이유: 기어 폴더들 · 사전 파일을 읽어 문제 줄들을 낸다(알림은 GEAR_WARN)
lint_gears() {
  local tidx="$1" idx="$2" d name text walk flat e line t r out="" dict decl gin gout first last a exs k ea exargs parts u tmp i s rc nshow want got
  dict="$(teeth_text)"
  tmp="$(mktemp -d 2>/dev/null)" || tmp=""
  for d in "$GDIR"/*/; do
    [[ -d "$d" ]] || continue
    name="${d%/}"; name="${name##*/}"
    [[ "$name" != teeth ]] || continue
    if [[ ! -f "$d/GEAR.md" ]]; then out+="GEAR_BAD: $name — 기어 글(GEAR.md)이 없다"$'\n'; continue; fi
    [[ "$(scv_gear_name_ok "$name")" == yes ]] || out+="GEAR_BAD: $name — 이름은 영문 소문자 · 숫자 · 붙임표만"$'\n'
    [[ -z "$(scv_gear_index_get "$tidx" "$name" kind)" ]] || out+="GEAR_BAD: $name — 같은 이름의 톱니가 있다(기어와 톱니는 이름이 달라야 한다)"$'\n'
    text="$(cat "$d/GEAR.md")"
    if [[ -z "$(scv_gear_front_get "$text" flow)" ]]; then out+="GEAR_BAD: $name — 맨 위에 flow 줄이 없다"$'\n'; continue; fi
    walk="$(flat_walk "$name" "$tidx" 1 "" "")"; flat="$(printf '%s\n' "$walk" | cut -f1,2)"
    e="$(scv_gear_flow_check "$flat" "$tidx")"
    r="$e"
    while IFS= read -r line; do [[ -n "$line" ]] && out+="GEAR_FLOW: $name: $line"$'\n'; done <<< "$e"
    # 받는 값 · 돌려주는 값: 기어 글에 적은 이름을 첫 · 끝 톱니와 맞춰 본다(흐름의 처음 · 끝이 톱니일 때만)
    gin="$(scv_gear_sig_name "$(scv_gear_front_get "$text" in)")"; gout="$(scv_gear_sig_name "$(scv_gear_front_get "$text" out)")"
    first="$(printf '%s\n' "$flat" | head -n 1)"; last="$(printf '%s\n' "$flat" | tail -n 1)"
    [[ "$first" == tooth$'\t'* ]] && first="$(scv_gear_index_get "$tidx" "${first#*$'\t'}" in)" || first=""
    [[ "$last" == tooth$'\t'* ]] && last="$(scv_gear_index_get "$tidx" "${last#*$'\t'}" out)" || last=""
    e="$(scv_gear_sig_check "$gin" "$gout" "$first" "$last")"
    while IFS= read -r line; do [[ -n "$line" ]] && out+="GEAR_SIG: $name: $line"$'\n'; done <<< "$e"
    [[ -n "$gin$gout" ]] || out+="GEAR_WARN: $name — in · out 줄이 없다(맨 위에 받는 값 · 돌려주는 값의 이름을 적으면 목록에 보인다)"$'\n'
    # 기어의 arg 줄: 모양과, 흐름의 톱니가 선언한 이름인지
    decl="$(flow_decl "$flat" "$dict")"
    while IFS= read -r a; do
      [[ -n "$a" ]] || continue
      if [[ "$a" != *=* || "$(scv_gear_arg_name_ok "${a%%=*}")" != yes ]]; then out+="GEAR_BAD: $name — arg 줄의 모양이 '이름=값' 이 아니다: $(scv_gear_one_line "$a")"$'\n'
      elif [[ -n "$(scv_gear_args_unknown "$a" "$decl")" ]]; then out+="GEAR_BAD: $name — arg 줄의 인자 ${a%%=*} 을 선언한 톱니가 흐름에 없다"$'\n'; fi
    done <<< "$(scv_gear_front_all "$text" arg)"
    # 예시: 순수 톱니로만 된 흐름은 실제로 돌려 맞춰 보고, 그 밖은 보기용으로 센다(돌리지 않는다)
    exs="$(scv_gear_front_all "$text" 예)"; t="$(scv_gear_front_all "$text" example)"
    [[ -z "$t" ]] || exs+="${exs:+$'\n'}$t"
    if [[ -n "$exs" && -z "$r" ]]; then
      if [[ "$(scv_gear_example_mode "$flat" "$tidx")" == run ]]; then
        # 돌리면 안 되는 톱니가 하나라도 있으면 예시도 돌리지 않는다(그 톱니는 톱니 검사가 알린다)
        t=""
        while IFS= read -r line; do [[ -z "$(tooth_block "$tidx" "${line#*$'\t'}")" ]] || t=blocked; done <<< "$flat"
        k=0
        while IFS= read -r line; do
          [[ -n "$line" && -z "$t" ]] || continue
          k=$((k + 1))
          [[ -n "$tmp" ]] || { out+="GEAR_EXAMPLE: $name — 예시를 돌릴 임시 자리를 만들지 못했다"$'\n'; break; }
          ea="$(scv_gear_example_args "$line")"; exargs="${ea%%$'\n'*}"; exargs="${exargs// /$'\n'}"
          parts="$(scv_gear_example_split "${ea#*$'\n'}")"
          if [[ -z "$parts" ]]; then out+="GEAR_EXAMPLE: $name — 예시 $k 의 모양이 '<입력> → <출력>' 이 아니다"$'\n'; continue; fi
          u="$(scv_gear_args_unknown "$exargs" "$decl")"
          if [[ -n "$u" ]]; then out+="GEAR_EXAMPLE: $name — 예시 $k: 흐름의 톱니가 선언하지 않은 인자 $(scv_gear_one_line "$u")"$'\n'; continue; fi
          want="$(scv_gear_lit_decode "${parts#*$'\n'}")"
          scv_gear_lit_decode "${parts%%$'\n'*}" > "$tmp/data"
          i=0; rc=0
          while IFS= read -r s; do
            i=$((i + 1)); s="${s#*$'\t'}"
            scv_gear_args_apply "$(scv_gear_args_parse "$dict" "$s")" "$(scv_gear_args_merge "$(step_ov "$walk" "$i")" "$exargs")" > "$tmp/args"
            run_example "$TDIR/$s.sh" "$tmp/data" "$tmp/next" "$tmp/args"; rc=$?
            (( rc == 0 )) || break
            mv "$tmp/next" "$tmp/data"
          done <<< "$flat"
          got="$(cat "$tmp/data" 2>/dev/null)"
          if (( rc == 124 )); then out+="GEAR_EXAMPLE: $name — 예시 $k: ${i}단계 $s 가 ${EXSECS}초 안에 끝나지 않았다"$'\n'
          elif (( rc != 0 )); then out+="GEAR_EXAMPLE: $name — 예시 $k: ${i}단계 $s 종료 코드 $rc"$'\n'
          elif [[ "$got" != "$want" ]]; then out+="GEAR_EXAMPLE: $name — 예시 $k: 기대 [$(scv_gear_one_line "${want:0:60}")] 실제 [$(scv_gear_one_line "${got:0:60}")]"$'\n'
          fi
        done <<< "$exs"
      else
        nshow="$(printf '%s\n' "$exs" | grep -c .)"
        out+="GEAR_SHOW: $name — 보기용 예시 ${nshow}개(판단 단계나 순수하지 않은 톱니가 있어 돌리지 않는다)"$'\n'
      fi
    fi
    e="$(scv_gear_flow_warn "$flat" "$tidx")"
    while IFS= read -r line; do [[ -n "$line" ]] && out+="GEAR_WARN: $name: $line"$'\n'; done <<< "$e"
    if [[ $'\n'"$flat"$'\n' == *$'\n'"text"$'\t'"$name"$'\n'* && -z "$(scv_gear_body "$text")" ]]; then
      out+="GEAR_BAD: $name — flow 에 @ 가 있는데 글이 비었다"$'\n'
    fi
  done
  [[ -z "$tmp" ]] || rm -rf "$tmp"
  t=""; [[ -f "$GDIR/INDEX.tsv" ]] && t="$(cat "$GDIR/INDEX.tsv")"
  if [[ "$t" != "$idx" ]]; then
    r="$( { printf '%s\n' "$t"; printf '%s\n' "$idx"; } | LC_ALL=C sort | LC_ALL=C uniq -u | LC_ALL=C awk -F'\t' 'NF > 0 && !s[$1]++ { printf "%s%s", (n++ ? " " : ""), $1 }')"
    out+="GEAR_INDEX_STALE: 사전(INDEX.tsv)이 톱니 사전 · 기어 글과 다르다 — 어긋난 이름: ${r:-?} · gear.sh index 로 다시 만들어라(INDEX.tsv 는 손으로 고치지 않는다)"$'\n'
  fi
  printf '%s' "$out"
}

# @effect gear_log
# 이유: 실행이 끝났을 때 저널에 한 줄을 남긴다 — 기어 이름 · 준 인자 · 종료 코드. 대화 없이 돌린 실행도 나중에 찾을 수 있게. 저널 폴더가 이미 있는 프로젝트에서만 적는다(없는 폴더를 만들지 않는다). 기록 실패는 실행을 막지 않는다
gear_log() {
  local run="$1" rc="$2" name args ja="$SCRIPT_DIR/journal-append.sh"
  [[ -f "$ja" && -f "$run/name" && -d "$JDIR" ]] || return 0
  name="$(head -n 1 "$run/name" 2>/dev/null)"; args=""
  [[ -f "$run/given" ]] && args="$(tr '\n' ' ' < "$run/given" 2>/dev/null)"
  printf '기어 %s %s→ 종료 코드 %s\n' "$name" "$args" "$rc" | bash "$ja" --speaker gear >/dev/null 2>&1 || true
}

# @effect drive
# 이유: 실행 폴더의 상태를 읽어 단계를 차례로 돌린다 — 톱니를 실행하고, 넘김 · 확인에서 상태를 쓰고 멈추고, 끝나면 결과를 내고 상태를 지운다
drive() {
  local run="$1" i="$2" idx tidx steps n line k s mark does conf mode rc label
  idx="$(cat "$run/index")"; tidx="$(cat "$run/teeth")"; steps="$(cat "$run/steps")"
  n="$(printf '%s\n' "$steps" | grep -c .)"
  while (( i <= n )); do
    line="$(printf '%s\n' "$steps" | sed -n "${i}p")"
    k="${line%%$'\t'*}"; s="${line#*$'\t'}"
    if [[ "$k" == tooth ]]; then mark="$(scv_gear_index_get "$tidx" "$s" mark)"; does="$(scv_gear_index_get "$tidx" "$s" does)"
    else mark="-"; does="$(printf '%s\n' "$idx" | LC_ALL=C awk -F'\t' -v n="$s" '$1 == n && $2 == "gear" { print $6; exit }')"; fi
    conf=""; [[ -f "$run/confirmed.$i" ]] && conf=yes
    mode="$(scv_gear_step_mode "$k" "$mark" "$conf")"
    case "$mode" in
      direct)
        tooth_run "$TDIR/$s.sh" "$run/data" "$run/next" "$run/err" "$run/args.$i" "$run/argnames"; rc=$?
        if (( rc != 0 )); then
          printf 'GEAR_ERROR: %s단계 %s — 종료 코드 %s\n' "$i" "$s" "$rc" >&2
          tail -n 5 "$run/err" >&2
          gear_log "$run" 1
          rm -rf "$run"; exit 1
        fi
        mv "$run/next" "$run/data"; i=$((i + 1)) ;;
      handoff)
        printf '%s' "$i" > "$run/wait"; printf 'handoff' > "$run/kind"
        label="$i/$n @$s — $does"
        scv_gear_handoff_text "${run##*/}" "$label" "$(scv_gear_body "$(cat "$GDIR/$s/GEAR.md")")" "$(cat "$run/data")" "$SELF resume ${run##*/}"; printf '\n'
        exit 10 ;;
      confirm)
        printf '%s' "$i" > "$run/wait"; printf 'confirm' > "$run/kind"
        label="$i/$n $s — $does"
        scv_gear_confirm_text "${run##*/}" "$label" "$(cat "$TDIR/$s.sh")" "$SELF resume ${run##*/}" "$i" "$(cat "$run/args.$i" 2>/dev/null)"; printf '\n'
        exit 11 ;;
      *) printf 'GEAR_ERROR: %s단계 %s — 돌릴 수 없다(종류 %s · 표시 %s)\n' "$i" "$s" "$k" "$mark" >&2; rm -rf "$run"; exit 1 ;;
    esac
  done
  cat "$run/data"
  gear_log "$run" 0
  rm -rf "$run"
  exit 0
}

[[ $# -ge 1 ]] || usage
CMD="$1"; shift

case "$CMD" in
  list)
    idx=""; [[ -d "$GDIR" ]] && idx="$(built_index)"
    [[ -n "$idx" ]] || { echo "기어 없음"; exit 0; }
    ng="$(printf '%s\n' "$idx" | LC_ALL=C awk -F'\t' '$2 == "gear"' | grep -c .)"
    nt="$(printf '%s\n' "$idx" | LC_ALL=C awk -F'\t' '$2 == "tooth"' | grep -c .)"
    printf '기어 %s개\n' "$ng"
    if (( ng > 0 )); then
      printf '이름\t값\t인자\t하는 일\t흐름\n'
      while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        name="${line%%$'\t'*}"
        printf '%s\t%s\n' "$line" "$(scv_gear_front_get "$(cat "$GDIR/$name/GEAR.md" 2>/dev/null)" flow)"
      done <<< "$(scv_gear_list_rows "$idx" gear)"
    fi
    printf '톱니 %s개\n' "$nt"
    if (( nt > 0 )); then
      printf '이름\t표시\t값\t인자\t하는 일\n'
      printf '%s\n' "$(scv_gear_list_rows "$idx" tooth)"
    fi
    exit 0
    ;;

  ask)
    # 0.102.0+ — 이 기어 · 톱니를 쓸 때 정해야 할 값: 인자(이름 · 지금 값 · 기어가 정해 둠 여부 · 설명)와 받는 값. 읽기만 한다.
    name="${1:-}"
    [[ "$(scv_gear_name_ok "$name")" == yes ]] || die 2 "쓸 수 없는 이름: $name"
    dict="$(teeth_text)"; tidx="$(scv_gear_teeth_parse "$dict")"; idx=""; [[ -d "$GDIR" ]] && idx="$(built_index)"
    kind="$(scv_gear_index_get "$idx" "$name" kind)"
    [[ -n "$kind" ]] || die 2 "사전에 없는 기어 · 톱니: $name"
    if [[ "$kind" == gear ]]; then walk="$(flat_walk "$name" "$tidx" 1 "" "")"; else walk="tooth"$'\t'"$name"; fi
    acc=""; fixed=""; descs=""; i=0
    while IFS= read -r line; do
      i=$((i + 1)); [[ "$line" == tooth$'\t'* ]] || continue
      t="${line#*$'\t'}"; t="${t%%$'\t'*}"; ov="$(step_ov "$walk" "$i")"
      acc="$(scv_gear_args_merge "$acc" "$(scv_gear_args_apply "$(scv_gear_args_parse "$dict" "$t")" "$ov")")"
      fixed="$(scv_gear_args_merge "$fixed" "$ov")"
      descs+="$(scv_gear_args_desc "$dict" "$t")"$'\n'
    done <<< "$walk"
    printf 'GEAR_ASK: %s\n' "$name"
    rows="$(scv_gear_ask_rows "$acc" "$fixed" "$descs" "$(scv_gear_index_get "$idx" "$name" in)")"
    if [[ -n "$rows" ]]; then printf '%s\n' "$rows"; else echo "none"; fi
    exit 0
    ;;

  index)
    write_index || die 1 "사전을 쓰지 못함: $GDIR/INDEX.tsv"
    n=0; [[ -s "$GDIR/INDEX.tsv" ]] && n="$(grep -c . "$GDIR/INDEX.tsv")"
    echo "GEAR_INDEX: ${n}개 → $GDIR/INDEX.tsv"
    exit 0
    ;;

  new)
    NAME="${1:-}"; [[ $# -ge 1 ]] && shift
    KIND=""; DOES=""; GIN=""; GOUT=""; MARK=""; WORDS=""; FLOW=""; EX=""; ARGS=""
    while [[ $# -gt 0 ]]; do
      [[ $# -ge 2 ]] || usage
      case "$1" in
        --kind) KIND="${2:-}"; shift 2 ;;
        --does) DOES="${2:-}"; shift 2 ;;
        --in) GIN="${2:-}"; shift 2 ;;
        --out) GOUT="${2:-}"; shift 2 ;;
        --mark) MARK="${2:-}"; shift 2 ;;
        --words) WORDS="${2:-}"; shift 2 ;;
        --flow) FLOW="${2:-}"; shift 2 ;;
        --example) EX="${2:-}"; shift 2 ;;
        --arg) ARGS+="${ARGS:+$'\n'}$(scv_gear_one_line "${2:-}")"; shift 2 ;;
        *) usage ;;
      esac
    done
    # 인자 이름은 파일을 만들기 전에 가린다
    while IFS= read -r a; do
      [[ -n "$a" ]] || continue
      a="${a%% — *}"; a="${a%%=*}"; a="${a%"${a##*[![:space:]]}"}"
      [[ "$(scv_gear_arg_name_ok "$a")" == yes ]] || die 2 "쓸 수 없는 인자 이름: '$a' (영문 소문자로 시작 · 소문자 · 숫자 · 밑줄, _proxy 로 끝나면 안 됨)"
    done <<< "$ARGS"
    [[ "$(scv_gear_name_ok "$NAME")" == yes ]] || die 2 "이름은 영문 소문자 · 숫자 · 붙임표만(64자까지, teeth 는 못 씀): '$NAME'"
    tidx="$(scv_gear_teeth_parse "$(teeth_text)")"
    [[ -z "$(scv_gear_index_get "$tidx" "$NAME" kind)" && ! -e "$TDIR/$NAME.sh" ]] || die 1 "이미 있는 톱니: $NAME"
    [[ ! -e "$GDIR/$NAME" ]] || die 1 "이미 있는 기어: $NAME"
    case "$KIND" in
      tooth)
        MARK="${MARK:-pure}"
        case "$MARK" in pure|effect|outward) ;; *) die 2 "--mark 는 pure · effect · outward 중 하나" ;; esac
        # 순수 톱니는 예시가 있어야 한다 — 안 주면 뼈대 본문(cat)에 맞는 예시를 넣어 둔다(본문을 고칠 때 함께 고친다)
        [[ -n "$EX" || "$MARK" != pure ]] || EX='"a" → "a"'
        mkdir -p "$TDIR" || die 1 "폴더를 만들지 못함: $TDIR"
        printf '#!/usr/bin/env bash\nset -euo pipefail\ncat\n' > "$TDIR/$NAME.sh"
        [[ -f "$TDICT" ]] || printf '# 톱니 사전\n\n톱니마다 역할 · 표시(pure | effect | outward) · 값(받는 값 → 돌려주는 값) · 예시를 적는다.\n순수 톱니의 예시는 gear.sh check 가 실제로 돌려 맞춰 본다.\n' > "$TDICT"
        printf '\n%s\n' "$(scv_gear_tooth_entry "$NAME" "$(scv_gear_one_line "$DOES")" "$MARK" "$(scv_gear_one_line "${GIN:-*}")" "$(scv_gear_one_line "${GOUT:-*}")" "$(scv_gear_one_line "$EX")" "$ARGS")" >> "$TDICT"
        where="$TDIR/$NAME.sh" ;;
      gear)
        [[ -n "$FLOW" ]] || die 2 "--flow 가 필요하다(예: \"a | b | @ | c\")"
        # 받는 값 · 돌려주는 값을 안 주면 흐름의 첫 · 끝 낱말(톱니나 기어)에서 채운다 — @ 로 시작하거나 끝나면 비워 둔다
        idx="$(built_index)"; toks="$(scv_gear_flow_parse "$FLOW")"
        [[ -n "$GIN" ]] || GIN="$(scv_gear_index_get "$idx" "$(printf '%s\n' "$toks" | head -n 1)" in)"
        [[ -n "$GOUT" ]] || GOUT="$(scv_gear_index_get "$idx" "$(printf '%s\n' "$toks" | tail -n 1)" out)"
        [[ "$GIN" != "*" ]] || GIN=""
        [[ "$GOUT" != "*" ]] || GOUT=""
        # 기어의 인자는 흐름의 톱니가 선언한 것이어야 한다
        if [[ -n "$ARGS" ]]; then
          decl=""
          while IFS= read -r tok; do
            if [[ -n "$(scv_gear_index_get "$tidx" "$tok" kind)" ]]; then decl="$(scv_gear_args_merge "$decl" "$(scv_gear_args_parse "$(teeth_text)" "$tok")")"
            elif [[ "$tok" != "@" && -f "$GDIR/$tok/GEAR.md" ]]; then decl="$(scv_gear_args_merge "$decl" "$(flow_decl "$(flat_flow "$tok" "$tidx" 1 "")" "$(teeth_text)")")"; fi
          done <<< "$toks"
          while IFS= read -r a; do
            [[ "$a" == *=* ]] || die 2 "기어의 --arg 는 '이름=값' 모양: '$a'"
            [[ -z "$(scv_gear_args_unknown "$a" "$decl")" ]] || die 2 "인자 ${a%%=*} 을 선언한 톱니가 흐름에 없다"
          done <<< "$ARGS"
        fi
        mkdir -p "$GDIR/$NAME" || die 1 "폴더를 만들지 못함: $GDIR/$NAME"
        {
          printf 'flow: %s\n' "$(scv_gear_one_line "$FLOW")"
          [[ -z "$GIN" ]] || printf 'in: %s\n' "$(scv_gear_one_line "$GIN")"
          [[ -z "$GOUT" ]] || printf 'out: %s\n' "$(scv_gear_one_line "$GOUT")"
          if [[ -n "$ARGS" ]]; then while IFS= read -r a; do printf 'arg: %s\n' "$a"; done <<< "$ARGS"; fi
          [[ -z "$EX" ]] || printf '예: %s\n' "$(scv_gear_one_line "$EX")"
          printf 'does: %s\n' "$(scv_gear_one_line "$DOES")"
          printf 'words: %s\n' "$(scv_gear_one_line "$WORDS")"
          printf '\n# %s\n' "$NAME"
          [[ "$FLOW" != *"@"* ]] || printf '\n<@ 자리에서 모델이 할 일을 짧게 적는다 — 받는 값은 앞 톱니의 결과, 돌려주는 값은 다음 톱니의 입력이다.>\n'
        } > "$GDIR/$NAME/GEAR.md"
        where="$GDIR/$NAME/GEAR.md" ;;
      *) die 2 "--kind 는 tooth · gear 중 하나" ;;
    esac
    write_index || die 1 "사전을 쓰지 못함"
    echo "GEAR_NEW: $NAME ($KIND) → $where"
    exit 0
    ;;

  check)
    [[ -d "$GDIR" ]] || { echo "기어 없음"; exit 0; }
    tidx="$(scv_gear_teeth_parse "$(teeth_text)")"
    idx="$(built_index)"
    out="$(lint_teeth "$tidx")"; o2="$(lint_gears "$tidx" "$idx")"
    [[ -z "$o2" ]] || out+="${out:+$'\n'}$o2"
    nf=0; nw=0; ns=0
    if [[ -n "$out" ]]; then
      printf '%s\n' "$out"
      nf="$(printf '%s\n' "$out" | grep -v -e '^GEAR_WARN: ' -e '^GEAR_SHOW: ' | grep -c .)"
      nw="$(printf '%s\n' "$out" | grep -c '^GEAR_WARN: ')"
      ns="$(printf '%s\n' "$out" | sed -n 's/^GEAR_SHOW: .* 보기용 예시 \([0-9]*\)개.*/\1/p' | LC_ALL=C awk '{ s += $1 } END { print s + 0 }')"
    fi
    if (( nf > 0 )); then echo "GEAR_CHECK: 실패 — ${nf}건 · 알림 ${nw}건"; exit 1; fi
    ng="$(printf '%s\n' "$idx" | LC_ALL=C awk -F'\t' '$2 == "gear"' | grep -c .)"
    nt="$(printf '%s\n' "$idx" | LC_ALL=C awk -F'\t' '$2 == "tooth"' | grep -c .)"
    if (( ns > 0 )); then echo "GEAR_CHECK: 통과 — 기어 ${ng}개 · 톱니 ${nt}개 · 알림 ${nw}건 · 보기용 예시 ${ns}개"
    else echo "GEAR_CHECK: 통과 — 기어 ${ng}개 · 톱니 ${nt}개 · 알림 ${nw}건"; fi
    exit 0
    ;;

  run)
    NAME="${1:-}"; [[ $# -ge 1 ]] && shift
    [[ "$(scv_gear_name_ok "$NAME")" == yes ]] || die 2 "기어나 톱니 이름이 필요하다"
    words=""
    for w in "$@"; do
      [[ "$w" != *$'\n'* ]] || die 2 "인자 값에는 줄바꿈을 쓸 수 없다"
      words+="${words:+$'\n'}$w"
    done
    dict="$(teeth_text)"
    tidx="$(scv_gear_teeth_parse "$dict")"
    idx="$(built_index light)"
    if [[ -n "$(scv_gear_index_get "$tidx" "$NAME" kind)" ]]; then walk="tooth"$'\t'"$NAME"$'\t'
    elif [[ -f "$GDIR/$NAME/GEAR.md" ]]; then walk="$(flat_walk "$NAME" "$tidx" 1 "" "")"
    else die 2 "없는 기어 · 톱니: $NAME"
    fi
    steps="$(printf '%s\n' "$walk" | cut -f1,2)"
    # 한 단계도 돌기 전에 검사한다 — 없는 이름 · 값 이름 불일치 · 빠진 파일 · 표시 없는 위험 명령
    errs="$(scv_gear_flow_check "$steps" "$tidx")"
    if [[ -z "$errs" ]]; then
      i=0
      while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        i=$((i + 1)); k="${line%%$'\t'*}"; s="${line#*$'\t'}"
        if [[ "$k" == tooth ]]; then
          # 돌리면 안 되는 톱니는 한 단계도 돌기 전에 막는다 — 이름 · 사전의 중복 · 표시 · 파일 · 위험 명령
          r="$(tooth_block "$tidx" "$s")"
          [[ -z "$r" ]] || errs+="${errs:+$'\n'}${i}단계 $s — $r"
        elif [[ "$k" == text ]]; then
          [[ -n "$(scv_gear_body "$(cat "$GDIR/$s/GEAR.md" 2>/dev/null)")" ]] || errs+="${errs:+$'\n'}${i}단계 @$s — 기어의 글이 비었다"
        fi
      done <<< "$steps"
    fi
    # 기어 글의 arg 줄: 모양이 맞고, 흐름의 톱니가 선언한 이름이어야 한다
    decl="$(flow_decl "$steps" "$dict")"
    if [[ -z "$errs" && "$walk" == *=* ]]; then
      i=0
      while IFS= read -r line; do
        i=$((i + 1)); [[ "$line" == tooth$'\t'*$'\t'?* ]] || continue
        while IFS= read -r a; do
          [[ -n "$a" ]] || continue
          if [[ "$a" != *=* || "$(scv_gear_arg_name_ok "${a%%=*}")" != yes ]]; then errs+="${errs:+$'\n'}${i}단계 — 기어 글의 arg 줄 모양이 '이름=값' 이 아니다: $a"
          elif [[ -n "$(scv_gear_args_unknown "$a" "$decl")" ]]; then errs+="${errs:+$'\n'}${i}단계 — 기어 글의 arg 줄의 인자 ${a%%=*} 을 선언한 톱니가 흐름에 없다"; fi
        done <<< "$(step_ov "$walk" "$i")"
      done <<< "$walk"
      [[ -z "$errs" ]] || errs="$(printf '%s\n' "$errs" | LC_ALL=C awk '!s[$0]++')"
    fi
    if [[ -n "$errs" ]]; then
      while IFS= read -r line; do printf 'GEAR_ERROR: %s: %s\n' "$NAME" "$line" >&2; done <<< "$errs"
      exit 1
    fi
    # 실행할 때 준 인자: 모양이 틀리거나 어느 톱니도 선언하지 않은 이름이면 한 단계도 돌리지 않는다
    given="$(scv_gear_args_split "$words")"
    r="$(printf '%s\n' "$given" | sed -n 's/^!//p')"
    [[ -z "$r" ]] || die 2 "인자는 '이름=값' 모양이어야 한다(이름은 영문 소문자로 시작 · 소문자 · 숫자 · 밑줄): $(scv_gear_one_line "$r")"
    names="$(printf '%s\n' "$decl" | sed -n 's/=.*//p')"
    r="$(scv_gear_args_unknown "$given" "$decl")"
    [[ -z "$r" ]] || die 2 "모르는 인자: $(scv_gear_one_line "$r") — 쓸 수 있는 인자: $(scv_gear_one_line "${names:-없음}")"
    tok="$(new_token)"; run="$STATE/$tok"
    mkdir -p "$run" || die 1 "실행 상태 폴더를 만들지 못함: $run"
    printf '%s\n' "$idx" > "$run/index"; printf '%s\n' "$tidx" > "$run/teeth"; printf '%s\n' "$steps" > "$run/steps"
    printf '%s\n' "$NAME" > "$run/name"; [[ -z "$given" ]] || printf '%s\n' "$given" > "$run/given"
    # 단계마다 들어갈 인자를 적어 둔다 — 멈췄다 이어 가도 같은 값이 쓰인다
    [[ -z "$names" ]] || printf '%s\n' "$names" > "$run/argnames"
    i=0
    while IFS= read -r line; do
      [[ -n "$decl" ]] || break
      i=$((i + 1)); [[ "$line" == tooth$'\t'* ]] || continue
      s="${line#*$'\t'}"; s="${s%%$'\t'*}"
      a="$(scv_gear_args_apply "$(scv_gear_args_parse "$dict" "$s")" "$(scv_gear_args_merge "$(step_ov "$walk" "$i")" "$given")")"
      [[ -z "$a" ]] || printf '%s\n' "$a" > "$run/args.$i"
    done <<< "$walk"
    if [[ -t 0 ]]; then : > "$run/data"; else cat > "$run/data"; fi
    drive "$run" 1
    ;;

  resume)
    tok="${1:-}"
    [[ "$tok" =~ ^[0-9abcdef]{8}$ ]] || die 2 "이어가기 표가 필요하다(16진 8자)"
    [[ $# -le 1 ]] || die 2 "이어가기에는 인자를 줄 수 없다 — 처음 준 인자가 그대로 쓰인다"
    run="$STATE/$tok"
    [[ -d "$run" && -f "$run/wait" ]] || die 2 "모르는 표이거나 이미 끝난 실행: $tok"
    i="$(cat "$run/wait")"; k="$(cat "$run/kind" 2>/dev/null)"
    [[ "$i" =~ ^[0-9]{1,4}$ ]] || die 2 "실행 상태를 읽지 못함: $tok"
    case "$k" in
      handoff)
        # 판단 단계의 결과가 다음 단계의 입력이 된다
        if [[ -t 0 ]]; then : > "$run/data"; else cat > "$run/data"; fi
        rm -f "$run/wait" "$run/kind"
        drive "$run" "$((i + 1))" ;;
      confirm)
        if [[ ! -f "$run/confirmed.$i" ]]; then
          tidx="$(cat "$run/teeth")"; line="$(sed -n "${i}p" "$run/steps")"; s="${line#*$'\t'}"; n="$(grep -c . "$run/steps")"
          scv_gear_confirm_text "$tok" "$i/$n $s — $(scv_gear_index_get "$tidx" "$s" does)" "$(cat "$TDIR/$s.sh" 2>/dev/null)" "$SELF resume $tok" "$i" "$(cat "$run/args.$i" 2>/dev/null)"; printf '\n'
          exit 11
        fi
        rm -f "$run/wait" "$run/kind"
        drive "$run" "$i" ;;
      *) die 2 "실행 상태를 읽지 못함: $tok" ;;
    esac
    ;;

  detect)
    # 매 턴 훅이 부른다. 판정은 lib/gear.sh 의 순수 함수가 하고, 여기는 읽기(요청 · 사전 · 기록)와 쓰기(기록 한 줄 · 알린 표시)만 한다.
    # 요청 글은 비밀 가림을 거친 것만 견주고 쌓는다 — 맞춰 보기용 글도 가린 글에서 만든다(원문의 비밀이 조각으로 남지 않게).
    _dk="human"; [[ "${1:-}" == "--kind" ]] && _dk="${2:-human}"
    _dreq="$(head -c 8192 2>/dev/null || true)"
    [[ "$(scv_gear_request_keep "$_dreq" "$_dk" "${SCV_GEAR_DETECT_MIN:-18}")" == "1" ]] || exit 0
    [[ -d "$JDIR" ]] || mkdir -p "$JDIR" 2>/dev/null || exit 0
    _dlog="$JDIR/.gear-requests"; _ddec="$JDIR/.gear-declined"; _dlast="$JDIR/.gear-noticed"
    [[ -L "$_dlog" || -L "$_ddec" || -L "$_dlast" ]] && exit 0
    _dred="$(printf '%s' "$_dreq" | bash "$SCRIPT_DIR/journal-append.sh" --redact-only 2>/dev/null || true)"
    [[ -n "$_dred" ]] || exit 0
    _dline="$(scv_gear_request_line "$_dred" "$(date +%Y-%m-%d)")"
    [[ -n "$_dline" ]] || exit 0
    _dnorm="${_dline#*$'\t'}"; _dnorm="${_dnorm%%$'\t'*}"
    _dgear=""; _dpast=""
    [[ -f "$GDIR/INDEX.tsv" && ! -L "$GDIR/INDEX.tsv" ]] && _dgear="$(scv_gear_match_index "$_dnorm" "$(head -n 500 "$GDIR/INDEX.tsv" 2>/dev/null)")"
    # 기어가 맞아도 지난 요청을 함께 본다(계획 gear-notice-unmask): 낱말만 겹치는 다른 기어가 새 기어 질문을 가리지 않게.
    if [[ -s "$_dlog" ]]; then
      _ddl=""; [[ -s "$_ddec" ]] && _ddl="$(tail -n 200 "$_ddec" 2>/dev/null)"
      _dpast="$(scv_gear_match_requests "$_dnorm" "$(tail -n "${SCV_GEAR_DETECT_LINES:-200}" "$_dlog" 2>/dev/null)" "${SCV_GEAR_DETECT_SCORE:-55}" "$_ddl")"
    fi
    _dout="$(scv_gear_notice_line "$_dgear" "$_dpast" "$SCRIPT_DIR/gear.sh")"
    if [[ -n "$_dout" ]]; then
      printf '%s\n' "$_dout"
      if [[ -n "$_dpast" ]]; then printf '%s\n' "$_dnorm" > "$_dlast" 2>/dev/null || true; else rm -f "$_dlast" 2>/dev/null || true; fi
    fi
    printf '%s\n' "$_dline" >> "$_dlog" 2>/dev/null || true
    exit 0 ;;
  decline)
    _dlast="$JDIR/.gear-noticed"; _ddec="$JDIR/.gear-declined"
    [[ -L "$_dlast" || -L "$_ddec" ]] && { echo "✖ 기록 자리가 링크라 쓰지 않는다" >&2; exit 2; }
    [[ -s "$_dlast" ]] || { echo "알린 요청이 없다 — 적을 것이 없음"; exit 0; }
    head -n 1 "$_dlast" >> "$_ddec" 2>/dev/null && rm -f "$_dlast" 2>/dev/null
    echo "적음: 이 요청은 기어로 만들지 않음 — 다시 알리지 않는다"; exit 0 ;;
  confirm)
    Q=""; A=""
    while [[ $# -gt 0 ]]; do
      [[ $# -ge 2 ]] || usage
      case "$1" in
        --question) Q="${2:-}"; shift 2 ;;
        --answer) A="${2:-}"; shift 2 ;;
        *) usage ;;
      esac
    done
    ts="$(scv_gear_confirm_token "$Q")"
    [[ -n "$ts" ]] || exit 0
    tok="${ts%%:*}"; step="${ts#*:}"
    run="$STATE/$tok"
    # 지금 그 단계 앞에서 확인을 기다리는 실행일 때만 적는다 — 지난 단계의 물음을 다시 보내도 다음 단계가 열리지 않는다
    [[ -d "$run" && "$(cat "$run/kind" 2>/dev/null)" == confirm && "$(cat "$run/wait" 2>/dev/null)" == "$step" ]] || { echo "GEAR_CONFIRM_UNKNOWN: $ts"; exit 0; }
    if [[ "$(scv_gear_confirm_ok "$A")" == yes ]]; then
      : > "$run/confirmed.$step"
      echo "GEAR_CONFIRMED: $ts"
    else
      rm -f "$run/confirmed.$step"   # 나중 답이 거절이면 앞의 "실행"도 거둔다
      echo "GEAR_DECLINED: $ts"
    fi
    exit 0
    ;;

  *) usage ;;
esac
