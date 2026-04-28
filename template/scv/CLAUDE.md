# scv/CLAUDE.md — SCV 워크플로 인덱스

> **이 파일은 SCV 워크플로 범위의 인덱스와 규칙입니다.** 프로젝트 루트의 `CLAUDE.md` 는 **SCV 가 건드리지 않으며** 사용자 소유입니다. SCV 가 필요한 맥락은 전부 `scv/` 안에 있습니다.

## 두 가지 hydrate 모드

SCV 는 hydrate 시점에 두 가지 모드를 지원합니다. **대부분의 경우 기본(adoption) 이면 충분**합니다.

### 기본 (adoption) — **권장 · 기존 프로젝트**

- `bash hydrate.sh init .` (플래그 없음)
- 표준 문서 (`DOMAIN`, `ARCHITECTURE`, `DESIGN`, `AGENTS`, `TESTING`, `REPORTING`, `RALPH_PROMPT`) 가 전부 `status: N/A` 로 시드
- **INTAKE 강제 없음**. `/scv:promote` / `/scv:work` 루프를 즉시 사용 가능
- 필요해지면 특정 subsystem 만 scope 좁혀 `draft → active` 로 단계적 문서화
- 외부 문서(Confluence 등) 있으면 `refs:` 로 연결

### `--new` (greenfield) — 신규 프로젝트

- `bash hydrate.sh init . --new`
- 표준 문서가 `status: draft` 로 시드
- `/scv:help` 가 `scv/INTAKE.md` 의 대화 프로토콜을 통해 모든 표준 문서를 하나씩 채우도록 안내
- 프로젝트를 zero 부터 정의할 때만 쓰세요

## 최상위 규칙 (불변)

1. **표준 문서가 `status: draft` 면 그 문서의 범위에 해당하는 구현 작업을 시작하지 않는다.** 먼저 `scv/INTAKE.md` 의 해당 단계를 돌려 사용자와 대화로 문서를 채운다.
   - **Adoption 모드에선 이 규칙이 발동하지 않습니다** (문서가 `N/A` 라서). 특정 subsystem 을 문서화하기로 결정해 `draft` 로 올린 경우에만 적용.
2. **추측 금지**: 사용자의 명시적 답변 없이 섹션을 채우지 않는다.
3. **한 번에 하나**: 섹션 하나 완성 → 사용자 확인 → 다음.

## 루트 CLAUDE.md 와의 관계

- 프로젝트 루트의 `CLAUDE.md` (있다면) 는 사용자의 **프로젝트 전체 규칙**. SCV 는 **절대 수정하지 않습니다**.
- SCV 의 루틴(슬래시 커맨드, sync, hydrate) 은 **이 `scv/CLAUDE.md` 와 `scv/` 하위 문서들만** 참조합니다.
- Claude 가 평소 대화에서도 SCV 를 인지하도록 하려면, 사용자의 루트 `CLAUDE.md` 에 아래 한 줄만 추가하세요 (선택):
  ```
  > This project uses SCV — see `scv/CLAUDE.md` for workflow details.
  ```

## 표준 문서

모든 SCV 문서는 `scv/` 디렉토리에 있습니다.

### 프로세스 (이 문서는 채우는 게 아니라 **읽고 따른다**)

| 문서 | 역할 |
|---|---|
| `scv/INTAKE.md` | 프로젝트 시작 시의 인터뷰 프로토콜. 다른 문서를 채우는 순서. |
| `scv/PROMOTE.md` | raw → promote → archive 승격 규약. 폴더명·PLAN/TESTS·Related Documents. |

### 필수 (모든 프로젝트)

| 문서 | 한줄 목적 |
|---|---|
| `scv/DOMAIN.md` | 용어·엔티티·불변 규칙·유스케이스 |
| `scv/ARCHITECTURE.md` | 서비스 경계·데이터 저장소·환경·비기능 요구사항 |
| `scv/TESTING.md` | 테스트 피라미드·E2E 시나리오·아티팩트 경로 계약 |
| `scv/REPORTING.md` | 협업툴 매핑 (Slack/Discord) 규약 |

### 조건부 필수

| 문서 | 조건 |
|---|---|
| `scv/DESIGN.md` | 사용자 대면 UI(웹/앱)가 있을 때 필수. 없으면 `status: N/A` |

### 선택

| 문서 | 조건 |
|---|---|
| `scv/AGENTS.md` | LLM/STT/TTS/분류기 등 **확률적 구성요소**가 있을 때만 |

