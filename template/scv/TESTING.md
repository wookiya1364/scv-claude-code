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

CI 환경에서는 `regression.sh` 가 **`CI=true` 환경변수를 자동 감지**해서 non-interactive 모드로 동작합니다 (GitHub Actions · GitLab CI · CircleCI · Jenkins 모두 자동 세팅). `--ci` 같은 플래그를 명시할 필요 없음. 실패 시 exit 2, `test-results/regression-summary.json` 자동 생성.

**GitHub Actions 예시** (`.github/workflows/scv-regression.yml`):

```yaml
name: SCV regression

on:
  pull_request:
  schedule:
    - cron: '0 18 * * *'   # 매일 03:00 KST nightly

jobs:
  regression:
    runs-on: ubuntu-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4    # 또는 setup-python, setup-go 등
        with:
          node-version: 20
      - run: npm ci
      # SCV 플러그인을 CI 에 함께 두려면 git submodule 또는 cache add
      - name: Run SCV accumulated regression
        env:
          # CI=true 는 GitHub Actions 가 자동 세팅 → --ci 모드 자동 활성화
          # SCV 가 인식할 수 있게 플러그인 경로만 알려주면 끝
          CLAUDE_PLUGIN_ROOT: ${{ github.workspace }}/.scv-plugin
        run: |
          bash "$CLAUDE_PLUGIN_ROOT/scripts/regression.sh"
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: regression-summary
          path: test-results/regression-summary.json
```

PR 머지 게이트로 만들려면 위 workflow 의 `regression` job 을 GitHub branch protection rule 의 "Required status checks" 에 추가. 회귀 실패 시 머지 차단됨.

**Tip — supersedes 의 효과**: 새 feature 가 옛 feature 를 의도적으로 바꾼 경우, 옛 feature 의 archived TESTS 가 자동으로 깨지는 게 정상입니다. PLAN.md 의 `supersedes: [<옛-slug>]` 한 줄로 회귀 runner 가 자동 skip — 이게 **시간 압박 머지** 를 막으면서도 **노후화** 는 명시적으로 처리하는 핵심.

#### 3.3 PR 비디오 자동 첨부 (v0.3+)

`/scv:work` Step 9d 가 PR 을 만들 때, **테스트 실행 비디오** 를 PR body 에 자동 임베드합니다 — 리뷰어가 코드 안 보고도 "진짜 동작하는지" 영상으로 확인 가능.

**자동화되는 것**:
- Playwright 프로젝트라면 SCV 가 `playwright.config.{ts,js,mjs,cjs}` 자동 감지 + `video: 'on'` 자동 추가 권장 (Step 5b 의 AskUserQuestion). 한 번 Yes 하면 영구 적용.
- 테스트 시 .webm 이 `test-results/` 에 자동 생성됨 (Playwright 표준 동작).
- Step 9d 에서 PR 생성 시 그 비디오들이 **`scv-attachments` orphan 브랜치** 로 push (작업 브랜치 git history 영향 0). PR body 에 GitHub raw URL 로 markdown 임베드 → PR 페이지에서 inline 재생.
- 로컬 비디오 파일은 push 후 즉시 삭제 (디스크 정리).
- PR 머지 + 사용자 지정 N 일 (default 3) 후 orphan 브랜치에서 자동 삭제 (manifest.json + `gh pr view` 기반 self-amortizing cleanup).

**.env 설정** (선택, 기본값 그대로 두면 OK):
```
SCV_ATTACHMENTS_BACKEND=git-orphan         # 기본. v0.4 부터 s3 · r2 추가 예정
SCV_ATTACHMENTS_RETENTION_DAYS=3           # 머지 후 보관 일수. 'never' 가능
```

비-Playwright 프로젝트 (Cypress / 백엔드 테스트만) 는 비디오 없이 진행 — PR 에 스크린샷만 첨부됨.

#### 3.4 테스트 노후화 처리 (회귀와의 구분)

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
