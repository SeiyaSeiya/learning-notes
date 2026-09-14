# Projects配下の全リポジトリを自動でgit pullするシェルスクリプトの設計と、bareリポジトリを使った動作確認

- 学んだきっかけ: 9/13、Projects配下に複数cloneしているGitリポジトリの`git pull`を毎回手動で回すのが煩わしいと感じ、それを自動化するシェルスクリプト（`pull-all.sh`）をCoworkに作ってもらった際に、着手前に詰めておくべき設計判断の観点と、実リポジトリを汚さずに動作確認する方法を学んだ。

## 1. 課題: 複数リポジトリの`git pull`を都度手動で回す煩わしさ

- Projectsディレクトリ配下に、cloneしたGitリポジトリを並べて管理している。
- 最新化するには各ディレクトリへ`cd`して`git pull`を実行する必要があり、リポジトリ数が増えるほど手間になる。
- 「Projects配下の全フォルダを対象に、自動でgit pullするシェルスクリプト」というアイディア自体は単純だが、実際に作るとなると事前に決めておくべき分岐がいくつかあることに気づいた。

## 2. 着手前に決めておくべき3つの設計判断

- **対象範囲**: Projects直下（1階層目）だけを対象にするか、再帰的に全階層を探すか
  → 直下のみを既定にした。ほとんどの運用はこれで足りるうえ、将来ネストした構成に変えることになっても再帰オプションを後から足せばよい、というスコープの絞り方。
- **未コミットの変更（作業中のファイル）がある場合の扱い**: スキップして警告／自動でstash／気にせずpullを試行
  → 自動でstash→pull→popを選ぶことにした。ただしstash popでコンフリクトが起きる可能性はゼロにできないので、popが失敗した場合はstashを消さずに残し、警告だけ出す設計にした（自動化と安全性の両立）。
- **自動化のレベル**: 手動実行用のスクリプトのみか、cron/launchdでの定期実行まで含めるか
  → 今回はまず手動実行のスクリプトのみとした。定期実行は後からいつでも追加できるので、最初のスコープを広げすぎない判断。

## 3. 未コミットの変更を安全に扱う: `stash push -u` → `pull --ff-only` → `stash pop`

実際の中核部分（`snippets/pull-all-repos/pull-all.sh`より抜粋・簡略化）:

```bash
if [[ -n "$(git status --porcelain)" ]]; then
  git stash push -u -m "auto-pull-stash $(date '+%Y-%m-%d %H:%M:%S')"
  stashed=true
fi

git pull --ff-only

if [[ "$stashed" == true ]]; then
  git stash pop || echo "警告: stash popでコンフリクト。変更はstashに残っています"
fi
```

ポイント:

- `git pull`に`--ff-only`を付けることで、pull自体がマージコミットを生んで履歴を複雑にする事故を避けている。ローカルとリモートの履歴が分岐していてfast-forwardできない場合は、pull自体を失敗させて人間の判断に委ねる。
- stash pop失敗時に、popを再試行したりrebaseで解消を試みたりせず、「stashに残したまま警告するだけ」に留めているのは、自動化スクリプトが中途半端にコンフリクト解消を試みて状態をさらに壊すリスクを避けるため。`git stash list`で後から人間が確認すればよい、という割り切り。

## 4. pullできない・すべきでないケースを事前に列挙してスキップする

以下を事前にチェックし、該当する場合はエラーで止めずにスキップして次のリポジトリへ進む設計にした。

- `.git`が無いフォルダ（そもそもGitリポジトリではない）
- detached HEAD状態（`git symbolic-ref --short HEAD`が空になる）
- リモート追跡ブランチが設定されていないリポジトリ（`git rev-parse --abbrev-ref '@{u}'`が失敗する）

複数リポジトリを1回のスクリプト実行でまとめて処理しきりたい場合、1つのリポジトリの特殊事情で全体が止まらないようにする設計が重要になる。

## 5. 動作確認の手法: 使い捨てのbareリポジトリでテスト環境を再現する

実際のProjectsディレクトリやリポジトリを試験台にすると、テスト中の失敗で本当の作業内容を壊すリスクがある。そこで`/tmp`配下に、使い捨ての検証環境を作ってもらった。

```bash
git init --bare remote_a.git                 # 疑似リモート
git clone remote_a.git Projects/repo-clean   # 手元のcloneに相当

# 別のcloneから追加コミット・pushして「リモートが進んでいる」状態を再現する
git clone remote_a.git other_clone
(cd other_clone && echo update >> f.txt && git commit -am update && git push)
```

この方法で、以下の4パターンを実リポジトリに触れずに再現・確認できた。

- クリーンな状態でのpull（fast-forward更新）
- 未コミット変更がある状態でのstash→pull→pop
- リモート追跡ブランチが無いリポジトリのスキップ
- `.git`が無い（Gitリポジトリではない）フォルダのスキップ

