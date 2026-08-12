# Changelog

All notable changes to SCV Core are documented here.

## [0.23.0] - 2026-08-12

### 쉬운 말 먼저 — 사용자 대상 출력의 기본 규칙

- SCV는 어떤 **언어**로 말할지는 정해 두었지만 얼마나 **쉽게** 말할지는 정해
  두지 않았다. 그래서 계획 설명과 진행 보고가 길고 어려워졌다. 이해되지 않은
  계획은 승인받을 수 없고, 이해되지 않은 보고는 판단 재료가 되지 못한다.
- `## Plain language first` 절을 프로토콜 **13개**의 `## Language preference`
  옆에 추가했다. 핵심은 "짧게 먼저 말하고, 더 원하면 그때 자세히". 한 문장에
  한 가지, 범주명 대신 실제 이름, 사용자에게 무슨 일이 생기는지 먼저, 필요하면
  비유, 전문 용어는 처음 쓸 때 그 자리에서 정의.
- `set-models.md` / `update.md`는 제외했다. 어댑터 소유 스텁이고 사용자 대상
  출력이 없다.
- 문구는 13개 파일에서 **동일**하다. 회귀 가드가 존재·동일성·스텁 제외를
  고정한다(`run-dry.sh` [15p]).
- **분류 이월**: 어블레이션 기준으로는 채팅 출력 코칭이라 GUIDANCE지만,
  1단계 범위가 promote·work 외 프로토콜의 마커를 금지한다. 그래서 13개 전부
  마커 없이(= CONTRACT) 넣었다. 2단계에서 나머지 프로토콜에 마커를 도입할 때
  함께 GUIDANCE로 감쌀 것.
- **한계**: 규칙이 프로토콜에 있다는 것까지만 테스트한다. 에이전트가 실제로
  쉽게 말하는지 검증하는 수단은 없다.


### 릴리스 알림이 실패하면 릴리스 run 도 실패한다

- `release.yml` 의 dispatch 스텝에서 `if: env.SCV_WRAPPER_SYNC_TOKEN != ''` 와
  `continue-on-error: true` 를 **둘 다 제거**했다. 토큰이 없으면 스텝이
  **skipped** 되어 run 이 초록불로 남았고, v0.22.0 릴리스 run 이 실제로 그
  상태였다(스텝은 skipped, run 은 success). 이제 토큰 부재는 스텝 안에서 명시적
  error 로 실패하고, "래퍼가 통보받지 못했다"가 **한 가지 신호**로 통일된다.
- 릴리스 자산 게시는 dispatch 보다 **앞** 스텝이므로 빨간불이어도 아티팩트는
  항상 온전하다. job 재실행도 안전하다 — 기존 릴리스를 감지해 `--clobber`
  업로드 경로를 탄다.
- dispatch 루프의 **반쪽 실행**을 고쳤다. 기본 셸이 `bash -e {0}` 라 첫 래퍼가
  실패하면 루프가 중단되어 `scv-codex` 는 시도조차 되지 않았다. 이제 래퍼별로
  독립적인 3회 백오프 재시도를 받고, 실패는 `::error::` 와 재발송 명령이 담긴
  job summary 로 남는다.
