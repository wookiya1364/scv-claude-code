---
name: testing
version: 1.0.0
status: draft
last_updated: 2026-04-17
applies_to: []
owners: ["@team-qa"]
tags: [standard, core, testing]
standard_version: 1.0.0
merge_policy: merge-on-markers
---

# TESTING — 품질 검증 규약

> Claude 는 `INTAKE.md` 단계 5 와 아래 `How to elicit` 를 따라 사용자에게 물어 채웁니다.
> 이 문서의 일부(아티팩트 경로 규칙)는 템플릿 기본값으로 고정됩니다.

## How to elicit (Claude 가 물어볼 순서)

1. **테스트 피라미드 비중**: "unit/integration/e2e 비중 목표가 있나요?"
2. **Mock 정책**: "integration 테스트에서 DB/외부 의존성을 **mock 할지, 실제 의존성에 연결할지**?" (권장: 실제)
3. **E2E 도구**: "UI 가 있다면 E2E 도구가 정해졌나요? (기본: Playwright + Chrome DevTools MCP)"
4. **E2E 대상 시나리오**: "DOMAIN.md 의 어느 유스케이스를 E2E 로 커버하나요?" (최소 1개)
5. **확률적 부분 검증**: "AI 에이전트가 있다면 확률적 응답을 어떻게 E2E 에서 다루나요?" (AGENTS.md 의 분포 테스트 재사용)
6. **CI 통합**: "어느 시점에 테스트가 실행되어야 하나요?" (PR / main 머지 / 야간)
7. **실패 정책**: "어떤 실패가 머지 블록인가요? (통과율 임계치, p95 등)"

## Completion criteria

- [ ] 테스트 피라미드 비중 결정
- [ ] Mock 정책 명시
- [ ] E2E 도구 확정 (또는 "UI 없음" 표시)
- [ ] E2E 시나리오 최소 1개 (UC-코드 참조)
- [ ] CI 트리거 지점 합의
- [ ] 실패 정책 명시
- [ ] 사용자 확인

## 아티팩트 경로 규칙 (템플릿 고정)

> 이 섹션은 `/scv:report` 의 `collect-artifacts.sh` 가 의존하는 **계약**입니다. 변경 시 스크립트도 함께 변경해야 합니다.

| 종류 | 경로 패턴 | 비고 |
|---|---|---|
| 스크린샷 | `test-results/**/*.png` | 최근 수정 시간 기준 |
| 비디오 | `test-results/**/*.{webm,mp4}` | 실패 테스트 |
| 트레이스 | `test-results/**/trace.zip` | 선택 |
| MCP 아티팩트 | `test-results/mcp/**` | 수동 시나리오 |
| 로그 | `test-results/logs/*.log` | 실패 시 tail 20KB |
| JSON 결과 | `test-results/results.json` | summary 추출 |

**아티팩트가 없으면**: `/scv:report` summary 에 `[아티팩트 없음: <사유>]` 명시.

## Playwright 설정 권장값 (UI 프로젝트용)

```ts
export default defineConfig({
  outputDir: 'test-results/',
  reporter: [
    ['list'],
    ['html', { outputFolder: 'test-results/report', open: 'never' }],
    ['json', { outputFile: 'test-results/results.json' }],
  ],
  use: {
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
});
```

## Chrome DevTools MCP 사용 규약

- 스크린샷: `test-results/mcp/<YYYYMMDD>-<slug>.png`
- 성능 트레이스: `test-results/mcp/trace-<slug>.json`
- 콘솔 로그: `test-results/mcp/console-<slug>.log`

## Structure

### 1. 테스트 피라미드

| 레이어 | 비중 목표 | 도구 |
|---|---|---|
| unit | <TODO> | ... |
| integration | <TODO> | ... |
| e2e | <TODO> | ... |

### 2. Mock 정책

<TODO: 어디까지 mock, 어디부터 실제 의존성. 사유.>

### 3. CI 통합 + 회귀 전략

SCV 는 두 축의 테스트 실행을 구분합니다.

| 축 | 커맨드 | 시점 | 범위 |
|---|---|---|---|
| 개별 계획 검증 | `/scv:work <slug>` | 구현 직후 | 해당 `scv/promote/<slug>/TESTS.md` 하나 |
| 누적 회귀 | `/scv:regression` | archive 전 · nightly · 릴리즈 전 | `scv/archive/**/TESTS.md` (+ `--include-promote` 시 promote 도) |

#### 3.1 로컬 workflow

- 새 계획 구현 중: `/scv:work` 가 해당 TESTS 만 실행 (빠름).
- archive 직전: `/scv:work` 의 Step 9a 에서 "archived 회귀도 돌릴까요?" AskUserQuestion → Yes 선택 시 `/scv:regression` 이 pre-flight 로 돌아가며 `supersedes` 선언된 slug 는 자동 skip.
- 주 1회 또는 릴리즈 전: 사용자가 수동으로 `/scv:regression` (또는 `/scv:regression --tag core` 로 범위 축소).

#### 3.2 CI 통합 예시

CI 파이프라인 단계에서 `--ci` 모드로 호출하면 AskUserQuestion 없이 exit code 로 pass/fail 을 판정. 실패 시 exit 2, `test-results/regression-summary.json` 이 생성됩니다.

```yaml
# 예: .github/workflows/regression.yml
- name: SCV full regression
  run: bash "$CLAUDE_PLUGIN_ROOT/scripts/regression.sh" --ci
```

#### 3.3 테스트 노후화 처리 (회귀와의 구분)

새 기능이 **의도적으로** 기존 동작을 바꿀 때의 3 경로 (자세히는 `scv/PROMOTE.md §8b`):

1. **사전 선언** — 새 PLAN.md 에 `supersedes: [<old-slug>]` 또는 `supersedes_scenarios: ["<slug>:T<n>"]`.
2. **자동 전파** — 선언이 있으면 `/scv:work` Step 9c 가 archive 시점에 옛 slug 를 obsolete 로 마킹할지 묻고 (default Yes) 승인 시 옛 PLAN.md frontmatter 만 수정.
3. **런타임 triage** — `/scv:regression` 실패 시 slug 별 3-way AskUserQuestion: regression (코드 수정) / obsolete (지금 마킹) / flaky (재시도).

`status: obsolete` 로 마킹된 slug 는 이후 회귀 실행에서 자동 제외되며 (`--include-obsolete` 플래그로만 포함), archived TESTS.md 는 **영원히 수정되지 않습니다** (불변 archive 원칙).

### 4. 실패 정책

<TODO: 머지 블록이 되는 실패 종류.>

### 5. E2E 시나리오 카탈로그

<!-- PROJECT:LOCAL START -->
<!-- 이 블록은 sync 시 보존됩니다. 프로젝트별 E2E 시나리오를 여기에 작성하세요. -->

<TODO: E2E-001, E2E-002 형태. 각 시나리오마다 선행조건·스텝·성공 기준·아티팩트 저장 위치.>

<!-- PROJECT:LOCAL END -->

## 관련 모듈

<!-- MODULES:AUTO START applies_to=testing -->
<!-- MODULES:AUTO END -->
