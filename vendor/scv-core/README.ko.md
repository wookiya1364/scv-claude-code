# SCV Core

[English](README.md) · [日本語](README.ja.md)

SCV Core는 Claude Code용 SCV와 Codex용 SCV가 함께 사용하는 호스트 중립
원본입니다. 워크플로 프로토콜, 실행 스크립트, 프로젝트 템플릿, DeckUI,
에셋, 공통 회귀 테스트를 이 저장소에서 관리합니다. 각 래퍼는 변경 불가능한
Core 릴리스를 고정하고, 검증된 호스트 프로필을 반영한 뒤 런타임별 어댑터만
추가합니다.

버전은 파일에 있으므로 이 문서는 낡지 않습니다.

| 계약 | 파일 | 의미 |
|---|---|---|
| SCV Core | [`VERSION`](VERSION) | 공통 동작과 릴리스 페이로드 |
| Core API | [`CORE_API`](CORE_API) | 래퍼와 코어의 통합 계약 |
| Template | [`TEMPLATE_VERSION`](TEMPLATE_VERSION) | hydrate되는 프로젝트 템플릿 스키마 |

가장 최근에 게시된 Core는
[릴리스 페이지](https://github.com/wookiya1364/scv-core/releases/latest)에 있습니다.
설치 가능한 플러그인은 다음 저장소에 있습니다.

- [Claude Code용 SCV](https://github.com/wookiya1364/scv-claude-code)
- [Codex용 SCV](https://github.com/wookiya1364/scv-codex)

## 구조

```text
scv-core 릴리스(변경 불가능한 tarball + SHA-256)
                  │
                  ├── scv-claude-code가 버전 고정 및 구체화
                  └── scv-codex가 버전 고정 및 구체화
                                      │
                                      └── 런타임 네트워크 요청 없이 로컬 실행
```

15개 SCV 액션 중 13개는 Core가 소유합니다. 설치 방식과 모델 선택은 호스트에
종속되므로 `update`, `set-models`는 어댑터가 소유합니다. 정규 프로토콜은
`action:<name>`과 `{{SCV_ARGS}}`를 사용하며, 실제 명령 문법과 인자 전달
방식은 검증된 호스트 프로필로만 주입됩니다. `scv/SCV.md`는 최상위 규칙과,
규칙끼리 부딪힐 때 무엇이 이기는지의 순서로 시작하며 모든 프로토콜이 이를
따릅니다.

### 매 턴

명령만이 입구가 아닙니다. 매 턴 훅이 일반 대화를 help 액션으로
라우팅하고(`SCV_ALWAYS_ON`, 기본 켬) 짧은 프로젝트 진단을 함께 실어, 모델이
상태를 다시 묻지 않고 실제 상태에서 출발하게 합니다. help 규약 전체는 세션당
한 번 읽습니다. 훅은 그 규약의 지문을 기억해 두었다가, 기록된 턴에서 지문이
사라지거나 답이 답 모양을 벗어나면 규약을 다시 싣습니다(`SCV_HELP_LOAD_ONCE`,
`SCV_HELP_RELOAD_EVERY`).

- **쉬운 말** — 답은 한두 문장의 결론으로 시작하고, 예시 하나를 들고, 코드 값은
  물어볼 때만 보입니다(`SCV_PLAIN_LANGUAGE`, `SCV_PLAIN_MAX_SENTENCES`).
  종료 훅이 답의 모양을 검사합니다(`SCV_ANSWER_LINT`).
- **모델별 프롬프팅** — 래퍼가 어떤 모델의 공식 프롬프팅 가이드(원문 그대로의
  오프라인 사본)를 싣고 있으면, help 는 컨텍스트마다 한 번 그 원문을 읽고 요청을
  그 모델에 가장 알맞은 프롬프트로 다시 씁니다. 매 턴 요청을 그 모델의 요구 항목
  목록과 하나씩 비교해 등록합니다 — 항목마다 가이드를 글자 그대로 인용하고,
  래퍼의 CI 가 인용을 검사합니다. 이번 턴이 등록되기 전의 파일 쓰기는 거절되고,
  등록이나 다시 쓴 요청 인용 없이 끝나는 턴은 한 번 막힙니다
  (`SCV_MODEL_PROMPTING`).
- **재개 요약** — 압축, `/clear`, 재개 뒤에 세션 시작 훅이 진행 중인 계획,
  최근 결정, 미결 항목, 진행 중인 대화를 다시 실어 줍니다(`SCV_RESUME_RECAP`).
  기록 하나는 이름으로 펼칩니다: `core/scripts/record-read.sh --key <name>`.
  호스트의 세션 시작 훅이 필요합니다.
- **배경 조사** — `SCV_DELEGATE_EFFORT=on`(기본 끔)이면 깊은 질문을 배경
  조사 담당에게 넘기고, 보고서는 `scv/raw/`에 남습니다. 세션의 모델과 사고량은
  바꾸지 않습니다. 호스트의 에이전트가 필요합니다.

프로젝트 설정은 `scv/scv_settings.json`(+ git 무시되는 비밀 파일)에 있으며,
모든 키가 설명과 함께 자동 생성됩니다. 프로젝트의 `.env` 는 읽지 않습니다.
모든 키와 기본값:
[`core/template/scv/scv_settings.example.json`](core/template/scv/scv_settings.example.json).

### 계획 · 증적 · 기록

- **그림으로 보는 계획** — 모든 계획서에는 순수함수 파이프라인 절이 있고, deck
  액션은 계획의 그림 문서(`FEATURE_ARCHITECTURE.md`)를 번호식 화면설계서로
  그립니다. 큰 그림 하나에 번호를 달고, 번호마다 설명을 옆에 두고, 검증 문구
  표를 붙이며, `PLAN.md`와 `TESTS.md`는 원문 탭으로 따라옵니다.
- **SCV 자체 그래프** — 문서 링크, 보관된 계획과 파일, 결정 참조, 함께 바뀌는
  파일을 promote 와 work 가 bash 와 jq 만으로 자동으로 다시 만듭니다. 설치할
  것이 없습니다(`SCV_GRAPH`). Graft 는 선택입니다. 설치돼 있으면 계획 · 구현
  머리말에 관련 코드 후보와 변경 영향 범위가 붙고(`SCV_GRAFT`), SCV 가 직접
  설치하지는 않습니다.
- **지난 작업 찾기** — help 의 회상 모드는 제목만이 아니라 계획 본문, 테스트,
  결정 로그, 대화까지 훑습니다
  ([`archive-search`](core/protocols/help/archive-search.md)).
- **결정** — `scv/DECISIONS.md`는 덧붙이기만 하는 기록이며, 계획 승인 · 보관 ·
  폐기 때와 도중에 얻은 교훈을 적습니다.
- **과정 계기판** — `core/scripts/metrics.sh`는 프로젝트의 기록(보관 색인,
  계획서, 대화, 결정)을 읽어 과정을 숫자로 보여 줍니다. 아무 파일도 쓰지
  않습니다.
- **증적** — PR 첨부는 파일 이름이 아니라 기록된 테스트 실행을 따르고, 브랜치당
  PR 은 하나이며, 같은 증적을 팀 채널로도 보낼 수 있습니다.

### 상태 인덱스와 DeckUI 캐시

공통 상태 인덱스는 항상 `scv/SCV.md`입니다. 이전 래퍼에서 전환하는 동안에는
`SCV.md`가 없을 때만 `CLAUDE.md` 또는 `CODEX.md`를 읽습니다. 서로 독립적인
상태 파일이 다르면 변경 작업인 sync는 아무 파일도 건드리지 않고 중단합니다.
두 래퍼는 Core가 소유하는 단일 resolver와 pointer finalizer를 사용하며,
호환 pointer는 정확한 `SCV:HOST-POINTER target=SCV.md` marker로만 판별합니다.

설치된 래퍼의 DeckUI 원본은 변경하지 않습니다. 의존성, 생성된 deck, 빌드 결과는
Core 페이로드 해시별 외부 캐시에 저장되므로 Claude Code와 Codex가 같은 런타임을
재사용하면서 어느 플러그인에도 쓰지 않습니다. 기본 사용자 캐시는
`SCV_DECK_CACHE_DIR`로 바꿀 수 있습니다.
캐시 초기화와 기존 런타임 마이그레이션은 동시에 생긴 목적지를 덮어쓰지 않고,
목적지 조상의 링크를 따라가지 않으며, 캐시와 기존 런타임 경로가 겹치면 쓰기
전에 중단합니다.
캐시 base, 페이로드 namespace, 런타임 target, lock, staging, install,
cleanup은 모두 검증된 열린 디렉터리 descriptor에 고정됩니다. 따라서 작업 중
경로나 조상이 바뀌어도 외부 경로로 쓰기·삭제가 전환되지 않고 안전하게
중단됩니다.

기존 런타임 migration은 기본적으로 strict합니다. source와 다른 cache 값이
이미 있으면 collision으로 중단합니다. 지속해서 보존되는 legacy source만
`migrate --from PATH --reuse-existing`을 명시할 수 있습니다. 모든 대상의
preflight에서 기존 destination 하나라도 source와 다르면 현재 cache 전체를
authoritative로 선택하고 legacy source 전체를 건너뜁니다. 따라서 같거나 아직
없는 항목도 복사하지 않습니다. 차이가 없으면 기존처럼 additive하게
migration하며, preflight 뒤 생긴 collision은 여전히 fail-closed입니다.
wrapper swap 뒤 제거될 수 있는 기존 vendor 복구는 반드시 strict 모드를
유지해야 합니다.

### guard와 병합 시점 게이트

Core는 이 워크플로가 지켜지는지 확인하는 장치도 함께 배포합니다. workspace
guard는 `PreToolUse` 훅으로 동작하며 두 가지를 거부합니다. 계획 파일을 새로
만드는 것과, 워크플로 디렉터리 밖에 쓰는 것입니다. 이번 세션에서 호스트가 SCV
액션이 실행 중이라고 알린 적이 있으면 예외입니다. 그 호스트 이벤트는 모델이
위조할 수 없는 유일한 신호이므로 guard는 여기에만 의존합니다. 세 번째 규칙은
이번 턴의 요청이 모델의 요구 항목 목록에 등록되기 전까지 파일 쓰기를 거절합니다
(위의 모델별 프롬프팅). guard는 빈 payload와 JSON 리더가 없는 기계, 이 둘에서만
fail-open 해서 모든 프로젝트의 쓰기를 막는 사태를 피합니다. 반대로 영수증
저장소를 쓸 수 없을 때는 닫히는 쪽으로 실패합니다. SCV를 도입하지 않은
프로젝트에서는 아무 일도 하지 않습니다. 등록은 래퍼의 몫입니다. 래퍼가 훅
항목마다 `SCV_GUARD_MODE`를 전달하므로 스크립트 자체는 호스트를 언급하지
않습니다. 규칙은 [guard 계약](core/contracts/guard.md)에 있습니다.

훅이 볼 수 없는 부분은 병합 시점의 게이트 두 개가 담당합니다.
`core/scripts/check-provenance.sh`는 코드를 바꾸면서
`scv/archive/<slug>/PLAN.md`에 보관된 계획을 추가하지 않은 PR을 거부합니다.
문서와 워크플로 디렉터리만 바뀐 diff는 코드 변경으로 보지 않습니다.
`core/scripts/check-vendor-provenance.sh`는 sync 봇이 아닌 브랜치에서 래퍼의
`vendor/scv-core/`를 다시 쓴 PR을 거부합니다. 봇은 게시된 릴리스 아티팩트를
받아 원본 해시와 구체화된 해시를 함께 기록하지만, 손으로 복사하면 그때 작업
트리에 있던 내용이 그대로 기록됩니다. 두 게이트 모두 `stage`, `main`으로 가는
릴리스 체인과 봇의 `chore/core-*` 브랜치는 예외로 두고, PR 제목에
`[no-plan: <이유>]`와 `[manual-vendor: <이유>]`로 예외를 선언할 수 있습니다.
이유는 필수이며, 이유 없는 marker는 거부합니다. Core 자체 CI는 provenance
게이트를 실행하고, vendor 게이트는 vendor된 Core를 가진 래퍼 저장소를 위해
배포됩니다.

자세한 경계는 [아키텍처](docs/architecture.md)와
[래퍼 통합](docs/wrapper-integration.md)을 참고하세요. 실제 변경을 어느
저장소에서 해야 하는지는
[Core와 Wrapper 소유권 가이드](docs/core-wrapper-ownership.ko.md)에 정리되어
있습니다.

## 검증과 테스트

```bash
bash tests/run.sh
bash core/tests/run-dry.sh
for test_file in core/tests/test-*.sh; do bash "$test_file"; done
```

`tests/run.sh`는 `tools/check-readme.sh`로 이 문서도 저장소와 대조합니다. 적힌
설정 · 액션 · 링크는 모두 실제로 있어야 하고, 세 언어판은 같아야 합니다.

DeckUI 원본 체크아웃 개발에는 Node.js와 pnpm이 추가로 필요합니다.

```bash
pnpm -C core/DeckUI install --frozen-lockfile
pnpm -C core/DeckUI typecheck
pnpm -C core/DeckUI build:deck
```

## 내보내기와 벤더링

검증된 호스트 중립 내보내기를 만듭니다.

```bash
tools/export-core.sh --output /tmp/scv-core-export
```

로컬 체크아웃에서 래퍼 전용 페이로드를 구체화합니다.

```bash
tools/vendor-core.sh \
  --source /path/to/scv-core \
  --target /path/to/wrapper/vendor/scv-core \
  --profile /path/to/wrapper/adapter/host-profile.env
```

벤더링 결과의 `core.lock.json`에는 원본과 구체화된 결과의 해시가 함께
기록됩니다. 개발 의존성, 빌드 결과, 캐시, 디렉터리 심볼릭 링크는 내보내기에서
제외됩니다.

## 릴리스

```bash
tools/release-artifact.sh --output-dir dist
```

버전이 `X.Y.Z`이면 다음 파일을 생성합니다.

- `scv-core-vX.Y.Z.tar.gz`
- `scv-core-vX.Y.Z.tar.gz.sha256`

`vX.Y.Z` 태그는 두 파일을 릴리스한 뒤 두 래퍼에 Core 동기화 이벤트를 보냅니다.
교차 저장소 토큰은 필수이며, 알림에 실패한 릴리스 run 은 실패로 표시됩니다
(이미 게시된 릴리스 자산은 영향받지 않습니다). 두 래퍼 모두 매일 폴링하므로
알림 실패는 전파를 잃는 것이 아니라 늦추는 것입니다. 래퍼 자동화는 체크섬 검증,
호스트별 재생성, 회귀 테스트를 거쳐 `develop` 대상 PR을 엽니다.
`gh workflow run promote.yml`은 `develop → stage → main`으로 승격하며,
`-f release=false`를 주면 태그 없이 승격해 문서처럼 릴리스가 필요 없는 변경에
씁니다. 자세한 내용은 [릴리스와 무결성](docs/release.md)을 참고하세요.

## 기여

영구 브랜치는 `develop`, `stage`, `main`입니다. 작업 브랜치는 `develop`으로
병합하고, 이후 `develop → stage → main` 순서로 승격합니다.
[브랜치 정책](.github/BRANCHING.md)을 참고하세요.
