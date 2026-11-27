# RailsのN+1対策とパフォーマンス改善のパターン（実コードの改善履歴から）

- 学んだきっかけ: 業務で関わっている大規模なRails APIプロジェクトの、過去の性能改善コミットの差分を読み、次の職場のRails開発でも通用するパターンとしてClaude（Cowork）と整理した。社内固有の名称は含めず、一般化した内容だけを残す。
- 前提メモ: [Railsのマイグレーションと大規模DBの扱い](2026-11-27-rails-migration-and-large-db-handling.md)（パターン4・5はこちらと対になっている）

## 1. 結論

Railsの性能問題は、次の4つの型に分類できる。

1. **読み込み**: N+1、不要な `JOIN`、デカルト積（`includes` / `preload` / `eager_load` の使い分け）
2. **書き込み**: ループ内の1件ずつの `create` / `update`（一括 `import` / `insert_all` / `update_all` に置き換える）
3. **削除**: `dependent: :destroy` の連鎖（`delete_all` やDBの `on_delete: :cascade` に寄せる）
4. **DB・計算**: 複合インデックス不足、同じオブジェクトの再生成（メモ化）

改善の順序は「**計測 → 原因の型を特定 → 最小の修正 → 再計測**」。

## 2. 題材プロジェクトの特徴（一般化）

| 観察 | 内容 |
| --- | --- |
| N+1検出 | `bullet` gem が開発環境のみ有効 |
| 読み込み系 | `includes` 約125、`preload` 約23、`eager_load` 約5、`pluck` 約380 |
| 一括書き込み | `activerecord-import` の `import` 約48、`update_all` / `delete_all` 各30件台 |
| 未使用 | `counter_cache`、`find_in_batches` |
| 改善の履歴 | 検索API、一括登録、削除、インデックス追加、メモ化など |

## 3. パターン別の解説

### パターン1: `includes` を `preload` に替える

```ruby
# Before: where で関連テーブルを参照 → includes が LEFT JOIN に切り替わる
Result.includes({ detail: :options }, :files, :student)
      .where(details: { id: ids })

# After: 読み込みだけなら preload（関連ごとに別クエリ）。絞り込みは自テーブルの列で行う
Result.preload({ detail: :options }, :files, :student)
      .where(detail_id: ids)
```

- `preload` は関連ごとに別クエリ（`WHERE id IN (...)`）を発行する。
- `includes` は、`where` / `order` で関連テーブルを参照した瞬間に **JOIN方式（`eager_load` 相当）へ自動で切り替わる**。
- 複数の `has_many` をJOINすると行数が掛け算で増える（**デカルト積**）。結果が数千件でも、DBから数十万行返ることがある。
- 使い分けの目安:
  - 関連テーブルの列で絞り込む・並べ替える → `eager_load`（または `joins` + `preload`）
  - 読み込むだけ → `preload`（迷ったらこれ）
  - `includes` は条件で挙動が変わる「便利屋」と覚える

### パターン2: 重複した `preload` の整理

- 同じ関連名（例: `:creator`, `:updater`）を `preload` の引数に2回書いていたのを削除するだけの修正があった。
- 効果は小さいが、N+1を潰していく過程で関連のリストが散らかる、というあるあるを示している。
- シリアライザが実際に使う関連だけを読み込むよう、定期的に棚卸しする。

### パターン3: 1件ずつ `create` → 一括 `import`

```ruby
# Before: 件数ぶんINSERT（＋バリデーション＋コールバック）
ids.each { |id| parent.children.create(target_id: id, ...) }

# After: 1回のINSERT
rows = ids.map { |id| [parent.id, id, ...] }
Child.import(columns, rows, validate: false)

# さらに大きな入力に備えてバッチ分割
rows.each_slice(2000) { |batch| Child.import(columns, batch, validate: false) }
```

- Rails標準では `insert_all` / `upsert_all`（Rails 6以降）。`activerecord-import` はその先行ライブラリ。
- **`validate: false` の代償**: バリデーションもコールバックも走らない。入力の検証は呼び出し側で済ませる前提になる。
- 一括INSERTにも上限がある（SQL長、パラメータ数）。数千件単位で `each_slice` で分割する。
- `return if ids.blank?` を最初に置いて、無駄なクエリを避ける。

### パターン4: `dependent: :destroy` → `:delete_all`

```ruby
has_many :results, dependent: :destroy     # 全件ロード → 1件ずつコールバック付きで削除（遅い）
has_many :results, dependent: :delete_all  # DELETE FROM results WHERE parent_id = ? （1回）
```

- `:destroy` は子を全件ロードして1件ずつ削除する。子の子まで連鎖すると、クエリ数が爆発する。
- `:delete_all` は1回のSQLだが、**コールバックが走らない**。孫レコードの削除は別の手段（DBの外部キー `on_delete: :cascade` など）で担保する必要がある。
- 実際の改善でも、先に外部キーをカスケード化するマイグレーションが入っていた。**コードの変更とDB制約はセットで成立する**。

### パターン5: 複合インデックスの追加

```ruby
add_index :reports, [:client_id, :created_at, :content_id]
```

- 複合インデックスは**列の順序が重要**。基本は「等価条件（`=`）の列 → 範囲条件・並べ替えの列」の順。
- 追加前後で `EXPLAIN (ANALYZE, BUFFERS)` を見て、`Seq Scan` が `Index Scan` に変わるかを確認する。
- 巨大テーブルへの追加は `algorithm: :concurrently` を検討する（前回メモ参照）。
- インデックスは書き込みを遅くするため、増やしすぎない。

### パターン6: メモ化（`@x ||=`）

```ruby
def s3_object
  return nil if media_key.nil?
  @s3_object ||= S3Object.new(media_key)
end
```

- 一覧で、シリアライザが同じレコードから何度も呼ぶ場合に効く。
- 注意点:
  - 元になる属性が後から変わると、古い値のまま残る。
  - `nil` / `false` を返すメソッドには `||=` が効かない（毎回再計算される）。必要なら `defined?(@x)` で判定する。

## 4. N+1の発生源の傾向

- 一覧系APIで、シリアライザが `object.xxx.yyy` と辿るたびにクエリが増える（`active_model_serializers` 系の典型）。
- `pluck` の多用は、必要な列だけ取得できて軽い一方、複数列を配列で返すと可読性が落ちる。
- `exists?` など小さなクエリの積み重ねも、本番の遅さにつながる。

## 5. 次の職場で使える確認手順

1. **計測**: 開発環境で `bullet` を有効にしてログを確認する。重い処理は `EXPLAIN ANALYZE` と実行時間で見る。
2. **読み込み**: N+1なら `preload`、絞り込みを伴うなら `eager_load` / `joins`。
3. **書き込み・削除**: ループ内の `create` / `update` / `destroy` は、`import` / `insert_all` / `update_all` / `delete_all` で置き換えられないかを考える。コールバックが消える影響を確認する。
4. **検索**: WHERE・ORDER BYに合わせた複合インデックスを検討する。
5. **再発防止**: テストでクエリ数を固定する（`ActiveSupport::Notifications` でSQL数を数える、など）。

## 6. 手を動かす確認（10分）

- `git log -i --grep='perform\|N+1\|preload'` で過去の性能改善コミットを探し、diffだけを見て「なぜこの書き方が速いのか」を自分の言葉で説明してみる。
- 自分が担当した一覧APIで、`preload` の有無とクエリ数を `rails_logger` で数えてみる。
