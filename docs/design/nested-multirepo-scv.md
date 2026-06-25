# Nested Multi-Repo SCV — 설계서

> 상태: **설계 (코드 전)** · 작성 2026-06-24 · 대상 SCV 플러그인
> 본 문서는 로컬 설계 산출물입니다. 커밋/푸시는 별도 동의 후에만.

---

## 0. TL;DR

단일 레포에서는 **지금과 byte-identical**, Nest(루트 우산 scv + 자식 레포 scv)에 들어가면 **멀티레포 협업 루프**가 켜진다. 핵심 루프는:

```
FE 자식 scv: /scv:work 후 "BE/AI 대응개발 필요" 명시적 선언 (/scv:handoff)
   → 루트 scv repo(공유 git)에 handoff 파일 + 결정 + 대화 기록 → (동의 후) push
   → BE가 git pull → /scv:status [7] 가 "너에게 온 handoff" 표시
   → /scv:promote(handoff-aware) 로 PLAN+TESTS 스캐폴드 → 기존 /scv:codegen(TDD) 으로 구현
   → BE가 다시 AI로 선언 가능 … 루프
```

새 구현 엔진은 만들지 않는다. `/scv:generate` 같은 신규 명령 없음 — **기존 `/scv:codegen` 재사용**. 신규 표면은 선언 명령(`/scv:handoff`)과 additive 동작뿐.

---

## 1. 문제 & 목표

- 프로덕션은 FE / BE(MSA) / AI 가 **여러 레포** (또는 모노레포 혼합)로 존재. 각자 다른 머신.
- 4인 팀, 한 명이 한 분야. 한 명이 빠지거나 결정이 내려졌을 때, **Claude Code + SCV만으로** 개발이 이어져야 함.
- 원하는 것: "FE에서 기능 추가/변경/삭제 → 다른 레포 대응개발이 필요하면 **명시적으로 선언** → 상대 레포가 그걸 보고 대응개발 제안" 하는 루프. 그 과정의 **결정과 대화가 기록**되고, **스펙 문서 기반 자동 구현**이 가능할 것.
- **명시적 선언** 기반이다. 코드 diff 자동 감지가 아니다 (사용자 명시).

### 비목표 (이번 범위 밖)
- cross-repo **회귀** (FE 변경이 BE 테스트를 한 번에 RED) — `regression.sh` per-target `cd` 버그 선수정 필요.
- cross-repo **PR 생성** — PR 레이어가 cwd/origin 고정.
- **계약(contract) 기반 mechanical 전파** — 현재 팀은 계약/계약테스트 없음. 나중 업그레이드.

---

## 2. 핵심 원칙 — 워크스페이스는 "탈부착 additive 오버레이"

> **불변식**: 로컬 SCV(promote / work / codegen / regression / status[1-6] / report)는 워크스페이스 상태를 **절대 읽지 않는다.** 워크스페이스는 순수 additive 오버레이다. 모드는 **매 명령 호출마다 로컬 파일로 재계산**된다 (일방향 migration 없음). 루트가 없거나 닿지 않으면 cross-repo 기능만 한 줄 안내 후 no-op으로 **graceful degrade** 하고, 로컬은 그대로 돈다.

이 원칙이 보장하는 것:

| 동작 | 결과 |
|---|---|
| Nest에서 빼냄 (identity 블록 제거 / 폴더 이동 / 오프라인) | 원래 SCV 그대로. cross-repo 기능만 잠듦 |
| Nest로 다시 넣음 (블록 복귀 / 재연결 / pull) | 신규 기능 다시 켜짐 |
| 양방향 전환 비용 | **0 (migration 없음, 무손실)** |

탈부착이 무손실인 이유: identity 블록과 옛 PLAN에 남은 `handoffs:` ref는 단일 모드에선 **inert 텍스트**(아무도 안 읽음)다. 떼어내도 안 깨진다.

정직한 단서: handoff 파일 자체는 **루트 repo(진실원천)**에 있으므로, 떼어낸 자식은 재연결+pull 전엔 그걸 못 본다(당연). push 안 한 발신 선언은 재연결까지 로컬에 남는다.

---

## 3. 모드 & nesting 감지

`scripts/lib/workspace.sh::scv_resolve_mode()` — 모든 명령이 시작 시 호출. **로컬 파일 + 로컬 frontmatter만** 본다 (네트워크 없음 → 단일 모드가 git/네트워크 의존을 절대 안 가짐).

