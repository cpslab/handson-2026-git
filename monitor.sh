#!/usr/bin/env bash
# 受講者ブランチの push 状況を一覧表示する。
#
#   ./monitor.sh          一覧を 1 回表示
#   ./monitor.sh -c       各自の 学籍番号.md の中身も表示
#   ./monitor.sh -w 10    10 秒ごとに更新し続ける (Ctrl+C で終了)
set -u
. "$(dirname "$0")/config.sh"

show_content=0
interval=0
while getopts "cw:" opt; do
  case $opt in
    c) show_content=1 ;;
    w) interval=$OPTARG ;;
    *) sed -n '2,7p' "$0"; exit 1 ;;
  esac
done

report() {
  sync_work

  local ids n_total=0 n_pushed=0 n_injected=0 n_resolved=0 n_problem=0
  ids=$(all_ids)

  printf '%s\n' "${C_DIM}$(date '+%H:%M:%S') 更新 / $REPO_URL${C_RST}"
  printf '%-10s %-14s %s\n' "ID" "STATUS" "最新コミット"
  printf '%s\n' "------------------------------------------------------------------"

  for id in $ids; do
    n_total=$((n_total + 1))
    local ref="origin/$id" file="$id.md" status color note="" last=""

    if ! has_ref "$id"; then
      status="NO_BRANCH"; color=$C_DIM
    else
      last=$(g log -1 --format='%an, %ar: %s' "$ref")
      local inject
      inject=$(inject_commit "$id")

      if ! g cat-file -e "$ref:$file" 2>/dev/null; then
        status="NO_FILE"; color=$C_RED; n_problem=$((n_problem + 1))
        note=$(g ls-tree --name-only "$ref" | grep -v '^README.md$' | tr '\n' ' ')
        [ -n "$note" ] && note="ファイル: $note"
      elif g show "$ref:$file" | grep -Eq '^(<<<<<<<|=======|>>>>>>>)'; then
        status="MARKER_LEFT"; color=$C_RED; n_problem=$((n_problem + 1))
        note="コンフリクトマーカーが残ったまま push"
      elif [ -z "$inject" ] && was_injected "$id"; then
        status="FORCE_PUSHED"; color=$C_RED; n_problem=$((n_problem + 1))
        note="運営のコミットが履歴から消えている (push -f ?)"
      elif [ -z "$inject" ]; then
        status="PUSHED"; color=$C_GRN; n_pushed=$((n_pushed + 1))
      elif [ "$(g rev-parse "$ref")" = "$inject" ]; then
        status="INJECTED"; color=$C_YEL; n_injected=$((n_injected + 1))
        note="受講者の対応待ち"
      else
        status="RESOLVED"; color=$C_CYN; n_resolved=$((n_resolved + 1))
        if [ -n "$(g rev-list --merges "$inject..$ref")" ]; then
          note="merge で解決"
        else
          note="merge コミットなし (rebase か、pull 後に編集)"
        fi
      fi
    fi

    printf '%s%-10s %-14s%s %s\n' "$color" "$id" "$status" "$C_RST" "$last"
    [ -n "$note" ] && printf '%-25s %s\n' "" "${C_DIM}↳ $note${C_RST}"

    if [ $show_content = 1 ] && has_ref "$id" && g cat-file -e "$ref:$file" 2>/dev/null; then
      g show "$ref:$file" | sed 's/^/    │ /'
    fi
  done

  printf '%s\n' "------------------------------------------------------------------"
  printf '全 %d 人 / push 済み %d / 書き換え済み %d / 解決 %d / 要対応 %s%d%s\n' \
    "$n_total" "$n_pushed" "$n_injected" "$n_resolved" "$C_RED" "$n_problem" "$C_RST"

  # 学籍番号の形式に合わないブランチ (打ち間違いの可能性)
  local odd
  odd=$(remote_branches | grep -Ev "$ID_REGEX" | tr '\n' ' ')
  [ -n "$odd" ] && printf '%s形式外のブランチ: %s%s\n' "$C_YEL" "$odd" "$C_RST"
  # 名簿にない学籍番号 (名簿がある場合のみ)
  if [ -f "$ROSTER" ]; then
    local extra
    extra=$(remote_branches | grep -E "$ID_REGEX" | grep -vxFf <(tr -d '\r' < "$ROSTER") | tr '\n' ' ')
    [ -n "$extra" ] && printf '%s名簿にないブランチ: %s%s\n' "$C_YEL" "$extra" "$C_RST"
  fi
  return 0
}

if [ "$interval" -gt 0 ] 2>/dev/null; then
  while true; do
    out=$(report)
    clear
    printf '%s\n' "$out"
    sleep "$interval"
  done
else
  report
fi
