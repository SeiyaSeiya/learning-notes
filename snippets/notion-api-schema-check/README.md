# Notion API スキーマ確認・検証スニペット

Notion Integration（APIトークン）を使って、対象データベースの実際のスキーマを確認したり、
ページ作成の疎通確認・ドキュメント未記載の挙動の実測を行うための使い捨てスクリプト群。
プロジェクト固有の情報（データベースID・プロパティ名など）は含まれていないので、
別のNotion連携作業でもそのまま使い回せる。

## 背景

2026年8月〜9月、`gas-voc-extract`プロジェクトのNotion連携実装（Slack Interactivity経由でVOCを
Notionへ登録する機能）で実際に使ったスクリプトから、プロジェクト固有の情報を取り除いて一般化したもの。
経緯の詳細は [../../notes/2026-09-01-notion-api-verification-shell-scripts.md](../../notes/2026-09-01-notion-api-verification-shell-scripts.md) を参照。

## 使う場面

- 実装（GAS・Node.jsなど）を書く前に、対象データベースの正確なプロパティ名・型・選択肢を確認したいとき
  → `fetch-schema.sh`
- 実際に1件ページを作ってみて、想定した値が正しく保存されるか確かめたいとき
  → `create-page.sh`
- ドキュメントに書かれていない挙動（存在しないプロパティ名を渡すとどうなるか、型を間違えるとどうなるか等）
  を実測したいとき → `create-page.sh` に、あえて誤った内容のJSONを渡してエラー内容を見る

## 使い方

```bash
# 1. スキーマを確認する（DATABASE_ID はURL末尾の32桁の英数字）
./fetch-schema.sh <DATABASE_ID>
#    → data_source_id が表示される。以降のコマンドではこちらを使う。
#    → notion_database.json / notion_data_source.json にプロパティ名・型・選択肢一覧が保存される。

# 2. 実際にページを作って確認する（properties.json は事前に用意する）
./create-page.sh <DATA_SOURCE_ID> properties.json

# 3. 確認が終わったら、作成したテストページをゴミ箱へ移動する
./trash-page.sh <PAGE_ID>
```

## 共通の作法

- `NOTION_API_TOKEN` は環境変数で渡すか、未設定なら非表示入力（`read -rs`）で受け取る。コマンドの引数や
  設定ファイルに直接書かない（シェル履歴にも残さない）。
- `Notion-Version` ヘッダーは省略しない（省略すると古いデフォルトバージョンで動作してしまう）。
- 検証用に作ったページは本番データに混ざらないよう、確認後に必ず `trash-page.sh` でゴミ箱へ移動する
  （完全削除ではなくゴミ箱に入るだけなので、間違えて実行しても復元できる）。

## Notion APIバージョンに関する注意

Notion APIは頻繁にバージョンが更新される。このスニペット作成時点で直近の主な変更は以下の2つ。

- `2025-09-03`: データベースの下に「データソース」という階層が追加され、ページ作成の`parent`が
  `database_id`ではなく`data_source_id`を指すようになった。
- `2026-03-11`: ページ等をゴミ箱へ移動する際のフィールド名が`archived`から`in_trash`へ変更された。

これらのスニペットは`2026-03-11`を前提に書いている。再利用する際は
[Notion公式のchangelog](https://developers.notion.com/page/changelog)で、さらに新しいバージョンが
出ていないか確認すること。
