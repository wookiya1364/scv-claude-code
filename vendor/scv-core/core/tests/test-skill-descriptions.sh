#!/usr/bin/env bash
# test-skill-descriptions.sh — 래퍼 스킬 파일의 이름·설명 길이·모델 줄 검사 (v0.47.0+).
#
# 왜 있나: 호스트는 스킬 설명을 목록에 실어 모델이 언제 부를지 고르게 한다. 그 목록은
# 설명 1,536자에서 잘리고, 전체가 예산을 넘으면 덜 쓰인 스킬부터 조용히 빠진다 —
# "설치는 됐는데 절대 안 뜨는" 무증상 실패. 또 name 줄이 없으면 스킬 이름이 설치
# 디렉터리명(버전 문자열)으로 떨어져 갱신마다 바뀐다. 이 검사가 그 셋을 기계로 본다.
#
# 무엇을 보나 (skills/<action>/SKILL.md 마다):
#   - name: 이 디렉터리명과 같다
#   - description 이 있고 개별 상한(기본 1536) 이내, 전체 합계가 상한(기본 8000) 이내
#   - model: 줄이 없다 (0.45.0 — 명령은 세션 모델을 바꾸지 않는다)
#   - context: 줄이 없다 (계획 결정 — 포크는 사용자와 대화하지 못한다)
#
# 순수부: 문자열을 받아 위반 줄을 내는 함수 셋 (@pure). 파일 읽기와 출력은 바깥층.
#
# 대상: 옆 체크아웃 scv-claude-code/skills (없으면 SKIP). 환경변수로 바꿀 수 있다 —
#   SCV_SKILLS_DIR=<dir>  SCV_SKILL_DESC_MAX=<n>  SCV_SKILL_DESC_TOTAL_MAX=<n>
#
# Covers TESTS.md T2·T6·T9 of 20260911-wookiya1364-skills-layout-gates.
#
# Run: bash core/tests/test-skill-descriptions.sh
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE=""
for up in "$HERE/.." "$HERE/../.."; do
  for sub in core vendor/scv-core/core plugins/scv/vendor/scv-core/core; do
    if [[ -f "$up/$sub/scripts/lib/settings.sh" ]]; then CORE="$(cd "$up/$sub" && pwd)"; break 2; fi
  done
done
[[ -n "$CORE" ]] || { echo "test-skill-descriptions: payload not found from $HERE" >&2; exit 1; }

PASS=0; FAIL=0; SKIP=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
skip() { echo "  – SKIP: $1"; SKIP=$((SKIP + 1)); }

DESC_MAX="${SCV_SKILL_DESC_MAX:-1536}"
TOTAL_MAX="${SCV_SKILL_DESC_TOTAL_MAX:-8000}"

# ---------------------------------------------------------------- 순수부
# @pure
# frontmatter 문자열 → "name<US>description<US>hasModel<US>hasContext" 한 줄 (US = \x1f).
# 탭이 아니라 단위 구분자(\x1f)를 쓴다 — 탭은 IFS 공백류라 빈 칸이 합쳐져 값이 밀린다.
# description 은 따옴표를 벗긴 값. 여러 줄(접힘 `>`·`|`, 들여쓴 이어쓰기)은 공백으로 잇는다.
# name 도 따옴표를 벗긴다. 같은 키가 두 번이면 첫 번째만.
scv_skill_meta() {
  local fm="${1:-}" line k v name="" desc="" model=0 ctx=0 in_desc=0 seen_desc=0 first
  local us=$'\x1f' gt=$'\076' bar=$'\174'
  while IFS= read -r line; do
    line="${line%$'\r'}"
    if (( in_desc )); then
      if [[ "$line" == [[:space:]]* ]]; then
        v="${line#"${line%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
        [[ -n "$desc" ]] && desc="$desc $v" || desc="$v"
        continue
      fi
      in_desc=0
    fi
    k="${line%%:*}"; v="${line#*:}"
    [[ "$k" == "$line" || "$k" == [[:space:]]* ]] && continue
    v="${v#"${v%%[![:space:]]*}"}"; v="${v%"${v##*[![:space:]]}"}"
    case "$k" in
      name)        if [[ -z "$name" ]]; then v="${v#\"}"; v="${v%\"}"; v="${v#\'}"; v="${v%\'}"; name="$v"; fi ;;
      description) if (( seen_desc == 0 )); then
                     seen_desc=1; in_desc=1; first="${v:0:1}"
                     if [[ "$first" == "$gt" || "$first" == "$bar" ]]; then desc=""   # 접힘 블록: 다음 줄들이 본문
                     else v="${v#\"}"; v="${v%\"}"; v="${v#\'}"; v="${v%\'}"; desc="$v"; fi
                   fi ;;
      model)       model=1 ;;
      context)     ctx=1 ;;
    esac
  done <<< "$fm"
  desc="${desc#\"}"; desc="${desc%\"}"
  printf '%s%s%s%s%s%s%s' "$name" "$us" "$desc" "$us" "$model" "$us" "$ctx"
}

