# Changelog

이 저장소의 변경사항을 기록합니다. [Semantic Versioning](https://semver.org/lang/ko/) 규칙을 따릅니다.

## [0.3.0] — 2026-04-29

### 핵심 — PR 비디오 자동 첨부 (Playwright 자동 + Orphan 브랜치)

리뷰어가 코드를 안 보고도 "진짜 동작하는지" 확인할 수 있도록 **테스트 실행 비디오를 PR body 에 자동 임베드**. PR 브랜치 git history 를 더럽히지 않도록 별도 `scv-attachments` orphan 브랜치 경유 + 머지 후 N일 자동 삭제.

### Added

- **`scripts/lib/attachments.sh`** (신규, ~310 라인) — backend abstraction layer
  - Public API: `attachments_upload`, `attachments_cleanup_stale`, `attachments_status`
  - 백엔드 dispatch (`SCV_ATTACHMENTS_BACKEND` 환경변수): `git-orphan` (default, v0.3 구현) / `s3`, `r2` (v0.4 stub — 현재는 git-orphan fallback + warning)
  - `git-orphan` 백엔드: orphan 브랜치 worktree 분리 체크아웃 → 비디오 commit + push → 로컬 파일 삭제 → GitHub raw URL 반환
  - manifest.json 으로 slug ↔ PR 번호 매핑 추적
  - `attachments_cleanup_stale`: `gh pr view` 로 mergedAt/closedAt 조회 → retention 일수 지난 entry 자동 삭제 (self-amortizing — 매 pr-helper 호출 시 함께 진행, cron 인프라 불요)
  - 크기 가드: 50MB+ WARN, 100MB+ 거부 (git push 실패 방지)

- **Playwright 자동 video 설정** — `commands/work.md` Step 5b 신설
  - `playwright.config.{ts,js,mjs,cjs}` 자동 감지
  - `video:` 미설정/`'off'` 시 AskUserQuestion (default Yes) → Yes 선택 시 Claude 가 `Edit` 으로 한 줄 추가
  - 한 번 설정하면 영구 (이후 호출엔 안 뜸)

- **PR 비디오 자동 첨부 흐름** — `commands/work.md` Step 9d 확장
  - **Step 9d-prep** — `.env` 에 `SCV_ATTACHMENTS_RETENTION_DAYS` 가 없으면 한 번만 AskUserQuestion: 3일 (기본) / 7일 / 30일 / Never. 답변을 `.env` 에 저장.
  - **Step 9d-main** — `gh pr create` 후 `attachments_upload` → `gh pr edit` 으로 placeholder 교체 패턴. PR body 에 GitHub raw URL markdown 임베드 → PR 페이지에서 inline 재생.

- **`/scv:status` 에 `[scv-attachments]` 섹션** — backend, retention, active/stale/total size 표시

### Changed

- **`scripts/pr-helper.sh`** — `lib/attachments.sh` 호출 + 비디오 수집 (.webm/.mp4) + Test evidence 섹션 (Videos + Screenshots) + create-then-edit 흐름. dry-run 출력에도 비디오 경로 + 예상 raw URL 패턴 표시.
- **`scripts/status.sh`** — `[scv-attachments]` 신규 섹션. `lib/attachments.sh::attachments_status` 호출.
- **`template/scv/TESTING.md §3.3`** (신설) — PR 비디오 자동 첨부 안내 + .env 설정 예시.
- **`template/scv/PROMOTE.md`** — TESTS.md 작성 가이드에 비디오 증거 자동 첨부 한 단락.
- **`template/.env.example.scv`** — `SCV_ATTACHMENTS_BACKEND` · `SCV_ATTACHMENTS_RETENTION_DAYS` · `SCV_ATTACHMENTS_BRANCH` env vars 추가.

### Tests

- `tests/run-dry.sh` 새 섹션 [11ee–11ll] 8개. 330 → **357 PASS** (+27 assertion). 0 FAIL.
- 검증 영역: pr-helper 비디오 감지 · URL 파싱 (3 형식 + non-GitHub 거부) · 백엔드 dispatch + s3/r2 stub · 크기 가드 · cleanup with mock gh CLI · Step 5b/9d-prep/9d-main content.

### 비채택 (의도적, 후속 버전)

- **CDP MCP 기반 화면 녹화**: MCP 도구 없음. Playwright 만 지원. v0.4 이상에서 검토.
- **`s3` / `r2` 백엔드 실제 구현**: v0.3 은 abstraction + stub 만. v0.4 에서 `_attachments_s3_*` / `_attachments_r2_*` 본문.
- **GitLab / Bitbucket / Gitea 지원**: v0.4. `lib/pr-platform.sh` 추상화 도입 예정.
- **`attachments_status` 의 stale 정확 카운트**: v0.3 에선 `?` (gh API 호출 부담). v0.4 캐싱 후 정확 표시.
- **자동 GIF 합성 (스크린샷 시퀀스 → GIF)**: v0.5+ 후보.

## [0.2.1] — 2026-04-28

### Added — Fast-path 가이드 (작은 변경 전용)

`template/scv/PROMOTE.md` 에 새 **§1.6 Fast-path — promote 없이 직접 PR** 섹션 신설.

배경: `DISCUSS.md` 의 6 페르소나 시뮬레이션 토론에서 **만장일치로 합의된 약점**. 옹호·반대 양쪽 모두 "5 분짜리 오타 수정에 18 분짜리 PLAN 작성을 강요하는 건 과한 의례" 라는 점에 동의했고, 이 fast-path 가 명문화되면 도구 시도 의지가 50% → 70% 로 오를 거라고 토론 중 박민수 (반대) 가 명시.

### 추가된 내용

- **Fast-path 기준 체크리스트 4개** — 모두 만족할 때만 정식 루프 우회 가능. 기본값은 항상 "정식 promote 루프".
- **✅/❌ 구체 예시 표** — 오타 수정·의존성 패치·hotfix 같은 fast-path OK 사례 vs 새 feature·refactor·DB schema 변경 같은 정식 루프 사례.
- **안전망 명시** — fast-path 는 **PLAN/TESTS 작성을 건너뛰는 것이지 검증을 건너뛰는 게 아니라는 점** 강조. GitHub PR 리뷰 + `/scv:regression` 의 archived TESTS + 프로젝트 CI 가 그대로 작동.
- **"의심스러우면 promote" 기본 원칙** — 경계가 모호하면 비용이 약간 더 들더라도 정식 루프 가는 게 장기적으로 옳음.

### Tests

- `tests/run-dry.sh` `[11dd]` 섹션 신규. 324 → **330 PASS** (+6 assertion). 0 FAIL.

### 비채택 (의도적 — DISCUSS.md 권장 #2~#5)

토론에서 도출된 다른 4 개 권장은 데이터·privacy·우선순위 사유로 미채택:

| 권장 | 사유 | 시점 |
|---|---|---|
| Onboarding 가이드 | 데이터 기반 작성을 위해 4 주 회고 후 | v0.3.0 후보 |
| 회귀 evict 정책 | 6 개월 후 archive 누적 데이터 보고 결정 | 6 개월 후 재검토 |
| Telemetry opt-in | privacy 검토 필요 | v0.4.0 또는 v1.0 |
| Prototype 단계 모호-테스트 옵션 | 의견 분기 (1 강한 반대 + 2 강한 옹호). 더 사례 필요 | v0.3.0 후보 |

자세한 토론 내용은 저장소 루트 `DISCUSS.md` 참조.

## [0.2.0] — 2026-04-28

### 핵심 — 거대 요구의 epic 분할 + 단위 PR + 통합 refactor

타 회사 팀의 실제 사례 (10명 중 6명이 미검증 코드를 PR, 하루 50개 PR 폭증, 시간 압박 머지로 회귀 폭주) 를 들으며 정리한 v0.2.0. **새 슬래시 커맨드 0개 · 새 사용자 표면 플래그 0개**. 모든 변화는 frontmatter 스키마 + AskUserQuestion 흐름 + 문서로.

### Added

- **거대 feature 자동 분할 제안** (`/scv:promote`)
  - `promote-helper.sh` 가 raw 자료 양 (파일 수 > 7) + 토픽 다양성 (top-level cluster ≥ 3) 시그널 출력 (`SUGGEST_SPLIT`, `SPLIT_REASON`)
  - 시그널이 yes 면 `commands/promote.md` Step 3.0 에서 `AskUserQuestion` 로 분할 vs 단일 선택. 자동 분할은 절대 안 함 — 항상 사용자 확인.
  - 분할 시 여러 promote 폴더가 같은 `epic: <slug>` frontmatter 로 묶임. **분할 갯수는 고정값이 아니라 raw 자료의 실제 내용에 맞춰 Claude 가 적절한 N 을 제안 + 사용자 조정** — 작은 자료면 2~3개, 큰 자료면 더 많이.

- **PLAN.md frontmatter 확장** (공개 스키마)
  - `epic: <slug>` — 거대 요구를 N 개로 쪼갰을 때 동일 epic 으로 묶기
  - `kind: feature | refactor | retirement` — feature(기본) / 통합 정리 / 순수 제거

- **`/scv:status` 에 epic 진척도 표시**
  - `[epics]` 섹션이 archive + promote 의 PLAN.md 를 epic 별로 집계
  - 출력: `… epic <slug>: 4/7 archived, 2 in promote, refactor pending`
  - 상태 아이콘 — `…` (진행 중) · `!` (refactor 필요) · `✓` (epic 완료)

- **`/scv:work` Step 9d — PR 자동 생성** (스크린샷 첨부)
  - archive 후 `AskUserQuestion`: "PR 만들까요?" (default Yes)
  - Yes 시 `scripts/pr-helper.sh` 가 PLAN/TESTS/ARCHIVED_AT 조립 → PR body markdown
  - `test-results/` 의 PNG 스크린샷을 `.scv-pr-artifacts/<slug>/` 로 이동 (test-results 정리 + git committable 위치)
  - PR body 에 markdown 이미지로 임베드 (GitHub blob URL)
  - `epic` 있으면 base = `epic/<epic-slug>`, 없으면 origin/HEAD. epic 브랜치 없으면 origin/main 에서 자동 생성.
  - `gh pr create` 호출 + PR URL 출력
  - **비디오 첨부는 v0.3.0** 으로 (GitHub API 한계상 외부 스토리지 또는 사용자 drag-drop 필요 — 정식 자동화 설계 후 도입)

- **`/scv:work` Step 9e — Epic 완료 시 refactor 자동 안내**
  - epic 의 모든 feature 가 archive 되고 refactor 가 아직 없으면 `AskUserQuestion`: "refactor PLAN scaffold 만들까요?"
  - Yes 시 `scv/promote/<TODAY>-<author>-<epic-slug>-refactor/` 자동 생성, frontmatter `kind: refactor` + `epic: <epic-slug>`

- **`/scv:regression` — `CI=true` 환경변수 자동 감지**
  - `--ci` 플래그 명시 없이도 GitHub Actions / GitLab CI / CircleCI / Jenkins 환경에서 자동으로 non-interactive 모드. 산업 표준 `CI=true` 를 따름.

### Changed — 사용자 표면 플래그 숨김

전체 22 플래그 중 사용자에게 노출되는 건 0 개로 줄임. 코드는 그대로 유지 (Claude ↔ 스크립트 내부 API). 사용자 멘탈 모델 = "슬래시 7개 + 대화" 만.

- **`commands/*.md` 의 `argument-hint`** — 모든 플래그 제거. 위치 인자만 남김. 7 개 커맨드 일괄.
- **README 3개 언어 슬래시 커맨드 표** — 플래그 노출 모두 제거. "외울 플래그 없음 / 覚えるフラグなし / No flags to memorize" 가이드 문구.
- **TESTING.md §3 CI 통합** — `CI=true` 자동 감지 강조. 더 자세한 GitHub Actions 예시 (env, schedule, upload-artifact). PR merge gate 활용 안내.

### Spec 문서 추가

- **PROMOTE.md §8d** — Epic 브랜치 전략. PR base = epic/<slug>, main 직행 금지, refactor 가 epic 의 종료 조건.
- **PROMOTE.md §8e** — Refactor PLAN 패턴. `kind: refactor` + epic 동일. 통합 시점 발견된 정리 항목들을 한 PR 로.
- **PROMOTE.md §4 frontmatter 표** — `epic` · `kind` 필드 행 추가, YAML 예시도 갱신.
- **PROMOTE.md §9 status 전이** — kind 별 흐름 명시.

### Tests

- `tests/run-dry.sh` 새 섹션 [11v–11cc] 8개. 277 → **324 PASS** (+47 assertion). 0 FAIL.
- 검증 영역: split heuristic 시그널 (`SUGGEST_SPLIT`/`RAW_TOPIC_CLUSTERS`) · `kind` validator (수락/거절) · `/scv:status` epic 진척도 · `pr-helper.sh` dry-run body 조립 + kind 별 title prefix · `regression.sh` `CI=true` 자동 감지 · PROMOTE.md `§8d`/`§8e` content · work.md `Step 9d`/`9e` content · 모든 `argument-hint` 가 flag-free.

### 비채택 (의도적)

- **CI gate turnkey 워크플로 파일 자동 시드** — 팀마다 CI 환경 차이가 커서 generic 템플릿이 fit 안 함. 대신 TESTING.md §3 의 자세한 GitHub Actions 예시로 충분.
- **`/scv:pr` 신설 슬래시 커맨드** — `/scv:work` Step 9d AskUserQuestion 으로 충분. 슬래시 카운트 7 유지.
- **`/scv:work --pr` 같은 신설 플래그** — 같은 이유로 미채택. AskUserQuestion 패스.
- **비디오 첨부 자동화** — GitHub PR 첨부 공식 API 부재. v0.3.0 에서 외부 스토리지 등 정식 설계.

### 마이그레이션

기존 PLAN.md 는 `epic`/`kind` 없이도 그대로 작동 (둘 다 optional). 새 분할/refactor 흐름은 `/scv:promote` 가 raw 분석 후 자동 제안하므로 사용자 행동 변화 없음.

## [0.1.0] — 2026-04-28

### 첫 공개 릴리즈

SCV (Standard · Cowork · Verify) — Claude Code 용 팀 협업 워크플로 플러그인의 첫 공개 버전.

이 0.1.0 은 비공개 dogfooding 단계 (1.x ~ 2.x) 을 거쳐 정리된 결과물의 첫 외부 노출입니다. 핵심 워크플로·슬래시 커맨드·문서 규약은 충분히 안정화되어 채택 가능한 수준이며, `0.x` 버전대는 사용자 피드백을 받아 1.0 안정 API 를 확정하기 위한 단계입니다.

### Highlights

**핵심 컨셉 — Standard · Cowork · Verify**

| 글자 | 의미 | 무엇을 하나 |
|---|---|---|
| **S** | Standard | 표준 문서를 Claude 와 **대화로 채움** |
| **C** | Cowork | 회의록·자료를 `scv/raw/` 에 던지면 주제별로 정리 → `scv/promote/` 승격 → 구현 → archive |
| **V** | Verify | `/scv:regression` 으로 archived TESTS 누적 회귀 + Slack/Discord 자동 보고 |

**슬래시 커맨드 7개**

- `/scv:help` — 현재 상태 진단 + 다음 액션 추천
- `/scv:status` — `scv/raw/` 변경 + 활성 promote 계획 + docs graph 상태
- `/scv:promote` — `scv/raw/` → `scv/promote/<YYYYMMDD>-<author>-<slug>/` 정제 (PLAN.md + TESTS.md scaffold)
- `/scv:work` — promote 계획 구현 → TESTS 실행 → 통과 시 archive 이동 + supersede 전파
- `/scv:regression` — `scv/archive/**/TESTS.md` 누적 회귀 실행 + 3-way triage (regression / obsolete / flaky)
- `/scv:report` — Slack/Discord 에 Phase 결과 자동 보고
- `/scv:sync` — 플러그인 업데이트를 내 프로젝트에 안전 병합

**두 가지 hydrate 모드**

- **adoption (기본)** — 기존 프로젝트에 얹기. 표준 문서 `status: N/A` 로 시드 → INTAKE 강제 없이 `/scv:promote` / `/scv:work` 즉시 사용 가능. 필요한 subsystem 만 scope 좁혀 단계적 문서화.
- **`--new` (greenfield)** — 신규 프로젝트. 표준 문서 `status: draft` 로 시드 → `/scv:help` 가 INTAKE 프로토콜로 DOMAIN/ARCHITECTURE 등을 대화로 채우도록 안내.

**테스트 노후화 처리 (`supersedes`)**

PLAN.md frontmatter 에 `supersedes: [<old-slug>]` 또는 `supersedes_scenarios: ["<slug>:T<n>"]` 선언 → `/scv:regression` 이 자동 skip. archived TESTS.md 본문은 **영구 불변**, obsolete 마킹은 PLAN.md frontmatter 3 필드 (`status: obsolete`, `obsoleted_at`, `obsoleted_by`) 만 수정하는 최소 침습. archive 시점 `AskUserQuestion` 으로 자동 전파 (default Yes, 옵션 description 에 효과 상세 안내).

**3개 언어 README**

영어·한국어·일본어 단일 README 로 GitHub `<details>` 탭 구조. Quick Start 4 줄 설치 명령은 모든 경우(첫 설치/업데이트/재설치)에 동일.

**비파괴 hydrate**

루트 `CLAUDE.md` · `.env.example` · 기존 `.gitignore` 등을 절대 건드리지 않음. SCV 는 `scv/` 디렉토리만 소유하고, notifier 변수는 별도 `.env.example.scv` 로 분리.

**Architecture multi-perspective**

`scv/ARCHITECTURE.md` 가 단일 시각이 아닌 관점 체크리스트 (필수 2개: Logical, Deployment + 선택 8개: Data, Network, Security, Compliance, DR/BCP, AI/ML, Hardware, Observability). 한국 금융권 등 폐쇄망·규제 도메인 대응. Mermaid + `scv/architecture/assets/` (.drawio/.png/.svg) 다이어그램 지원.

**Notifier 이벤트**

`phase-complete`, `e2e-failure`, `daily-summary`, `error-alert`, `regression-summary`, `regression-failure` 6 이벤트. Slack/Discord 자동 라우팅, 채널 매핑 가능.

### 알려진 한계 (1.0 까지 정리할 항목)

- `/ralph-loop` 는 외부 커맨드 (별도 `~/.claude/ralph-template.md` 설정 필요). SCV 가 자체 제공하지 않음.
- INTAKE 프로토콜의 자동 resume 판정은 사용자 A/B 확인을 거치도록 보수적으로 동작. 더 매끄러운 UX 가능성 검토 중.
- multi-author 협업 시 promote 폴더 충돌 회피는 `<YYYYMMDD>-<author>-<slug>` 컨벤션에만 의존. 동일 작성자가 동일 날짜에 동일 slug 를 만들면 충돌 — `/scv:promote` 가 `<slug>-v2` 자동 제안.

### 설치

```
/plugin marketplace add https://github.com/wookiya1364/scv-claude-code
/plugin install scv@scv-claude-code
/reload-plugins
```

`/scv:help` 한 줄로 시작.

### 라이선스

MIT.