```
SINGLE  : scv/CLAUDE.md 에 SCV:WORKSPACE 블록 없음 (또는 root 비어있음)   → 오늘과 동일
ROOT    : 이 repo 가 scv/WORKSPACE.yaml 보유                              → 우산
CHILD   : SCV:WORKSPACE 블록의 root 가 채워져 있음                         → 자식
```

- 기존 모든 repo, 새로 hydrate 한 단일 repo → 둘 다 없음 → **SINGLE**. hydrate는 이 둘을 만들지 않는다.
- CHILD 판정은 **명시적 포인터**(root URL/경로)로 한다. 디렉터리 인접성이 아니다 — FE/BE/AI가 다른 디스크에 있기 때문.
- **graceful degrade**: CHILD인데 root가 안 닿으면(오프라인/떼어냄) → 로컬 명령은 SINGLE처럼 정상 작동, cross-repo 부분만 "workspace root 도달 불가 — 로컬 전용으로 진행" 1줄 후 skip.

---

## 4. 레포 정체성 (현재 없는 식별자)

오늘 SCV에는 repo 정체성/role 필드가 **전혀 없다**(slug에도 repo 성분 없음). 죽은 frontmatter 훅을 재사용해 추가:

`scv/CLAUDE.md` 에 **`SCV:WORKSPACE` 마커 블록** (PROJECT:LOCAL 과 동일 plumbing — `merge.sh` replace_marker_block, `/scv:sync` 가 보존):

```
<!-- SCV:WORKSPACE START -->
repo_id: fe                 # 워크스페이스-글로벌 안정 id (기본=cwd basename, 편집 가능)
role: frontend
root: git@github.com:org/acme-root-scv.git   # 루트 scv repo (경로 또는 git URL). 비면 SINGLE
workspace: acme-platform
<!-- SCV:WORKSPACE END -->
```

- `repo_id` = 그동안 없던 **cross-repo 상관 키**.
- role 라우팅은 죽은 `applies_to:[]` 필드 재사용(현재 아무 스크립트도 안 읽음 → 단일 모드 무영향).
- 루트의 `scv/WORKSPACE.yaml` = 멤버 레지스트리 (flat + simple list, 기존 `yaml.sh` 파서 호환, 중첩 mapping 없음):

```yaml
workspace_id: acme-platform
members:
  - id: fe
    role: frontend
    url: git@github.com:org/fe.git
  - id: be
    role: backend
    url: git@github.com:org/be.git
  - id: ai
    role: ai-agent
    url: git@github.com:org/ai.git
```

---

## 5. handoff 레코드 (데이터 모델)

한 파일 = 한 handoff. **파일명이 글로벌 키** (없던 cross-repo 키를 파일명으로 제조). frontmatter는 전부 flat scalar + block list (= `yaml.sh` 무수정 파싱).

```
handoffs/raw/HANDOFF-20260624-fe-refund-button__to-be.md
```

```yaml
---
handoff_id: 20260624-fe-refund-button__to-be   # date-origin-target = 글로벌 유니크
from_repo: fe
from_slug: 20260624-sspark-refund-button       # 발신 promote/archive slug
to_repo: be                                     # 파일당 타깃 1개 (fan-out = 파일 N개)
decision: needed                                # needed | maybe | not-needed (명시적 결정)
status: open                                    # open | claimed | implemented | declined | superseded
title: BE needs POST /api/refunds for the FE refund button
created_at: 2026-06-24
created_by: sspark
conversation: conversations/20260624-refund-button.md
refs:                                           # 기존 3필드 type/id/url 형식 그대로
  - type: handoff-origin
    id: 20260624-sspark-refund-button
    url: https://github.com/org/fe/pull/812
  - type: scv-decision
    url: decisions/20260624-refund-button.md
---
# 결정 요약 (WHAT)
FE가 환불 버튼 배포(PR #812). POST /api/refunds 호출 → BE 구현 필요.

## 수신 레포 수용기준 (소비자 TESTS 시드)
- POST /api/refunds {orderId, amount} → 200 {refundId}; 중복 시 409.

## 다음 단계
BE: /scv:promote (이 handoff 로부터) → /scv:codegen
```

`handoffs:` 를 발신 PLAN.md frontmatter에도 동일 3필드 형식으로 기록(`type: handoff / id: <to_repo> / url: handoffs/<dir>`) — 단일 모드에선 inert.

---

## 6. 루트 repo 레이아웃 (산출물 위치)

전부 **루트 우산 scv repo의 git 트리** 안. 기존 raw|promote|archive 삼분구조를 그대로 미러 → 새 machinery 없음.

