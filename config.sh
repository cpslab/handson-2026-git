# 運営スクリプト共通の設定。monitor.sh / inject-conflict.sh から source される。

# 監視対象のリポジトリ (環境変数 REPO_URL で上書き可)
REPO_URL="${REPO_URL:-git@github.com:cpslab/handson-2026-git.git}"

# 学籍番号の形式: 2xFIxxx / 2xFMIxxx (x の前半は 3-6、後半は 3 桁)
ID_REGEX='^2[3-6]FM?I[0-9]{3}$'

# コンフリクトを起こす行。受講者の 学籍番号.md に「ひとこと: 〜」の行がある前提
TARGET_KEY='ひとこと'
# 運営が書き込む文言 (sed の置換に入るので / と & は使わない)
INJECT_TEXT='運営が書き換えました！自分の文章と見比べて直してください'
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

remote_branches() {
  g for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin | grep -Ev "$IGNORE_BRANCHES"
}

# 名簿の学籍番号 + リモートにある学籍番号形式のブランチ (重複なし)
all_ids() {
  {
    [ -f "$ROSTER" ] && tr -d '\r' < "$ROSTER" | grep -E "$ID_REGEX"
    remote_branches | grep -E "$ID_REGEX"
  } | sort -u
}

has_ref() { g rev-parse -q --verify "origin/$1" >/dev/null; }

# 運営が書き換えたコミット (ブランチの履歴から探す)
inject_commit() {
  g log --format=%H -1 --fixed-strings --grep="$INJECT_TAG" "origin/$1" 2>/dev/null
}

was_injected() { [ -f "$INJECTED_LOG" ] && grep -q "^$1	" "$INJECTED_LOG"; }
