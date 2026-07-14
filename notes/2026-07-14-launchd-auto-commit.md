# launchdによるlearning-notesリポジトリの自動commit・push設定

## 概要
毎回「変更をcommit・pushして」とClaude Codeに手動で依頼するのが煩雑だったため、macOSの`launchd`を使って毎日6:30に自動でcommit・pushする仕組みを構築した。`cron`ではなく`launchd`を選んだ理由と、実装時に気をつけたポイントをまとめる。

## なぜcronではなくlaunchdか
* `cron`はMacがスリープ中だった時刻の実行を単純にスキップする。
* `launchd`は`StartCalendarInterval`で時刻指定した場合、指定時刻にスリープしていても**スリープ復帰時に自動でキャッチアップ実行**してくれる。
  * 電源が完全にオフだった日はキャッチアップされず、その日は実行されない（それで問題ない想定）。
* 常時起動しているノートPCでの「毎日決まった時刻に実行したいが、寝ている間は動かしていない」というユースケースに`launchd`の方が合っている。

## 構成
* **LaunchAgent plist**: `~/Library/LaunchAgents/`に配置し、`launchctl load`で登録。処理内容は書かず、シェルスクリプトの呼び出しのみを記述。
* **本体スクリプト**: `~/.claude/scripts/learning-notes-auto-commit.sh`
  * launchd経由でも手動(`bash ~/.claude/scripts/learning-notes-auto-commit.sh`)でも同じ結果になるように、スクリプト内で`git`・`claude`コマンドの絶対パス指定、`PATH`/`HOME`の明示的なexport、リポジトリへの`cd`を行う。
  * launchdはシェルのプロファイル（`.zshrc`など）を経由しないため、`PATH`がほぼ空の状態で起動する点に注意が必要だった。
* **ログ**: `~/.claude/cron-logs/learning-notes-auto-commit.log`に実行時刻・成功/失敗・commitの有無を記録。

## 処理フロー
1. `git status --porcelain`で未コミットの変更（追跡ファイル・未追跡ファイル問わず）の有無を確認。変更がなければ何もせず終了（空commitを作らない）。
2. 変更があれば、Claude Code CLIをheadlessモード（`claude -p`）で呼び出し、コミットメッセージ生成と`git add` / `git commit`のみを行わせる。
3. `git commit`の前後でHEADのコミットハッシュを比較し、実際にcommitが作成されたかをスクリプト側で機械的に確認する（Claudeの出力テキストを信用しすぎない）。
4. pushはClaudeにやらせず、スクリプト自身が固定コマンド`git push origin main`のみを実行する。

## 安全のための設計判断
* **pushはLLMにやらせない**: Claudeの`--allowedTools`で`git push`系を許可しても、引数に`--force`が混入する余地は原理上ゼロにできない。そのためpushだけはスクリプト側の固定コマンドとして実装し、force pushが物理的に発生しない構造にした。
* **mainブランチ以外では何もしない**: スクリプト冒頭でカレントブランチが`main`であることを確認し、それ以外なら即終了する。
* **非対話実行**: `--permission-mode default`と`--allowedTools`の組み合わせで、想定した`git`系コマンドのみを許可。確認プロンプトで止まらないようにした。
* **失敗時に作業ツリーを壊さない**: commitが作成されていない場合はpushをスキップし、その時点の`git status`をログに残すだけにとどめる。

## 学び
* `launchd`の`StartCalendarInterval`はcronの上位互換的に使えるが、環境変数がほぼ空の状態で起動するため、シェルスクリプト側で環境を自己完結させる設計が必須になる。
* LLMに「絶対にやってほしくない操作」がある場合、プロンプトで禁止を指示するだけでなく、そもそもその操作を実行できる権限自体を与えない（今回で言えば`git push`をスクリプト側の固定コマンドに追い出す）方が構造的に安全。
