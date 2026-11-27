# Railsのマイグレーションと大規模DBの扱い（PostgreSQL）

- 学んだきっかけ: 業務で関わっている、数百本規模のマイグレーションを持つ大規模なRails APIプロジェクトを題材に、次の職場のRails開発でも通用する「マイグレーションとDB設計の勘所」をClaude（Cowork）と整理した。社内固有の名称は含めず、一般化した内容だけを残す。

## 1. 結論

大規模・長期運用のRailsアプリでは、マイグレーションは「スキーマを変えるコード」ではなく**本番を止めずにDBを変更する運用手順**として考える。押さえるポイントは次の6つ。

1. `structure.sql` と `schema.rb` の使い分け
2. 部分ユニークインデックス（NULLを含む一意性）
3. 外部キーと `on_delete: :cascade`
4. 大量データを更新するマイグレーションの書き方
5. DBビューとPG関数の使いどころと代償
6. 安全なマイグレーションの定石（今回の題材には無かったが、次の職場で必ず確認する）

## 2. 題材プロジェクトの特徴（一般化）

| 観察 | 内容 |
| --- | --- |
| マイグレーション数 | 数百本規模（約10年分） |
| スキーマ管理 | `db/structure.sql`（2万行超）。`schema.rb`ではない |
| DBビュー | 複数あり、Railsモデルから読み取り専用で参照 |
| PG関数 | 一括削除など、整合性が必要な処理をDB内に持つ |
| 生SQL（`execute`） | 多数のマイグレーションで使用 |
| 外部キー | 多数のマイグレーションで `add_foreign_key` を使用 |
| `algorithm: :concurrently` / `strong_migrations` | 使われていなかった |

最後の行が重要で、「無停止で変更するための道具が入っていないプロジェクトもある」という気づきになった。

## 3. 各ポイントの解説

### 3-1. `structure.sql` と `schema.rb`

- `schema.rb`はRubyのDSLでスキーマを表す。DBビュー、PG関数、部分インデックスなど**PostgreSQL固有機能は表現しきれない**。
- 固有機能を使うなら `config.active_record.schema_format = :sql` として `structure.sql` を使う。
- デメリット: 差分が大きくなりやすく、ブランチ間でコンフリクトしやすい。
- 次の職場では、どちらの方式か、なぜそうしているかを最初に確認する。

### 3-2. 部分ユニークインデックス（NULLを含む一意性）

PostgreSQLでは、NULLどうしは「異なる値」として扱われるため、NULLを含む列の組み合わせは通常のユニークインデックスでは重複を防げない。条件別にインデックスを分けて対処できる。

```ruby
# 例: parent_id がNULLの行と、NULLでない行で別々に一意性を守る
add_index :results, [:detail_id, :branch_id], unique: true,
          where: 'parent_id IS NULL'
add_index :results, [:detail_id, :branch_id, :parent_id], unique: true,
          where: 'parent_id IS NOT NULL'
```

- アプリ側の `validates :uniqueness` だけでは、並行リクエストでレースコンディションが起き得る。
- 一意性の最終防衛線は**DBの制約**に置く（バリデーションは親切なエラーメッセージ用）。

### 3-3. 外部キーと `on_delete: :cascade`

- 外部キーの挙動を変えるには、いったん `remove_foreign_key` してから `add_foreign_key` し直す。
- `up` / `down` を両方明示して、元に戻せるようにしておく。
- `has_many dependent: :destroy` はRuby側で1行ずつ削除するので遅い。DBのカスケードは速く、ロック時間も短くなりやすい。
- 注意点:
  - カスケード削除では**ActiveRecordのコールバックが走らない**。`after_destroy` に監査ログや外部連携を書いている場合は漏れる。
  - 巨大テーブルへの外部キー追加は、検証のために書き込みをブロックすることがある。

### 3-4. 大量データを更新するマイグレーション

典型例:

```ruby
def up
  add_column :results, :last_performed_at, :datetime
  add_index  :results, :last_performed_at

  Result.find_each(batch_size: 100) do |r|
    r.update_columns(last_performed_at: ...)
  end
end
```

- 良い点: `find_each` でメモリを抑え、`update_columns` でコールバックとバリデーションを避けている。
- 意識したい点:
  - **スキーマ変更とデータ移行は分ける**（別マイグレーション、または別のrakeタスク）。長時間のトランザクションでロックを握り続けないため。
  - マイグレーション内で本物のモデルクラスを使うと、将来モデルが変わったときに古いマイグレーションが壊れる。`Class.new(ActiveRecord::Base)` で簡易モデルを定義するか、SQLで書く。
  - 1行ずつの更新より、`update_all` やSQLの一括更新で済まないか先に考える。

### 3-5. DBビューとPG関数

- ビューは `execute` で `CREATE VIEW` を書き、Railsモデルに `self.table_name` を指定して読み取り専用で使う。
- 使いどころ: 複雑な集計の再利用、ツリー構造（`ancestry`など）の親子突き合わせ。
- 代償:
  - ビューが参照している列は、元テーブルから簡単に変更・削除できない（依存エラーになる）。
  - ビューは基本的に読み取り専用。
  - PG関数にビジネスロジックを置くと、速度と原子性は得られる一方、テスト・レビュー・可読性が難しくなる。
- 「DB側に持つか、アプリ側に持つか」は常にトレードオフとして判断する。

### 3-6. 安全なマイグレーションの定石（要確認リスト）

| 項目 | 内容 |
| --- | --- |
| `algorithm: :concurrently` | 書き込みを止めずにインデックスを作る。`disable_ddl_transaction!` とセットで使う |
| `strong_migrations` gem | 危険なマイグレーション（カラム削除、型変更、長時間ロック等）を実行前に検出し、安全な書き方を案内する |
| カラム削除の3段階手順 | ①コードで `ignored_columns` に指定 → ②デプロイ → ③カラム削除。いきなり消すと旧コードが落ちる |
| 外部キーの `validate: false` → 後で `validate_foreign_key` | 巨大テーブルで、ロックを短くしつつ制約を追加する |
| NOT NULL追加の安全手順 | CHECK制約を `NOT VALID` で作る → 検証 → NOT NULLに変換 |

## 4. 手を動かす確認（5〜10分）

1. 最近自分が書いたマイグレーションを3本選ぶ（`git log --diff-filter=A --name-only -- db/migrate`）。
2. 各マイグレーションについて「本番の巨大テーブルで実行したら何秒ロックするか？」を自問する。
3. `config/application.rb` で `schema_format` を確認する。
4. マイグレーションの実行タイミングと順序がデプロイ手順（CI/CD設定）でどう制御されているかを読む。

## 5. 次の職場で最初に確認すること

- スキーマ管理は `structure.sql` か `schema.rb` か
- `strong_migrations` は導入されているか
- インデックス追加は `concurrently` で行う運用か
- カラム削除のルール（`ignored_columns` を使うか）
- マイグレーションを本番へ流すタイミング（デプロイ前か後か、手動か自動か）

## 6. 関連メモ

- [2026-10-18: rbenvでRubyをバージョンアップする手順](2026-10-18-rbenv-ruby-version-upgrade.md)（Rails開発環境の整備）
