#!/bin/bash
# 指定したdata_source_idに対して、指定したプロパティJSONでページ作成を試す。
# 用途1: 実装前に「この値の渡し方で本当に想定通り保存されるか」を疎通確認する。
# 用途2: ドキュメントに書かれていない挙動（存在しないプロパティ名・型の誤りなど）を、
#        あえて誤った内容のJSONを渡して実測する。
#
# 使い方:
#   NOTION_API_TOKEN=ntn_xxxx ./create-page.sh <DATA_SOURCE_ID> <properties.json>
#
# properties.json はNotion APIのpropertiesオブジェクトそのものを書いたファイル。例:
#   {
#     "名前": { "title": [{ "text": { "content": "テスト" } }] },
#     "ステータス": { "select": { "name": "進行中" } }
#   }
#
# 成功時（HTTP 200）: 作成したページのURLとIDを表示する。
#   確認が終わったら trash-page.sh で必ず削除すること（本番データに混ざらないように）。
# 失敗時: Notionが返したエラー内容をそのまま表示する。
set -e

DS_ID="${1:?使い方: create-page.sh <DATA_SOURCE_ID> <properties.json>}"
PROPS_FILE="${2:?使い方: create-page.sh <DATA_SOURCE_ID> <properties.json>}"
NOTION_VERSION="2026-03-11"

if [ ! -f "$PROPS_FILE" ]; then
  echo "プロパティJSONファイルが見つかりません: ${PROPS_FILE}" >&2
  exit 1
fi

if [ -z "$NOTION_API_TOKEN" ]; then
  printf "NOTION_API_TOKEN を貼り付けてください（入力は表示されません）: " >&2
  read -rs NOTION_API_TOKEN
  echo "" >&2
fi

BODY=$(python3 -c "
import json
props = json.load(open('${PROPS_FILE}'))
payload = {'parent': {'type': 'data_source_id', 'data_source_id': '${DS_ID}'}, 'properties': props}
print(json.dumps(payload))
")

RESPONSE=$(curl -sS -w '\n%{http_code}' -X POST "https://api.notion.com/v1/pages" \
  -H "Authorization: Bearer ${NOTION_API_TOKEN}" \
  -H "Notion-Version: ${NOTION_VERSION}" \
  -H "Content-Type: application/json" \
  --data "${BODY}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY_JSON=$(echo "$RESPONSE" | sed '$d')

echo "HTTP ${HTTP_CODE}"
echo "$BODY_JSON" | python3 -m json.tool 2>/dev/null || echo "$BODY_JSON"

if [ "$HTTP_CODE" = "200" ]; then
  URL=$(echo "$BODY_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('url',''))")
  PAGE_ID=$(echo "$BODY_JSON" | python3 -c "import json,sys; print(json.load(sys.stdin).get('id',''))")
  echo ""
  echo "作成成功。確認後は次のコマンドで削除してください:"
  echo "  ./trash-page.sh ${PAGE_ID}"
  echo "URL: ${URL}"
fi
