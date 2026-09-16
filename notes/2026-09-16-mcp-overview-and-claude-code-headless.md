# MCPとは何か：概要とClaude Code headless実行での自動利用

- 学んだきっかけ: Coworkとの雑談の中で「MCPって何？」という基礎的な疑問から出発し、Claudeで使える主要なMCPコネクタ、さらに「スクリプト経由でClaude Codeを動かす際にMCPを自動で使わせられるか」という実務上の疑問まで掘り下げて教えてもらった。

## 1. MCP（Model Context Protocol）とは何か

- AnthropicがオープンなAI連携規格として公開しているプロトコル。AIアシスタントが外部のデータソースやツール（Slack、Google Drive、GitHub、社内DBなど）とやり取りするための「共通の差し込み口（USB-Cのようなもの）」というイメージ。
- MCP登場以前は、AIをSlackやDBなどと連携させるにはサービスごとに個別の連携コードを書く必要があった。MCPがあれば、サービス提供者は1つの「MCPサーバー」を用意するだけで、MCP対応のどのAIからでも同じように使ってもらえる。
- 「AIが使う用に設計された、共通規格のAPI」と捉えるとイメージしやすい。ただし通常のAPIと違い、AI（Claude）がサーバーに接続した際に「今どんなツールが使えるか」を自動的に発見できる点が特徴（人間が仕様書を読んでコードを書かなくても、AIがその場でツールの使い方を理解して使える）。

## 2. Claudeで使える主要なMCP（コネクタ）

- Anthropicが第一級（プレビルト）統合として提供している代表例:
  - **Google Workspace**（Google Drive / Gmail / Google Calendar）: ファイル検索・読み込み、メールの確認・送信、予定の確認・作成など。
  - **Microsoft 365**: Outlook、OneDrive、Teamsなど。
  - **Slack**: チャンネル検索、メッセージ送信、スレッド要約など。
  - **GitHub**: リポジトリ参照、Issue・PRの確認や作成など。
- これらに加えて、サードパーティ提供のMCPサーバー（Notion、Asana、Linear、Atlassian（Jira/Confluence）、Zapier、Stripe、Figmaなど）もディレクトリに多数登録されており、Anthropicが検証済みのものとコミュニティ提供のものが混在する。
- 実際に使えるものはプランや管理者設定によって変わるため、最新の一覧はClaude.aiの「カスタマイズ」→「コネクタ」から確認するのが確実。

## 3. スクリプト実行（`claude -p`）でもMCPは自動的に使わせられる

- Claude Codeを`claude -p "..."`のような非対話（headless）モードで動かす場合でも、MCPサーバーを自動で読み込ませて使わせることができる。
- 読み込み方法:
  - プロジェクトルートの`.mcp.json`は、通常の`claude -p`実行時に自動的に読み込まれる。
  - `--mcp-config`オプションで、その場限りのMCP設定をコマンドラインから直接渡すこともできる。
  - `--bare`オプション（起動高速化のため、hooks/skills/MCPサーバー等の自動読込を全部スキップするモード）を付けた場合は、`.mcp.json`は読み込まれない点に注意。この場合は`--mcp-config`で明示的に渡す必要がある。

```bash
claude -p "在庫データを確認して" --mcp-config '{"type":"http","url":"https://mcp.example.com/mcp"}'
```

## 4. 対話モードとの一番の違い：承認（パーミッション）の扱い

- 対話モードでは「このMCPツールを使っていいですか？」という確認ダイアログが出るが、`claude -p`のような非対話実行ではこのダイアログ自体が表示されない。
- 何もしないと、承認が必要なアクションは自動的に**拒否**される（黙って失敗するのではなく、拒否されて処理が進まない形）。
- そのため、スクリプトで実際にMCPツールを使わせたい場合は、事前に許可設定をしておく必要がある。
  - `--allowedTools`で個別のツールを許可する。MCPツールは`mcp__サーバー名__ツール名`という形式で指定する（正規表現的な指定も可能）。
  - `--permission-mode auto`を指定すると、承認判断を自動の分類器に任せられる。
  - 誰も承認できない完全無人実行（cron/launchdなど）では、`--permission-prompts none`を付けて承認待ちで止まらないようにする。

```bash
claude -p "GitHubのIssueを確認して要約して" \
  --allowedTools "mcp__github__.*" \
  --permission-mode auto
```

- OAuth認証が必要なMCPサーバー（Slack、Google Driveなど）は、スクリプト実行の中では認証フローを完結できない。事前に`claude mcp login <サーバー名>`のようなコマンドで一度対話的にログインを済ませておく必要がある。

## まとめ

- MCPは「AIと外部ツール・データソースをつなぐ共通規格」で、Claudeでは Google Workspace / Microsoft 365 / Slack / GitHub などが第一級統合として、それ以外にもNotionやAsanaなど多数のサードパーティコネクタが利用できる。
- `claude -p`のようなheadless実行でも、`.mcp.json`や`--mcp-config`でMCPサーバーを自動的に読み込ませられる（ただし`--bare`時は自動読込されない）。
- 非対話実行では承認ダイアログが出ないため、`--allowedTools`や`--permission-mode auto`などで事前に明示的な許可を与えておかないと、MCPツールは何もできずに拒否される。
- 無人実行では`--permission-prompts none`、OAuth系MCPでは事前の`claude mcp login`が必要になる点も忘れずに。
