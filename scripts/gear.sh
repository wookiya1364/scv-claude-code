#!/usr/bin/env bash
# gear.sh — 기어(스킬)와 톱니(아주 작은 sh)를 만들고 · 검사하고 · 돌린다 (계획 20261124-wookiya1364-gears-run).
#
# 되풀이되는 작업에서 정해진 흐름은 톱니가 돌고, 모델은 판단이 필요한 자리의 글과 앞 단계 결과만 읽게 한다.
# 모두 프로젝트의 scv/gears/ 안에만 있다 — 호스트의 스킬 폴더에는 아무것도 쓰지 않는다.
#
#   gear.sh list                         기어와 톱니를 보여 준다(없으면 "기어 없음" 한 줄)
#   gear.sh new <이름> --kind tooth [--does "<하는 일>"] [--mark pure|effect|outward] [--in <받는 값>] [--out <돌려주는 값>]
#                      [--example '<입력 표기> → <출력 표기>']
#   gear.sh new <이름> --kind gear --flow "<톱니> | <톱니> | @ | <톱니>" [--does "<하는 일>"] [--words "<낱말들>"]
#                                        뼈대 파일을 쓰고 사전을 다시 만든다 (@ 는 이 기어의 글 — 판단 단계)
#   gear.sh index                        톱니 사전과 기어 글에서 사전(INDEX.tsv)을 다시 만든다
#   gear.sh check                        사전 · 파일 · 흐름 · 순수 톱니의 예시 · 표시 없는 위험 명령을 검사한다
#   gear.sh run <이름>                    기어나 톱니를 돌린다 — 처음 입력은 표준 입력
#   gear.sh resume <표>                   멈춘 실행을 잇는다 — 판단 단계 뒤에는 그 단계의 결과를 표준 입력으로
#   gear.sh confirm --question <글> --answer <글>
#                                        선택 답 훅이 부른다 — 질문에 [기어 확인 <표>] 가 있고 답이 "실행"이면 확인으로 적는다
#
# 자리:  scv/gears/teeth/<톱니>.sh      톱니 본문 — 표준 입력 → 표준 출력, 한 가지 일만. 주석 없이 본문만 둔다
#        scv/gears/teeth/TEETH.md       톱니 사전(원본) — 톱니마다 역할 · 표시 · 값 · 예시
#        scv/gears/<기어>/GEAR.md        기어 — 맨 위 flow · does · words 줄, 그 아래 판단 단계의 글
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
  sed -n '6,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

# @effect die
# 이유: 오류 한 줄을 표준 오류에 쓰고 주어진 종료 코드로 끝낸다
die() { printf 'GEAR_ERROR: %s\n' "$2" >&2; exit "$1"; }

# @effect teeth_text
# 이유: 톱니 사전 파일을 읽는다(없으면 빈 값)
teeth_text() { [[ -f "$TDICT" ]] && cat "$TDICT"; return 0; }

# @effect flat_flow
# 이유: 기어 글 파일들을 읽어 흐름을 펼친다 — 톱니는 그대로, @ 는 그 기어의 글, 다른 기어 이름은 그 기어의 흐름으로(되돌아오거나 8단을 넘으면 오류 줄)
flat_flow() {
  local g="$1" tidx="$2" depth="$3" seen="$4" text tok
  (( depth <= 8 )) || { printf 'error\t%s — 흐름이 너무 깊다(8단 넘음)\n' "$g"; return 0; }
  case " $seen " in *" $g "*) printf 'error\t%s — 흐름이 자기 자신으로 돌아온다\n' "$g"; return 0 ;; esac
  [[ -f "$GDIR/$g/GEAR.md" ]] || { printf 'unknown\t%s\n' "$g"; return 0; }
  text="$(cat "$GDIR/$g/GEAR.md")"
  [[ -n "$(scv_gear_flow_parse "$(scv_gear_front_get "$text" flow)")" ]] || { printf 'error\t%s — 맨 위에 flow 줄이 없다\n' "$g"; return 0; }
  while IFS= read -r tok; do
    [[ -n "$tok" ]] || continue
    if [[ "$tok" == "@" ]]; then printf 'text\t%s\n' "$g"
    elif [[ -n "$(scv_gear_index_get "$tidx" "$tok" kind)" ]]; then printf 'tooth\t%s\n' "$tok"
    elif [[ "$(scv_gear_name_ok "$tok")" == yes && -f "$GDIR/$tok/GEAR.md" ]]; then flat_flow "$tok" "$tidx" $((depth + 1)) "$seen $g"
    else printf 'unknown\t%s\n' "$tok"
    fi
  done <<< "$(scv_gear_flow_parse "$(scv_gear_front_get "$text" flow)")"
  return 0
}

