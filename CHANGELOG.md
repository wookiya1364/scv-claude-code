# Changelog

이 저장소의 변경사항을 기록합니다. [Semantic Versioning](https://semver.org/lang/ko/) 규칙을 따릅니다.

## [0.7.3] — 2026-05-04

### 핵심 — 사용자 언어 미스매치 자동 감지 + dialog 한 번 + cache + PR/도식 풀 다국어화

`/scv:promote` 호출 시 사용자의 글로벌 언어 설정 (`settings.json language`) 과 프로젝트 언어 설정 (`.env SCV_LANG`) 이 *둘 다 명시적으로 설정되어 있고 다른 경우*, 어느 언어로 산출물 (PLAN.md / TESTS.md / FEATURE_ARCHITECTURE.md / 도식 / commit / PR title / PR body) 을 작성할지 한 번 묻고 그 결정을 `.env SCV_PROMOTE_LANG` 에 캐시. 다음 promote 부터는 캐시된 결정을 inline 한 줄 안내 (sed 명령 포함) 와 함께 사용 — dialog 안 발화.

배경: 사용자 명시 요청 — "PR, 아키텍처가 영어로 되어있어서 불편하네... 만약 유저언어가 한국어이고, 프로젝트 env설정에서 유저언어랑 다를 경우, PR을 한국어, 영어, 일본어 등등 어떤 것으로 올릴지 물어봐줘". 매번 묻는 건 귀찮으니 cache + inline 안내로 마찰 ↓.

**i18n 정책 변경 (정직 명시):** v0.4.0 부터 박혀있던 정책 ("영어 단일 source of truth + Claude 응답 다국어 = 합리적 균형") 의 *template* 영역이 일부 변경됨. `scripts/pr-helper.sh` 의 fixed 라벨 (`## Summary` / `🗂 Archived` 등) 이 PLAN.md frontmatter `lang:` 따라 한국어 / 일본어 / 영어 분기. 메모리 reference / project 갱신 (사용자 명시 결정 = "B 옵션 — Full localization").

### Added

- **`commands/promote.md` Step 0 — Language alignment (신규)** — Step 1 직전. 5 분기 (둘 다 미설정 / 한쪽만 / 같음 / 다름+캐시 / 다름+캐시없음). 다름+캐시없음 시 `AskUserQuestion` 4-way ([1] English / [2] 한국어 / [3] 日本語 / [4] free-form). 결과를 `.env SCV_PROMOTE_LANG=<value>` 에 자동 저장 (free-form 제외).
- **inline 안내 (다름+캐시 발견 시)** — dialog 안 발화. 한 줄로 "Promote language: 한국어 (cached: SCV_PROMOTE_LANG=korean in .env). Settings mismatch: settings.json=korean, .env SCV_LANG=english. To change: sed -i ... To clear cache: sed -i ...". 복붙 가능한 정확한 sed 명령.
- **PLAN.md frontmatter `lang:` field** — Step 0 의 `LANG_RESOLVED` 가 박힘. `/scv:work` Step 9d 와 `pr-helper.sh` 가 후속 단계에서 읽어서 일관 적용.
- **Step 6.1 mapping rule #5 신규** — Mermaid node labels / edge labels / subgraph names 가 `LANG_RESOLVED` 따라감. 단 component identifiers (`OrderService` 같은 Mermaid node ID) 는 영어 유지 (Mermaid syntax 안정성), function names / SQL / HTTP verbs 는 verbatim (다국어 무관).
- **`scripts/pr-helper.sh` 라벨 다국어 분기 (en / ko / ja, fallback en)** — PR body 의 fixed 라벨 모두 PLAN.md `lang:` 따라 분기:
  - 한국어: `## 요약` / `## 목표 / 비목표` / `## 단계` / `## 테스트` / `## 아키텍처 도식` / `## 테스트 증거` / `### 비디오` / `### 스크린샷` / `## 외부 참조` / `🗂 보관됨 ... 작성자 ...`
  - 일본어: `## 概要` / `## 目標 / 非目標` / `## ステップ` / `## テスト` / `## アーキテクチャ図` / `## テスト証跡` / `### ビデオ` / `### スクリーンショット` / `## 外部参照` / `🗂 アーカイブ済み ... 作成者 ...`
  - 영어 (fallback): 기존 그대로
  - `extract_section` 의 PLAN/TESTS heading 매칭 regex 도 다국어 alternation 추가 (`Summary|요약|概要` 등) — 사용자가 PLAN 의 헤딩을 그 언어로 작성해도 추출됨.
- **`commands/work.md` Step 9d-main `[1] Yes` description 갱신** — frontmatter `lang:` 읽고 PR body labels 가 그 언어로 분기됨을 명시.
- **`template/scv/PROMOTE.md`** — §4 frontmatter 표에 `lang` 행 추가 + §5b (FEATURE_ARCHITECTURE.md spec) frontmatter 에 `lang:` 한 줄 명시.
- **`template/.env.example.scv`** — `SCV_PROMOTE_LANG` 섹션 신규 + 변경 / 클리어 sed 명령 안내.

### Tests

- 신규 섹션 **[11ddd]** (~35 assertion):
  - Step 0 Language alignment 의 5 분기 표 / cache 안내 sed 명령 / AskUserQuestion 4 옵션 / `LANG_RESOLVED` 명시
  - PLAN.md frontmatter `lang: <LANG_RESOLVED>` 명시
  - Step 6.1 mapping rule #5 (Mermaid 라벨 다국어, identifier 영어 유지)
  - work.md Step 9d 의 `Read \`lang:\` from the archived PLAN.md frontmatter` 안내
  - pr-helper.sh 의 case statement 3 분기 (en/ko/ja) + 핵심 라벨 변수 설정
  - PROMOTE.md / .env.example.scv 의 lang 설명
  - **Isolated pr-helper dry-run** — dummy archives (test-en / test-ko / test-ja / test-other) 만들어 lang frontmatter 별 PR body 출력 검증:
    - lang=english → `## Summary` + `🗂 Archived`
    - lang=korean → `## 요약` + `🗂 보관됨`
    - lang=japanese → `## 概要` + `🗂 アーカイブ済み`
    - lang=spanish (unknown) → English fallback
- 회귀: 654 → **689 PASS** (+35 assertion) / 0 FAIL.

### Changed

- **`.claude-plugin/plugin.json`** — version `0.7.2` → `0.7.3`.
- **`README.md`** — 회귀 배지 654 PASS → 689 PASS.
- **i18n 정책 (메모리 갱신)** — v0.4.0 부터의 "template 영어 단일 source" 정책이 *부분 변경*. `scripts/pr-helper.sh` 의 PR body 라벨이 `lang:` 따라 분기 (template 의 일부 부위가 다국어). 메모리의 `project_scv_current_state.md` + `reference_scv_resume_guide.md` 에 정책 변경 명시.

### Backwards compat

- 기존 사용자에게 동작 변화 1 가지 — `/scv:promote` 호출 시 settings.json language ≠ .env SCV_LANG 인 경우 한 번 dialog. 양쪽 같거나 한쪽만 설정 → 기존과 동일 (dialog 없음).
- v0.7.2 이전 archived PLAN.md 에 `lang:` 없음 → pr-helper.sh 의 case statement default (English) → 기존 동작과 100% 동일. 자동 backfill 안 함 (역사적 사실 보존).
- `extract_section` regex 가 multi-lang alternation 으로 확장 → 영어 헤딩 (`## Summary`) 만 있는 기존 PLAN.md 도 정상 동작.

### 비채택

- **dialog 결과를 `.env SCV_LANG` 자체에 갱신** (mismatch 자체 해소) — 사용자가 글로벌 settings.json 과 프로젝트 .env 를 *다르게 설정한 의도* 가 있을 수 있음. SCV 가 갱신하면 그 의도 침범. 별도 cache 키 (`SCV_PROMOTE_LANG`) 로 mismatch 상태 유지하면서 promote-time 결정만 캐시.
- **글로벌 cache (홈 디렉토리)** — 프로젝트별로 다른 결정 가능 (회사 A 영어 / 회사 B 한국어). 프로젝트 `.env` 가 적절.
- **AskUserQuestion 에 "이번만 / 캐시" 분리 옵션** — 옵션 너무 많음. [1]/[2]/[3] 은 자동 캐시, [4] free-form 만 캐시 안 함 — 단순 패턴.
- **mmdc / mermaid lint** — v0.7.1 비채택 그대로 유지.

### 검증 한계

- *실제 mismatch 상황* 의 dialog → 캐시 → inline 안내 흐름을 별도 Claude 세션에서 풀 검증 안 함. promote.md 의 prompt + pr-helper.sh 의 case statement 는 isolated 어설션 + dry-run 으로 검증, dialog UX 는 사용자가 다음 SCV 사용 시 자연스럽게 검증.
- 일본어 / 한국어 라벨의 자연스러움 (`## 요약` / `## 概要` 등 의 적절성) 은 LLM 판단 — 네이티브 사용자가 부자연스럽다 보면 v0.7.x patch 후보.
- pr-helper.sh 의 다국어 라벨이 free-form lang (`spanish` / `french` 등) 에 대해선 영어 fallback. 진짜 다국어 지원은 en/ko/ja 만. 다른 언어 사용자는 free-form [4] 로 가도 PR body 라벨은 영어가 됨.

### 메모

- 이 변경은 사용자 명시 요청 — "PR 올리는 것도 사용자 언어 설정에 맞게... 매번 다시 물으면 좀 귀찮을거같네... 정한 값을 유지... 이전에 결정한 언어로 작성을 한다... 복사붙여넣기 해서 언어 바꿀 수 있도록 쉽게 안내".
- v0.7.2 resume guide → v0.7.3 resume guide 로 대체.

---

## [0.7.2] — 2026-05-04

### 핵심 — pr-helper.sh awk 의 closing-fence guard + GitHub mermaid 렌더 실증 검증

v0.7.1 출시 직후 사용자가 "검증 안 한 것 검증해봐" 지적 → 실제 검증 결과 awk 의 닫는-fence 누락 케이스 (시나리오 B) 에서 PR body corruption 위험 발견. fix + dummy PR 만들어 GitHub 가 mermaid 실제 렌더하는지 실증 확인.

배경:
- v0.7.1 awk 가 simple case (heading 2 + mermaid 2) 만 isolated 검증 → 5 복잡 시나리오 검증 시 시나리오 B (LLM 이 닫는 ` ``` ` fence 빠뜨린 손상 입력) 에서 awk 가 파일 끝까지 mermaid block 으로 처리 → PR body 의 모든 후속 콘텐츠 (Tests / Refs / Archived 정보 등) 가 깨진 mermaid block 안에 가둬짐.
- GitHub vs GitLab mermaid 렌더는 *알려진 사실* 이라 표현했으나 실제 검증 안 함 → dummy PR 만들어서 GitHub 의 server-side rendering 에서 `highlight-source-mermaid` class 가 적용되는지 확인.

### Added

- **`scripts/pr-helper.sh` awk 에 `END` block guard** — closing fence 누락 시 자동 보강:
  ```awk
  END { if (in_mermaid) { print "```"; print "" } }
  ```
  손상 입력에서 mermaid block 이 파일 끝까지 잡아먹는 사고 방지. mermaid renderer 는 깨진 콘텐츠를 syntax error 로 표시하지만 PR body 의 *다른 섹션* (Tests / Refs / Archived) 은 정상 보존.

### Tests

- 신규 섹션 **[11ccc]** (~13 assertion) — pr-helper awk 의 5 복잡 시나리오 isolated 검증:
  - **Scenario A** (heading 3 개) — 셋 다 정확 추출, 6 fences (3 mermaid 시작 + 3 close).
  - **Scenario B** (closing fence 누락) — END block 자동 보강 동작 확인 (2 fences = mermaid 시작 + auto-close), 마지막 줄 closing fence 위치 검증.
  - **Scenario C** (빈 mermaid 블록) — heading 추출 정상.
  - **Scenario D** (다른 fence 섞임 — bash, yaml) — mermaid 만 추출, bash/yaml content 누설 안 함.
  - **Scenario E** (블록 사이 markdown content) — description / Source 줄 / intro text 모두 누설 안 함.
  - **Sanity** — 정상 케이스에서 END block 이 중복 fence 추가 안 함 (4 fences).
- 회귀: 641 → **654 PASS** (+13 assertion) / 0 FAIL.

### 검증 — GitHub mermaid 렌더 실증

dummy PR (#8) 만들어 GitHub 의 server-rendered HTML 확인 → **`<div class="highlight highlight-source-mermaid">` 로 두 mermaid block 모두 처리됨**. `highlight-source-mermaid` 는 GitHub 의 mermaid 인식 marker (client-side mermaid.js 가 SVG 변환). PR 페이지에서 시각 확인 후 close + branch 삭제 (https://github.com/wookiya1364/scv-claude-code/pull/8 closed).

GitLab 은 본 repo mirror 가 없어 직접 검증 안 함 — GitLab docs 의 mermaid 지원 명시는 *알려진 사실* 로 남김 (사용자가 GitLab 환경에서 직접 검증 가능).

### Changed

- **`.claude-plugin/plugin.json`** — version `0.7.1` → `0.7.2`.
- **`README.md`** — 회귀 배지 641 PASS → 654 PASS.

### Backwards compat

- v0.7.1 정상 케이스와 동작 100% 동일 (sanity check 로 입증). END block 은 *손상 입력에만* 발화.
- archived 폴더의 FEATURE_ARCHITECTURE.md 가 정상 (양 fence 모두 있음) 이면 PR body 변화 0.

### 비채택

- **시나리오 C (빈 mermaid 블록) 의 noise 제거** — mermaid 안 fenced block 이 빈 채로 PR body 에 들어가도 GitHub 는 빈 영역만 표시 (에러 아님). 작은 noise 라 영구 수용. 처리하려면 `END` block 외에도 빈 블록 detection 필요 → 복잡도 증가 비용 > 효과.
- **GitLab 검증을 위한 dummy GitLab repo 생성** — 본 repo 와 떨어진 인프라 (별도 GitLab account / repo / glab CLI 인증). 비용 높음. GitLab docs 의 mermaid 지원 명시로 충분.

### 검증 한계

- LLM 행동 정확도 *실제 향상* — v0.7.1 의 prompt 보강이 진짜 효과 있는지는 사용자가 비교 사용해야 데이터 들어옴. 본 patch 는 awk 안전성만 강화.
- awk 의 7+ 시나리오 (e.g., heading 5 개 / mermaid block 안에 ` ``` ` 가 escape 되어 있는 케이스) 는 unit test 안 함 — 발견 시 v0.7.x patch 후보.
- GitHub 의 mermaid 렌더는 server-side `highlight-source-mermaid` class 까지 확인. 실제 SVG 변환은 client-side JS 로 사용자가 PR 페이지에서 직접 본 것이 검증.

### 메모

- 이 patch 는 v0.7.1 출시 후 사용자 즉각 ("확인을 제대로 해주라") 요청 → 5 복잡 시나리오 검증 + 시나리오 B fix + dummy PR 실증 + close. 실제 위험 발견 + 해소.
- v0.7.1 resume guide → v0.7.2 resume guide 로 갱신.

---

## [0.7.1] — 2026-05-04

### 핵심 — v0.7.0 의 도식 정확도 + 리뷰 사이클 강화 (3 영역 동시)

v0.7.0 출시 후 사용자가 검증 한계 (LLM Mermaid 정확도 미시뮬레이션 + graphify graph.json → flowchart 매핑 logic 명세 부족) 를 지적 → 즉시 patch. 사용자 명시 결정 = "(가) 묶음 patch".

배경: v0.7.0 의 두 도식 자동 생성은 *하부 인프라 (promote-helper, ARCHITECTURE.md status 추출, graph mtime 비교)* 가 4 시나리오 모두 검증됐지만, *LLM 행동 정확도 (도식 노드 / 매핑 / Source 줄)* 는 prompt 보강과 사용자 검토 사이클로만 향상 가능. 이번 patch 가 그 부분을 메움.

### Added

- **`commands/promote.md` Step 6.1 — Mermaid prompt 보강** — "Mapping rules (must follow)" 4 항목 (모든 컴포넌트 노드화 / 외부 시스템은 cylinder / 모든 edge 에 라벨 / 발명 금지) + "Anti-patterns to avoid" 5 항목 (skeleton 베끼기 / 라벨 없는 화살표 / 모든 노드 cylinder / 일반 데이터 명 / 12 노드 초과). 사용자가 검증한 시뮬레이션 사례 외 진짜 LLM 출력에서 자주 보이는 실수를 명시 차단.
- **`commands/promote.md` Step 6.2 — graphify mapping algorithm 명시** — 두 번째 그림의 데이터 소스별 매핑 절차:
  - Source = `scv/ARCHITECTURE.md`: Logical view 의 service 명칭을 subgraph 로 그대로 사용.
  - Source = graphify `graph.json`: (1) communities → subgraph (graphify 가 만든 plain-language label *그대로* 사용, LLM 재해석 금지) (2) god_nodes 만 노드화 (수백 노드 그리지 말 것) (3) top-weight links 만 edge (god 노드 양 끝 + weight 상위 8-12) (4) 새 컴포넌트는 PLAN.md 에서 추출 + `:::new` (5) 새-기존 edge 는 dashed `-.->`.
- **`commands/promote.md` Step 6.4 — Self-review (신규 단계)** — 도식 작성 후 LLM 자가 점검 8 항목 (Coverage / No inventions / Edge labels / 외부-내부 노테이션 / Source 줄 / `:::new` 클래스 / Dashed edges / Mermaid fence). 결과는 사용자에게 *내부적으로* 처리 — material fix 가 발생한 경우만 "Self-review: added 1 missing component (...)" 형태로 confirmation 라인에 추가.
- **`scripts/pr-helper.sh` — FEATURE_ARCHITECTURE.md inline 자동 첨부** — `FEATURE_ARCH_FILE` 변수 추가, `## Steps` 다음에 PR body 조립 단계에서 awk 로 ` ```mermaid ` 블록 두 개 추출 + `## Architecture diagrams` 섹션으로 inline. frontmatter / Source 줄 / heading 본문은 제외, mermaid 블록만. GitHub / GitLab 모두 PR / MR description 의 mermaid fenced block 자동 렌더 → 리뷰어가 PR 페이지에서 도식 즉시 확인 → 부정확한 부분 코멘트로 피드백.
- **`commands/work.md` Step 9d-main — PR 생성 안내 갱신** — `[1] Yes` 의 description 에 "FEATURE_ARCHITECTURE.md 가 있으면 두 Mermaid 블록 inline 포함, GitHub / GitLab 자동 렌더, 리뷰어 design-at-a-glance" 한 줄 추가.

### Changed

- **`.claude-plugin/plugin.json`** — version `0.7.0` → `0.7.1`.
- **`README.md`** — 회귀 배지 599 PASS → 641 PASS.

### Tests

- 신규 섹션 **[11bbb]** (~42 assertion):
  - Step 6.1 의 Mapping rules + Anti-patterns 핵심 문구
  - Step 6.2 의 mapping algorithm (communities / god_nodes / top-weight / 새 컴포넌트 / dashed edges) + Anti-patterns
  - Step 6.4 self-review 8 체크리스트 + 사용자 보고 문구
  - work.md Step 9d-main 의 inline 도식 안내
  - pr-helper.sh 의 FEATURE_ARCH_FILE 변수 + Mermaid 블록 추출 awk 로직
  - **awk 로직 isolated 검증** — 임시 FEATURE_ARCHITECTURE.md 만들어서 추출 결과 검증 (`### 1.` / `### 2.` 헤딩 변환 / mermaid fence 정확히 2 개 / Source 줄 제외).
- 회귀: 599 → **641 PASS** (+42 assertion) / 0 FAIL.

### Backwards compat

- v0.7.0 와 동작 호환성 100% — 새 어떤 분기 / dialog 도 추가 없음. promote.md 의 prompt 만 보강, work.md / pr-helper.sh 의 PR body 조립만 보강.
- v0.7.0 archived 폴더의 FEATURE_ARCHITECTURE.md 가 있으면 다음 PR 생성 시 자동으로 inline 포함됨 (역방향 적용 OK).
- FEATURE_ARCHITECTURE.md 없는 archived 폴더는 PR body 변화 0 (조건부 분기).
- v0.6.2 이전 archived 폴더 (FEATURE_ARCHITECTURE.md 미존재) 는 PR body 변화 0.

### 비채택

- **Mermaid CLI (mmdc) 자동 lint** — 검토했으나 미채택. 진짜 문제는 syntax 가 아니라 *내용 정확도* (PLAN 의 컴포넌트가 빠지거나 발명됨); Mermaid syntax 자체는 LLM 이 거의 항상 맞음. mmdc 도입은 npm/Node 의존성 추가 + install-deps.sh 갱신 필요 → 비용 대비 효과 낮음.
- **Concrete examples 다수 추가** — 검토했으나 미채택. "예시 베끼기" 행동 유발 위험. 현재 skeleton 1 개 + Anti-patterns 명시가 균형.
- **graphify query 호출 (도식용)** — `/graphify query "..."` BFS subgraph 반환은 도식 1 개당 추가 호출 + 토큰 사용 → 무거움. 대신 graph.json 의 community + god_nodes 직접 활용 (mapping algorithm) 으로 0 추가 호출.

### 검증 한계

- LLM 행동 정확도의 *실제 향상* 은 시뮬레이션 안 함. promote.md prompt 보강의 효과는 사용자가 v0.7.0 + v0.7.1 흐름을 비교 사용했을 때만 확인 가능.
- Mermaid block 추출 awk 로직은 **간단한 케이스** (heading 2 개 + mermaid 블록 2 개) 로만 검증. 복잡 케이스 (heading 3 개 / mermaid 블록 부분 손상 / 빈 블록) 는 unit 테스트 안 함.
- PR body 의 GitHub vs GitLab 자동 렌더 동작 *실제 검증 안 함* — 두 플랫폼 모두 mermaid fenced block 지원한다고 알려졌지만, 실제 PR/MR 만들어 확인 안 함. Bitbucket 은 미지원 (description 에서) — 이번 patch 영향 범위 밖.

### 메모

- 이 변경은 **v0.7.0 출시 직후 사용자 즉각 피드백 → 묶음 patch (가)** 로 진행. v0.6.2 의 "real user feedback 단계, treadmill 회피" 정책 일관 — 이번도 사용자 명시 요청.
- v0.7.0 resume guide 는 v0.7.1 resume 로 대체 (혼란 회피).

---

## [0.7.0] — 2026-05-04

### 핵심 — `/scv:promote` 가 PLAN.md / TESTS.md 옆에 `FEATURE_ARCHITECTURE.md` 도 자동 생성 (옵트인)

`/scv:work` 로 구현 들어가기 전에 *기능 단위 아키텍처 도식* 두 개를 PLAN 옆에 미리 그려서, 구현자 / 리뷰어 / 이해관계자가 같은 그림으로 출발하도록 함. fast-path 같은 trivial 변경엔 dialog 의 [2] "skip" 한 번이면 끝 — 별도 플래그 없음.

배경: 사용자가 backlog 에서 새로 결정한 항목 ("기능 한 개 = 두 그림 최소: 1) 컴포넌트 데이터 흐름 2) 전체 아키텍처에서 차지하는 위치"). DISCUSS treadmill 회피 정책 (v0.6.2) 유지하면서 사용자 명시 요청만 진행.

### Added

- **`commands/promote.md` Step 6 — Architecture diagrams** — Step 5 (PLAN/TESTS 작성) 다음에 폴더당 한 번 `AskUserQuestion` (3-way: yes / no / 주관식). [1] 선택 시 Step 6.1 ~ 6.3 으로 `FEATURE_ARCHITECTURE.md` 작성. 기존 Step 6 (readpath) → Step 7, Step 7 (Report) → Step 8 로 번호 밀림.
- **Step 6.1 첫 번째 그림 — Component data flow** — `flowchart LR` (또는 TB) 로 PLAN.md 의 Approach Overview / Steps 에서 식별한 컴포넌트들이 어떤 함수 호출 / 이벤트 / 페이로드 로 데이터를 주고받는지. 외부 시스템은 `[(...)]` cylinder 노드.
- **Step 6.2 두 번째 그림 — Position in whole architecture** — 데이터 소스 분기:
  - `scv/ARCHITECTURE.md` `status: active|draft` → 그 내용을 layout reference 로 사용
  - `status: N/A` + graphify graph 가 fresh → `.graphify/docs/graphify-out/graph.json` 사용
  - `status: N/A` + graphify available + graph stale/missing → 3-way `AskUserQuestion` (run graphify update / skip / 주관식)
  - `status: N/A` + graphify missing → 2-way `AskUserQuestion` (skip / 주관식)
  - `flowchart TB` + subgraph (layer/domain) + `classDef new fill:#FFE082,stroke:#F57C00` 로 신규 컴포넌트 강조 (`:::new`).
- **Step 6.3 — `FEATURE_ARCHITECTURE.md` 파일 템플릿** — frontmatter (title/slug/created_at/status) + `## 1. Component data flow` + `## 2. Position in whole architecture` (Source 줄 mandatory). Diagram 2 가 skip 되면 §2 가 "lift ARCHITECTURE.md or run /graphify" 한 줄 안내로 대체.
- **`template/scv/PROMOTE.md` §5b** — 표준 문서에 `FEATURE_ARCHITECTURE.md` spec (왜 두 그림 / 왜 옵트인 / 데이터 소스 결정 트리 / 파일 위치 / frontmatter / 본문 skeleton / convention).
- **`template/scv/PROMOTE.md` §3** — free-extension 디렉토리 예시에 `FEATURE_ARCHITECTURE.md` 한 줄 추가 (다른 free files 와 동일 레벨).

### Changed

- **`.claude-plugin/plugin.json`** — version `0.6.2` → `0.7.0`.
- **`README.md`** — 회귀 배지 557 PASS → 599 PASS, 5-Minute Walkthrough 의 Min 2 (`/scv:promote`) 에 도식 단계 한 줄 추가 (3 언어).

### Tests

- 신규 섹션 **[11aaa]** (~42 assertion):
  - `commands/promote.md` Step 6 의 AskUserQuestion 옵션 텍스트 (3-way) + Step 6.1 ~ 6.3 의 핵심 키워드
  - graphify 분기 표 (active/draft/N/A × built/stale/missing/skill missing)
  - 3-way / 2-way `AskUserQuestion` 텍스트 (run graphify / skip diagram 2 / 주관식)
  - Mermaid `flowchart LR` / `flowchart TB` / `classDef new fill:#FFE082` / `:::new`
  - Step 6 의 [2] "No" 분기 (skip the rest of Step 6)
  - 기존 Step 6, 7 → Step 7, 8 로 번호 밀린 것
  - `template/scv/PROMOTE.md` §5b spec + §3 디렉토리 예시
- 회귀: 557 → **599 PASS** (+42 assertion) / 0 FAIL.

### Backwards compat

- **기존 사용자에게 동작 변화 1 가지** — `/scv:promote` 호출 시 **폴더당 한 번 더 질문 (도식 그릴까?)**. 사용자가 [2] "No" 한 번이면 v0.6.2 와 동일 흐름 (PLAN.md + TESTS.md 만). [1] 선택 시 `FEATURE_ARCHITECTURE.md` 도 추가로 생성.
- `FEATURE_ARCHITECTURE.md` 는 **`/scv:work` / `/scv:regression` 에서 enforce 안 함** — 인간 이해 도구일 뿐, 게이트 아님. v0.6.2 기존 archived 폴더 무영향.
- v0.6.2 이전 archived 폴더는 `FEATURE_ARCHITECTURE.md` 없이 보존됨 (역사적 사실, 자동 backfill 안 함).
- `scv/ARCHITECTURE.md` `status: N/A` 가 적용된 adoption-mode 사용자: graphify 도 미설치라면 [11aaa] 의 2-way 분기에서 [1] "Skip diagram 2" 한 번이면 첫 번째 그림만 받음 — 추가 의존성 없음.

### 비채택

- **fast-path 면제 자동 트리거** — 검토 옵션 A (promote 호출 자체가 안 됨, 자연스러운 면제) / B (LLM 이 PLAN size 보고 판단) / C (매번 사용자 묻기) 중 사용자 결정 = **C**. A 는 사용자가 promote 호출 후에도 trivial 변경이라고 판단할 수 있어 한계, B 는 LLM 판단 신뢰도 낮음. C 는 매번 묻는 마찰이 있지만 사용자가 옵션·플래그 추가를 원치 않은 정책과 일관되며, 사용자 결정권 보존.
- **자동 graphify --update 호출** — 사용자 모르는 토큰 사용 발생 (`graphify-out/cost.json` 에 기록되긴 하지만 사용자가 매번 확인 안 함) + graphify 미설치 환경 에러. 대신 stale/missing 감지 시 `AskUserQuestion` 으로 사용자 결정.
- **`--architecture` / `--no-architecture` CLI 플래그** — 사용자 명시 거부 ("슬래시 명령어나 옵션이 더 추가되는 것을 원치 않음"). 매번 dialog 가 일관 패턴.
- **Mermaid 자동 syntax 검증** — LLM 결과의 Mermaid 문법 에러 가능성에 대해 자동 lint 도입 검토 → 채택 안 함. 출력에 "Review Mermaid syntax — LLM-generated" 한 줄 안내 + 사용자 검토 흐름이 PLAN/TESTS 와 동일 패턴.

### 검증 한계

- 별도 Claude 세션에서 `/scv:promote` 의 새 Step 6 풀 흐름은 미검증 (사용자 본인이 다음 SCV 사용 시 자연스럽게 검증). regression 은 텍스트 어설션 레벨.
- LLM 이 만드는 Mermaid 의 *실제 정확도* 는 시뮬레이션 안 함 — 사용자 검토 흐름에 의존.
- graphify graph.json 으로 두 번째 그림 만드는 *구체 매핑 로직* 은 promote.md 의 텍스트 가이드 레벨 (graph.json → flowchart 자동 변환 코드 미작성). LLM 이 graph.json 의 community / god nodes 를 보고 자유롭게 layout 작성. 정확도는 corpus 와 graph 품질에 따라 변동.

### 메모

- 이 변경은 **사용자 backlog 결정 (b) — DISCUSS §7 의 14 항목 외 신규 결정** 으로 진행. 메모리 `project_scv_current_state.md` 는 v0.6.2 → v0.7.0 으로 갱신, "real user feedback 단계" 명제는 유지 (이번도 사용자 명시 요청).
- 이전 v0.6.2 resume guide (`~/.claude/plans/scv-resume-after-v0.6.2.md`) 는 v0.7.0 resume 로 대체 (혼란 회피, v0.6.2 → v0.5.0 와 동일 정리 패턴).

---

## [0.6.2] — 2026-04-30

### 핵심 — README 재구조 (Why SCV? + 5 분 walkthrough)

DISCUSS.md 의 README 가 가치 못 드러내는 약점 마무리. 기능 표 중심 → 가치 + 시나리오 중심으로 hero 다음 두 신규 섹션 추가. 3 언어 모두.

### Added

- **`README.md` "Why SCV?" 섹션** (3 언어) — hero "What is SCV?" 다음, "Quick Start" 전. AI 코드 짜는 흐름에서 마주치는 3 문제 + SCV 답:
  1. **AI 가 짠 코드 리뷰가 괴롭다** — Playwright 비디오 + ffmpeg GIF 자동 첨부로 5 초 안에 동작 확인. 리뷰어 인지 비용 비교 ASCII 표.
  2. **변경 정보가 Linear / PR description / 코드 3 사본** — PLAN.md = *실행 가능한 quality gate*, refs: 가 외부 도구 *링크* (복제 아님). 자동 인식 (raw / args / dialog).
  3. **archive 가 죽은 무게** — supersedes / obsolete 그래프로 자동 skip + 살아있는 자산 (grep 검색 가능).

- **`README.md` "5-Minute Walkthrough" 섹션** (3 언어) — concrete scenario "Add a refund button to checkout":
  - Min 1: raw 자료 떨어뜨림 (URL 포함)
  - Min 2: `/scv:promote` (refs 자동 인식 + dialog)
  - Min 3: `/scv:work` (구현 + Playwright e2e + .webm 캡처)
  - Min 4: 자동 PR (ffmpeg .gif + orphan branch + GIF inline + .webm 링크 + refs)
  - Min 5: 리뷰 → 머지 → archive → retention cleanup → 누적 회귀 진입

- **상단 nav 앵커** — `#why-scv` / `#5-minute-walkthrough` 추가, `#end-to-end-flow` 제거 (스페이스 확보).

### Changed

- **`.claude-plugin/plugin.json`** — version `0.6.1` → `0.6.2`.
- **`README.md`** 회귀 배지 528 PASS → 557 PASS.

### Tests

- 신규 섹션 **[11zz]** (~30 assertion):
  - 3 언어 의 신규 섹션 헤더 (`## Why SCV?` / `## 왜 SCV?` / `## なぜ SCV?` / `## 5-Minute Walkthrough` / `## 5 분 워크스루` / `## 5 分ウォークスルー`)
  - 핵심 가치 3 가지의 핵심 문구 (영어 / 한국어 / 일본어)
  - "executable quality gate" / "실행 가능한 quality gate" / "実行可能な quality gate"
  - Walkthrough 시나리오 ("Add a refund button to the checkout page" + 한국어 / 일본어 등가)
  - Min 1 ~ Min 5 단계 헤더
  - 상단 nav 앵커
- 회귀: 528 → **557 PASS** (+29 assertion) / 0 FAIL.

### Backwards compat

- 동작 변화 0. 기존 사용자 무영향.
- README 의 기존 섹션 (Quick Start / Slash Commands / End-to-End Flow / Project Layout / 기타) 모두 보존, 새 섹션은 hero 와 Quick Start 사이에 *추가* 만.
- archived TESTS.md / hydrated 문서 / orphan branch layout 모두 무영향.

### 비채택

- README 의 기존 섹션 큰 재정렬 — Quick Start 의 정확성 / Slash Commands 표 의 reference 가치는 그대로 두는 게 안전. 새 섹션 추가만으로 가치 부각 충분.
- 다른 언어 (Spanish / French / 등) 추가 — 4 지선다 의 "Other" 사용자 표면은 i18n 인프라 (Language preference 우선순위 + render-template.sh dynamic 분기) 만으로 처리. README 자체는 영어 / 한국어 / 일본어 3 언어 유지.

## [0.6.1] — 2026-04-30

### 핵심 — 표준 문서 부담 완화 + 외부 refs 자동 인식 (deliberate sources only, dialog-driven clarification 보존)

DISCUSS.md 의 두 약점 ("9 표준 문서가 부담" + "DRY 잔재") 동시 마무리. 사용자 가시 표면 (출력 / docs / dialog) 만 변경 — 동작 표면 호환성 유지.

### Changed

- **`scripts/help.sh`** — Document status 출력 압축. `draft = 0` (정상 adoption mode 운영) 시 9 줄 → 1 줄: "Standard docs: 2 active, 7 N/A — adoption mode default. Lift any N/A doc to draft only when you decide to document that subsystem." `draft > 0` 시 기존 multi-line + "needs filling" 힌트 유지. 첫 사용자가 N/A 9 개를 "9 항목 ToDo" 로 오해하는 마찰 mitigation.

- **`template/scv/CLAUDE.md`** — adoption mode 단락 강화. "N/A is a steady state, not a backlog. Existing large projects can run SCV indefinitely with all 7 docs at status: N/A — just do feature work and bug fixes through /scv:promote / /scv:work / /scv:regression." + "Lift one doc at a time when there's a real driver — never preemptively." 기존 프로젝트 사용자 안심.

- **`commands/promote.md`** — Y5+ refs 자동 인식 흐름 4 단계 추가/갱신:
  - **Step 2.1 (신규)** — Reference scan from deliberate sources only. (1) `scv/raw/` 안 URL (2) `/scv:promote` 호출 인자 안 URL 만 자동 populate. **이전 conversation (예: `/scv:help "...URL..."`) 은 자동 add 안 함** — 대신 LLM topic match 로 "💡 Earlier you mentioned: ... (paste into your dialog answers if you want it in refs)" suggestion 으로만 표시. SCV 의 "deliberate clarification" 철학 보존 — casual mention 으로 PLAN.md 더럽히지 않음.
  - **Step 3.1 머리 (신규)** — Conditional preamble: Step 2.1 에서 URL 추출 0 + `.env` 에 `*_BASE_URL` 하나라도 set 시에만 한 줄 텍스트 hint ("if this plan has any URLs, include them in any of your answers"). **AskUserQuestion 새 단계 추가 안 함** — 기존 question batch (Scope / Slug / Title / Raw sources) 에 "URL 도 paste 해주세요" 섞으면 choice 혼란 발생하는 우려 회피.
  - **Step 3.1.5 (신규)** — Dialog 답변 안 URL parsing. URL pattern → ref type table: jira (`*.atlassian.net/browse/<KEY>-<N>`) / linear (`linear.app/.../issue/<ID>`) / pr (GitHub + GitLab MR) / confluence / google-doc / notion / link. `.env` 의 `<TYPE>_BASE_URL` 일치 시 `id:` 만 저장, 외엔 `url:` 직접. Step 2.1 + Step 3.1.5 결과 dedupe.
  - **Step 5 (갱신)** — Source attribution after writing. PLAN.md 작성 후 한 줄 출력: "refs: 3 auto-detected (2 from raw, 1 from dialog answer) · edit PLAN.md frontmatter to add more." 사용자가 어디서 detected 됐는지 가시화.

- **`template/.env.example.scv`** — `JIRA_BASE_URL` / `LINEAR_BASE_URL` / `CONFLUENCE_BASE_URL` 주석 placeholder 단락 추가. 사용자가 setup 단계에서 refs 자동 인식 + Step 3.1 conditional preamble 의 BASE_URL 시그널 인지.

- **`README.md`** (3 언어 — English / 한국어 / 日本語):
  - "표준 문서는 옵션입니다 / N/A is a steady state, not a backlog" callout — adoption mode 기본 동작 안심.
  - "External Refs (Jira / Linear / PR / Docs) — Auto-Detection" 신규 섹션 — 3 deliberate sources (raw / args / dialog answer) 명시 + `.env` BASE_URL setup 안내 + `/scv:work` / regression / archive 보존.
  - 회귀 배지: 488 PASS → 528 PASS.

- **`.claude-plugin/plugin.json`** — version `0.6.0` → `0.6.1`.

### Tests

- 신규 섹션 **[11yy]** (~40 assertion):
  - `help.sh` 의 adoption mode 압축 출력 (한 줄, "adoption mode default", "Lift any N/A doc to draft" 문구) + draft 분기 (multi-line + "needs filling")
  - `template/scv/CLAUDE.md` 의 "N/A is a steady state, not a backlog" + "Lift one doc at a time when there's a real driver" 문구
  - `commands/promote.md` 의 Step 2.1 (deliberate sources only / 자동 populate 거부 / suggestion 표시) + Step 3.1 conditional preamble + Step 3.1.5 URL pattern table (jira / linear / pr GitLab + GitHub / google-doc / notion) + Step 5 source attribution
  - `template/.env.example.scv` 의 3 BASE_URL placeholder
  - `README.md` 3 언어 의 표준 문서 옵션 + 외부 Refs 단락 영어/한국어/일본어 매치
- 회귀: 488 → **528 PASS** (+40 assertion) / 0 FAIL.

### Backwards compat

- 기존 PLAN.md frontmatter `refs:` 스키마 변경 0. 기존 archived 데이터 무영향.
- `/scv:work` / `/scv:regression` / `/scv:status` / `/scv:report` / `/scv:sync` / `/scv:install-deps` 동작 변화 0.
- `/scv:promote` 의 사용자 표면 변화: (1) Plan summary 에 "Detected refs" 라인 추가 (URL 발견 시) (2) Step 3.1 conditional preamble (조건 충족 시) (3) Step 5 의 source attribution 한 줄. 기존 dialog 4 questions 동일.
- `/scv:help` 의 Document status 출력 형식 변경 — `draft = 0` 시 한 줄 (이전 multi-line) / `draft > 0` 시 기존 동일.
- archived TESTS.md / hydrated 문서 / orphan branch layout 모두 무영향.

### 검증 한계 (정직한 안내)

- URL pattern matching 의 LLM judgment quality 는 회귀 mock 으로 직접 측정 못 함. instruction 존재 검증만.
- "Earlier conversation suggestion" 의 topic match 정확도도 LLM 영역 — false positive 발생 시 사용자가 dialog 답변에서 "skip" 명시하거나 PLAN.md 직접 편집.
- 모든 변경은 docs / instruction / 출력 표면 영역 — 실 코드 동작 변화 0 (help.sh 의 출력 분기만 코드 수정).

### 비채택

- **conversation 전체 무차별 scan (Y4-loose)** — false positive 큼 + SCV 의 "deliberate clarification" 가치와 모순.
- **/scv:help 의 URL 자동 add (Y4-balanced)** — casual mention 을 PLAN.md 에 박는 건 명확화 단계 단축. Y5+ 의 suggestion-only 가 안전한 답.
- **AskUserQuestion 새 step 추가** — choice question 과 URL 입력 혼란 우려. preamble + dialog parsing 로 충분.

## [0.6.0] — 2026-04-30

### 핵심 — `/scv:install-deps` 신규 슬래시 명령어 + 전체 OS 자동 감지 + graphify 인지

DISCUSS.md v0.5.2 토론의 §3.3 (외부 의존성 install friction) 마무리. 7 시스템 CLI (git/gh/glab/curl/jq/ffmpeg/python3) + 1 Claude Code skill (graphify) 의 부재 감지 + OS 별 정확한 install 명령어 자동 출력. 사용자가 본인 OS 확인하고 라인 찾는 마찰 제거.

### Added

- **`scripts/install-deps.sh`** (신규, ~330 줄) — OS / package manager 자동 감지 + 부재 deps install 명령어 출력 또는 실행. 3 모드:
  - **`--check`** (default) — 부재 deps 별 OS 정확 명령어 출력 (실행 안 함). exit 0 (모두 설치됨 또는 optional 만 부재) / 1 (required 부재) / 2 (PM 자체 부재).
  - **`--install`** — 실제 install 실행. sudo prompt 가능 (apt/dnf/pacman/zypper/apk). winget 은 자체 dialog.
  - **`--print`** — 정보용 — 모든 OS 의 install 명령어 reference 출력.

  OS / PM 지원 행렬:
  - **macOS** → `brew install ...` (전체 deps 한 줄)
  - **Linux Debian/Ubuntu** → `apt install ...` + **gh apt repo 자동 등록** (keyring + sources.list) + **glab .deb 직접 다운로드** (apt 에 없음)
  - **Linux Fedora/RHEL** → `dnf install ...` + gh repo 자동 등록 + glab .rpm 직접
  - **Linux Arch/Manjaro** → `pacman -S ...` (전체 한 줄, AUR 불요)
  - **Linux openSUSE** → `zypper install ...` + glab .rpm 직접
  - **Linux Alpine** → `apk add ...` + glab static binary 다운로드
  - **Windows winget** (default) → `winget install ...` (`GitHub.cli` / `GitLab.GLab` / `Gyan.FFmpeg` / `jqlang.jq` 등 정확한 ID)
  - **Windows scoop / choco** (alternative) → `scoop install ...` / `choco install ...`
  - **Unknown OS / PM** → 명확한 안내 + 종료

  graphify 처리: **시스템 CLI 가 아니라서 install-deps.sh scope 외**. 부재 시 `https://github.com/safishamsi/graphify` 안내만 (manual SKILL.md 배치 권장).

- **`commands/install-deps.md`** (신규) — `/scv:install-deps` 슬래시 명령어. 8 번째 명령어:
  - Step 0: `--check` 자동 실행
  - Step 1: 부재 시 AskUserQuestion 으로 3 지선다 (Install now / Just print / Cancel)
  - "Install now" 선택 시 `--install` 실행 + 결과 요약. graphify 자동 install 안 함 (다른 채널).
  - Language preference 우선순위 instruction 포함.

### Changed

- **`scripts/help.sh`** — Dependency check 에 `graphify` row 추가:
  - 가용 시 `[✓] graphify — Claude Code skill — token-efficient graph queries (/scv:promote, /scv:work)`
  - 부재 시 `[△] graphify — Claude Code skill ... (optional, graceful degrade)` + `Install: https://github.com/safishamsi/graphify`
  - 감지 경로: `~/.claude/skills/graphify/SKILL.md` 또는 `~/.claude/plugins/cache/*/skills/graphify/SKILL.md` (status.sh 와 동일 패턴).
  - Install hint footer 갱신: `Install hint: run '/scv:install-deps' for OS-specific commands, or:` + macOS/Debian fallback 라인 보존.

- **`commands/promote.md`** §Step 1 graphify-missing 안내에 install link 박음 — 기존의 `[link from user's environment]` placeholder → `https://github.com/safishamsi/graphify (place SKILL.md at ~/.claude/skills/graphify/)`.

- **`commands/work.md`** §Protocol 머리에 Dependency note 단락 추가 — helper warning 시 `/scv:install-deps` 안내 권장. graphify install link 명시. **자동 호출 안 함** (decision: 사용자 manual run 권장 — friction 끼어드는 거 회피).

  §Step 2 (Graph freshness check) 의 graphify missing 케이스를 silent 에서 → 한 줄 mention (한 번만, 반복 안 함) 으로 갱신.

- **`.claude-plugin/plugin.json`** — version `0.5.2` → `0.6.0`.
- **`.claude-plugin/marketplace.json`** — description "7 slash commands" → "8 slash commands".
- **`README.md`** — 3 언어 섹션 (English / 한국어 / 日本語) 모두 슬래시 커맨드 표 갱신: "Seven Total" → "Eight Total" (한국어 7→8, 일본어 7→8) + `/scv:install-deps` row 추가. 배지 카운트 451 → 488.
- **`DISCUSS.md`** §1 / §3.3 / §4.2 갱신 — 외부 의존성 표면을 "시스템 CLI 7 + Claude Code skill 1 (graphify)" 로 명시 + v0.6.0 의 install-deps.sh 마찰 완화 효과 반영.

### Tests

- 신규 섹션 **[11xx]** (~30 assertion):
  - `install-deps.sh --check` exit 0/1, OS / PM detection 라인 출력, deps 섹션 + graphify 섹션 헤더 검증
  - `--print` mode 의 7 OS 섹션 (macos/brew, linux-debian/apt, linux-fedora/dnf, linux-arch/pacman, linux-suse/zypper, linux-alpine/apk, windows/winget) 모두 포함
  - Windows winget package ID 정확성 (`GitHub.cli`, `Gyan.FFmpeg`)
  - graphify 부재 시뮬레이션 (`HOME=/nonexistent`) 후 install link 출력 검증
  - 알 수 없는 mode (`--bogus`) 시 exit 2
  - `commands/install-deps.md` frontmatter (`AskUserQuestion`, `install-deps.sh`) + body (`Install now` / `Just print` / `Cancel`)
  - `help.sh` 의 graphify row + `/scv:install-deps` reference
  - `commands/work.md` 의 `/scv:install-deps` 안내 + graphify install link
  - `commands/promote.md` 의 graphify install link
- **[11tt]** 의 install hint 문구 갱신 — "Install hint: macOS" → "Install hint" 더 일반적 매치, `/scv:install-deps` reference 검증 추가.
- 회귀: 451 → **488 PASS** (+37 assertion) / 0 FAIL.

### Backwards compat

- 기존 7 슬래시 명령어 (help/status/promote/work/regression/report/sync) 동작 변화 0. 새 명령어 추가만.
- `/scv:help` 의 dependency check 출력 형식 변경 — 기존 한 줄 install hint → 다중 줄 (run /scv:install-deps + macOS/Debian fallback). 회귀의 [11tt] 갱신 외 사용자 영향 없음.
- archived TESTS.md / hydrated 문서 / orphan branch layout 모두 무영향.

### 검증 한계 (정직한 안내)

- 자동 install 흐름 (`--install` mode) 의 실 환경 검증은 **Linux/apt 만 end-to-end 수행**. macOS/brew, Windows/winget, 기타 Linux distros (Fedora/Arch/openSUSE/Alpine) 는 **best-effort** — 패키지 ID 와 명령어 syntax 는 upstream packaging guide 기반이지만 실 install 검증 미수행.
- `--check` / `--print` mode 는 모든 OS 에서 verify 됨 (출력 검증).
- Windows 의 PowerShell vs Git Bash 환경 차이는 미검증. WSL 은 Linux 분기 자동 적용으로 동작 예상.

### 비채택 (DISCUSS §4.4 권장 중 v0.6.0 제외)

- **#1 Slack/Discord 토큰 OS keyring 통합** — vendor CLI 부재 영역. 자체 keyring 추상화 layer 도입 vs `.env` 평문 유지 결정 필요. v0.6.x / v0.7 후보.
- **#5 Telemetry opt-in** — privacy 검토 후 1.0 진입 결정 근거 수집. v0.7+ 또는 v1.0 진입 시.
- **graphify 자동 install** — Claude Code skill 의 공식 배포 채널 미확정. 사용자 GitHub 링크 안내로 manual placement 권장.

## [0.5.2] — 2026-04-30

### 핵심 — GitLab 토큰을 OS keyring 으로 (`glab auth login` 우선) + `.env.example.scv` 영어화

DISCUSS.md v0.5.0 회고의 권장 #1 (secret backend 통합) 을 **최소 부담 경로** 로 해결. 별도 keyring 추상화 layer (`lib/secrets.sh`) 만들지 않고, 이미 SCV 의존인 vendor CLI (`gh` / `glab`) 가 OS native keyring 자동 처리하는 점을 활용. GitLab 사용자는 `glab auth login` 하면 토큰이 macOS Keychain / Linux libsecret / Windows Credential Manager 에 저장되고, SCV 가 자동으로 `glab auth token` 으로 읽어옴. 평문 `.env` 노출 제거.

추가로 v0.4.x i18n 정리에서 누락됐던 `template/.env.example.scv` 한국어 주석을 영어로 통째 번역. 글로벌 사용자 일관성.

### Changed

- **`scripts/lib/pr-platform.sh`** — `_pr_gitlab_token` 을 2-tier 로:
  - **Tier 1 (preferred, v0.5.2+)**: `glab` CLI 가 PATH 에 있으면 `glab auth token` 호출 (self-hosted 시 `--hostname` 자동 부여 — `GITLAB_HOST` env 에서 hostname 추출). 토큰 OS native keyring 에 자동 저장된 상태.
  - **Tier 2 (fallback)**: `GITLAB_TOKEN` env. backwards compat 유지 — v0.5.0/0.5.1 에서 `.env` 평문 박은 사용자 무영향.
  - **둘 다 없을 때**: 새 에러 메시지가 두 옵션 모두 안내 ("Run 'glab auth login'" + "Or set GITLAB_TOKEN in .env").
  - Sanity check: `glab auth token` 이 빈 문자열·whitespace 포함·8 자 미만 반환하면 토큰 아닌 진단으로 간주하고 Tier 2 로 fall through.

- **`scripts/help.sh`** — Dependency check 에 `glab` row 추가 (recommended tier, "GitLab MR auth (preferred over GITLAB_TOKEN .env)"). 부재 시 `gh` 와 함께 install hint 마지막 줄에 GitLab CLI 설치 + `glab auth login` 안내 링크.

- **`template/.env.example.scv`** — 두 가지 변화:
  - **`GITLAB_TOKEN` 주석 갱신** — `glab auth login` 권장이 default 가이드. Tier 2 fallback (deprecated 아님) 으로 명시.
  - **전체 한국어 주석을 영어로 번역** — v0.4.x i18n 정리에서 누락된 부분. 117 줄 영어화. 동작 변화 0.

### Tests

- 신규 섹션 **[11ww]** (8 assertion) — `_pr_gitlab_token` 의 4 시나리오 + whitespace token sanity:
  1. `glab` 있고 token 반환 → 그 토큰 사용 (`GITLAB_TOKEN` env 무시)
  2. `glab` 있고 exit 1 → `GITLAB_TOKEN` env fallback
  3. `glab` 부재 → `GITLAB_TOKEN` env fallback
  4. 둘 다 없음 → exit 1 + 에러 메시지에 두 옵션 모두 명시
  5. `glab` 가 `"no token"` 같은 진단 문자열 반환 → 토큰 아닌 것으로 간주, Tier 2 fall through
- mock `glab` via `PATH` 의 임시 디렉토리. 실 `glab` CLI 의존 없음.
- **[11tt]** 에 glab row 검증 한 줄 추가 (deps check 의 8 번째 row 정상 출력).
- **[11uu]** 의 `.env.example.scv` 영어화 따라 한국어 매치 1 곳 영어로 갱신 ("Fast-path 임계점" → "Fast-path threshold").
- 회귀: 442 → **451 PASS** (+9 assertion) / 0 FAIL.

### Backwards compat

- v0.5.0/0.5.1 사용자 무영향. `.env` 의 `GITLAB_TOKEN` 그대로 동작 (Tier 2). 새로 `glab auth login` 한 사용자만 keyring 경로로 자동 전환.
- archived TESTS.md / hydrated 문서 / orphan branch layout 모두 무영향.
- self-hosted GitLab: `GITLAB_HOST` 가 `glab` 의 `--hostname` 으로 자동 forwarding.

### 비채택 (DISCUSS §4.4 권장 중 v0.5.2 제외)

- **secrets.sh 추상화 + Slack/Discord keyring 적용** — Slack bot token / Discord bot token 은 vendor CLI 가 issue + keyring 저장하는 흐름 자체가 없음 (Slack 은 dashboard 에서 발급, 사용자 어딘가 paste 필요). v0.6+ 에 자체 keyring 추상화 도입 시 같이 검토.
- **다국어 동적 template** — `.env.example.scv` 와 `template/scv/*.md` 의 사용자 선호 언어별 분기. hydrate 시점에 SCV_LANG 미확정 + 재-render trigger 설계 필요. v0.6 후보로 미룸.
- **`pass` (GPG-based) 백엔드** — power-user 도구라 SCV 사용자 모집단에 비해 진입 장벽 큼. 기존 `gh` / `glab` keyring 으로 대부분 케이스 cover. 별도 추가 필요 없음.

## [0.5.1] — 2026-04-30

### 핵심 — DISCUSS.md v0.5.0 회고에서 도출된 docs-only patch

`DISCUSS.md` 의 v0.5.0 시점 6 페르소나 시뮬레이션 회고 (3 개월 사용 후) 에서 도출된 권장 7 개 중, **검증 부담이 작고 backwards compat 안 깨지는 docs-heavy 항목 3 개 + 부수 정리**. 사용자 가시 동작은 거의 같지만 첫 사용자 onboarding 마찰이 줄어듦.

### Added

- **`scripts/help.sh` — Dependency check section** (DISCUSS §4.4 #3): `/scv:help` 출력의 dynamic 진단에 SCV 가 사용하는 외부 CLI 6 개 (`git` / `gh` / `curl` / `jq` / `ffmpeg` / `python3`) 의 부재 여부 + tier (required / recommended / optional) 표시. 부재 시 macOS Homebrew + Debian/Ubuntu apt 설치 hint 한 줄 출력. `gh` 가 부재면 GitHub apt repo 안내 링크 추가. 첫 사용자가 `ffmpeg` 안 깔린 상태에서 PR 비디오 GIF 변환만 안 되는 비균일 표면을 사전 발견.

- **`template/scv/PROMOTE.md` §1.6 — Fast-path threshold + team override** (DISCUSS §4.4 #2):
  - 기본 임계점이 "1–2 line hotfix" → **"≤ 5 lines + 단일 함수/블록 안"** 으로 확장.
  - 새 env `SCV_FAST_PATH_LINE_THRESHOLD` 로 팀별 lock 가능 (보수적: 3, 성숙 코드베이스: 10 등). `.env` 한 줄로 per-PR 협상 ("이 6 줄 변경은 fast-path OK?") 제거.
  - **단일 함수/블록 룰은 override 불가** — 다중 함수 변경은 라인 수와 무관하게 formal promote loop. 안전 default 유지.
  - examples 표의 "1–2 line null-guard hotfix" → "≤5 line null-guard / off-by-one hotfix in a single function" 으로 갱신.

- **`commands/regression.md` — Archive scale guidance** (DISCUSS §4.4 #6): Step 3 와 Flag semantics 사이에 "Archive scale guidance" 단락 추가. archive 가 수십 개 누적 시 `--tag core` / `--tag payment` 등으로 partition 권장. tag taxonomy 는 사용자 자율, SCV 가 자동 추가하지 않음 (안전 default). `--tag <x>` flag 설명에도 "Recommended for large archives" 한 줄 보강.

- **`template/.env.example.scv`** — `SCV_FAST_PATH_LINE_THRESHOLD` 주석 단락 추가.

### Changed

- **`README.md`** — Regression 배지 `412 PASS` → `442 PASS` (v0.5.0 = 421 → v0.5.1 = 442, 다음 21 assertion 추가).
- **`.claude-plugin/plugin.json`** — version `0.5.0` → `0.5.1`.

### Tests

- 신규 섹션 **[11tt]** (10 assertion) — `help.sh` Dependency check 섹션 + 부재 시 Install hint 출력. 부재 시뮬레이션은 `env -i HOME=$HOME PATH=/nonexistent /bin/bash` 패턴으로 모든 `command -v` 가 fail 하는 환경 재현.
- 신규 섹션 **[11uu]** (7 assertion) — PROMOTE.md 의 ≤5 line / 단일 함수 룰 / `SCV_FAST_PATH_LINE_THRESHOLD` / Team override / non-overridable 룰 / `.env.example.scv` 동기화.
- 신규 섹션 **[11vv]** (4 assertion) — regression.md 의 Archive scale guidance / `--tag` 권장 / "Do not auto-add tags" stance.
- 회귀: 421 → **442 PASS** (+21 assertion) / 0 FAIL.

### Backwards compat

- 동작 변화 0. 모든 추가는 docs / 출력 표면 / env 옵션. 기존 사용자가 `.env` 에 `SCV_FAST_PATH_LINE_THRESHOLD` 안 박아도 default 5 로 동작 (v0.2.1 fast-path 보다 약간 완화).
- archived TESTS.md (v0.3.x) / hydrated 문서 / orphan branch layout 모두 무영향.

### 비채택 (DISCUSS §4.4 권장 중 v0.5.1 제외, v0.6.0 후보)

- **#1 secret backend 통합** (`GITLAB_TOKEN` Keychain / `gh auth` / `pass` 통합 + `hydrate.sh` `.gitignore` 강제) — 구조 변경 + cross-OS 분기 + 회귀 신규 섹션. patch 가 아닌 minor (v0.6.0).
- **#4 `docs/ONBOARDING.md` 또는 README walkthrough** — 시나리오 작성 + 스크린샷. v0.5.x 후속 또는 v0.6.0.
- **#5 orphan branch gc 정책** — 6 개월 데이터 후 결정.
- **#7 telemetry opt-in** — privacy 검토 → v1.0 진입 결정 근거.

## [0.5.0] — 2026-04-29

### 핵심 — GitLab MR 자동 생성 + PR/MR backend 추상화

v0.3+ 의 GitHub-only PR 자동 생성을 GitLab MR 까지 확장. PR/MR 생성·업데이트·raw URL 을 platform-agnostic 추상화 layer (`scripts/lib/pr-platform.sh`) 로 분리. GitHub 사용자는 동작 변화 없음, GitLab 사용자는 본인 token + Personal Access Token 으로 자동 동작.

**검증 완료**: 실 GitLab repo (`gitlab.com/wookiya1364/scv-test-pr-flow`) 로 MR 자동 생성 end-to-end 검증. iid 1 정상 생성, title / target_branch / source_branch / description 모두 정확.

### Added

- **`scripts/lib/pr-platform.sh`** (신규, ~250 줄) — PR/MR backend 추상화 layer.
  - **Public API**:
    - `pr_create <title> <body_file> <base_branch> <head_branch>` → echo URL
    - `pr_update_body <pr_number> <body_file>` → silent
    - `pr_get_owner_repo` → `"owner/repo"` (GH) 또는 URL-encoded `"ns%2Fproject"` (GL)
    - `pr_raw_url <branch> <path>` → raw content URL (attachments 가 사용)
  - **Backend dispatch**:
    - 명시: `SCV_PR_PLATFORM=github|gitlab` env
    - 자동 감지: `git remote get-url origin` host (`github.com` / `gitlab.com`)
    - 알 수 없는 값 → `github` fallback
  - **GitHub backend** (`gh` CLI): `gh pr create` + `gh api -X PATCH` (기존 `pr-helper.sh` 패턴 옮김).
  - **GitLab backend** (`curl` + REST API v4): `POST /projects/<ns%2Fproject>/merge_requests`, `PUT /merge_requests/<iid>`. 인증: `PRIVATE-TOKEN` 헤더. **`glab` CLI 불요** — `curl` + `jq` 만 의존 (사용자 환경 의존도 최소화). self-hosted: `GITLAB_HOST` env.

### Changed

- **`scripts/pr-helper.sh`** — `gh pr create` / `gh api -X PATCH` 직접 호출 → `pr_create` / `pr_update_body` 추상화 호출. GitHub 사용자 동작 동일. GitLab origin 시 자동으로 GitLab API 사용.
- **`scripts/pr-helper.sh`** — Screenshot URL 생성을 **commit SHA 기반 absolute raw URL** 로 변경. body 조립 시 `__SCV_HEAD_SHA__` placeholder 박고, push 직후 `git rev-parse HEAD` 결과로 substitute. 효과:
  - GitLab MR description 에서도 screenshot 인라인 렌더 (이전엔 상대 경로라 깨짐)
  - GitHub PR 에서 branch 이름에 `/` 가 있어도 ambiguous URL resolution 으로 인한 502 회피 (예: `feat/foo/bar` → `raw/feat/foo/bar/.scv-pr-artifacts/...`)
  - branch 머지/삭제 후에도 raw URL 영구 유효 (commit SHA 가 immutable)
- **`scripts/lib/attachments.sh`** — `_attachments_git_orphan_upload` 의 raw URL 생성을 `pr_raw_url` 호출로:
  - GitHub: `https://github.com/<owner>/<repo>/raw/<branch>/<path>` (기존 동일)
  - GitLab: `<host>/<ns>/<project>/-/raw/<branch>/<path>` (신규, `/-/raw/` 접두)
  - `pr-platform.sh` 자동 source (idempotent). defensive fallback (`pr_raw_url` 미정의 시 GitHub 하드코딩).
- **`scripts/lib/attachments.sh`** — `_attachments_git_orphan_upload` 의 platform sanity check 를 lenient 하게 변경. 기존: `_get_github_owner_repo` 강제 (GitHub-only) → GitLab 사용 시 비디오 첨부 자체 reject. 새: `git remote get-url origin` 만 검증, owner_repo 추출 fail 은 무시 (raw URL 은 `pr_raw_url` 추상화로 platform 별 분기).
- **`template/.env.example.scv`** — `SCV_PR_PLATFORM` / `GITLAB_TOKEN` / `GITLAB_HOST` 주석 단락 추가.

### Tests

- 신규 섹션 **[11ss]** 9 assertion (platform 자동 감지 + env override + raw URL):
  1. `github.com` origin → `github`
  2. `github` owner_repo `wookiya1364/foo`
  3. `github` raw URL 형식 (`https://github.com/...raw/...`)
  4. `SCV_PR_PLATFORM=gitlab` env override (origin 무관)
  5. `gitlab.com` origin → `gitlab`
  6. `gitlab` project path URL-encoded (`wookiya1364%2Fscv-test-pr-flow`)
  7. `gitlab` raw URL 형식 (`/-/raw/`)
  8. self-hosted: `SCV_PR_PLATFORM=gitlab` + `GITLAB_HOST` env
  9. unknown `SCV_PR_PLATFORM` 값 → `github` fallback
- **실 환경 검증** (GitHub + GitLab 양쪽):
  - **GitLab** (`gitlab.com/wookiya1364/scv-test-pr-flow`) — MR 자동 생성 + description 의 PLAN/TESTS/ARCHIVED footer 정확. 비디오 (`![](.gif)` inline + `.webm` 클릭 링크) + screenshot (commit SHA absolute raw URL) 인라인 렌더 모두 정상.
  - **GitHub** (`github.com/wookiya1364/scv-claude-code`) — PR 자동 생성. 비디오 + screenshot 양쪽 raw URL 인라인 렌더. branch 이름에 `/` 있어도 SHA 기반 URL 로 502 회피.
- 회귀: 412 → **421 PASS** (+9 assertion) / 0 FAIL.

### Backwards compat

- GitHub 사용자: 동작 변화 0. `pr-helper.sh` 가 `gh` CLI 사용하는 부분이 추상화로 옮겨졌을 뿐, 호출 결과 동일.
- 기존 archived TESTS.md (v0.3.x) 의 `## 실행 방법` / `## 통과 판정` 섹션 호환은 v0.4 alternation 으로 그대로 유지.

### 비채택 (v0.5.x+ 후보)

- **`s3` / `r2` 백엔드 본문**: storage 영역. 별 minor (v0.5.1 또는 v0.6) 로 분리. LocalStack + 사용자 R2 계정으로 검증 가능.
- **Bitbucket / Gitea PR 자동 생성**: `lib/pr-platform.sh` 추상화에 `_pr_bitbucket_*` / `_pr_gitea_*` backend 추가. 사용 빈도 낮아 community beta 또는 사용자 도움 검증으로.
- **Cypress / Puppeteer → Playwright 자동 마이그레이션**: 별 도구 영역. v0.5.x+ 또는 별 plugin 후보.

## [0.4.1] — 2026-04-29

### 핵심 — i18n internal cleanup (commands 본문 + template 영어화 + Notifier dynamic)

v0.4.0 의 사용자 가시 동작은 그대로 유지하면서, instruction / template 의 hardcoded 한국어를 영어로 통째 정리. 추가로 Notifier 메시지 (Slack/Discord) 가 `SCV_LANG` 따라 동적으로 한국어/일본어/영어 분기.

### Changed

- **`commands/*.md` 본문 영어화** (A3 step) — 7 commands 의 instruction 본문이 영어로:
  - `work.md` (162 → 8 한국어 라인) — Step 5b Playwright video config + Non-Playwright notice / Step 9a 회귀 pre-flight / 9b archive decision / 9c supersede 3-way / 9d retention 4지선다 + PR 자동 생성. 사용자 발화 예시 (예: `tests 통과하면 알아서 archive 해`, `분리해`, `ARCH.md 도 보고 구현해`) 는 영어 + 한국어 hybrid 로 backwards compat 유지.
  - `regression.md` (72 → 1) — Non-negotiable rules / Step 0 / Step 1 (all-pass) / Step 2 (3-way triage AskUserQuestion) / Step 3 final summary / flag semantics / Never.
  - `promote.md` (42 → 1) — Non-negotiable rules / Step 1-7 / Step 3.0 split suggestion heuristic + AskUserQuestion / Step 5 의 PLAN.md / TESTS.md scaffold (영어 헤더: `## How to run` / `## Pass criteria`).

- **`template/scv/*.md` 영어화** (B-1 + B-2 step) — hydrate 시 사용자 프로젝트로 복사되는 표준 문서 10 개 (총 827 한국어 라인) 모두 영어로:
  - **B-1**: `DESIGN.md` / `DOMAIN.md` / `RALPH_PROMPT.md` / `REPORTING.md` / `AGENTS.md` / `CLAUDE.md`
  - **B-2**: `TESTING.md` / `INTAKE.md` / `ARCHITECTURE.md` / `PROMOTE.md` (627 라인 통째)
  - 새 v0.4 hydrate 는 영어 표준 문서로 시작. 기존 hydrated 프로젝트는 `/scv:sync` 가 `merge_policy` 따라 안전 병합.

### Added (v0.4.3 step)

- **`scripts/render-template.sh` — `SCV_LANG` dynamic 분기**:
  - 영어 (default + fallback) / 한국어 / 일본어 status label, meta line (`Project:` / `Commit:` / `Attempt:` / `Duration:` 또는 한·일 등가), failure cause label (`*Cause*` / `*원인*` / `*原因*`), retry message, summary fallback.
  - Case-insensitive 매칭 (`KOREAN` == `korean`). 알 수 없는 언어 (예: `esperanto`) → 영어 fallback.
- **`scripts/report.sh`** — `SCV_LANG` 환경 변수 export 추가. `.env` 의 `SCV_LANG` (env_load 로 로드) 이 `render-template.sh` 에 전달돼서 Slack/Discord 메시지 자체가 사용자 언어로 출력됨.

### Backwards compat

- archived `TESTS.md` (v0.3.x 사용자) 의 `## 실행 방법` / `## 통과 판정` 섹션은 그대로 동작 — `regression.sh` 와 `pr-helper.sh` 의 awk regex `(How to run|실행 방법)` / `(Pass criteria|통과 판정)` 알터네이션이 영어 + 한국어 양쪽 매치.
- 사용자 main branch 에 hydrate 된 한국어 표준 문서들도 **그대로 보존됨** (`/scv:sync` 가 `merge_policy: preserve` / `merge-on-markers` 로 처리). v0.4.1 의 영어 template 은 새 hydrate / merge 시점부터 적용.

### Tests

- 신규 섹션 **[11rr]** 8 assertion (`render-template.sh` SCV_LANG dynamic branching: english passed/Project / korean 완료/프로젝트 / japanese 失敗/原因 / unknown lang → english fallback / case-insensitive).
- 한국어 → 영어 매치 갱신 약 30+ 곳 (commands `work` / `regression` / `promote` + template `TESTING` / `INTAKE` / `ARCHITECTURE` / `PROMOTE`).
- 회귀: 404 → **412 PASS** (+8 assertion) / 0 FAIL.

### Internal cleanup remaining

없음 — i18n core 마무리. 후속은 v0.5+ 의 새 기능 영역 (s3/r2 백엔드, GitLab/Bitbucket/Gitea, Cypress/Puppeteer → Playwright 자동 마이그레이션 등).

## [0.4.0] — 2026-04-29

### 핵심 — i18n core 인프라 (Language preference + sh 메시지 영어화)

SCV 의 사용자 가시 텍스트가 사용자 선호 언어로 출력되도록 인프라 추가. 모든 슬래시 명령어가 다음 우선순위로 언어를 결정해서 응답합니다:

1. `~/.claude/settings.json` (또는 project `.claude/settings.json` / `.claude/settings.local.json`) 의 `language` 키 (Claude Code official — 값 예: `"korean"`, `"english"`, `"japanese"`).
2. 프로젝트 `.env` 의 `SCV_LANG` (= `/scv:help` 4지선다 답변이 저장되는 곳).
3. 사용자 가장 최근 메시지 언어 자동 감지.
4. default 영어.

기술 식별자 (file paths, 슬래시 명령어 이름, frontmatter 키, env var 이름, SCV 용어 `promote` / `archive` / `orphan branch` / `epic` / `supersedes`) 는 모든 언어에서 그대로 유지.

### Added

- **`commands/help.md` — first-time language setup**: `settings.json` `language` + `.env` `SCV_LANG` 모두 비어있으면 4지선다 AskUserQuestion (default [1] English):
  - [1] **English** — 글로벌 default
  - [2] **한국어 (Korean)**
  - [3] **日本語 (Japanese)**
  - [4] **Other — type a language** — Spanish, French, German 등 follow-up 텍스트 입력

  답을 `.env` 의 `SCV_LANG=<value>` 로 저장. `.env` 가 없으면 생성.
- **모든 `commands/*.md` 에 "Language preference" instruction 단락** — 7 commands (`help` / `work` / `promote` / `regression` / `status` / `report` / `sync`) 모두 우선순위 instruction 따라 사용자 언어로 응답.
- **`template/.env.example.scv`** — `SCV_LANG=english` 주석 한 단락 (사용자가 직접 편집해서 lock 가능).

### Changed

- **`scripts/help.sh`** — 모든 사용자 가시 메시지 영어화: overview heredoc (S/C/V 핵심 아이디어, 워크플로 ①-⑤, 커맨드 목록), 동적 진단 (hydrate / .env / 문서 상태 / raw / promote / archive 카운트), 추천 next-action heredoc 6 가지, footer.
- **`scripts/render-template.sh`** — Notifier 메시지 (Slack/Discord) 영어화: Passed / Failed / In progress label, meta line (`Project:` / `Commit:` / `Attempt:` / `Duration:`), failure reason (`*Cause*` / `→ Retry in progress`), info fallback (`(progress report)`).
- **`scripts/hydrate.sh`** — hydrate 완료 안내 영어로.
- **`scripts/work.sh`** — `ARCHIVED_AT.md` body (`# Archive record` / `## Reason`), REASON default ("All TESTS scenarios passed") 영어로.
- **`scripts/regression.sh`** — TESTS.md 섹션 헤더 매치 awk pattern 을 `(How to run|실행 방법)` 알터네이션으로 (영어 + 한국어 backwards compat). skip 메시지 영어로.
- **`scripts/pr-helper.sh`** — PR body 의 `**How to run**:` / `**Pass criteria**:` 섹션 헤더, `extract_section` 패턴도 알터네이션 backwards compat. 주석 영어로.
- **`scripts/promote-helper.sh`** — SPLIT_REASON 문구 영어로 ("3 raw files (>7 threshold)", "5 topic clusters (>=3)").
- **`scripts/sync.sh`** / **`scripts/report.sh`** / **`scripts/lib/attachments.sh`** — 한국어 주석 영어로.

### Backwards compat (v0.3.x archived TESTS.md 호환)

archived `TESTS.md` (v0.3.x 사용자) 의 `## 실행 방법` / `## 통과 판정` 섹션은 그대로 동작 — `regression.sh` 와 `pr-helper.sh` 의 awk regex 가 `(How to run|실행 방법)` / `(Pass criteria|통과 판정)` 알터네이션으로 양쪽 매치. v0.4 의 새 TESTS.md template 영어화는 후속 minor 에서.

### Tests

- `tests/run-dry.sh` 신규 섹션 **[11qq]** 27 assertion (모든 commands 의 Language preference instruction 존재 + `/scv:help` 4지선다 옵션 + `.env.example.scv` SCV_LANG 검증) + [1d] / [11b] / [11h] 의 한국어 매치 영어로 갱신. 377 → **404 PASS** (+27 assertion). 0 FAIL.

### Internal cleanup deferred (v0.4.1+ 후보)

다음은 사용자 가시 동작에 영향 없는 internal cleanup — Claude 가 이미 Language preference 우선순위에 따라 사용자 언어로 응답하므로 instruction / template 의 한국어가 남아있어도 동작 OK.

- **`commands/*.md` 본문 한국어 → 영어화** (work.md 162 / regression.md 72 / promote.md 42 = ~278 라인). v0.4.1 후보.
- **`template/scv/*.md` 영어화** (PROMOTE / INTAKE / TESTING / CLAUDE 등). hydrate 시 사용자 프로젝트로 복사되는 표준 문서. v0.4.x 후속 minor 에서.
- **Notifier 메시지의 SCV_LANG dynamic 분기**: 현재 `render-template.sh` 가 영어 단일. Slack/Discord 가 사용자 화면에 직접 가니 SCV_LANG 따라 동적 번역이 이상적. v0.4.x / v0.5.

### 비채택 (v0.4+ 명단 그대로 유지)

- **`s3` / `r2` 백엔드 본문**: v0.5 후보 (이전 v0.4 후보였으나 i18n 이 v0.4.0 차지).
- **GitLab / Bitbucket / Gitea PR**: v0.5+ 후보, `lib/pr-platform.sh` 추상화 도입 예정.
- **Cypress / Puppeteer → Playwright 자동 마이그레이션**: 별도 minor / 별 plugin 후보.

## [0.3.1] — 2026-04-29

### 핵심 — orphan branch layout 단정화, `attachments_status` 정확화, Playwright 표준화 stance

v0.3.0 출시 후 보강. **사용자 표면 변화 없음**, 세 축의 내부 정리:

1. **Orphan branch 의 모든 SCV 파일을 `scv/` subdirectory 안으로**: 사용자 main branch 와 동일한 정신 모델 ("SCV 가 만든 건 항상 `scv/` 안") 로 일관. orphan branch root 는 README 만 남고, manifest 와 slug 폴더는 모두 `scv/` 안에. v0.3.0 사용자의 기존 layout (root `manifest.json` + root `<slug>/`) 은 자동 migration.
2. **`attachments_status` stale 카운트 정확화** + 5 분 TTL 캐시.
3. **Playwright 표준화 stance 명시** — Cypress / Puppeteer 는 자동 감지 대상에서 빼고, 발견 시 마이그레이션 안내만 (자동 변경 없음).

### Changed

- **`scripts/lib/attachments.sh`** — orphan branch 의 새 layout:
  - **Init** (origin 에 branch 없을 때): `README.md` (root) + `scv/manifest.json` 으로 시작. slug 폴더들도 `scv/<slug>/` 안에 commit.
  - **Auto-migration** (origin 에 v0.3.0 branch 있을 때): `_orphan_worktree_open` 이 root `manifest.json` 발견 시 `mkdir scv` + `git mv manifest.json scv/manifest.json` + 모든 root-level `<slug>/` 디렉토리들을 `scv/<slug>/` 로 이동 → commit ("Migrate v0.3.0 layout → scv/ subdirectory (v0.3.1)") + push. **Idempotent** — `scv/manifest.json` 이 이미 있으면 no-op. stderr 에 한 번 안내 메시지 ("Migrated v0.3.0 layout → scv/ on scv-attachments").
  - **URL 형식**: `/raw/scv-attachments/<slug>/<file>` → `/raw/scv-attachments/scv/<slug>/<file>` (한 단계 추가, functional 영향 0).
  - `attachments_status` 의 `stale=?` deferred 를 **정확 숫자**로. 새 helper `_compute_stale_count` 가 manifest 의 `pr_number` 별로 `gh pr view --json state,closedAt` 호출 + state ≠ OPEN AND `closed_at + retention_days ≤ now` 로 판정.
  - **5 분 TTL 캐시** (`/tmp/scv-attachments-status-<owner>_<repo>-<retention>.json`). cache key = orphan branch HEAD SHA + retention. push 발생 시 SHA 변경으로 **자연 invalidate**. retention 다르면 별도 cache key. graceful degrade — gh / python3 부재 등 모든 실패 경로에서 `?` fallback.

- **`scripts/pr-helper.sh`** — 비디오 수집은 **`test-results/` 만** (Playwright 표준 폴더). Cypress 의 `cypress/videos/` 별도 스캔 없음. Cypress 사용자가 PR 첨부 받으려면 `cypress.config` 에서 `videosFolder: 'test-results/...'` 로 redirect 필요. Playwright 표준화 stance 와 일관.

- **`commands/work.md` Step 5b** — "Playwright 비디오 자동 설정" 의 stance 명시:
  - **SCV 의 표준 E2E framework 는 Playwright**. 자동 감지·자동 video config·PR 자동 첨부의 보장 대상은 Playwright 단일.
  - `playwright.config` 발견 시 기존 흐름 (AskUserQuestion → `video: 'on'` 자동 추가) 그대로.
  - **`playwright.config` 가 없지만 다른 E2E 도구 흔적 (Cypress config, 또는 `package.json` 의 `cypress`/`puppeteer` 의존성) 발견 시**: **non-Playwright notice** 한 번 출력 (자동 변경/거부 없음). 안내문에 Playwright 마이그레이션 가이드 링크 (cypress / puppeteer 각각).

### Added

- **`template/.env.example.scv`**: `SCV_STATUS_CACHE_TTL=300` 주석 한 줄 추가 (`/scv:status` 의 stale 카운트 캐시 TTL, 초 단위).

### Removed (v0.3.1 작업 중 도입했다가 stance 재고로 빠진 것들)

- ~~Cypress 자동 감지 Step 5c~~ — Playwright 표준화 stance 와 일관 안 맞아 제외. 대신 Step 5b 의 non-Playwright notice 로 통합.
- ~~`pr-helper.sh` 의 `cypress/videos/` 자동 스캔~~ — 동일 사유. Cypress 사용자는 `videosFolder` 로 redirect.

### Tests

- `tests/run-dry.sh` 신규 섹션 [11mm], [11nn], [11oo] — 357 → **377 PASS** (+20 assertion). 0 FAIL.
- 검증 영역:
  - **[11mm]** v0.3.0 layout 자동 migration (7 assertion) — root `manifest.json` + root `<slug>/legacy.webm` 시드 → upload 호출 → `scv/manifest.json` + `scv/<slug>/legacy.webm` 로 이동, root 의 옛 파일/폴더 부재, commit 메시지 정확, 두 번째 upload 시 idempotent (정확히 1 migration commit).
  - **[11nn]** `attachments_status` 정확 카운트 + 캐시 (5 assertion) — fresh 계산 (`stale=1` at retention=3), cache 파일 생성, cache hit (mock gh swap 으로 검증), retention=7 별도 cache key 로 fresh compute (`stale=0`), SHA mismatch poisoned cache invalidation.
  - **[11oo]** Step 5b 표준화 stance + non-Playwright 안내 (8 assertion) — "SCV 표준 E2E", `playwright.config.{ts,js,mjs,cjs}`, "non-Playwright notice", "Cypress → Playwright" / "Puppeteer → Playwright" 링크, Cypress 5c step 부재 (제거 일관성 검증).

### 비채택 (v0.4+ 후보, v0.3.0 명단 그대로 유지)

- **`s3` / `r2` 백엔드 본문**: v0.4 후보. v0.3.x 는 abstraction + stub 만.
- **GitLab / Bitbucket / Gitea PR 자동 생성**: v0.5 후보. `lib/pr-platform.sh` 추상화 도입 예정.
- **Cypress / Puppeteer → Playwright 자동 마이그레이션**: 의미 차이 큰 영역 (특히 Cypress) 의 자동 변환은 reliability 가 핵심이라 별도 minor 또는 별도 plugin 후보.

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
  - **Step 9d-main** — `gh pr create` 후 `attachments_upload` → `gh api -X PATCH` 으로 placeholder 교체 (gh pr edit 의 GraphQL Projects classic deprecation 경고로 인한 exit 1 회피). orphan 브랜치에는 `.webm` 과 ffmpeg 으로 동시 변환된 `.gif` 를 함께 push. PR body 는 **GIF inline (자동 재생, 무음) + .webm 클릭 링크 (새 탭에서 native player + 음성 재생)** 의 hybrid markdown.

- **ffmpeg 기반 GIF 미리보기** (Path C hybrid) — `scripts/pr-helper.sh`
  - 2-pass palette 변환 (`palettegen` + `paletteuse dither=bayer:bayer_scale=5`) 으로 256 색 GIF 생성. default `480px` 가로 / `10fps` / `60s` cap.
  - GitHub PR body 는 `<video>` 태그를 strip 하고 `/blob/.webm` 도 inline 안 함 — 그래서 GIF 인라인 미리보기 + .webm 클릭 native player 로 양쪽 다 충족 (음성 + 풀 화질은 .webm, 인라인 자동 재생은 GIF).
  - ffmpeg 미설치 시 graceful degrade: webm 링크만 첨부 + "install ffmpeg for inline GIF previews" 안내. 변환 실패 시도 동일.
  - env override: `SCV_GIF_WIDTH` / `SCV_GIF_FPS` / `SCV_GIF_MAX_SECONDS`.

- **`/scv:status` 에 `[scv-attachments]` 섹션** — backend, retention, active/stale/total size 표시

### Changed

- **`scripts/pr-helper.sh`** — `lib/attachments.sh` 호출 + 비디오 수집 (.webm/.mp4) + Test evidence 섹션 (Videos + Screenshots) + create-then-edit 흐름. orphan 브랜치 URL 은 `/raw/` 사용 (`/blob/` 은 image 만 inline 렌더, video / GIF 는 안 됨). dry-run 출력에도 비디오 경로 + 예상 raw URL + ffmpeg 변환 가능 여부 표시.
- **`scripts/status.sh`** — `[scv-attachments]` 신규 섹션. `lib/attachments.sh::attachments_status` 호출.
- **`template/scv/TESTING.md §3.3`** (신설) — PR 비디오 자동 첨부 안내 + .env 설정 예시.
- **`template/scv/PROMOTE.md`** — TESTS.md 작성 가이드에 비디오 증거 자동 첨부 한 단락.
- **`template/.env.example.scv`** — `SCV_ATTACHMENTS_BACKEND` · `SCV_ATTACHMENTS_RETENTION_DAYS` · `SCV_ATTACHMENTS_BRANCH` · `SCV_GIF_WIDTH` · `SCV_GIF_FPS` · `SCV_GIF_MAX_SECONDS` env vars 추가.

### Tests

- `tests/run-dry.sh` 새 섹션 [11ee–11ll] 8개. 330 → **357 PASS** (+27 assertion). 0 FAIL.
- 검증 영역: pr-helper 비디오 감지 · URL 파싱 (3 형식 + non-GitHub 거부) · 백엔드 dispatch + s3/r2 stub · 크기 가드 · cleanup with mock gh CLI · Step 5b/9d-prep/9d-main content.

### 비채택 (의도적, 후속 버전)

- **CDP MCP 기반 화면 녹화**: MCP 도구 없음. Playwright 만 지원. v0.4 이상에서 검토.
- **`s3` / `r2` 백엔드 실제 구현**: v0.3 은 abstraction + stub 만. v0.4 에서 `_attachments_s3_*` / `_attachments_r2_*` 본문.
- **GitLab / Bitbucket / Gitea 지원**: v0.4. `lib/pr-platform.sh` 추상화 도입 예정.
- **`attachments_status` 의 stale 정확 카운트**: v0.3 에선 `?` (gh API 호출 부담). v0.4 캐싱 후 정확 표시.

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
