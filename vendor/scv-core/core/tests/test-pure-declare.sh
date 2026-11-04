#!/usr/bin/env bash
# test-pure-declare.sh — 모든 함수에 순수 · 부수효과 선언(계획 20261104-wookiya1364-pure-declare-081 T1–T5).
set -euo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$CORE/template/hooks/guard.sh"; PD="$CORE/scripts/pure-declare.sh"
# shellcheck source=../scripts/lib/pure-declare.sh
source "$CORE/scripts/lib/pure-declare.sh"
fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-puredecl.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
export SCV_GUARD_STATE="$WORK/guard-state"

# T1 — 언어별 이름 있는 함수 찾기
sh_src=$'a() {\n  :\n}\nfunction b {\n  :\n}\nc_d::e() { :; }'
js_src=$'export async function load(id) {}\nconst pick = (a, b) => a\nexport const f2 = async (x: number): Promise<void> => {}\nlet g = function () {}\nfunction* gen() {}\nreturn fn(x)'
py_src=$'def f(x):\n    pass\nclass A:\n    async def _m(self):\n        pass'
go_src=$'func Run() error {\n}\nfunc (s *S) Stop() {\n}\nfunc Map[T any](x T) T {'
r1="$(scv_pd_functions sh "$sh_src")"; r2="$(scv_pd_functions js "$js_src")"; r3="$(scv_pd_functions py "$py_src")"; r4="$(scv_pd_functions go "$go_src")"
[[ "$r1" == $'a\nb\nc_d::e' && "$r2" == $'load\npick\nf2\ng\ngen' && "$r3" == $'f\n_m' && "$r4" == $'Run\nStop\nMap' ]] \
  && ok "T1 함수 찾기(sh · js/ts · py · go)" || bad "T1 [$r1] [$r2] [$r3] [$r4]"

new_repo() {  # <이름> [설정 json] → 저장소
  local d="$WORK/$1"; mkdir -p "$d/scv/archive" "$d/src"; (cd "$d" && git init -q)
  printf '%s\n' "${2:-{\}}" > "$d/scv/scv_settings.json"
  printf '// @pure add\n// 역할: 두 수를 더한다\n// 종류: 세기\n// 예: 1 2 → 3\nexport function add(a, b) { return a + b }\n' > "$d/src/m.js"
  printf 'function old_one() { return 1 }\n' > "$d/src/legacy.js"
  printf '%s' "$d"
}
gw() {  # <저장소> <tool_input json> [에이전트] → 가드 stdout
  (cd "$1" && jq -cn --arg c "$1" --argjson ti "$2" --arg ag "${3:-}" '{session_id:"s1",cwd:$c,tool_name:"Edit",tool_input:$ti} + (if $ag == "" then {} else {agent_id:$ag} end)' \
     | SCV_GUARD_MODE=gate-write SCV_GUARD_SCRIPTS="$CORE/scripts" SCV_GUARD_RULE_B=off bash "$GUARD" 2>/dev/null)
}
denied() { [[ "$1" == *'"permissionDecision":"deny"'* ]]; }

# T2 — 선언 없는 새 함수(Edit · Write · 새 파일) 거절, 이유에 이름
R="$(new_repo t2)"
o1="$(gw "$R" '{"file_path":"src/m.js","old_string":"export function add","new_string":"function helper(x) { return x }\nexport function add"}')"
o2="$(gw "$R" '{"file_path":"src/n.ts","content":"export const pick = (a: number) => a\n"}')"
o3="$(gw "$R" '{"file_path":"src/s.py","content":"def run():\n    pass\n"}')"
denied "$o1" && [[ "$o1" == *helper* ]] && denied "$o2" && [[ "$o2" == *pick* ]] && denied "$o3" \
  && ok "T2 선언 없는 새 함수 거절(Edit · 새 ts · 새 py), 이유에 이름" || bad "T2 [$o1] [$o2] [$o3]"

# T3 — 선언을 단 편집은 통과(@pure 이름 · 이름 없는 @effect)
o1="$(gw "$R" '{"file_path":"src/m.js","old_string":"export function add","new_string":"// @effect helper\n// 이유: 로그를 남긴다\nfunction helper(x) { return x }\nexport function add"}')"
o2="$(gw "$R" '{"file_path":"src/n.py","content":"# @pure\n# 역할: 그대로 돌려준다\n# 종류: 다듬기\n# 예: 1 → 1\ndef same(x):\n    return x\n"}')"
[[ -z "$o1$o2" ]] && ok "T3 @effect · @pure 를 단 함수는 통과" || bad "T3 [$o1] [$o2]"

# T4 — 옛 함수만 있는 파일의 다른 편집 · 시험 폴더 · 스위치 off · 하위 에이전트는 통과
p=0
[[ -z "$(gw "$R" '{"file_path":"src/legacy.js","old_string":"return 1","new_string":"return 2"}')" ]] && p=$((p + 1))
[[ -z "$(gw "$R" '{"file_path":"tests/x.test.js","content":"function t() {}\n"}')" ]] && p=$((p + 1))
R2="$(new_repo t4b '{"SCV_PURE_DECLARE":"off"}')"; [[ -z "$(gw "$R2" '{"file_path":"src/q.js","content":"function q() {}\n"}')" ]] && p=$((p + 1))
[[ "$p" == 3 ]] && ok "T4 옛 함수 파일 · 시험 · 스위치 off 는 통과 3/3" || bad "T4 $p/3"
o="$(gw "$R" '{"file_path":"src/q.js","content":"function q() {}\n"}' a1)"
denied "$o" && ok "T4 하위 에이전트가 쓴 선언 없는 함수도 거절" || bad "T4b [$o]"

# T5 — 목록 검사 기준선: 늘면 실패, 줄면 기준선 내림
R="$(new_repo t5)"; (cd "$R" && git add -A >/dev/null)   # 추적 파일만 보면 된다 — 커밋은 하지 않는다(CI 에는 작성자 정보가 없다)
B="$WORK/baseline"; echo 1 > "$B"
c1=0; (cd "$R" && bash "$PD" baseline check --baseline "$B" --project >/dev/null 2>&1) || c1=$?
printf 'function more() {}\n' > "$R/src/more.js"; (cd "$R" && git add -A >/dev/null)
c2=0; (cd "$R" && bash "$PD" baseline check --baseline "$B" --project >/dev/null 2>&1) || c2=$?
rm "$R/src/more.js" "$R/src/legacy.js"; (cd "$R" && git add -A >/dev/null)
(cd "$R" && bash "$PD" baseline update --baseline "$B" --project >/dev/null 2>&1)
[[ "$c1" == 0 && "$c2" == 1 && "$(cat "$B")" == 0 ]] && ok "T5 기준선: 같으면 통과 · 늘면 실패 · 줄면 내림(1 → 0)" || bad "T5 c1=$c1 c2=$c2 base=$(cat "$B")"

exit "$fail"
