#!/usr/bin/env bash
# test-pr-base.sh — PR 도구가 저장소 브랜치 규칙대로 PR 을 열고(에픽 > 설정 SCV_PR_BASE > origin 기본 브랜치 > main),
# SCV 기록은 보관 폴더와 같은 커밋에 올리며, 그 밖에 커밋 안 된 변경이 있으면 아무것도 하지 않고 멈추는지 본다.
#
# 계획: scv/promote/20261001-wookiya1364-auto-turns-pr-base-fixes/TESTS.md (T8~T10 — 이 파일의 T1~T4; 독립 검토 결함 — T5)
#
# Run: bash core/tests/test-pr-base.sh
set -uo pipefail

HERE="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
CORE="$( cd "$HERE/.." && pwd )"
PRH="$CORE/scripts/pr-helper.sh"
FLOW="$CORE/scripts/lib/pr-flow.sh"

PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
N=0; BAD=0
eqc() { N=$((N + 1)); [[ "$2" == "$3" ]] || { BAD=$((BAD + 1)); echo "      ✖ $1: expected [$2] got [$3]"; }; }
for f in "$PRH" "$FLOW"; do [[ -f "$f" ]] || { echo "✖ 없음: $f"; exit 1; }; done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-prb.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
SLUG="20261001-tester-base-feature"

# 가짜 gh: 받은 인자를 줄마다 기록한다. pr list 는 빈 목록(생성 경로), pr create 는 URL.
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "${SCV_FAKE_GH_LOG:-/dev/null}"
case "$1 ${2:-}" in
  "pr list")   ;;
  "pr create") echo "https://example.invalid/pull/7" ;;
  *)           exit 0 ;;
esac
FAKE
chmod +x "$WORK/bin/gh"

