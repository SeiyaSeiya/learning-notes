# Claude Code CLIの未ログインで自動commitが失敗した件（`.git/index.lock`の幽霊ロックとは別原因）

- 学んだきっかけ: [launchdによる自動commit・push](2026-07-14-launchd-auto-commit.md)の`learning-notes-auto-commit.sh`を手動実行したら失敗し、Cowork（Claude Desktop）に原因調査を依頼したセッション。過去の[「幽霊ロック」問題](2026-08-02-git-index-lock-auto-commit-failure.md)・[「自動解消閾値をすり抜けた」件](2026-08-03-git-index-lock-stale-threshold-retry.md)と症状（ターミナルに何も出ず失敗する）が同じだったため最初は同系統のトラブルを疑ったが、実際の原因は全く別だった。

## 概要
`bash scripts/learning-notes-auto-commit.sh`を手動実行したところ2回連続で失敗（終了コード非0、ターミナルには何も表示されない）。ログを確認したところ、`claude -p`（headless呼び出し）が`Not logged in · Please run /login`というエラーで即座に失敗しており、コミット自体が一度も試みられていなかった。Claude Code CLIのログインセッションが何らかの理由で切れており、headlessモード（`-p`）は対話的なログイン処理ができないため、`claude /login`で再ログインするまで自動commitが機能しない状態になっていた。

## 症状
- `bash scripts/learning-notes-auto-commit.sh`を手動実行しても、過去の幽霊ロック事案と同様にターミナルには何も表示されず、コマンドが失敗して戻ってくる。
- `git status`では`README.md`の変更と当日分のノート（未追跡ファイル）が未コミットのまま残っていた。
- launchdの定期実行（6:30・18:30）は当日朝までは正常（`NO CHANGE`）で、日中に変更が発生してから手動実行した分だけが失敗していた。

## 調査の経緯
1. [過去の幽霊ロック事案](2026-08-02-git-index-lock-auto-commit-failure.md)と症状が酷似していたため、まず`.git/index.lock` / `.git/HEAD.lock`の有無を疑った。
2. Coworkのサンドボックス（デバイスブリッジ）経由でリポジトリの状態を確認する過程で、診断のために実行した`git status --porcelain`自体が新規に`.git/index.lock`を作成し、しかもサンドボックス側の制約（ブリッジ経由のマウントでは`unlink`が許可されておらず、git自身が後片付けのロック削除に失敗する）でロックファイルが消せずに残ってしまうという事故が発生した。タイムスタンプを突き合わせて「これは調査由来の副産物であり、今回の本来の失敗原因ではない」と切り分け、`.git/index.lock`を同一ディレクトリ内で`index.lock.bak-cowork`にリネームして退避させた（リネームは同一ファイルシステム内であれば許可された）。
3. 本来の原因を特定するため、`~/.claude/cron-logs/learning-notes-auto-commit.log`を確認する必要があったが、このパスはCoworkに接続していた`learning-notes`フォルダの外だったため、Cowork側からは直接読めなかった。ユーザー側でログの末尾をターミナルから貼り付けてもらう形で確認した。
4. ログの中身は以下の通りで、`claude`コマンド自体が`exit code 1`で失敗しており、原因はロックとは無関係だと判明した。

   ```
   2026-08-10 15:42:15 claude exit code: 1
   2026-08-10 15:42:15 claude output (truncated): Not logged in · Please run /login
   2026-08-10 15:42:15 FAILURE: no new commit was created (HEAD unchanged: 00cf191...)
   ```

## 根本原因
- `learning-notes-auto-commit.sh`は`claude -p ...`（headlessモード）を呼び出してコミットメッセージ生成と`git add` / `git commit`を行わせている。
- headlessモード（`-p`）は非対話的な実行が前提のため、ログインセッションが切れていても対話的な認証フロー（ブラウザでのログイン）を自分で開始することができず、`Not logged in · Please run /login`というエラーメッセージを返して即座に終了するだけになる。
- なぜ今回ログインセッションが切れたのかは特定できなかった（トークンの有効期限切れ、別セッションでのログアウト、CLIのアップデートなど複数の可能性が考えられる）。

## 対処
1. ターミナルで`claude /login`を実行し、ブラウザ経由で再ログイン。
2. `bash scripts/learning-notes-auto-commit.sh`を再実行し、README.mdの変更と新規ノートが正常にcommit・pushされることを確認。
3. 調査中にできてしまった`.git/index.lock.bak-cowork`（実害はないが不要なファイル）を削除。

## 再発防止: スクリプトにターミナルへの警告出力を追加
このスクリプトは元々、`.env`ファイルが見つからない場合を除きエラーをすべて`log()`関数経由でログファイルにしか書き込まない設計になっており（[2026-08-02のメモ](2026-08-02-git-index-lock-auto-commit-failure.md)で触れた通り）、手動実行時に「無言で失敗する」ことが繰り返し調査コストを生んでいた。今回、`claude`コマンドが失敗した場合はターミナル（stderr）にも出力するようにし、特に「未ログイン」のケースは`claude /login`を促す専用メッセージを出すようにした。

```bash
if [ "$claude_exit" -ne 0 ]; then
  echo "" >&2
  echo "⚠️  claude コマンドが失敗しました (exit $claude_exit)" >&2
  if printf '%s' "$claude_output" | grep -qi "not logged in"; then
    echo "⚠️  Claude Code CLI が未ログインです。次を実行して再ログインしてください:" >&2
    echo "    claude /login" >&2
  else
    printf '%s\n' "$claude_output" >&2
  fi
  echo "" >&2
fi
```

launchd経由の定期実行では、plistで`StandardErrorPath`を設定していない限りこの出力の行き先は無く挙動は変わらない（ログファイルへの記録は従来通り）。あくまで手動実行時に気づきやすくするための対策であり、認証切れそのものを防ぐものではない点に注意。

## 学び
- 「ターミナルに何も出ず失敗する」という症状だけで過去の原因（幽霊ロック）を早合点しないこと。同じ症状でも原因は毎回ログを見て確認する必要がある。まず`~/.claude/cron-logs/learning-notes-auto-commit.log`を見る、という初動自体は正しかったが、「今回もロックのはず」という先入観を持たずに中身をきちんと読むべきだった。
- Coworkのデバイスブリッジ（サンドボックス）経由でリポジトリを調査する際、読み取り専用のつもりで実行したコマンド（`git status`など）がインデックスの更新のために書き込みロックを取得し、かつブリッジの制約でそのロックの削除に失敗して実ファイルとして残ってしまうことがある。調査目的で本番のgit管理下フォルダに対してコマンドを実行するときは、自分の操作が副作用（特にロックファイルの残存）を生んでいないかをタイムスタンプ等で確認し、本来の原因と混同しないようにする。
- `-p`（headless）モードのCLIツールは対話的な認証フローを内包できないという制約があるため、認証切れは「エラーで落ちて終わり」になりやすい。cron/launchdのような無人実行を前提にする場合、認証の有効期限がどのくらいか・切れた際にどう気づける仕組みにするかを設計段階で考えておく必要がある（今回は「ログに書くだけ」から「ターミナルにも警告を出す」への改善に留まり、根本的な自動再認証や通知の仕組みまでは入れていない）。
