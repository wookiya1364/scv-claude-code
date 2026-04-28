---
name: reporting
version: 1.0.0
status: draft
last_updated: 2026-04-17
applies_to: []
owners: ["@team"]
tags: [standard, core, reporting]
standard_version: 1.0.0
merge_policy: merge-on-markers
---

# REPORTING — 협업툴 보고 규약

> 이 문서는 **설정**에 가깝습니다. Claude 는 `INTAKE.md` 단계 6 에서 사용자의 협업툴과 채널을 확인한 뒤 `PROJECT:LOCAL` 블록에 기록합니다.

## How to elicit (Claude 가 물어볼 순서)

1. **협업툴 선택**: "팀이 쓰는 협업툴은 Slack / Discord 중 어느 것인가요?"
2. **Bot 생성 여부**: "Bot App 이 이미 존재하나요? 없으면 먼저 생성·초대해야 합니다."
3. **채널 매핑**: "다음 이벤트별 채널을 어떻게 쓸 건가요?"
   - `phase-complete` — Phase 완료 보고
   - `e2e-failure` — E2E 실패
   - `daily-summary` — (선택) 일일 요약
   - `error-alert` — (선택) 크리티컬
4. **메시지 포맷 특이사항**: "기본 포맷 외 추가 필드·아이콘·멘션 규칙이 있나요?"

## Completion criteria

- [ ] `NOTIFIER_PROVIDER` 결정 (slack | discord)
- [ ] Bot 토큰 발급·채널 초대 완료
- [ ] 최소 `phase-complete`, `e2e-failure` 채널 ID 확보
- [ ] `.env` 에 토큰·채널 ID 기입
- [ ] `/scv:report` dry-run 1회 성공
- [ ] 사용자 확인

## 보고 원칙 (템플릿 고정)

- Ralph Loop 는 직접 HTTP 호출 금지. 항상 `/scv:report <phase> <status>` 슬래시 커맨드 경유
- 모든 보고에 **시각적 아티팩트 1개 이상** 첨부 (없으면 summary 에 `[아티팩트 없음: 사유]` 명시)
- 성공·실패·중간 보고는 **동일 thread** 로 묶인다

## 이벤트 → 채널 매핑 (템플릿 규약)

| 이벤트 | 트리거 | 환경 변수 (기본 채널) |
|---|---|---|
| `phase-complete` | `passed` | `<PROVIDER>_CHANNEL_ID_PHASE_COMPLETE` |
| `e2e-failure` | `failed` | `<PROVIDER>_CHANNEL_ID_E2E_FAILURE` |
| `daily-summary` | `--event daily-summary` | `<PROVIDER>_CHANNEL_ID_DAILY_SUMMARY` |
| `error-alert` | `--event error-alert` | `<PROVIDER>_CHANNEL_ID_ERROR_ALERT` |
| `regression-summary` | `--event regression-summary` (주기적 회귀 통과 알림) | `<PROVIDER>_CHANNEL_ID_REGRESSION_SUMMARY` |
| `regression-failure` | `--event regression-failure` (archived 중 일부 깨짐 — triage 필요) | `<PROVIDER>_CHANNEL_ID_REGRESSION_FAILURE` |
| `info` | `info` | `<PROVIDER>_CHANNEL_ID_PHASE_COMPLETE` (재사용) |

환경변수가 없으면 `<PROVIDER>_CHANNEL_ID` (기본) 로 폴백.

## 첨부 규칙 (템플릿 고정)

| 상태 | 첨부 |
|---|---|
| `passed` | 스크린샷 + 비디오(있으면) |
| `failed` | 스크린샷 + 비디오 + 로그 tail (20KB) |
| `info` | 스크린샷 (있을 때만) |
| `regression-summary` | `test-results/regression-summary.json` + 사람이 읽을 summary 텍스트 (screenshot/video 없음) |
| `regression-failure` | 동일 JSON + 실패 slug 별 로그 tail (20KB 까지) |

모든 첨부는 본 메시지의 thread 로 이어붙임.

## 변수 치환 (템플릿 고정)

`render-template.sh` 가 치환:

| 변수 | 출처 |
|---|---|
| `{project}` | `.env` `PROJECT_NAME` |
| `{phase}` · `{status}` | 커맨드 인자 |
| `{git_short}` | `git rev-parse --short HEAD` |
| `{attempt}` · `{summary}` | 커맨드 인자 |
| `{duration}` | `test-results/results.json` |

## 이 프로젝트의 설정

<!-- PROJECT:LOCAL START -->
<!-- 이 블록은 sync 시 보존됩니다. 실 채널 ID 와 커스텀 규칙을 여기 작성하세요. -->

**협업툴**: <TODO: slack | discord>

**Slack 워크스페이스 / Discord 서버**: <TODO>

**Bot 이름**: <TODO>

**채널 ID 매핑** (실제 값은 `.env` 에, 여기는 문서용 참고):

| 이벤트 | 채널 이름 | 채널 ID |
|---|---|---|
| phase-complete | <TODO> | <TODO> |
| e2e-failure | <TODO> | <TODO> |

<!-- PROJECT:LOCAL END -->
