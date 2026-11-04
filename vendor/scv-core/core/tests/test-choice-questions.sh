#!/usr/bin/env bash
# test-choice-questions.sh — 나눈 조각을 차례로 돌리는 묶음(지난 계획의 시험 명령이 이 이름을 부른다).
# scv-test: aggregate
# 조각: test-choice-questions-a.sh test-choice-questions-b.sh test-choice-questions-c.sh — CI 와 전체 시험은 조각을 따로 돌리고, 이 묶음은 건너뛴다.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc=0
for p in test-choice-questions-a.sh test-choice-questions-b.sh test-choice-questions-c.sh; do bash "$HERE/$p" || rc=1; done
exit "$rc"
