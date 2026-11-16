#!/usr/bin/env bash
# test-update.sh — /scv:update 의 엔진 scripts/update.sh 와 스킬 검사 (gh 없이 최신 버전 확인 · 직접 올리기 · 모드까지 함께).
#
# 가짜 claude 와 가짜 git 으로 본다 — 상태(마켓과 채널, 설치된 플러그인의 버전 · 범위, 태그 목록, 실패할 명령)를 파일로
# 들고, 받은 plugin 명령을 기록하고 상태를 바꾼다. 실제 마켓 · 네트워크 · 설치본은 건드리지 않는다.
# 모드 쪽은 진짜 scripts/mods.sh 가 같은 가짜 claude 로 돈다.
# Run: bash tests/test-update.sh
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
U="$ROOT/scripts/update.sh"; M="$ROOT/scripts/mods.sh"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
for f in "$U" "$M"; do [[ -f "$f" ]] || { echo "✖ 없음: $f"; exit 1; }; done
command -v jq >/dev/null 2>&1 || { echo "jq 없음 — 이 검사는 jq 가 필요하다" >&2; exit 1; }
W="$(mktemp -d "${TMPDIR:-/tmp}/scv-update-test.XXXXXX")"; trap 'rm -rf "$W"' EXIT
mkdir -p "$W/bin" "$W/root/.claude-plugin" "$W/proj" "$W/nogh"

# 가짜 플러그인 뿌리 — 진단이 읽는 설치 버전 · 이름 · 저장소 주소.
plugin_root() {
  cat > "$W/root/.claude-plugin/plugin.json" <<JSON
{
  "name": "scv",
  "version": "$1",
  "homepage": "https://github.com/wookiya1364/scv-claude-code"
}
JSON
  cat > "$W/root/.claude-plugin/marketplace.json" <<'JSON'
{
  "name": "scv-claude-code",
  "plugins": [{ "name": "scv" }]
}
JSON
}

# 가짜 claude — $FC_DIR/mkts ("마켓 가지|-" 줄), $FC_DIR/inst ("id 버전 범위 [프로젝트 폴더]" 줄),
# $FC_DIR/next.<이름> (올린 뒤 버전), $FC_DIR/failon (이 말로 시작하는 명령은 실패 — 문구는 $FC_DIR/failmsg).
# 범위 없이 부른 update 는 같은 id 의 첫 줄만 올린다 — 명령줄의 "자동 고르기"가 한쪽만 올리는 것을 흉내 낸다.
cat > "$W/bin/claude" <<'FC'
#!/usr/bin/env bash
[[ "$1" == plugin ]] || exit 9; shift
echo "$*" >> "$FC_DIR/calls"
if [[ -f "$FC_DIR/failon" ]] && [[ "$*" == "$(cat "$FC_DIR/failon")"* ]]; then
  if [[ -f "$FC_DIR/failmsg" ]]; then cat "$FC_DIR/failmsg" >&2; else echo "Error: boom" >&2; fi
  exit 1
fi
inst() { [[ -f "$FC_DIR/inst" ]] && cat "$FC_DIR/inst"; }
case "$*" in
  "marketplace list --json")
    { [[ -f "$FC_DIR/mkts" ]] && awk 'NF { if ($2 == "-" || $2 == "") printf "{\"name\":\"%s\"}\n", $1; else printf "{\"name\":\"%s\",\"ref\":\"%s\"}\n", $1, $2 }' "$FC_DIR/mkts"; echo '{"name":"other"}'; } | jq -cs . ;;
  "list --json")
    { inst | awk 'NF { p = ($4 != "") ? ",\"projectPath\":\"" $4 "\"" : ""; printf "{\"id\":\"%s\",\"version\":\"%s\",\"scope\":\"%s\"%s}\n", $1, $2, $3, p }'; echo '{"id":"x@other","version":"1","scope":"user"}'; } | jq -cs . ;;
  "list --json --available") echo '{"installed":[],"available":[]}' ;;
  "marketplace update "*) : ;;
  "update "*)
    id="$2"; scope=""; [[ "${3:-}" == "-s" ]] && scope="${4:-}"
    name="${id%@*}"; v="$(cat "$FC_DIR/next.$name" 2>/dev/null)"
    if [[ -n "$v" ]]; then
      inst | awk -v id="$id" -v s="$scope" -v v="$v" '
        $1 == id && ((s == "" && !done) || (s != "" && $3 == s)) { $2 = v; done = 1 } { print }' > "$FC_DIR/inst.n"
      mv "$FC_DIR/inst.n" "$FC_DIR/inst"
    fi ;;
  *) exit 8 ;;
