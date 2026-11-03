# 運営スクリプト共通の設定。monitor.sh / inject-conflict.sh から source される。

# 監視対象のリポジトリ (環境変数 REPO_URL で上書き可)
REPO_URL="${REPO_URL:-git@github.com:cpslab/handson-2026-git.git}"

# 学籍番号の形式: 2xFIxxx / 2xFMIxxx (x の前半は 3-6、後半は 3 桁)
ID_REGEX='^2[3-6]FM?I[0-9]{3}$'

# コンフリクトを起こす行の候補。「- 一言: 〜」のような行を前から順に探し、最初に見つかった行を書き換える
# (行頭の「- 」はなくてもよい)
TARGET_KEYS=(一言 好きなこと 趣味 名前)
# 運営が書き込む文言 (sed の置換に入るので / と & は使わない)
INJECT_TEXT='運営が入力を妨害しました！！！一緒にコンフリクト対応しましょうね^^'
# 運営コミットを見分けるための目印。コミットメッセージに入る
INJECT_TAG='[conflict-drill]'

# main と admin 以外で、学籍番号ブランチとして扱わないブランチ
IGNORE_BRANCHES='^(main|admin|HEAD)$'

ADMIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$ADMIN_DIR/.work"          # 作業用 clone (gitignore 済み)
ROSTER="$ADMIN_DIR/students.txt"     # 名簿 (任意・gitignore 済み)
INJECTED_LOG="$ADMIN_DIR/injected.tsv" # 書き換えた記録 (gitignore 済み)

if [ -t 1 ]; then
  C_RED=$'\e[31m'; C_GRN=$'\e[32m'; C_YEL=$'\e[33m'; C_CYN=$'\e[36m'; C_DIM=$'\e[2m'; C_RST=$'\e[0m'
else
  C_RED=; C_GRN=; C_YEL=; C_CYN=; C_DIM=; C_RST=
fi

g() { git -C "$WORK_DIR" "$@"; }

# 作業用 clone を用意して最新化する
sync_work() {
  if [ ! -d "$WORK_DIR/.git" ]; then
    git clone --quiet --no-checkout "$REPO_URL" "$WORK_DIR" || exit 1
  fi
  g fetch --quiet --prune origin || exit 1
}

# 学籍番号のブランチ名・ファイル名は大文字小文字を区別しない (24fi001 も 24FI001 として扱う)
# 一覧や記録では大文字にそろえた学籍番号を使う
upper() { tr '[:lower:]' '[:upper:]'; }

# 新しく更新された順
remote_branches() {
  g for-each-ref --sort=-committerdate --format='%(refname:lstrip=3)' refs/remotes/origin | grep -Ev "$IGNORE_BRANCHES"
}

roster_ids() {
  [ -f "$ROSTER" ] && tr -d '\r' < "$ROSTER" | upper | grep -E "$ID_REGEX"
}

# 名簿の学籍番号 + リモートにある学籍番号形式のブランチ (大文字にそろえて重複なし)
all_ids() {
  {
    roster_ids
    remote_branches | grep -Ei "$ID_REGEX" | upper
  } | sort -u
}

# 標準入力から $1 と大文字小文字を無視して一致する行を出す
# (Git Bash の grep は -i と -F を一緒に使うと異常終了するため awk で比べる)
match_i() { awk -v k="$1" 'tolower($0) == tolower(k)'; }

# 学籍番号に対応するリモートのブランチ名。大文字小文字違いで複数あれば最後に更新されたもの
branch_of() { remote_branches | match_i "$1" | head -1; }

# ブランチ ($1 = ref) にある 学籍番号.md のファイル名
file_of() { g ls-tree --name-only "$1" | match_i "$2.md" | head -1; }

# 運営が書き換えたコミット (ブランチ $1 = ref の履歴から探す)
inject_commit() {
  g log --format=%H -1 --fixed-strings --grep="$INJECT_TAG" "$1" 2>/dev/null
}

was_injected() { [ -f "$INJECTED_LOG" ] && grep -q "^$1	" "$INJECTED_LOG"; }
