# CodePrism ワークフロー（日本語）

## 概要

CodePrism は、**3 エージェント並列開発** オーケストレータです。正しさ・保守性・運用効率の異なる観点から並列実装とクロスレビューを行います。Cursor のエージェント CLI または SDK、手動実行に対応します。

## 3 つの役割

| エージェント | 焦点 |
|-------------|------|
| **Melchior（メルキオール）** | 正しさ・要件・テスト・回帰 |
| **Balthasar（バルタザール）** | 保守性・パターン・一貫性 |
| **Caspar（ガスパール）** | 性能・運用コスト・信頼性 |

## クイックスタート

```bash
export PATH="/path/to/CodePrism/bin:$PATH"
cd your-repo
codeprism init
# タスクを .codeprism/task.yaml に書いてから:
codeprism run --repo .
# またはファイルを直接指定:
codeprism run --task-file path/to/task.md --base main
```

## タスクファイル（YAML / Markdown）

長い `--task` の代わりにファイルを使えます。

| 指定方法 | 例 |
|---------|-----|
| 明示 | `codeprism run -f examples/tasks/github-profile.md --repo .` |
| 既定 | リポジトリ内 `.codeprism/task.yaml`（`init` で雛形作成） |

**YAML** — `title`, `base`（任意）, `task:` または `prompt:`（複数行）

**Markdown** — frontmatter（任意）+ 本文。frontmatter に `task:` がなければ本文全体がタスクになります。

詳細は [README の Task files](../README.md#task-files-yaml--markdown) を参照。

1. **implement** — 各エージェント用 git worktree を作成し、並列で実装。
2. **review** — 3×2 のクロスレビュー（匿名ラベル optional）。
3. **synthesize** — ラポルテュール（既定: Melchior）が `SYNTHESIS.md` を作成。
4. **apply** — 採用案のブランチを cherry-pick または merge。

## 手動モード

`agent.backend: manual` または CLI 未検出時、プロンプトは `.codeprism/sessions/<id>/manual-*.md` に出力されます。作業後:

```bash
codeprism collect --session <id> --repo .
codeprism review --session <id>
```

## tmux / Warp

`codeprism tmux` で 4 ペイン（メイン + 3 エージェント）のレイアウトを起動できます。Warp などのターミナル分割でも同様に worktree パスを開いてください。

## セッションの場所

- メタデータ: `your-repo/.codeprism/sessions/<id>/`
- Worktree: `../.codeprism-worktrees/<id>/<agent>/`

## 制限事項

- YAML パーサはフラットな設定向けの簡易実装です。
- SDK は `optional/sdk` で別途 `npm install` が必要です。
- エージェントの品質はモデルとプロンプトに依存します。
