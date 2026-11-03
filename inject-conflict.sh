#!/usr/bin/env bash
# 受講者が push した 学籍番号.md の一番下に運営の 1 行 (config.sh の INJECT_LINE) を追記して push し、
# コンフリクトの種を仕込む。受講者が指示どおりファイルの一番下に 1 行追加して push すると、
# 同じ場所に両方が追記したことになりコンフリクトする。
#
#   ./inject-conflict.sh -w 5          5 秒ごとに新しく push されたファイルを探して仕込み続ける (Ctrl+C で終了)
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
    *) sed -n '2,9p' "$0"; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

watching=0
n_done=0
skip() { [ $watching = 1 ] || echo "$1"; }

# ブランチ $1 (ref) のファイル $2 の一番下に INJECT_LINE を追記した版を Git に書き込み、その blob を出す
# (改行コードはファイルに合わせる。作業ツリーには何も書かない)
appended_blob() {
  local obj="$1:$2" eol=$'\n'
  [ "$(g cat-file blob "$obj" | tail -c 2 | od -An -c | tr -d ' ')" = '\r\n' ] && eol=$'\r\n'
  {
    g cat-file blob "$obj"
    # 最終行に改行がなければ先に改行する
    [ -n "$(g cat-file blob "$obj" | tail -c 1)" ] && printf '%s' "$eol"
    printf '%s%s' "$INJECT_LINE" "$eol"
  } | g hash-object -w --no-filters --stdin
}

# ブランチ $1 (ref) の一番上のツリーで、ファイル $2 だけを blob $3 に差し替えたツリーを作る
replaced_tree() {
  g ls-tree -z "$1" | awk -v f="$2" -v b="$3" 'BEGIN { RS = ORS = "\0"; FS = OFS = "\t" }
    $2 == f { split($1, m, " "); $1 = m[1] " " m[2] " " b } { print }' | g mktree -z
}

inject() {
  local id=$1 branch ref file blob tree commit
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
    skip "${C_YEL}skip $id: $id.md がまだない${C_RST}"; return
  fi

  if [ $dry_run = 1 ]; then
    echo "${C_CYN}would inject $id: $branch/$file に追記${C_RST}"; return
  fi

  # チェックアウトせずにコミットを作り、そのまま origin のブランチへ push する
  blob=$(appended_blob "$ref" "$file") &&
    tree=$(replaced_tree "$ref" "$file" "$blob") &&
    commit=$(g commit-tree "$tree" -p "$ref" -m "運営: $file の一番下に追記しました ${INJECT_TAG}") || {
    echo "${C_RED}コミット作成失敗 $id${C_RST}"; return
  }
  if g push --quiet origin "$commit:refs/heads/$branch"; then
    g update-ref "$INJECTED_REFS/$id" "$commit"
    echo "${C_GRN}$(date '+%H:%M:%S') injected $id ($file)${C_RST}"
    n_done=$((n_done + 1))
  else
    # 直前に受講者が push した場合など。もう一度実行すれば最新に対して仕込み直す
    echo "${C_RED}push 失敗 $id: 再実行してください${C_RST}"
  fi
}

if [ "$interval" -gt 0 ] 2>/dev/null; then
  watching=1
  echo "新しく push されたファイルを ${interval} 秒ごとに探しています (Ctrl+C で終了)"
  while true; do
    fetch_remote
    for id in $(all_ids); do inject "$id"; done
    sleep "$interval"
  done
fi

fetch_remote
if [ $# -gt 0 ]; then
  ids=$(printf '%s\n' "$@" | upper)
else
  ids=$(all_ids)
fi
for id in $ids; do inject "$id"; done

echo "完了: $n_done 件"
