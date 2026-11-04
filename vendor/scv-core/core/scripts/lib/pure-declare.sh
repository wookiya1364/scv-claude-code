#!/usr/bin/env bash
# lib/pure-declare.sh — 모든 함수가 순수 · 부수효과를 선언했는지 보는 순수부 (0.81.0+, 계획 pure-declare-081).
# 효과(파일 읽기, 편집 뒤 본문 만들기, 설정 · 기준선 읽기 · 쓰기, 거절 출력)는 scripts/pure-declare.sh · template/hooks/guard.sh.
#
#   scv_pd_lang <파일 이름>                      → sh | js | py | go | 빈 값(판정하지 않는 언어)
#   scv_pd_functions <언어> <본문>               → 이름 있는 함수 선언 이름들(줄마다 하나, 나온 순서)
#   scv_pd_declared <언어> <본문>                → 선언된 이름들(@pure · @deterministic · @effect)
#   (선언 없는 이름 고르기는 lib/rule-constitution.sh 의 scv_rc_allowed_out <함수 이름들> <선언된 이름들> 을 그대로 쓴다)
#   scv_pd_write_verdict <편집 전 빠진 이름들> <편집 뒤 빠진 이름들> → 편집으로 새로 빠진 이름들(없으면 빈 값)
#
# 선언: 함수 바로 위 주석 묶음에 `@pure` · `@deterministic`(순수 — 역할 · 종류 · 예를 함께, contracts/purity.md) 또는
# `@effect`(바깥을 바꾸는 함수 — `이유:` 한 줄). 표식 줄에 이름을 적으면 그 이름, 적지 않으면 그 뒤에 처음 나오는 함수.
# 함수 찾기는 이름 있는 선언만 본다(익명 함수 · 클래스 메서드는 보지 않는다 — 알려진 한계).
# 꺾쇠 글자는 쓰지 않는다 — 순수성 검사가 리다이렉션으로 본다.

# shellcheck source=rule-constitution.sh
declare -F scv_rc_allowed_out >/dev/null 2>&1 || source "${BASH_SOURCE[0]%/*}/rule-constitution.sh"

# @pure
# 역할: 파일 이름의 확장자로 함수 찾기 규칙(언어)을 고른다 — 모르는 확장자는 빈 값
# 종류: 고르기
# 예: src/a.ts → "js"
# 예: lib/x.sh → "sh"
# 예: app/m.py → "py"
# 예: README.md → ""
scv_pd_lang() {
  case "${1:-}" in
    *.sh|*.bash) printf 'sh' ;;
    *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs|*.mts|*.cts) printf 'js' ;;
    *.py) printf 'py' ;;
    *.go) printf 'go' ;;
    *) return 0 ;;
  esac
}

# @pure
# 역할: 본문 한 줄이 이름 있는 함수 선언이면 그 이름을 낸다(아니면 빈 값)
# 종류: 꺼내기
# 예: sh "foo_bar() {" → "foo_bar"
# 예: js "export async function loadMap(id) {" → "loadMap"
# 예: js "const pick = (a, b) => a" → "pick"
# 예: py "    def _helper(self, x):" → "_helper"
# 예: go "func (s *S) Run() error {" → "Run"
# 예: js "return fn(x)" → ""
scv_pd_line_function() {
  local lang="${1:-}" l="${2:-}"
  local re_sh='^[[:space:]]*(function[[:space:]]+)?([A-Za-z_][A-Za-z0-9_:.-]*)[[:space:]]*\(\)[[:space:]]*(\{|$)'
  local re_sh2='^[[:space:]]*function[[:space:]]+([A-Za-z_][A-Za-z0-9_:.-]*)[[:space:]]*(\{|$)'
  local lt=$'\x3c' gt=$'\x3e'
  local re_js1='^[[:space:]]*(export[[:space:]]+)?(default[[:space:]]+)?(async[[:space:]]+)?function\*?[[:space:]]*([A-Za-z_$][A-Za-z0-9_$]*)[[:space:]]*[('"$lt"']'
  local re_js2='^[[:space:]]*(export[[:space:]]+)?(const|let|var)[[:space:]]+([A-Za-z_$][A-Za-z0-9_$]*)[[:space:]]*(:[^=]*)?=[[:space:]]*(async[[:space:]]*)?(function|(\([^)]*\)|[A-Za-z_$][A-Za-z0-9_$]*)[[:space:]]*(:[^=]*)?=['"$gt"'])'
  local re_py='^[[:space:]]*(async[[:space:]]+)?def[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\('
  local re_go='^func[[:space:]]+(\([^)]*\)[[:space:]]*)?([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*[(\[]'
  case "$lang" in
    sh) if [[ "$l" =~ $re_sh ]]; then printf '%s' "${BASH_REMATCH[2]}"; elif [[ "$l" =~ $re_sh2 ]]; then printf '%s' "${BASH_REMATCH[1]}"; fi ;;
    js) if [[ "$l" =~ $re_js1 ]]; then printf '%s' "${BASH_REMATCH[4]}"; elif [[ "$l" =~ $re_js2 ]]; then printf '%s' "${BASH_REMATCH[3]}"; fi ;;
    py) [[ "$l" =~ $re_py ]] && printf '%s' "${BASH_REMATCH[2]}" ;;
    go) [[ "$l" =~ $re_go ]] && printf '%s' "${BASH_REMATCH[2]}" ;;
  esac
  return 0
}

