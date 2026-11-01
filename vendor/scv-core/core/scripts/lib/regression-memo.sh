#!/usr/bin/env bash
# lib/regression-memo.sh — 회귀 시험의 '같은 시험은 한 번만' 판정부. 글을 받아 글을 낸다.
#
# 보관된 계획들이 같은 시험을 각자 적어 두어, 회귀 한 번에 같은 시험이 여러 번 돌았다
# (2026-11-01: 실행 250번 중 서로 다른 시험 73개, 49분 넘게 미완). scripts/regression.sh 가
# 여기 함수로 시험 줄을 모아 한 번씩 동시에 돌리고, 계획 블록의 그 줄을 결과 코드로 바꾼다.
# 시험을 돌리는 일 · 파일을 읽는 일은 regression.sh 가 한다.

# 시험 줄 모양: 앞 공백 · "bash <경로>.sh" · 글자로 시작하는 인자들 · 꼬리(없음 · 리디렉션 · || · && · ;).
# 꼬리가 파이프 하나(|)면 시험 줄로 보지 않는다 — 출력이 다음 명령의 입력이라 코드만으로는 못 바꾼다.
# 시험 줄 뒤에 와도 되는 꼬리의 시작 — 함수 밖에 둬 순수 검사기가 기호를 리디렉션으로 오해하지 않게.
_SCV_REG_TAIL_OPS='> < 2> &> || && ;'
_SCV_REG_LINE_RE='^([[:space:]]*)(bash[[:space:]]+[A-Za-z0-9._/-]+\.sh([[:space:]]+[A-Za-z-][A-Za-z0-9._=/-]*)*)(.*)$'

# @pure
# 역할: 실행 줄이 '시험 파일 하나를 bash 로 부르는 줄'이면 그 명령(키)을 낸다 — 아니면 빈 값
# 종류: 꺼내기
# 예: "  bash core/tests/test-a.sh >/dev/null || fail a" → "bash core/tests/test-a.sh"
# 예: "bash tests/run.sh --quick" → "bash tests/run.sh --quick"
# 예: "bash core/tests/test-a.sh | tail -1" → ""
# 예: "bash -euo pipefail -c '" → ""
scv_reg_line_key() {
  local line="${1:-}" tail
  [[ "$line" =~ $_SCV_REG_LINE_RE ]] || return 0
  tail="${BASH_REMATCH[4]}"
  tail="${tail#"${tail%%[![:space:]]*}"}"
  local key="${BASH_REMATCH[2]}" op
  [[ -z "$tail" ]] && { printf '%s' "$key"; return 0; }
  for op in $_SCV_REG_TAIL_OPS; do
    [[ "${tail:0:${#op}}" == "$op" ]] && { printf '%s' "$key"; return 0; }
  done
  return 0
}

