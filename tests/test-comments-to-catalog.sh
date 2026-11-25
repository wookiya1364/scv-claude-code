#!/usr/bin/env bash
# test-comments-to-catalog.sh — 코드 주석을 없애고 순수 함수 사전에만 (계획 20261122-wookiya1364-comments-to-catalog · TESTS.md T1 ~ T8, 계획 comments-strip-safety T9 ~ T12).
#
# 사전이 원본인 프로젝트(사전 폴더의 SOURCE)에서 사전 검사 · 선언 검사 · 쓰기 전 안전장치가 사전을 보는지, 옮기기가 잃는 것 없이
# 주석을 사전으로 옮기고 코드 뜻을 바꾸지 않는지, 설정을 켠 프로젝트가 다음 사람 턴에 한 번 옮기는지, 끈 프로젝트는 그대로인지 본다.
set -uo pipefail

CORE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CC="$CORE/scripts/code-comments.py"; CM="$CORE/scripts/comments-migrate.sh"; PC="$CORE/scripts/pure-catalog.sh"; PD="$CORE/scripts/pure-declare.sh"
command -v python3 >/dev/null 2>&1 || { echo "python3 없음 — 이 검사는 python3 가 필요하다" >&2; exit 1; }
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
unset SCV_CATALOG_SOURCE SCV_JOURNAL_DIR 2>/dev/null || true
fail=0
ok() { echo "ok $1"; }
bad() { echo "✖ $1" >&2; fail=1; }

DEFAULT_SETTINGS='{"SCV_LANG":"korean"}'   # 기본값을 변수로 둔다 — 옛 셸(3.2)은 ${2:-{…\}} 안의 닫는 괄호 앞 역슬래시를 글자로 남긴다
mkrepo() {  # <이름> [설정 JSON] → 저장소 경로 (sh · ts · rs · py 함수 넷, 표식 · 설명 · 도구 표시 주석이 섞임)
  local d="$WORK/$1"; mkdir -p "$d/scv/raw" "$d/src"
  ( cd "$d" && git init -q . && git config user.email t@t && git config user.name t
    printf '%s\n' "${2:-$DEFAULT_SETTINGS}" > scv/scv_settings.json
    printf '%s\n' '#!/usr/bin/env bash' '# shellcheck disable=SC2034' '# @pure' '# 역할: 센다' '# 종류: 세기' '# 예: "ab" → "2"' \
      'cnt() { printf "%s" "${#1}"; }   # 길이' '# 메모: 이건 설명' 'x="a # b"' 'cat <<EOF' '# 여기 문서는 글' 'EOF' > src/a.sh
    printf '%s\n' '// @pure add' '// 역할: 더한다' '// 종류: 세기' '// 예: add(1, 2) → 3' \
      'export const add = (a: number, b: number) => a + b; // 끝' 'const url = "http://x"; const re = /a\/\/b/;' > src/b.ts
    printf '%s\n' '/// @pure grade 역할: 등급 종류: 고르기 예: grade(4) → 1' 'pub fn grade(g: u8) -> u8 {' '    // 기본 덱은 8장' \
      '    let s = r#"a // b"#;' '    if g > 3 { 1 } else { 0 }' '}' > src/c.rs
    printf '%s\n' '# @effect save' '# 이유: 파일을 쓴다' 'def save(p):' '    open(p, "w").write("# not comment")  # 쓰기' > src/d.py
    git add -A && git commit -qm init )
  printf '%s' "$d"
}
code_text() { cat "$1"/src/a.sh "$1"/src/b.ts "$1"/src/c.rs "$1"/src/d.py; }

# ---------- T5 — 옮기기: 잃는 것 없이, 코드 뜻 그대로 ----------
R="$(mkrepo t5)"
OUT="$(cd "$R" && bash "$CM" run)"
left="$(cd "$R" && bash "$CM" files | python3 -I "$CC" count-stdin | sed -n 's/^TOTAL\t//p')"
cat="$R/scv/core/catalog/pure"
n_pure="$(grep -h '^### ' "$cat"/count.md "$cat"/select.md 2>/dev/null | wc -l | tr -d ' ')"
keep_ok=1
grep -qF 'x="a # b"' "$R/src/a.sh" && grep -qF '# 여기 문서는 글' "$R/src/a.sh" && grep -qF '"http://x"' "$R/src/b.ts" \
  && grep -qF '/a\/\/b/' "$R/src/b.ts" && grep -qF 'r#"a // b"#' "$R/src/c.rs" && grep -qF '"# not comment"' "$R/src/d.py" || keep_ok=0
