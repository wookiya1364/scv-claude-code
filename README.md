<div align="center">

<img src="assets/scv-circle.png" width="160" height="160" alt="SCV mascot" />

<h1>SCV</h1>

<p><b>Standard · Cowork · Verify</b></p>

<p>
A Claude Code plugin for team workflows.<br>
Every change becomes a plan + tests before merging, and those tests accumulate into a self-running regression suite.
</p>

<p>
<a href="https://github.com/wookiya1364/scv-claude-code/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/wookiya1364/scv-claude-code?label=release&color=blue" /></a>
<img alt="License" src="https://img.shields.io/badge/license-MIT-green" />
<img alt="Claude Code plugin" src="https://img.shields.io/badge/Claude%20Code-plugin-D97757" />
<img alt="Regression" src="https://img.shields.io/badge/tests-412_PASS-brightgreen" />
<img alt="i18n" src="https://img.shields.io/badge/i18n-EN_·_KO_·_JA-purple" />
</p>

<p>
<a href="#quick-start--four-steps">Quick Start</a> ·
<a href="#slash-commands--seven-total">Commands</a> ·
<a href="#end-to-end-flow">End-to-end flow</a> ·
<a href="CHANGELOG.md">Changelog</a>
</p>

</div>

---

> **Team collaboration plugin for Claude Code · Claude Code 팀 협업 플러그인 · Claude Code のチーム協業プラグイン**

Click a language below to expand. **English** is open by default.

<details open>
<summary><b>English</b></summary>

## What is SCV?

A **team collaboration plugin** for Claude Code. It does three things.

| Letter | Meaning | What it does |
|:-:|---|---|
| **S** | Standard | Fill team standard docs **through conversation** with Claude |
| **C** | Cowork | Drop materials into `scv/raw/`, organize by topic |
| **V** | Verify | Auto-report implementation results to Slack/Discord |

> **Core idea**: Accumulate → refine → implement → verify team knowledge with Claude, packaged as **a single plugin**.

## Quick Start — Four Steps

**Step 1 — Install or update the plugin** (in a Claude Code session — same 4 commands for **every case**: first install, update, reinstall)

```
/plugin marketplace remove scv-claude-code
/plugin marketplace add https://github.com/wookiya1364/scv-claude-code
/plugin install scv@scv-claude-code
/reload-plugins
```

> On a brand-new machine the first line says "marketplace not found" — harmless, just continue. Run these four any time you want the latest version from GitHub.

**Step 2 — Check status (always do this first)**

```
/scv:help
```

Diagnoses your project and tells you what to do next. When unsure, run `/scv:help` first.

**Step 3 — Hydrate your project** (once per directory)

Run the hydrate command shown in `/scv:help`'s output.

- **Default — adoption mode** (recommended for existing projects): standard docs are seeded as `status: N/A`; `/scv:promote` and `/scv:work` are immediately usable. Document only the subsystems you actually touch.
- **Greenfield mode**: append `--new` to the hydrate command if this is a brand-new project and you want `/scv:help` to drive the full INTAKE protocol.

> Either way, SCV only creates files inside `scv/`. Your root `CLAUDE.md` (if any) is never touched.

**Step 4 — Run `/scv:help` again**

See what changed and get the next-step guidance.

From here `/scv:help` keeps routing you through `.env` setup, raw changes, active promote plans, and implementation — whatever comes next. **Stuck at any point? Run `/scv:help`.**

## Slash Commands — Seven Total

| Command | What | When |
|---|---|---|
| **`/scv:help`** | **Diagnose state + recommend next action** *(read-only)* | When unsure — always first |
| **`/scv:status`** | **Inspect current state in detail** *(read-only)* — raw changes, active promote, epic progress | After dropping files into `scv/raw/` |
| **`/scv:promote`** | **Organize raw → promote folder** *(interactive, creates PLAN + TESTS)* — auto-suggests epic split for big requests | When raw materials accumulate |
| **`/scv:work`** | **Implement a promote plan** *(writes code + runs tests + archives + opens PR)* — screenshots + Playwright videos auto-attached to PR | When starting implementation |
| **`/scv:regression`** | **Run accumulated regression on archived TESTS** *(auto-skips supersedes/obsolete; triages failures)* | Periodically, before releases, or before archive |
| **`/scv:report`** | **Post a phase report to Slack/Discord** | When sharing results with the team |
| **`/scv:sync`** | **Apply plugin updates to your project** | After plugin version bumps |

