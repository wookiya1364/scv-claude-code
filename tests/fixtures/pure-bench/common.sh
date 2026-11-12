#!/usr/bin/env bash
# fixtures/pure-bench/common.sh — 재는 명령 시험 네 파일(test-pure-bench-a.sh ~ d.sh)이 함께 쓰는 준비.
# 시험 파일이 CORE 와 PB 를 정한 뒤 source 한다 — 혼자 돌리는 파일이 아니다.
# 준비는 임시 폴더에 작은 파일 몇 개를 쓰는 것뿐이라 넷이 따로 해도 시간이 들지 않는다
# (2026-11-12 실측: 나누기 전 271초 가운데 준비는 1초 미만).

# shellcheck source=../../../scripts/lib/pure-catalog.sh
source "$CORE/scripts/lib/pure-catalog.sh"
# shellcheck source=../../../scripts/lib/pure-bench.sh
source "$CORE/scripts/lib/pure-bench.sh"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
eq()   { if [[ "$2" == "$3" ]]; then ok "OK [$1]"; else fail "[$1] want [$2] got [$3]"; fi; }
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# 잰 줄 파일에서 함수 한 줄의 칸 하나 — <파일> <함수> <칸 번호>
col() { awk -F'\t' -v n="$2" -v c="$3" '$1 == n { print $c }' "$1"; }

# 앞뒤 잰 줄 하나의 판정(함수 이름 칸은 뺀다)
v() { pb_compare "$1" | cut -f2-; }

# 임시 함수 둘과 사전 — 함수 재기(S6)가 쓰는 바탕. $B 를 정한다.
pbt_base() {
  B="$TMP/base"; mkdir -p "$B/lib" "$B/cat"
  cat > "$B/lib/t.sh" <<'LIB'
t_each() { local l; while IFS= read -r l; do printf '%s\n' "$l" | tr 'a-z' 'A-Z'; done <<< "$1"; }
t_once() { printf '%s\n' "$1" | tr 'a-z' 'A-Z'; }
LIB
  printf '### t_each\n- 위치: lib/t.sh · @pure · sh\n- 예: `$\x27a\\nb\x27 → $\x27A\\nB\x27`\n\n### t_once\n- 위치: lib/t.sh · @pure · sh\n- 예: `$\x27a\\nb\x27 → $\x27A\\nB\x27`\n\n### t_gone\n- 위치: lib/t.sh · @pure · sh\n- 예: `"a b" → "x"`\n\n### t_fixed\n- 위치: lib/t.sh · @pure · sh\n- 예: `7 → "7"`\n\n### t_ts\n- 위치: src/x.ts · @pure · ts\n- 예: `"a b" → "2"`\n' > "$B/cat/a.md"
}

# 엮은 함수 셋을 바탕에 더한다 — 엮은 함수 재기(S13)부터 쓴다. pbt_base 뒤에 부른다.
pbt_base_composed() {
  cat >> "$B/lib/t.sh" <<'LIB'
t_up()   { printf '%s\n' "$1" | tr 'a-z' 'A-Z'; }
t_rev()  { printf '%s\n' "$1" | tr 'A-Z' 'a-z'; }
t_both() { t_rev "$(t_up "$1")"; }
LIB
  printf '\n### t_up\n- 역할: 대문자로 바꾼다\n- 위치: lib/t.sh · @deterministic · sh\n- 예: `$\x27a\\nb\x27 → $\x27A\\nB\x27`\n\n### t_rev\n- 역할: 소문자로 바꾼다\n- 위치: lib/t.sh · @deterministic · sh\n- 예: `$\x27A\\nB\x27 → $\x27a\\nb\x27`\n\n### t_both\n- 역할: 둘을 잇는다 — 대문자로 바꿨다가 소문자로\n- 위치: lib/t.sh · @deterministic · sh\n- 예: `$\x27a\\nb\x27 → $\x27a\\nb\x27`\n' >> "$B/cat/a.md"
}

# 끝 줄과 끝 코드
pbt_finish() {
  echo
  echo "── $PASS passed, $FAIL failed"
  [[ $FAIL -eq 0 ]]
}