cnt_ok="$(cd "$R" && bash -c 'source src/a.sh >/dev/null; cnt abc')"
head1="$(head -1 "$R/src/a.sh")"
if [[ "$head1" == '#!/usr/bin/env bash' && "$left" == 0 && "$n_pure" == 3 && $keep_ok == 1 && "$cnt_ok" == 3 && -f "$cat/SOURCE" ]] \
   && grep -q '^### save' "$cat/effects.md" && grep -qF '기본 덱은 8장' "$cat/notes.md"; then
  ok "T5 주석 0줄(첫 줄 #! 는 남김 — 지우면 직접 실행이 깨짐) · 순수 3(러스트 한 줄 표식 포함) · 부수효과 · 메모로 옮김 · 문자열/정규식/여기 문서는 그대로 · 함수 동작 같음"
else bad "T5 남은 주석=$left 순수=$n_pure 보존=$keep_ok cnt=$cnt_ok out=[$OUT]"; fi

# ---------- T1 — 사전이 원본: 코드에 주석이 없어도 사전 검사 통과, 지운 함수는 낡음 ----------
c1="$(cd "$R" && bash "$PC" check --project . 2>&1)"; r1=$?
( cd "$R" && sed -i.bak 's/pub fn grade(/pub fn grade2(/' src/c.rs && rm -f src/c.rs.bak )
c2="$(cd "$R" && bash "$PC" check --project . 2>&1)"; r2=$?
( cd "$R" && sed -i.bak 's/pub fn grade2(/pub fn grade(/' src/c.rs && rm -f src/c.rs.bak )
if [[ $r1 == 0 && $r2 != 0 && "$c2" == *"사전 항목의 함수가 코드에 없다: grade "* ]]; then ok "T1 원본 사전 검사 통과 · 이름이 바뀐 함수는 낡음으로 잡힘"
else bad "T1 r1=$r1 r2=$r2 [$c1] [$c2]"; fi

# ---------- T2 — 순수 검사(예시 실행)가 사전 항목으로 함수를 찾음 ----------
( cd "$R" && sed -i.bak 's/printf "%s" "${#1}"/printf "%s" "x${#1}"/' src/a.sh && rm -f src/a.sh.bak )
c3="$(cd "$R" && bash "$PC" check --project . 2>&1)"; r3=$?
( cd "$R" && sed -i.bak 's/printf "%s" "x${#1}"/printf "%s" "${#1}"/' src/a.sh && rm -f src/a.sh.bak )
if [[ $r3 != 0 && "$c3" == *"cnt 예시가 틀렸다"* ]]; then ok "T2 주석 없는 함수도 사전 항목의 예시로 실제 실행해 어긋남을 잡음"
else bad "T2 r3=$r3 [$c3]"; fi

# ---------- T3 — 함수 선언 안전장치: 사전에 없는 새 함수는 거절, 적은 뒤에는 허용 ----------
printf 'cnt() { :; }\nnewf() { :; }\n' > "$WORK/after.sh"
g1="$(cd "$R" && bash "$PD" gate --file src/a.sh --before src/a.sh --after "$WORK/after.sh")"
printf '\n### newf\n- 역할: 아무것도 안 한다\n- 위치: src/a.sh · @pure · sh\n- 예: `"" → ""`\n' >> "$cat/count.md"
g2="$(cd "$R" && bash "$PD" gate --file src/a.sh --before src/a.sh --after "$WORK/after.sh")"
if [[ "$g1" == *"사전에 없는 함수가 생긴다: newf"* && -z "$g2" ]]; then ok "T3 사전에 없는 새 함수는 거절 · 사전에 적은 뒤에는 허용"
else bad "T3 [$g1] [$g2]"; fi

