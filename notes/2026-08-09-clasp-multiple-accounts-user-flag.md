# claspで複数のGoogleアカウントを切り替える方法（Chromeプロファイルのような運用を`--user`で実現する）

- 学んだきっかけ: Chromeブラウザのプロファイル機能のように、複数のターミナルからそれぞれ別のGoogleアカウントで同時に`clasp push`したい場面を想定し、claspに同様の仕組みがあるかClaude（Cowork）に相談した。

## 1. 結論: `--user`オプションが公式のマルチアカウント機能

claspには`--user <name>`という名前付きクレデンシャルの仕組みがあり、これがChromeプロファイルに相当する。

```bash
# アカウントごとに名前を付けてログイン（初回のみ）
clasp login --user work
clasp login --user personal
```

以降、コマンドに`--user <name>`を付けるとそのアカウントとして実行される。`push`/`pull`/`run`など全コマンドで使えるグローバルオプション。

```bash
# ターミナルA（workアカウントのプロジェクト）
cd ~/projects/work-script
clasp push --user work

# ターミナルB（personalアカウントのプロジェクト）
cd ~/projects/personal-script
clasp push --user personal
```

## 2. 旧来の`--auth <file>`は非推奨

以前は個別の`.clasprc.json`ファイルを`--auth`（`-A`）で直接指定する方法もあったが、現在の公式READMEでは**非推奨**と明記されており、「複数アカウントの管理には`--user`を使うこと」と案内されている。新規に組むなら`--user`一択でよい。

## 3. 運用を楽にする工夫（シェルエイリアス）

毎回`--user`を打つのが面倒なら、`~/.zshrc`（or `.bashrc`）にエイリアスを用意しておくと、ターミアルごとに「このターミナル＝このアカウント」という運用にできる。

```bash
alias clasp-work='clasp --user work'
alias clasp-personal='clasp --user personal'
```

## 4. 注意点: 同時実行時の競合リスクは実質ゼロ

`--user`の認証情報は内部的にホームディレクトリ配下の設定ファイルに名前付きキーで保存される形式のため、理論上は「同じユーザー名」で複数プロセスから同時にトークン更新が走るとファイル書き込みが競合する可能性はゼロではない。ただし今回のように「アカウントごとに別ターミナル・別キーを使う」運用であれば、そもそも異なるキーへのアクセスになるため実質的に問題は起きない。

完全に物理分離したい（例: ファイルレベルで絶対に混ざらないようにしたい）場合は、旧来のように`.clasprc.json`をアカウントごとにコピーしてホームディレクトリ自体を分ける（別ユーザー/コンテナで動かす）方法も選択肢としてはあるが、通常の用途では`--user`で十分。

## 5. まとめ

- claspの複数アカウント運用は、Chromeのプロファイル切り替えと同じ発想で`clasp login --user <name>`→以降`--user <name>`を都度指定、で実現できる。
- 旧方式の`--auth`は非推奨なので使わない。
- ターミナル・プロジェクトディレクトリごとにアカウント用のエイリアスを固定しておくと運用がシンプルになる。
- 関連メモ: [2026-07-14: clasp v3のコマンド変更と、git worktreeが引き起こす.claspignoreの落とし穴](2026-07-14-clasp-v3-and-claspignore.md)、[2026-08-06: claspでスタンドアロン型のGASプロジェクトを新規作成し、Hello Worldをpushするまで](2026-08-06-clasp-standalone-create-and-push.md)
