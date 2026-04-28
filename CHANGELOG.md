# Changelog

이 저장소의 변경사항을 기록합니다. [Semantic Versioning](https://semver.org/lang/ko/) 규칙을 따릅니다.

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
