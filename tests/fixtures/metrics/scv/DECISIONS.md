# DECISIONS — fixture

## [YYYY-MM-DD HH:MM] <author> — <제목>

- verdict: adopted | archived | obsolete | needed | maybe | not-needed | lesson
- refs: scv/promote/TEMPLATE/PLAN.md

## [2026-09-01 10:00] tester — P1 승인

- verdict: adopted
- why: fixture
- refs: scv/promote/P1/PLAN.md

## [2026-09-02 12:30] tester — P1 보관

- verdict: archived
- why: fixture
- path delta: as planned
- refs: scv/archive/P1/PLAN.md

## [2026-09-03 08:00] tester — P2 승인

- verdict: adopted
- why: adopted 만 — 리드타임 none
- refs: scv/promote/P2/PLAN.md

## [2026-09-10 09:00] tester — P4 승인

- verdict: adopted
- why: fixture
- refs: scv/promote/P4/PLAN.md

## [2026-09-10 09:45] tester — P4 보관

- verdict: archived
- why: fixture
- path delta: as planned
- refs: scv/archive/P4/PLAN.md

## [2026-09-11 10:00] tester — 손으로 쓴 refs

- verdict: archived
- why: refs 가 promote/archive 경로가 아니다 — unmatched
- refs: https://example.invalid/pr/1

## [2026-09-12 10:00] tester — 계획과 무관한 교훈

- verdict: lesson
- why: adopted/archived 가 아니면 리드타임에 들지 않는다
- refs: scv/archive/P1/PLAN.md