# ---------- T4 — 주석 막기: 쓰기 전 안전장치가 주석 줄을 넣는 편집을 거절, 문자열 안은 허용 ----------
guard_edit() {  # <저장소> <파일> <새 글> → 안전장치 출력
  ( cd "$1" && jq -cn --arg c "$1" --arg f "$1/$2" --arg t "$3" '{session_id:"s1",cwd:$c,tool_name:"Write",tool_input:{file_path:$f,content:$t}}' \
      | SCV_GUARD_MODE=gate-write SCV_GUARD_SCRIPTS="$CORE/scripts" SCV_GUARD_STATE="$WORK/gs" SCV_GUARD_RULE_B=off bash "$CORE/template/hooks/guard.sh" 2>/dev/null )
}
w1="$(guard_edit "$R" src/b.ts $'export const add = (a: number, b: number) => a + b;\n// 새 주석\n')"
w2="$(guard_edit "$R" src/b.ts $'export const add = (a: number, b: number) => a + b;\nconst s = "// 글";\n')"
w3="$(guard_edit "$R" src/d.py $'def save(p):\n    pass  # 새 주석\n')"
if [[ "$w1" == *"주석 1줄이 생긴다"* && "$w2" != *"주석"* && "$w3" == *"주석 1줄이 생긴다"* ]]; then ok "T4 주석 줄을 넣는 편집은 거절(ts · py) · 문자열 안 // 는 허용"
else bad "T4 [${w1:0:120}] [${w2:0:120}] [${w3:0:120}]"; fi

# ---------- T6 — 기존 프로젝트 자동 옮기기: 설정을 켜면 다음 사람 턴에 한 번 ----------
R6="$(mkrepo t6 '{"SCV_LANG":"korean","SCV_CATALOG_SOURCE":"on"}')"
hook() { ( cd "$1" && printf '{"prompt":"안녕","session_id":"s1"}' | CLAUDE_PLUGIN_ROOT="$CORE" SCV_GUARD_STATE="$WORK/gs6" bash "$CORE/template/hooks/on-user-prompt.sh" 2>/dev/null ); }
h1="$(hook "$R6")"; h2="$(hook "$R6")"
st="$(cd "$R6" && git status --porcelain | grep -c '^ M src/')"; cm="$(cd "$R6" && git log --oneline | wc -l | tr -d ' ')"
if [[ "$h1" == *"[SCV 주석 옮김] 코드 파일 4개"* && "$h2" != *"[SCV 주석 옮김]"* && "$st" == 4 && "$cm" == 1 ]]; then
  ok "T6 설정을 켠 첫 사람 턴에 한 번 옮기고 보고 · 둘째 턴은 아무것도 안 함 · 커밋하지 않음"
else bad "T6 첫=$(grep -c '주석 옮김' <<<"$h1") 둘째=$(grep -c '주석 옮김' <<<"$h2") 바뀐 파일=$st 커밋=$cm"; fi

# ---------- T7 — 기본값 on: 키가 없으면 옮김 · 적힌 off 는 그대로(옮기지 않음 · 주석 넣는 편집도 막지 않음) ----------
R7="$(mkrepo t7 '{"SCV_LANG":"korean","SCV_CATALOG_SOURCE":"off"}')"
o1="$(hook "$R7")"
d7="$(cd "$R7" && git status --porcelain | grep -c '^ M src/')"
w7="$(guard_edit "$R7" src/b.ts $'export const add = (a: number, b: number) => a + b;\n// 새 주석\n')"
R7b="$(mkrepo t7b)"
o7b="$(hook "$R7b")"
if [[ "$d7" == 0 && ! -e "$R7/scv/core/catalog/pure/SOURCE" && "$o1" != *"주석 옮김"* && "$w7" != *"SCV 주석 없음"* \
   && "$o7b" == *"[SCV 주석 옮김]"* && -f "$R7b/scv/core/catalog/pure/SOURCE" ]]; then
  ok "T7 키 없음 → 기본 on 으로 옮김 · 적힌 off → 옮기지 않음 · 원본 표시 없음 · 주석 넣는 편집도 막지 않음"
else bad "T7 off바뀐=$d7 off표시=$([[ -e "$R7/scv/core/catalog/pure/SOURCE" ]] && echo 있음) [${w7:0:80}] 키없음=$(grep -c '주석 옮김' <<<"$o7b")"; fi

