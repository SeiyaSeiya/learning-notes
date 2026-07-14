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
