#!/usr/bin/env python3
# 云端 HLS 中转：mpv/App 播 play.m3u8?src=<编码后的源地址>，
# 本脚本代抓 m3u8 并把分片地址全部改写为指向自身，绕开 mpv 代理缺陷。
# 用法: python3 relay.py   (仅需 Python3 标准库，无需 pip)
import hashlib
import os
import re
import shutil
import subprocess
import tempfile
import threading
import time
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


# ===== 低码率转码：/live.m3u8?src=<源> 用 ffmpeg 转出 360p/800k 的 HLS =====
# 适用「只有高码率源、客户端下行带宽不足」的场景；每路占用一个 ffmpeg 进程。
FFMPEG = "ffmpeg"
LIVE_HEIGHT = "360"  # 输出高度，宽度按比例（-2 保证偶数）
LIVE_V_BITRATE = "800k"
LIVE_HLS_TIME = 2  # 分片时长（秒）
LIVE_LIST_SIZE = 6
LIVE_IDLE_SECONDS = 60  # 会话空闲多久后杀 ffmpeg 并清临时目录
LIVE_STARTUP_TIMEOUT = 25  # 等首个转码列表的最长时间（秒）

_hls_opts_cache = None


def _hls_allowed_opts():
    """探测当前 ffmpeg 的 HLS 分片后缀放行选项。
    7.1+ 拆成 allowed_extensions(列表)/allowed_segment_extensions(分片)，旧版只有前者；
    源用 .jpg 等非标准后缀做分片时必须置 ALL，否则 ffmpeg 拒绝所有分片直接退出。"""
    global _hls_opts_cache
    if _hls_opts_cache is not None:
        return list(_hls_opts_cache)
    try:
        p = subprocess.run(
            [FFMPEG, "-hide_banner", "-h", "demuxer=hls"],
            capture_output=True,
            timeout=10,
        )
        text = (p.stdout + p.stderr).decode("utf-8", "replace")
    except Exception:
        text = ""
    opts = []
    for name in ("allowed_segment_extensions", "allowed_extensions"):
        if name in text:
            opts += ["-" + name, "ALL"]
    if "extension_picky" in text:
        # 默认 true：严格校验「URL 后缀 ↔ 探测出的内容格式」，.jpg 伪装分片必挂，关掉
        opts += ["-extension_picky", "0"]
    _hls_opts_cache = opts
    print("live: ffmpeg hls 放行选项 %s" % (opts or "(未探测到)"), flush=True)
    return opts

_sessions = {}  # sid -> {proc, dir, playlist, used}
_sessions_lock = threading.Lock()


def _sid(src):
    return hashlib.md5(src.encode("utf-8")).hexdigest()[:12]


def _drop_session(sid):
    s = _sessions.pop(sid, None)
    if not s:
        return
    try:
        s["proc"].kill()
    except Exception:
        pass
    shutil.rmtree(s["dir"], ignore_errors=True)


def _live_session(src):
    """按源地址复用一个 ffmpeg 会话；进程已死则自动重建。调用方须持 _sessions_lock。"""
    sid = _sid(src)
    s = _sessions.get(sid)
    if s and s["proc"].poll() is None:
        s["used"] = time.time()
        return s
    if s:
        _drop_session(sid)
    d = tempfile.mkdtemp(prefix="relay_live_%s_" % sid)
    playlist = os.path.join(d, "out.m3u8")
    cmd = [
        FFMPEG, "-nostdin", "-loglevel", "error",
        "-user_agent", UA["User-Agent"],
    ] + _hls_allowed_opts() + [
        "-i", src,
        "-vf", "scale=-2:%s" % LIVE_HEIGHT,
        "-c:v", "libx264", "-preset", "veryfast",
        "-b:v", LIVE_V_BITRATE, "-maxrate", LIVE_V_BITRATE, "-bufsize", "1600k",
        "-c:a", "aac", "-b:a", "64k",
        # 强制 2 秒一个关键帧再切段：否则源 GOP 长（~10s）时单段能到 1MB，
        # 链路抖动窗口内传不完会把播放器饿死
        "-force_key_frames", "expr:gte(t,n_forced*%d)" % LIVE_HLS_TIME,
        "-f", "hls", "-hls_time", str(LIVE_HLS_TIME),
        "-hls_list_size", str(LIVE_LIST_SIZE),
        "-hls_delete_threshold", "10",  # 滚出列表后再留 10 个才删，防 mpv 慢半拍取到列表却 404
        "-hls_flags", "delete_segments",
        "-hls_segment_filename", os.path.join(d, "seg%05d.ts"),
        playlist,
    ]
    try:
        # ffmpeg 报错写进会话目录，启动失败时可打印尾部定位（见 _wait_ready）
        errf = open(os.path.join(d, "ffmpeg.log"), "wb")
        try:
            proc = subprocess.Popen(
                cmd,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=errf,
            )
        finally:
            errf.close()
    except Exception:
        shutil.rmtree(d, ignore_errors=True)
        raise
    s = {"proc": proc, "dir": d, "playlist": playlist, "used": time.time()}
    _sessions[sid] = s
    return s


