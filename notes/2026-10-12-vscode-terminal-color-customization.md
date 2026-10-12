# VS Codeのターミナルの色を変更する方法

## 概要
VS Codeの統合ターミナルの配色を変えたくなり、変更方法を整理した。大きく分けて「テーマ全体を変える」「settings.jsonで個別に指定する」「補正やタブ色などのオプションを調整する」の3通りがある。

## 1. カラーテーマ全体を変更する
ターミナルの配色はエディタのカラーテーマに連動する。

* `Cmd + K` → `Cmd + T`（Windowsは `Ctrl + K` → `Ctrl + T`）でテーマ一覧を開いて選ぶ。
* Solarized、Dracula、Catppuccinなど特定の配色にしたい場合は、拡張機能のテーマをインストールするのが手軽。

## 2. settings.jsonで個別にカスタマイズする
コマンドパレット（`Cmd + Shift + P`）で「Preferences: Open User Settings (JSON)」を開き、`workbench.colorCustomizations` に追記する。

```json
{
  "workbench.colorCustomizations": {
    "terminal.background": "#1e1e2e",
    "terminal.foreground": "#cdd6f4",
    "terminalCursor.foreground": "#f5e0dc",
    "terminal.selectionBackground": "#45475a",

    "terminal.ansiRed": "#f38ba8",
    "terminal.ansiGreen": "#a6e3a1",
    "terminal.ansiYellow": "#f9e2af",
    "terminal.ansiBlue": "#89b4fa",
    "terminal.ansiMagenta": "#f5c2e7",
    "terminal.ansiCyan": "#94e2d5"
  }
}
```

### 主なキー
| キー | 内容 |
|---|---|
| `terminal.background` / `terminal.foreground` | 背景色・文字色 |
| `terminalCursor.foreground` | カーソルの色 |
| `terminal.selectionBackground` | 選択範囲の背景色 |
| `terminal.ansi〇〇`（Black, Red, Green, Yellow, Blue, Magenta, Cyan, White） | ANSI標準8色 |
| `terminal.ansiBright〇〇` | 明るい側の8色。`ls`の色分けやgitの出力などに使われる |

### 特定のテーマにだけ適用する
テーマ名を括弧で囲んでネストする。

```json
"workbench.colorCustomizations": {
  "[Default Dark Modern]": {
    "terminal.background": "#101010"
  }
}
```

## 3. その他のオプション
* **色が指定どおりに出ないとき**: `terminal.integrated.minimumContrastRatio`（既定値4.5）が、背景と文字色のコントラストが低いときに色を自動補正している。`1`にすると補正が無効になる。
* **ターミナルのタブごとの色**: タブを右クリック →「Change Color...」。

## 便利なTips
* どのキーがあるか分からないときは、コマンドパレットで「Developer: Generate Color Theme From Current Settings」を実行すると、現在の全色設定が一覧で出る。
* settings.jsonで `"terminal.` と入力すると補完候補が出る。
* 変更は保存すると即座に反映される。

## 関連メモ
* [2026-07-13: VS CodeでのClaude Code（ターミナル版）運用と効率化](2026-07-13-claude-code-cli-and-vscode-integration.md)
* [2026-08-01: ターミナルの文字列をマウスなしでコピーする方法](2026-08-01-terminal-copy-without-mouse.md)