# ---------- T8 — catalog-source 명령: 켜면 바로 옮김 · 끄면 주석 막기만 풂(사전은 원본) · 다시 켜면 막기가 돌아옴 ----------
CS="$CORE/scripts/catalog-source.sh"
R8="$(mkrepo t8 '{"SCV_LANG":"korean","SCV_CATALOG_SOURCE":"off"}')"
k1="$(cd "$R8" && bash "$CS")"
left8="$(cd "$R8" && bash "$CM" files | python3 -I "$CC" count-stdin | sed -n 's/^TOTAL\t//p')"
k2="$(cd "$R8" && bash "$CS" off)"
e_off="$(guard_edit "$R8" src/b.ts $'export const add = (a: number, b: number) => a + b;\n// 새 주석\n')"
k3="$(cd "$R8" && bash "$CS" on)"
e_on="$(guard_edit "$R8" src/b.ts $'export const add = (a: number, b: number) => a + b;\n// 새 주석\n')"
( cd "$R8" && bash "$CS" maybe >/dev/null 2>&1 ); r8=$?
if [[ "$k1" == *"CATALOG_SOURCE: off -> on"* && "$k1" == *"MIGRATED: now"* && "$left8" == 0 && "$k2" == *"on -> off"* \
   && "$e_off" != *"SCV 주석 없음"* && "$k3" == *"MIGRATED: already"* && "$e_on" == *"SCV 주석 없음"* && $r8 == 2 \
   && -f "$R8/scv/core/catalog/pure/SOURCE" ]]; then
  ok "T8 catalog-source: 뒤집기로 켜면 바로 옮김 · 끄면 주석 허용(사전은 원본 그대로) · 다시 켜면 막기 · 잘못된 인자 exit 2"
else bad "T8 [$k1] 남은=$left8 [$k2] off편집=[${e_off:0:60}] [$k3] on편집=[${e_on:0:60}] r=$r8"; fi

# ---------- T9 — 겹친 따옴표 · 치환 · 이스케이프: 문자열 안 # 는 남기고 진짜 주석만 (계획 comments-strip-safety) ----------
printf '%s\n' 'x="$(echo ab | tr -d '"'"'"[:space:]'"'"')"' "echo '(### b)'" 'y="${v:-"q"}" # c' 'z=$(echo "a)b" # in' ')' \
  'if true; then' '  echo a\ #b' 'fi' 'w=`echo "#q"` # d' > "$WORK/t9.sh"
s9="$(python3 -I "$CC" strip "$WORK/t9.sh")"
if grep -qF "echo '(### b)'" <<<"$s9" && grep -qF 'echo a\ #b' <<<"$s9" && grep -qF '"#q"' <<<"$s9" \
   && ! grep -qE '# (c|in|d)$' <<<"$s9" && bash -n <(printf '%s\n' "$s9"); then
  ok "T9 큰따옴표 안 \$( ) 속 따옴표 · \${ } 안 따옴표 · 이스케이프된 공백 뒤 # 는 남김 · \$( ) · 역따옴표 뒤 주석만 지움 · 문법 그대로"
else bad "T9 [$s9]"; fi

# ---------- T10 — 지운 뒤 문법이 깨지는 파일은 건드리지 않음 ----------
R10="$(mkrepo t10)"; before10="$(cat "$R10/src/a.sh")"
( cd "$R10" && bash "$CM" files > "$WORK/l10" )
o10="$(python3 -I - "$CC" "$R10" "$WORK/l10" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location('cc', sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
orig = m.strip_comments
m.strip_comments = lambda t, l: (orig(t, l) + '\nfi\n') if l == 'sh' else orig(t, l)
m.main(['migrate', '--root', sys.argv[2], '--list', sys.argv[3], '--catalog', sys.argv[2] + '/scv/core/catalog/pure', '--entries-out', sys.argv[2] + '/e.tsv', '--write'])
PY
)"
if [[ "$(cat "$R10/src/a.sh")" == "$before10" && "$o10" == *"skipped=1"* ]] && ! grep -q '^# @pure add' "$R10/src/b.ts"; then
  ok "T10 지운 뒤 bash -n 이 깨지는 셸 파일은 그대로 두고 skipped=1 로 보고 · 다른 파일은 옮김"