- **`core_tag` 는 Core 에 추가하지 않았다.** `scv-codex` 가 읽던 그 키는 Core
  계약(`docs/wrapper-integration.md` §7 의 `version`/`tag`/`asset_url`/
  `checksum_url`)에 존재한 적이 없다. 계약에 없는 키를 Core 가 맞춰 보내는
  대신 래퍼가 계약에 맞추는 쪽으로 정리했다(scv-codex PR #21). 두 래퍼의 폴링
  주기도 매일로 통일했다.

### 토큰 헬스체크 — 만료를 릴리스 전에 잡는다

- `.github/workflows/token-health.yml` 을 추가했다(주 1회 + 수동). 릴리스는
  드물어서 토큰이 죽어도 다음 태그까지 모른다. fine-grained PAT 은 만료되므로
  그 사이가 길다.
- 검사 3종, 전부 부작용 없는 GET: ① 시크릿 존재 ② 토큰이 API 에 아직
  수락되는가 + `github-authentication-token-expiration` 헤더 기반 만료 14일
  전 경고(헤더가 없는 토큰 종류면 조용히 건너뜀) ③ 두 래퍼에 대한
  `permissions.push` — `repository_dispatch` 가 요구하는 권한이다.
- 모든 API 실패를 값으로 흡수한다. 기본 셸이 `bash -e -o pipefail` 이라
  `x=$(gh api ...)` 를 그대로 쓰면 403 한 번에 스텝이 죽어 **어느 저장소가
  문제인지 말하지 못한 채** 빨간불만 남는다.

### check-frontmatter — PLAN 은 PLAN 스키마로 검사한다 (동작 변경)

- `core/scripts/check-frontmatter.sh` 가 단일 `REQUIRED_KEYS`(표준문서 스키마
  `name`/`version`/`last_updated`/`standard_version`/`merge_policy`)를
  `scv/promote/**` 에도 적용하고 있었다. `PROMOTE.md` §4 가 규정한 PLAN 필수
  필드(`title`/`slug`/`author`/`created_at`/`status`/`tags`)와는 `status`
  하나만 겹쳐서, **문서화된 템플릿으로 쓴 PLAN 은 전부 이 린트에 실패**했다
  (실측: 계획 7건 기준 35 violations). run-dry 는 표준문서 키를 넣어 만든 자체
  픽스처만 돌려서 초록불이었다.
- 스키마를 `STANDARD_DOC_KEYS` / `PLAN_KEYS` 로 분리하고, **status 값 목록도
  함께 분리**했다(`STANDARD_DOC_STATUS` / `PLAN_STATUS`). 필수 키만 쪼개고
  status 를 병합해 두면 PLAN 이 `status: draft` 를 써도 통과하는 절충이 남는다.
- 계약에 없는 `scv/promote/*.md` · `*/index.md` 글롭은 검사 대상에서 **제거**
  했다. `PROMOTE.md` §3 은 promotion 을 "PLAN.md 를 담은 폴더"로 정의한다 —
  린트가 계약에 없는 형식에 스키마를 발명해 부여하지 않는다.
- 픽스처 4건을 실제 PLAN 템플릿 형태로 교체하고, 회귀 가드 4종을 추가했다:
  템플릿 PLAN 통과 / `author` 누락 거부 / **표준문서 헤더를 단 PLAN 거부** /
  **`status: draft` 인 PLAN 거부**. 뒤의 두 개가 이 결함을 초록불로 유지했던
  바로 그 형태다.

### 구현 원칙 4종 — work·codegen 기본값

- `action:work` Step 6 과 `action:codegen` Step 7 에 **구현 원칙 4종**을 CONTRACT
  로 넣었다: ① 기존 코드를 먼저 찾아 재활용 — 이미 한 방식이 있는 일에 두 번째
  방식을 만들지 않는다 ② 현재 요구를 완전히 충족하는 가장 단순한 구현 ③ 관심사
  하나당 컴포넌트 하나, 독자가 이름 붙일 수 있는 경계 ④ 되돌리기 비싼 결정(데이터
  모델·모듈 경계·공개 계약)은 장기 관점 — 나중에 교체할 임시방편 금지.
  **PLAN 의 `Guardrails` 가 항상 우선한다** — Core 가 프로젝트 정책을 덮어쓰지
  않는다.
- ②와 ③·④의 긴장은 의도된 것이라, 판별 기준을 GUIDANCE 로 붙였다: 미래 변경이
  재작성이면 아키텍처이고, 아키텍처는 지름길이 아니라 계획에 넣는다.
- `codegen` 은 work Step 6 을 상속하지 않는다(자체 Red/Green/Refactor 루프).
  Step 7 Green 반복에서 정본을 참조하게 했다 — TDD 의 최소 코드 규칙이 ②를 이미
  덮지만, 재활용과 경계는 Step 8 리팩터가 아니라 코드를 쓰는 중에 결정된다.
- **넣지 않은 것**: "하위호환을 유지하지 마라" 는 보류했다. SCV 자신이 legacy
  `## Steps` · `.conversations` 마이그레이션 · `CLAUDE.md`/`CODEX.md` 포인터로
  후방호환을 광범위하게 유지하므로, 배포되는 도구와 사용자 프로젝트 코드의 층위
  정리가 먼저다. "주기적 데드코드 제거" 도 넣지 않았다 — 이미
  `routines/examples/dead-code.md`(`cadence: 1d`) 가 그 루틴이다.
- **알려진 마찰**: `test-guidance.sh` [6] 은 promote·work 밖 프로토콜의 **커밋되지
  않은** 변경을 전부 실패로 본다(어블레이션 1단계 스코프 가드). `codegen.md` 편집은
  커밋 전까지 이 검사 1건을 빨갛게 만든다 — 회귀가 아니라 가드의 설계다. 2단계에서
  다른 프로토콜을 손대면 같은 마찰이 재발하므로, 가드를 "마커 유출 검사"로 좁힐지
  판단이 필요하다.

### 결정 로그 실작동 — 실행 경로 복구 + 구현 델타 기록

- **문제**: v0.22.0 이 `scv/DECISIONS.md` 와 자동 append 3지점을 도입했지만,
  이 저장소에서 결정 엔트리는 **0건**이었고 파일 자체가 git 이력에 존재한 적이
  없었다. 원인은 기록할 필드 부족이 아니라 **기록 지시가 실행되는 경로의 부재**
  다 — 아카이브 5건이 전부 수동 `git mv` 로 처리됐고(`scv/archive/INDEX.yaml`
  부재가 확증), 유일한 자동 경로인 `action:work` Step 9b.0 은 한 번도 도달하지
  않았다.
- `action:work` **Step 0 archive short-circuit 이 Step 9b.0 만은 수행**하도록
  바꿨다. 이전에는 `action:work <slug> --archive` 가 Steps 1+ 를 통째로 끊어
  결정 로그가 남지 않았다. 이 경로는 대화 밖에서 구현한 작업의 수동 아카이브에
  쓰이므로, 델타를 모를 때는 `path delta: unknown (archived outside this
  conversation)` 을 쓰도록 명시했다.
- archive 결정 엔트리에 **`- path delta:` 1필드**를 추가했다 (Step 9b.0).
  PLAN 의 `Suggested path`(legacy: `Steps`; 둘 다 없으면 Step 6 에서 사용자에게
  말한 경로) 대비 실제로 간 경로와 이탈 이유를 한 줄로 남긴다. `refs:` /
  `conversation:` 과 달리 **생략 불가** — 그대로 갔으면 `as planned` 한 단어로
  끝난다. Step 6 은 "더 나은 경로를 찾으면 그리로 가라"이고 Step 5c 는 자율
  완주 계약이므로, 이탈 이유는 세션이 끝나면 어디에도 남지 않는 유일한 정보축
  이었다.
- **`new invariants:` 필드는 만들지 않았다.** 기존 `- why:` 가 이미 "what was
  learned while implementing it" 을 요구하므로 부분집합이다 — 대신 그 문구에
  "including anything that must not break from now on" 절을 덧붙여 흡수했다.
- Step 8 에서 **`drift-detect.sh`** 를 호출해 PLAN 의 `scope:` 밖에서 바뀐
  파일(`SCOPE_OUTSIDE_FILES`)을 델타 서술의 근거로 쓰게 했다. 이 헬퍼는
  promote-only 이므로 archive 가 폴더를 옮기기 전인 Step 8 이 실행 가능한
  마지막 시점이다. 호출은 `scope:` 를 선언한 계획에서만 하도록 **CONTRACT 에**
  조건을 뒀다(예외가 GUIDANCE 에 있으면 `minimal` 투영에서 예외만 사라져
  no-scope 계획에서 헬퍼가 헛돈다). 이 헬퍼는 nested 모듈을 스스로 해석하지
  못하므로 모노레포에서는 `PROMOTE_DIR=<SCV_DIR>/promote` 를 앞에 붙인다 —
  스크립트 무수정 원칙을 지키면서 exit 2 실패를 피하는 유일한 방법이다.
  한계도 문안에 적었다: `git diff HEAD` 기반이라 **untracked 신규 파일은 보지
  못하며**, `DRIFT: no` 는 "추적되는 파일이 이탈하지 않았다"이지 "계획대로
  갔다"가 아니다.
- 예시 루틴 `decision-log-integrity` 를 추가했다 (예시 7종 → 8종). 아카이브
  슬러그와 DECISIONS 엔트리를 대조해 누락을 보고한다.
- **분류**: `- path delta:` 필드와 "생략 불가" 의무 문장, Step 0 예외,
  `drift-detect.sh` 호출은 전부 CONTRACT(마커 밖). 근거 산문만 GUIDANCE —
  `promote.md` Step 5.1 의 "discarded alternatives" 배치와 동일한 패턴이다.
- **회귀 보호**: `run-dry.sh` [16] 에 `- path delta:` / `Step 9b.0 only` /
  `drift-detect.sh` assert 3개, `test-guidance.sh` 의 work.min.md 생존 배열에
  같은 앵커를 등록했다. 그 배열이 오분류를 잡는 **유일한** 수단이라는 사실을
  배열 위 주석으로 남겼다 — [19a] 는 스크립트 호출·컬럼0 frontmatter 만 보고
  [19b] 는 에이전트를 실행하지 않기 때문이다. 오분류 시 실패가 실제로 재현되는
  것을 역방향으로 1회 확인했다.
- **재측정**: `core/protocols/work.md` GUIDANCE 222줄 / 전체 589줄 (37.7%).
  직전 문서값 `203 / 521` 은 갱신되지 않아 낡아 있었다 —
  `docs/guidance-ablation.md` 표를 실측값으로 고쳤다.
- **강제력의 정직한 범위**: DECISIONS.md 를 쓰는 스크립트는 존재하지 않는다.
  테스트가 보장하는 것은 "프로토콜에 지시가 있다"와 "그 지시가
  `SCV_GUIDANCE=minimal` 에서 사라지지 않는다" 두 가지뿐이다. **에이전트가
  필드를 빠뜨려도 실패하는 테스트는 없다** — 누락은 위 루틴으로만 드러난다.
- `action:codegen` 은 수정 0줄 (`codegen.md` 가 Steps 8–9e 를 work.md verbatim
  으로 위임). `action:promote` / `action:regression` 엔트리는 의도적으로 그대로
  둔다 — 그 두 결정에는 구현 단계가 없다.
- `core/template/scv/DECISIONS.md` 의 스키마 정본도 갱신했다. 이 파일은
  `merge_policy: preserve` 라 **기존 프로젝트에는 전파되지 않는다** — 실효
  전파 매체는 프로토콜 md 이며 래퍼 재벤더링으로 도달한다.

## [0.22.0] - 2026-08-07

### 가이던스 어블레이션 1단계 — CONTRACT/GUIDANCE 분리 + `SCV_GUIDANCE=minimal` (promote·work)

- 프로토콜 md 의 행동 코칭(GUIDANCE)을 `<!-- SCV:GUIDANCE -->` …
  `<!-- /SCV:GUIDANCE -->` HTML 주석 마커로 감싸는 규약을 도입했다.
  분류 기준: **삭제해도 산출물의 형식·경로·불변식(생성 파일 목록 ·
  frontmatter 스키마 · 스크립트 호출 시퀀스)이 변하지 않으면 GUIDANCE** —
  규약/기준 문서는 `docs/guidance-ablation.md`.
- 주입 필터 `core/scripts/guidance-filter.sh` 를 추가하고 래퍼 주입 지점인
  `tools/materialize-profile.sh` 에 연결했다. `SCV_GUIDANCE=full`(기본,
  미설정 포함)은 주입 내용이 원본과 바이트 동일하고,
  `SCV_GUIDANCE=minimal` 은 GUIDANCE 블록을 제거한 투영본을 주입한다.
  원본 프로토콜 파일은 어떤 모드에서도 불변. 잘못된 마커(닫힘 누락 ·
  고아 닫힘 · 중첩 · malformed)는 `파일:줄` 에러로 전체 주입을 중단한다
  (fail-closed — 부분 주입 없음; full 모드도 동일하게 검증).
- 어블레이션 동등성 하네스: `core/tests/run-dry.sh` [19] 가 promote·work
  경로를 두 모드로 실행해 생성 파일 목록 · frontmatter 스키마 · 스크립트
  호출 시퀀스가 동일함을 강제한다(차이 = CONTRACT 오분류 → 재분류).
  마커 lint · fail-closed · 타 프로토콜 바이트 불변 · deck 마커 비노출은
  `core/tests/test-guidance.sh` 가 검증하고, deck transform 은 마커 줄만
  드롭한다(GUIDANCE 본문은 deck 문서에서 계속 렌더).
- **1단계 분류 결과 (목표 비율 없이 기준 적용 후 측정)** —
  `promote.md`: GUIDANCE 241줄 / 전체 883줄 (27.3%),
  `work.md`: GUIDANCE 203줄 / 전체 529줄 (38.4%).
  다른 프로토콜 파일들은 이 웨이브에서 바이트 불변이다 (2단계는 minimal
  모드 실사용 피드백 후 별도 계획).

### BREAKING — adoption 단일화 + 표준 문서 7종 제거 (TEMPLATE_VERSION 2.0.0)

- `hydrate.sh --new` (greenfield mode) is removed. Passing `--new` now exits 1
  with a migration notice and changes no files (fail-closed). Hydrate has a
  single path and no longer seeds the seven standard docs
  (`DOMAIN.md` / `ARCHITECTURE.md` / `DESIGN.md` / `AGENTS.md` / `TESTING.md` /
  `INTAKE.md` / `RALPH_PROMPT.md`) — their templates are deleted from
  `core/template/scv/`. Kept files are unchanged in behavior: `SCV.md`,
  `PROMOTE.md`, `REPORTING.md`, `raw/README.md`, `WORKSPACE.yaml.example`,
  and the `.env` / `.gitignore` fragments.
- `action:sync` now **deletes** those seven files from existing projects,
  **without backup** (deliberate decision — git history is the recovery path),
  and reports each as `DELETED scv/<file>` in the CHANGES summary.
  `--dry-run` previews the deletions without touching files. No file outside
  the seven is ever deleted; a symlinked target is left in place with a
  `WARN` instead of being deleted (fail-closed). The `sync.md` protocol
  instructs the host agent to check each doomed file for user-authored content
  first and, when found, propose migrating the decisions worth keeping into a
  version-controlled team note (e.g. `DECISIONS.md` / journal) before applying.
- Cascade cleanup: the draft/N/A status gate, the INTAKE flow, and all
  standard-doc references are removed from `check-frontmatter.sh`, `help.sh` /
  `help.md` (incl. the greenfield hydrate option), `promote.md` (diagram 2 now
  sources from graphify only), `work.md`, `deck.md` / `deck-context.sh`,
  `SCV.md` / `PROMOTE.md` / `REPORTING.md` templates, and
  `integrations/loop-runner.md` (rewritten to run from `scv/promote/<slug>/`
  plans with a free-form user-authored entry prompt instead of
  `RALPH_PROMPT.md`). The hydration signal in `state-index.sh` / `help.sh` now
  uses `scv/PROMOTE.md` (previously `scv/INTAKE.md`); state-index and legacy
  CLAUDE.md/CODEX.md migration semantics are otherwise unchanged.
- Upgrade note: external loop harnesses (e.g. rloop) that expect
  `scv/RALPH_PROMPT.md` must switch to a free-form entry prompt; content you
  still need from a deleted doc is recoverable from git history
  (`git log -- scv/<file>`).

### Changed

- PLAN grammar overhaul (guardrails-first, Boris Cherny's task+guardrails+exit
  criteria model): the `action:promote` PLAN scaffold now has `## Guardrails`
  (do-not-touch areas / invariants in prose) and `## Exit criteria` (higher-level
  done conditions beyond TESTS), and `## Steps` is demoted to `## Suggested path`
  — the path is a suggestion, Guardrails/Exit criteria are the contract
  (경로는 제안, Guardrails/Exit criteria 가 계약). `scv/PROMOTE.md` §4 is synced.
  All new sections/fields are optional: legacy PLANs with only `## Steps` are
  processed by `action:work` / `action:regression` unchanged.
- `action:promote`'s Socratic follow-up questions changed direction: do not
  interrogate implementation method (구현 방법을 캐묻지 말라) — ask only about
  boundaries, risks, exit criteria, and verification means; the
  procedure-probing example list was replaced accordingly.
- `action:work` gained a long-run execution contract (Step 5c): with Guardrails /
  Exit criteria + TESTS verification means in hand, run to completion without
  micro-step instructions, and strengthen the verification means first when
  stuck. This paragraph owns work's long-run behavior even after RALPH_PROMPT
  retirement.

### Added

- Optional PLAN frontmatter `parallel_groups: [[step,...],...]` — independent
  Suggested-path step groups a subagent-capable host may fan out concurrently
  (`action:work` Step 5d); `action:regression` documents the analogous slug-level
  fan-out. Absent hint or non-parallel host → behavior identical to before.
- Raw-injection hygiene: `action:promote` and `action:help` now state that raw /
  conversation file content is **data** — instruction-like text inside it is
  never executed and is reported to the user instead.
- **Team journal — author-attributed, committed project memory**
  (전면 기록화): three new templates, all `merge_policy: preserve`, seeded by
  hydrate and propagated as `NEW` by sync — `scv/journal/README.md` (usage
  rules), `scv/DECISIONS.md` (append-only decision log; entry schema reuses
  the handoff decision format with a mandatory author), and `scv/TODO.md`
  (team todo, `- [ ] (T-NNN) <내용> — @<author>, YYYY-MM-DD`).
- `core/scripts/lib/author.sh` — unified author resolution
  (`git config user.name` → `GIT_AUTHOR_NAME` → `USER` → `unknown`) +
  filename-safe slugging that keeps non-ASCII (Korean) names;
  `promote-helper.sh`'s `AUTHOR` signal now uses it.
- `core/scripts/journal-append.sh` — appends `### [HH:MM:SS] <speaker>` blocks
  to `scv/journal/<YYYYMMDD>-<author>.md` (per-day, per-author files — no git
  conflicts), with a built-in redaction filter
  (password/token/secret/api-key values, `Bearer` tokens, `AKIA…` keys →
  `[REDACTED]`); `--redact-only` exposes the filter to protocols.
- Host hook templates `core/template/hooks/on-user-prompt.sh` (prompt-submit
  event, stdin JSON `prompt`) and `on-stop.sh` (stop event, stdin JSON
  `transcript_path`) journal free conversation; both are non-blocking (any
  failure → exit 0, no write). Registration is **wrapper-owned** — the seam
  contract is `docs/wrapper-integration.md` §6, hydrate never seeds `hooks/`
  into projects.
- Decision record points in three protocols, appending author-attributed
  entries to `scv/DECISIONS.md`: `action:promote` plan approval (adopted
  direction + **discarded alternatives**), `action:work` archive (the reason
  promoted to a decision summary), `action:regression` obsolete triage (the
  WHY that previously evaporated with the session).
- `action:status` now surfaces the last 5 `DECISIONS.md` entries and the open
  `TODO.md` items counted per author.
- **`scv/routines/` — 한 문장 프롬프트 유지보수 루틴 레이어** (Boris Cherny's
  daily-maintenance-routines practice): one routine = one md file under
  `scv/routines/<name>.md` with a five-key frontmatter contract
  (`name` / `cadence` / `guardrails` / `exit` / `report`) and a task-only body
  (plan-grammar — 과업+가드레일+종료 조건, 절차 나열 금지). hydrate seeds ONLY
  `scv/routines/README.md` (the convention doc, `merge_policy: overwrite`);
  sync propagates it to existing projects the same explicit-line way as
  `raw/README.md`. Routine files themselves are user/agent-authored.
- **`action:routine` — the 15th action** (core-owned): `--list` shows a
  NAME/CADENCE/REPORT table (guidance line when none are defined), `<name>`
  parses the routine md via the new `core/scripts/routine.sh`
  (frontmatter signals + task body + host-scheduling guidance block;
  unknown name → error with the available list, exit 1; `--lint <file>`
  validates the five-key schema). The `routine.md` protocol binds execution
  to the routine's task/guardrails/exit contract, forbids direct writes to
  permanent branches (working branch + PR or report only), makes the
  `report:` summary follow the `action:report` format, and ends with
  host-specific schedule-registration EXAMPLES — **SCV itself never
  schedules**: no cron registration, no daemon, no loop (host-owned, like
  `update` / `set-models` installation ownership). Action-count contracts
  updated 14 → 15 (`tests/test-actions.sh`, `tools/verify-core.sh`, READMEs,
  `docs/wrapper-integration.md`, `docs/core-wrapper-ownership.ko.md`);
  wrappers must register the new command surface (handoff drafts in
  `scv/promote/20260807-wookiya1364-routines/HANDOFF-DRAFTS.md`).
- Seven built-in routine templates under `core/template/scv/routines/examples/`
  (copy into `scv/routines/` to adopt; never auto-seeded): 4 SCV maintenance
  routines — `regression-runner` (run `action:regression`, report failures),
  `outdated-verifier` (semantically verify `readpath.sh outdated`'s
  `OUTDATED-CANDIDATE` docs against current code — completes the 0.21.0
  heuristic), `promote-staleness` (remind about `status: planned` folders
  older than N days), `archive-integrity` (regenerate `INDEX.yaml`, verify
  `supersedes` links) — plus 3 project-agnostic codebase routines imported
  from the Boris interview: `dead-code`, `abstraction-police`,
  `useless-tests`. All pass the routine frontmatter lint
  (`core/tests/test-routines.sh` covers seeding, list/prepare/error paths,
  outdated wiring, the 15-action catalog, and a no-scheduler-code sweep).

### Changed (team journal wave)

- Conversations are now **committed**: `.gitignore.fragment` no longer ignores
  `/scv/.conversations/`; `action:help` persists conversation files to
  `scv/conversations/` through the `journal-append.sh --redact-only` filter,
  and offers a one-time migration when it detects a legacy local
  `scv/.conversations/` (`LEGACY_CONVERSATIONS:` helper line).

## [0.21.0] - 2026-08-04

### Added

- Offline-ready 기획서 decks: after the doc build, `deck.sh` bakes every
  mermaid diagram into the HTML as inline SVG via a locally installed headless
  Chrome (`deckdoc/static-mermaid.mjs` + render.mjs's `?scv-static` build
  mode), so the deck opens fully rendered with no CDN at view time.
  Best-effort by contract — without Chrome or network the deck keeps the
  existing CDN + text-fallback rendering; opt out with `--no-static` or
  `SCV_DECK_STATIC=0`.

- Raw-doc lifecycle: `action:promote` Step 8 now runs `readpath.sh consume`,
  which moves consumed originals (content unchanged) into `scv/raw/stale/` and
  records which promote slugs used each doc in `scv/readpath.json`'s new
  `ref_docs` map (schema v2; a doc reused by several features accumulates all
  their slugs plus `ref_commit`/`consumed_at`). Files still directly under
  `scv/raw/` are therefore exactly the never-promoted **unused** docs.
- New `readpath.sh` subcommands: `consume`, `unused`, `refs`,
  `lifecycle-counts`, and `outdated` — a content-staleness heuristic that flags
  consumed docs mentioning repo files changed since their `ref_commit`
  (`OUTDATED-CANDIDATE`), with semantic verification delegated to the host
  agent in `action:promote` / `action:status`.
- `action:status` shows the unused/consumed split, per-doc `ref_docs` slugs,
  and outdated candidates; `action:help`'s banner surfaces the unused count;
  `promote-helper.sh` emits `RAW_STALE_COUNT` / `RAW_OUTDATED_COUNT` and no
  longer counts consumed docs toward the split heuristic.
- `action:status` documents a one-time legacy backfill: retro-consuming raw
  docs referenced by `raw_sources:` of existing promote/archive plans.

### Fixed

- Deck mermaid diagrams were near-invisible (white init-palette edges on the
  renderer's light card). The doc renderer now emits the
  `scv-mermaid-contrast` overrides (transparent diagram card, theme-variable
  edges and edge labels) and the promote protocol's `%%{init}%%` template
  aligns with the deck's own theme tokens (`#9096a8`/`#e7e9f0`/`#171922`), so
  architecture diagrams stay readable in both light and dark themes.

### Changed

- readpath schema is now v2 (`files` + `ref_docs`, each entry also recording
  its pre-move `origin`). v1 state files remain readable, `update` preserves
  `ref_docs`, and v1 readers ignore the new block. Caveat: a **v1** `update`
  rewrites the file without `ref_docs` — mixed-version teams should upgrade
  wrappers together.
- `consume` is fail-closed: preflight validates every path (normalization of
  `//`·`/./` variants, raw-dir prefix, no `..`, no symlinked leaf **or path
  component**, no duplicate arguments, README excluded, no
  quote/backslash/control characters) before any file moves. A shared source
  that an earlier promote folder already moved is remapped via its recorded
  `origin` (`REMAPPED` output) instead of failing.
- The ref_docs parser tolerates pretty-printed state files (e.g. after
  `jq .`) via brace-depth tracking, and empty TSV fields use a `-` placeholder
  so IFS tab-collapsing can no longer shift columns (previously an empty
  `ref_commit` silently corrupted the state on the next `update`).
- `diff`/`status-counts` no longer crash on filenames containing spaces
  (pre-existing `compute_diff` word-splitting bug); filenames with quotes,
  backslashes, tabs, or newlines are skipped by `scan`/`diff` with a warning
  and rejected by `consume` (the narrow no-jq schema cannot represent them).
- `action:sync` now propagates `scv/raw/README.md` (merge_policy `overwrite`)
  so existing projects receive the raw lifecycle guide instead of keeping the
  old "raw files are never moved" text that contradicts Step 8's stale-move.

## [0.20.6] - 2026-07-29

### Fixed

- Centralized canonical, legacy, conflict, and broken-pointer state resolution
  in one host-neutral Core entrypoint so Claude Code and Codex cannot classify
  the same project differently.
- Standardized compatibility pointers on the exact
  `SCV:HOST-POINTER target=SCV.md` marker and made both host directions share
  the same inspect, preview, backup, and pointer-finalization behavior.
- Kept projects with readable state and `scv/INTAKE.md` classified as hydrated
  during a fail-closed conflict, preventing a conflict from being mistaken for
  an unhydrated project.

### Security

- Made canonical seeding no-replace and revalidated every active legacy file
  against its recoverable backup before publishing any pointer.
- Preserved read-only and dry-run trees byte-for-byte across the full
  canonical/legacy/pointer conflict matrix.

## [0.20.5] - 2026-07-29

### Changed

- Kept legacy Deck runtime migration strict by default and added the explicit
  `migrate --from LEGACY_DECKUI --reuse-existing` opt-in for persistent legacy
  sources.
- Made cache reuse authoritative and all-or-none: if preflight finds any
  pre-existing destination that differs from its legacy source, the entire
  legacy source is skipped, including equal and missing destinations. With no
  mismatch, migration retains its existing additive behavior.
- Required ephemeral existing-vendor recovery to remain strict so a wrapper
  cannot discard runtime data when that vendor is removed after a successful
  swap. Core API remains `1`.

### Security

- Preflight now evaluates every eligible runtime entry before any copy or
  authoritative-reuse decision. A destination collision that appears after
  preflight still fails closed instead of changing policy mid-transaction.

## [0.20.4] - 2026-07-28

### Security

- Anchored the Deck runtime cache base, payload namespace, target, staging,
  migration destinations, installation, and cleanup to verified directory
  descriptors opened with no-follow semantics.
- Made lock acquisition install a complete owner record through an atomic
  no-replace rename, and bound stale quarantine and release to the original
  lock inode and owner token.
- Added deterministic late-symlink, ancestor-replacement, quarantine-collision,
  and release-race regressions that assert external sentinels remain unchanged.

## [0.20.3] - 2026-07-28

### Fixed

- Made first-use and migration installs in the shared DeckUI cache use
  platform-native atomic no-replace renames on Linux and macOS.
- Rejected cache/legacy overlap before initialization and opened every
  migration destination ancestor without following links.
- Limited stale lock reclamation to a valid dead-owner record with no
  unexpected lock data; malformed or surprising state is preserved and fails
  closed.

## [0.20.2] - 2026-07-28

### Fixed

- Moved mutable DeckUI dependencies, build output, and generated deck data out
  of the immutable Core/plugin tree into a payload-keyed external cache.
- Added an idempotent legacy DeckUI migration that preserves pnpm links,
  generated decks, and build output without deleting or rewriting the source.
- Prevented wrapper Core replacement from treating DeckUI runtime data as
  distributable payload and removed excluded empty deck directories from
  exports.
- Expanded the cross-host state matrix to cover approved `CLAUDE.md` and
  `CODEX.md` migrations, both supported readpath encodings, workspace markers,
  and mutating conflict failure with byte-for-byte preservation.

### Security

- Added atomic cache initialization, per-payload locking, collision detection,
  unsafe target rejection, and link/special-file checks for immutable DeckUI
  inputs.

## [0.20.1] - 2026-07-28

### Fixed

- Materialized source-checkout metadata links as regular files in exported and
  released payloads so strict wrapper archive validation can reject every link
  and special-file entry consistently.
- Added export, vendoring, and release hygiene checks that fail if any
  non-regular entry is present.

## [0.20.0] - 2026-07-28

### Added

- Extracted the shared SCV protocols, scripts, template, DeckUI, assets, docs,
  and regression tests into a host-neutral Core payload.
- Added a strict Core API v1 host-profile contract and deterministic
  materialization for template-string and argv-array hosts.
- Added verified export, vendoring, lock generation, deterministic release
  artifacts, and SHA-256 integrity metadata.
- Added legacy `CLAUDE.md`/`CODEX.md` read compatibility with explicit,
  non-destructive migration to `SCV.md`.
- Added CI for contracts, host-neutrality, state migration, shared regression,
  DeckUI, cross-platform shell behavior, deterministic artifacts, and branch
  flow.

### Changed

- Made `scv/SCV.md` the canonical shared state index.
- Moved host installation (`update`) and model selection (`set-models`) behind
  adapter-owned boundaries.
- Made sync fail closed when independent state indexes diverge and preserve
  project-local metadata and existing lifecycle status during migration.

### Security

- Host profiles are parsed as data without `source` or `eval`.
- Exports reject escaping or directory symlinks and exclude development
  dependencies, build outputs, caches, and temporary files.