Just type the command — Claude handles the rest by asking when needed. No flags to memorize.

## End-to-End Flow

```
 ┌───────────────────────┐
 │  Drop into scv/raw/   │   meetings, sketches, PDFs, recordings — any format
 │  (anyone · anytime)   │
 └───────────┬───────────┘
             │
 ┌───────────▼───────────┐
 │  /scv:promote         │   Claude groups by topic, proposes refinement
 │                       │   User approves per-candidate
 └───────────┬───────────┘
             │
 ┌───────────▼───────────┐
 │  scv/promote/<slug>/  │   PLAN.md + TESTS.md (refs to Jira/PR/...)
 └───────────┬───────────┘
             │
 ┌───────────▼───────────┐
 │  /scv:work <slug>     │   implement → run tests → archive on pass
 └───────────┬───────────┘
             │
 ┌───────────▼───────────┐
 │  /scv:report          │   Notify Slack/Discord
 └───────────────────────┘
```

## Your Project Layout (after hydrate)

```
my-project/
├── CLAUDE.md           # (optional, user-owned — SCV never touches it)
├── scv/                # SCV owns everything under here
│   ├── CLAUDE.md       # SCV workflow index (scoped to SCV only)
│   ├── INTAKE.md       # Conversation protocol (empty template)
│   ├── PROMOTE.md      # raw → promote → archive convention
│   ├── DOMAIN.md       # Domain, terminology, use cases
│   ├── ARCHITECTURE.md # Architecture
│   ├── DESIGN.md       # UI/UX (if any)
│   ├── AGENTS.md       # AI agents (if any)
│   ├── TESTING.md      # Test strategy
│   ├── REPORTING.md    # Team-channel reporting spec
│   ├── RALPH_PROMPT.md # Ralph Loop runtime config
│   ├── readpath.json   # raw change snapshot (auto-managed)
│   ├── promote/        # Active plans (YYYYMMDD-author-slug folders)
│   ├── archive/        # Completed plans (moved by /scv:work)
│   └── raw/            # Free-input space
├── .env.example.scv    # SCV's notifier env template (your existing .env.example is untouched)
└── .gitignore          # SCV rules appended; existing .gitignore preserved
```

> **Non-destructive**: your existing root `CLAUDE.md` and `.env.example` stay intact. SCV creates `scv/` plus a separate `.env.example.scv` (notifier vars) at the root, and appends its ignore rules to an existing `.gitignore` (or creates one from its fragment). Want Claude to be SCV-aware in casual conversations? Add one line to your root `CLAUDE.md`: `> This project uses SCV — see scv/CLAUDE.md.`

## Notifier Setup (.env) — Optional

To auto-post phase results to Slack or Discord:

```bash
cp .env.example.scv .env
$EDITOR .env
```

Required values (Slack example):

```bash
NOTIFIER_PROVIDER=slack
SLACK_BOT_TOKEN=xoxb-...
SLACK_CHANNEL_ID=C0XXXXX0
SLACK_CHANNEL_ID_PHASE_COMPLETE=C0XXXXX1
SLACK_CHANNEL_ID_E2E_FAILURE=C0XXXXX2
```

For Discord: `NOTIFIER_PROVIDER=discord` + `DISCORD_BOT_TOKEN` · `DISCORD_CHANNEL_ID_*`.

> If you already have a project `.env` / `.env.example`, SCV's template lives in `.env.example.scv` instead — `cp .env.example.scv .env` or `cat .env.example.scv >> .env` to merge.

> Never commit `.env` to git. `.gitignore` already blocks it.

## Learn More

- Each command's detail: `/scv:<command> --help`
- Project-specific guide: `/scv:help`
- Changelog: [CHANGELOG.md](./CHANGELOG.md)

## Contributing

- Run `tests/run-dry.sh` before PRs
- Log user-facing changes in `CHANGELOG.md`
- Follow SemVer for `VERSION` bumps

</details>

<details>
<summary><b>한국어</b></summary>

## SCV 가 뭐예요?

Claude Code 용 **팀 협업 플러그인**입니다. 세 가지 일을 합니다.

