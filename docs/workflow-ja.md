# CodePrism ワークフロー（日本語）

## 概要

CodePrism は、エヴァンゲリオンの MAGI をモチーフにした **3 エージェント並列開発** オーケストレータです。Cursor のエージェント CLI または SDK、手動実行に対応します。

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
codeprism run --task "機能 X を実装" --base main
```

## フェーズ

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
