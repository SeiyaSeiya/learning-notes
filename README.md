# learning-notes

日々の開発・調査の中で学んだことを、知識のアウトプットとして蓄積するための個人リポジトリ。

## 運用方針

- 1トピック1ファイル。`notes/` 配下に `yyyy-mm-dd-トピック名.md` の形式で追加していく。
- 学んだきっかけになった作業・プロジェクト名があれば、メモの中に一言添えておく（後で文脈を思い出しやすくするため）。
- 完璧な文章より、要点が後で見返してわかることを優先する。
- Claude（Claude Code）とのセッションで学んだ内容は、そのセッション終了前にこのリポジトリへメモとして書き出す。別セッションを開いても、このリポジトリのファイルを読めば文脈を引き継げる。

## 自動commit・push（launchd）

このリポジトリの変更は、毎日6:30と18:30の1日2回、macOSの`launchd`経由で自動的にcommit・pushされる。詳しい設計・検証の経緯は [2026-07-14: launchdによるlearning-notesリポジトリの自動commit・push設定](notes/2026-07-14-launchd-auto-commit.md) を参照。

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
- [2026-07-21: BigQueryのスクリプト機能（DECLARE / CREATE TEMP TABLE / IF文）の基礎](notes/2026-07-21-bigquery-script-temp-table.md)
- [2026-07-21: BigQueryのTIMESTAMP→DATETIME変換と、スケジュールクエリの手動即時実行](notes/2026-07-21-bigquery-timestamp-datetime-and-manual-scheduled-query.md)
- [2026-07-23: SQL: SELECT句内のサブクエリ（スカラ・サブクエリと相関サブクエリ）の挙動](notes/2026-07-23-sql-scalar-and-correlated-subqueries.md)
- [2026-07-24: Claudeのアーティファクト（Artifacts）とは何か](notes/2026-07-24-claude-artifacts.md)
- [2026-07-24: GASの既存プロジェクトに手動実行フローを追加する勘所（Sheetsの日付自動変換・関数流用・列順整合）](notes/2026-07-24-gas-add-manual-flow-and-sheets-date-pitfall.md)
- [2026-07-26: GASによるシステム開発で重要な設計概念（疎結合・べき等性・実行時間対策など）](notes/2026-07-26-gas-system-design-concepts.md)
- [2026-07-27: 外部SaaSの仕様変更で自動処理が「静かに」壊れた話（Google Meetの保存先移行とDrive走査の移行対応）](notes/2026-07-27-google-meet-drive-folder-migration-and-silent-failure.md)
- [2026-07-28: 実運用ログからの切り分けと、"安全弁"の閾値を実測で決めるということ（Driveのショートカット権限・外部リソースはIDで解決される）](notes/2026-07-28-drive-shortcut-permissions-and-failsafe-threshold.md)
- [2026-07-29: Googleドライブで「親フォルダより厳しい制限」を子フォルダにかける方法（2025/9/22仕様変更後の正しいやり方）](notes/2026-07-29-google-drive-folder-permission-restriction.md)
- [2026-07-29: BigQueryでビューからテーブルを新規作成しようとして「マテリアライズド ビューのレプリカ作成」画面に迷い込んだ話](notes/2026-07-29-bigquery-create-table-from-view-materialized-replica-pitfall.md)
- [2026-07-30: 過去のcommitを修正する方法（amend / rebase -i / reset+cherry-pick）と、force pushでの反映のさせ方](notes/2026-07-30-git-commit-history-rewrite-amend-rebase-cherrypick.md)
- [2026-08-01: ターミナルの文字列をマウスなしでコピーする方法](notes/2026-08-01-terminal-copy-without-mouse.md)
- [2026-08-02: learning-notesの自動commitが数日間失敗し続けた原因（`.git/index.lock`の幽霊ロック）](notes/2026-08-02-git-index-lock-auto-commit-failure.md)
- [2026-08-03: 登録済みlaunchd plistの編集・再反映手順とハマりどころ](notes/2026-08-03-launchd-plist-edit-and-reload.md)
- [2026-08-03: `.git/index.lock`の自動解消閾値をすり抜けて手動実行が失敗した件](notes/2026-08-03-git-index-lock-stale-threshold-retry.md)
- [2026-08-06: claspでスタンドアロン型のGASプロジェクトを新規作成し、Hello Worldをpushするまで](notes/2026-08-06-clasp-standalone-create-and-push.md)
- [2026-08-08: フォールバック処理とは何か、GAS開発でどう実装するか](notes/2026-08-08-fallback-processing-and-gas.md)
- [2026-08-09: claspで複数のGoogleアカウントを切り替える方法（Chromeプロファイルのような運用を`--user`で実現する）](notes/2026-08-09-clasp-multiple-accounts-user-flag.md)
- [2026-08-10: GASライブラリ×コンテナの2階層構成で「ファイル単位Drive転送」プロトタイプを作って学んだこと](notes/2026-08-10-gas-library-container-file-level-drive-transfer.md)
- [2026-08-10: Claude Code CLIの未ログインで自動commitが失敗した件（`.git/index.lock`の幽霊ロックとは別原因）](notes/2026-08-10-claude-cli-not-logged-in-auto-commit-failure.md)
- [2026-08-11: Claude Codeの「フォーク」機能とは何か：追加時期と使い方](notes/2026-08-11-claude-code-fork-feature.md)
- [2026-08-13: Googleドライブに「Slackのグループ」に相当する機能はあるか：Googleグループ＋共有ドライブでの実現方法](notes/2026-08-13-google-drive-group-sharing-via-shared-drive.md)
- [2026-08-14: 仕事の生産性低下と「未完了タスクの同時保持」問題：マルチタスク仮説とツァイガルニク効果](notes/2026-08-14-productivity-multitasking-zeigarnik-effect.md)
- [2026-08-16: claspの`clasp push`が「Project settings not found」で失敗する原因と、1リポジトリに複数push先を持つ構成について](notes/2026-08-16-clasp-push-project-settings-not-found.md)
- [2026-08-16: SETUP.mdとREADME.mdの違い、そしてSETUP.mdという慣習の位置づけ](notes/2026-08-16-setup-md-vs-readme-convention.md)
- [2026-08-27: GASプロジェクトの外部公開（Webアプリ／API実行可能ファイル／ライブラリ）の仕組みと、claspでのデプロイ操作](notes/2026-08-27-gas-external-publish-webapp-api-library.md)
- [2026-08-28: BPMNとは何か：業務フロー表記法の基礎と実務での使い方](notes/2026-08-28-bpmn-notation-basics.md)
- [2026-08-31: GASでコードから動的にトリガーを作成する際の承認ダイアログと、動的トリガーの一般的な用途](notes/2026-08-31-gas-dynamic-trigger-authorization.md)
- [2026-08-31: SlackのInteractivity機構とNotion API連携によるVOC登録フローの設計メモ（Request URL/Socket Mode、Bot Tokenスコープ、Webアプリ公開のセキュリティと組織単位の制限）](notes/2026-08-31-slack-interactivity-notion-registration-flow.md)
- [2026-09-01: GASで「エディタ上のコード」と「デプロイしたアプリ」が別々になっている理由と、デプロイし忘れの弊害](notes/2026-09-01-gas-editor-code-vs-deployed-app.md)
