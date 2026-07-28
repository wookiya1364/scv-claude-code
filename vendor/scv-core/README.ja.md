# SCV Core

[English](README.md) · [한국어](README.ko.md)

SCV Core は、Claude Code 版 SCV と Codex 版 SCV が共有するホスト中立の
正本です。ワークフロープロトコル、実行スクリプト、プロジェクトテンプレート、
DeckUI、アセット、共通回帰テストをこのリポジトリで管理します。各ラッパーは
変更不能な Core リリースを固定し、検証済みホストプロファイルを反映してから、
ランタイム固有のアダプターだけを追加します。

現在の契約バージョン:

| 契約 | バージョン | 意味 |
|---|---:|---|
| SCV Core | `0.20.1` | 共通動作とリリースペイロード |
| Core API | `1` | ラッパーと Core の統合契約 |
| Template | `1.0.0` | hydrate されるプロジェクトテンプレートのスキーマ |

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

14 個の SCV アクションのうち 12 個を Core が所有します。インストール方法と
モデル選択はホスト依存のため、`update` と `set-models` はアダプター所有です。
正規プロトコルは `action:<name>` と `{{SCV_ARGS}}` を使い、実際のコマンド構文
と引数形式は検証済みホストプロファイルからのみ注入されます。

共有状態インデックスは常に `scv/SCV.md` です。旧ラッパーからの移行中は、
`SCV.md` がない場合に限り `CLAUDE.md` または `CODEX.md` を読みます。独立した
状態ファイルが異なる場合、変更を伴う sync は何も変更せず停止します。

詳細は [Architecture](docs/architecture.md) と
[Wrapper integration](docs/wrapper-integration.md) を参照してください。

## 検証とテスト

```bash
bash tests/run.sh
bash core/tests/run-dry.sh
for test_file in core/tests/test-*.sh; do bash "$test_file"; done
```

DeckUI の検証には Node.js と pnpm も必要です。

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

`vX.Y.Z` タグは両ファイルを公開します。リポジトリ間トークンが設定されて
いれば Core 同期イベントも即時送信し、トークンがない場合は各ラッパーの
定期ポーリングが同じ役割を担います。ラッパー自動化はチェックサム検証、
ホスト別の再生成、回帰テストを行い、`develop` 向け PR を作成します。詳細は
[Release and integrity](docs/release.md) を参照してください。

## コントリビューション

常設ブランチは `develop`、`stage`、`main` です。作業ブランチは `develop`
へマージし、その後 `develop → stage → main` の順で昇格します。
[Branch policy](.github/BRANCHING.md) を参照してください。
