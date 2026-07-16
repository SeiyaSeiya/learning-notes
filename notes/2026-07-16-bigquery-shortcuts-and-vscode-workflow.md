# BigQueryの操作をショートカット化する方法とVS Code移行の検討

## 概要
- 学んだきっかけ: BigQuery上で社内の分析テーブルを調査していた際、タブの開閉・切り替え・ペイン移動をマウス操作でしか行っておらず煩わしさを感じたこと。
- BigQuery Studio（ブラウザ版）のショートカットの調べ方から始まり、最終的に「ブラウザ版に頼らずVS Codeで快適にBigQueryを使う」方向で運用方針を決定するまでの調査記録。

## BigQuery Studio（ブラウザ版）のショートカット確認方法
- 正確なショートカット一覧は、ネットの二次情報（Medium記事など）を鵜呑みにせず、**アプリ内で直接確認するのが確実**。
  - 確認方法: エディタ画面で **`Shift + ?`**（`?`キー）を押すと、その環境で実際に有効なショートカット一覧がポップアップ表示される。
  - 実際に試した結果、ネットで見つけた「新規タブ作成 = `Cmd+Option+T`」等の情報は不正確だった。正しくは環境依存のカスタム設定（本セッションでは`Shift T`）だった。
- 確認できた主なタブ操作（実機で有効だったもの）
  | アクション | ショートカット |
  |---|---|
  | 新規タブ作成 | `Shift T` |
  | 次のタブへ移動 | `Shift J` |
  | 前のタブへ移動 | `Shift F` |
  | 特定のタブへジャンプ（1〜8番目） | `⌘ Alt 1` 〜 `⌘ Alt 8` |
  | 最後のタブへ移動 | `⌘ Alt 9` |
  | タブを分割/右へ移動 | `⌘ Alt ]` |
  | タブを分割/左へ移動 | `⌘ Alt [` |
  | タブを右のペインへ移動 | `Ctrl Alt Shift PageDown` |
  | タブを左のペインへ移動 | `Ctrl Alt Shift PageUp` |
- **タブを閉じるショートカットは存在しない**（アプリの仕様として未提供）。macOS側の自動化ツール（Vimiumなどのキーボード操作型のChrome拡張、Keyboard Maestro / BetterTouchToolなどのクリック自動化ツール）で代替する方法はあるが、いずれもBigQuery Studio本体の機能ではなく外部ツールでの回避策。正式対応してほしい場合はBigQuery Studio右上の「フィードバックを送信」から要望を出すのが筋。

## ブラウザ版以外の選択肢
BigQueryはブラウザのBigQuery Studio以外にも利用方法がある。
- **`bq`コマンドラインツール**: Google Cloud CLIに含まれる公式CLI。ターミナルから直接SQL実行可能。
- **Google Cloud VS Code拡張機能（公式）**: データセット/テーブルのブラウズ・スキーマ確認・プレビューが可能。ただしクエリ実行は現状Pythonカーネル経由のNotebook（bigframes）が中心で、プレビュー段階の機能。
- **サードパーティのVS Code拡張機能**: BigQuery Runner、SQLTools BigQuery Driver等。純粋にSQLを書いて結果を見る用途はこちらが適している。
- **DBeaver / DataGrip等の汎用SQLクライアント**: JDBC/ODBC経由でBigQueryに接続可能。使い慣れたエディタのタブ・ペイン操作（通常のOSショートカット）がそのまま使える。

## 運用方針の検討: BigQueryネイティブ機能 vs dbt
「SQLを書いてサクッと結果を見る」に加え、「新しいテーブル/ビュー作成」「SQLの毎日の定期実行」も行いたいという業務要件に対し、2方向を比較した。

- **方向A: BigQueryネイティブ機能で完結**（VS Code + BigQuery Runner + スケジュールされたクエリ）
  - メリット: 新しいツールを覚える必要がなく、既存のVS Code中心のワークフローに馴染む。
  - デメリット: テーブル数が増えると依存関係管理・テスト・命名規則の統一が手作業になりやすい。
- **方向B: dbtを使ったアナリティクスエンジニアリング**
  - SQL+YAMLでテーブル/ビューを宣言的に管理でき、依存関係解決・テスト・ドキュメント生成が可能。VS Code用に「dbt Power User」拡張機能（BigQuery向けフォークあり）が存在。
  - 注意点: dbt Core自体には定期実行の仕組みがなく、Airflow/Cloud Composer/GitHub Actions等の外部オーケストレーションか、有料のdbt Cloudのスケジューラーが別途必要。

→ 今回は**方向A**を採用。管理対象のテーブル・ビューが増えて依存関係が複雑になってきたら、方向B（dbt）への移行を検討する、という段階的な進め方にした。

## 方向A: VS Code環境構築手順
1. Google Cloud CLIをインストール（Homebrew）
   ```bash
   brew install --cask gcloud-cli
   ```
2. 認証
   ```bash
   gcloud auth application-default login
   ```
   認証情報は `~/.config/gcloud/application_default_credentials.json` に保存される。
3. VS Code拡張機能「BigQuery Runner」（`minodisk.bigquery-runner`）をインストール。
4. `settings.json` にプロジェクトIDを設定。
   ```json
   "bigqueryRunner.projectId": "your-project-id"
   ```
5. `.bqsql` 拡張子のファイルにSQLを記述。デフォルトで `Cmd+Enter` が実行キーに割り当て済みで、結果はVS Code内に表示される。ページング移動は `space h`（前）/ `space l`（次）。
   - `CREATE TABLE` / `CREATE VIEW` も同じ実行方法でそのまま流せる。
6. 毎日の定期実行（スケジュールされたクエリ）はVS Code内では完結しないため、統合ターミナルから `bq` コマンドで作成する。
   ```bash
   bq mk --transfer_config \
     --project_id=your-project-id \
     --data_source=scheduled_query \
     --target_dataset=your_dataset \
     --display_name="daily_xxx_view_refresh" \
     --schedule="every day 06:00" \
     --params='{"query":"SELECT ...","destination_table_name_template":"table_name","write_disposition":"WRITE_TRUNCATE"}'
   ```
   もしくはBigQueryコンソールでクエリ実行後に表示される「クエリをスケジュール」ボタンからGUIで作成することも可能（この場合のみ初回にブラウザ操作が必要）。
   - 注意: スケジュールクエリの作成・実行にはBigQuery Data Transfer Service APIの有効化と、実行ユーザーへの`bigquery.admin`相当（またはData Transfer関連ロール）の権限付与が必要。

## まとめ
- 日々のSQL開発・確認（1〜5）はVS Code内で完結する。
- 定期実行の設定だけ、都度ターミナル（`bq`コマンド）かBigQueryコンソールのGUIを使う。
- テーブル/ビューの数や依存関係が複雑化してきたら、dbt導入を再検討する。