| 글자 | 의미 | 무엇을 하나 |
|:-:|---|---|
| **S** | Standard (표준) | 표준 문서를 Claude 와 **대화로 채움** |
| **C** | Cowork (협업) | 회의록·자료를 `scv/raw/` 에 던지면 주제별로 정리 |
| **V** | Verify (검증) | 구현 결과를 Slack/Discord 로 자동 보고 |

> **핵심 메시지**: 팀 지식을 Claude 와 함께 축적·정제·구현·검증하는 흐름을 **플러그인 하나**로 제공합니다.

## 빠른 시작 — 딱 네 단계

**1단계 — 플러그인 설치 또는 업데이트** (Claude Code 세션에서 — **모든 경우 동일한 4줄**: 첫 설치·업데이트·재설치)

```
/plugin marketplace remove scv-claude-code
/plugin marketplace add https://github.com/wookiya1364/scv-claude-code
/plugin install scv@scv-claude-code
/reload-plugins
```

> 첫 설치 시 첫 줄에서 "marketplace not found" 가 떠도 무시하고 계속 진행. GitHub 에서 최신 버전을 받고 싶을 때 언제든 이 4줄을 실행하면 됩니다.

**2단계 — 상태 확인 (항상 가장 먼저 실행)**

```
/scv:help
```

현재 프로젝트가 어떤 상태인지, 다음에 무엇을 하면 되는지 **알려줍니다**. 무엇을 해야 할지 모르겠으면 항상 `/scv:help` 먼저.

**3단계 — 내 프로젝트 초기화** (디렉토리당 한 번만)

`/scv:help` 출력에 보이는 hydrate 명령을 그대로 실행.

- **기본 — adoption 모드** (기존 프로젝트에 권장): 표준 문서는 `status: N/A` 로 시드되고 `/scv:promote`, `/scv:work` 를 즉시 사용 가능. 본인이 건드리는 subsystem 만 그때그때 문서화.
- **Greenfield 모드**: 신규 프로젝트에서 INTAKE 프로토콜로 전체 표준 문서를 정의하고 싶으면 hydrate 명령 뒤에 `--new` 를 붙이세요.

> 어느 모드든 SCV 는 **`scv/` 안에만** 파일을 만듭니다. 루트 `CLAUDE.md` 는 (있다면) 절대 건드리지 않음.

**4단계 — 다시 `/scv:help`**

무엇이 달라졌는지 확인하고 다음 액션 안내를 받습니다.

이후 `.env` 설정, raw 변경, 활성 promote 계획, 구현까지 상태에 맞춰 `/scv:help` 가 계속 다음 커맨드를 안내해 줍니다. **어느 단계든 막히면 `/scv:help`.**

## 슬래시 커맨드 — 7개

| 커맨드 | 역할 | 언제 쓰나요 |
|---|---|---|
| **`/scv:help`** | **상태 진단 + 다음 액션 추천** *(읽기만)* | 뭘 해야 할지 모를 때 — 항상 가장 먼저 |
| **`/scv:status`** | **현재 상태 자세히 보기** *(읽기만)* — raw 변경 · 활성 promote · epic 진척도 | raw 에 파일 넣은 뒤 확인할 때 |
| **`/scv:promote`** | **raw → promote 폴더로 정리** *(대화 · PLAN + TESTS 생성)* — 거대 요구는 epic 분할 자동 제안 | raw 에 새 자료가 쌓였을 때 |
| **`/scv:work`** | **promote 계획 구현** *(코드 작성 · 테스트 실행 · archive · PR 생성)* — 스크린샷 + Playwright 비디오 PR 자동 첨부 | 구현 시작할 때 |
| **`/scv:regression`** | **archived TESTS 누적 회귀** *(supersedes/obsolete 자동 skip · 실패 시 triage)* | 주기적, 릴리즈 전, archive 직전 |
| **`/scv:report`** | **Slack/Discord 에 Phase 결과 보고** | 결과를 팀에 공유할 때 |
| **`/scv:sync`** | **플러그인 업데이트를 내 프로젝트에 반영** | 플러그인 버전이 올라간 뒤 |

커맨드만 입력하면 됩니다 — Claude 가 필요할 때 물어봐 줍니다. 외울 플래그 없음.

## 전체 흐름 한 장 요약