esac
exit 0
FC
chmod +x "$W/bin/claude"

# 가짜 git — $FG_DIR/tags (태그 이름 줄)가 있으면 ls-remote 꼴로 내고, 없으면 네트워크 실패처럼 끝난다.
cat > "$W/bin/git" <<'FG'
#!/usr/bin/env bash
echo "$*" >> "$FG_DIR/gitcalls"
[[ -f "$FG_DIR/tags" ]] || { echo "fatal: unable to access 'https://example.invalid/': Could not resolve host" >&2; exit 128; }
awk 'NF { printf "0000000000000000000000000000000000000000\trefs/tags/%s\n", $1 }' "$FG_DIR/tags"
FG
chmod +x "$W/bin/git"

# gh 가 없는 PATH — 필요한 도구만 이어 붙인다 (gh 는 넣지 않는다).
for t in bash sh env cat sed grep awk jq sort head tail tr mktemp rm mv mkdir dirname basename pwd printf cut wc date uname; do
  p="$(command -v "$t" 2>/dev/null)" && [[ -n "$p" && "$p" == /* ]] && ln -sf "$p" "$W/nogh/$t"
done
NOGH="$W/nogh"

case_dir() { rm -rf "$W/fc"; mkdir -p "$W/fc"; : > "$W/fc/calls"; : > "$W/fc/gitcalls"; echo "scv-claude-code -" > "$W/fc/mkts"; }
tags() { printf '%s\n' "$@" > "$W/fc/tags"; }
run() { ( cd "$W/proj" && PATH="$NOGH" FC_DIR="$W/fc" FG_DIR="$W/fc" SCV_CLAUDE_BIN="$W/bin/claude" SCV_UPDATE_GIT_BIN="$W/bin/git" \
    SCV_UPDATE_PLUGIN_ROOT="$W/root" "$BASH" "$U" "$@" 2>&1 ); }
runm() { ( cd "$W/proj" && PATH="$NOGH" FC_DIR="$W/fc" SCV_CLAUDE_BIN="$W/bin/claude" "$BASH" "$M" "$@" 2>&1 ); }
calls() { grep -vE '^(marketplace list|list) --json' "$W/fc/calls"; }
ncalls() { calls | grep -c "$1" || true; }

echo "── [T1] gh 가 없어도 최신 버전이 읽힌다 ──"
plugin_root 0.85.2; case_dir; tags v0.93.3 v0.94.0
O="$(run)"
grep -q '^LATEST_VERSION: 0.94.0$' <<<"$O" && ok "최신 버전 0.94.0" || fail "최신 버전 줄: $O"
grep -q '^UP_TO_DATE: no$' <<<"$O" && ok "새 버전 있음" || fail "UP_TO_DATE: $O"
grep -q 'unavailable' <<<"$O" && fail "확인 불가가 나옴: $O" || ok "확인 불가 0번"
plugin_root 0.94.0
O="$(run)"
grep -q '^UP_TO_DATE: yes$' <<<"$O" && ok "같으면 최신" || fail "UP_TO_DATE: $O"
grep -vE '^[[:space:]]*#' "$U" | grep -qE '(^|[^[:alnum:]_/.-])gh[[:space:]]+(release|api|auth)' && fail "엔진이 gh 를 부름" || ok "엔진에 gh 호출 0곳"

echo "── [T2] 최신 버전 고르기 — 숫자로 견주고 정식 태그만 ──"
case_dir
( SCV_CLAUDE_BIN="$W/bin/claude"; FC_DIR="$W/fc"; FG_DIR="$W/fc"; SCV_UPDATE_GIT_BIN="$W/bin/git"
  # shellcheck source=/dev/null
  source "$U"
  in1=$'v0.9.0\nv0.10.0\nv0.94.0\nv0.94.0-codex.1\nv1.0.0-rc.1\nchannel-dev\n\nnightly'
  echo "A=$(update_latest_version "$in1")"
  echo "B=$(update_latest_version $'v0.9.0\nv0.10.0')"
  echo "C=$(update_latest_version $'nightly\nv1.0.0-rc.1')"
  echo "D=$(update_latest_version "$(printf '0000\trefs/tags/v0.2.0\n1111\trefs/tags/v0.11.3\n')")"
  p1="$(update_plan apply 'user 0.85.2' 0.94.0 scv scv-claude-code prod)"
  p2="$(update_plan apply 'user 0.85.2' 0.94.0 scv scv-claude-code prod)"
  s1="$(update_summary scv 'user 0.85.2' 'user 0.94.0' '' prod)"
  s2="$(update_summary scv 'user 0.85.2' 'user 0.94.0' '' prod)"
  [[ "$p1" == "$p2" && "$s1" == "$s2" && -n "$p1" && -n "$s1" ]] && echo "PURE=SAME" || echo "PURE=DIFF" ) > "$W/pure" 2>&1
grep -q '^A=0.94.0$' "$W/pure" && ok "섞인 태그에서 0.94.0" || fail "고르기: $(tr '\n' '|' < "$W/pure")"
grep -q '^B=0.10.0$' "$W/pure" && ok "0.10.0 이 0.9.0 보다 높음" || fail "숫자 견주기: $(grep '^B=' "$W/pure")"
grep -q '^C=$' "$W/pure" && ok "정식 태그가 없으면 빈 값" || fail "빈 값이 아님: $(grep '^C=' "$W/pure")"
grep -q '^D=0.11.3$' "$W/pure" && ok "ls-remote 꼴 줄에서도 고름" || fail "ls-remote 꼴: $(grep '^D=' "$W/pure")"
grep -q '^PURE=SAME$' "$W/pure" && ok "순수 단계 — 두 번 같은 출력" || fail "출력이 다름: $(tr '\n' '|' < "$W/pure")"
[[ ! -s "$W/fc/calls" && ! -s "$W/fc/gitcalls" ]] && ok "순수 단계가 바깥을 부르지 않음" || fail "바깥 호출: $(cat "$W/fc/calls" "$W/fc/gitcalls" | tr '\n' '|')"

echo "── [T3] 새 버전이 있으면 직접 올린다 — 명령 두 줄, 순서대로 ──"
plugin_root 0.85.2; case_dir; tags v0.94.0; echo "scv@scv-claude-code 0.85.2 user" > "$W/fc/inst"; echo 0.94.0 > "$W/fc/next.scv"
O="$(run apply)"; rc=$?
[[ "$(calls | tr '\n' '|')" == "marketplace update scv-claude-code|update scv@scv-claude-code -s user|" ]] && ok "순서: 마켓 새로 받기 → 올리기(범위 user)" || fail "호출: $(calls | tr '\n' '|')"
grep -q '^RESULT: scv updated 0.85.2 -> 0.94.0 \[user\]$' <<<"$O" && ok "앞뒤 버전 보고" || fail "결과: $O"
grep -q '^NEXT: .*새 세션' <<<"$O" && ok "새 세션 안내" || fail "새 세션 안내 없음: $O"
[[ $rc -eq 0 ]] && ok "종료 코드 0" || fail "종료 코드 $rc"

echo "── [T4] 이미 최신이면 아무 명령도 실행하지 않는다 ──"
plugin_root 0.94.0; case_dir; tags v0.94.0; echo "scv@scv-claude-code 0.94.0 user" > "$W/fc/inst"
O="$(run apply)"; rc=$?
[[ -z "$(calls)" ]] && ok "바꾸는 명령 0줄" || fail "호출: $(calls | tr '\n' '|')"
grep -q '^RESULT: scv up-to-date 0.94.0 \[user\]$' <<<"$O" && ok "이미 최신" || fail "결과: $O"
grep -q '새 세션' <<<"$O" && fail "안 바뀌었는데 새 세션 안내" || ok "새 세션 안내 없음"
[[ $rc -eq 0 ]] && ok "종료 코드 0" || fail "종료 코드 $rc"

echo "── [T5] 설치 범위가 둘이면 범위마다 올린다 ──"
plugin_root 0.85.2; case_dir; tags v0.94.0; echo 0.94.0 > "$W/fc/next.scv"
printf 'scv@scv-claude-code 0.85.2 user\nscv@scv-claude-code 0.85.2 project\n' > "$W/fc/inst"
O="$(run apply)"
[[ "$(ncalls '^marketplace update scv-claude-code$')" -eq 1 ]] && ok "마켓 새로 받기 1번" || fail "호출: $(calls | tr '\n' '|')"
[[ "$(ncalls '^update scv@scv-claude-code -s user$')" -eq 1 && "$(ncalls '^update scv@scv-claude-code -s project$')" -eq 1 && "$(ncalls '^update scv@')" -eq 2 ]] \
  && ok "올리기 2번 — 범위마다 한 번" || fail "호출: $(calls | tr '\n' '|')"
grep -q '^RESULT: scv updated 0.85.2 -> 0.94.0 \[user\]$' <<<"$O" && grep -q '^RESULT: scv updated 0.85.2 -> 0.94.0 \[project\]$' <<<"$O" && ok "범위별 앞뒤 버전" || fail "결과: $O"
case_dir; tags v0.94.0; echo 0.94.0 > "$W/fc/next.scv"
printf 'scv@scv-claude-code 0.85.2 user\nscv@scv-claude-code 0.85.2 project /somewhere/else\n' > "$W/fc/inst"
O="$(run apply)"
[[ "$(ncalls '^update scv@')" -eq 1 ]] && ok "다른 프로젝트의 설치본은 건드리지 않음" || fail "호출: $(calls | tr '\n' '|')"
case_dir; tags v0.94.0; echo 0.94.0 > "$W/fc/next.scv"; ln -sfn "$W/proj" "$W/projlink"
printf 'scv@scv-claude-code 0.85.2 user\nscv@scv-claude-code 0.85.2 project %s\n' "$(cd "$W/proj" && pwd -P)" > "$W/fc/inst"
( cd "$W/projlink" && PATH="$NOGH" FC_DIR="$W/fc" FG_DIR="$W/fc" SCV_CLAUDE_BIN="$W/bin/claude" SCV_UPDATE_GIT_BIN="$W/bin/git" SCV_UPDATE_PLUGIN_ROOT="$W/root" "$BASH" "$U" apply >/dev/null 2>&1 )
[[ "$(ncalls '^update scv@scv-claude-code -s project$')" -eq 1 ]] && ok "심볼릭 링크로 들어온 지금 프로젝트의 설치본은 올림" || fail "호출: $(calls | tr '\n' '|')"

echo "── [T6] 앞 단계가 실패하면 멈추고 실패라고 말한다 ──"
plugin_root 0.85.2; case_dir; tags v0.94.0; echo "scv@scv-claude-code 0.85.2 user" > "$W/fc/inst"; echo 0.94.0 > "$W/fc/next.scv"
echo "marketplace update scv-claude-code" > "$W/fc/failon"; echo "Error: marketplace source path does not exist" > "$W/fc/failmsg"
O="$(run apply)"; rc=$?
[[ "$(ncalls '^update scv@')" -eq 0 ]] && ok "뒤 단계(올리기) 0번" || fail "호출: $(calls | tr '\n' '|')"
grep -q '^RESULT: scv failed marketplace update scv-claude-code$' <<<"$O" && ok "실패한 단계 이름" || fail "결과: $O"
[[ "$(grep -c '^NEXT: ' <<<"$O")" -eq 1 ]] && ok "다음 행동 한 줄" || fail "NEXT 줄 수: $O"
grep -q 'marketplace source path does not exist' <<<"$O" && ok "오류 문구 그대로" || fail "오류 문구 없음: $O"
grep -qE '^RESULT: scv (updated|up-to-date)' <<<"$O" && fail "성공 줄이 나옴: $O" || ok "성공 줄 0번"
[[ $rc -eq 1 ]] && ok "종료 코드 1" || fail "종료 코드 $rc"

echo "── [T7] claude 명령줄이 없으면 못 한다고 말하고 칠 명령을 안내한다 ──"
plugin_root 0.85.2; case_dir; tags v0.94.0
O="$( cd "$W/proj" && PATH="$NOGH" FC_DIR="$W/fc" FG_DIR="$W/fc" SCV_CLAUDE_BIN="$W/bin/no-such-claude" SCV_UPDATE_GIT_BIN="$W/bin/git" SCV_UPDATE_PLUGIN_ROOT="$W/root" "$BASH" "$U" apply 2>&1 )"; rc=$?
grep -q '^RESULT: scv failed claude-cli-missing$' <<<"$O" && ok "명령줄 없음으로 실패" || fail "결과: $O"
grep -q 'claude plugin marketplace update scv-claude-code' <<<"$O" && grep -q 'claude plugin update scv@scv-claude-code' <<<"$O" && ok "터미널에서 칠 두 명령 안내" || fail "안내 없음: $O"
[[ $rc -eq 1 ]] && ok "종료 코드 1" || fail "종료 코드 $rc"
O="$( cd "$W/proj" && PATH="$NOGH" FC_DIR="$W/fc" FG_DIR="$W/fc" SCV_CLAUDE_BIN="$W/bin/no-such-claude" SCV_UPDATE_GIT_BIN="$W/bin/git" SCV_UPDATE_PLUGIN_ROOT="$W/root" "$BASH" "$U" 2>&1 )"; rc=$?
[[ $rc -eq 0 ]] && grep -q '^LATEST_VERSION: 0.94.0$' <<<"$O" && ok "진단은 같은 조건에서도 종료 0" || fail "진단: rc=$rc $O"

echo "── [T8] 최신 버전을 못 읽어도 올리기는 되고, 진단은 이유를 말한다 ──"
plugin_root 0.85.2; case_dir; echo "scv@scv-claude-code 0.85.2 user" > "$W/fc/inst"; echo 0.94.0 > "$W/fc/next.scv"
O="$(run)"; rc=$?
grep -q '^LATEST_VERSION: (unavailable — ' <<<"$O" && grep -q '^UP_TO_DATE: unknown$' <<<"$O" && ok "진단: 확인 불가 + 이유" || fail "진단: $O"
grep '^LATEST_VERSION:' <<<"$O" | grep -qw 'gh' && fail "이유에 gh 가 나옴: $O" || ok "이유에 gh 없음"
[[ $rc -eq 0 ]] && ok "진단 종료 코드 0" || fail "종료 코드 $rc"
O="$(run apply)"
[[ "$(calls | tr '\n' '|')" == "marketplace update scv-claude-code|update scv@scv-claude-code -s user|" ]] && ok "못 읽어도 명령 두 줄 실행" || fail "호출: $(calls | tr '\n' '|')"
grep -q '^RESULT: scv updated 0.85.2 -> 0.94.0 \[user\]$' <<<"$O" && ok "앞뒤 버전으로 보고" || fail "결과: $O"

echo "── [T9] 진단은 읽기만 하고, 출력 다섯 줄이 그대로다 ──"
plugin_root 0.85.2; case_dir; tags v0.94.0; echo "scv@scv-claude-code 0.85.2 user" > "$W/fc/inst"
rm -rf "$W/proj"; mkdir -p "$W/proj/scv"; echo a > "$W/proj/a.txt"; echo b > "$W/proj/scv/b.md"
snap() { ( cd "$W/proj" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do printf '%s %s\n' "$(cksum < "$f")" "$f"; done ); }
B="$(snap)"; O="$(run)"; A="$(snap)"
keys="$(printf '%s\n' "$O" | sed -E 's/:.*//' | tr '\n' ' ')"
[[ "$keys" == "INSTALLED_VERSION MARKETPLACE_NAME PLUGIN_NAME LATEST_VERSION UP_TO_DATE " ]] && ok "출력 다섯 줄의 이름 · 순서 그대로" || fail "출력 키: $keys"
[[ "$B" == "$A" ]] && ok "프로젝트 폴더 전후 같음" || fail "프로젝트 파일이 바뀜"
[[ ! -s "$W/fc/calls" ]] && ok "claude 호출 0번" || fail "호출: $(tr '\n' '|' < "$W/fc/calls")"
B="$(snap)"; run apply >/dev/null; A="$(snap)"
[[ "$B" == "$A" ]] && ok "올리기도 프로젝트 파일을 바꾸지 않음" || fail "올리기가 프로젝트 파일을 바꿈"

echo "── [T10] 채널이 운영이 아니면 올리지 않는다 ──"
plugin_root 0.94.1-dev.abc1234; case_dir; tags v0.94.0; echo "scv-claude-code channel/dev" > "$W/fc/mkts"
echo "scv@scv-claude-code 0.94.1-dev.abc1234 user" > "$W/fc/inst"; echo 0.94.0 > "$W/fc/next.scv"
O="$(run apply)"; rc=$?
[[ -z "$(calls)" ]] && ok "바꾸는 명령 0줄" || fail "호출: $(calls | tr '\n' '|')"
grep -q '/scv:channel' <<<"$O" && ok "/scv:channel 안내" || fail "안내 없음: $O"
grep -q '^RESULT: scv skipped channel dev$' <<<"$O" && ok "건너뜀 결과" || fail "결과: $O"
[[ $rc -eq 0 ]] && ok "종료 코드 0" || fail "종료 코드 $rc"

echo "── [T11] 설명서와 README 가 새 동작을 말한다 ──"
S="$ROOT/skills/update/SKILL.md"
grep -qE 'scripts/update\.sh"? apply' "$S" && ok "설명서: 엔진을 apply 로 부름" || fail "설명서에 apply 호출 없음"
grep -q '/plugin marketplace update' "$S" && fail "설명서에 슬래시 명령 안내가 남음" || ok "설명서: 슬래시 명령 안내 0곳"
grep -qiE 'auto-invoke|guide the user only|cannot self-update' "$S" && fail "설명서에 '안내만' 문구가 남음" || ok "설명서: '안내만' 문구 0곳"
grep -qiE 'only (asks|asked)|check only|only whether' "$S" && ok "설명서: 확인만 요청이면 올리지 않음" || fail "설명서에 확인만 문구 없음"
grep -qi 'new session' "$S" && ok "설명서: 새 세션 안내" || fail "설명서에 새 세션 안내 없음"
grep -qi 'mods' "$S" && ok "설명서: 모드도 함께 오름" || fail "설명서에 모드 문구 없음"
sed -n '1,8p' "$S" | grep -q '^description: ' && sed -n '1,8p' "$S" | grep '^description: ' | grep -qiE 'updates? ' && ok "설명 줄이 '올린다'는 뜻" || fail "설명 줄: $(sed -n '1,8p' "$S" | grep '^description: ')"
sed -n '1,8p' "$S" | grep '^description: ' | grep -qiE 'guide the user' && fail "설명 줄에 '안내'가 남음" || ok "설명 줄에 '안내' 없음"
for r in README.md README.ko.md README.ja.md; do
  grep -q '^/plugin marketplace update' "$ROOT/$r" && fail "$r: 슬래시 명령 안내가 남음" || ok "$r: 슬래시 명령 안내 0곳"
  grep -q '/scv:update' "$ROOT/$r" && ok "$r: /scv:update 안내" || fail "$r: /scv:update 안내 없음"
done

echo "── [T14] /scv:update 한 번에 모드까지 오른다 ──"
plugin_root 0.85.2; case_dir; tags v0.94.0; printf 'scv-claude-code -\nscv-mods -\n' > "$W/fc/mkts"
printf 'scv@scv-claude-code 0.85.2 user\nscv-dashboard@scv-mods 0.2.19 user\n' > "$W/fc/inst"; echo 0.94.0 > "$W/fc/next.scv"; echo 0.2.25 > "$W/fc/next.scv-dashboard"
O="$(run apply)"; rc=$?
[[ "$(calls | tr '\n' '|')" == "marketplace update scv-claude-code|update scv@scv-claude-code -s user|marketplace update scv-mods|update scv-dashboard@scv-mods|" ]] \
  && ok "명령 4줄 — 본체 두 줄 다음 모드 두 줄" || fail "호출: $(calls | tr '\n' '|')"
grep -q '^RESULT: scv updated 0.85.2 -> 0.94.0 \[user\]$' <<<"$O" && ok "본체 결과" || fail "본체 결과: $O"
grep -q '^RESULT: scv-dashboard updated 0.2.19 -> 0.2.25$' <<<"$O" && ok "모드 결과" || fail "모드 결과: $O"
[[ $rc -eq 0 ]] && ok "종료 코드 0" || fail "종료 코드 $rc"

echo "── [T15] 본체가 이미 최신이어도 모드는 올린다 ──"
plugin_root 0.94.0; case_dir; tags v0.94.0; printf 'scv-claude-code -\nscv-mods -\n' > "$W/fc/mkts"
printf 'scv@scv-claude-code 0.94.0 user\nscv-dashboard@scv-mods 0.2.19 user\n' > "$W/fc/inst"; echo 0.2.25 > "$W/fc/next.scv-dashboard"
O="$(run apply)"
[[ "$(ncalls '^update scv@')" -eq 0 && "$(ncalls '^update scv-dashboard@scv-mods$')" -eq 1 ]] && ok "본체 올리기 0번 · 모드 올리기 1번" || fail "호출: $(calls | tr '\n' '|')"
grep -q '^RESULT: scv up-to-date 0.94.0 \[user\]$' <<<"$O" && grep -q '^RESULT: scv-dashboard updated 0.2.19 -> 0.2.25$' <<<"$O" && ok "두 결과 줄" || fail "결과: $O"

echo "── [T16] 모드 마켓이나 설치된 모드가 없으면 모드 쪽은 아무것도 하지 않는다 ──"
plugin_root 0.85.2; case_dir; tags v0.94.0; echo "scv@scv-claude-code 0.85.2 user" > "$W/fc/inst"; echo 0.94.0 > "$W/fc/next.scv"
O="$(run apply)"; rc=$?
[[ "$(ncalls '^marketplace add')" -eq 0 && "$(ncalls 'scv-mods')" -eq 0 ]] && ok "(가) 마켓 없음 — 모드 명령 0줄, 마켓 추가 0번" || fail "호출: $(calls | tr '\n' '|')"
grep -q '^RESULT: scv updated 0.85.2 -> 0.94.0 \[user\]$' <<<"$O" && [[ $rc -eq 0 ]] && ok "(가) 본체 결과 그대로 · 종료 0" || fail "결과: rc=$rc $O"
case_dir; tags v0.94.0; printf 'scv-claude-code -\nscv-mods -\n' > "$W/fc/mkts"; echo "scv@scv-claude-code 0.85.2 user" > "$W/fc/inst"; echo 0.94.0 > "$W/fc/next.scv"
O="$(run apply)"; rc=$?
[[ "$(ncalls '^marketplace add')" -eq 0 && "$(ncalls '^update .*@scv-mods')" -eq 0 && "$(ncalls '^install ')" -eq 0 ]] && ok "(나) 설치된 모드 없음 — 모드 올리기 · 설치 0번" || fail "호출: $(calls | tr '\n' '|')"
grep -q '^RESULT: scv updated 0.85.2 -> 0.94.0 \[user\]$' <<<"$O" && [[ $rc -eq 0 ]] && ok "(나) 본체 결과 그대로 · 종료 0" || fail "결과: rc=$rc $O"

echo "── [T17] 모드가 실패해도 본체 결과를 가리지 않는다 ──"
plugin_root 0.85.2; case_dir; tags v0.94.0; printf 'scv-claude-code -\nscv-mods -\n' > "$W/fc/mkts"
printf 'scv@scv-claude-code 0.85.2 user\nscv-dashboard@scv-mods 0.2.19 user\n' > "$W/fc/inst"; echo 0.94.0 > "$W/fc/next.scv"
echo "marketplace update scv-mods" > "$W/fc/failon"
O="$(run apply)"; rc=$?
grep -q '^RESULT: scv updated 0.85.2 -> 0.94.0 \[user\]$' <<<"$O" && ok "본체는 올라간 그대로 보고" || fail "본체 결과: $O"
grep -q '^RESULT: all failed marketplace update scv-mods$' <<<"$O" && ok "모드는 실패로 보고" || fail "모드 결과: $O"
[[ $rc -eq 1 ]] && ok "종료 코드 1" || fail "종료 코드 $rc"

echo "── [T18] 같은 모드가 두 범위에 깔려 있으면 범위마다 올린다 ──"
two_scopes() { case_dir; tags v0.94.0; printf 'scv-claude-code -\nscv-mods -\n' > "$W/fc/mkts"; echo 0.2.25 > "$W/fc/next.scv-dashboard"
  printf 'scv@scv-claude-code 0.94.0 user\nscv-dashboard@scv-mods 0.2.19 user\nscv-dashboard@scv-mods 0.2.19 project\n' > "$W/fc/inst"; }
plugin_root 0.94.0; two_scopes
O="$(runm update)"
[[ "$(ncalls '^update scv-dashboard@scv-mods -s user$')" -eq 1 && "$(ncalls '^update scv-dashboard@scv-mods -s project$')" -eq 1 && "$(ncalls '^update scv-dashboard@')" -eq 2 ]] \
  && ok "/scv:mods 의 길: 올리기 2번 — 범위마다" || fail "호출: $(calls | tr '\n' '|')"
grep -q '^RESULT: scv-dashboard updated 0.2.19 -> 0.2.25 \[user\]$' <<<"$O" && grep -q '^RESULT: scv-dashboard updated 0.2.19 -> 0.2.25 \[project\]$' <<<"$O" && ok "범위별 앞뒤 버전" || fail "결과: $O"
two_scopes
O="$(run apply)"
[[ "$(ncalls '^update scv-dashboard@scv-mods -s user$')" -eq 1 && "$(ncalls '^update scv-dashboard@scv-mods -s project$')" -eq 1 ]] && ok "/scv:update 의 길: 올리기 2번 — 범위마다" || fail "호출: $(calls | tr '\n' '|')"
grep -q '^RESULT: scv-dashboard updated 0.2.19 -> 0.2.25 \[project\]$' <<<"$O" && ok "범위별 결과가 이어짐" || fail "결과: $O"

echo "── [T20] 확인만 하는 진단은 모드도 건드리지 않는다 ──"
plugin_root 0.85.2; case_dir; tags v0.94.0; printf 'scv-claude-code -\nscv-mods -\n' > "$W/fc/mkts"
printf 'scv@scv-claude-code 0.85.2 user\nscv-dashboard@scv-mods 0.2.19 user\n' > "$W/fc/inst"; echo 0.2.25 > "$W/fc/next.scv-dashboard"
O="$(run)"
[[ -z "$(calls)" ]] && ok "바꾸는 명령 0줄" || fail "호출: $(calls | tr '\n' '|')"
grep -qE '^(MODS_|MOD:|STEP:|RESULT:)' <<<"$O" && fail "진단에 올리기 줄이 나옴: $O" || ok "진단 출력에 모드 · 단계 줄 없음"

echo ""
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