make_proj() {  # <이름> [에픽] → 기능 브랜치의 저장소. 보관 폴더는 커밋 전(작업 흐름에서 방금 보관한 상태)이다.
  local P="$WORK/prj-$1" epic="${2:-}"
  mkdir -p "$P/src" "$P/scv/journal" "$P/scv/archive/$SLUG"
  ( cd "$P" && git init -q && git config user.name t && git config user.email t@example.invalid \
    && git remote add origin https://github.com/example/repo.git )
  printf 'app\n' > "$P/src/app.js"
  printf '# journal\n' > "$P/scv/journal/20261001-tester.md"
  ( cd "$P" && git add -A && git commit -qm init && git checkout -q -b feat/base )
  {
    printf -- '---\ntitle: base feature\nslug: %s\nauthor: tester\ncreated_at: 2026-10-01\nstatus: done\nkind: feature\nlang: english\n' "$SLUG"
    [[ -n "$epic" ]] && printf 'epic: %s\n' "$epic"
    printf -- '---\n\n# base\n\n## Summary\n\nb.\n'
  } > "$P/scv/archive/$SLUG/PLAN.md"
  printf '# Test Plan\n\n## How to run\n\n```bash\ntrue\n```\n\n## Pass criteria\n\n- exit 0\n' > "$P/scv/archive/$SLUG/TESTS.md"
  printf '%s' "$P"
}
origin_head() {  # <저장소> <브랜치> — origin 의 기본 브랜치를 정한다(원격 없이)
  ( cd "$1" && git update-ref "refs/remotes/origin/$2" HEAD && git symbolic-ref refs/remotes/origin/HEAD "refs/remotes/origin/$2" )
}
run_prh() {  # <저장소> [인자…] → 종료 코드. 출력은 $WORK/out · $WORK/err, gh 인자는 $WORK/gh.log
  local P="$1"; shift
  : > "$WORK/gh.log"
  ( cd "$P" && PATH="$WORK/bin:$PATH" SCV_FAKE_GH_LOG="$WORK/gh.log" bash "$PRH" "$SLUG" --no-push --no-rerun "$@" ) \
    > "$WORK/out" 2> "$WORK/err"
  echo $?
}
created_base() { grep '^pr create' "$WORK/gh.log" 2>/dev/null | head -1 | sed -E 's/.*--base ([^ ]+).*/\1/'; }

echo "T1. 대상 브랜치 · 커밋 범위 — 순수부"
N=0; BAD=0
T1OUT="$(bash -c '
  source "'"$FLOW"'"
  e() { printf "%s\n" "$1=$(printf "%s" "$2" | tr "\n" "|")"; }
  e b1 "$(scv_pr_base_branch pay-v2 develop trunk)"
  e b2 "$(scv_pr_base_branch "" develop trunk)"
  e b3 "$(scv_pr_base_branch "" "" trunk)"
  e b4 "$(scv_pr_base_branch "" "" "")"
  e b5 "$(scv_pr_base_branch "" "  \"develop\" " "")"
  e b6 "$(scv_pr_base_branch "" " " "trunk")"
  A="$(printf "scv/\ntest-results/\n.scv-pr-artifacts/\n")"
  # 상태 기록 = git status --porcelain -z 의 NUL 을 줄바꿈으로 바꾼 것 — 경로 그대로, R/C 는 다음 줄이 원래 경로.
  e s1 "$(scv_pr_stray_changes "$(printf " M scv/journal/a.md\n?? scv/archive/x/\n?? test-results/r/shot.png\n?? .scv-pr-artifacts/x/a.png\n")" "$A")"
  e s2 "$(scv_pr_stray_changes "$(printf " M src/app.js\n?? lib/new.js\n M scv/INDEX.tsv\n")" "$A")"
  e s3 "$(scv_pr_stray_changes "$(printf "R  scv/moved.md\nsrc/old.js\nR  src/b.js\nscv/a.md\n")" "$A")"
  e s4 "$(scv_pr_stray_changes "$(printf "?? src/with space.js\n?? scv/with space.md\n")" "$A")"
  e s4k "$(scv_pr_stray_changes "$(printf " M 앱/scv/j.md\n?? 앱/src/a.ts\n")" "$(printf "앱/scv/\n")")"
  e s4a "$(scv_pr_stray_changes "$(printf "?? scv/raw/v1 -> v2 migration.md\n")" "$A")"
  e s5 "$(scv_pr_stray_changes "$(printf " M scvx/a.md\n M scv\n")" "$A")"
  e s6 "$(scv_pr_stray_changes "$(printf " M FE/scv/j.md\n M FE/src/a.ts\n")" "$(printf "FE/scv/\n")")"
  e s7 "$(scv_pr_stray_changes "" "$A")"
  e s8 "$(scv_pr_stray_changes "$(printf " M README.md\n")" "$(printf "README.md\n")")"
  e s9 "$(scv_pr_stray_changes "$(printf "C  scv/copy.md\nscv/orig.md\n M src/x.js\n")" "$A")"
')"
g() { printf '%s\n' "$T1OUT" | grep -m1 "^$1=" | sed "s/^$1=//"; }
eqc "epic wins over the setting" "epic/pay-v2" "$(g b1)"
eqc "setting wins over the origin default" "develop" "$(g b2)"
eqc "origin default when no setting" "trunk" "$(g b3)"
eqc "main when nothing is known" "main" "$(g b4)"
eqc "setting: spaces and quotes stripped" "develop" "$(g b5)"
eqc "setting: blank is no setting" "trunk" "$(g b6)"
eqc "SCV records, archive, results, artifacts are allowed" "" "$(g s1)"
eqc "code and untracked files outside are listed" "src/app.js|lib/new.js" "$(g s2)"
eqc "renames: both sides judged (code moved into scv is outside)" "src/old.js|src/b.js" "$(g s3)"
eqc "spaces verbatim" "src/with space.js" "$(g s4)"
eqc "non-ASCII folder verbatim (no octal escapes)" "앱/src/a.ts" "$(g s4k)"
eqc "an arrow inside a file name is just a name" "" "$(g s4a)"
eqc "copy: original line consumed, next entry still parsed" "src/x.js" "$(g s9)"
eqc "folder prefix needs the slash (scvx/ is not scv/)" "scvx/a.md" "$(g s5)"
eqc "nested SCV folder" "FE/src/a.ts" "$(g s6)"
eqc "clean tree" "" "$(g s7)"
eqc "exact file entry" "" "$(g s8)"
if [[ $BAD -eq 0 ]]; then ok "OK [T1] $N/$N"; else fail "[T1] $((N - BAD))/$N"; fi