```
 ┌───────────────────────┐
 │  scv/raw/ 에 자료 투입  │   회의록·스케치·PDF·녹화 — 형식 자유
 │  (누구나 · 언제든)      │
 └───────────┬───────────┘
             │
 ┌───────────▼───────────┐
 │  /scv:promote         │   Claude 가 주제별로 묶어 정제 제안
 │                       │   사용자가 건건이 승인
 └───────────┬───────────┘
             │
 ┌───────────▼───────────┐
 │  scv/promote/<slug>/  │   PLAN.md + TESTS.md (refs: Jira/PR 등)
 └───────────┬───────────┘
             │
 ┌───────────▼───────────┐
 │  /scv:work <slug>     │   구현 → 테스트 실행 → 통과 시 archive
 └───────────┬───────────┘
             │
 ┌───────────▼───────────┐
 │  /scv:report          │   Slack/Discord 로 결과 알림
 └───────────────────────┘
```

## 내 프로젝트 디렉토리 (초기화 후)

```
my-project/
├── CLAUDE.md           # (선택, 사용자 소유 — SCV 가 건드리지 않음)
├── scv/                # SCV 가 소유하는 영역
│   ├── CLAUDE.md       # SCV 워크플로 인덱스 (SCV 범위 전용)
│   ├── INTAKE.md       # 대화 프로토콜 (빈 템플릿)
│   ├── PROMOTE.md      # raw → promote → archive 승격 규약
│   ├── DOMAIN.md       # 도메인·용어·유스케이스
│   ├── ARCHITECTURE.md # 아키텍처
│   ├── DESIGN.md       # UI/UX (있을 때)
│   ├── AGENTS.md       # AI 에이전트 (있을 때)
│   ├── TESTING.md      # 테스트 전략
│   ├── REPORTING.md    # 협업툴 보고 규약
│   ├── RALPH_PROMPT.md # Ralph Loop 실행 설정
│   ├── readpath.json   # raw 변경 스냅샷 (자동 관리)
│   ├── promote/        # 활성 계획 (YYYYMMDD-author-slug 폴더)
│   ├── archive/        # 완료 계획 (/scv:work 가 이동)
│   └── raw/            # 자유 투입 공간
├── .env.example.scv    # SCV 전용 Notifier 변수 템플릿 (기존 .env.example 은 건드리지 않음)
└── .gitignore          # SCV 규칙을 뒤에 append; 기존 .gitignore 내용 보존
```

> **Non-destructive**: 본인의 루트 `CLAUDE.md` 와 `.env.example` 은 그대로 보존됩니다. SCV 는 `scv/` 를 만들고, 루트에 별도 `.env.example.scv` (Notifier 변수) 를 추가하며, 기존 `.gitignore` 가 있으면 SCV 규칙만 뒤에 붙입니다 (없으면 fragment 에서 생성). 평소 대화에서 Claude 가 SCV 를 인지하길 원하면 본인의 루트 `CLAUDE.md` 에 한 줄: `> 이 프로젝트는 SCV 사용 — scv/CLAUDE.md 참조.`

## 협업툴 설정 (.env) — 선택 사항

Phase 결과를 Slack 이나 Discord 에 자동으로 올리려면:

```bash
cp .env.example.scv .env
$EDITOR .env
```

필수 값 (Slack 예시):

```bash
NOTIFIER_PROVIDER=slack
SLACK_BOT_TOKEN=xoxb-...
SLACK_CHANNEL_ID=C0XXXXX0
SLACK_CHANNEL_ID_PHASE_COMPLETE=C0XXXXX1
SLACK_CHANNEL_ID_E2E_FAILURE=C0XXXXX2
```

Discord 는 `NOTIFIER_PROVIDER=discord` + `DISCORD_BOT_TOKEN` · `DISCORD_CHANNEL_ID_*`.

> 이미 본인 프로젝트의 `.env` / `.env.example` 이 있다면 SCV 템플릿은 `.env.example.scv` 에 있습니다 — `cp .env.example.scv .env` 하거나 `cat .env.example.scv >> .env` 로 append.

> `.env` 는 절대 git 에 커밋 금지. `.gitignore` 가 이미 차단합니다.

## 더 알아보기

- 각 커맨드 상세: `/scv:<command> --help`
- 현재 프로젝트 맞춤 안내: `/scv:help`
- 변경 이력: [CHANGELOG.md](./CHANGELOG.md)

