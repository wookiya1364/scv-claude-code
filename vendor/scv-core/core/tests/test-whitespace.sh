#!/usr/bin/env bash
# test-whitespace.sh — core/ 아래 추적 파일에 줄끝 공백·파일 끝 빈 줄이 없는지 본다.
#
# 래퍼 저장소의 core-sync 는 벤더링 뒤 `git diff --check` 를 돌린다. 코어가 파일 끝에
# 빈 줄 하나를 흘리면 계약 테스트가 전부 통과해도 래퍼 전파가 그 자리에서 멈춘다
# (0.34.0 → 래퍼 고정 PR 미생성). 그 검사를 코어 쪽에서 먼저 돌려 릴리스 전에 잡는다.
#
# Run: bash core/tests/test-whitespace.sh
set -uo pipefail

CORE="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." && pwd )"

PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }

# 추적 파일 목록: git 안이면 ls-files, 아니면(벤더 복사본) 파일 시스템.
list_files() {
  if git -C "$CORE" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$CORE" ls-files -z -- . | tr '\0' '\n' | sed "s|^|$CORE/|"
  else
    find "$CORE" -type f ! -path '*/node_modules/*' ! -path '*/.git/*'
  fi
}

echo "T1. 파일 끝 빈 줄 (git diff --check 의 'new blank line at EOF')"
eof_bad=()
while IFS= read -r f; do
  [[ -f "$f" && -s "$f" ]] || continue
  grep -Iq . "$f" 2>/dev/null || continue           # 바이너리는 건너뛴다
  [[ "$(tail -c 2 "$f" | od -An -c | tr -d ' \n')" == '\n\n' ]] && eof_bad+=("${f#$CORE/}")
done < <(list_files)
if (( ${#eof_bad[@]} == 0 )); then ok "파일 끝에 빈 줄을 흘린 파일 없음"
else fail "파일 끝 빈 줄: ${eof_bad[*]}"; fi

echo "T2. 줄끝 공백 (git diff --check 의 'trailing whitespace')"
ws_bad=()
while IFS= read -r f; do
  [[ -f "$f" && -s "$f" ]] || continue
  grep -Iq . "$f" 2>/dev/null || continue
  case "$f" in *.md) continue ;; esac                # 마크다운의 두 칸 줄바꿈은 허용
  grep -qE '[[:space:]]+$' "$f" && ws_bad+=("${f#$CORE/}")
done < <(list_files)
if (( ${#ws_bad[@]} == 0 )); then ok "줄끝 공백 없음"
else fail "줄끝 공백: ${ws_bad[*]}"; fi

echo "T3. 검사 자체가 잡는가 (일부러 흘린 빈 줄)"
tmp="$(mktemp)"; printf 'x\n\n' > "$tmp"
if [[ "$(tail -c 2 "$tmp" | od -An -c | tr -d ' \n')" == '\n\n' ]]; then ok "빈 줄 흘린 파일을 잡는다"
else fail "탐지 로직이 빈 줄을 놓친다"; fi
rm -f "$tmp"

echo
echo "─────────────────────────────"
echo "  통과 $PASS · 실패 $FAIL"
[[ $FAIL -eq 0 ]] && { echo "  ALL GATES OK"; exit 0; } || exit 1
