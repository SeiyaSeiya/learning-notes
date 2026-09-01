#!/bin/bash
# Notionデータベースの data_source_id とプロパティスキーマ（プロパティ名・型・選択肢一覧）を取得する。
#
# 使い方:
#   NOTION_API_TOKEN=ntn_xxxx ./fetch-schema.sh <DATABASE_ID>
# もしくは:
#   ./fetch-schema.sh <DATABASE_ID>   （トークンの入力を求められる。入力は表示されない）
#
# DATABASE_ID は対象データベースのURL末尾に含まれる32桁の英数字（ハイフンは付けても付けなくてもよい）。
# 出力: 実行したディレクトリに notion_database.json / notion_data_source.json を書き出す。
set -e

DB_ID="${1:?使い方: fetch-schema.sh <DATABASE_ID>}"
OUT_DIR="$(pwd)"
NOTION_VERSION="2026-03-11"

if [ -z "$NOTION_API_TOKEN" ]; then
  printf "NOTION_API_TOKEN を貼り付けてください（入力は表示されません）: " >&2
  read -rs NOTION_API_TOKEN
  echo "" >&2
fi
if [ -z "$NOTION_API_TOKEN" ]; then
  echo "NOTION_API_TOKEN が空です。中断します。" >&2
  exit 1
fi

echo "1) データベースを取得して data_source_id を確認..." >&2
curl -sS -X GET "https://api.notion.com/v1/databases/${DB_ID}" \
  -H "Authorization: Bearer ${NOTION_API_TOKEN}" \
  -H "Notion-Version: ${NOTION_VERSION}" > "${OUT_DIR}/notion_database.json"

DS_ID=$(python3 -c "
import json
d = json.load(open('${OUT_DIR}/notion_database.json'))
print((d.get('data_sources') or [{}])[0].get('id', ''))
")

if [ -z "$DS_ID" ]; then
  echo "data_source_id を取得できませんでした。レスポンスを確認してください:" >&2
  cat "${OUT_DIR}/notion_database.json" >&2
  exit 1
fi
echo "   data_source_id = ${DS_ID}" >&2

echo "2) データソースのプロパティスキーマを取得..." >&2
curl -sS -X GET "https://api.notion.com/v1/data_sources/${DS_ID}" \
  -H "Authorization: Bearer ${NOTION_API_TOKEN}" \
  -H "Notion-Version: ${NOTION_VERSION}" > "${OUT_DIR}/notion_data_source.json"

echo "" >&2
echo "完了しました。書き出し先:" >&2
echo "  ${OUT_DIR}/notion_database.json" >&2
echo "  ${OUT_DIR}/notion_data_source.json" >&2
echo "" >&2
echo "data_source_id: ${DS_ID}"
