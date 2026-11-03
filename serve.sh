#!/usr/bin/env bash
# 投影用ページを http://localhost:8000 で起動する (PORT=8080 ./serve.sh で変更可)
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
exec "$PY" server.py
