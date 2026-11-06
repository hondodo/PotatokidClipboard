#!/usr/bin/env python3
# 云端 HLS 中转：mpv/App 播 play.m3u8?src=<编码后的源地址>，
# 本脚本代抓 m3u8 并把分片地址全部改写为指向自身，绕开 mpv 代理缺陷。
# 用法: python3 relay.py   (仅需 Python3 标准库，无需 pip)
import hashlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import threading
import time
from urllib.parse import quote, urljoin, urlparse, parse_qs
from urllib.request import urlopen, Request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# ===== 部署前修改这三处（也可用环境变量覆盖） =====
BASE = os.environ.get("RELAY_BASE", "http://143.203.52.132:47291")  # 本机公网地址:端口
TOKEN = os.environ.get("RELAY_TOKEN", "hhpotatokidtoken")   # 随机串，App 侧拼进 URL
PORT = int(os.environ.get("RELAY_PORT", "47291"))  # 监听端口，须与 BASE 中一致
# =================================================
# ===== 转换流量历史（按转码源；只存主机名+短哈希，不落完整 URL/token） =====
TRAFFIC_FILE = os.environ.get(
    "RELAY_TRAFFIC_FILE", "/var/log/potatokid-relay-traffic.jsonl")
TRAFFIC_INTERVAL = max(2, int(os.environ.get("RELAY_TRAFFIC_INTERVAL", "10")))
TRAFFIC_RETENTION = max(60, int(os.environ.get("RELAY_TRAFFIC_RETENTION", "86400")))
TRAFFIC_MAX_BYTES = max(
    256 * 1024,
    int(os.environ.get("RELAY_TRAFFIC_MAX_BYTES", str(8 * 1024 * 1024))))
TRAFFIC_TRIM_EVERY = 300  # 秒：常规修剪周期（文件超限时每次采样都会触发）
# 入站口径：auto=优先用 ss 的 TCP bytes_received（rchar 在 Debian 6.1 上不计 socket 读），
# rchar=强制走 /proc/io（仅本地文件读，网络入站会接近 0，仅作降级）。
TRAFFIC_INBOUND = os.environ.get("RELAY_TRAFFIC_INBOUND", "auto").lower()
SS_BIN = shutil.which("ss") or "/usr/bin/ss"
# =========================================================================
ALLOW_HOST_API = os.environ.get(
    "ALLOW_HOST_API", "http://100.83.142.107:3000/api/allow_reply_host")
ALLOW_HOST_CACHE = os.environ.get(
    "ALLOW_HOST_CACHE",
    os.path.join(os.path.dirname(os.path.abspath(__file__)),
                 "relay_allow_hosts.cache.json"))
ALLOW_HOST_INTERVAL = int(os.environ.get("ALLOW_HOST_INTERVAL", "60"))
ALLOW_HOST_MAX = 200  # 名单条数上限，防止异常响应撑爆判断循环

