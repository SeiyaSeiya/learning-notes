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

## 定期実行にしたい場合

現時点では手動実行用のスクリプトとしてのみ運用している。定期的に自動実行したくなった場合は、
`crontab -e`やmacOSの`launchd`から本スクリプトを呼び出す設定を追加すればよい
（`learning-notes`リポジトリ自身の自動commit・push設定を参考にできる。
[scripts/learning-notes-auto-commit.sh](../../scripts/learning-notes-auto-commit.sh)と
[README.mdの該当セクション](../../README.md#自動commitpushlaunchd)を参照）。
