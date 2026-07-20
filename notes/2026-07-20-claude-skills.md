# Claude Skillsとは何か：概要と使い方

- 学んだきっかけ: Coworkでこのlearning-notesリポジトリを操作中に、Cowork/Claude Codeが自動で読み込んでいる`docx`/`pptx`/`xlsx`/`pdf`/`schedule`などのSkillsについて、その仕組み自体を調べた。

## 1. Skillsとは何か

- Skillは「指示（Markdown）＋任意のスクリプト・参照資料」を1つのフォルダにまとめたもので、Claudeが必要な時に自動で読み込んで使う拡張機能。
- 通常のプロンプト（その場限りの指示）と違い、一度作れば毎回同じ指示を書かずに済む「再利用可能な手順書」。新人に渡すオンボーディングガイドに近い。
- Anthropicが用意した事前構築済みSkill（PowerPoint/Excel/Word/PDF作成用の`pptx`/`xlsx`/`docx`/`pdf`）と、自分で作るカスタムSkillの2種類がある。

## 2. 構造：SKILL.mdとYAML frontmatter

Skillは以下のようなディレクトリ構造を持つ。

```
pdf-processing/
├── SKILL.md          # 必須。指示の本体
├── FORMS.md           # 任意。詳細ガイド
├── REFERENCE.md       # 任意。APIリファレンス等
└── scripts/
    └── fill_form.py   # 任意。実行用スクリプト
```

`SKILL.md`は必ずYAML frontmatterで始まり、`name`と`description`が必須項目。

```yaml
---
name: pdf-processing
description: Extract text and tables from PDF files, fill forms, merge documents. Use when working with PDF files or when the user mentions PDFs, forms, or document extraction.
---
```

- `name`: 64文字以内、小文字・数字・ハイフンのみ、「anthropic」「claude」といった予約語は使用不可。
- `description`: 1024文字以内。「何をするか」と「いつ使うべきか」の両方を書く必要がある。Claudeがどのタスクでこのskillを使うか判定する際、実際に参照するのはこの`description`だけ。

## 3. 動作の仕組み：progressive disclosure（段階的開示）

Skillは3段階でしか読み込まれず、使わない部分はコンテキスト（トークン）を消費しない設計になっている。

| レベル | 読み込まれるタイミング | 内容 | コスト |
|---|---|---|---|
| レベル1: メタデータ | 起動時に常に | `name`と`description`のみ | 1skillあたり約100トークン |
| レベル2: 本文 | Claudeがそのskillが必要と判断した時 | `SKILL.md`本体（指示・手順） | 5,000トークン未満程度 |
| レベル3: 追加資料・スクリプト | 本文中で参照され、実際に必要になった時のみ | 追加のMarkdown、参照資料、実行スクリプト | 使わなければ0 |

- レベル3のスクリプトはClaudeがbash経由で実行するだけで、スクリプトのコード自体はコンテキストに読み込まれない（出力結果だけが読み込まれる）。そのため巨大なリファレンスやスクリプトを同梱しても、使わない限りコストはゼロ。
- 実際の流れ: ①起動時に全skillの`name`/`description`がシステムプロンプトに載る → ②ユーザーの依頼内容と`description`が一致すると判断したら、Claudeが`cat SKILL.md`のようにbashで本文を読む → ③本文が他ファイルを参照していれば、必要な時だけそれも読む → ④スクリプトがあれば実行し、出力だけを受け取る。

## 4. 使える場所と管理単位の違い

Skillsは複数の製品で使えるが、置き場所と共有範囲が製品ごとに異なる点に注意。

- **claude.ai**: 事前構築済みSkillはドキュメント作成時に自動で有効。カスタムSkillはSettings > FeaturesからZIPでアップロード。個人単位で、組織管理者による一元管理はできない。
- **Claude API**: `container`パラメータに`skill_id`（`pptx`/`xlsx`/`docx`/`pdf`または自作ID）を指定し、code execution toolと組み合わせて使う。カスタムSkillはワークスペース全体で共有される。ネットワークアクセスなし、実行時のパッケージ追加インストールも不可。
- **Claude Code / Cowork**: ファイルシステムベース。個人用は`~/.claude/skills/`、プロジェクト用は`.claude/skills/`に置くだけで自動的に発見・使用される。Claude Code Pluginsを使えば配布も可能。事前構築済みのドキュメント系Skillはこちらには標準搭載されないこともある（今のCoworkセッションでは`docx`/`pptx`/`xlsx`/`pdf`が使えている）。
- 重要な注意点: **カスタムSkillは各サーフェス間で同期されない**。claude.aiにアップロードしたものはAPIには反映されず、逆も同様。Claude Codeのskillはファイルシステム上の別物。

## 5. 今回のCoworkセッションでの実例

このセッションで実際に読み込まれていた（`<available_skills>`一覧に出ていた）skillの例:

- `docx` / `pptx` / `xlsx` / `pdf`: Word・PowerPoint・Excel・PDFファイルの作成・編集を扱うたびに自動でトリガーされる、Anthropic提供のドキュメント系skill。
- `schedule`: 「毎朝」「1時間後に」のような定期実行・リマインダーの依頼で使われる。
- `skill-creator`: 新しいskillを作ったり、既存skillの性能を評価・最適化する用途。
- 呼び出し方はシンプルで、Claude側は`Skill`ツールに`skill: "docx"`のようにskill名だけを渡す。渡すとそのskillのSKILL.md本文がプロンプトとして展開され、以降はその指示に従って作業する（ユーザー側が明示的に指定しなくても、依頼内容から自動でマッチする設計）。

## 6. セキュリティ上の注意

- Skillは「指示＋実行可能なコード」をClaudeに与える仕組みなので、信頼できない出典のskillを入れると、記載された目的と異なる形でツールやbashコマンドを悪用される・データが外部に漏える等のリスクがある。
- 原則、**自分で作ったskillか、Anthropic公式のskillのみ**を使う。出典が不明なskillを使う場合は、`SKILL.md`本文・同梱スクリプト・外部URLへのアクセスの有無を必ず事前に確認する。

## 7. まとめ：プロンプトとの違い

- プロンプト: その場限りの指示。会話ごとに毎回書く必要がある。
- Skill: 一度ファイルとして作れば、条件（`description`との一致）に応じてClaudeが自動的に読み込み、繰り返し使える「手順書」。加えてスクリプトという形で決定論的な処理も同梱できる点がプロンプトにはない強み。