def _log_ffmpeg_tail(s, lines=15):
    """把 ffmpeg 的 stderr 尾部打进 relay 日志，便于定位 502 根因。"""
    try:
        with open(os.path.join(s["dir"], "ffmpeg.log"), "rb") as fh:
            data = fh.read()[-4096:]
        tail = [
            ln for ln in data.decode("utf-8", "replace").splitlines() if ln.strip()
        ][-lines:]
        if tail:
            print("ffmpeg stderr tail:\n" + "\n".join(tail), flush=True)
    except Exception:
        pass


def _wait_ready(s, timeout=LIVE_STARTUP_TIMEOUT):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.isfile(s["playlist"]) and os.path.getsize(s["playlist"]) > 0:
            return True
        if s["proc"].poll() is not None:
            print("live: ffmpeg 已退出 code=%s" % s["proc"].returncode, flush=True)
            _log_ffmpeg_tail(s)
            return False
        time.sleep(0.3)
    print("live: %ss 内未生成列表（ffmpeg 仍在运行）" % timeout, flush=True)
    _log_ffmpeg_tail(s)
    return False


def _reaper_loop():
    """定期回收空闲超时或已退出的转码会话。"""
    while True:
        time.sleep(15)
        with _sessions_lock:
            now = time.time()
            for sid, s in list(_sessions.items()):
                if s["proc"].poll() is not None or now - s["used"] > LIVE_IDLE_SECONDS:
                    _drop_session(sid)


