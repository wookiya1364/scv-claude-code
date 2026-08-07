# SCV Core

[English](README.md) · [日本語](README.ja.md)

SCV Core는 Claude Code용 SCV와 Codex용 SCV가 함께 사용하는 호스트 중립
원본입니다. 워크플로 프로토콜, 실행 스크립트, 프로젝트 템플릿, DeckUI,
에셋, 공통 회귀 테스트를 이 저장소에서 관리합니다. 각 래퍼는 변경 불가능한
Core 릴리스를 고정하고, 검증된 호스트 프로필을 반영한 뒤 런타임별 어댑터만
추가합니다.

현재 계약 버전:

| 계약 | 버전 | 의미 |
|---|---:|---|
| SCV Core | `0.22.0` | 공통 동작과 릴리스 페이로드 |
| Core API | `1` | 래퍼와 코어의 통합 계약 |
| Template | `2.0.0` | hydrate되는 프로젝트 템플릿 스키마 |

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
방식은 검증된 호스트 프로필로만 주입됩니다.

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

자세한 경계는 [아키텍처](docs/architecture.md)와
[래퍼 통합](docs/wrapper-integration.md)을 참고하세요.
실제 변경을 어느 저장소에서 해야 하는지는
[Core와 Wrapper 소유권 가이드](docs/core-wrapper-ownership.ko.md)에
정리되어 있습니다.

## 검증과 테스트

```bash
bash tests/run.sh
bash core/tests/run-dry.sh
for test_file in core/tests/test-*.sh; do bash "$test_file"; done
```

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

`vX.Y.Z` 태그는 두 파일을 릴리스합니다. 교차 저장소 토큰이 설정되어 있으면
즉시 Core 동기화 이벤트도 보내며, 토큰이 없을 때는 각 래퍼의 정기 폴링이
같은 역할을 합니다. 래퍼 자동화는 체크섬 검증, 호스트별 재생성, 회귀 테스트를
거쳐 `develop` 대상 PR을 엽니다. 자세한 내용은
[릴리스와 무결성](docs/release.md)을 참고하세요.

## 기여

영구 브랜치는 `develop`, `stage`, `main`입니다. 작업 브랜치는 `develop`으로
병합하고, 이후 `develop → stage → main` 순서로 승격합니다.
[브랜치 정책](.github/BRANCHING.md)을 참고하세요.
