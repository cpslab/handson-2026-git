#!/usr/bin/env bash
# 受講者ブランチにコンフリクトの種を仕込んで push する。
#
# - 学籍番号.md がまだないブランチ: テンプレートに運営の文言を入れた ブランチ名.md を先に作る。
#   受講者が自分の 学籍番号.md を作って push すると、同じファイルを両方が作ったことになり必ずコンフリクトする
# - 学籍番号.md が push 済みのブランチ: 「一言:」の行 (なければ TARGET_KEYS の次の候補) を書き換える。
#   受講者が同じ行を書き換えて push するとコンフリクトする
#
#   ./inject-conflict.sh -w 5          5 秒ごとに新しいブランチを探し、ファイルを先に作り続ける (Ctrl+C で終了)
#   ./inject-conflict.sh -n            何をするかだけ表示 (dry run)
#   ./inject-conflict.sh               対象の全ブランチに仕込む
#   ./inject-conflict.sh 24FI001 ...   指定した学籍番号だけに仕込む
set -u
. "$(dirname "$0")/config.sh"

dry_run=0
interval=0
while getopts "nw:" opt; do
  case $opt in
    n) dry_run=1 ;;
    w) interval=$OPTARG ;;
    *) sed -n '2,12p' "$0"; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

key_pattern() { printf '^([-*] *)?%s *(:|：)' "$1"; }

# 標準入力の中で最初に見つかった TARGET_KEYS の項目名
find_key() {
  local text k
  text=$(cat)
  for k in "${TARGET_KEYS[@]}"; do
    if grep -Eq "$(key_pattern "$k")" <<< "$text"; then printf '%s' "$k"; return; fi
  done
}

# 作業用 clone のファイル $1 の項目 $2 の行を運営の文言にする (行末の \r は残す)
rewrite_key() {
  sed -i -E "s/($(key_pattern "$2"))[^\r]*/\1 ${INJECT_TEXT}/" "$WORK_DIR/$1"
}

watching=0
n_done=0
skip() { [ $watching = 1 ] || echo "$1"; }

# 学籍番号 $1 のブランチに仕込む。$2 が new なら 学籍番号.md がまだないブランチだけを対象にする
inject() {
  local id=$1 only_new=${2:-} branch ref file key tpl="" what msg
  branch=$(branch_of "$id")
  if [ -z "$branch" ]; then
    skip "${C_DIM}skip $id: ブランチなし${C_RST}"; return
  fi
  ref="origin/$branch"
  if [ -n "$(inject_commit "$ref")" ]; then
    skip "${C_DIM}skip $id: 仕込み済み${C_RST}"; return
  fi
  file=$(file_of "$ref" "$id")

  if [ -z "$file" ]; then
    # 受講者はブランチ名と同じ名前でファイルを作る想定 (大文字小文字まで同じでないとコンフリクトしない)
    file="$branch.md"
    tpl=$(g show "$ref:template.md" 2>/dev/null || g show origin/main:template.md 2>/dev/null)
    key=$(find_key <<< "$tpl")
    if [ -z "$key" ]; then
      skip "${C_YEL}skip $id: template.md に「${TARGET_KEYS[*]}」のどの行もない${C_RST}"; return
    fi
    what="$file を先に作成 (「$key」に運営の文言)"
    msg="運営: $file を先に作りました ${INJECT_TAG}"
  else
    [ "$only_new" = new ] && return
    key=$(g show "$ref:$file" | find_key)
    if [ -z "$key" ]; then
      skip "${C_YEL}skip $id: 「${TARGET_KEYS[*]}」のどの行もない${C_RST}"; return
    fi
    what="$file の「$key」を書き換え"
    msg="運営: ${key} を書き換えました ${INJECT_TAG}"
  fi

  if [ $dry_run = 1 ]; then
    echo "${C_CYN}would inject $id: $what${C_RST}"; return
  fi

  # 大文字小文字だけ違うブランチ名がぶつからないよう、ローカルブランチは作らない
  g checkout --quiet --detach "$ref" || return
  if [ -n "$tpl" ] && [ -z "$(file_of HEAD "$id")" ]; then
    printf '%s\n' "$tpl" | sed -E "s/^# *学籍番号/# $branch/" > "$WORK_DIR/$file"
    g add "$file"
  fi
  rewrite_key "$file" "$key"
  if g diff --quiet HEAD; then
    skip "${C_YEL}skip $id: すでに同じ文言${C_RST}"; return
  fi
  g commit --quiet -am "$msg"
  if g push --quiet origin "HEAD:refs/heads/$branch"; then
    printf '%s\t%s\n' "$id" "$(g rev-parse HEAD)" >> "$INJECTED_LOG"
    echo "${C_GRN}$(date '+%H:%M:%S') injected $id: $what${C_RST}"
    n_done=$((n_done + 1))
  else
    # 直前に受講者が push した場合など。もう一度実行すれば最新に対して仕込み直す
    echo "${C_RED}push 失敗 $id: 再実行してください${C_RST}"
  fi
}

if [ "$interval" -gt 0 ] 2>/dev/null; then
  watching=1
  echo "新しいブランチを ${interval} 秒ごとに探しています (Ctrl+C で終了)"
  while true; do
    sync_work
    for id in $(all_ids); do inject "$id" new; done
    sleep "$interval"
  done
fi

sync_work
if [ $# -gt 0 ]; then
  ids=$(printf '%s\n' "$@" | upper)
else
  ids=$(all_ids)
fi
for id in $ids; do inject "$id"; done

g checkout --quiet --detach 2>/dev/null
echo "完了: $n_done 件"
