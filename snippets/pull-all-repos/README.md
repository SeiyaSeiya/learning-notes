# Projects配下の全リポジトリを自動git pullするスクリプト

`Projects`ディレクトリ（などリポジトリをまとめて置いている場所）直下にある各Gitリポジトリに対して、
`git pull`をまとめて実行するためのスクリプト。プロジェクト固有の情報は含まれていないので、
リポジトリを複数cloneして管理している環境ならそのまま使い回せる。

## 背景

2026年9月、Projects配下の各リポジトリで`git pull`を都度手動で実行するのが煩わしいと感じ、
それを解消するために作成した。設計判断の経緯（対象範囲・未コミット変更の扱い・自動化レベルを
どう決めたか）や、bareリポジトリを使った動作確認の方法については
[../../notes/2026-09-13-git-pull-all-script-and-bare-repo-testing.md](../../notes/2026-09-13-git-pull-all-script-and-bare-repo-testing.md)
を参照。

## 使い方

```bash
chmod +x pull-all.sh

./pull-all.sh                  # ~/Projects を対象に実行
./pull-all.sh /path/to/dir     # 対象ディレクトリを指定して実行
```

## 動作

- Projects直下（1階層目）のフォルダだけを対象にする（サブフォルダの中までは探索しない）。
- `.git`が無いフォルダは黙ってスキップする。
- リモート追跡ブランチが設定されていないリポジトリ、detached HEAD状態のリポジトリはスキップして警告する。
- 未コミットの変更がある場合は、`git stash push -u` → `git pull --ff-only` → `git stash pop`の順で
  自動的に退避・復元する。
- `stash pop`でコンフリクトが起きた場合は、変更を消さずにstashへ残したまま警告表示のみ行う
  （`git stash list`で後から手動確認・復元できる）。
- pullは`--ff-only`で行うため、ローカルとリモートの履歴が分岐していてfast-forwardできない場合は
  自動でマージなどはせず、そのリポジトリだけ失敗として扱う（他のリポジトリの処理は継続する）。
- 最後に「更新完了／stashコンフリクト／追跡ブランチ無しでスキップ／失敗／非Gitフォルダ」を
  色分けしたサマリーで一覧表示する。

## 定期実行（launchd）

3時間おきなど、一定間隔でこのスクリプトを自動実行したい場合は、`launchd`のLaunchAgentとして登録する。
`learning-notes`リポジトリ自身の自動commit・push設定（[scripts/learning-notes-auto-commit.sh](../../scripts/learning-notes-auto-commit.sh)、
[README.mdの該当セクション](../../README.md#自動commitpushlaunchd)）と同じ仕組み。

### plistのひな形

[`com.username.projects.pullall.plist.example`](com.username.projects.pullall.plist.example)をひな形として同梱している。
このファイル自体はリポジトリの外（`~/Library/LaunchAgents/`）に置くファイルなので、コピーしてから
`<username>`を自分のmacOSアカウント名に置き換えて使う。

```bash
# <username> の部分を実際のmacOSアカウント名に置き換えつつコピーする（1コマンドで完結させる）
sed 's/<username>/実際のアカウント名/g' \
    snippets/pull-all-repos/com.username.projects.pullall.plist.example \
  > ~/Library/LaunchAgents/com.実際のアカウント名.projects.pullall.plist
```

（`<`・`>`はXMLの構文上の特殊文字なので、ひな形ファイル自体は単体では正しいXMLになっていない。
必ずsedで置換した後のファイルを使うこと。）

主なキーの意味:

- `ProgramArguments`: `bash pull-all.sh <対象ディレクトリ>`を実行する。対象ディレクトリは明示的に渡し、
  launchdの環境変数がほぼ空でも`$HOME`に依存しないようにしている。
- `StartInterval`: 起動からの経過秒数で定期実行する（`10800`=3時間）。特定時刻ではなく「一定間隔」を
  表現したい場合は`StartCalendarInterval`より`StartInterval`が適している。
- `EnvironmentVariables.PATH`: launchdはシェルの`.zshrc`等を経由せず、PATHがほぼ空の状態で起動するため
  明示的に設定する（gitコマンドを解決できるようにするため）。
- `StandardOutPath` / `StandardErrorPath`: 実行結果は`~/.claude/cron-logs/pull-all-repos.std{out,err}.log`
  に出力される。

### 登録・確認・解除

```bash
# 登録（初回、またはplist内容を変更した場合は unload → load し直す）
launchctl load ~/Library/LaunchAgents/com.実際のアカウント名.projects.pullall.plist

# 登録状況の確認（Label, LastExitStatusなど）
launchctl list | grep projects.pullall

# スケジュールを待たずに今すぐ手動トリガーして動作確認
launchctl start com.実際のアカウント名.projects.pullall

# ログを確認
tail -f ~/.claude/cron-logs/pull-all-repos.stdout.log

# 登録解除（自動実行を止めたい場合）
launchctl unload ~/Library/LaunchAgents/com.実際のアカウント名.projects.pullall.plist
```

これらの`launchctl`コマンドは実際のmacOS上のTerminalで実行する必要がある（Coworkの`device_bash`は
ユーザーの端末上で動くが、`launchctl`・`plutil`を持たないサンドボックス内シェルで実行されるため、
またLaunchAgentsディレクトリ自体も保護された場所でありCowork側から直接書き込めないため）。
