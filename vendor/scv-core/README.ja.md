# SCV Core

[English](README.md) · [한국어](README.ko.md)

SCV Core は、Claude Code 版 SCV と Codex 版 SCV が共有するホスト中立の
正本です。ワークフロープロトコル、実行スクリプト、プロジェクトテンプレート、
DeckUI、アセット、共通回帰テストをこのリポジトリで管理します。各ラッパーは
変更不能な Core リリースを固定し、検証済みホストプロファイルを反映してから、
ランタイム固有のアダプターだけを追加します。

バージョンはファイルにあるため、このページは古くなりません。

| 契約 | ファイル | 意味 |
|---|---|---|
| SCV Core | [`VERSION`](VERSION) | 共通動作とリリースペイロード |
| Core API | [`CORE_API`](CORE_API) | ラッパーと Core の統合契約 |
| Template | [`TEMPLATE_VERSION`](TEMPLATE_VERSION) | hydrate されるプロジェクトテンプレートのスキーマ |

最新の公開 Core は
[リリースページ](https://github.com/wookiya1364/scv-core/releases/latest)にあります。
インストール可能なプラグイン:

- [SCV for Claude Code](https://github.com/wookiya1364/scv-claude-code)
- [SCV for Codex](https://github.com/wookiya1364/scv-codex)

## 構造

```text
scv-core リリース（変更不能な tarball + SHA-256）
                  │
                  ├── scv-claude-code が固定・具体化
                  └── scv-codex が固定・具体化
                                      │
                                      └── 実行時の取得なしでローカル実行
```

15 個の SCV アクションのうち 13 個を Core が所有します。インストール方法と
モデル選択はホスト依存のため、`update` と `set-models` はアダプター所有です。
正規プロトコルは `action:<name>` と `{{SCV_ARGS}}` を使い、実際のコマンド構文
と引数形式は検証済みホストプロファイルからのみ注入されます。`scv/SCV.md` は
最上位の規則と、規則どうしが衝突したときの優先順位から始まり、すべての
プロトコルがそれに従います。

### 毎ターン

コマンドだけが入口ではありません。毎ターンのフックが自由会話を help アクション
へルーティングし（`SCV_ALWAYS_ON`、既定はオン）、短いプロジェクト診断を添える
ので、モデルは状態を聞き直さず実際の状態から始められます。help の規約全体は
セッションごとに一度だけ読みます。フックはその規約の指紋を覚えておき、記録された
ターンから指紋が消えたときや、答えが答えの形から外れたときに規約を載せ直します
（`SCV_HELP_LOAD_ONCE`、`SCV_HELP_RELOAD_EVERY`）。

- **やさしい言葉** — 答えは一、二文の結論から始め、例を一つ挙げ、コードの値は
  聞かれたときだけ見せます（`SCV_PLAIN_LANGUAGE`、`SCV_PLAIN_MAX_SENTENCES`）。
  終了フックが答えの形を検査します（`SCV_ANSWER_LINT`）。
- **モデル別プロンプティング** — ラッパーがあるモデルの公式プロンプティングガイド
  （原文そのままのオフライン写し）を同梱していれば、help はコンテキストごとに
  一度その原文を読み、依頼をそのモデルに最適なプロンプトへ書き直します。毎ターン、
  依頼をそのモデルの要求項目リストと一つずつ照合して登録します — 各項目はガイドを
  一字一句引用し、ラッパーの CI が引用を検査します。そのターンの登録前のファイル
  書き込みは拒否され、登録か書き直した依頼の引用がないまま終わるターンは一度
  止められます（`SCV_MODEL_PROMPTING`）。
- **再開サマリー** — 圧縮、`/clear`、再開のあと、セッション開始フックが進行中の
  計画、最近の決定、未決事項、進行中の会話を載せ直します（`SCV_RESUME_RECAP`）。
  記録一つは名前で展開します: `core/scripts/record-read.sh --key <name>`。
  ホストのセッション開始フックが必要です。
- **バックグラウンド調査** — `SCV_DELEGATE_EFFORT=on`（既定はオフ）のとき、深い
  質問はバックグラウンドの調査担当へ渡り、報告は `scv/raw/` に残ります。セッション
  のモデルと思考量は変えません。ホストのエージェントが必要です。

プロジェクト設定は `scv/scv_settings.json` (+ git-ignore される secret ファイル)
にあり、全キーが説明つきで自動生成されます。プロジェクトの `.env` は読みません。
全キーと既定値:
[`core/template/scv/scv_settings.example.json`](core/template/scv/scv_settings.example.json)。

### 計画・証跡・記録

- **絵で見る計画** — すべての計画書には純粋関数パイプラインの節があり、deck
  アクションは計画の図の文書（`FEATURE_ARCHITECTURE.md`）を番号付き画面設計書
  として描きます。大きな図一枚に番号を振り、番号ごとの説明を横に置き、検証
  メッセージの表を添え、`PLAN.md` と `TESTS.md` は原文タブとして付きます。
- **SCV 独自のグラフ** — 文書リンク、保管された計画とファイル、決定の参照、一緒に
  変わるファイルを、promote と work が bash と jq だけで自動的に作り直します。
  インストールは不要です（`SCV_GRAPH`）。Graft は任意です。入っていれば計画・
  実装のヘッダーに関連コードの候補と変更の影響範囲が付き（`SCV_GRAFT`）、SCV が
  自らインストールすることはありません。
- **過去の作業の検索** — help の想起モードは、タイトルだけでなく計画の本文、
  テスト、決定ログ、会話まで調べます
  （[`archive-search`](core/protocols/help/archive-search.md)）。
- **決定** — `scv/DECISIONS.md` は追記専用の記録で、計画の承認・保管・廃止の
  ときと、途中で得た教訓を書きます。
- **プロセス計器盤** — `core/scripts/metrics.sh` はプロジェクトの記録（保管
  インデックス、計画書、会話、決定）を読み、プロセスを数字で示します。ファイルは
  何も書きません。
- **証跡** — PR の添付はファイル名ではなく記録されたテスト実行に従い、ブランチ
  ごとに PR は一つで、同じ証跡をチームのチャンネルにも送れます。

### 状態インデックスと DeckUI キャッシュ

共有状態インデックスは常に `scv/SCV.md` です。旧ラッパーからの移行中は、
`SCV.md` がない場合に限り `CLAUDE.md` または `CODEX.md` を読みます。独立した
状態ファイルが異なる場合、変更を伴う sync は何も変更せず停止します。両方の
ラッパーは Core 所有の単一 resolver と pointer finalizer を使用し、互換
pointer は正確な `SCV:HOST-POINTER target=SCV.md` marker だけで判定します。

インストール済みラッパーの DeckUI 原本は変更しません。依存関係、生成 deck、
ビルド出力は Core ペイロードハッシュ別の外部キャッシュに保存されるため、
Claude Code と Codex は同じランタイムを再利用しながら、どちらのプラグインにも
書き込みません。既定のユーザーキャッシュは `SCV_DECK_CACHE_DIR` で変更できます。
キャッシュ初期化と旧ランタイム移行は、並行して現れた宛先を置換せず、宛先の
祖先リンクをたどらず、キャッシュと旧ランタイムが重なる場合は書き込み前に
停止します。
キャッシュ base、ペイロード namespace、ランタイム target、lock、staging、
install、cleanup は、すべて検証済みのオープン済みディレクトリ descriptor に
固定されます。処理中にパスや祖先が置換されても、外部パスへ書き込みや削除を
転送せず、安全側で停止します。

旧ランタイムの移行は既定で strict です。source と異なる cache 値が既に
あれば collision として停止します。永続的に残る legacy source に限り、
`migrate --from PATH --reuse-existing` を明示できます。全対象の preflight
で既存 destination が一つでも source と異なる場合、現在の cache 全体を
authoritative とし、legacy source 全体を skip します。同一または未作成の
項目もコピーしません。相違がなければ従来どおり additive に移行し、
preflight 後に発生した collision は引き続き fail-closed です。wrapper
swap 後に削除され得る既存 vendor の recovery は、必ず strict mode の
まま実行します。

### guard とマージ時のゲート

Core は、このワークフローが守られているかを確かめる仕組みも同梱します。
workspace guard は `PreToolUse` フックとして動き、二つを拒否します。計画
ファイルの新規作成と、ワークフローディレクトリ外への書き込みです。このセッション
中にホストが「SCV アクションが実行中」と報告していれば例外です。そのホスト
イベントはモデルが偽造できない唯一の信号なので、guard はそれだけを根拠にします。
三つ目の規則は、そのターンの依頼がモデルの要求項目リストに登録されるまで
ファイルの書き込みを拒否します（上のモデル別プロンプティング）。guard が
fail-open するのは、payload が空のときと JSON リーダーが無い機械の二つだけで、
すべてのプロジェクトの書き込みを止める事態を避けます。逆にレシート置き場が
書けないときは閉じる側に倒れます。SCV を導入していないプロジェクトでは何も
しません。登録はラッパーの仕事です。ラッパーがフック項目ごとに `SCV_GUARD_MODE`
を渡すため、スクリプト自体はホストを名指ししません。規則は
[guard 契約](core/contracts/guard.md) にあります。

フックからは見えない部分は、マージ時の二つのゲートが受け持ちます。
`core/scripts/check-provenance.sh` は、コードを変更しながら
`scv/archive/<slug>/PLAN.md` に保管された計画を追加していない PR を拒否します。
文書とワークフローディレクトリだけの diff はコード変更とみなしません。
`core/scripts/check-vendor-provenance.sh` は、sync bot 以外のブランチで
ラッパーの `vendor/scv-core/` を書き換えた PR を拒否します。bot は公開済みの
リリース成果物を解決して正本ハッシュと具体化後ハッシュの両方を記録しますが、
手作業のコピーはそのときの作業ツリーの内容をそのまま記録します。どちらのゲート
も `stage`・`main` へのリリースチェーンと bot の `chore/core-*` ブランチを除外
し、PR タイトルで `[no-plan: <理由>]`、`[manual-vendor: <理由>]` として例外を
宣言できます。理由は必須で、理由のない marker は拒否します。Core 自身の CI は
provenance ゲートを実行し、vendor ゲートは vendor された Core を持つラッパーの
リポジトリ向けに同梱されます。

詳細は [Architecture](docs/architecture.md)、
[Wrapper integration](docs/wrapper-integration.md)、そして
[Core とラッパーの所有権ガイド](docs/core-wrapper-ownership.ko.md)（韓国語）を
参照してください。

## 検証とテスト

```bash
bash tests/run.sh
bash core/tests/run-dry.sh
for test_file in core/tests/test-*.sh; do bash "$test_file"; done
```

`tests/run.sh` は `tools/check-readme.sh` でこのページもリポジトリと照合します。
書かれた設定・アクション・リンクはすべて実在し、三つの言語版は一致して
いなければなりません。

DeckUI のソースチェックアウト開発には Node.js と pnpm も必要です。

```bash
pnpm -C core/DeckUI install --frozen-lockfile
pnpm -C core/DeckUI typecheck
pnpm -C core/DeckUI build:deck
```

## エクスポートとベンダリング

検証済みのホスト中立エクスポートを作成します。

```bash
tools/export-core.sh --output /tmp/scv-core-export
```

ローカルチェックアウトからラッパー用ペイロードを具体化します。

```bash
tools/vendor-core.sh \
  --source /path/to/scv-core \
  --target /path/to/wrapper/vendor/scv-core \
  --profile /path/to/wrapper/adapter/host-profile.env
```

`core.lock.json` には原本と具体化後のハッシュが記録されます。開発依存、
ビルド出力、キャッシュ、ディレクトリシンボリックリンクはエクスポートされません。

## リリース

```bash
tools/release-artifact.sh --output-dir dist
```

バージョン `X.Y.Z` では次のファイルを生成します。

- `scv-core-vX.Y.Z.tar.gz`
- `scv-core-vX.Y.Z.tar.gz.sha256`

`vX.Y.Z` タグは両ファイルを公開し、続いて両ラッパーへ Core 同期イベントを
送信します。リポジトリ間トークンは必須で、通知に失敗したリリース run は失敗と
して扱われます（公開済みのリリース資産には影響しません）。両ラッパーとも毎日
ポーリングするため、通知の失敗は伝播を失うのではなく遅らせるだけです。ラッパー
自動化はチェックサム検証、ホスト別の再生成、回帰テストを行い、`develop` 向け
PR を作成します。`gh workflow run promote.yml` は `develop → stage → main`
へ昇格し、`-f release=false` を付けるとタグを付けずに昇格するので、文書のように
リリースの要らない変更に使います。詳細は [Release and integrity](docs/release.md)
を参照してください。

## コントリビューション

常設ブランチは `develop`、`stage`、`main` です。作業ブランチは `develop`
へマージし、その後 `develop → stage → main` の順で昇格します。
[Branch policy](.github/BRANCHING.md) を参照してください。
