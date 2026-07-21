# learning-notes

日々の開発・調査の中で学んだことを、知識のアウトプットとして蓄積するための個人リポジトリ。

## 運用方針

- 1トピック1ファイル。`notes/` 配下に `yyyy-mm-dd-トピック名.md` の形式で追加していく。
- 学んだきっかけになった作業・プロジェクト名があれば、メモの中に一言添えておく（後で文脈を思い出しやすくするため）。
- 完璧な文章より、要点が後で見返してわかることを優先する。
- Claude（Claude Code）とのセッションで学んだ内容は、そのセッション終了前にこのリポジトリへメモとして書き出す。別セッションを開いても、このリポジトリのファイルを読めば文脈を引き継げる。

## 自動commit・push（launchd）

このリポジトリの変更は、毎日6:30にmacOSの`launchd`経由で自動的にcommit・pushされる。詳しい設計・検証の経緯は [2026-07-14: launchdによるlearning-notesリポジトリの自動commit・push設定](notes/2026-07-14-launchd-auto-commit.md) を参照。

### スクリプト
- 本体: [scripts/learning-notes-auto-commit.sh](scripts/learning-notes-auto-commit.sh)
- 未コミットの変更（追跡ファイル・未追跡ファイル問わず）を検知し、変更がなければ何もせず終了する（空commitは作らない）。
- 変更があれば、Claude Code CLIをheadlessモード（`claude -p`）で呼び出してコミットメッセージ生成と`git add` / `git commit`のみを行わせる。pushはClaudeにはやらせず、スクリプト自身が固定コマンド`git push origin main`のみを実行する（force pushは行わない）。
- `main`ブランチ以外では何もしない。

### 初回セットアップ（別マシンでこのリポジトリを使う場合）
1. `scripts/learning-notes-auto-commit.env.example`を同じディレクトリに`scripts/learning-notes-auto-commit.env`としてコピーし、`REAL_HOME`を自分のmacOSアカウントのホームディレクトリに書き換える（`.env`はユーザー固有の情報を含むため`.gitignore`対象で、リポジトリにはcommitされない）。
2. 動作確認として手動実行してみる。

   ```bash
   bash scripts/learning-notes-auto-commit.sh
   ```

### launchd（LaunchAgent）への登録
`~/Library/LaunchAgents/`配下にplist（例: `com.<username>.learningnotes.autocommit.plist`）を作成し、`ProgramArguments`に本スクリプトの絶対パスを指定する。plist自体はリポジトリの外（`~/Library/LaunchAgents/`）に置く。plistの書き方の詳細・実物のサンプルは前述のメモを参照。

```bash
# 登録
launchctl load ~/Library/LaunchAgents/com.<username>.learningnotes.autocommit.plist

# 登録状況の確認
launchctl list | grep learningnotes

# 手動トリガー（スケジュールを待たずに今すぐ実行してテストする）
launchctl start com.<username>.learningnotes.autocommit

# 登録解除（自動実行を止めたい場合）
launchctl unload ~/Library/LaunchAgents/com.<username>.learningnotes.autocommit.plist
```

### ログ
実行時刻・変更有無・成功/失敗は`~/.claude/cron-logs/learning-notes-auto-commit.log`に記録される。

```bash
tail -f ~/.claude/cron-logs/learning-notes-auto-commit.log
```

## 目次

- [2026-07-09: git worktree と checkout の違い](notes/2026-07-09-git-worktree-and-checkout.md)
- [2026-07-10: CLAUDE.mdの役割と活用方法](notes/2026-07-10-claude-md-usage.md)
- [2026-07-11: Claude Desktop（Cowork）とCLIの違い](notes/2026-07-11-claude-desktop-vs-cli.md)
- [2026-07-12: AI生成コードの品質責任とエンジニアとしての調査プロセス](notes/2026-07-12-ai-code-and-investigation-process.md)
- [2026-07-13: VS CodeでのClaude Code（ターミナル版）運用と効率化](notes/2026-07-13-claude-code-cli-and-vscode-integration.md)
- [2026-07-13: GASでスプレッドシートの列幅を確実に確保する方法（autoResizeColumnsの落とし穴）](notes/2026-07-13-gas-sheets-column-width.md)
- [2026-07-14: launchdによるlearning-notesリポジトリの自動commit・push設定](notes/2026-07-14-launchd-auto-commit.md)
- [2026-07-14: clasp v3のコマンド変更と、git worktreeが引き起こす.claspignoreの落とし穴](notes/2026-07-14-clasp-v3-and-claspignore.md)
- [2026-07-14: Slack Bot連携で実際に必要になる認証情報の見分け方（Client ID/App IDとBot Tokenの違い）](notes/2026-07-14-slack-bot-credentials.md)
- [2026-07-16: BigQueryの操作をショートカット化する方法とVS Code移行の検討](notes/2026-07-16-bigquery-shortcuts-and-vscode-workflow.md)
- [2026-07-17: Google スプレッドシートで特定のシートを別ファイルにコピーする方法](notes/2026-07-17-google-sheets-copy-tab-to-another-file.md)
- [2026-07-18: BigQueryでビュー・テーブルを作成し、スケジュールクエリ（トリガー）で定期反映する方法](notes/2026-07-18-bigquery-view-table-and-scheduled-query.md)
- [2026-07-19: Vimの基本操作](notes/2026-07-19-vim-basic-operations.md)
- [2026-07-20: Claude Skillsとは何か：概要と使い方](notes/2026-07-20-claude-skills.md)
- [2026-07-21: アンケートVOC抽出作業とopenpyxlの基礎、業務効率化アプローチの考察](notes/2026-07-21-voc-extraction-and-openpyxl.md)
- [2026-07-21: BigQueryの分析用テーブルに対するテストSQL作成の観点整理](notes/2026-07-21-bigquery-list-table-testing-checklist.md)
