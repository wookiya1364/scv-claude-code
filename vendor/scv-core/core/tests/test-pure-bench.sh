#!/usr/bin/env bash
# test-pure-bench.sh — 나눈 넷을 차례로 돌리는 묶음(지난 계획의 시험 명령이 이 이름을 부른다).
# scv-test: aggregate
# 조각: test-pure-bench-a.sh test-pure-bench-b.sh test-pure-bench-c.sh test-pure-bench-d.sh — CI 와 전체 시험은 조각을 따로 돌리고, 이 묶음은 건너뛴다.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
rc=0
for p in test-pure-bench-a.sh test-pure-bench-b.sh test-pure-bench-c.sh test-pure-bench-d.sh; do bash "$HERE/$p" || rc=1; done
exit "$rc"
