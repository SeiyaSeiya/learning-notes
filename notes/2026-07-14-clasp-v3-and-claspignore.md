# clasp v3のコマンド変更と、git worktreeが引き起こす.claspignoreの落とし穴

- 学んだきっかけ: `gas-feedback-generate` プロジェクトで `clasp open` を実行したら `Unknown command` エラーになり、原因調査からclasp v3系でのコマンド体系の変化、さらに `clasp push` 時の別のエラー（ファイル名衝突）の原因調査までClaude Codeとの会話の中で行った。

## 1. clasp v2→v3でコマンドが用途別に分割された

インストールされていたclaspは3.3.0で、v2時代の `clasp open`（GASエディタをブラウザで開く）は廃止されており、代わりに用途ごとのサブコマンドに分かれていた。

- `clasp open-script` — GASエディタを開く（`clasp open`の直接の後継）
- `clasp open-logs` — 実行ログを開発者コンソールで開く
- `clasp open-credentials-setup` — スクリプトのGCPプロジェクトの認証情報ページを開く
- `clasp open-web-app` — デプロイ済みWebアプリを開く

一方 `clasp logs` は `tail-logs|logs` としてエイリアスがそのまま残っており、v2時代のコマンドが全部変わったわけではない。`clasp --help` で一覧を確認するのが確実。

## 2. `clasp push` の「マニフェストを上書きするか」警告の意味

```
? Manifest file has been updated. Do you want to push and overwrite? (y/N)
```

これは「GASエディタ側の `appsscript.json` の内容が、ローカルのファイルと異なる」ときに出る確認プロンプトで、`y` にするとGAS側のマニフェストがローカルの内容で上書きされる。

- 原因としてよくあるのは、GASエディタ上で関数を実行した際に必要なOAuthスコープが自動追記されていたり、Advanced Servicesをエディタ上のUIで有効化していたりするケース。
- 上書きしてよいか判断がつかない場合は、一度 `N` で止めて `clasp open-script` からマニフェストの中身を実際に見て、ローカルとの差分がないか確認してから進めるのが安全。

## 3. git worktreeを残したままclasp pushすると、ファイル名衝突エラーになる

`clasp push` で `A file with this name already exists in the current project: appsscript` というエラーが出た。原因は以下の組み合わせ。

- `.claspignore` が存在せず、`.clasp.json` の `skipSubdirectories` も `false` のため、claspがサブディレクトリまで再帰的にpush対象を探索していた。
- 過去の実装作業で使った `git worktree`（`.claude/worktrees/<branch-name>/` 配下）がまだ削除されずに残っており、その中にも独自の `appsscript.json` が存在していた。
- 結果、ルート直下の `appsscript.json` とworktree内の `appsscript.json` が、拡張子を除いた同じファイル名としてclaspに二重に認識され、衝突した。

`clasp status` でトラッキング対象ファイルの一覧を事前に確認すると、この手の「意図しないファイルが紛れ込んでいる」問題は事前に検知できる。

## 4. 対処法: `.claspignore` を用意してpush対象を明示的に絞る

`.claspignore` はgitignore的な記法でpush対象から除外するファイル/ディレクトリを指定できる。作成すると、claspのデフォルト除外設定（`.git`や`node_modules`など）を上書きする形になるため、必要なものは自分で全部書く必要がある。

```
**/**.git/**
.git/**
node_modules/**
.claude/**
.claspignore
.clasp.json
.gitignore
README.md
```

- `.claude/` を丸ごと除外しておけば、今回のようなworktreeやセッション用ファイルが増えても push対象に紛れ込まなくなる。
- `.claspignore` 自体はプロジェクトの運用ルールなのでGitにコミットしておいてよい（`.clasp.json` はスクリプトIDを含むため引き続き`.gitignore`対象）。

## 5. まとめ

- claspはメジャーバージョンが上がるとコマンド体系が変わることがあるので、エラーが出たら素直に `clasp --help` で現在のコマンド一覧を見るのが早い。
- `git worktree` を使った作業が終わったら、GASプロジェクトのようにpush対象を全ファイル走査するツールと組み合わせている場合、worktreeの残骸が思わぬ形で悪さをする。`.claspignore` で除外設定をしておくか、使い終わったworktreeはこまめに削除するのが望ましい。