echo
echo "T2. PR 도구 실행 — 설정한 대상 브랜치로 연다(설정 없음 · 에픽은 지금과 같다)"
c=0
P="$(make_proj t2a)"; origin_head "$P" trunk
printf '{"SCV_PR_BASE": "develop"}\n' > "$P/scv/scv_settings.json"
rc="$(run_prh "$P")"
[[ "$rc" == 0 && "$(created_base)" == develop ]] && grep -q 'PR created: https://example.invalid/pull/7' "$WORK/out" && c=$((c + 1)) \
  || echo "      (1) setting develop: rc=$rc base=[$(created_base)] $(tail -3 "$WORK/err")"
P="$(make_proj t2b)"; origin_head "$P" trunk
rc="$(run_prh "$P")"
[[ "$rc" == 0 && "$(created_base)" == trunk ]] && c=$((c + 1)) || echo "      (2) no setting → origin default: rc=$rc base=[$(created_base)]"
P="$(make_proj t2c)"
rc="$(run_prh "$P")"
[[ "$rc" == 0 && "$(created_base)" == main ]] && c=$((c + 1)) || echo "      (3) nothing known → main: rc=$rc base=[$(created_base)]"
P="$(make_proj t2d pay-v2)"; origin_head "$P" trunk
printf '{"SCV_PR_BASE": "develop"}\n' > "$P/scv/scv_settings.json"
rc="$(run_prh "$P")"
[[ "$rc" == 0 && "$(created_base)" == epic/pay-v2 ]] && c=$((c + 1)) || echo "      (4) epic wins: rc=$rc base=[$(created_base)]"
P="$(make_proj t2e)"; origin_head "$P" trunk
printf '{"SCV_PR_BASE": "develop"}\n' > "$P/scv/scv_settings.json"
rc="$(run_prh "$P" --dry-run)"
[[ "$rc" == 0 ]] && grep -A1 '^=== PR base branch ===' "$WORK/out" | grep -qx develop && [[ ! -s "$WORK/gh.log" ]] && c=$((c + 1)) \
  || echo "      (5) dry-run shows the setting: rc=$rc $(grep -A1 'PR base branch' "$WORK/out")"
if [[ $c -eq 5 ]]; then ok "OK [T2] 5/5 base branch"; else fail "[T2] $c/5"; fi

echo
echo "T3. PR 커밋 범위 — SCV 기록은 보관 폴더와 같은 커밋에, 그 밖의 커밋 안 된 변경은 멈춘다"
c=0
# (a) 구현 파일 수정 + 새 파일 → exit 1, 목록 · 할 일, 새 커밋 · gh 호출 · 이동 없음
P="$(make_proj t3a)"; origin_head "$P" trunk
printf 'changed\n' >> "$P/src/app.js"; printf 'new\n' > "$P/src/new.js"
mkdir -p "$P/test-results/r"; printf 's' > "$P/test-results/r/$SLUG-shot.png"
before="$(cd "$P" && git rev-parse HEAD)"
rc="$(run_prh "$P")"
[[ "$rc" == 1 ]] && grep -q 'uncommitted changes outside the SCV records' "$WORK/err" && grep -qF 'src/app.js' "$WORK/err" \
  && grep -qF 'src/new.js' "$WORK/err" && grep -q 'Nothing was moved, committed, pushed or created' "$WORK/err" && c=$((c + 1)) \
  || echo "      (a1) stop with the list: rc=$rc $(head -5 "$WORK/err")"