# @pure
# 역할: 본문에서 이름 있는 함수 선언의 이름들을 나온 순서대로 낸다
# 종류: 꺼내기
# 예: sh $'a() {\n  :\n}\nb() { :; }' → $'a\nb'
# 예: py $'def f(x):\n    return x' → "f"
# 예: js "" → ""
scv_pd_functions() {
  local lang="${1:-}" text="${2:-}" line n out=""
  [[ -n "$lang" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    n="$(scv_pd_line_function "$lang" "$line")"
    [[ -n "$n" ]] && out="${out:+$out$'\n'}$n"
  done <<< "$text"
  printf '%s' "$out"
}

# @pure
# 역할: 본문에서 순수 · 부수효과 선언(@pure · @deterministic · @effect)이 붙은 함수 이름들을 낸다
# 종류: 꺼내기
# 예: sh $'# @pure\n# 역할: x\na() {' → "a"
# 예: js $'/** @effect save\n * 이유: 파일을 쓴다 */\nfunction save() {' → "save"
# 예: py $'# @pure\n\ndef f(x):\n    pass\ndef g(): pass' → "f"
# 예: sh $'a() {' → ""
# 이름을 적은 표식은 그 이름을, 이름 없는 표식은 그 뒤 처음 나오는 함수를 선언한다. 표식 뒤 함수가 나오기 전에 다른 코드 줄이
# 끼면(주석 · 빈 줄 · 장식(@) 줄이 아닌 줄) 그 표식은 버린다.
scv_pd_declared() {
  local lang="${1:-}" text="${2:-}" line t n pending=0 out="" re_mark='@(pure|deterministic|effect)([[:space:]]+([A-Za-z_$][A-Za-z0-9_$:.-]*))?'
  while IFS= read -r line || [[ -n "$line" ]]; do
    t="${line#"${line%%[![:space:]]*}"}"
    case "$t" in
      '#'*|'//'*|'/*'*|'*'*|'--'*|';'*|"'"*)
        if [[ "$t" =~ $re_mark ]]; then
          if [[ -n "${BASH_REMATCH[3]}" && "${BASH_REMATCH[3]}" != "*/" ]]; then out="${out:+$out$'\n'}${BASH_REMATCH[3]}"; pending=0
          else pending=1; fi
        fi
        continue ;;
      ''|'@'*) continue ;;
    esac
    n="$(scv_pd_line_function "$lang" "$line")"
    if (( pending )) && [[ -n "$n" ]]; then out="${out:+$out$'\n'}$n"; fi
    pending=0
  done <<< "$text"
  printf '%s' "$out"
}

# @pure
# 역할: 편집 전에는 없던, 편집으로 새로 선언이 빠진 함수 이름들을 낸다(없으면 빈 값 — 통과)
# 종류: 판정/gate
# 예: "old" $'old\nnew' → "new"
# 예: $'old\nnew' "old" → ""
# 예: "" "" → ""
# <편집 전 빠진 이름들> <편집 뒤 빠진 이름들> → 새로 빠진 이름들. 옛 함수만 남은 파일의 다른 편집은 막지 않는다(기준선).
scv_pd_write_verdict() {
  scv_rc_allowed_out "${2:-}" "${1:-}"
}