# @pure
# 역할: 한 줄을 &&, ||, ; 로 이은 조각들로 나눠 '조각<US>뒤 구분자' 줄들로 낸다 — 따옴표가 든 줄은 나누지 않는다
# 종류: 꺼내기
# 예: "bash t/a.sh && bash t/b.sh || exit 1" → $'bash t/a.sh \x1f&&\n bash t/b.sh \x1f||\n exit 1\x1f'
# 예: "echo 'a && b'" → $'echo \'a && b\'\x1f'
# 시험 여럿을 한 줄에 이은 줄이 보관된 계획에 47개 — 첫 시험만 공유되고 나머지는 계획마다 다시 돌았다(2026-11-01).
scv_reg_split_chain() {
  local line="${1:-}" seg="" i=0 n c2
  if [[ "$line" == *"'"* || "$line" == *'"'* ]]; then printf '%s\x1f\n' "$line"; return 0; fi
  n=${#line}
  while [[ $i -lt $n ]]; do
    c2="${line:i:2}"
    if [[ "$c2" == "&&" || "$c2" == "||" ]]; then
      printf '%s\x1f%s\n' "$seg" "$c2"; seg=""; i=$((i + 2)); continue
    elif [[ "${line:i:1}" == ";" ]]; then
      printf '%s\x1f;\n' "$seg"; seg=""; i=$((i + 1)); continue
    fi
    seg+="${line:i:1}"; i=$((i + 1))
  done
  printf '%s\x1f\n' "$seg"
}

# @pure
# 역할: 여러 블록의 줄에서 시험 줄 키를 처음 나온 순서대로 겹치지 않게 모은다
# 종류: 고르기
# 예: $'bash t/a.sh\necho x\n  bash t/a.sh >/dev/null\nbash t/b.sh' → $'bash t/a.sh\nbash t/b.sh'
# 예: "bash t/a.sh && bash t/c.sh" → $'bash t/a.sh\nbash t/c.sh'
# 예: "echo x" → ""
scv_reg_collect_keys() {
  local text="${1:-}" line key seen=$'\n' part
  while IFS= read -r line || [[ -n "$line" ]]; do
    while IFS= read -r part; do
      key="$(scv_reg_line_key "${part%%$'\x1f'*}")"
      [[ -n "$key" ]] || continue
      [[ "$seen" == *$'\n'"$key"$'\n'* ]] && continue
      seen+="$key"$'\n'
      printf '%s\n' "$key"
    done <<< "$(scv_reg_split_chain "$line")"
  done <<< "$text"
}

# @pure
# 역할: 시험 줄이면 그 명령을 기록된 종료 코드 '( exit N )' 로 바꾸고 앞 공백 · 꼬리는 남긴다 — 표에 없으면 그대로
# 종류: 변환
# 예: "  bash t/a.sh >/dev/null || fail a" $'bash t/a.sh\t1' → "  ( exit 1 ) >/dev/null || fail a"
# 예: "bash t/b.sh" $'bash t/a.sh\t0' → "bash t/b.sh"
# 예: "bash t/a.sh && bash t/b.sh" $'bash t/a.sh\t0\nbash t/b.sh\t1' → "( exit 0 ) && ( exit 1 )"
scv_reg_rewrite_line() {
  local line="${1:-}" table="${2:-}" part seg sep key k rc out="" hit=0 done_seg
  while IFS= read -r part; do
    seg="${part%%$'\x1f'*}"; sep="${part#*$'\x1f'}"
    done_seg="$seg"
    key="$(scv_reg_line_key "$seg")"
    if [[ -n "$key" ]]; then
      while IFS=$'\t' read -r k rc; do
        if [[ "$k" == "$key" && -n "$rc" && "$seg" =~ $_SCV_REG_LINE_RE ]]; then
          done_seg="${BASH_REMATCH[1]}( exit $rc )${BASH_REMATCH[4]}"; hit=1; break
        fi
      done <<< "$table"
    fi
    out+="$done_seg$sep"
  done <<< "$(scv_reg_split_chain "$line")"
  if [[ $hit -eq 1 ]]; then printf '%s' "$out"; else printf '%s' "$line"; fi
}

# @pure
# 역할: 블록이 다른 폴더로 옮겨 가면(cd · pushd) 공유 결과를 쓰면 안 되므로 1, 아니면 0 — 괄호 하위 셸 안의 cd 는 괜찮다
# 종류: 판정/gate
# 예: $'bash t/a.sh\necho ok' → [0]
# 예: $'cd sub && bash t/a.sh' → [1]
# 예: $'out=$( cd "$X" && bash t/a.sh )\nbash t/b.sh' → [0]
# 예: $'echo abcd' → [0]
# 하위 셸 '( cd …' 의 이동은 그 괄호 안에서 끝나 블록의 다른 줄에 번지지 않는다(2026-11-01 — 이걸 막다가
# 계획 하나가 공유 결과를 못 써 15분을 혼자 돌았다).
scv_reg_block_memo_ok() {
  [[ "${1:-}" =~ (^|[[:space:]\;\&\|\{])(cd|pushd)[[:space:]] ]] || return 0
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ (^|[\;\&\|\{])[[:space:]]*(cd|pushd)[[:space:]] ]] && return 1
  done <<< "${1:-}"
  return 0
}

# @pure
# 역할: '코어 시험 전부' 반복 줄(for t in core/tests/test-*.sh …)이면 1 을 낸다 — 시험 파일 하나하나로 나눠 공유할 수 있다
# 종류: 판정
# 예: 'for t in core/tests/test-*.sh; do bash "$t" >/dev/null || fail "T $t"; done' → [0]
# 예: "bash core/tests/test-a.sh" → [1]
scv_reg_is_core_loop() {
  [[ "${1:-}" =~ ^[[:space:]]*for[[:space:]]+t[[:space:]]+in[[:space:]]+core/tests/test-\*\.sh\;[[:space:]]*do[[:space:]]+bash[[:space:]]+\"\$t\".*done[[:space:]]*$ ]]
}