[[ "$(cd "$P" && git rev-parse HEAD)" == "$before" && ! -s "$WORK/gh.log" && -f "$P/test-results/r/$SLUG-shot.png" && ! -d "$P/.scv-pr-artifacts" ]] \
  && c=$((c + 1)) || echo "      (a2) nothing may change: head moved, gh called or screenshot moved"
# (b) SCV 기록만 바뀜(작업 기록 수정 · 새 대화 · 보관 폴더) → 같은 커밋에 모두 들어가고 PR 이 열린다
P="$(make_proj t3b)"; origin_head "$P" trunk
printf 'turn\n' >> "$P/scv/journal/20261001-tester.md"; mkdir -p "$P/scv/conversations"; printf '# c\n' > "$P/scv/conversations/c1.md"
rc="$(run_prh "$P")"
files="$(cd "$P" && git show --name-only --format= HEAD)"
[[ "$rc" == 0 ]] && grep -qx "scv/archive/$SLUG/PLAN.md" <<<"$files" && grep -qx 'scv/journal/20261001-tester.md' <<<"$files" \
  && grep -qx 'scv/conversations/c1.md' <<<"$files" && [[ -z "$(cd "$P" && git status --porcelain scv)" ]] && c=$((c + 1)) \
  || echo "      (b) SCV records in the same commit: rc=$rc files=[$(tr '\n' ' ' <<<"$files")] $(tail -3 "$WORK/err")"
# (c) 결과 폴더만 있음 → 멈추지 않는다
P="$(make_proj t3c)"; origin_head "$P" trunk
mkdir -p "$P/test-results/other"; printf 'log\n' > "$P/test-results/other/run.log"
rc="$(run_prh "$P")"
[[ "$rc" == 0 ]] && grep -q 'PR created:' "$WORK/out" && c=$((c + 1)) || echo "      (c) results only must not stop: rc=$rc $(tail -3 "$WORK/err")"
# (d) --dry-run 은 (a) 에서도 멈추지 않고 경고만 — 아무것도 바꾸지 않는다
P="$(make_proj t3d)"; origin_head "$P" trunk
printf 'changed\n' >> "$P/src/app.js"
before="$(cd "$P" && git rev-parse HEAD)"
rc="$(run_prh "$P" --dry-run)"
[[ "$rc" == 0 ]] && grep -q '^=== WARNING: uncommitted changes outside the SCV records' "$WORK/out" && grep -qF 'src/app.js' "$WORK/out" \
  && [[ "$(cd "$P" && git rev-parse HEAD)" == "$before" && ! -s "$WORK/gh.log" ]] && c=$((c + 1)) \
  || echo "      (d) dry-run warns only: rc=$rc $(grep -A2 WARNING "$WORK/out")"
if [[ $c -eq 5 ]]; then ok "OK [T3] 5/5 commit scope"; else fail "[T3] $c/5"; fi

echo
echo "T5. 독립 검토가 찾은 경우 — 재실행 전 판정 · 경로 그대로 · 이름 바뀜 · 세션 파일 · 하위 모듈"
c=0
run_prh_rerun() {  # <저장소> → 종료 코드 — 재실행을 막지 않는다(--no-rerun 없이)
  : > "$WORK/gh.log"
  ( cd "$1" && PATH="$WORK/bin:$PATH" SCV_FAKE_GH_LOG="$WORK/gh.log" bash "$PRH" "$SLUG" --no-push ) > "$WORK/out" 2> "$WORK/err"
  echo $?
}
rerun_tests() { printf '# Test Plan\n\n## How to run\n\n```bash\nprintf x > build.out\n```\n\n## Pass criteria\n\n- exit 0\n' > "$1/scv/archive/$SLUG/TESTS.md"; }
# (1) 코드가 커밋 안 됐으면 검사 재실행 전에 멈춘다 — 재실행이 만드는 파일이 생기지 않고, 그 파일 때문에 멈추지도 않는다
P="$(make_proj t5a)"; origin_head "$P" trunk; rerun_tests "$P"
printf 'changed\n' >> "$P/src/app.js"
rc="$(run_prh_rerun "$P")"
[[ "$rc" == 1 && ! -e "$P/build.out" ]] && grep -qF 'src/app.js' "$WORK/err" && ! grep -qF 'build.out' "$WORK/err" && c=$((c + 1)) \
  || echo "      (1) stop before the re-run: rc=$rc build.out=$([[ -e "$P/build.out" ]] && echo made || echo none) $(head -3 "$WORK/err")"