# @effect gear_lines
# 이유: 기어 글 파일들을 읽어 기어의 사전 줄들을 낸다 — 받는 값 · 돌려주는 값은 펼친 흐름의 첫 톱니 · 끝 톱니에서
gear_lines() {
  local tidx="$1" f d name text flat first last gin gout
  for f in "$GDIR"/*/GEAR.md; do
    [[ -f "$f" ]] || continue
    d="${f%/GEAR.md}"; name="${d##*/}"
    [[ "$name" != teeth ]] || continue
    text="$(cat "$f")"
    flat="$(flat_flow "$name" "$tidx" 1 "")"
    first="$(printf '%s\n' "$flat" | sed -n $'s/^tooth\t//p' | head -n 1)"
    last="$(printf '%s\n' "$flat" | sed -n $'s/^tooth\t//p' | tail -n 1)"
    gin="$(scv_gear_index_get "$tidx" "$first" in)"; gout="$(scv_gear_index_get "$tidx" "$last" out)"
    printf '%s\tgear\t-\t%s\t%s\t%s\t%s\n' "$name" "${gin:-*}" "${gout:-*}" \
      "$(scv_gear_one_line "$(scv_gear_front_get "$text" does)")" "$(scv_gear_one_line "$(scv_gear_front_get "$text" words)")"
  done
  return 0
}

# @effect built_index
# 이유: 톱니 사전과 기어 글 파일들을 읽어 지금의 사전 글을 만든다(파일은 쓰지 않는다)
built_index() {
  local tidx; tidx="$(scv_gear_teeth_parse "$(teeth_text)")"
  scv_gear_index_build "$(printf '%s\n%s' "$tidx" "$(gear_lines "$tidx")")"
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
  local tidx="$1" s="$2" m c r body
  [[ "$(scv_gear_name_ok "$s")" == yes ]] || { printf '쓸 수 없는 톱니 이름'; return 0; }
  c="$(printf '%s\n' "$tidx" | LC_ALL=C awk -F'\t' -v n="$s" '$1 == n' | grep -c .)"
  [[ "$c" == 1 ]] || { printf '톱니 사전에 %s번 적혀 있다(한 번만 적는다)' "$c"; return 0; }
  m="$(scv_gear_index_get "$tidx" "$s" mark)"
  case "$m" in pure|effect|outward) ;; *) printf '표시가 pure · effect · outward 중 하나가 아니다(지금: %s)' "$m"; return 0 ;; esac
  [[ -f "$TDIR/$s.sh" ]] || { printf '톱니 파일이 없다'; return 0; }
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

# @effect run_example
# 이유: 톱니를 예시 입력으로 실제로 돌려 출력 파일에 받는다 — 정한 시간(초)을 넘기면 죽이고 124 를 낸다
run_example() {
  local f="$1" infile="$2" outfile="$3" pid w rc
  bash "$f" < "$infile" > "$outfile" 2>/dev/null & pid=$!
  ( sleep "$EXSECS"; kill -9 "$pid" 2>/dev/null ) >/dev/null 2>&1 & w=$!
  wait "$pid" 2>/dev/null; rc=$?
  if kill "$w" 2>/dev/null; then wait "$w" 2>/dev/null; else rc=124; fi
  return "$rc"
}

