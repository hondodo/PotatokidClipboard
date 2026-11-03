#!/usr/bin/env python3
# 云端 HLS 中转：mpv/App 播 play.m3u8?src=<编码后的源地址>，
# 本脚本代抓 m3u8 并把分片地址全部改写为指向自身，绕开 mpv 代理缺陷。
# 用法: python3 relay.py   (仅需 Python3 标准库，无需 pip)
import re
from urllib.parse import quote, urljoin, urlparse, parse_qs
from urllib.request import urlopen, Request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# ===== 部署前修改这两处 =====
BASE = "http://xxxxxxx:xxxxxx"  # 本机公网地址:端口（高位随机端口，防扫描）
TOKEN = "xxxxxxx"   # 随机串，App 侧拼进 URL
# ============================
PORT = xxxxxx  # 监听端口，须与 BASE 中一致

UA = {"User-Agent": "Mozilla/5.0"}


def fetch(url):
    return urlopen(Request(url, headers=UA), timeout=15)


def rewrite_playlist(body, base):
    """把 m3u8 里的分片/子列表/密钥地址全部改写为经 relay 的 /fetch。"""
    out = []
    for line in body.decode("utf-8", "replace").splitlines():
        if line.strip() and not line.startswith("#"):
            # 普通行：分片或子列表地址（相对或绝对）
            out.append("%s/fetch?t=%s&u=%s"
                       % (BASE, TOKEN, quote(urljoin(base, line.strip()), safe="")))
        else:
            # 注释行：只改写 EXT-X-KEY / EXT-X-MAP 里的 URI="..."
            line = re.sub(
                r'URI="([^"]+)"',
                lambda m: 'URI="%s/fetch?t=%s&u=%s"'
                % (BASE, TOKEN, quote(urljoin(base, m.group(1)), safe="")),
                line,
            )
            out.append(line)
    return "\n".join(out).encode()


class Relay(BaseHTTPRequestHandler):
    def do_GET(self):
        u = urlparse(self.path)
        p = parse_qs(u.query)
        if p.get("t", [""])[0] != TOKEN:
            self.send_error(403)
            return
        try:
            if u.path == "/play.m3u8":
                self.serve_playlist(p["src"][0])
            elif u.path == "/fetch":
                self.serve_fetch(p["u"][0])
            else:
                self.send_error(404)
        except Exception:
            try:
                self.send_error(502)
            except Exception:
                pass

    def serve_playlist(self, src):
        r = fetch(src)
        base = r.geturl()  # 跟随跳转后的最终地址，用于解析相对分片路径
        body = r.read()
        data = rewrite_playlist(body, base)
        self.send_response(200)
        self.send_header("Content-Type", "application/vnd.apple.mpegurl")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def serve_fetch(self, url):
        r = fetch(url)
        body = r.read()
        ctype = r.headers.get("Content-Type", "application/octet-stream")
        # 两层列表场景：/fetch 也可能拿到子 m3u8（URL 无后缀，须按内容嗅探），
        # 同样要改写分片地址，否则 mpv 会按 relay 地址解析相对路径得到 404
        if "mpegurl" in ctype or body.lstrip()[:7] == b"#EXTM3U":
            body = rewrite_playlist(body, r.geturl())
            ctype = "application/vnd.apple.mpegurl"
        self.send_response(200)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        print("%s - %s" % (self.address_string(), fmt % args), flush=True)


if __name__ == "__main__":
    print("relay on %s (token=%s)" % (BASE, TOKEN), flush=True)
    ThreadingHTTPServer(("0.0.0.0", PORT), Relay).serve_forever()
