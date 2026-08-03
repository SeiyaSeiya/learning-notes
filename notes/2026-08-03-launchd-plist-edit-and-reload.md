# 登録済みlaunchd plistの編集・再反映手順とハマりどころ

- 学んだきっかけ: [2026-07-14: launchdによるlearning-notesリポジトリの自動commit・push設定](2026-07-14-launchd-auto-commit.md)で組んだ自動commit・pushを、1日1回（6:30）から1日2回（6:30・18:30）に変更する作業。既にload済みのplistを編集・反映する手順が曖昧だったため、Coworkに解説してもらいながら実際に手を動かして確認した。

## 前提: なぜ「編集するだけ」では反映されないか
`launchd`は`launchctl load`を実行した時点でplistの内容をメモリに読み込む。ファイルを書き換えただけでは、既にloadされているジョブの定義は更新されない。そのため必ず「編集 → 検証 → 一度unload → 再度load」という順序を踏む必要がある。

## 手順
1. **対象ファイルとlabelを確認する**
   ```bash
   ls ~/Library/LaunchAgents/ | grep learningnotes
   launchctl list | grep learningnotes
   ```
   `launchctl list`の出力の一番右の列が正確なlabel名（例: `com.<username>.learningnotes.autocommit`）。以降のコマンドではこの値をそのまま使う（`<username>`のようなプレースホルダーのまま実行しないよう注意。後述のハマりどころ参照）。

2. **先にunloadする**
   ```bash
   launchctl unload ~/Library/LaunchAgents/com.<username>.learningnotes.autocommit.plist
   ```
   動いている定義を書き換えている最中に中途半端な状態でトリガーされる事故を防ぐため、編集前に外しておく。

3. **plistを編集する**
   ```bash
   open -e ~/Library/LaunchAgents/com.<username>.learningnotes.autocommit.plist
   ```
   `StartCalendarInterval`を複数時刻にする場合、単一の`<dict>`ではなく`<dict>`を`<array>`で囲んで並べる。

   ```xml
   <key>StartCalendarInterval</key>
   <array>
       <dict>
           <key>Hour</key>
           <integer>6</integer>
           <key>Minute</key>
           <integer>30</integer>
       </dict>
       <dict>
           <key>Hour</key>
           <integer>18</integer>
           <key>Minute</key>
           <integer>30</integer>
       </dict>
   </array>
   ```

4. **構文チェック**
   ```bash
   plutil -lint ~/Library/LaunchAgents/com.<username>.learningnotes.autocommit.plist
   ```
   `OK`が出ることを確認してから次に進む。

5. **再度loadする**
   ```bash
   launchctl load ~/Library/LaunchAgents/com.<username>.learningnotes.autocommit.plist
   echo "exit code: $?"
   ```

6. **反映内容を確認する**（詳細は次項）

## 反映確認でのハマりどころ

### 1. `plutil -p`と`launchctl print`は見ている対象が違う
- `plutil -p ~/Library/LaunchAgents/....plist`: **ファイル自体**の中身をそのまま表示する。launchdにloadされているかどうかとは無関係。「編集・保存は正しくできているか」を切り分けたいときはまずこちらを見るのが早い。
- `launchctl print gui/$(id -u)/<label>`: **launchdが現在loadしている実行時の状態**を表示する。編集後に`load`し忘れていたり、labelが間違っていると、こちらは正しい情報を返さない。

編集が反映されているかを疑ったときは、この2つを分けて確認すると原因の切り分けが早い（ファイル側の問題か、load状態側の問題か）。

### 2. labelのプレースホルダーをそのまま実行してしまう
手順書などに`com.<username>.learningnotes.autocommit`のような書き方をしていると、コピペ時に`<username>`を実際のmacOSアカウント名に置き換え忘れることがある。置き換え忘れると`launchctl print`は対象のジョブを見つけられず、エラーも含めて何も出力されない（ように見える）ことがあった。`launchctl list | grep <キーワード>`で事前に正確なlabelを確認し、それをそのまま使うのが確実。

### 3. `grep "calendar interval"`では引っかからないことがある
使用したmacOSのバージョンでは、`launchctl print`の出力において複数時刻（`StartCalendarInterval`を配列にした場合）の設定は、想定していた`calendar interval = { Hour = 6; Minute = 30 }`のような単純な形ではなく、以下のような`monitor` / `descriptor`という構造の中に時刻情報がネストされる形で表示された。

```
                        monitor = com.apple.UserEventAgent-Aqua
                        descriptor = {
                                "Minute" => 30
                                "Hour" => 18
                        }
                }
--
                        monitor = com.apple.UserEventAgent-Aqua
                        descriptor = {
                                "Minute" => 30
                                "Hour" => 6
                        }
                }
```

そのため`grep "calendar interval"`では何も引っかからなかった。`launchctl print`の出力フォーマットはmacOSのバージョンによって変わりうるので、特定の文言に依存したgrepではなく、まず**grepなしで全文を出力して目視する**か、`Hour`/`Minute`のような値そのものを大文字小文字問わず検索する方が確実。

```bash
launchctl print gui/$(id -u)/<label> | grep -B 2 -A 2 -i "hour\|minute"
```

## 学び
- launchdのジョブは「ファイル」と「loadされた実行時の状態」が別物であり、確認作業ではまずどちらを見ているかを意識する必要がある。
- ドキュメント上のプレースホルダー（`<username>`等）は、コピペ実行時の実際の値との置き換え忘れが起きやすい典型的なハマりポイント。手順書には「事前に`launchctl list`等で実際の値を確認してから使う」という一手間を明記しておくとよい。
- OSコマンドの出力フォーマットはバージョンによって変わりうるため、特定のキーワードでの`grep`に頼りすぎず、まず生の全文を確認する習慣が原因切り分けを早くする。
