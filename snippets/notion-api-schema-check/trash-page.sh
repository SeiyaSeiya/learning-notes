#!/bin/bash
# 検証用に作成したページをゴミ箱へ移動する（完全削除ではない。Notion上のゴミ箱から復元可能）。
#
# 使い方:
#   NOTION_API_TOKEN=ntn_xxxx ./trash-page.sh <PAGE_ID>
#
# 注意: APIバージョン2026-03-11以降は archived ではなく in_trash を使う
#      （2026-03-11で archived は in_trash へ名称変更された）。
set -e

PAGE_ID="${1:?使い方: trash-page.sh <PAGE_ID>}"
NOTION_VERSION="2026-03-11"

if [ -z "$NOTION_API_TOKEN" ]; then
  printf "NOTION_API_TOKEN を貼り付けてください（入力は表示されません）: " >&2
  read -rs NOTION_API_TOKEN
  echo "" >&2
fi

curl -sS -X PATCH "https://api.notion.com/v1/pages/${PAGE_ID}" \
  -H "Authorization: Bearer ${NOTION_API_TOKEN}" \
  -H "Notion-Version: ${NOTION_VERSION}" \
  -H "Content-Type: application/json" \
  --data '{"in_trash": true}'

echo ""
echo "ゴミ箱へ移動しました（完全削除ではありません）。"
