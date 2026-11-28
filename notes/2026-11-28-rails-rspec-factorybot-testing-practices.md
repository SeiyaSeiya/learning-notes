# RailsのRSpec + FactoryBotのテスト作法（リクエストスペック中心の設計から学ぶ）

- 学んだきっかけ: 業務で関わっている大規模なRails APIプロジェクトのテスト構成・設定・ファクトリ・実際のスペックを読み、次の職場のRails開発でも通用する作法としてClaude（Cowork）と整理した。社内固有の名称は含めず、一般化した内容だけを残す。
- 関連メモ: [マイグレーションと大規模DB](2026-11-27-rails-migration-and-large-db-handling.md) / [N+1対策とパフォーマンス改善](2026-11-27-rails-n-plus-one-and-performance-patterns.md) / [Sidekiqによる非同期処理](2026-11-27-rails-sidekiq-background-jobs.md)

## 1. 結論

テストの設計で押さえるのは次の9点。

1. APIはリクエストスペックで通しで確認し、複雑なロジックはユニットテストに分ける
2. DBの後始末は「トランザクション方式」と「`DatabaseRewinder` 等」のどちらかを理由つきで選ぶ
3. ファクトリは「有効な最小限」を既定にし、重い構築は `trait` に分ける
4. `create` に偏らず、`build` / `build_stubbed` を使い分ける
5. `let` / `let!` / 名前付き `subject` を使い分ける
6. ロールが複数あるAPIは `shared_examples` で認可を網羅する
7. 非同期処理と外部APIは、スタブの置き場所を決めて明示する
8. 時間に依存するテストは `travel_to` で固定する
9. 1つの `it` に多数の `expect` を並べるなら `aggregate_failures` を使う

## 2. 題材プロジェクトの特徴（一般化）

| 観察 | 内容 |
| --- | --- |
| スペック総数 | 約350ファイル。うちAPI（リクエスト）スペックが約340、モデル約7、シリアライザ1、lib 3 |
| ファクトリ | 約140個。`create` 系が約1万回、`create_list` が約950回、`build` は約40回、`build_stubbed` は0 |
| DBの後始末 | トランザクション方式は使わず、`DatabaseRewinder` で各テスト後に掃除 |
| 構造 | `context` 約7,700、`it` 約5,500、`let` 約11,700、`let!` 約5,000、名前付き `subject` 約4,400 |
| 共通化 | `shared_examples` 約970、`it_behaves_like` 約2,000 |
| 外部連携 | WebMockで外部APIをスタブ、Redisは `mock_redis` |
| 時間 | `travel_to` 約27回 |
| 並列実行 | `parallel_tests` |
| CI品質ゲート | Rubocop、Brakeman、Danger、SimpleCov |

## 3. 各ポイントの解説

### 3-1. リクエストスペック中心の設計

```ruby
describe Api::SomeResource, type: :request do
  subject(:update_item) { put "/api/items/bulk", params: params, headers: headers }
end
```

- Rails公式もコントローラスペックよりリクエストスペックを推奨。ルーティング、認証、パラメータ検証、シリアライズまで通しで確認できる。
- 認証は `sign_in_as_xxx(user)` のようなヘルパー、JSONのパースは `json` ヘルパーに集約する（`spec/support/`）。
- 題材プロジェクトはモデル・シリアライザ・lib単位のテストが非常に少なく、ロジックがAPIテストを通してしか検証されない。フィードバックが遅くなる（ピラミッドが逆さ）。
- 原則: APIの正常系・異常系・認可はリクエストスペックで、複雑なロジックはユニットテストで、と役割を分ける。

### 3-2. DBの後始末

```ruby
config.use_transactional_fixtures = false
config.after(:each) { DatabaseRewinder.clean }
```

- 通常は `use_transactional_fixtures = true`（テストをトランザクションで囲み、最後にロールバック）が最速。
- `DatabaseRewinder` は、そのテストで触れたテーブルだけを `DELETE` で消す方式。別スレッド・別プロセス・DBトリガなど、実コミットを伴う処理の検証や並列テストで使われる。
- 判断軸: 速度優先ならトランザクション方式、実コミットが必要ならRewinder / `database_cleaner` のtruncation方式。
- 次の職場では、どの方式か、なぜそうしているかを最初に確認する。

### 3-3. FactoryBotの設計

```ruby
factory :client do
  sequence(:name) { |n| "クライアント#{n}" }
  sequence(:code) { |n| "client#{n}" }

  trait :with_organization_hierarchy do
    after(:create) do |client|
      # 管理者・サービス・エリア・店舗などを一式作る
    end
  end
end
```

