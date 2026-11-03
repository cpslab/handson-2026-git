#!/usr/bin/env bash
# 受講者ブランチの「一言:」行 (config.sh の TARGET_KEY) を書き換えて push し、コンフリクトの種を仕込む。
#
#   ./inject-conflict.sh -n            何をするかだけ表示 (dry run)
#   ./inject-conflict.sh               対象の全ブランチに仕込む
#   ./inject-conflict.sh 24FI001 ...   指定した学籍番号だけに仕込む
set -u
. "$(dirname "$0")/config.sh"

dry_run=0
while getopts "n" opt; do
  case $opt in
    n) dry_run=1 ;;
    *) sed -n '2,7p' "$0"; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

sync_work

if [ $# -gt 0 ]; then
  ids=$(printf '%s\n' "$@" | upper)
else
  ids=$(all_ids)
fi

key_pattern="^([-*] *)?${TARGET_KEY} *(:|：)"
n_done=0

for id in $ids; do
  branch=$(branch_of "$id")
  if [ -z "$branch" ]; then
    echo "${C_DIM}skip $id: ブランチなし${C_RST}"; continue
  fi
  ref="origin/$branch"
  file=$(file_of "$ref" "$id")
  if [ -z "$file" ]; then
    echo "${C_YEL}skip $id: $id.md がない${C_RST}"; continue
  fi
  if [ -n "$(inject_commit "$ref")" ]; then
    echo "${C_DIM}skip $id: 書き換え済み${C_RST}"; continue
  fi
  if ! g show "$ref:$file" | grep -Eq "$key_pattern"; then
    echo "${C_YEL}skip $id: 「${TARGET_KEY}:」の行がない${C_RST}"; continue
  fi

  if [ $dry_run = 1 ]; then
    echo "${C_CYN}would inject $id ($branch/$file)${C_RST}"; continue
  fi

  # 大文字小文字だけ違うブランチ名がぶつからないよう、ローカルブランチは作らない
  g checkout --quiet --detach "$ref" || continue
  # 改行コード (CRLF) を壊さないよう行末の \r は残す
  sed -i -E "s/(${key_pattern})[^\r]*/\1 ${INJECT_TEXT}/" "$WORK_DIR/$file"
  if g diff --quiet; then
    echo "${C_YEL}skip $id: すでに同じ文言${C_RST}"; continue
  fi
  g commit --quiet -am "運営: ${TARGET_KEY} を書き換えました ${INJECT_TAG}"
  if g push --quiet origin "HEAD:refs/heads/$branch"; then
    printf '%s\t%s\n' "$id" "$(g rev-parse HEAD)" >> "$INJECTED_LOG"
    echo "${C_GRN}injected $id${C_RST}"
    n_done=$((n_done + 1))
  else
    # 直前に受講者が push した場合など。もう一度実行すれば最新に対して仕込み直す
    echo "${C_RED}push 失敗 $id: 再実行してください${C_RST}"
  fi
done

g checkout --quiet --detach 2>/dev/null
echo "完了: $n_done 件"
