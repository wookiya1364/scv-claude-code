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
| SCV Core | `0.20.1` | 공통 동작과 릴리스 페이로드 |
| Core API | `1` | 래퍼와 코어의 통합 계약 |
| Template | `1.0.0` | hydrate되는 프로젝트 템플릿 스키마 |

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

14개 SCV 액션 중 12개는 Core가 소유합니다. 설치 방식과 모델 선택은 호스트에
종속되므로 `update`, `set-models`는 어댑터가 소유합니다. 정규 프로토콜은
`action:<name>`과 `{{SCV_ARGS}}`를 사용하며, 실제 명령 문법과 인자 전달
방식은 검증된 호스트 프로필로만 주입됩니다.

공통 상태 인덱스는 항상 `scv/SCV.md`입니다. 이전 래퍼에서 전환하는 동안에는
`SCV.md`가 없을 때만 `CLAUDE.md` 또는 `CODEX.md`를 읽습니다. 서로 독립적인
상태 파일이 다르면 변경 작업인 sync는 아무 파일도 건드리지 않고 중단합니다.

자세한 경계는 [아키텍처](docs/architecture.md)와
[래퍼 통합](docs/wrapper-integration.md)을 참고하세요.

## 검증과 테스트

```bash
bash tests/run.sh
bash core/tests/run-dry.sh
for test_file in core/tests/test-*.sh; do bash "$test_file"; done
```

DeckUI 검증에는 Node.js와 pnpm이 추가로 필요합니다.

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