else bad "T10 [$o10] a.sh 바뀜=$([[ "$(cat "$R10/src/a.sh")" == "$before10" ]] || echo 예)"; fi

# ---------- T11 — 사전 쓰기가 실패하면 코드 · 사전을 옮기기 전으로 되돌림(커밋 안 한 편집 포함) ----------
R11="$(mkrepo t11)"; printf 'echo dirty  # 편집 중\n' >> "$R11/src/a.sh"
snap11="$(cd "$R11" && cat src/* | shasum | cut -c1-12)"
BR="$WORK/broken"; cp -R "$CORE/scripts" "$BR"
printf '%s\n' '[[ "${1:-}" == import ]] && exit 1' "exec bash \"$CORE/scripts/pure-catalog.sh\" \"\$@\"" > "$BR/pure-catalog.sh"
o11="$(cd "$R11" && bash "$BR/comments-migrate.sh" run 2>&1)"; r11=$?
snap11b="$(cd "$R11" && cat src/* | shasum | cut -c1-12)"
if [[ $r11 == 1 && "$snap11" == "$snap11b" && ! -e "$R11/scv/core/catalog/pure/SOURCE" && ! -e "$R11/scv/core/catalog/pure/notes.md" && "$o11" == *"되돌림"* ]]; then
  ok "T11 사전 쓰기 실패 → exit 1 · 코드 파일 바이트까지 그대로(커밋 안 한 편집 포함) · 사전 표시 없음"
else bad "T11 r=$r11 같음=$([[ "$snap11" == "$snap11b" ]] && echo 예) [$o11]"; fi

# ---------- T12 — 예시 속 표식 · 칸 이름은 글 · 옮기기 전 항목이 하나라도 빠지면 멈춤 ----------
R12="$(mkrepo t12)"
printf '%s\n' '# @pure f2' '# 역할: 고른다' '# 종류: 고르기' "# 예: \$'# @pure g\\n# 종류: 뭐' → \"g\"" 'f2() { :; }' >> "$R12/src/a.sh"
( cd "$R12" && git add -A && git commit -qm t12 )
o12="$(cd "$R12" && bash "$CM" run 2>&1)"
k12="$(grep -A3 '^### f2$' "$R12"/scv/core/catalog/pure/select.md 2>/dev/null | grep -c '고른다')"
g12="$(grep -rc '^### g$' "$R12"/scv/core/catalog/pure/*.md 2>/dev/null | awk -F: '{s+=$2} END {print s+0}')"
R12b="$(mkrepo t12b)"; snap12="$(cd "$R12b" && cat src/* | shasum | cut -c1-12)"
BR2="$WORK/broken2/scripts"; mkdir -p "$WORK/broken2"; cp -R "$CORE/." "$WORK/broken2/"
printf '%s\n' 'import subprocess, sys' "r = subprocess.run([sys.executable, '-I', '$CORE/scripts/code-comments.py'] + sys.argv[1:]).returncode" \
  "sys.argv.count('--write-entries-only') and open(sys.argv[sys.argv.index('--entries-out') + 1], 'w').write('')" 'sys.exit(r)' > "$BR2/code-comments.py"
o12b="$(cd "$R12b" && bash "$BR2/comments-migrate.sh" run 2>&1)"; r12b=$?
snap12b="$(cd "$R12b" && cat src/* | shasum | cut -c1-12)"
if [[ "$k12" == 1 && "$g12" == 0 && $r12b == 1 && "$snap12" == "$snap12b" && "$o12b" == *"옮긴 결과에 없다"* ]]; then
  ok "T12 예시 속 @pure · 종류: 는 글로 읽음(가짜 항목 없음 · 종류 그대로) · 옮기기 전 항목이 빠지면 코드 그대로 두고 멈춤"
else bad "T12 f2역할=$k12 가짜g=$g12 r=$r12b 같음=$([[ "$snap12" == "$snap12b" ]] && echo 예) [$o12] [$o12b]"; fi

exit "$fail"
