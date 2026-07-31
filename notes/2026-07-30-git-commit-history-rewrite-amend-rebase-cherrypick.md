# 過去のcommitを修正する方法（amend / rebase -i / reset+cherry-pick）と、force pushでの反映のさせ方

## 概要
- **学んだきっかけ**: 前日の学習メモ（BigQueryのビュー→テーブル化に関するメモ）の内容に誤りがあったことに後から気づき、修正した上でリモートを上書きした作業。直前1コミットのみの修正だったが、「2つ以上前のコミットを直す場合はどうするか」「過去に使った`reset`＋`cherry-pick`方式との違いは何か」という点も合わせて整理する。

## 目次

1. [直前1コミットのみを直す：`git commit --amend`](#1-直前1コミットのみを直すgit-commit---amend)
2. [amendしてもcommit日時の表示が変わらない理由](#2-amendしてもcommit日時の表示が変わらない理由)
3. [2つ以上前のコミットを直す：`git rebase -i`](#3-2つ以上前のコミットを直すgit-rebase--i)
4. [別解：`git reset`＋新ブランチ＋`git cherry-pick`との違い](#4-別解git-reset新ブランチgit-cherry-pickとの違い)
5. [force pushに関する注意点](#5-force-pushに関する注意点)
6. [まとめ：状況ごとの使い分け](#6-まとめ状況ごとの使い分け)

## 1. 直前1コミットのみを直す：`git commit --amend`

修正したいコミットが**直前（HEAD）のコミット1つだけ**であれば、最もシンプル。

```bash
# ファイルを修正した後
git add -A
git commit --amend --no-edit   # コミットメッセージは変えずに内容だけ差し替え
git push --force origin main   # 既にpush済みの場合は force が必須
```

今回のケースでは、修正したい変更が独立した1コミット（該当ファイルの新規追加のみ）だったため、この方法で対応できた。`git log --oneline`で対象コミットがHEADであること、`git log origin/main..main`で余計な差分が無いことを事前に確認しておくと安全。

## 2. amendしてもcommit日時の表示が変わらない理由

`git commit --amend`後も`git log`のデフォルト表示（`Date:`）が元のままに見えることがある。これはコミットに**2種類の日時**があるため。

- **AuthorDate**：最初にその変更が作られた日時。`git log`のデフォルトの`Date:`はこちら。
- **CommitDate**：そのコミットオブジェクトが最後に書き換えられた日時。`amend`のたびに更新される。

`--amend`はデフォルトでAuthorDateを引き継ぐ仕様のため、`--no-edit`で実行すると表示上の日時は変わらないように見える。実際には裏でCommitDateはきちんと更新されている。

```bash
git log -1 --pretty=fuller <commit>
# AuthorDate: 元の日時（そのまま）
# CommitDate: amendした時刻（更新される）
```

表示上の日時も揃えたい場合は`--reset-author`を付ける。

```bash
git commit --amend --no-edit --reset-author
```

## 3. 2つ以上前のコミットを直す：`git rebase -i`

直したいコミットがHEADより前にある場合は、インタラクティブリベースを使う。

1. 対象コミットの1つ前のハッシュ（または`HEAD~n`）を確認：`git log --oneline`
2. `git rebase -i <対象コミットの1つ前>`
3. エディタのtodoリストで、対象コミット行の`pick`を`edit`に変更して保存
4. Gitがそのコミット時点まで巻き戻して停止するので、ファイルを修正
5. `git add <修正ファイル>`
6. `git commit --amend --no-edit`（必要なら`--reset-author`も）
7. `git rebase --continue` → 後続コミットが修正後の内容の上に順に再適用される
8. 後続コミットが同じ箇所を触っていた場合はコンフリクトが出るので、その都度解消して`--continue`
9. 完了後、`git push --force origin main`

## 4. 別解：`git reset`＋新ブランチ＋`git cherry-pick`との違い

以前は「対象コミットの手前まで`git reset`し、新しい作業ブランチを切って、元のコミットを1つずつ`cherry-pick`し直す」という方法を使っていた。`rebase -i`との関係は次の通り。

**結論：処理内容としてはほぼ同じ。`rebase -i`は、この手動手順（reset→cherry-pickの繰り返し）を1つのコマンドに自動化したもの。**

`rebase -i <base>`の内部動作は、大まかに「`<base>`の位置でdetached HEADになる（＝resetに相当）」→「対象コミットを1つずつ順に再適用する（＝cherry-pickに相当）」→「`edit`指定したコミットで一時停止し、修正後`--continue`で残りも再適用」→「全て終わったら元のブランチ（例：main）のポインタを自動で最終コミットへ進める」という流れ。

違いは主に利便性の部分。

- **ブランチポインタの扱い**：手動方式は作業用ブランチ上で全て終わらせてから、最後に`git branch -f main 作業ブランチ`のようにmainを付け替える一手間が必要。`rebase -i`は同等の安全性（失敗時は`git rebase --abort`で元通り）を保ちつつ、成功時の最終的なブランチ付け替えまで自動でやってくれる。
- **計画の立て方**：手動cherry-pick方式は1つずつコマンドを打ちながらその都度判断できる（このコミットは省く、順番を入れ替える、など）。`rebase -i`はエディタのtodoリスト（`pick`/`edit`/`squash`/`drop`など）で先に計画を書いてから実行する。できることの範囲はほぼ同等だが、1コミットを分割するなど複雑な作業をしたい場合は、手動cherry-pick方式の方が直感的に感じることもある。

コンフリクト解消の流れ（都度手で直して`--continue`）と、最終的にforce pushが必要になる点は両者共通。

## 5. force pushに関する注意点

- `force push`はブランチの参照（ポインタ）を書き換えるだけであり、既にリモートにpushされていたコミットオブジェクト自体は、リモート側にしばらく「ダングリングコミット」として残る可能性がある。ハッシュを知っている人がいれば一時的にアクセスできてしまう余地は完全にはゼロにならない。
- 修正したい内容の性質によって緊急性は変わる。単なる記載ミス程度であれば緊急性は低いが、パスワードやAPIキーなど**認証情報そのもの**が漏れた場合は、force pushだけで満足せず**該当の認証情報自体をローテーション（無効化・再発行）**する方が確実。必要であればGitHubサポートに完全パージを依頼することも可能。
- 作業環境によってはSSHの認証情報（鍵）が無く`git push`自体が実行できないことがある（例：サンドボックス化された実行環境）。その場合は、SSH鍵を持つ本来の作業マシン側で`git push --force origin main`を実行する必要がある。
- このリポジトリは`launchd`により毎日6:30に自動commit・pushされる設定になっている（詳細は[2026-07-14のメモ](2026-07-14-launchd-auto-commit.md)）。履歴を書き換えた直後は、次回の自動実行より先に手動でforce pushを済ませておかないと、自動commit側とのdiverge（食い違い）でこじれる可能性がある。

## 6. まとめ：状況ごとの使い分け

| 状況 | 使う方法 |
|---|---|
| 直したいのが直前（HEAD）の1コミットだけ | `git commit --amend` |
| 直したいのが2つ以上前のコミット | `git rebase -i`（対象コミットを`edit`指定） |
| 同じ修正内容が複数コミットに繰り返し登場している | 1つずつ直すより`git filter-repo --replace-text`やBFG Repo-Cleanerで履歴全体を一括置換 |
| コミット単位でより自由に取捨選択・順序入れ替えしたい | `git reset`＋新ブランチ＋`git cherry-pick`（`rebase -i`と等価だが手動で細かく制御できる） |

いずれの方法も、リモートに既にpush済みの履歴を書き換えるため、最終的には`git push --force`が必要になる。

## 関連メモ

- [2026-07-09: git worktree と checkout の違い](2026-07-09-git-worktree-and-checkout.md) — git remoteの基本的な仕組み（push対象の決まり方、SSH URLの意味など）
- [2026-07-14: launchdによるlearning-notesリポジトリの自動commit・push設定](2026-07-14-launchd-auto-commit.md) — このリポジトリの自動commit・push運用の詳細
- [2026-07-29: BigQueryでビューからテーブルを新規作成しようとして「マテリアライズド ビューのレプリカ作成」画面に迷い込んだ話](2026-07-29-bigquery-create-table-from-view-materialized-replica-pitfall.md) — 今回のcommit修正のきっかけとなった元メモ
