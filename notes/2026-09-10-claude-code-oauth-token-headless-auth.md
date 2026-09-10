# headless実行（`claude -p`）の認証切れを防ぐ：長期OAuthトークン（`CLAUDE_CODE_OAUTH_TOKEN`）による無人実行対応

- 学んだきっかけ: [2026-08-10のメモ](2026-08-10-claude-cli-not-logged-in-auto-commit-failure.md)で、`learning-notes-auto-commit.sh`内の`claude -p`（headlessモード）がログインセッション切れで`Not logged in · Please run /login`エラーを起こした際、その場では`claude /login`での対話的な再ログインしか対処できなかった（メモの最後で「根本的な自動再認証の仕組みまでは入れていない」と書いた課題）。今回、launchdで無人実行しているスクリプトが今後また同じ理由で無言で失敗し続けるのを防ぐため、恒久対応となりうる長期トークンの方式についてClaudeに教えてもらった。

## 1. そもそもの問題: headlessモードは対話的な再ログインができない

- `claude -p "..."`のようなheadless呼び出しは、非対話的な実行が前提のCLI。
- 通常の`claude`コマンド（対話型REPL）でのログイン（`/login`）はブラウザを介した認証フローを必要とするが、headlessモードはその場でブラウザを開いて認証を待つようなことができない。
- そのため、通常ログインのセッションが何らかの理由（トークンの有効期限切れ、別セッションでのログアウトなど）で切れると、headlessモードは「未ログイン」エラーを返して即終了するだけになり、launchdのような無人スケジュール実行では誰も気づかないまま失敗し続けるリスクがある。

## 2. 対処法: `claude setup-token`で長期トークンを発行し、環境変数として渡す

- `claude setup-token`を一度だけ対話的に実行すると、有効期限が1年のOAuthトークンを取得できる。
- このトークンを`CLAUDE_CODE_OAUTH_TOKEN`という環境変数としてheadless実行の環境に渡しておくと、`claude -p`はそのトークンで認証されるため、通常ログインのセッション切れの影響を受けなくなる。

```bash
# 対話的に一度だけ実行してトークンを取得する
claude setup-token

# 取得したトークンを、スクリプトの実行環境（.env等）に設定する
export CLAUDE_CODE_OAUTH_TOKEN=<発行されたトークン>
```

- `learning-notes-auto-commit.sh`の場合、既にユーザー固有の設定を`scripts/learning-notes-auto-commit.env`（`.gitignore`対象）に置く運用になっているため、ここに`CLAUDE_CODE_OAUTH_TOKEN`を追加するのが自然な導線になりそう。

## 3. `ANTHROPIC_API_KEY`との違い

- 非対話的な認証手段としてはもう一つ、Claude ConsoleのAPIキー（`ANTHROPIC_API_KEY`）を使う方法もある。
- `CLAUDE_CODE_OAUTH_TOKEN`は「Claude Codeの利用契約（サブスクリプション）に紐づく認証」で、`ANTHROPIC_API_KEY`は「従量課金のAPI利用に紐づく認証」という位置づけの違いがある。普段使っているClaude Codeの契約をそのままheadless実行にも使いたい場合は、素直に`CLAUDE_CODE_OAUTH_TOKEN`の方が筋が良さそう。

## 4. macOSのKeychainとの関係

- 通常のログイン状態はmacOSのKeychainに保存されるが、Keychainにアクセスできない状況（launchdのバックグラウンドジョブなど、SSHセッションに近い扱いになる場合）では、認証情報が`~/.claude/.credentials.json`にフォールバックする、という話も出てきた。
- launchdのような「ユーザーが実際にログインしている画面の外」で動くジョブは、通常ログインのセッションを前提にすると根本的に相性が悪い可能性がある。長期トークンを環境変数で明示的に渡す方式の方が、この手のバックグラウンド実行とは相性が良いはず。

## 5. 今後の運用への反映（TODO）

- [ ] `claude setup-token`を実行して長期トークンを発行する。
- [ ] `scripts/learning-notes-auto-commit.env`に`CLAUDE_CODE_OAUTH_TOKEN`を追記する（`.env.example`側にも変数名だけコメントで残しておく）。
- [ ] 反映後、`bash scripts/learning-notes-auto-commit.sh`を手動実行し、`claude -p`が正常に動くことを確認する。
- [ ] 有効期限は1年なので、来年同じ時期に再発行が必要になることをどこかに書き残しておく（このメモ自体がその役割を兼ねる）。

## まとめ

- headlessモード（`claude -p`）はログインセッション切れ時に対話的な再ログインができず、無人実行のバッチが無言で失敗し続けるリスクがある。
- `claude setup-token`で発行できる1年有効の長期OAuthトークンを`CLAUDE_CODE_OAUTH_TOKEN`環境変数として渡すことで、通常ログインのセッション切れに影響されない認証にできる。
- `ANTHROPIC_API_KEY`（従量課金API）とは位置づけが異なり、Claude Codeの契約をそのまま使いたい場合は`CLAUDE_CODE_OAUTH_TOKEN`が適している。
- launchdのようなバックグラウンド実行はKeychain前提の通常ログインと相性が悪い可能性があるため、長期トークンの明示的な受け渡しが恒久対応として有効。
