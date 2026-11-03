#!/usr/bin/env bash
# 投影用ページを http://localhost:8000 で起動し、コンフリクトの自動仕込み (inject-conflict.sh -w) も一緒に動かす。
# Ctrl+C で両方止まる。
#
#   ./serve.sh                    いつもの起動
#   PORT=8080 ./serve.sh          ポートを変える
#   INJECT_INTERVAL=10 ./serve.sh 自動仕込みの間隔 (秒、既定 5)
#   AUTO_INJECT=0 ./serve.sh      自動仕込みを動かさず、ページだけ出す
cd "$(dirname "$0")" || exit 1

# Windows では server.py から Git Bash の bash を呼べるよう Windows 形式のパスで渡す
# (素の bash だと WSL の bash.exe が呼ばれることがある)
if command -v cygpath >/dev/null; then
  BASH_BIN=$(cygpath -w "$(command -v bash)")
else
  BASH_BIN=$(command -v bash)
fi
export BASH_BIN

PY=$(command -v python3 || command -v python || command -v py)

if [ "${AUTO_INJECT:-1}" = 0 ]; then
  exec "$PY" server.py
fi

# fetch は自動仕込み側だけが行い、ページ側 (monitor.sh) は手元の origin/* を読むだけにする
# serve.sh が強制終了されても残らないよう、WATCH_PARENT で親が生きているかを見させる
WATCH_PARENT=$$ NO_FETCH= bash inject-conflict.sh -w "${INJECT_INTERVAL:-5}" &
inject_pid=$!
trap 'kill "$inject_pid" 2>/dev/null' EXIT

NO_FETCH=1 "$PY" server.py
