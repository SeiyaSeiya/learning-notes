# GASプロジェクトの外部公開（Webアプリ／API実行可能ファイル／ライブラリ）の仕組みと、claspでのデプロイ操作

- 学んだきっかけ: GASプロジェクトを外部に公開する3つの方式（Webアプリ、API実行可能ファイル、ライブラリ）について、普段使っているclaspでの具体的な操作（`clasp deploy --description "..."`）との対応関係を調査した。

## 1. GASの外部公開には3種類ある

- **Webアプリ**: `doGet(e)` / `doPost(e)` を実装し、HTTP経由でブラウザや外部システムから叩けるエンドポイントとして公開する方式。
- **API実行可能ファイル（Executable API）**: `doGet`/`doPost`は不要で、スクリプト内の任意の関数を、Apps Script APIの`scripts.run`経由でRPC的に呼び出せるようにする方式。
- **ライブラリ（Library）**: 複数のGASプロジェクト間でコード（関数・クラス）を再利用するための共有機能。他プロジェクトへの「公開API」ではなく、開発者間でのコード共有が主目的。

3つとも「デプロイ（Deploy）」という共通の仕組みの上に乗っている。デプロイには、常にエディタの最新コードと同期する**ヘッドデプロイ**（テスト用）と、特定のバージョンに固定される**バージョン付きデプロイ**（本番用）の2種類がある。

## 2. WebアプリとexecutionApiのマニフェスト設定

`appsscript.json`に、公開方式ごとの設定を書く。

```json
{
  "webapp": {
    "executeAs": "USER_DEPLOYING",
    "access": "ANYONE_ANONYMOUS"
  },
  "executionApi": {
    "access": "MYSELF"
  }
}
```

- `webapp.executeAs`: `USER_DEPLOYING`（デプロイした人の権限で常に実行）か`USER_ACCESSING`（アクセスしたユーザー自身の権限で実行、グラニュラーOAuth同意画面が出る）。
- `access`（Webアプリ・executionApi共通）: `MYSELF` / `DOMAIN` / `ANYONE`（Googleアカウント所持者）/ `ANYONE_ANONYMOUS`（匿名可）の4段階。
- `webapp`と`executionApi`は同時にマニフェストへ書いておくこと自体は可能で、アクセスしてくる側の方法（URLを叩くか`scripts.run`するか）次第でどちらの性質が使われるかが決まる。

実行時間上限は最大6分（Workspaceの有料版などでは条件により最大30分）で、Webアプリ・API実行可能ファイルとも共通の制約。

## 3. ライブラリはマニフェストで差別化されているわけではない

重要な違いとして、Apps Scriptの「新しいデプロイ」で選べる種類の一覧に「ライブラリ」という項目自体は**存在しない**（種類はウェブアプリ／アドオン系／API実行可能ファイルのみ）。公式ガイドが求めているのは次の2点だけ。

1. スクリプトの「バージョン付きデプロイメント」を作る（`webapp`や`executionApi`のようなマニフェスト設定は不要。何も書かれていない状態のデプロイでもよい）
2. そのプロジェクトへの閲覧権限をGoogle Drive側で共有し、利用者にスクリプトIDを渡す

つまりライブラリの成立条件は「マニフェストのフィールド」ではなく「Driveでの共有設定＋スクリプトIDの共有」。利用側がライブラリを読み込むときも、デプロイIDではなく**バージョン番号**を指定する（識別子を設定してそのライブラリを`識別子.libraryMethod()`のように呼び出す）。

## 4. claspでの操作：v2→v3でコマンド名がケバブケースに整理された

claspは2025〜2026年にv2系からv3系へ書き換えられ、コマンド名がケバブケースに統一された（最新は3.3.0）。旧名は多くがエイリアスとして残っている。

| 用途 | v3の主コマンド | v2時代の呼び方（エイリアスとして残る） |
|---|---|---|
| バージョン作成 | `create-version` | `version` |
| バージョン一覧 | `list-versions` | `versions` |
| デプロイ作成 | `create-deployment` | `deploy` |
| デプロイ一覧 | `list-deployments` | `deployments` |
| デプロイ削除 | `delete-deployment` | `undeploy` |
| エディタを開く | `open-script` | `open` |
| Webアプリを開く | `open-web-app` | `open --webapp` |
| 関数を遠隔実行 | `run-function` | `run` |
| API有効化 | `enable-api` | `apis enable` |

手元の環境がどちらのコマンド体系か分からない場合は`clasp --version`と`clasp help`で確認するのが確実（v3の中でもalpha版時点では`update-deployment`や`open-web-app`が動かないなどの過渡的な不整合があった）。

## 5. `clasp deploy`はバージョン作成とデプロイを1コマンドでまとめる便利コマンド

`clasp deploy --description "説明文"`のように**バージョン番号を省略**すると、内部的には

```bash
clasp create-version "説明文"
clasp create-deployment -V <今できたバージョン番号> -d "説明文"
```

を1回でやっているのと同じ。GitHubのREADMEにも`clasp create-deployment (create new deployment and new version)`と明記されている。単一のWebアプリ／API実行可能ファイルを更新するだけなら、`create-version`を分けて叩く必要はなく、この省略形が標準的な使い方。

## 6. 実務上の注意：`-i`（--deploymentId）なしだと毎回新しいURLになる

**`-i`を指定しないと、毎回まったく新しいデプロイ（新しいデプロイID・新しい`/exec` URL）が作られる。** Slack Interactivityの受け口のように外部にURLを登録済みの場合、`-i`なしで再度`clasp deploy`すると、コードは更新されるが登録済みURLとは別の新URLが発行され、Slack側の設定更新をしないと動かなくなる。

同じURLを維持したまま更新する場合：

```bash
clasp deploy -i <既存のdeploymentId> --description "受け口を修正"
```

既存のデプロイIDは`clasp list-deployments`（旧`clasp deployments`）で確認できる。

## まとめ

- Webアプリ／API実行可能ファイル／ライブラリの3つとも、`clasp push` → `clasp deploy --description "..."` という同じ手順で作れる。
- Webアプリ・API実行可能ファイルの違いは`appsscript.json`の`webapp`/`executionApi`フィールドで決まる。
- ライブラリだけは特殊で、マニフェストのフィールドではなく「バージョン付きデプロイの存在」＋「Drive共有設定」＋「スクリプトIDの共有」で成立する。
- 本番運用中のWebhook（Slack Interactivity受け口など）を更新するときは、`-i <既存のdeploymentId>`を付けないと新しいURLが発行されてしまう点に要注意。
