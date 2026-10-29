#!/usr/bin/env bash
# test-check-privacy.sh — 개인정보 검사가 깨끗한 커밋은 통과시키고, 개인 메일 · 경로 · 세션 줄 · 비밀 목록 낱말은 막는지 본다.
# 개인 값은 쓰지 않는다 — 모두 가짜 값(alice, example-team)이다.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK="$HERE/../scripts/check-privacy.sh"
PASS=0; FAIL=0
ok()   { echo "  ✓ $1"; PASS=$((PASS + 1)); }
fail() { echo "  ✖ FAIL: $1"; FAIL=$((FAIL + 1)); }
WORK="$(mktemp -d "${TMPDIR:-/tmp}/scv-privacy.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

NOREPLY='1+alice@users.noreply.github.com'
new_repo() {  # → 기준 커밋 하나가 있는 저장소
  local d="$WORK/$1"; mkdir -p "$d"
  git -C "$d" init -q; git -C "$d" config user.name alice; git -C "$d" config user.email "$NOREPLY"
  echo base > "$d/README.md"; git -C "$d" add -A; git -C "$d" commit -qm base
  echo "$d"
}
commit() {  # <dir> <file> <line> <message> [email]
  printf '%s\n' "$3" >> "$1/$2"; git -C "$1" add -A
  GIT_AUTHOR_EMAIL="${5:-$NOREPLY}" GIT_COMMITTER_EMAIL="${5:-$NOREPLY}" git -C "$1" commit -qm "$4"
}
run() { (cd "$1" && SCV_PRIVACY_EMAILS="${EMAILS:-off}" BASE_SHA="$(git rev-list --max-parents=0 HEAD)" SCV_PRIVACY_TERMS="${2:-}" bash "$CHECK" 2>&1); }
expect() {  # <name> <want 0|1> <dir> <fragment> [terms]
  local out rc=0; out="$(run "$3" "${5:-}")" || rc=$?
  if [[ $rc -ne $2 ]]; then fail "$1 (exit $rc, want $2): $out"; return; fi
  if [[ -n "$4" ]] && ! grep -qF -- "$4" <<< "$out"; then fail "$1: missing '$4' in: $out"; return; fi
  ok "$1"
}

echo "── [T9] 개인정보 검사 ──"
d="$(new_repo clean)"; commit "$d" docs.md 'a plain line' 'docs: plain'
expect "(e) 깨끗한 커밋은 통과" 0 "$d" "OK privacy"

d="$(new_repo email)"; commit "$d" docs.md 'x' 'docs: x' 'alice@gmail.com'
expect "기본: 개인 메일 작성자는 허용(공개 계정 메일)" 0 "$d" "OK privacy"
EMAILS=on expect "(a) SCV_PRIVACY_EMAILS=on 이면 개인 메일 작성자는 막힘" 1 "$d" "author email is not a noreply address"

d="$(new_repo path)"; commit "$d" notes.md 'see /Us''ers/alice/work/repo' 'docs: path'
expect "(b) 추가 줄의 /Users 경로는 막힘" 1 "$d" "notes.md:1 local-path"

d="$(new_repo trailer)"; commit "$d" docs.md 'y' "$(printf 'docs: y\n\nHost-Sess''ion: https://example.ai/code/sess''ion_01AbCdEfGhIjKlMn')"
expect "(c) 세션 링크 줄은 막힘" 1 "$d" "commit message: session-line"

d="$(new_repo term)"; commit "$d" docs.md 'built for the Example-Team squad' 'docs: z'
out="$(run "$d" "$(printf 'nobody\nexample-team\n')")"
if grep -qF "matches private term #2" <<< "$out" && ! grep -qiF "example-team" <<< "$out"; then ok "(d) 비밀 목록 낱말은 막히고 출력에서 가려짐"; else fail "(d) private term: $out"; fi

d="$(new_repo partial)"; commit "$d" docs.md 'teammate notes' 'docs: partial'
expect "낱말 경계 — 다른 낱말 속은 걸리지 않음" 0 "$d" "OK privacy" "$(printf 'team\n')"

d="$(new_repo fixture)"; mkdir -p "$d/tests/fixtures"; commit "$d" tests/fixtures/s.jsonl '{"p":"/Us''ers/alice/secret"}' 'test: fixture'
expect "가짜 시험 자료 경로는 검사하지 않음" 0 "$d" "OK privacy"

d="$(new_repo bot)"; commit "$d" docs.md 'w' 'chore: bot' 'scv-core-sync[bot]@users.noreply.github.com'
expect "봇 noreply 주소는 통과" 0 "$d" "OK privacy"

echo "test-check-privacy: PASS=$PASS FAIL=$FAIL"
(( FAIL == 0 ))