```
<root-scv-repo>/scv/
  CLAUDE.md                    # SCV:WORKSPACE 블록 (루트 자신)
  WORKSPACE.yaml               # 멤버 레지스트리 (= ROOT 모드 마커)
  handoffs/
    raw/        HANDOFF-...__to-be.md    # 갓 도착, 미처리
    promote/    (claimed = 대상이 작업 중)
    archive/    (implemented/declined) + ARCHIVED_AT.md
    INDEX.yaml  (자동 생성 캐시, archive/INDEX.yaml 방식)
  decisions/                   # 명시적 결정 기록 (verdict 의 진실원천)
    20260624-refund-button.md
  conversations/               # 커밋되는 대화 기록 (gitignore된 .conversations 와 별개)
    20260624-refund-button.md
```

> **중요**: 기존 `scv/.conversations/`(점 있음)는 gitignore·로컬 전용 유지. 새 `scv/conversations/`(점 없음)는 **의도적으로 커밋**되는 cross-repo "왜". 기존 ignore 규칙 안 건드림.

`readpath.sh` 가 `handoffs/raw` 를 추적 경로로 보면 → 들어온 handoff 가 평범한 "raw change(A/M/R)"로 노출(이미 아는 흐름).

---

## 7. 결정 + 대화 기록

두 산출물 분리, 둘 다 루트에 커밋(cross-repo 가시) + archive처럼 immutable:

1. **`decisions/<id>.md`** — 명시적 결정. flat frontmatter: `verdict: needed|maybe|not-needed`, `from_repo`, `targets: [be, ai]`, `handoffs: [...]`. 본문: 무엇을/왜/기각된 대안.
2. **`conversations/<id>.md`** — 그 결정을 낳은 대화(durable "왜"). 로컬 `.conversations` 스케치의 커밋되는 대응물.
3. **링크**: handoff.refs(type=scv-decision) → decision, decision.handoffs → handoff, 둘 다 → conversation. 어느 하나에서 나머지 둘 도달.
4. **불변성/lifecycle**: handoff가 `archive/`에 도달하면 `ARCHIVED_AT.md` 생성(work.sh 방식). 결정 번복 = 새 decision_id + 옛 handoff `status: superseded`(기존 supersede 어휘 재사용).

---

## 8. 엔드투엔드 루프 (명령·파일 매핑)

| 단계 | 행동 | 명령 | 재사용 |
|---|---|---|---|
| 0. 셋업(1회) | 루트 scv repo 생성 + `WORKSPACE.yaml`; 각 자식 join → `SCV:WORKSPACE` 블록 stamp | **`/scv:workspace`** (대화형 — 내부적으로 `hydrate --root` / `sync --join` 실행. 긴 플래그 불필요) | merge.sh 마커 |
| 1. FE 선언 | 대응개발 필요 명시 → handoff 파일 + decision + conversation 작성 | `/scv:handoff` | refs 3필드, AUTHOR |
| 2. 루트 전파 | `git -C <root> pull --rebase` → write → 명시 path add → commit → **동의 후 push** | (workspace.sh 내부) | work.sh archive 훅 |
| 3. BE 인지 | pull 후 "너에게 온 handoff" 표시 | `/scv:status` [7] | status.sh [6] 패턴, readpath |
| 4. BE 대응 | handoff → PLAN+TESTS 스캐폴드 → TDD 구현 → archive | `/scv:promote`(handoff-aware) → `/scv:codegen` → `/scv:work` | 기존 엔진 그대로 |
| 5. 연쇄 | BE가 AI로 다시 선언 | `/scv:handoff` | — |

---

## 9. 명령 표면 (codegen 재사용 — `/scv:generate` 없음)