class Relay(BaseHTTPRequestHandler):
    # 分片序列复用同一条 TCP：免去每段一次跨境握手，拥塞窗口也能延续
    protocol_version = "HTTP/1.1"

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
            elif u.path == "/live.m3u8":
                self.serve_live_playlist(p["src"][0])
            elif u.path == "/liveseg":
                self.serve_live_segment(p["sid"][0], p["f"][0])
            else:
                self.send_error(404)
        except Exception as e:
            print("handler error %s: %s: %s" % (u.path, type(e).__name__, e), flush=True)
            try:
                self.send_error(502)
            except Exception:
                pass

    @staticmethod
    def _host(url):
        try:
            return urlparse(url).netloc or "-"
        except Exception:
            return "-"

    def _perf(self, label, parts, nbytes):
        """耗时分解：ttfb=上游连接+响应头(含跳转)，recv=下载，send=下发客户端。"""
        print(
            "%s perf %s %s bytes=%d"
            % (
                time.strftime("%H:%M:%S"),
                label,
                " ".join("%s=%.0fms" % (name, sec * 1000) for name, sec in parts),
                nbytes,
            ),
            flush=True,
        )

    def serve_playlist(self, src):
        t0 = time.perf_counter()
        r = fetch(src)
        t1 = time.perf_counter()  # 上游 TTFB（含跳转）
        base = r.geturl()  # 跟随跳转后的最终地址，用于解析相对分片路径
        body = r.read()
        t2 = time.perf_counter()
        data = rewrite_playlist(body, base)
        self.send_response(200)
        self.send_header("Content-Type", "application/vnd.apple.mpegurl")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
        self._perf(
            "/play.m3u8->%s" % self._host(src),
            (("ttfb", t1 - t0), ("recv", t2 - t1), ("send", time.perf_counter() - t2)),
            len(data),
        )

    def serve_fetch(self, url):
        t0 = time.perf_counter()
        r = fetch(url)
        t1 = time.perf_counter()  # 上游 TTFB（含跳转）
        ctype = r.headers.get("Content-Type", "application/octet-stream")
        # 先读一块做嗅探：/fetch 也可能拿到子 m3u8（URL 无后缀，须按内容判断），
        # 是列表就整体改写（列表很小）；否则把已读的头块和后续数据流式透传，
        # 避免大分片/大文件全量进内存。
        head = r.read(65536)
        t2 = time.perf_counter()  # 嗅探块下载完成
        if "mpegurl" in ctype or head.lstrip()[:7] == b"#EXTM3U":
            body = rewrite_playlist(head + r.read(), r.geturl())
            t3 = time.perf_counter()
            self.send_response(200)
            self.send_header("Content-Type", "application/vnd.apple.mpegurl")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            self._perf(
                "/fetch->%s" % self._host(url),
                (("ttfb", t1 - t0), ("recv", t3 - t1), ("send", time.perf_counter() - t3)),
                len(body),
            )
            return
        self.send_response(getattr(r, "status", 200) or 200)
        self.send_header("Content-Type", ctype)
        # 上游带长度就原样带上，mpv 可显示进度/支持拖动；不带则由连接关闭界定。
        length = r.headers.get("Content-Length")
        if length:
            self.send_header("Content-Length", length)
        else:
            # 上游无长度，无法 keep-alive，声明本响应后即断开
            self.send_header("Connection", "close")
            self.close_connection = True
        range_ = r.headers.get("Content-Range")
        if range_:
            self.send_header("Content-Range", range_)
        self.end_headers()
        recv_s = t2 - t1  # 已含嗅探块
        send_s = 0.0
        nbytes = 0
        try:
            tw = time.perf_counter()
            self.wfile.write(head)
            send_s += time.perf_counter() - tw
            nbytes += len(head)
            while True:
                tr = time.perf_counter()
                buf = r.read(65536)
                recv_s += time.perf_counter() - tr
                if not buf:
                    break
                tw = time.perf_counter()
                self.wfile.write(buf)
                send_s += time.perf_counter() - tw
                nbytes += len(buf)
        except Exception:
            self.close_connection = True  # 半截中断，帧已不完整，禁复用
        finally:
            self._perf(
                "/fetch->%s" % self._host(url),
                (("ttfb", t1 - t0), ("recv", recv_s), ("send", send_s)),
                nbytes,
            )

    def serve_live_playlist(self, src):
        """起（或复用）ffmpeg 转码会话，返回分片地址改写为 /liveseg 的转码后列表。"""
        t0 = time.perf_counter()
        with _sessions_lock:
            s = _live_session(src)
        if not _wait_ready(s):
            raise RuntimeError("ffmpeg 未生成转码列表（源不可读？）")
        with open(s["playlist"], "rb") as fh:
            body = fh.read()
        sid = _sid(src)
        out = []
        for line in body.decode("utf-8", "replace").splitlines():
            if line.strip() and not line.startswith("#"):
                out.append(
                    "%s/liveseg?t=%s&sid=%s&f=%s"
                    % (BASE, TOKEN, sid, quote(os.path.basename(line.strip())))
                )
            else:
                out.append(line)
        data = "\n".join(out).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/vnd.apple.mpegurl")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)
        self._perf(
            "/live.m3u8->%s" % self._host(src),
            (("start", time.perf_counter() - t0),),
            len(data),
        )

    def serve_live_segment(self, sid, fname):
        """按需流式下发本地转码分片。"""
        t0 = time.perf_counter()
        name = os.path.basename(fname)
        with _sessions_lock:
            s = _sessions.get(sid)
            if s:
                s["used"] = time.time()
        path = os.path.join(s["dir"], name) if s else ""
        if not s or not name.startswith("seg") or not os.path.isfile(path):
            self.send_error(404)
            return
        size = os.path.getsize(path)
        self.send_response(200)
        self.send_header("Content-Type", "video/mp2t")
        self.send_header("Content-Length", str(size))
        self.end_headers()
        sent = 0
        try:
            with open(path, "rb") as fh:
                while True:
                    buf = fh.read(65536)
                    if not buf:
                        break
                    self.wfile.write(buf)
                    sent += len(buf)
        except Exception:
            pass
        finally:
            self._perf(
                "/liveseg->%s" % name, (("send", time.perf_counter() - t0),), sent
            )

    def log_message(self, fmt, *args):
        print(
            "%s %s - %s" % (time.strftime("%H:%M:%S"), self.address_string(), fmt % args),
            flush=True,
        )


if __name__ == "__main__":
    threading.Thread(target=_reaper_loop, daemon=True).start()
    print(
        "relay on %s (token=%s) live=ffmpeg %sp/%s x%d"
        % (BASE, TOKEN, LIVE_HEIGHT, LIVE_V_BITRATE, os.cpu_count() or 0),
        flush=True,
    )
    ThreadingHTTPServer(("0.0.0.0", PORT), Relay).serve_forever()
