#!/usr/bin/env bash
# ci-plan.sh — 이 PR 에 무거운 시험(계약 · 공유 회귀 · 집중 시험)이 필요한지 정한다.
#
# 바뀐 파일이 전부 문서 · 버전(docs/ 아래, VERSION, CHANGELOG.md)이면 건너뛴다.
# README 는 README 검사가, core/ 아래 .md 는 모델이 읽고 실행하는 규약이라 시험 대상이다 —
# 문서로 치지 않는다. 판정이 애매하면(목록이 비었거나 읽지 못하면) 전체를 돈다.
#
# 맥 조각은 실행 코드가 바뀐 PR 에만 필요하다. 맥 · 리눅스 차이(BSD/GNU 도구, bash 3.2, 대소문자
# 구분)는 코드가 드러내는 것이라, 바뀐 파일이 전부 Markdown(.md) · VERSION 이면 맥은 건너뛴다.
# 그 밖의 파일이 하나라도 있거나 목록이 비면 맥도 돈다.
#
# 쓰는 법: bash tools/ci-plan.sh <base-sha> [<head-sha>]
#   출력: 'docs_only=yes|no' 와 'macos=yes|no' 두 줄 (GITHUB_OUTPUT 이 있으면 거기에도 적는다)
#
# 파이프라인: changed_files → ci_docs_only · ci_needs_macos → 출력

set -u

# ── 순수: 바뀐 파일 목록(줄마다 하나) → yes | no
ci_docs_only() {
  awk '
    NF == 0 { next }
    { n++ }
    $0 == "VERSION" || $0 == "CHANGELOG.md" { next }
    $0 ~ /^docs\// { next }
    { other++ }
    END { print (n > 0 && other == 0) ? "yes" : "no" }'
}

# ── 순수: 바뀐 파일 목록 → yes(맥도 돈다) | no(Markdown · VERSION 뿐)
ci_needs_macos() {
  awk '
    NF == 0 { next }
    { n++ }
    $0 == "VERSION" || $0 ~ /\.md$/ { next }
    { code++ }
    END { print (n == 0 || code > 0) ? "yes" : "no" }'
}

# ── 입구: base..head 사이에 바뀐 파일
ci_changed_files() {
  git diff --name-only "$1" "$2" 2>/dev/null
}

ci_main() {
  local base="${1:-}" head="${2:-HEAD}" files verdict macos
  if [[ -z "$base" ]] || ! files="$(ci_changed_files "$base" "$head")"; then
    verdict="no"; macos="yes"
  else
    verdict="$(printf '%s\n' "$files" | ci_docs_only)"
    macos="$(printf '%s\n' "$files" | ci_needs_macos)"
  fi
  printf 'docs_only=%s\nmacos=%s\n' "$verdict" "$macos"
  [[ -n "${GITHUB_OUTPUT:-}" ]] && printf 'docs_only=%s\nmacos=%s\n' "$verdict" "$macos" >> "$GITHUB_OUTPUT"
  return 0
}

if [[ "${BASH_SOURCE[0]:-}" == "$0" ]]; then
  ci_main "$@"
fi