- `sequence`: ユニーク制約のある列（コード、メールなど）の衝突を避ける定番。
- `trait`: 状態の違い（管理者付き、階層付きなど）を名前で表現する。
- `transient`: 「子を何件作るか」のようなパラメータを受け取れる。
- `after(:create)` で組織階層まるごとを作るtraitは便利だが、テスト1件あたりのコストが大きい。
- 原則: 既定値は「有効な最小限のレコード」。重いデータ構築は、必要なテストだけが指定するtraitに分ける。

### 3-4. `create` に偏ると遅くなる

| 方法 | DB | 使いどころ |
| --- | --- | --- |
| `build_stubbed` | 触らない | ユニットテスト、シリアライザ、計算ロジック |
| `build` | 保存しない | バリデーションの確認 |
| `create` | 保存する | 関連の取得、クエリ、リクエストスペック |

- 題材プロジェクトでは、ほぼすべてが `create`。ある一括更新のスペックでは、1テストごとに数百件のレコードを `let!` で作成していた。
- 件数が結果に影響しないなら、必要最小限（1〜3件）に減らす。大量データが必要なのは、上限値・ページング・パフォーマンスの検証だけ。

### 3-5. `let` / `let!` / 名前付き `subject`

```ruby
let(:client)  { create(:client) }        # 使われたとき初めて作る（遅延）
let!(:tags)   { create_list(:tag, 5) }   # 各テストの前に必ず作る（即時）
subject(:update_item) { put path, params: params }  # 実行するアクションに名前を付ける
```

- `let!` は、作られていないと意味が通らないデータだけにする。増えるほど、1テストあたりの準備時間が膨らむ。
- `subject` に「何を実行するか」の名前を付けると、`it` 内が一行で読める。

### 3-6. `shared_examples` で同じ振る舞いを複数の主体で検証

```ruby
shared_examples 'update succeeds' do
  it 'updates the record' do ... end
end

context 'as admin A' { before { sign_in_as_a(...) } it_behaves_like 'update succeeds' }
context 'as admin B' { before { sign_in_as_b(...) } it_behaves_like 'update succeeds' }
```

- ロールが複数あるAPIの認可テストで効果的。
- 共有化しすぎると、失敗したときにどの前提が崩れたのか追いにくい。引数付きの `shared_examples` で差分を明示すると読みやすい。

### 3-7. 非同期処理・外部APIのテスト

```ruby
expect(SomeWorker.jobs.size).to eq ids.count   # ジョブが投入されたこと
```

```ruby
WebMock.stub_request(:post, "http://localhost/v1/users")
       .to_return(status: 200, body: { id: 1 }.to_json)
```

- Sidekiqは `fake!` モードで、投入されたことを `Worker.jobs` で検証する（Sidekiqメモ参照）。
- 題材プロジェクトでは、外部APIのスタブをファクトリの `before(:create)` の中に置いていた。使う側が意識せずに済む反面、「なぜ通るのか」が見えにくい。
- 一般には、スタブは `spec/support` に共通化するか、テストの中で明示する方が追いやすい。

### 3-8. 時間のテスト

- `ActiveSupport::Testing::TimeHelpers` を導入し、`travel_to` で時刻を固定する。
- ブロック形式 `travel_to(time) { ... }` なら、終了時に自動で元に戻る。
- 「今日」「期限切れ」「営業日」など、実行日で結果が変わるものは必ず固定する。

### 3-9. 気づいた改善余地

- 1つの `it` に多数の `expect` を並べると、最初の失敗で後続が評価されない。`aggregate_failures` を使うと一度に全部が分かる（題材プロジェクトでは使用0件）。
- 「`create` が多く、ユニットテストが少ない」構造は、実行時間の増大に直結する。`parallel_tests` で緩和しているのはその表れ。

## 4. 次の職場で最初に確認すること

1. ファクトリを `FactoryBot.lint` で検証しているか（全ファクトリが有効かを確認する）
2. DBクリーン方式（トランザクション / Rewinder / truncation）
3. `rubocop-rspec` の有無（`let!` の多用、`it` の長さなどの規約）
4. 外部APIのスタブ方針（WebMock / VCR の使い分け）
5. 並列実行とCIの所要時間の目標
6. カバレッジの計測と基準（SimpleCovの下限など）

## 5. 手を動かす確認（10分）

- 自分が書いたスペックを1つ選び、`let!` を `let` に変えても通るものがないか試す。
- そのスペックで `create` を使っている箇所のうち、`build_stubbed` で済むものを探す。
- `bundle exec rspec --profile 10` で遅いテスト上位10件を出し、原因が「データ作成」か「処理そのもの」かを切り分ける。