# @pure
# meta 줄 + 디렉터리명 + 개별 상한 → 위반 줄들 (없으면 아무것도 안 낸다).
scv_skill_check() {
  local meta="${1:-}" dir="${2:-}" max="${3:-1536}" name desc model ctx n us=$'\x1f'
  name="${meta%%"$us"*}"; meta="${meta#*"$us"}"
  desc="${meta%%"$us"*}"; meta="${meta#*"$us"}"
  model="${meta%%"$us"*}"; ctx="${meta#*"$us"}"
  [[ "$name" == "$dir" ]] || printf 'name mismatch: "%s" != directory "%s"\n' "$name" "$dir"
  [[ -n "$desc" ]] || printf 'description missing\n'
  n=${#desc}
  (( n <= max )) || printf 'description %d chars exceeds %d\n' "$n" "$max"
  [[ "$model" == "0" ]] || printf 'model: line present (commands never change the session model)\n'
  [[ "$ctx" == "0" ]] || printf 'context: line present (forked skills cannot talk to the user)\n'
  return 0
}

# @pure
# 설명 길이들(공백 구분) → 합계.
scv_skill_total() {
  local total=0 n
  for n in ${1:-}; do
    [[ "$n" =~ ^[0-9]+$ ]] && total=$((total + n))
  done
  printf '%s' "$total"
}

# ---------------------------------------------------------------- 바깥층
frontmatter_of() {  # <파일> → 첫 --- 와 닫는 --- 사이
  awk 'NR==1 { if ($0 !~ /^---\r?$/) exit; next } /^---\r?$/ { exit } { print }' "$1" 2>/dev/null
}

# check_dir <skills dir> → 위반 수를 낸다 (stdout: 위반 줄들)
check_dir() {
  local dir="$1" f d meta viol lens="" bad=0 n
  for f in "$dir"/*/SKILL.md; do
    [[ -f "$f" ]] || continue
    d="$(basename "$(dirname "$f")")"
    meta="$(scv_skill_meta "$(frontmatter_of "$f")")"
    viol="$(scv_skill_check "$meta" "$d" "$DESC_MAX")"
    if [[ -n "$viol" ]]; then
      bad=$((bad + 1)); printf '%s:\n%s\n' "$f" "$viol" | sed 's/^/    /'
    fi
    desc="${meta#*$'\x1f'}"; desc="${desc%%$'\x1f'*}"; lens="$lens ${#desc}"
  done
  n="$(scv_skill_total "$lens")"
  if (( n > TOTAL_MAX )); then bad=$((bad + 1)); printf '    total description length %d > %d\n' "$n" "$TOTAL_MAX"; fi
  printf 'TOTAL=%s BAD=%s\n' "$n" "$bad"
}

echo "test-skill-descriptions: $CORE"

echo "── [T0] 순수부 단위 ──"
m="$(scv_skill_meta $'name: help\r\ndescription: "Use when x."\nmodel: some-model\n')"
[[ "$m" == $'help\x1fUse when x.\x1f1\x1f0' ]] && ok "meta 파싱 (CRLF·따옴표·model 감지)" || fail "meta 파싱 결과가 다르다: [$m]"
v="$(scv_skill_check "$m" help 1536)"; [[ "$v" == *"model: line present"* && "$v" != *"name mismatch"* ]] && ok "check: model 줄 위반만" || fail "check 결과: $v"
v="$(scv_skill_check $'x\x1fabc\x1f0\x1f0' help 2)"; [[ "$v" == *"name mismatch"* && "$v" == *"3 chars exceeds 2"* ]] && ok "check: 이름 불일치 + 길이 초과" || fail "check 결과: $v"
[[ "$(scv_skill_total "1 2 3")" == "6" ]] && ok "total 합계" || fail "total 이 6 이 아니다"
m="$(scv_skill_meta $'name: "help"\ndescription: >\n  line one\n  line two\nmodel: some-model\n')"
[[ "$m" == $'help\x1fline one line two\x1f1\x1f0' ]] && ok "meta: 따옴표 name · 접힘(>) 여러 줄 description 을 잇는다" || fail "접힘 description 파싱: [$m]"
m="$(scv_skill_meta $'name: help\ndescription: "first\n  second"\ncontext: fork\n')"
[[ "$m" == $'help\x1ffirst second\x1f0\x1f1' ]] && ok "meta: 따옴표 이어쓰기 description 을 잇는다" || fail "이어쓰기 파싱: [$m]"
m="$(scv_skill_meta $'name: help\ndescription: ""\nmodel: x\n')"
v="$(scv_skill_check "$m" help 1536)"; [[ "$v" == *"description missing"* && "$v" == *"model: line"* && "$v" != *"context"* ]] && ok "check: 빈 description 이 '없음' 으로 잡히고 값이 밀리지 않는다" || fail "빈 description 처리: [$v]"
bash "$CORE/scripts/check-purity.sh" "${BASH_SOURCE[0]}" >/dev/null 2>&1 && ok "@pure 셋이 순수성 검사 통과" || fail "순수성 검사 실패"

# 대상 디렉터리
SKILLS="${SCV_SKILLS_DIR:-}"
if [[ -z "$SKILLS" ]]; then
  SIB="$(cd "$CORE/../.." 2>/dev/null && pwd)"
  [[ -d "$SIB/scv-claude-code/skills" ]] && SKILLS="$SIB/scv-claude-code/skills"
fi

if [[ -n "$SKILLS" && -d "$SKILLS" ]]; then
  echo "── [T1] 실제 래퍼 skills/: $SKILLS ──"
  out="$(check_dir "$SKILLS")"; summary="$(printf '%s\n' "$out" | tail -1)"
  cnt="$(ls "$SKILLS"/*/SKILL.md 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$summary" == *"BAD=0" ]]; then ok "스킬 ${cnt}개 전부 통과 ($summary, 개별 ≤${DESC_MAX} · 합계 ≤${TOTAL_MAX})"
  else fail "위반 있음 — $summary"; printf '%s\n' "$out" | grep -v '^TOTAL='; fi
  [[ ! -e "$SKILLS/../commands" ]] && ok "예전 commands/ 폴더 없음" || fail "commands/ 가 아직 있다"
  expected="codegen deck handoff help install-deps promote regression report routine set-models status sync update work workspace"
  actual="$(ls "$SKILLS" | LC_ALL=C sort | tr '\n' ' ' | sed 's/ $//')"
  [[ "$actual" == "$expected" ]] && ok "호출 이름 열다섯 개가 그대로다" || fail "스킬 집합이 다르다: $actual"
else
  skip "래퍼 skills/ 디렉터리 없음 (옆 체크아웃 없거나 SCV_SKILLS_DIR 미지정)"
fi

echo "── [T2] 위반을 실제로 잡는가 (임시 복제) ──"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/a/skills/help" "$WORK/a/skills/status"
long="$(printf 'x%.0s' $(seq 1 1600))"
printf -- '---\nname: help\ndescription: "%s"\n---\nbody\n' "$long" > "$WORK/a/skills/help/SKILL.md"
printf -- '---\nname: status\ndescription: "short"\n---\nbody\n' > "$WORK/a/skills/status/SKILL.md"
out="$(check_dir "$WORK/a/skills")"
[[ "$out" == *"1600 chars exceeds 1536"* && "$out" == *"BAD=1"* ]] && ok "개별 1,600자 → 실패 1건" || fail "개별 상한을 못 잡는다: $(printf '%s' "$out" | tail -1)"
mkdir -p "$WORK/b/skills"
for i in 1 2 3 4 5 6; do mkdir -p "$WORK/b/skills/s$i"; printf -- '---\nname: s%s\ndescription: "%s"\n---\n' "$i" "$(printf 'y%.0s' $(seq 1 1400))" > "$WORK/b/skills/s$i/SKILL.md"; done
out="$(check_dir "$WORK/b/skills")"
[[ "$out" == *"total description length 8400 > 8000"* ]] && ok "합계 8,400자 → 실패" || fail "합계 상한을 못 잡는다: $(printf '%s' "$out" | tail -1)"
mkdir -p "$WORK/c/skills/help"; printf -- '---\nname: helper\ndescription: "d"\nmodel: some-model\ncontext: fork\n---\n' > "$WORK/c/skills/help/SKILL.md"
out="$(check_dir "$WORK/c/skills")"
[[ "$out" == *"name mismatch"* && "$out" == *"model: line"* && "$out" == *"context: line"* ]] && ok "이름 불일치 · model · context 줄을 잡는다" || fail "잡지 못함: $out"

echo
echo "test-skill-descriptions: PASS=$PASS FAIL=$FAIL SKIP=$SKIP"
[[ $FAIL -eq 0 ]]
