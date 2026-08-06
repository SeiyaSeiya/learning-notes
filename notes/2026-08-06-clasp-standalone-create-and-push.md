# claspでスタンドアロン型のGASプロジェクトを新規作成し、Hello Worldをpushするまで

- 学んだきっかけ: これまでGASはコンテナバインド型（Sheets/Docs/Formsなどに紐づくもの）しか使ってこなかったため、`clasp`をターミナルから使って単独のGASプロジェクト（standalone）を新規作成し、Hello Worldの動作確認までを実際に手を動かして確認した。Claude（Cowork）に手順を教わりながら進めた。

## 1. 前提となるclaspの基本コマンド

- `npm install -g @google/clasp` — Node.js 20系以降が必要。
- `clasp login` — Googleアカウントで認証。事前にGoogleアカウント設定で「Apps Script API」を有効化しておく必要がある（`script.google.com/home/usersettings`）。忘れると`create`や`push`でAPIエラーになる。
- `clasp create` — 新規プロジェクト作成。オプションで種類を指定する。

## 2. スタンドアロン型はコンテナバインド型と何が違うか

- コンテナバインド型は`clasp create --type sheets --parentId <ファイルID>`のように、既存のGoogleファイルにスクリプトを紐づける。
- スタンドアロン型は`--parentId`を指定せず、`--type standalone`のみで作成する。どのファイルにも属さない単独のスクリプトになる。
- 大きな違いは「実行のきっかけ」。コンテナバインド型はシートのメニューやセルの変更などをトリガーにできるが、スタンドアロン型はそうした自然な起動点がないので、エディタからの手動実行か、時間主導トリガー・Web公開・API実行のいずれかで動かす必要がある。

## 3. 実際に手を動かした手順

```bash
mkdir hello-clasp-standalone
cd hello-clasp-standalone
clasp create --title "Hello World Standalone" --type standalone
```

- 実行後に`Created new standalone script: https://script.google.com/d/xxxxxxxxxx/edit`という形でURLが返り、そのままエディタへのリンクになっている。
- 生成される2ファイル:
  - `.clasp.json` — scriptIdなどの設定（コンテナバインド型と違い、紐づくファイルのIDは持たない）。
  - `appsscript.json` — マニフェスト。デフォルトの`timeZone`が`America/New_York`になっていたので、`"Asia/Tokyo"`に書き換えておいた（日付関連の動作確認をしやすくするため）。

## 4. Hello Worldコードを書いてpush

`Code.js`に以下を記述:

```js
function helloWorld() {
  Logger.log('Hello, World!');
  console.log('Hello, World!');
  return 'Hello, World!';
}
```

```bash
clasp push
```

確認プロンプトが出た場合は`y`で進める（`clasp push -f`で確認をスキップ可能、`-w`でファイル変更を監視して自動push）。

## 5. 実行して動作確認する2つの方法、そしてclasp v3の罠

- **方法A（今回はこちら）**: `clasp open`でエディタをブラウザで開き、関数選択で`helloWorld`を選んで実行ボタンを押す。初回実行時は権限承認ダイアログが出るので許可する。実行ログに`Hello, World!`が出れば成功。
- **方法B**: `clasp run helloWorld`でターミナルから直接実行。ただしAPI実行可能プロジェクトとしての追加設定（GCPプロジェクト紐付け、`appsscript.json`の`executionApi`設定など）が必要なので、今回はスキップした。
- 【注意・以前の学びとの接続】以前の[clasp v3のコマンド変更メモ](2026-07-14-clasp-v3-and-claspignore.md)で確認した通り、インストール済みのclaspがv3系だと`clasp open`は廃止されていて`clasp open-script`が後継になっている。手元のclaspのバージョンによっては`clasp open`が`Unknown command`になるので、そのときは`clasp open-script`を使う。`clasp --help`で確認するのが確実。
- ログをターミナルから見たい場合は`clasp logs`（v3では`tail-logs|logs`のエイリアスとして残っている）。

## 6. まとめ

- スタンドアロン型の作成はコンテナバインド型と本質的には同じ`clasp create`だが、`--parentId`を付けないだけで単独プロジェクトになる。
- 一番の違いは「起動点が無い」ことで、Hello World程度の確認なら`clasp open`（またはv3系なら`clasp open-script`）でエディタを開いて手動実行するのが一番簡単。
- クラスプのバージョンによってコマンド名が変わる（`open`→`open-script`など）ので、詰まったらまず`clasp --help`で現在のコマンド一覧を確認する。
