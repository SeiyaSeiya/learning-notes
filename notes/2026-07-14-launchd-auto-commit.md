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
* **本体スクリプト**: `learning-notes/scripts/learning-notes-auto-commit.sh`（当初は`~/.claude/scripts/`に置いていたが、後述の理由でリポジトリ内に移動した）
  * launchd経由でも手動(`bash scripts/learning-notes-auto-commit.sh`)でも同じ結果になるように、スクリプト内で`git`・`claude`コマンドの絶対パス指定、`PATH`の明示的なexport、リポジトリへの`cd`を行う。
  * ホームディレクトリのパスなど**マシン・ユーザー固有の値はスクリプトに直書きせず、`.env`ファイルから読み込む**（詳細は後述）。
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

## 動作確認の結果
実装後、以下の3パターンで検証した。

1. **手動実行（変更あり）**: README.mdの目次更新と新規メモファイルを変更として検知 → Claudeが日本語コミットメッセージを生成してcommit → `git push origin main`成功。
2. **手動実行（変更なし）**: `git status --porcelain`が空 → `NO CHANGE`のログのみで終了し、空commitは作られない（冪等性の確認）。
3. **launchd経由**: `launchctl load`で登録 → `launchctl list`で登録状態（Label, LastExitStatus）を確認 → `launchctl start <Label>`で手動トリガーし、ログとexit statusが手動実行時と同じ結果になることを確認。

いずれも同じログファイル（`~/.claude/cron-logs/learning-notes-auto-commit.log`）に実行時刻・変更有無・成否が記録され、手動実行とlaunchd実行で挙動の差分がないことを確認できた。

## LaunchAgentとplistの理解
* **LaunchAgent**: `launchd`にジョブを登録する仕組みの一種。`~/Library/LaunchAgents/`（ユーザー単位）に置くとログイン中のユーザー権限で動く。`/Library/LaunchDaemons/`に置く**LaunchDaemon**はroot権限・ログイン不要で動く常駐処理向けで、SSHエージェントなどユーザー固有の環境が必要な処理（今回のgit push等）には向かない。
* **plist（property list）**: Appleの設定ファイル形式。XMLで「キーと値」を階層的に記述する（`.ini`や`.json`に近い役割）。`Label`（識別子）、`ProgramArguments`（実行コマンド）、`StartCalendarInterval`（実行時刻）などをここに書く。plistは設定データであってプログラムではないため、スクリプトの配置場所を変更した場合は`ProgramArguments`内のパスも書き換えて`launchctl unload` → `load`で再登録し直す必要がある。
* 管理コマンドの基本: 登録は`launchctl load`、解除は`launchctl unload`、登録状況は`launchctl list`、手動トリガーは`launchctl start <Label>`。

## plistの書き方（構文詳細）
plistはXMLベースの設定ファイルで、以下の型のみを組み合わせて「キーと値」を階層的に表現する。

| 型 | 記法 | 用途の例 |
|---|---|---|
| 文字列 | `<string>...</string>` | パス、識別子など |
| 整数 | `<integer>...</integer>` | 時刻（Hour/Minute）など |
| 真偽値 | `<true/>` / `<false/>` | フラグ系のON/OFF |
| 配列 | `<array>...</array>` | コマンドの引数リストなど、順序が意味を持つもの |
| 辞書 | `<dict>...</dict>` | ネストした設定のまとまり |

基本の骨格は決まっており、ルート要素は必ず`<plist>`、その直下に1つの`<dict>`を置く。

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- ここにキーと値のペアを並べる -->
</dict>
</plist>
```

`<dict>`の中身は「`<key>キー名</key>`の次の要素がその値」という並び方をする。JSONの`{"キー名": 値}`と違い、キーと値がペアの入れ子ではなく**同じ階層に交互に並ぶ**点がややクセがある書き方。

今回`launchd`用に実際に使ったキーは以下。

| キー | 型 | 意味 |
|---|---|---|
| `Label` | string | ジョブの一意な識別子。`launchctl list`等で参照する名前 |
| `ProgramArguments` | array | 実行するコマンドと引数（`argv`そのもの）。第1要素が実行ファイル |
| `StartCalendarInterval` | dict | 実行時刻。`Hour`/`Minute`キー（他に`Day`/`Weekday`/`Month`も指定可） |
| `EnvironmentVariables` | dict | 起動時に渡す環境変数。launchdはデフォルトでほぼ空のPATH/HOMEしか渡さないため明示が必要だった |
| `WorkingDirectory` | string | 実行時のカレントディレクトリ |
| `StandardOutPath` / `StandardErrorPath` | string | 標準出力・標準エラー出力の書き出し先ファイル |
| `RunAtLoad` | bool | `launchctl load`した瞬間に1回即実行するか。今回は`false`（スケジュール通りの時刻のみ実行したいため） |

今回作成した実物の全文（`~/Library/LaunchAgents/com.<username>.learningnotes.autocommit.plist`、リポジトリ外に配置。`<username>`は自分のmacOSアカウント名）:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.<username>.learningnotes.autocommit</string>

    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/<username>/Projects/learning-notes/scripts/learning-notes-auto-commit.sh</string>
    </array>

    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>6</integer>
        <key>Minute</key>
        <integer>30</integer>
    </dict>

    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key>
        <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    </dict>

    <key>WorkingDirectory</key>
    <string>/Users/<username>/Projects/learning-notes</string>

    <key>StandardOutPath</key>
    <string>/Users/<username>/.claude/cron-logs/learning-notes-auto-commit.stdout.log</string>
    <key>StandardErrorPath</key>
    <string>/Users/<username>/.claude/cron-logs/learning-notes-auto-commit.stderr.log</string>

    <key>RunAtLoad</key>
    <false/>
</dict>
</plist>
```