## 기여

- PR 전에 `tests/run-dry.sh` 통과 확인
- 사용자 영향 변경은 `CHANGELOG.md` 에 기록
- `VERSION` bump 은 SemVer 따름

</details>

<details>
<summary><b>日本語</b></summary>

## SCV とは？

Claude Code 向けの**チーム協業プラグイン**です。3 つのことを行います。

| 文字 | 意味 | 何をするか |
|:-:|---|---|
| **S** | Standard (標準) | チーム標準ドキュメントを Claude との**対話で埋める** |
| **C** | Cowork (協業) | 会議録・資料を `scv/raw/` に投入 → トピック別に整理 |
| **V** | Verify (検証) | 実装結果を Slack / Discord へ自動レポート |

> **コアアイデア**: チームの知識を Claude と共に蓄積 → 精製 → 実装 → 検証するフローを**プラグイン 1 つ**で提供。

## クイックスタート — 4 ステップ

**ステップ 1 — プラグインのインストール / アップデート** (Claude Code セッションで — **全ケース共通の 4 行**: 初回インストール · アップデート · 再インストール)

```
/plugin marketplace remove scv-claude-code
/plugin marketplace add https://github.com/wookiya1364/scv-claude-code
/plugin install scv@scv-claude-code
/reload-plugins
```

> 初回インストール時、1 行目に "marketplace not found" と出ても無視して続行。GitHub から最新版を取得したい時はいつでもこの 4 行を実行してください。

**ステップ 2 — 状態を確認 (必ず最初に実行)**

```
/scv:help
```

現在のプロジェクトを診断し、次に何をすべきかを**提案します**。困ったらまず `/scv:help`。

**ステップ 3 — プロジェクトを hydrate** (ディレクトリごとに 1 回)

`/scv:help` の出力に表示される hydrate コマンドをそのまま実行。

- **デフォルト — adoption モード** (既存プロジェクトに推奨): 標準ドキュメントは `status: N/A` でシードされ、`/scv:promote` と `/scv:work` が即座に利用可能。実際に触る subsystem だけをその都度文書化。
- **Greenfield モード**: 新規プロジェクトで INTAKE プロトコルに沿って全標準ドキュメントを定義したい場合、hydrate コマンドの末尾に `--new` を付けます。

> いずれのモードでも SCV は **`scv/` の中にしか**ファイルを作成しません。ルートの `CLAUDE.md` は (あっても) 一切触りません。

**ステップ 4 — もう一度 `/scv:help`**

何が変わったかを確認し、次のアクションの案内を受け取ります。

以降も `.env` 設定・raw の変更・アクティブな promote 計画・実装まで、状態に応じて `/scv:help` が次のコマンドを提案し続けます。**どこで詰まっても `/scv:help`。**

## スラッシュコマンド — 7 つ

| コマンド | 役割 | いつ使う |
|---|---|---|
| **`/scv:help`** | **状態診断 + 次のアクション推奨** *(読み取り専用)* | 何をすべきか分からないとき — 必ず最初 |
| **`/scv:status`** | **詳細な現在状態の確認** *(読み取り専用)* — raw 変更 · アクティブ promote · epic 進捗 | raw にファイルを投入した後 |
| **`/scv:promote`** | **raw → promote フォルダへ整理** *(対話 · PLAN + TESTS 生成)* — 大きな要求は epic 分割を自動提案 | raw に資料が溜まったとき |
| **`/scv:work`** | **promote 計画を実装** *(コード · テスト実行 · archive · PR 作成)* — スクリーンショット自動添付 | 実装開始時 |
| **`/scv:regression`** | **archived TESTS の累積回帰** *(supersedes/obsolete 自動 skip · 失敗時 triage)* | 定期的・リリース前・archive 直前 |
| **`/scv:report`** | **Slack/Discord に Phase 結果レポート** | 結果をチームに共有するとき |
| **`/scv:sync`** | **プラグイン更新を自分のプロジェクトに反映** | プラグインバージョンアップ後 |

コマンドだけ入力すれば OK — Claude が必要なときに尋ねます。覚えるフラグなし。

## 全体フロー

