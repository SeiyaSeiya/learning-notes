# rbenvでRubyをバージョンアップする手順（3.3.0 → 4.0.7）と、`rbenv install`系コマンド・Bundlerの基礎

- 学んだきっかけ: `rbenv versions`で現在のRubyが3.3.0だと分かり、最新版に上げる方法をClaude（Cowork）に相談した。実際に4.0.7へ更新できたので、手順と途中で出てきた疑問をまとめておく。

## 1. 結論

`rbenv versions`で表示されるのは**インストール済みのバージョン一覧**。新しいRubyを使うには、**追加でインストールして切り替える**必要がある。今回は3.3.0から4.0.7に更新できた（`rbenv install -l`に最新の安定版として表示されたもの）。

当初「4.0.6が最新安定版らしい」と聞いていたが、実際に`-l`で確認すると4.0.7だった。バージョン番号は人から聞いた情報や記憶に頼らず、**自分のコマンド出力で確認する**。

## 2. バージョン関連コマンドの違い

| コマンド | 表示されるもの | 使いどころ |
| --- | --- | --- |
| `rbenv versions` | インストール済みのバージョン一覧 | 今何が入っているか確認する |
| `ruby -v` | いま有効なRubyのバージョン | 切り替えが反映されたか確認する |
| `rbenv install -l` | インストールできる最新の安定版だけ | どれを入れればよいか迷ったとき（基本はこれ） |
| `rbenv install --list-all` | 開発版・preview版を含む全バージョン | 古いバージョンやpreview版を探す |

`-l`に出ず`--list-all`にだけ出るバージョンは、ruby-buildが古くて最新安定版として認識していないか、preview/RCなど正式版ではない可能性がある。`4.0.0-preview1`のような名前でなく素のバージョン番号なら正式版。

## 3. アップデートの手順

```bash
# 1. rbenvとruby-buildを更新（Homebrewの場合）
brew update && brew upgrade rbenv ruby-build
# gitで入れている場合は ~/.rbenv/plugins/ruby-build で git pull

# 2. インストールできる最新の安定版を確認
rbenv install -l

# 3. インストール
rbenv install 4.0.7

# 4. 切り替え
rbenv local 4.0.7     # プロジェクトだけ（.ruby-versionが作られる）
rbenv global 4.0.7    # マシン全体のデフォルト

# 5. 確認
ruby -v
```

新しいバージョンが一覧に出ないときは、ruby-buildが古いだけなのでステップ1で更新する。`local`で先に試して、問題なければ`global`にするのが安全。

## 4. Bundler（`gem install bundler`）とは

Bundlerは、`Gemfile`に書かれたgemを決まったバージョンでまとめてインストールするツール。Railsなどで`bundle install`を使うために必要になる。

- rbenvはRubyのバージョンごとにgemを別々に管理する。切り替えた直後は、以前のバージョンに入っていたgemは使えない。
- BundlerはRubyに標準で同梱されていることが多い。`bundle -v`でバージョンが表示されれば、`gem install bundler`は不要。
- 表示されない場合や最新版にしたい場合だけ`gem install bundler`を実行する。
- プロジェクトを動かすときは、その後に`bundle install`でgemをインストールする。

## 5. 注意点

3.3から4.0はメジャーバージョンの更新なので、既存プロジェクトで使う前に互換性を確認する。

- **互換性**: Railsなどのフレームワークやgemが、Ruby 4.0に対応しているか先に確認する。非対応のgemがあると`bundle install`が失敗することがある。
- **ネイティブ拡張**: 拡張を持つgemはRubyのバージョンごとに再ビルドが必要。時間がかかったり、OS側のライブラリ不足でエラーになったりすることがある。
- **ロールバック**: 古いバージョンは残るので、`rbenv global 3.3.0`で戻せる。不要になったら`rbenv uninstall 3.3.0`で削除できる。
- **進め方**: まず`rbenv local`でプロジェクト単位で試し、問題なければ`global`に切り替える。
