#!/usr/bin/env bash
# lib/run-manifest.sh — 실행 기록: 테스트를 돌린 그 실행이 만든 결과 파일 목록.
#
# 왜 있나: 첨부를 파일 "이름"으로 알아맞히는 구조는 결과 폴더명이 잘리면 깨진다
# (Playwright 는 폴더명을 길이 제한으로 자른다 — 슬러그 전체가 경로에 남지 않아
# 이름 매칭이 0건이 된 실측 사례가 raw 에 있다). 테스트를 돌린 그 순간에는
# "이 실행 = 이 계획" 을 확실히 안다 — 그때 기록하면 이름은 상관없어진다.
#
# 위치: <base>/.scv/<slug>.manifest (기본 base: test-results). 결과 폴더 안에
# 두는 것은 의도다 — 테스트 러너가 다음 실행에서 결과를 비우면 기록도 함께
# 사라진다. 기록은 절대 결과보다 오래 살지 않으므로, 낡은 기록이 없는 파일을
# 가리키는 일이 없다.
#
# 사용:
#   run_manifest_path <slug> [base]            → 기록 파일 경로
#   run_manifest_record <slug> <marker> [pre] [base]
#       marker 파일보다 새로 생긴/갱신된 파일 목록을 기록한다. pre(실행 전
#       파일 목록, 한 줄 한 경로)를 주면 mtime 이 같아도 "전에 없던" 파일을
#       잡는다 (초 단위 파일시스템 대비).
#   run_manifest_read <slug> [base]            → 기록 중 지금 존재하는 파일만
#       출력. 기록이 없거나 유효 항목 0 이면 출력 없음 (호출자는 이름 매칭으로
#       폴백한다).

# @pure
run_manifest_path() {
  local slug="${1:?slug}" base="${2:-test-results}"
  printf '%s/.scv/%s.manifest\n' "$base" "$slug"
}

run_manifest_record() {
  local slug="${1:?slug}" marker="${2:?marker}" pre="${3:-}" base="${4:-test-results}"
  [[ -d "$base" ]] || return 0
  local out tmp
  out="$(run_manifest_path "$slug" "$base")"
  mkdir -p "${out%/*}"
  tmp="$(mktemp)"
  find "$base" -type f ! -path "$base/.scv/*" -newer "$marker" 2>/dev/null > "$tmp"
  if [[ -n "$pre" && -f "$pre" ]]; then
    find "$base" -type f ! -path "$base/.scv/*" 2>/dev/null | LC_ALL=C sort \
      | comm -13 <(LC_ALL=C sort "$pre") - >> "$tmp"
  fi
  LC_ALL=C sort -u "$tmp" > "$out"
  rm -f "$tmp"
  return 0
}

run_manifest_read() {
  local slug="${1:?slug}" base="${2:-test-results}" f p
  f="$(run_manifest_path "$slug" "$base")"
  [[ -f "$f" ]] || return 0
  while IFS= read -r p; do
    [[ -n "$p" && -f "$p" ]] && printf '%s\n' "$p"
  done < "$f"
  return 0   # 마지막 read 는 EOF 에서 1 — set -e 호출자가 실패로 보면 안 된다
}