### 설정 진입점

| 파일 | 역할 |
|---|---|
| `scv/RALPH_PROMPT.md` | Ralph Loop 실행 시 읽는 프로젝트별 설정 (focus_phase, 명령어 등) |

## 라우팅 — 작업 유형별 먼저 읽을 문서

- 프로젝트 시작 / 요구사항 정리 → `scv/INTAKE.md`
- 아키텍처·서비스 경계 → `scv/ARCHITECTURE.md`
- 도메인 규칙·용어 혼동 → `scv/DOMAIN.md`
- UI/UX → `scv/DESIGN.md` (해당 시)
- AI 에이전트 동작·확률적 응답 → `scv/AGENTS.md` (해당 시)
- 테스트 실패 분석·E2E 작성 → `scv/TESTING.md`
- 협업툴 알림·리포트 포맷 → `scv/REPORTING.md`

## 프로젝트 디렉토리 구조

```
project-root/
├── CLAUDE.md                     # 사용자 소유 (SCV 가 건드리지 않음) — 있어도 되고 없어도 됨
├── scv/                          # SCV 워크플로의 모든 문서·상태가 이 하위에
│   ├── CLAUDE.md                 # 이 파일 (SCV 인덱스)
│   ├── INTAKE.md                 # 대화 프로토콜
│   ├── PROMOTE.md                # 승격 규약
│   ├── DOMAIN.md ARCHITECTURE.md DESIGN.md AGENTS.md
│   ├── TESTING.md REPORTING.md
│   ├── RALPH_PROMPT.md
│   ├── readpath.json             # raw 변경 추적 스냅샷 (/scv:promote 가 자동 갱신)
│   ├── promote/                  # 승격된 주제·계획 문서
│   │   └── <YYYYMMDD>-<author>-<slug>/
│   │       ├── PLAN.md
│   │       ├── TESTS.md
│   │       └── (자유 확장 파일들)
│   ├── archive/                  # 구현 완료된 계획 (토큰 효율)
│   │   └── <YYYYMMDD>-<author>-<slug>/
│   │       ├── PLAN.md TESTS.md ...
│   │       └── ARCHIVED_AT.md    # 완료 기록 (자동 생성)
│   └── raw/                      # 자유 투입 공간 (회의록·스케치·PDF·녹화)
│       └── README.md
├── .env, .env.example, .gitignore
└── (프로젝트 고유 코드: src/, packages/, apps/ 등)
```

**큰 그림**: `scv/raw/` 에 자료를 자유롭게 던지고 → `/scv:promote` 가 정제해 `scv/promote/<slug>/` 생성 → `/scv:work <slug>` 이 구현·테스트 → 통과 시 `scv/archive/` 로 이동.

## 작업 절차

1. **INTAKE 완료 확인** — 모든 필수 문서의 `status` 가 `active` 인지. 하나라도 `draft` 면 INTAKE 해당 단계부터 진행.
2. 요구사항 이해 → 관련 표준 문서 읽기 → 필요 시 `scv/promote/` 아래 계획 문서 읽기
3. 구현 → 테스트 → 수정 루프 (`/scv:work <slug>` 또는 Ralph Loop)
4. Phase 완료 시 `/scv:report "<phase>" <status>` 호출 → 협업툴 전송

## 승격 문서

<!-- 이 섹션은 `scv/promote/` 하위 문서를 가리킵니다. 필요 시 수동으로 링크를 추가하세요. -->

## 이 프로젝트 고유 — SCV 범위 규칙

<!-- PROJECT:LOCAL START -->
<!-- 이 블록은 /scv:sync 시 절대 덮어쓰이지 않습니다. -->
<!-- SCV 워크플로에 특화된 프로젝트별 규칙을 여기에 적으세요 -->
<!-- (예: 승격 슬러그 접두어 정책, TESTS.md 필수 섹션 추가, Phase 네이밍 등). -->
<!-- 프로젝트 전체 규칙은 루트 CLAUDE.md 에 — 이 파일이 아닙니다. -->
<!-- PROJECT:LOCAL END -->

## SCV 템플릿 메타

- 템플릿 버전: <!-- STANDARD:VERSION -->1.0.0<!-- /STANDARD:VERSION -->
- 마지막 sync: <!-- STANDARD:SYNCED_AT -->UNSET<!-- /STANDARD:SYNCED_AT -->
- 협업툴 선택: `.env` 의 `NOTIFIER_PROVIDER` (slack | discord)
