#!/usr/bin/env bash
# 受講者ブランチの push 状況を一覧表示する。
#
#   ./monitor.sh          一覧を 1 回表示
#   ./monitor.sh -c       各自の 学籍番号.md の中身も表示
#   ./monitor.sh -w 10    10 秒ごとに更新し続ける (Ctrl+C で終了)
#   ./monitor.sh -t       機械向けの出力 (server.py が使う)
set -u
. "$(dirname "$0")/config.sh"

SEP=$'\x1f'
show_content=0
interval=0
machine=0
while getopts "cw:t" opt; do
  case $opt in
    c) show_content=1 ;;
    w) interval=$OPTARG ;;
    t) machine=1 ;;
    *) sed -n '2,8p' "$0"; exit 1 ;;
  esac
done

# 1 人 1 行で状態を出力する。区切りは \x1f、ファイルの中身は base64
#   row SEP id SEP status SEP author SEP 時刻(unix) SEP 時刻(相対) SEP 件名 SEP 補足 SEP 中身
# 最後に形式外のブランチ (odd) と名簿にないブランチ (extra) を 1 行ずつ出力する
collect() {
  sync_work

  for id in $(all_ids); do
    local branch ref file status note="" author="" ct="" ar="" subject="" content=""
    branch=$(branch_of "$id")

    if [ -z "$branch" ]; then
      status="NO_BRANCH"
    else
      ref="origin/$branch"
      file=$(file_of "$ref" "$id")
      IFS=$SEP read -r author ct ar subject < <(g log -1 --format="%an${SEP}%ct${SEP}%ar${SEP}%s" "$ref")
      local inject
      inject=$(inject_commit "$ref")

      if [ -z "$file" ] && [ "$(g rev-list --count "origin/main..$ref")" = 0 ]; then
        status="BRANCH_ONLY"; note="ブランチだけ push 済み"
      elif [ -z "$file" ]; then
        status="NO_FILE"
        note=$(g ls-tree --name-only "$ref" | grep -Ev '^(README|template)\.md$' | tr '\n' ' ')
        [ -n "$note" ] && note="ファイル: $note"
      elif [ -n "$inject" ] && [ "$(g rev-parse "$ref")" != "$inject" ] && g diff --quiet "$inject" "$ref" -- "$file"; then
        # 運営のコミットの後に push があるのに 学籍番号.md が運営の版のまま
        status="NO_FILE"; note="$file が運営の版のまま"
        content=$(g show "$ref:$file" | base64 -w0)
      else
        content=$(g show "$ref:$file" | base64 -w0)
        if g show "$ref:$file" | grep -Eq '^(<<<<<<<|=======|>>>>>>>)'; then
          status="MARKER_LEFT"; note="コンフリクトマーカーが残ったまま push"
        elif [ -z "$inject" ] && was_injected "$id"; then
          status="FORCE_PUSHED"; note="運営のコミットが履歴から消えている (push -f ?)"
        elif [ -z "$inject" ]; then
          status="PUSHED"
        elif [ "$(g rev-parse "$ref")" = "$inject" ]; then
          status="INJECTED"; note="受講者の対応待ち"
        elif [ -n "$(g rev-list --merges "$inject..$ref")" ]; then
          status="RESOLVED"; note="merge で解決"
        else
          status="RESOLVED"; note="merge コミットなし (rebase か、pull 後に編集)"
        fi
      fi

      # 学籍番号.md を作らずにテンプレートを直接書き換えるミスが多いので知らせる
      if [ "$status" = NO_FILE ] && ! g diff --quiet origin/main "$ref" -- template.md 2>/dev/null; then
        note="${note:+$note / }template.md を直接編集している (コピーして $id.md にする)"
      fi

      local same
      same=$(remote_branches | match_i "$id" | tr '\n' ' ')
      [ "${same% }" != "$branch" ] && note="${note:+$note / }同じ学籍番号のブランチが複数: ${same}($branch を表示)"
    fi

    printf '%s\n' "row$SEP$id$SEP$status$SEP$author$SEP$ct$SEP$ar$SEP${subject//$'\t'/ }$SEP$note$SEP$content"
  done

  printf 'odd%s%s\n' "$SEP" "$(remote_branches | grep -Eiv "$ID_REGEX" | sort | tr '\n' ' ')"
  local extra=""
  [ -f "$ROSTER" ] && extra=$(remote_branches | grep -Ei "$ID_REGEX" | upper | sort -u | grep -vxFf <(roster_ids) | tr '\n' ' ')
  printf 'extra%s%s\n' "$SEP" "$extra"
}

report() {
  local data
  data=$(collect) || return 1

  local n_total=0 n_branch=0 n_pushed=0 n_injected=0 n_resolved=0 n_problem=0 odd="" extra=""

  printf '%s\n' "${C_DIM}$(date '+%H:%M:%S') 更新 / $REPO_URL${C_RST}"
  printf '%-10s %-14s %s\n' "ID" "STATUS" "最新コミット"
  printf '%s\n' "------------------------------------------------------------------"

  while IFS=$SEP read -r kind id status author ct ar subject note content; do
    case $kind in
      odd) odd=$id; continue ;;
      extra) extra=$id; continue ;;
    esac

    local color last=""
    n_total=$((n_total + 1))
    case $status in
      NO_BRANCH) color=$C_DIM ;;
      BRANCH_ONLY) color=$C_RST; n_branch=$((n_branch + 1)) ;;
      PUSHED) color=$C_GRN; n_pushed=$((n_pushed + 1)) ;;
      INJECTED) color=$C_YEL; n_injected=$((n_injected + 1)) ;;
      RESOLVED) color=$C_CYN; n_resolved=$((n_resolved + 1)) ;;
      *) color=$C_RED; n_problem=$((n_problem + 1)) ;;
    esac
    [ -n "$author" ] && last="$author, $ar: $subject"

    printf '%s%-10s %-14s%s %s\n' "$color" "$id" "$status" "$C_RST" "$last"
    [ -n "$note" ] && printf '%-25s %s\n' "" "${C_DIM}↳ $note${C_RST}"
    if [ $show_content = 1 ] && [ -n "$content" ]; then
      base64 -d <<< "$content" | sed 's/^/    │ /'
    fi
  done <<< "$data"

  printf '%s\n' "------------------------------------------------------------------"
  printf '全 %d 人 / ブランチのみ %d / push 済み %d / 仕込み済み %d / 解決 %d / 要対応 %s%d%s\n' \
    "$n_total" "$n_branch" "$n_pushed" "$n_injected" "$n_resolved" "$C_RED" "$n_problem" "$C_RST"
  # 学籍番号の形式に合わないブランチ (打ち間違いの可能性)
  [ -n "$odd" ] && printf '%s形式外のブランチ: %s%s\n' "$C_YEL" "$odd" "$C_RST"
  [ -n "$extra" ] && printf '%s名簿にないブランチ: %s%s\n' "$C_YEL" "$extra" "$C_RST"
  return 0
}

if [ $machine = 1 ]; then
  collect
elif [ "$interval" -gt 0 ] 2>/dev/null; then
  while true; do
    out=$(report)
    clear
    printf '%s\n' "$out"
    sleep "$interval"
  done
else
  report
fi
