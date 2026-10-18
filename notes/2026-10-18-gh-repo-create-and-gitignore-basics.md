# ghコマンドでのリポジトリ作成と、.gitignore・.envの基本

## 概要
メモ用のスクリプト置き場として新しいリポジトリ（`sandbox`）をプライベートで作成した際に学んだことを整理した。リポジトリ名の決め方、TIL用リポジトリとの分離判断、`gh repo create` の使い方、`.gitignore` / `.env` の書き方、初回 `git push` だけで送れた理由など。

## 1. リポジトリ名・分離の判断
メモ感覚で書くスクリプト置き場の名前候補は、短くて打ちやすく用途が分かるものが良い。

* 定番: `scratch` / `playground` / `sandbox`
* メモ・ノート感: `scripts-memo` / `snippets` / `dev-notes`
* 遊び心: `junk-drawer` / `workbench` / `toolbox`

今回は `sandbox` にした。組織アカウントに作る場合は `clipline-sandbox` のように接頭辞を付けると他と区別しやすい。

### TIL用リポジトリとは分ける
用途が似ていても、次の理由で分けた。

* 成果物の種類が違う（スクリプトは実行するコード、TILは読み返す文章）
* 公開範囲が違う（スクリプトはトークンや社内URLが混ざりやすくPrivate向き、TILは公開してもよい内容が多い）
* 見返し方が違う（TILは日付・トピック、スクリプトは用途・言語で探す）
* 運用ルールを別々にできる

まとめるのは「完全に個人用で公開しない」「記録の頻度が低い」場合のみ。リポジトリは後から統合するより分離する方が手間がかかるので、迷うなら先に分けておく。

## 2. ghコマンドでリポジトリを作成する
事前に `gh auth login` で認証しておく（状態確認は `gh auth status`）。

```bash
# 作成・クローン・初期コミットを一度に行う
gh repo create sandbox --private --clone --add-readme

# 組織配下に作る場合
gh repo create <組織名>/sandbox --private --clone --add-readme

# ローカルに git init 済みのフォルダから作る場合（先に1コミット必要）
gh repo create sandbox --private --source=. --remote=origin --push
```

* `--add-readme` を付けるとGitHub側でREADME入りの初期コミットが作られる。付けないとコミットのない空リポジトリになる。
* `--description "..."` で説明文、`--gitignore Python` で `.gitignore` テンプレートを付けられる。
* 公開範囲は後から `gh repo edit --visibility public --accept-visibility-change-consequences` で変更できる。

## 3. 初回から `git push` だけで送れた理由
`--clone` が内部で `git clone` 相当の処理をするため、次の2つが自動で設定される。

* リモート `origin`（クローン元のURL）
* 上流ブランチの紐づけ（ローカルの `main` が `origin/main` を追跡）

確認コマンド。

```bash
git remote -v
git branch -vv   # main が [origin/main] を追跡していれば OK
```

ローカルで `git init` しただけのリポジトリはリモートも上流ブランチも未設定なので、次のように指定する必要がある。

```bash
git remote add origin <URL>
git push -u origin main   # -u で上流ブランチを紐づけ。以降は git push だけでよい
```

## 4. .gitignore と .env の基本

### .gitignore（最初は汎用セットで十分）
```gitignore
# 環境変数・認証情報
.env
.env.*
!.env.example

# OS・エディタ
.DS_Store
Thumbs.db
.vscode/
.idea/

# Python
__pycache__/
*.pyc
.venv/
venv/

# Node.js
node_modules/

# ログ・一時ファイル
*.log
tmp/
```

### .env と .env.example
* `.env`: 実際の値（トークンなど）を `KEY=value` 形式で書く。コミットしない。最初は空でもよい。
* `.env.example`: 必要なキーだけを値なしで書いたひな形。こちらはコミットする。別のPCで環境を作るときの手がかりになる。

### 注意点
* `.gitignore` に追記する前に一度でもコミットしたファイルは追跡され続ける。止めるには `git rm --cached <ファイル>`（ファイル自体は消えない）。
* `git add .env` が「ignored by one of your .gitignore files」で失敗するのは、`.gitignore` が正しく効いている証拠で、想定どおりの動作。`-f` で強制追加すると履歴に残り続けるので使わない。
* コミット前に `git status` で `.env` が一覧に出ていないことを確認する。

## 5. .DS_Store とは
macOSのFinderが、フォルダを開くと自動で作る隠しファイル（Desktop Services Store）。アイコンの配置、表示方法、ウィンドウのサイズ・位置、並び順など、そのフォルダの表示設定が入っている。自分のMacの表示設定にすぎず、コードやデータとは無関係なので、`.gitignore` に入れるのが定番。Windowsでは似た存在として `Thumbs.db`（サムネイルのキャッシュ）がある。

## まとめ
* 用途や公開範囲が違うリポジトリは、最初から分けておく。
* `gh repo create ... --private --clone --add-readme` で、作成・クローン・初期コミットまで済み、すぐ `git push` で運用できる。
* `.env` は最初から `.gitignore` に入れ、コミット前に `git status` で確認する習慣をつける。