```
 ┌───────────────────────┐
 │  scv/raw/ に資料投入   │   会議録・スケッチ・PDF・録画 — 形式自由
 │  (誰でも · いつでも)    │
 └───────────┬───────────┘
             │
 ┌───────────▼───────────┐
 │  /scv:promote         │   Claude がトピック別にまとめて精製提案
 │                       │   ユーザーが個別に承認
 └───────────┬───────────┘
             │
 ┌───────────▼───────────┐
 │  scv/promote/<slug>/  │   PLAN.md + TESTS.md (refs: Jira/PR 等)
 └───────────┬───────────┘
             │
 ┌───────────▼───────────┐
 │  /scv:work <slug>     │   実装 → テスト → 通過時 archive
 └───────────┬───────────┘
             │
 ┌───────────▼───────────┐
 │  /scv:report          │   Slack / Discord に結果通知
 └───────────────────────┘
```

## プロジェクトディレクトリ (hydrate 後)

```
my-project/
├── CLAUDE.md           # (任意 · ユーザー所有 — SCV は触らない)
├── scv/                # SCV が所有する領域
│   ├── CLAUDE.md       # SCV ワークフローのインデックス (SCV 範囲限定)
│   ├── INTAKE.md       # 対話プロトコル (空テンプレート)
│   ├── PROMOTE.md      # raw → promote → archive 昇格規約
│   ├── DOMAIN.md       # ドメイン・用語・ユースケース
│   ├── ARCHITECTURE.md # アーキテクチャ
│   ├── DESIGN.md       # UI/UX (ある場合)
│   ├── AGENTS.md       # AI エージェント (ある場合)
│   ├── TESTING.md      # テスト戦略
│   ├── REPORTING.md    # チーム通知規約
│   ├── RALPH_PROMPT.md # Ralph Loop 実行設定
│   ├── readpath.json   # raw 変更スナップショット (自動管理)
│   ├── promote/        # アクティブな計画 (YYYYMMDD-author-slug フォルダ)
│   ├── archive/        # 完了した計画 (/scv:work が移動)
│   └── raw/            # 自由投入スペース
├── .env.example.scv    # SCV 専用 Notifier 変数テンプレート (既存の .env.example は触らない)
└── .gitignore          # SCV ルールを末尾に append; 既存 .gitignore の内容は保持
```

> **Non-destructive**: ご自身のルート `CLAUDE.md` と `.env.example` はそのまま保持されます。SCV は `scv/` を作成し、ルートに別途 `.env.example.scv` (Notifier 変数) を追加し、既存の `.gitignore` があれば SCV ルールのみ末尾に追加します (なければ fragment から生成)。通常の対話で Claude に SCV を認識させたい場合は、ご自身のルート `CLAUDE.md` に 1 行: `> このプロジェクトは SCV を使用 — scv/CLAUDE.md 参照。`

## 通知ツール設定 (.env) — 任意

Phase 結果を Slack / Discord に自動投稿するには:

```bash
cp .env.example.scv .env
$EDITOR .env
```

必須値 (Slack 例):

```bash
NOTIFIER_PROVIDER=slack
SLACK_BOT_TOKEN=xoxb-...
SLACK_CHANNEL_ID=C0XXXXX0
SLACK_CHANNEL_ID_PHASE_COMPLETE=C0XXXXX1
SLACK_CHANNEL_ID_E2E_FAILURE=C0XXXXX2
```

Discord の場合: `NOTIFIER_PROVIDER=discord` + `DISCORD_BOT_TOKEN` · `DISCORD_CHANNEL_ID_*`。

> 既にご自身のプロジェクトの `.env` / `.env.example` がある場合、SCV のテンプレートは `.env.example.scv` にあります — `cp .env.example.scv .env` または `cat .env.example.scv >> .env` でマージしてください。

> `.env` は絶対に git にコミットしないこと。`.gitignore` が既にブロックしています。

## さらに詳しく

- 各コマンドの詳細: `/scv:<command> --help`
- プロジェクト固有の案内: `/scv:help`
- 変更履歴: [CHANGELOG.md](./CHANGELOG.md)

## コントリビューション

- PR の前に `tests/run-dry.sh` を通す
- ユーザー影響のある変更は `CHANGELOG.md` に記録
- `VERSION` は SemVer に従う

</details>

---

**License**: [MIT](./LICENSE) © 2026 wookiya1364
