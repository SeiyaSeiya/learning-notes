# Slack Bot連携で実際に必要になる認証情報の見分け方（Client ID/App IDとBot Tokenの違い）

- 学んだきっかけ: `gas-feedback-generate` プロジェクトで、DM通知用のSlack Botを情シスに作成依頼し、受け取った「Client ID」「App ID」をどこに設定すればよいか分からずClaude Codeに確認した。

## 1. Client ID / App IDは「Slack App自体」を識別するための情報で、GASのコードには出てこない

Slack Appを作成すると、Slack API管理画面上でそのAppに紐づく識別子として Client ID・App ID・Client Secret などが発行される。これらは主に、外部の第三者ユーザーに対してOAuth認可フロー（「このAppをワークスペースに追加を許可しますか？」的なやつ）を組む場合に使うもので、**自分のワークスペース向けに`chat.postMessage`でDMを送るだけの用途では直接使わない**。

## 2. 実際にコードが必要とするのは「Bot User OAuth Token」

`chat.postMessage` のようなSlack Web APIを呼ぶ場合、必要なのは `xoxb-` から始まる **Bot User OAuth Token** で、これはSlack Appを自分のワークスペースにインストールした時点で発行される。

- Slack Appの管理画面 → 「OAuth & Permissions」→ Bot Token Scopesに必要なスコープ（DM送信なら `chat:write`）を追加してワークスペースにインストールする。
- インストール完了後に表示される `xoxb-...` の文字列がBot Token。

## 3. Bot Tokenはコードに直書きせず、GASのスクリプトプロパティに保存する

APIキーやトークンをソースコードやGitにコミットしないという原則はSlack Tokenでも同じ。GASの場合は `PropertiesService.getScriptProperties()` から読み込む前提にしておき、実際の値はGASエディタの「プロジェクトの設定」→「スクリプト プロパティ」画面でキーと値を登録する。

```js
const SLACK_BOT_TOKEN = PropertiesService.getScriptProperties().getProperty('SLACK_BOT_TOKEN');
```

## 4. まとめ

- 「Slackの認証情報」と一口に言っても、Slack App自体を識別するClient ID/App IDと、API呼び出しに使うBot User OAuth Tokenは全く別物で、用途によって必要なものが違う。
- 情シスなど外部から認証情報一式を渡された場合、まず「このコードは具体的にどのSlack API呼び出しをしていて、どの種類の認証情報を要求しているか」をコード側（`Authorization: Bearer ${SLACK_BOT_TOKEN}` のような箇所）から逆算して確認すると、渡された情報だけで足りるのか、追加でBot Tokenの発行（＝ワークスペースへのインストール作業）が必要なのかを切り分けやすい。
