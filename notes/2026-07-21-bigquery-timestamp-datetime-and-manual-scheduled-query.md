# BigQueryのTIMESTAMP→DATETIME変換と、スケジュールクエリの手動即時実行

## 概要
- **学んだきっかけ**: `exams`ビュー定義SQLの`publish_from`/`publish_to`/`published_at`カラムがTIMESTAMP型になっていたのを、他カラム（`created_at`/`updated_at`）と揃えてDATETIME型に修正する作業。修正後、実テーブルへの反映がスケジュールクエリ（毎日7:00 JST実行）任せだと確認に1日かかるため、手動で即時反映させる方法も併せて調べた。

## 目次

1. [TIMESTAMPとDATETIMEの違い](#1-timestampとdatetimeの違い)
2. [TIMESTAMP→DATETIMEの変換方法](#2-timestampdatetimeの変換方法)
3. [スケジュールクエリを手動で即時実行する方法](#3-スケジュールクエリを手動で即時実行する方法)

## 1. TIMESTAMPとDATETIMEの違い

- **TIMESTAMP**: UTC基準の絶対時刻。タイムゾーンをまたぐ比較や複数地域展開を見据えたシステムに向く。
- **DATETIME**: タイムゾーンを持たない「壁時計時刻」。特定のタイムゾーン（例：Asia/Tokyo）に紐づく前提で使うなら可読性が高く、表示時の変換が不要になる。

どちらが「正解」というより、既存カラムとの一貫性で判断するのが実務的。今回は`created_at`/`updated_at`が既にDATETIME（JST変換済み）で統一されていたため、`publish_from`/`publish_to`/`published_at`もDATETIMEに揃えた。

## 2. TIMESTAMP→DATETIMEの変換方法

`DATETIME(カラム, タイムゾーン)`関数でTIMESTAMPからDATETIMEに変換できる。

```sql
DATETIME(W.publish_from, 'Asia/Tokyo') AS publish_from,
DATETIME(W.publish_to, 'Asia/Tokyo') AS publish_to,
DATETIME(W.published_at, 'Asia/Tokyo') AS published_at,
```

`created_at`/`updated_at`で使われていたのと同じパターン。SELECTの別名（AS句）は元のカラム名のままにしておけば、後続処理・BIツール側への影響を抑えられる。

## 3. スケジュールクエリを手動で即時実行する方法

ビュー定義のSQLを直しても、それがスケジュールクエリ経由で実テーブルに反映される構成の場合、通常運用のスケジュール（例：毎日7:00 JST）を待たないと確認できない。BigQueryには手動での即時実行手段がある。

### 手順

1. BigQueryコンソールの「スケジュールされたクエリ」一覧から対象のクエリを開く
2. 詳細画面上部の「バックフィルのスケジュール構成」をクリック
3. ダイアログで「1回限りのスケジュールされたクエリを実行する」を選択する（開始日時・終了日時の入力は不要）
4. 「OK」を押すと、通常のスケジュールを待たずに即時実行がリクエストされ、宛先テーブルに結果が反映される

### 補足・注意点

- 現在のBigQuery UIには独立した「Run now」ボタンは無く、「バックフィルのスケジュール構成」がその役割を担う。
- ダイアログのもう一方の選択肢「特定の期間で実行する」は、過去複数日分をまとめて再実行したいとき（本来の意味でのバックフィル）向け。今回のように直近の修正を1回だけ即時反映したい場合は使わなくてよい。
- 宛先テーブルの書き込みモードが「追記（WRITE_APPEND）」の場合、手動実行分と翌日の通常実行分とで重複行が発生する可能性があるため、実行前に書き込みモード（追記／上書き）を確認しておくと安心。