# (2) 기록만 바뀐 깨끗한 트리 — 재실행이 저장소에 파일을 만들어도 PR 은 열린다(그 파일은 커밋에 들어가지 않는다)
P="$(make_proj t5b)"; origin_head "$P" trunk; rerun_tests "$P"
rc="$(run_prh_rerun "$P")"
[[ "$rc" == 0 ]] && grep -q 'PR created:' "$WORK/out" && ! (cd "$P" && git show --name-only --format= HEAD | grep -qx build.out) && c=$((c + 1)) \
  || echo "      (2) re-run output must not stop a clean run: rc=$rc $(tail -3 "$WORK/err")"
# (3) 한글 · 공백 이름의 SCV 기록 — 8진수로 감싼 경로를 "밖"으로 보던 결함. 추적 중인 폴더 안에 두어야 git 이 파일 경로를
#     그대로 보인다(새 폴더 전체가 추적 밖이면 폴더 이름만 나와 이 결함을 못 본다).
P="$(make_proj t5c)"; origin_head "$P" trunk
printf 'm\n' > "$P/scv/journal/첫 메모.md"
rc="$(run_prh "$P")"
[[ "$rc" == 0 ]] && (cd "$P" && git -c core.quotepath=off show --name-only --format= HEAD | grep -qF '첫 메모.md') && c=$((c + 1)) \
  || echo "      (3) non-ASCII SCV record must pass and be committed: rc=$rc $(head -3 "$WORK/err")"
# (4) 코드를 SCV 폴더로 옮긴 이름 바뀜(스테이징됨) — 지워지는 쪽이 밖이라 멈춘다(그대로 두면 커밋에 코드 삭제가 섞였다)
P="$(make_proj t5d)"; origin_head "$P" trunk
(cd "$P" && git mv src/app.js scv/moved.md)
before="$(cd "$P" && git rev-parse HEAD)"
rc="$(run_prh "$P")"
[[ "$rc" == 1 && "$(cd "$P" && git rev-parse HEAD)" == "$before" ]] && grep -qF 'src/app.js' "$WORK/err" && c=$((c + 1)) \
  || echo "      (4) staged rename out of the code must stop: rc=$rc $(head -3 "$WORK/err")"
# (5) 저널을 공유하는 프로젝트(무시 목록 없음) — 세션 표식 파일은 커밋에 들어가지 않는다
P="$(make_proj t5e)"; origin_head "$P" trunk
for f in .help-state .help-turn .help-rewrite .help-turn-auto; do printf 'x\n' > "$P/scv/journal/$f"; done
rc="$(run_prh "$P")"
files="$(cd "$P" && git show --name-only --format= HEAD)"
[[ "$rc" == 0 ]] && ! grep -q 'scv/journal/\.help-' <<<"$files" && grep -qx "scv/archive/$SLUG/PLAN.md" <<<"$files" && c=$((c + 1)) \
  || echo "      (5) session files must stay out of the commit: rc=$rc files=[$(tr '\n' ' ' <<<"$files")]"