（plist自体はリポジトリの外に置くファイルなので、実際にはここに自分の本名アカウント名を書いて構わない。上の例では、このメモ自体がリポジトリにcommitされ公開されるため、伏せ字にしてある。）

### 確認・編集に使えるコマンド
* `plutil -lint <パス>`: XMLとして正しい構文かを検証する。編集後は必ずこれで確認してからlaunchdに読ませる。
* `plutil -p <パス>`: 人間が読みやすい形（JSON風のツリー）で内容を表示する。
* `plutil -convert xml1 <パス>` / `plutil -convert binary1 <パス>`: XML形式とバイナリ形式を相互変換する（バイナリ化されたplistもXMLに戻して読める）。
* 手で編集する場合は`Edit`ツールやテキストエディタで直接XMLを書き換えて問題ない（Xcodeの専用GUIエディタもあるが必須ではない）。

## 個人情報の秘匿: `.env`ファイルとgit履歴への対応
設定作業を進める中で、スクリプト内の`REPO_DIR`や`HOME`にmacOSの実アカウント名を直書きしてしまい、そのままPublicリポジトリにcommit・pushしてしまうという問題が発生した。この対応を通じて学んだことをまとめる。

### 何が起きたか
* スクリプト内に`REPO_DIR="/Users/<実際のアカウント名>/Projects/learning-notes"`のように、ユーザー固有の値を直接書いてしまっていた。
* このスクリプトをそのままcommit・pushしてしまい、Publicリポジトリの履歴に実名（macOSアカウント名）が残ってしまった。

### `git revert`では公開履歴からは消えない
`git revert`は「打ち消すコミットを新たに追加する」操作であり、**対象のコミット自体は履歴に残り続ける**。GitHub上で該当コミットのURLに直接アクセスしたり`git log -p`を辿れば、revert後でも内容を見られてしまう。公開してしまった情報を履歴から完全に消すには、revertではなく履歴の書き換えが必要という点を再認識した。

### コミットハッシュが変わる範囲
コミットのハッシュは「そのコミットの内容 + 親コミットのハッシュ」から計算される。そのため内容を書き換えると、**そのコミット自身と、それ以降の子孫コミットのハッシュだけ**が変わる。対象コミットより前の祖先コミットは内容も親も変化しないため、ハッシュは変わらない。

今回は問題のコミットがちょうど`main`の最新（先端）だったため、`git filter-repo`のような大掛かりな履歴書き換えツールは不要で、以下のシンプルな手順で対応できた。

```bash
git reset --soft HEAD~1        # 問題のコミットだけを取り消す（変更はステージ済みのまま残る）
# ここでファイルを修正
git commit -m "..."            # 修正済みの内容で改めてcommit
git push --force origin main   # リモートの先端を上書き
```

`git filter-repo`（`git filter-branch`の後継）は、対象コミットの後に何十ものコミットが積み重なっている場合や、ファイル単位で過去の全履歴から消したい場合に使う、より大掛かりな道具。今回のように「最新コミットの次に何もコミットが無い」状態であれば不要だった。

### 再発防止: `.env`（魂）と`.env.example`（器）の分離
同じ問題を繰り返さないよう、マシン・ユーザーによって値が変わる情報（今回で言えばホームディレクトリのパス）はスクリプト本体に書かず、別ファイルに分離した。

* **`scripts/learning-notes-auto-commit.env`**: 実際の値を書く。`.gitignore`対象でリポジトリにはcommitされない。
* **`scripts/learning-notes-auto-commit.env.example`**: プレースホルダーのみのテンプレート。こちらはcommitする。

`.env.example`が「型（器）」、`.env`が「その型に注ぎ込む実際の値（魂）」という関係。`.env.example`があることで、半年後や別マシンで環境を再構築する際に、スクリプトのソースコードを読み解かなくても、必要な変数名・書式がすぐに分かる。

スクリプト側は起動時に`.env`を`source`し、必要な変数（`REAL_HOME`）が空ならエラーで即終了するようにした。これにより「秘匿すべき情報がスクリプト本体に紛れ込む」という経路自体を構造的に塞いだ。

## スクリプト配置場所の検討と移行
当初スクリプトはリポジトリの外（`~/.claude/scripts/`）に置いていたが、以下を踏まえて`learning-notes/scripts/`配下に移動した。

* **配置場所への技術的な依存はない**: スクリプト内は全て絶対パスで完結しているため、スクリプト自体の置き場所には依存しない。依存するのはplist側（`ProgramArguments`にスクリプトの絶対パスをハードコードしているため、移動時はplistの更新とlaunchdへの再登録が必要）。
* **一般的な配置慣行としては2つの考え方がある**
  * 対象リポジトリの外（`~/bin/`, `~/dotfiles/scripts/`等）に置く: マシンの自動化・cronジョブを個人のdotfiles的な場所にまとめる考え方。特に今回はスクリプト自身が対象リポジトリをauto-commit/pushするため、リポジトリ内に置くと「スクリプトの変更差分も次回実行時に自動commitされる」という自己言及的な構造になる点に留意が必要。
  * 対象リポジトリの中（`scripts/`等）に置く: リポジトリを他マシンへ持ち運ぶ際にスクリプトごとgit cloneで復元できる利点がある。
* 今回は「リポジトリと一緒に持ち運びたい」という意図から、リポジトリ内(`scripts/`配下)への配置を選んだ。移動後、plistの`ProgramArguments`を新パスに書き換え、`unload` → `load`で再登録し、手動実行・launchd実行の両方で改めてcommit・push成功を確認した。