| 명령 | 변경 | 단일 모드 |
|---|---|---|
| `/scv:workspace` (**신규**) | **대화형 멀티레포 셋업**: 합류(자식)/우산 만들기(루트)/분리. 내부적으로 `sync --join`·`init-root`·`detach` 실행 (긴 플래그 불필요). `scripts/workspace-helper.sh` | SINGLE이면 "합류/우산/단일" 선택지 제시 |
| `/scv:handoff` (**신규**) | 대응개발 필요 **명시 선언** → handoff/decision/conversation 작성 → 루트에 write → 동의 후 push | `--`: "single-repo: 전파할 workspace 없음" no-op |
| `/scv:promote` | **handoff-aware 확장**: handoff_id 주면 그 수용기준으로 PLAN+TESTS 스캐폴드(back-link ref) | 인자 없으면 오늘과 동일 |
| `/scv:codegen` | **변경 없음**. 스캐폴드된 promote를 TDD Red→Green으로 구현 | 동일 |
| `/scv:work` | archive 시점 opt-in 프롬프트: PLAN에 `handoffs:` 있으면 "루트로 전파?"(AskUserQuestion). 비-SINGLE만 발동 | gate 미발동 → 동일 |
| `/scv:status` | additive 섹션 **[7]** (handoff 수신/발신). 비-SINGLE만 출력 | 미출력 → byte-identical |
| `/scv:sync` | `--join <root-url>` 로 SCV:WORKSPACE stamp. 코어 sync는 PROJECT:LOCAL과 같은 경로로 블록 보존 | `--join` 없으면 동일 |
| hydrate | (선택) `--root` 로 WORKSPACE.yaml 생성. 기본은 안 함 → 새 repo는 SINGLE | 동일 |
| `/scv:regression` | per-target `cd` 버그 수정(SINGLE에선 같은 cwd로 cd = no-op). cross-repo 회귀는 범위 밖 | no-op |

소비자 신규 명령 **0개** (codegen 재사용). 신규 명령은 선언용 `/scv:handoff` 하나뿐 (이마저 work archive 프롬프트로 흡수 가능 — §14 참조).

---

## 10. 후방호환 & 탈부착 보장

**단 하나의 스위치**: `scv/CLAUDE.md` 의 `SCV:WORKSPACE` 블록(+ root 채워짐) 존재 여부.

- **없음/빈 root** (모든 기존 repo, 새 단일 repo) → `scv_resolve_mode`=SINGLE → `/scv:handoff`·status[7]·handoff readpath·work archive 프롬프트 전부 no-op/skip. status는 [1-6] byte-identical. promote/work/codegen/regression/sync/report 오늘과 동일.
- **있음+root 채워짐** → 비-SINGLE 자동 활성.

byte-identical 논거: (1) 모든 멀티레포 경로가 SINGLE에서 거짓인 술어로 gating, (2) 술어는 로컬 파일만(네트워크 0), (3) 새 frontmatter(`handoffs:`/`applies_to:`/마커)는 inert, (4) 유일하게 단일 repo를 건드리는 변경 = regression per-target cd 수정인데 cwd 발견 타깃엔 같은 cwd로 cd = 리터럴 no-op. 관측 가능한 유일 델타 = re-hydrate/sync 후 `scv/CLAUDE.md` 에 HTML 주석 마커 몇 줄(동작 아님).

탈부착(§2): 모드가 매 호출 재계산 + graceful degrade 이므로 블록 제거/복귀가 곧 detach/attach. 변환 비용 0.

---

## 11. 동시성 모델

루트 scv repo는 머신 간 쓰기 경합점. 충돌을 없앤다 주장하지 않고 **폭발 반경을 줄인다**:

1. **파일-단위-handoff, 공유 가변 파일 없음.** handoff_id로 키된 서로소 파일명 → git이 무충돌 머지(다른 경로). 큰 단일 리스트 append 없음 = 흔한 경우 구조적으로 무충돌.
2. **pull --rebase --autostash → write → push**, push 거부 시 1회 재-pull+재시도, 그래도 실패면 중단+사용자 보고. `-i`/force 없음(환경 미지원). `git -C <root>` 사용 → 자식 repo 상태 불건드림.
3. **유일 공유 가변 파일** `handoffs/INDEX.yaml` 은 **파생 캐시** — handoff 파일들에서 재생성. 충돌 시 `rm && regen`. 권위는 항상 handoff 파일 집합.
4. **상태 전이**(open→claimed)는 단일 파일 scalar 편집 = 파일 범위. 같은 handoff 동시 claim만 진짜 레이스 → last-push-wins + 패자는 rebase 시 'claimed' 확인.
5. **안 푸는 것**: 분산 락/다중파일 원자성 없음. cross-repo handoff는 사람-속도 저빈도 이벤트라 낙관적 동시성으로 충분. 빈도 오르면 탈출구 = 루트 쓰기를 단일 CI 엔드포인트로 직렬화(포맷 불변).

---

## 12. 단계별 롤아웃

**Phase 1 (MVP) — 탈부착 기반 + 선언 + 표면화**
- `lib/workspace.sh`(매-호출 모드 재계산 + graceful degrade), `SCV:WORKSPACE` 블록(토글), `/scv:handoff`(선언→루트 write→동의 push), `/scv:status` [7].
- 산출: "FE 선언 → BE가 pull 시 인지" + 탈부착 자유. (구현 엔진 없음)
- 효과: **이 단계가 탈부착 불변식을 박으므로**, 이후 모든 기능이 자동으로 "떼면 원래대로" 보장.