# (6) 추적 안 된 파일만 있는 하위 모듈 — 커밋으로 풀 수 없으니 멈추지 않는다
SUBSRC="$WORK/subsrc"; mkdir -p "$SUBSRC"
(cd "$SUBSRC" && git init -q && git config user.name t && git config user.email t@example.invalid && printf 's\n' > s.txt && git add -A && git commit -qm s)
P="$(make_proj t5f)"; origin_head "$P" trunk
if (cd "$P" && git -c protocol.file.allow=always submodule add -q "$SUBSRC" vendor/sub >/dev/null 2>&1 && git commit -qm sub); then
  printf 'scratch\n' > "$P/vendor/sub/untracked.txt"
  rc="$(run_prh "$P")"
  [[ "$rc" == 0 ]] && grep -q 'PR created:' "$WORK/out" && c=$((c + 1)) || echo "      (6) untracked-only submodule must not stop: rc=$rc $(head -3 "$WORK/err")"
else
  echo "      · (6) 이 git 은 로컬 하위 모듈을 만들 수 없음 — 생략(통과로 셈)"; c=$((c + 1))
fi
# (7) 템플릿 무시 목록(저널 · 비밀 파일 무시)이 있는 보통 프로젝트 — git add 가 무시된 경로 때문에 1 로 끝나도 기록은 올라간다
P="$(make_proj t5g)"; origin_head "$P" trunk
printf 'scv/journal/\nscv/scv_settings.secret.json\n' > "$P/.gitignore"; (cd "$P" && git add .gitignore && git commit -qm ignore)
mkdir -p "$P/scv/conversations"; printf '# c\n' > "$P/scv/conversations/c7.md"; printf 'x\n' > "$P/scv/journal/.help-state"
rc="$(run_prh "$P")"
files="$(cd "$P" && git show --name-only --format= HEAD)"
[[ "$rc" == 0 ]] && grep -qx 'scv/conversations/c7.md' <<<"$files" && grep -qx "scv/archive/$SLUG/PLAN.md" <<<"$files" && c=$((c + 1)) \
  || echo "      (7) records must be committed even when git add reports ignored paths: rc=$rc files=[$(tr '\n' ' ' <<<"$files")]"
# (8) 무시되지 않은 비밀 설정 파일 — 커밋에 들어가지 않는다(마지막 방어선)
P="$(make_proj t5h)"; origin_head "$P" trunk
printf '{"SLACK_BOT_TOKEN": "xoxb-fixture"}\n' > "$P/scv/scv_settings.secret.json"
rc="$(run_prh "$P")"
files="$(cd "$P" && git show --name-only --format= HEAD)"
[[ "$rc" == 0 ]] && ! grep -q 'scv_settings.secret.json' <<<"$files" && c=$((c + 1)) \
  || echo "      (8) the secret settings file must stay out of the commit: rc=$rc files=[$(tr '\n' ' ' <<<"$files")]"
if [[ $c -eq 8 ]]; then ok "OK [T5] 8/8 review findings"; else fail "[T5] $c/8"; fi

echo
echo "T4. 순수성 · 설정 키"
c=0
bash "$CORE/scripts/check-purity.sh" "$FLOW" >/dev/null 2>&1 && c=$((c + 1)) || { echo "      purity:"; bash "$CORE/scripts/check-purity.sh" "$FLOW" 2>&1 | sed 's/^/        /'; }
# shellcheck source=/dev/null
( source "$CORE/scripts/lib/settings.sh"; grep -qw 'SCV_PR_BASE' <<<"$SCV_PLAIN_KEYS" && ! grep -qw 'SCV_PR_BASE' <<<"${SCV_SECRET_KEYS:-}" ) && c=$((c + 1)) \
  || echo "      SCV_PR_BASE must be a plain (not secret) settings key"
python3 - "$CORE/template/scv/scv_settings.example.json" <<'PY' && c=$((c + 1)) || echo "      settings example: SCV_PR_BASE value \"\" and a _doc entry"
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
sys.exit(0 if d.get("SCV_PR_BASE") == "" and d.get("_doc", {}).get("SCV_PR_BASE") else 1)
PY
if [[ $c -eq 3 ]]; then ok "OK [T4] 3/3 purity · settings key"; else fail "[T4] $c/3"; fi

echo
echo "── $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
