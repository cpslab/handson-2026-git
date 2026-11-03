"""投影用の状況ページを配信する。./serve.sh から起動する。

判定は monitor.sh -t に任せ、ここでは JSON にして返すだけ。
"""
import base64
import json
import os
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
BASH = os.environ.get("BASH_BIN", "bash")
PORT = int(os.environ.get("PORT", "8000"))
CACHE_SEC = 3  # タブを複数開いても git fetch が連発しないように
SEP = "\x1f"

_lock = threading.Lock()
_cache = {"at": 0.0, "data": {"rows": [], "odd": [], "extra": []}, "error": None}


def run_monitor():
    proc = subprocess.run(
        [BASH, os.path.join(HERE, "monitor.sh"), "-t"],
        cwd=HERE, capture_output=True, timeout=60,
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.decode("utf-8", "replace").strip() or "monitor.sh が失敗しました")

    data = {"rows": [], "odd": [], "extra": []}
    for line in proc.stdout.decode("utf-8", "replace").splitlines():
        f = line.split(SEP)
        if f[0] == "row":
            f += [""] * (9 - len(f))
            _, id_, status, author, ct, ar, subject, note, content = f[:9]
            data["rows"].append({
                "id": id_, "status": status, "author": author,
                "time": int(ct) if ct else None, "subject": subject, "note": note,
                "content": base64.b64decode(content).decode("utf-8", "replace") if content else "",
            })
        elif f[0] in ("odd", "extra") and len(f) > 1:
            data[f[0]] = f[1].split()
    return data


def status_json():
    with _lock:
        if time.time() - _cache["at"] > CACHE_SEC:
            try:
                _cache["data"] = run_monitor()
                _cache["error"] = None
            except Exception as e:  # 取得に失敗しても前回の結果は出し続ける
                _cache["error"] = str(e)
            _cache["at"] = time.time()
        return json.dumps({**_cache["data"], "error": _cache["error"], "updated": _cache["at"]})


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/api/status":
            self.send(200, "application/json", status_json().encode("utf-8"))
        elif self.path in ("/", "/index.html"):
            with open(os.path.join(HERE, "index.html"), "rb") as f:
                self.send(200, "text/html; charset=utf-8", f.read())
        else:
            self.send(404, "text/plain", b"not found")

    def send(self, code, ctype, body):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    print(f"http://localhost:{PORT} で配信中 (Ctrl+C で終了)")
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