「実データに近いが、壊れても問題ない使い捨ての再現環境を用意してから試す」というのは、シェルスクリプトに限らずファイル操作系の自動化を検証する際に汎用的に使える手法だと感じた。

## 6. launchdでの定期実行設定（`StartInterval`とdevice_bashの限界）

手動実行だけでは結局「思い出したときにしか回さない」ことに気づき、後から`launchd`での定期実行を追加した。

### 「N時間ごと」には`StartCalendarInterval`ではなく`StartInterval`が向く

`learning-notes`の自動commit（1日2回、決まった時刻）は`StartCalendarInterval`で組んでいたが、
今回のように「3時間ごと」という一定間隔の実行には、経過秒数で指定する`StartInterval`（整数・秒）の方が
素直に表現できる。`StartCalendarInterval`で同じことをやろうとすると、`Hour`違いの`dict`を8個並べる必要があり冗長になる。

```xml
<key>StartInterval</key>
<integer>10800</integer>  <!-- 3時間 = 10800秒 -->
```

### `ProgramArguments`に対象ディレクトリを明示的に渡す

`pull-all.sh`は引数が無ければ`$HOME/Projects`をデフォルトの対象にする作りだが、launchdは`$HOME`を
含め環境変数がほぼ空の状態でプロセスを起動する。`$HOME`に依存させず、`ProgramArguments`の第2要素として
対象ディレクトリの絶対パスを明示的に渡すようにした。

```xml
<key>ProgramArguments</key>
<array>
    <string>/bin/bash</string>
    <string>/Users/<username>/Projects/learning-notes/snippets/pull-all-repos/pull-all.sh</string>
    <string>/Users/<username>/Projects</string>
</array>
```

### device_bashでは`launchctl`・`plutil`が使えず、`~/Library`にも書き込めない

plistの中身をCoworkに作らせて、そのまま登録まで自動化できないかを試したところ、2つの壁にぶつかった。

1. `device_bash`は「ユーザーの端末上で動くが、隔離されたLinux VM内のシェル」であり、`launchctl`・`plutil`
   のようなmacOS固有のコマンドはそもそも存在しない（`command not found`になる）。
2. plist本体の置き場所である`~/Library/LaunchAgents/`は、Coworkの「フォルダアクセス許可」の対象外の
   保護された場所として扱われ、そもそも書き込み権限をリクエストすることすらできなかった
   （`device_request_folder_access`が"protected system or credential location"として拒否する）。

そのため、plistの中身の作成・XML構文の検証（`plutil -lint`の代わりに、Linux VM内でも動く
Pythonの`plistlib`で読み込めるかを確認した）まではCowork側で行い、実際のファイル設置と
`launchctl load`等の実行はユーザー自身がmacOSの実Terminalで行う、という役割分担になった。

```bash
# <username>を実際のアカウント名に置き換えつつ配置する
# （ひな形は snippets/pull-all-repos/com.username.projects.pullall.plist.example。
#  <・>はXMLの特殊文字なので、ひな形ファイル単体では正しいXMLになっていない点に注意）
sed 's/<username>/実際のアカウント名/g' \
    snippets/pull-all-repos/com.username.projects.pullall.plist.example \
  > ~/Library/LaunchAgents/com.実際のアカウント名.projects.pullall.plist

launchctl load ~/Library/LaunchAgents/com.実際のアカウント名.projects.pullall.plist
launchctl start com.実際のアカウント名.projects.pullall   # 動作確認のための即時トリガー
```

「AIエージェントがユーザーのローカル環境に対してどこまで自動化できるか」には、こうした
サンドボックスの実行環境（Linux VM上での実行）とOS保護領域という、2種類の別々の境界があることを
具体的なエラーを通じて把握できた。

## まとめ

- 複数リポジトリを横断する自動化スクリプトを作る際は、着手前に「対象範囲」「イレギュラーな状態（未コミット変更など）の扱い」「自動化のレベル」の3点を決めておくと、スコープが暴走しない。
- 自動化と安全性を両立させるコツは、「失敗しても人間が後から復旧できる状態を残す」設計（stashで退避したまま残す、`--ff-only`でpullを自動でマージさせない、等）。
- 実環境を壊さずに検証したい場合は、bareリポジトリ＋cloneで使い捨てのテスト環境を`/tmp`などに作るのが有効。
- 「N時間ごと」の定期実行には`launchd`の`StartInterval`が向いている。またAIエージェント経由の自動化には「サンドボックスの実行環境（Linux VMかmacOSか）」と「OSの保護領域か否か」という2種類の境界があり、両方に触れる作業は最終的に人間がTerminalで実行する必要がある。
- 作成したスクリプト本体は[snippets/pull-all-repos/pull-all.sh](../snippets/pull-all-repos/pull-all.sh)に保存した。