# @effect lint_teeth
# 이유: 톱니 파일들을 읽고 · 문법을 검사하고 · 순수 톱니를 예시 입력으로 실제로 돌려 문제 줄들을 낸다(알림은 GEAR_WARN)
lint_teeth() {
  local tidx="$1" dict line name mark f body r ex k parts in_lit out_lit want got rc why tmp seen=" " out=""
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
    k=0
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      k=$((k + 1))
      parts="$(scv_gear_example_split "$line")"
      if [[ -z "$parts" ]]; then out+="GEAR_EXAMPLE: $name — 예시 $k 의 모양이 '<입력> → <출력>' 이 아니다"$'\n'; continue; fi
      in_lit="${parts%%$'\n'*}"; out_lit="${parts#*$'\n'}"
      want="$(scv_gear_lit_decode "$out_lit")"
      scv_gear_lit_decode "$in_lit" > "$tmp/in"
      run_example "$f" "$tmp/in" "$tmp/out"; rc=$?
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
  local tidx="$1" idx="$2" d name text flat e line t r out=""
  for d in "$GDIR"/*/; do
    [[ -d "$d" ]] || continue
    name="${d%/}"; name="${name##*/}"
    [[ "$name" != teeth ]] || continue
    if [[ ! -f "$d/GEAR.md" ]]; then out+="GEAR_BAD: $name — 기어 글(GEAR.md)이 없다"$'\n'; continue; fi
    [[ "$(scv_gear_name_ok "$name")" == yes ]] || out+="GEAR_BAD: $name — 이름은 영문 소문자 · 숫자 · 붙임표만"$'\n'
    [[ -z "$(scv_gear_index_get "$tidx" "$name" kind)" ]] || out+="GEAR_BAD: $name — 같은 이름의 톱니가 있다(기어와 톱니는 이름이 달라야 한다)"$'\n'
    text="$(cat "$d/GEAR.md")"
    if [[ -z "$(scv_gear_front_get "$text" flow)" ]]; then out+="GEAR_BAD: $name — 맨 위에 flow 줄이 없다"$'\n'; continue; fi
    flat="$(flat_flow "$name" "$tidx" 1 "")"
    e="$(scv_gear_flow_check "$flat" "$tidx")"
    while IFS= read -r line; do [[ -n "$line" ]] && out+="GEAR_FLOW: $name: $line"$'\n'; done <<< "$e"
    e="$(scv_gear_flow_warn "$flat" "$tidx")"
    while IFS= read -r line; do [[ -n "$line" ]] && out+="GEAR_WARN: $name: $line"$'\n'; done <<< "$e"
    if [[ $'\n'"$flat"$'\n' == *$'\n'"text"$'\t'"$name"$'\n'* && -z "$(scv_gear_body "$text")" ]]; then
      out+="GEAR_BAD: $name — flow 에 @ 가 있는데 글이 비었다"$'\n'
    fi
  done
  t=""; [[ -f "$GDIR/INDEX.tsv" ]] && t="$(cat "$GDIR/INDEX.tsv")"
  if [[ "$t" != "$idx" ]]; then
    r="$( { printf '%s\n' "$t"; printf '%s\n' "$idx"; } | LC_ALL=C sort | LC_ALL=C uniq -u | LC_ALL=C awk -F'\t' 'NF > 0 && !s[$1]++ { printf "%s%s", (n++ ? " " : ""), $1 }')"
    out+="GEAR_INDEX_STALE: 사전(INDEX.tsv)이 톱니 사전 · 기어 글과 다르다 — 어긋난 이름: ${r:-?} · gear.sh index 로 다시 만들어라(INDEX.tsv 는 손으로 고치지 않는다)"$'\n'
  fi
  printf '%s' "$out"
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
        bash "$TDIR/$s.sh" < "$run/data" > "$run/next" 2> "$run/err"; rc=$?
        if (( rc != 0 )); then
          printf 'GEAR_ERROR: %s단계 %s — 종료 코드 %s\n' "$i" "$s" "$rc" >&2
          tail -n 5 "$run/err" >&2
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
        scv_gear_confirm_text "${run##*/}" "$label" "$(cat "$TDIR/$s.sh")" "$SELF resume ${run##*/}" "$i"; printf '\n'
        exit 11 ;;
      *) printf 'GEAR_ERROR: %s단계 %s — 돌릴 수 없다(종류 %s · 표시 %s)\n' "$i" "$s" "$k" "$mark" >&2; rm -rf "$run"; exit 1 ;;
    esac
  done
  cat "$run/data"
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
      printf '이름\t하는 일\t흐름\n'
      while IFS= read -r line; do
        [[ "$(scv_gear_index_get "$line" "${line%%$'\t'*}" kind)" == gear ]] || continue
        name="${line%%$'\t'*}"
        printf '%s\t%s\t%s\n' "$name" "$(scv_gear_index_get "$line" "$name" does)" "$(scv_gear_front_get "$(cat "$GDIR/$name/GEAR.md" 2>/dev/null)" flow)"
      done <<< "$idx"
    fi
    printf '톱니 %s개\n' "$nt"
    if (( nt > 0 )); then
      printf '이름\t표시\t값\t하는 일\n'
      printf '%s\n' "$idx" | LC_ALL=C awk -F'\t' '$2 == "tooth" { printf "%s\t%s\t%s → %s\t%s\n", $1, $3, $4, $5, $6 }'
    fi
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
    KIND=""; DOES=""; GIN=""; GOUT=""; MARK=""; WORDS=""; FLOW=""; EX=""
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
        *) usage ;;
      esac
    done
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
        printf '\n%s\n' "$(scv_gear_tooth_entry "$NAME" "$(scv_gear_one_line "$DOES")" "$MARK" "$(scv_gear_one_line "${GIN:-*}")" "$(scv_gear_one_line "${GOUT:-*}")" "$(scv_gear_one_line "$EX")")" >> "$TDICT"
        where="$TDIR/$NAME.sh" ;;
      gear)
        [[ -n "$FLOW" ]] || die 2 "--flow 가 필요하다(예: \"a | b | @ | c\")"
        mkdir -p "$GDIR/$NAME" || die 1 "폴더를 만들지 못함: $GDIR/$NAME"
        {
          printf 'flow: %s\n' "$(scv_gear_one_line "$FLOW")"
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
    nf=0; nw=0
    if [[ -n "$out" ]]; then
      printf '%s\n' "$out"
      nf="$(printf '%s\n' "$out" | grep -v '^GEAR_WARN: ' | grep -c .)"
      nw="$(printf '%s\n' "$out" | grep -c '^GEAR_WARN: ')"
    fi
    if (( nf > 0 )); then echo "GEAR_CHECK: 실패 — ${nf}건 · 알림 ${nw}건"; exit 1; fi
    ng="$(printf '%s\n' "$idx" | LC_ALL=C awk -F'\t' '$2 == "gear"' | grep -c .)"
    nt="$(printf '%s\n' "$idx" | LC_ALL=C awk -F'\t' '$2 == "tooth"' | grep -c .)"
    echo "GEAR_CHECK: 통과 — 기어 ${ng}개 · 톱니 ${nt}개 · 알림 ${nw}건"
    exit 0
    ;;

  run)
    NAME="${1:-}"
    [[ "$(scv_gear_name_ok "$NAME")" == yes ]] || die 2 "기어나 톱니 이름이 필요하다"
    tidx="$(scv_gear_teeth_parse "$(teeth_text)")"
    idx="$(built_index)"
    if [[ -n "$(scv_gear_index_get "$tidx" "$NAME" kind)" ]]; then steps="tooth"$'\t'"$NAME"
    elif [[ -f "$GDIR/$NAME/GEAR.md" ]]; then steps="$(flat_flow "$NAME" "$tidx" 1 "")"
    else die 2 "없는 기어 · 톱니: $NAME"
    fi
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
    if [[ -n "$errs" ]]; then
      while IFS= read -r line; do printf 'GEAR_ERROR: %s: %s\n' "$NAME" "$line" >&2; done <<< "$errs"
      exit 1
    fi
    tok="$(new_token)"; run="$STATE/$tok"
    mkdir -p "$run" || die 1 "실행 상태 폴더를 만들지 못함: $run"
    printf '%s\n' "$idx" > "$run/index"; printf '%s\n' "$tidx" > "$run/teeth"; printf '%s\n' "$steps" > "$run/steps"
    if [[ -t 0 ]]; then : > "$run/data"; else cat > "$run/data"; fi
    drive "$run" 1
    ;;

  resume)
    tok="${1:-}"
    [[ "$tok" =~ ^[0-9abcdef]{8}$ ]] || die 2 "이어가기 표가 필요하다(16진 8자)"
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
          scv_gear_confirm_text "$tok" "$i/$n $s — $(scv_gear_index_get "$tidx" "$s" does)" "$(cat "$TDIR/$s.sh" 2>/dev/null)" "$SELF resume $tok" "$i"; printf '\n'
          exit 11
        fi
        rm -f "$run/wait" "$run/kind"
        drive "$run" "$i" ;;
      *) die 2 "실행 상태를 읽지 못함: $tok" ;;
    esac
    ;;

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
