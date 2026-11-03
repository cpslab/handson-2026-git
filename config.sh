# 運営スクリプト共通の設定。monitor.sh / inject-conflict.sh から source される。

# 監視対象は、このスクリプトを置いているリポジトリの origin。
# 作業用の clone や記録ファイルは作らず、このリポジトリの origin/* を fetch して読む。
# 運営が追記したことは Git の内部の参照 refs/conflict-drill/学籍番号 に記録する (作業ツリーにファイルは出ない)

# 学籍番号の形式: 2xFIxxx / 2xFMIxxx (x の前半は 3-6、後半は 3 桁)
ID_REGEX='^2[3-6]FM?I[0-9]{3}$'

# 運営が受講者の 学籍番号.md の一番下に追記する行
INJECT_LINE='- 運営より: 運営が入力を妨害しました！！！一緒にコンフリクト対応しましょうね^^'
# 運営コミットを見分けるための目印。コミットメッセージに入る
INJECT_TAG='[conflict-drill]'

# main と admin 以外で、学籍番号ブランチとして扱わないブランチ
IGNORE_BRANCHES='^(main|admin|HEAD)$'

ADMIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROSTER="$ADMIN_DIR/students.txt"     # 名簿 (任意・gitignore 済み)

if [ -t 1 ]; then
  C_RED=$'\e[31m'; C_GRN=$'\e[32m'; C_YEL=$'\e[33m'; C_CYN=$'\e[36m'; C_DIM=$'\e[2m'; C_RST=$'\e[0m'
else
  C_RED=; C_GRN=; C_YEL=; C_CYN=; C_DIM=; C_RST=
fi

g() { git -C "$ADMIN_DIR" "$@"; }

# origin の受講者ブランチを最新化する。
# NO_FETCH が設定されていれば何もしない (serve.sh では fetch を自動の仕込み側だけに任せ、同時 fetch のぶつかりを避ける)
fetch_remote() {
  [ -n "${NO_FETCH:-}" ] && return 0
  g fetch --quiet --prune origin
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

# 運営が追記したコミットの記録
INJECTED_REFS=refs/conflict-drill
was_injected() { g rev-parse -q --verify "$INJECTED_REFS/$1" >/dev/null; }