**Phase 2 — 소비자 경로 (기존 codegen)**
- `/scv:promote` handoff-aware 확장 → 기존 `/scv:codegen`(TDD) → `/scv:work` archive.
- 산출: "BE가 handoff를 TDD 구현으로." (신규 명령 0개)

**Phase 3 (선택)**
- cross-repo 회귀(per-target cd 버그 수정 후), notifier 알림(notifier_post_message 재사용, best-effort), decision/conversation 기록 강화.

순서 근거: Phase 1 단독으로도 루프의 절반(선언+인지)이 돌고 위험이 가장 낮다. Phase 2는 그 위에 자동구현을 얹는다.

---

## 13. 정직한 한계 / 범위 밖

- `/scv:codegen` 결과 품질 = **handoff 수용기준 품질에 종속**. 자동구현도 결국 codegen TDD 게이트에 기댐 → 부실한 handoff = 부실한 결과. 좋은 handoff 작성이 진짜 일(선언당 1회).
- cross-repo **회귀**(FE 바꾸면 BE 테스트가 한 번에 RED)는 이번 범위 밖. 지금 전파 = "BE에 handoff가 뜬다"지 "BE 테스트가 자동 깨진다"가 아님(후자는 계약 필요, 아직 없음).
- cross-repo **PR 생성** 범위 밖(PR 레이어 cwd/origin 고정).
- **셋업 비용**: 누군가 루트 scv repo 호스팅, 각 자식 1회 join.
- **선언 의존**: 선언을 깜빡한 cross-repo 영향은 못 잡음(설계상 — diff 자동감지 비목표). 이를 메우는 건 나중 계약 도입.

---

## 14. 열린 결정 (구현 전 확정 권장)

1. **선언 명령 모양**: 별도 `/scv:handoff` vs `/scv:work` archive 프롬프트로 흡수. → *권장: 별도 `/scv:handoff`* (단일 책임, archive와 무관하게 선언 가능). work 프롬프트는 편의로 추가.
2. **루트 작업본 위치**: `root` 가 URL일 때 어디에 클론? → *권장: `~/.cache/scv/<workspace>/root`, `git -C` 로만 조작.*
3. **join 방법**: `sync --join <url>` vs `hydrate --root` vs 수동. → *권장: 자식은 `sync --join`, 루트는 `hydrate --root`.*
4. **INDEX.yaml 작성자**: 매 push마다 자식 vs 단일 소유자(CI/`--regen-index`). → *권장: 파생 캐시로 두고, 경합 보이면 단일 소유자로.*

---

## 15. 파일 변경 매니페스트 (코드 기준 — 구현 전 재확인)

신규:
- `scripts/lib/workspace.sh` — `scv_resolve_mode()`, repo_id/role/root 리더, graceful degrade.
- `commands/handoff.md` + `scripts/handoff.sh` (또는 work 흡수).
- `template/scv/WORKSPACE.yaml.example`.
- `template/scv/CLAUDE.md` 에 주석처리된 `SCV:WORKSPACE` 블록(주석=탐지상 부재).

확장(전부 비-SINGLE gating, additive):
- `scripts/status.sh` — 섹션 [7] (기존 [6] 블록 ~307-328 미러).
- `commands/promote.md` / `scripts/promote-helper.sh` — handoff-aware 스캐폴드.
- `scripts/work.sh` — archive 블록(~159-255, INDEX regen ~230-251)에 mode-gated handoff 미러 + 선택 프롬프트.
- `scripts/hydrate.sh` — `replace_simple_marker`(~107-110)로 repo_id/role stamp; `--root`.
- `scripts/sync.sh` — `--join`; `SCV:WORKSPACE` 를 PROJECT:LOCAL과 같은 merge-on-markers로 보존.
- `scripts/regression.sh` — per-target `cd` 버그 수정(~415/417; SINGLE no-op).

불변(재사용만):
- `scripts/lib/merge.sh`(마커 plumbing), `scripts/lib/yaml.sh`(flat 파싱), `scripts/readpath.sh`(추적 경로), `commands/codegen.md`(엔진), `scripts/notifiers/*`(Phase 3).

> ⚠ 위 file:line은 직전 코드-리딩(에이전트)에서 수집. 구현 착수 시 각 위치 재확인 필요.