UA = {"User-Agent": "Mozilla/5.0"}
# 内置默认只在「首次启动且本地缓存不可用」时使用；之后以服务端下发为准。
DEFAULT_ACCEPT_HOST = ['jdshipin.com']
_HOST_RE = re.compile(
    r"^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+"
    r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$")

_hosts_lock = threading.Lock()
_accept_host = list(DEFAULT_ACCEPT_HOST)


def _normalize_hosts(raw):
    """校验接口返回的 allow_reply_host；非法返回 None（调用方沿用上次成功值）。"""
    if not isinstance(raw, list):
        return None
    if len(raw) > ALLOW_HOST_MAX:
        print("白名单条数 %d 超过上限 %d，整份名单视为无效"
              % (len(raw), ALLOW_HOST_MAX), flush=True)
        return None
    hosts = []
    seen = set()
    for item in raw:
        if not isinstance(item, str):
            print("白名单含非字符串条目，整份名单视为无效", flush=True)
            return None
        host = item.strip().lower()
        if host == "*":
            # 转发机带宽有限，裸 * 会把全部域名压过来；整份名单视为无效。
            print("白名单含裸 *，整份名单视为无效", flush=True)
            return None
        if host.startswith("*."):
            host = host[2:]
        host = host.rstrip(".")
        if not host or not _HOST_RE.match(host):
            print("白名单含非法域名 %r，整份名单视为无效" % item, flush=True)
            return None
        if host not in seen:
            seen.add(host)
            hosts.append(host)
    return hosts


def _load_host_cache():
    try:
        with open(ALLOW_HOST_CACHE, "r", encoding="utf-8") as f:
            return _normalize_hosts(json.load(f))
    except FileNotFoundError:
        return None
    except Exception as e:
        print("读取白名单缓存失败: %s" % e, flush=True)
        return None


def _save_host_cache(hosts):
    tmp = ALLOW_HOST_CACHE + ".tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(hosts, f, ensure_ascii=False)
        os.replace(tmp, ALLOW_HOST_CACHE)
    except Exception as e:
        print("写白名单缓存失败: %s" % e, flush=True)


def _fetch_allow_hosts():
    """拉取服务端白名单；任何失败/非法都返回 None，绝不影响 relay 服务。"""
    try:
        with urlopen(Request(ALLOW_HOST_API, headers=UA), timeout=10) as r:
            body = r.read()
        payload = json.loads(body.decode("utf-8", "replace"))
        if not isinstance(payload, dict) or payload.get("code") != 0:
            raise ValueError("响应 code 非 0")
        data = payload.get("data")
        if not isinstance(data, dict):
            raise ValueError("响应缺少 data")
        hosts = _normalize_hosts(data.get("allow_reply_host"))
        if hosts is None:
            raise ValueError("白名单内容非法")
        return hosts
    except Exception as e:
        print("拉取白名单失败: %s" % e, flush=True)
        return None


def _allow_host_loop():
    global _accept_host
    while True:
        hosts = _fetch_allow_hosts()
        if hosts is not None:
            with _hosts_lock:
                _accept_host = hosts
            _save_host_cache(hosts)
            print("白名单已更新: %s"
                  % (hosts if hosts else "(空 = 全部直连)"), flush=True)
        else:
            print("本次拉取失败，沿用上次白名单: %s"
                  % (_accept_host if _accept_host else "(空 = 全部直连)"),
                  flush=True)
        time.sleep(max(5, ALLOW_HOST_INTERVAL))


def _init_allow_hosts():
    """启动时先用本地缓存，再起后台轮询；拉取失败不影响服务。"""
    global _accept_host
    cached = _load_host_cache()
    if cached is not None:
        _accept_host = cached
        print("白名单已从本地缓存加载: %s"
              % (cached if cached else "(空 = 全部直连)"), flush=True)
    else:
        print("无可用白名单缓存，使用内置默认: %s" % _accept_host, flush=True)
    threading.Thread(target=_allow_host_loop, daemon=True).start()


def _allowed_host(url):
    """src 域名白名单：仅当前名单中的域名（含其子域）可访问，其余拒绝。
    名单由服务端每 60 秒下发；空名单 = 全部拒绝（客户端空名单时不会把源路由
    到 relay）。裸 * 永远不会进入名单，不会退化成全部放行。"""
    try:
        host = (urlparse(url).hostname or "").lower().rstrip(".")
    except ValueError:
        return False
    with _hosts_lock:
        allowed = list(_accept_host)
    return any(host == d or host.endswith("." + d) for d in allowed)


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
LIVE_V_BITRATE = "670k"
LIVE_HLS_TIME = 2  # 分片时长（秒）
LIVE_LIST_SIZE = 12  # 加大窗口：mpv 落后 10-20 秒内仍能续上，不滚出丢段
LIVE_HIDE_TAIL = 4  # 列表尾部隐藏的最新分片数（×2s≈8s 余量）：让 mpv 落在产出边缘后方，吸收分片产出抖动
LIVE_IDLE_SECONDS = 60  # 会话空闲多久后杀 ffmpeg 并清临时目录
LIVE_MAX_SESSIONS = 4  # 同时保留的转码会话上限：换源即杀旧会话，防多 ffmpeg 堆积挤爆 1 核
LIVE_STARTUP_TIMEOUT = 25  # 等首个转码列表的最长时间（秒）
LIVE_DEV_KILL_GRACE = 10  # 换源杀旧宽限（秒）：同设备仅杀 used 超过该时长的会话，防在途迟到请求误杀新会话
LIVE_MAX_W = 1920  # 入站分辨率上限（宽）：超过则拒绝转码——4K 入站流量太大（按入站+出站计费）
LIVE_MAX_H = 1080  # 入站分辨率上限（高）

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
    if "seg_max_retry" in text:
        # 单分片失败重试次数（默认 5）：上游抖动多扛几跳，减少断流导致的进程退出重建
        opts += ["-seg_max_retry", "10"]
    _hls_opts_cache = opts
    print("live: ffmpeg hls 放行选项 %s" % (opts or "(未探测到)"), flush=True)
    return opts

_sessions = {}  # sid -> {proc, dir, playlist, used}
_sessions_lock = threading.Lock()
_segno = {}  # sid -> 已产出的最大分片号（跨重建记忆，供 -start_number 续号）


def _sid(src):
    return hashlib.md5(src.encode("utf-8")).hexdigest()[:12]


# ===== 流量采样：出站读 ffmpeg 的 /proc/<pid>/io(wchar)，入站读 TCP bytes_received =====
# 实测 Debian 6.1 内核下 rchar 不计 socket recv（5MB 下载仅 +96B），所以入站默认用
# `ss -tinp` 的 bytes_received 按源会话汇总；rchar 仅作 ss 不可用时的降级口径。
# 只记录主机名 + 源地址短哈希（即 /live.m3u8 里已出现的 sid），
# 不写完整 URL、query、token；采样失败只打日志，绝不影响转发。
_traffic_lock = threading.Lock()
_traffic_prev = {}  # sid -> {pid,t,rchar,wchar,sockets,in_total,out_total}
_traffic_last_trim = 0.0


def _traffic_source(src):
    """把源地址压成 (主机名, 12 位短哈希)；URL 其余部分全部丢弃。"""
    try:
        host = (urlparse(src).hostname or "").lower().rstrip(".")
    except ValueError:
        host = ""
    return host or "-", _sid(src)


def _read_proc_io(pid):
    """读取 /proc/<pid>/io 的 rchar/wchar；进程已退或权限不足返回 None。"""
    try:
        vals = {}
        with open("/proc/%d/io" % pid, "r") as fh:
            for line in fh:
                key, sep, value = line.partition(":")
                if sep and key in ("rchar", "wchar"):
                    vals[key] = int(value.strip())
        if "rchar" in vals and "wchar" in vals:
            return vals["rchar"], vals["wchar"]
    except Exception:
        pass
    return None


def _read_ss_all():
    """一次 ss 采样，返回 {pid: {local_addr: bytes_received}}；不可用返回 None。

    ffmpeg 以长连接读 HLS，socket 的 bytes_received 是累计值，按源会话求增量。"""
    if TRAFFIC_INBOUND == "rchar":
        return None
    try:
        out = subprocess.run([SS_BIN, "-tinp"], capture_output=True, timeout=5)
        if out.returncode != 0:
            return None
        text = out.stdout.decode("utf-8", "replace")
    except Exception:
        return None
    result = {}
    cur_pid = None
    cur_local = ""
    for line in text.splitlines():
        if not line.strip():
            continue
        if line[0] not in (" ", "\t"):
            parts = line.split()
            cur_local = parts[3] if len(parts) >= 4 else ""
            m = re.search(r"pid=(\d+)", line)
            cur_pid = int(m.group(1)) if m else None
        elif cur_pid is not None:
            m = re.search(r"bytes_received:(\d+)", line)
            if m:
                result.setdefault(cur_pid, {})[cur_local] = int(m.group(1))
    return result


def _traffic_sample_once():
    """采样一次全部存活转码会话；增量按上次采样时间折算。"""
    now = time.time()
    with _sessions_lock:
        sessions = [
            (sid, s.get("src", ""), s["proc"].pid)
            for sid, s in _sessions.items()
            if s["proc"].poll() is None
        ]
    ss_data = _read_ss_all()
    rows = []
    with _traffic_lock:
        alive = set()
        for sid, src, pid in sessions:
            io = _read_proc_io(pid)
            if io is None:
                continue
            rchar, wchar = io
            sockets = None if ss_data is None else ss_data.get(pid, {})
            alive.add(sid)
            prev = _traffic_prev.get(sid)
            if prev is None or prev.get("pid") != pid:
                # 首次采样/同 sid 换进程：只建基线，不写零值记录
                _traffic_prev[sid] = {
                    "pid": pid, "t": now, "rchar": rchar, "wchar": wchar,
                    "sockets": sockets or {}, "in_total": 0, "out_total": 0,
                }
                continue
            dt = now - prev["t"]
            if dt <= 0:
                continue
            dw = wchar - prev["wchar"]
            if dw < 0:
                _traffic_prev[sid] = {
                    "pid": pid, "t": now, "rchar": rchar, "wchar": wchar,
                    "sockets": sockets or {}, "in_total": 0, "out_total": 0,
                }
                continue
            if sockets is not None:
                base = prev.get("sockets") or {}
                di = 0
                for addr, value in sockets.items():
                    old = base.get(addr)
                    if old is not None and value >= old:
                        di += value - old
                    else:
                        di += value  # 新连接（或端口复用）：从 0 起算
                isrc = "ss"
            else:
                dr = rchar - prev["rchar"]
                if dr < 0:
                    _traffic_prev[sid] = {
                        "pid": pid, "t": now, "rchar": rchar, "wchar": wchar,
                        "sockets": {}, "in_total": 0, "out_total": 0,
                    }
                    continue
                di = dr
                isrc = "rchar"
            in_total = prev["in_total"] + di
            out_total = prev["out_total"] + dw
            host, short = _traffic_source(src)
            rows.append({
                "t": round(now, 3),
                "host": host,
                "sid": short,
                "din": di,
                "dout": dw,
                "in": in_total,
                "out": out_total,
                "dt": round(dt, 3),
                "iv": TRAFFIC_INTERVAL,
                "ret": TRAFFIC_RETENTION,
                "isrc": isrc,
            })
            _traffic_prev[sid] = {
                "pid": pid, "t": now, "rchar": rchar, "wchar": wchar,
                "sockets": sockets or {}, "in_total": in_total,
                "out_total": out_total,
            }
        for sid in list(_traffic_prev):
            if sid not in alive:
                _traffic_prev.pop(sid, None)
    if rows:
        _traffic_write(rows)
    _traffic_maybe_trim(now)


def _traffic_write(rows):
    try:
        text = "".join(
            json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n"
            for row in rows)
        with open(TRAFFIC_FILE, "a", encoding="utf-8") as fh:
            fh.write(text)
    except Exception as e:
        print("流量采样写入失败(不影响转发): %s" % e, flush=True)


def _traffic_maybe_trim(now):
    global _traffic_last_trim
    try:
        size = os.path.getsize(TRAFFIC_FILE)
    except OSError:
        return
    # 文件超限每次都修剪；否则最多每 5 分钟按时间清一次旧记录
    if size <= TRAFFIC_MAX_BYTES and now - _traffic_last_trim < TRAFFIC_TRIM_EVERY:
        return
    _traffic_last_trim = now
    _traffic_trim(now)


def _traffic_trim(now=None):
    """按保留时长与文件大小滚动修剪；任何异常只打日志。"""
    now = now or time.time()
    cutoff = now - TRAFFIC_RETENTION
    try:
        current_size = os.path.getsize(TRAFFIC_FILE)
    except OSError:
        return
    # 超限时一次裁到 90%，避免每轮采样都重写整份文件（1 核机器上必须留余量）
    target = (int(TRAFFIC_MAX_BYTES * 0.9)
              if current_size > TRAFFIC_MAX_BYTES else TRAFFIC_MAX_BYTES)
    keep = []
    stale = 0
    try:
        with open(TRAFFIC_FILE, "r", encoding="utf-8", errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    t = float(json.loads(line).get("t") or 0)
                except Exception:
                    continue
                if t >= cutoff:
                    keep.append(line)
                else:
                    stale += 1
    except FileNotFoundError:
        return
    except Exception as e:
        print("流量历史修剪读取失败(不影响转发): %s" % e, flush=True)
        return
    total = sum(len(line.encode("utf-8")) + 1 for line in keep)
    drop = 0
    while total > target and drop < len(keep):
        total -= len(keep[drop].encode("utf-8")) + 1
        drop += 1
    keep = keep[drop:]
    if not stale and not drop:
        return
    tmp = TRAFFIC_FILE + ".tmp"
    try:
        with open(tmp, "w", encoding="utf-8") as fh:
            fh.write("".join(line + "\n" for line in keep))
        os.chmod(tmp, 0o644)
        os.replace(tmp, TRAFFIC_FILE)
        print("流量历史修剪: 清理过期 %d 行、超限 %d 行，保留 %d 行/%d 字节"
              % (stale, drop, len(keep), total), flush=True)
    except Exception as e:
        print("流量历史修剪写入失败(不影响转发): %s" % e, flush=True)
        try:
            os.unlink(tmp)
        except Exception:
            pass


def _traffic_start():
    """创建流量文件并启动采样线程；失败不影响 relay 主服务。"""
    try:
        parent = os.path.dirname(TRAFFIC_FILE)
        if parent and not os.path.isdir(parent):
            os.makedirs(parent, exist_ok=True)
        if not os.path.exists(TRAFFIC_FILE):
            with open(TRAFFIC_FILE, "a", encoding="utf-8"):
                pass
        os.chmod(TRAFFIC_FILE, 0o644)  # app_server 以非 root 读取
        threading.Thread(target=_traffic_loop, daemon=True).start()
        print("流量采样已启动: %s 间隔=%ds 保留=%ds 上限=%d 字节"
              % (TRAFFIC_FILE, TRAFFIC_INTERVAL, TRAFFIC_RETENTION,
                 TRAFFIC_MAX_BYTES), flush=True)
    except Exception as e:
        print("流量采样初始化失败(不影响转发): %s" % e, flush=True)


def _traffic_loop():
    while True:
        try:
            _traffic_sample_once()
        except Exception as e:
            print("流量采样异常(不影响转发): %s" % e, flush=True)
        time.sleep(TRAFFIC_INTERVAL)


def _drop_session(sid):
    s = _sessions.pop(sid, None)
    if not s:
        return
    # 记录已产出的最大分片号：会话重建时用 -start_number 续号，
    # 避免 MEDIA-SEQUENCE 归零让播放器把新列表当成失效列表而干等
    try:
        with open(s["playlist"], "rb") as fh:
            text = fh.read().decode("utf-8", "replace")
        nums = [int(m) for m in re.findall(r"seg(\d+)\.ts", text)]
        if nums:
            _segno[sid] = max(nums)
    except Exception:
        pass
    try:
        s["proc"].kill()
    except Exception:
        pass
    try:
        # kill 后同步收尸：不留 <defunct> 僵尸壳。若该 Popen 还被某个
        # 处理线程引用着，Python 会等 GC 才延迟回收，壳就一直挂着。
        s["proc"].wait(timeout=5)
    except Exception:
        pass
    shutil.rmtree(s["dir"], ignore_errors=True)


_overlimit = set()  # 已判定入站分辨率超限的源 URL（进程内记忆：命中后 Popen 前直接拦截）


def _probe_resolution(src):
    """抓 1 秒内容探测入站视频分辨率，返回 (ok, w, h)；探测不到分辨率时 (False, 0, 0)。"""
    try:
        p = subprocess.run(
            [FFMPEG, "-hide_banner", "-nostdin", "-loglevel", "info",
             "-user_agent", UA["User-Agent"]] + _hls_allowed_opts() + [
                "-i", src, "-t", "1", "-f", "null", "-",
            ],
            capture_output=True, timeout=20,
        )
    except Exception:
        return False, 0, 0
    for line in p.stderr.decode("utf-8", "replace").splitlines():
        if "Video:" in line:
            m = re.search(r"(\d{2,5})x(\d{2,5})", line)
            if m:
                return True, int(m.group(1)), int(m.group(2))
    return False, 0, 0


def _live_session(src, dev=""):
    """按源地址复用一个 ffmpeg 会话；进程已死则自动重建。调用方须持 _sessions_lock。

    dev 为 App 附带的设备号（可为空）：带 dev 的请求到来时，同设备名下
    其它源的会话立即淘汰（换源即杀），不再等 60s 空闲回收。"""
    if src in _overlimit:
        # 已知超限源：Popen 之前拦截，连探测入站流量都不再产生
        print("源已判定超限（>%dx%d），跳过转码: %s"
              % (LIVE_MAX_W, LIVE_MAX_H, src), flush=True)
        raise RuntimeError("源分辨率超限，已跳过转码")
    sid = _sid(src)
    # 同设备换源即杀：淘汰该设备名下其它源的会话（当前源除外）。
    # 宽限保护：只杀 used 距今超过 LIVE_DEV_KILL_GRACE 的旧会话——轮播切源时
    # 上一源的迟到请求会晚一步到达，若无宽限它会把刚创建、还在等出列表的
    # 新会话误杀（ffmpeg code=-9 → 502 → 播不出来死循环）
    if dev:
        now = time.time()
        for other_sid in list(_sessions):
            other = _sessions[other_sid]
            if (other_sid != sid and other.get("dev") == dev
                    and now - other.get("used", 0) >= LIVE_DEV_KILL_GRACE):
                print("设备 %s 换源，立即淘汰旧会话 %s"
                      % (dev, other.get("src", other_sid)), flush=True)
                _drop_session(other_sid)
    s = _sessions.get(sid)
    if s and s["proc"].poll() is None:
        s["used"] = time.time()
        if dev:
            s["dev"] = dev
        return s
    if s:
        _drop_session(sid)
    # 上限保护：起新会话前先杀掉最旧的其它会话（换源即顶替，防止转码进程堆积）
    while len(_sessions) >= LIVE_MAX_SESSIONS:
        old_sid, old = min(_sessions.items(), key=lambda kv: kv[1]["used"])
        print("会话数已达上限(%d)，淘汰最旧会话 %s"
              % (LIVE_MAX_SESSIONS, old.get("src", old_sid)), flush=True)
        _drop_session(old_sid)
    d = tempfile.mkdtemp(prefix="relay_live_%s_" % sid)
    playlist = os.path.join(d, "out.m3u8")
    # 重建续号：从上次会话最大段号 +1 继续（序号单调递增，播放器把它当作
    # 正常推进的 live 而非归零的失效列表，重建空窗从 30s+ 缩到 1~2 个轮询）
    start_no = _segno.get(sid, -1) + 1
    # HTTP 协议级重连：上游短暂断流先自愈，减少进程退出（退出即重建）
    retry_opts = (
        ["-reconnect", "1", "-reconnect_streamed", "1",
         "-reconnect_delay_max", "5"]
        if src.startswith(("http://", "https://")) else []
    )
    cmd = [
        FFMPEG, "-nostdin", "-loglevel", "error",
        "-user_agent", UA["User-Agent"],
    ] + _hls_allowed_opts() + retry_opts + [
        "-re",  # 按实时节奏读输入：否则快于实时的源会让列表超前 mpv，导致跳段卡顿
        "-i", src,
        "-vf", "scale=-2:%s" % LIVE_HEIGHT,
        "-c:v", "libx264", "-preset", "veryfast",
        "-b:v", LIVE_V_BITRATE, "-maxrate", LIVE_V_BITRATE, "-bufsize", "1600k",
        "-c:a", "aac", "-b:a", "96k",
        # 强制 2 秒一个关键帧再切段：否则源 GOP 长（~10s）时单段能到 1MB，
        # 链路抖动窗口内传不完会把播放器饿死
        "-force_key_frames", "expr:gte(t,n_forced*%d)" % LIVE_HLS_TIME,
        "-f", "hls", "-hls_time", str(LIVE_HLS_TIME),
        "-hls_list_size", str(LIVE_LIST_SIZE),
        "-hls_delete_threshold", "10",  # 滚出列表后再留 10 个才删，防 mpv 慢半拍取到列表却 404
        "-hls_flags", "delete_segments",
        "-hls_segment_filename", os.path.join(d, "seg%05d.ts"),
        "-start_number", str(start_no),  # 重建续号，序号跨会话单调递增
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
    s = {"proc": proc, "dir": d, "playlist": playlist, "used": time.time(),
         "src": src, "dev": dev}
    _sessions[sid] = s
    print("会话创建: %s dev=%s (当前 %d/%d)"
          % (src, dev or "-", len(_sessions), LIVE_MAX_SESSIONS), flush=True)
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
                self.serve_live_playlist(p["src"][0], p.get("dev", [""])[0])
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
        if not _allowed_host(src):
            print("不支持的Host地址: %s" % src)
            self.send_error(403, "src host not in allow-list")
            return
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
        # /fetch 是分片直取入口，必须和白名单一起校验，否则可被用来代理任意域名
        if not _allowed_host(url):
            print("不支持的Host地址: %s" % url)
            self.send_error(403, "src host not in allow-list")
            return
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

    def serve_live_playlist(self, src, dev=""):
        """起（或复用）ffmpeg 转码会话，返回分片地址改写为 /liveseg 的转码后列表。"""
        if not _allowed_host(src):
            # 白名单在起会话之前拦：非白名单域名直接 403，不产生 ffmpeg 进程与入站流量
            print("live src host 不在白名单，拒绝: %s" % src, flush=True)
            self.send_error(403, "src host not in allow-list")
            return
        t0 = time.perf_counter()
        with _sessions_lock:
            s = _live_session(src, dev)
        if not s.get("probed"):
            # 每个会话只探测一次入站分辨率：超 1080p（如 4K）即记黑名单并杀会话，
            # 此后同源在 Popen 前被拦截，不再产生入站流量
            ok, w, h = _probe_resolution(src)
            s["probed"] = True
            if ok and (w > LIVE_MAX_W or h > LIVE_MAX_H):
                _overlimit.add(src)
                with _sessions_lock:
                    _drop_session(_sid(src))
                print("探测到源分辨率 %dx%d 超过上限 %dx%d，拒绝转码: %s"
                      % (w, h, LIVE_MAX_W, LIVE_MAX_H, src), flush=True)
                raise RuntimeError("源分辨率超限，拒绝转码")
        if not _wait_ready(s):
            raise RuntimeError("ffmpeg 未生成转码列表（源不可读？）")
        with open(s["playlist"], "rb") as fh:
            body = fh.read()
        # 掐掉最新几段（不回放给 mpv），使其贴在产出边缘后方 ~8s，吸收分片产出抖动；
        # 但启动期段数少时最多掐到「至少保留 2 段」，否则新会话前 ~10s 返回空列表，
        # 播放器无视频轨判成音频、一直缓冲，轮播时更易触发 60s 看门狗换源
        lines = [l for l in body.decode("utf-8", "replace").splitlines() if l.strip()]
        nseg = sum(1 for l in lines if not l.startswith("#"))
        hide = min(LIVE_HIDE_TAIL, max(0, nseg - 2))
        hidden = 0
        while hidden < hide and lines and not lines[-1].startswith("#"):
            lines.pop()  # 最新分片 URI
            if lines and lines[-1].startswith("#EXTINF"):
                lines.pop()  # 对应的 #EXTINF 行
            hidden += 1
        sid = _sid(src)
        out = []
        for line in lines:
            if not line.startswith("#"):
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


class _QuietHTTPServer(ThreadingHTTPServer):
    """压掉 keep-alive 噪音：客户端提前重置/断开连接（切源、原地重载、
    播放器超时挂断）时，socketserver 默认打印整屏 traceback，冲掉有用日志。"""

    def handle_error(self, request, client_address):
        exc = sys.exc_info()[1]
        if isinstance(exc, (ConnectionResetError, BrokenPipeError)):
            print(
                "%s client断开 keep-alive 连接(errno=%s) %s"
                % (time.strftime("%H:%M:%S"), getattr(exc, "errno", "?"), client_address),
                flush=True,
            )
            return
        super().handle_error(request, client_address)


def _sweep_orphans():
    """启动时清扫上次异常退出遗留的孤儿转码进程。

    pkill 停 relay 只杀 python，ffmpeg 孩子会被过继给 init 成为孤儿，
    而 reaper 随旧进程一起死亡，再无人回收（实测堆积 3 个持续烧 CPU
    与上游入站流量）。ffmpeg 命令行必然含临时目录串 `relay_live_`，
    本进程是 `python3 relay.py` 不含该串，pkill -f 不会误伤自己。"""
    try:
        r = subprocess.run(["pkill", "-f", "relay_live_"], capture_output=True, timeout=10)
    except Exception:
        return
    if r.returncode == 0:
        print("清扫: 已清理上次遗留的孤儿 ffmpeg 转码进程", flush=True)


def _on_shutdown(signum, _frame):
    """SIGTERM（pkill）/ SIGINT（Ctrl+C）时带走全部转码进程，不产生孤儿。

    不取 _sessions_lock：信号打断的是主线程，锁可能正被工作线程持有，
    拿锁有死锁风险；_drop_session 内部 pop 幂等，重复/并发调用无害。"""
    print("收到信号 %s，清理全部转码会话后退出" % signum, flush=True)
    for sid in list(_sessions):
        try:
            _drop_session(sid)
        except Exception:
            pass
    os._exit(0)


if __name__ == "__main__":
    signal.signal(signal.SIGTERM, _on_shutdown)
    signal.signal(signal.SIGINT, _on_shutdown)
    _sweep_orphans()
    _init_allow_hosts()
    threading.Thread(target=_reaper_loop, daemon=True).start()
    _traffic_start()
    print(
        "relay on %s (token=%s) live=ffmpeg %sp/%s x%d"
        % (BASE, TOKEN, LIVE_HEIGHT, LIVE_V_BITRATE, os.cpu_count() or 0),
        flush=True,
    )
    _QuietHTTPServer(("0.0.0.0", PORT), Relay).serve_forever()
