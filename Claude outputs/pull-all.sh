#!/usr/bin/env bash
#
# pull-all.sh
#
# 指定ディレクトリ（デフォルト: ~/Projects）直下にある各Gitリポジトリに対して
# 自動で git pull を実行するスクリプト。
#
# 動作:
#   - Projects直下の「1階層目」のフォルダだけを対象にする（サブフォルダの中は探索しない）
#   - .git が無いフォルダは黙ってスキップ
#   - upstream（追跡ブランチ）が設定されていないリポジトリはスキップして警告
#   - 未コミットの変更がある場合は自動で
#       git stash push -u  →  git pull  →  git stash pop
#     という手順で退避・復元する
#   - stash pop でコンフリクトが起きた場合は、stashを消さずに残して警告表示のみ行う
#     （中身は失われないので、後で手動で `git stash list` / `git stash pop` して解決する）
#   - 各リポジトリの処理が失敗しても止まらず、最後にまとめて結果を表示する
#
# 使い方:
#   ./pull-all.sh                  # ~/Projects を対象に実行
#   ./pull-all.sh /path/to/dir     # 対象ディレクトリを指定して実行
#
# 実行権限の付与:
#   chmod +x pull-all.sh
#
set -uo pipefail

# ── 設定 ──────────────────────────────────────────────
TARGET_DIR="${1:-$HOME/Projects}"

# 色付け（ターミナルがカラー非対応でも壊れないようにフォールバック）
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'
  C_RED=$'\033[31m'; C_BLUE=$'\033[34m'; C_BOLD=$'\033[1m'
else
  C_RESET=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_BLUE=""; C_BOLD=""
fi

# ── 前準備 ──────────────────────────────────────────────
if [[ ! -d "$TARGET_DIR" ]]; then
  echo "${C_RED}エラー: ディレクトリが見つかりません: $TARGET_DIR${C_RESET}" >&2
  exit 1
fi

declare -a UPDATED=()
declare -a UP_TO_DATE=()
declare -a STASHED_OK=()
declare -a STASH_CONFLICT=()
declare -a NO_UPSTREAM=()
declare -a NOT_A_REPO=()
declare -a FAILED=()

echo "${C_BOLD}対象ディレクトリ: $TARGET_DIR${C_RESET}"
echo "----------------------------------------"

# ── メイン処理（直下のフォルダのみ、1階層）───────────────
shopt -s nullglob
for dir in "$TARGET_DIR"/*/; do
  repo="${dir%/}"
  name="$(basename "$repo")"

  if [[ ! -d "$repo/.git" ]]; then
    NOT_A_REPO+=("$name")
    continue
  fi

  echo "${C_BLUE}▶ $name${C_RESET}"

  # サブシェルでcdして安全に処理（本体のカレントディレクトリを汚さない）
  (
    cd "$repo" || exit 2

    # detached HEAD などブランチが無い状態はスキップ
    branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null)"
    if [[ -z "$branch" ]]; then
      echo "  ${C_YELLOW}スキップ: ブランチにいません（detached HEADなど）${C_RESET}"
      exit 3
    fi

    # upstream（追跡ブランチ）が無い場合はpullできないのでスキップ
    if ! git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1; then
      echo "  ${C_YELLOW}スキップ: リモート追跡ブランチが設定されていません${C_RESET}"
      exit 4
    fi

    dirty=false
    if [[ -n "$(git status --porcelain)" ]]; then
      dirty=true
    fi

    stashed=false
    if [[ "$dirty" == true ]]; then
      stash_msg="auto-pull-stash $(date '+%Y-%m-%d %H:%M:%S')"
      if git stash push -u -m "$stash_msg" >/dev/null 2>&1; then
        stashed=true
        echo "  未コミットの変更を退避しました（stash）"
      else
        echo "  ${C_RED}エラー: stashに失敗しました。pullは行いません${C_RESET}"
        exit 5
      fi
    fi

    if git pull --ff-only 2>&1 | sed 's/^/  /'; then
      pull_ok=true
    else
      pull_ok=false
    fi

    if [[ "$stashed" == true ]]; then
      if git stash pop >/dev/null 2>&1; then
        echo "  退避していた変更を復元しました"
      else
        echo "  ${C_RED}警告: stash pop でコンフリクトが発生しました。変更はstashに残っています（git stash list で確認）${C_RESET}"
        exit 6
      fi
    fi

    if [[ "$pull_ok" != true ]]; then
      exit 7
    fi
  )
  status=$?

  case $status in
    0) UPDATED+=("$name") ;;
    3) : ;;  # detached HEAD -> NOT_A_REPO扱いにはしないが集計は下でまとめて処理
    4) NO_UPSTREAM+=("$name") ;;
    5) FAILED+=("$name (stash失敗)") ;;
    6) STASH_CONFLICT+=("$name") ;;
    7) FAILED+=("$name (pull失敗)") ;;
    *) FAILED+=("$name (不明なエラー)") ;;
  esac
done

# ── サマリー表示 ────────────────────────────────────────
echo ""
echo "${C_BOLD}========== 実行結果 ==========${C_RESET}"

if [[ ${#UPDATED[@]} -gt 0 ]]; then
  echo "${C_GREEN}✔ 更新完了 (${#UPDATED[@]}):${C_RESET} ${UPDATED[*]}"
fi
if [[ ${#STASH_CONFLICT[@]} -gt 0 ]]; then
  echo "${C_RED}⚠ stash復元でコンフリクト (${#STASH_CONFLICT[@]}):${C_RESET} ${STASH_CONFLICT[*]}"
fi
if [[ ${#NO_UPSTREAM[@]} -gt 0 ]]; then
  echo "${C_YELLOW}– 追跡ブランチ無しでスキップ (${#NO_UPSTREAM[@]}):${C_RESET} ${NO_UPSTREAM[*]}"
fi
if [[ ${#FAILED[@]} -gt 0 ]]; then
  echo "${C_RED}✘ 失敗 (${#FAILED[@]}):${C_RESET} ${FAILED[*]}"
fi
if [[ ${#NOT_A_REPO[@]} -gt 0 ]]; then
  echo "${C_BLUE}(Gitリポジトリではないためスキップ: ${NOT_A_REPO[*]})${C_RESET}"
fi

echo "----------------------------------------"
echo "完了しました。"
