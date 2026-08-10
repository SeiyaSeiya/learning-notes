#!/bin/bash
#
# learning-notes リポジトリの未コミット変更を検知し、Claude Code CLI (headless)
# にコミットメッセージ生成 + commit を行わせ、成功を確認した上で push するスクリプト。
#
# launchd (LaunchAgent) から呼ばれることを想定しているが、
# `bash scripts/learning-notes-auto-commit.sh` として手動実行しても同じ結果になる。
#
# 事前準備: このディレクトリの learning-notes-auto-commit.env.example を
# learning-notes-auto-commit.env としてコピーし、環境に合わせて値を設定すること。
# (このファイルはユーザー固有の情報を含むため .gitignore 対象で、リポジトリにはcommitされない)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/learning-notes-auto-commit.env"

if [ ! -f "$ENV_FILE" ]; then
  echo "ERROR: env file not found: $ENV_FILE" >&2
  echo "  ${SCRIPT_DIR}/learning-notes-auto-commit.env.example をコピーして作成してください。" >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

if [ -z "${REAL_HOME:-}" ]; then
  echo "ERROR: REAL_HOME is not set in $ENV_FILE" >&2
  exit 1
fi

REPO_DIR="$REAL_HOME/Projects/learning-notes"
BRANCH="main"
GIT="/usr/bin/git"
CLAUDE_BIN="/opt/homebrew/bin/claude"
LOG_DIR="$REAL_HOME/.claude/cron-logs"
LOG_FILE="$LOG_DIR/learning-notes-auto-commit.log"

# launchd はPATH等の環境変数をほぼ持たないため、必要なものを明示的に設定する。
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export HOME="$REAL_HOME"

mkdir -p "$LOG_DIR"

log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >>"$LOG_FILE"
}

log "===== run start (pid $$) ====="

if [ ! -x "$GIT" ]; then
  log "ERROR: git not found at $GIT"
  exit 1
fi
if [ ! -x "$CLAUDE_BIN" ]; then
  log "ERROR: claude not found at $CLAUDE_BIN"
  exit 1
fi
if [ ! -d "$REPO_DIR/.git" ]; then
  log "ERROR: repo not found at $REPO_DIR"
  exit 1
fi

cd "$REPO_DIR" || {
  log "ERROR: failed to cd into $REPO_DIR"
  exit 1
}

# 幽霊ロック（stale lock）の自動解消
# git操作の異常終了（rebase/amend中の強制終了等）で .git/index.lock や .git/HEAD.lock が
# 残ると、以後のgit commitが理由不明のまま失敗し続ける。
# 一定時間以上前のタイムスタンプで、かつ実際に稼働中のgitプロセスが無い場合のみ
# 「幽霊ロック」とみなして自動削除する。
STALE_LOCK_THRESHOLD_SEC=600  # 10分

remove_stale_lock_if_safe() {
  local lock_file="$1"
  [ -f "$lock_file" ] || return 0

  local lock_mtime now age
  lock_mtime="$(stat -f %m "$lock_file" 2>/dev/null)"
  if [ -z "$lock_mtime" ]; then
    log "WARN: failed to stat $lock_file; skipping stale-lock check for this file."
    return 0
  fi

  now="$(date +%s)"
  age=$((now - lock_mtime))

  if [ "$age" -lt "$STALE_LOCK_THRESHOLD_SEC" ]; then
    log "LOCK PRESENT: $lock_file is only ${age}s old (< ${STALE_LOCK_THRESHOLD_SEC}s). Another git process may genuinely be running; leaving it alone."
    return 0
  fi

  if pgrep -f "git.*${REPO_DIR}" >/dev/null 2>&1; then
    log "WARN: $lock_file is ${age}s old but a git process referencing $REPO_DIR is still running. Not deleting (not safe)."
    return 0
  fi

  log "STALE LOCK: removing $lock_file (age ${age}s, no active git process found for $REPO_DIR)."
  rm -f "$lock_file"
}

remove_stale_lock_if_safe "$REPO_DIR/.git/index.lock"
remove_stale_lock_if_safe "$REPO_DIR/.git/HEAD.lock"

