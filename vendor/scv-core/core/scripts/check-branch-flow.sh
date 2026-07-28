#!/bin/sh
# branch-flow 강제 — 타겟 브랜치별 허용 소스 브랜치 검사 (GitHub Actions / GitLab CI 공통)
#
# 입력(환경변수):
#   TARGET_BRANCH, SOURCE_BRANCH
#     GitHub Actions: github.base_ref / github.head_ref
#     GitLab CI:      CI_MERGE_REQUEST_TARGET_BRANCH_NAME / CI_MERGE_REQUEST_SOURCE_BRANCH_NAME
#
# 규칙 (see .github/BRANCHING.md):
#   main        <-  stage | fix/*
#   stage       <-  develop
#   develop <-  feat/* | fix/* | docs/* | chore/* | refactor/* | test/*
#
# 의존성 없음(POSIX sh). 위반 시 exit 1로 파이프라인 실패.
set -eu

TARGET="${TARGET_BRANCH:-}"
SOURCE="${SOURCE_BRANCH:-}"

if [ -z "$TARGET" ] || [ -z "$SOURCE" ]; then
  echo "ERROR: TARGET_BRANCH / SOURCE_BRANCH 가 설정되지 않았습니다." >&2
  exit 2
fi

echo "branch-flow 검사: '$SOURCE' -> '$TARGET'"

ok=0
allowed=""
case "$TARGET" in
  main)
    case "$SOURCE" in
      stage|fix/*) ok=1 ;;
    esac
    allowed="stage, fix/*"
    ;;
  stage)
    case "$SOURCE" in
      develop) ok=1 ;;
    esac
    allowed="develop"
    ;;
  develop)
    case "$SOURCE" in
      feat/*|fix/*|docs/*|chore/*|refactor/*|test/*) ok=1 ;;
    esac
    allowed="feat/*, fix/*, docs/*, chore/*, refactor/*, test/*"
    ;;
  *)
    echo "보호 대상 타겟이 아님('$TARGET') — 검사 건너뜀."
    exit 0
    ;;
esac

if [ "$ok" != "1" ]; then
  echo "ERROR: '$SOURCE' -> '$TARGET' 병합은 금지입니다. 허용 소스: $allowed" >&2
  exit 1
fi

echo "OK: '$SOURCE' -> '$TARGET' 허용됨."