# 安全策: mainブランチ以外では絶対に何もしない
current_branch="$("$GIT" rev-parse --abbrev-ref HEAD 2>&1)"
if [ "$current_branch" != "$BRANCH" ]; then
  log "SKIP: current branch is '$current_branch' (expected '$BRANCH'). No action taken."
  exit 0
fi

# 追跡ファイルの変更・未追跡ファイルを問わず未コミットの変更を検知
status_output="$("$GIT" status --porcelain)"
if [ -z "$status_output" ]; then
  log "NO CHANGE: working tree is clean. Nothing to do."
  exit 0
fi

log "CHANGES DETECTED:"
printf '%s\n' "$status_output" >>"$LOG_FILE"

before_head="$("$GIT" rev-parse HEAD)"

# Claude Code には「コミットメッセージ生成 + git add + git commit」のみを行わせる。
# push はこのスクリプト自身が固定コマンドで実行するため、Claudeにpush権限は与えない
# (force push など想定外の引数が混入する余地を構造的になくすため)。
claude_output="$("$CLAUDE_BIN" -p \
  --permission-mode default \
  --allowedTools "Bash(git add:*)" "Bash(git commit:*)" "Bash(git status:*)" "Bash(git diff:*)" "Bash(git log:*)" \
  --disallowedTools "Bash(git push:*)" "Bash(git reset:*)" "Bash(git checkout:*)" "Bash(git branch:*)" "Bash(git rebase:*)" \
  --output-format text \
  "カレントディレクトリのGitリポジトリに未コミットの変更があります。\`git status\` と \`git diff\` で変更内容を確認し、その内容を要約した簡潔な日本語のコミットメッセージを考えてください。変更されたファイル・新規追加されたファイルをすべて \`git add\` した上で、そのコミットメッセージで \`git commit\` を実行してください。pushは行わないでください。実行後は作成したコミットメッセージのみを出力してください。" \
  2>&1)"
claude_exit=$?

log "claude exit code: $claude_exit"
log "claude output (truncated): $(printf '%s' "$claude_output" | tr '\n' ' ' | cut -c1-800)"

# claudeコマンドが失敗した場合、ログファイルだけでなくターミナルにも
# はっきり分かる形で出力する（手動実行時に気づけるようにするため）。
if [ "$claude_exit" -ne 0 ]; then
  echo "" >&2
  echo "⚠️  claude コマンドが失敗しました (exit $claude_exit)" >&2
  if printf '%s' "$claude_output" | grep -qi "not logged in"; then
    echo "⚠️  Claude Code CLI が未ログインです。次を実行して再ログインしてください:" >&2
    echo "    claude /login" >&2
  else
    printf '%s\n' "$claude_output" >&2
  fi
  echo "" >&2
fi

after_head="$("$GIT" rev-parse HEAD)"

if [ "$before_head" = "$after_head" ]; then
  log "FAILURE: no new commit was created (HEAD unchanged: $before_head). Push is skipped."
  remaining_status="$("$GIT" status --porcelain)"
  if [ -n "$remaining_status" ]; then
    log "current working tree status:"
    printf '%s\n' "$remaining_status" >>"$LOG_FILE"
  fi
  log "===== run end (failure) ====="
  exit 1
fi

log "COMMIT SUCCESS: $before_head -> $after_head"

remaining_status="$("$GIT" status --porcelain)"
if [ -n "$remaining_status" ]; then
  log "WARNING: working tree not fully clean after commit (uncommitted leftovers):"
  printf '%s\n' "$remaining_status" >>"$LOG_FILE"
fi

# push は固定コマンドのみ。force push は絶対に行わない。
push_output="$("$GIT" push origin "$BRANCH" 2>&1)"
push_exit=$?

if [ $push_exit -eq 0 ]; then
  log "PUSH SUCCESS: $(printf '%s' "$push_output" | tr '\n' ' ')"
  log "===== run end (success) ====="
  exit 0
else
  log "PUSH FAILURE (exit $push_exit): $(printf '%s' "$push_output" | tr '\n' ' ')"
  log "Note: commit $after_head remains locally uncommitted-to-remote. Working tree itself is not broken."
  log "===== run end (push failure) ====="
  exit 1
fi
