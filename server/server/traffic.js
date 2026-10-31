// 接口流量统计（HTTP + WebSocket）。
//
// 目标：回答"每个接口在外网访问时消耗了多少流量"。
// - HTTP：在 Express 最外层包中间件，上行按实际收到的 body 字节计，
//   下行包装 res.write / res.end 累计（覆盖 JSON、sendFile、static 流式响应）。
// - WebSocket：realtime.js 在每个连接上包装 ws.send 并监听 message，
//   按通道（/ws、/ws/clipboard）与账号累计。
// - 来源分三类：wan（公网直连）、tail（Tailscale）、lan（本机/内网），
//   判断依据是连接对端 IP。
// - 聚合粒度为"天"：内存累计 + 每分钟原子落盘 datas/stats/traffic-YYYY-MM-DD.json，
//   重启时加载当天文件继续累计，启动时清理 KEEP_DAYS 天前的旧文件。
//
// 口径说明：统计的是应用层有效载荷（HTTP body / WS JSON 帧），
// 不含 TCP/IP/TLS 头，WS 不含握手帧与压缩收益——比抓包数字略小，
// 但接口之间可比，足以定位流量大头。

const fs = require('fs');
const path = require('path');

const KEEP_DAYS = 30;
const FLUSH_INTERVAL_MS = 60 * 1000;

function emptyBucket() {
    return { count: 0, in: 0, out: 0 };
}

function emptyDay(date) {
    return {
        date,
        // http[scope][`METHOD /route`] = { count, in, out }
        http: { wan: {}, tail: {}, lan: {} },
        // ws[scope][channel] = { count(消息数), in, out }
        ws: { wan: {}, tail: {}, lan: {} },
        // wsAccounts[scope][account] = { in, out }
        wsAccounts: { wan: {}, tail: {}, lan: {} },
    };
}

function todayStr() {
    // 服务器固定东八区，直接用本地时间即可
    const now = new Date();
    const pad = (n) => String(n).padStart(2, '0');
    return `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())}`;
}

function normalizeIp(ip) {
    return String(ip || '').replace(/^::ffff:/, '');
}

/** 归一化来源 IP → wan / tail / lan。 */
function classifyIp(ip) {
    const value = normalizeIp(ip);
    if (!value) return 'lan'; // 来源不明按内网算，避免污染外网统计
    if (value === '::1' || value.startsWith('127.')) return 'lan';
    if (value.startsWith('10.') || value.startsWith('192.168.')) return 'lan';
    if (/^172\.(1[6-9]|2\d|3[01])\./.test(value)) return 'lan'; // 含 docker0 172.17
    if (value.startsWith('169.254.') || value.startsWith('fe80:')) return 'lan';
    // Tailscale：IPv4 CGNAT 100.64/10，IPv6 ULA fd7a:115c:a1e0::/48
    if (/^100\.(6[4-9]|[7-9]\d|1[01]\d|12[0-7])\./.test(value)) return 'tail';
    if (value.startsWith('fd7a:115c:a1e0')) return 'tail';
    return 'wan';
}

function byteLengthOf(data) {
    if (typeof data === 'string') return Buffer.byteLength(data);
    if (Buffer.isBuffer(data)) return data.length;
    if (ArrayBuffer.isView(data)) return data.byteLength;
    return 0;
}

/** 请求归类：已匹配路由用模板（/api/download/:filename），静态资源按扩展名。 */
function routeKeyOf(req) {
    if (req.route && typeof req.route.path === 'string') {
        return `${req.method} ${req.baseUrl || ''}${req.route.path}`;
    }
    const pathname = req.path || String(req.url || '').split('?')[0];
    if (pathname.startsWith('/api/')) {
        // 未匹配任何路由的 API 路径：数字段归一化，防止基数爆炸
        return `${req.method} ${pathname.replace(/\d+/g, ':n')}`;
    }
    // 静态资源 / SPA 页面
    return `static ${path.extname(pathname).toLowerCase() || '(page)'}`;
}

function readJson(file, fallback) {
    try {
        if (!fs.existsSync(file)) return fallback;
        return JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch (_) {
        return fallback;
    }
}

function createTrafficTracker(datasDir) {
    const statsDir = path.join(datasDir, 'stats');
    const fileOf = (date) => path.join(statsDir, `traffic-${date}.json`);

    function pruneOldFiles() {
        try {
            if (!fs.existsSync(statsDir)) return;
            const cutoff = Date.now() - KEEP_DAYS * 24 * 60 * 60 * 1000;
            for (const name of fs.readdirSync(statsDir)) {
                const match = /^traffic-(\d{4}-\d{2}-\d{2})\.json$/.exec(name);
                if (!match) continue;
                const stamp = Date.parse(`${match[1]}T00:00:00+08:00`);
                if (Number.isFinite(stamp) && stamp < cutoff) {
                    fs.unlinkSync(path.join(statsDir, name));
                }
            }
        } catch (error) {
            console.error('[traffic] 清理旧统计文件失败:', error.message);
        }
    }

    function loadDay(date) {
        const saved = readJson(fileOf(date), null);
        if (saved && saved.http && saved.ws) return saved;
        return emptyDay(date);
    }

    let day = loadDay(todayStr());
    pruneOldFiles();

    let dirty = false;

    function rollDateIfNeeded() {
        const today = todayStr();
        if (today === day.date) return;
        flush();
        day = loadDay(today);
        dirty = true;
    }

    function flush() {
        if (!dirty) return;
        dirty = false;
        try {
            fs.mkdirSync(statsDir, { recursive: true });
            const tmp = `${fileOf(day.date)}.tmp`;
            fs.writeFileSync(tmp, JSON.stringify(day), 'utf8');
            fs.renameSync(tmp, fileOf(day.date));
        } catch (error) {
            dirty = true;
            console.error('[traffic] 落盘失败:', error.message);
        }
    }

    const flushTimer = setInterval(flush, FLUSH_INTERVAL_MS);
    flushTimer.unref();
    // pm2 restart 默认发 SIGINT，进程被信号杀掉不会走 exit 事件，这里显式落盘
    for (const signal of ['SIGINT', 'SIGTERM']) {
        process.once(signal, () => {
            flush();
            process.exit(0);
        });
    }

    function bump(map, key, inBytes, outBytes, count) {
        let bucket = map[key];
        if (!bucket) {
            bucket = emptyBucket();
            map[key] = bucket;
        }
        bucket.count += count;
        bucket.in += inBytes;
        bucket.out += outBytes;
    }

    // ------------------------------------------------------------ HTTP

    function middleware(req, res, next) {
        const scope = classifyIp(req.ip || (req.socket && req.socket.remoteAddress));
        let inBytes = 0;
        let outBytes = 0;

        // 实际收到的上行字节（上传接口的真实消耗）。中间件链是同步执行的，
        // 这里挂 data 监听不会与下游 body-parser / multer 的读取产生竞争。
        req.on('data', (chunk) => {
            inBytes += chunk.length;
        });

        const origWrite = res.write;
        const origEnd = res.end;
        res.write = function (chunk, ...args) {
            if (chunk) outBytes += byteLengthOf(chunk);
            return origWrite.call(this, chunk, ...args);
        };
        res.end = function (chunk, ...args) {
            if (chunk && typeof chunk !== 'function') outBytes += byteLengthOf(chunk);
            return origEnd.call(this, chunk, ...args);
        };

        res.on('finish', () => {
            rollDateIfNeeded();
            bump(day.http[scope], routeKeyOf(req), inBytes, outBytes, 1);
            dirty = true;
        });
        next();
    }

    // ------------------------------------------------------------ WebSocket

    /** realtime.js 在 connection 建立时调用一次；之后收发自动计数。 */
    function wsAttach(ws, remoteAddress, channel) {
        const scope = classifyIp(remoteAddress);
        const origSend = ws.send.bind(ws);
        ws.send = (data, ...args) => {
            try {
                rollDateIfNeeded();
                const bytes = byteLengthOf(data);
                bump(day.ws[scope], channel, 0, bytes, 1);
                recordAccount(ws.account, scope, 0, bytes);
                dirty = true;
            } catch (_) {
                // 统计不能影响发送
            }
            return origSend(data, ...args);
        };
        ws.on('message', (raw) => {
            rollDateIfNeeded();
            const bytes = byteLengthOf(raw);
            bump(day.ws[scope], channel, bytes, 0, 1);
            recordAccount(ws.account, scope, bytes, 0);
            dirty = true;
        });
    }

    function recordAccount(account, scope, inBytes, outBytes) {
        if (!account) return;
        const map = day.wsAccounts[scope];
        let bucket = map[account];
        if (!bucket) {
            bucket = { in: 0, out: 0 };
            map[account] = bucket;
        }
        bucket.in += inBytes;
        bucket.out += outBytes;
    }

    // ------------------------------------------------------------ 查询

    /** 指定日期（空 = 今天）的完整统计；非今天的历史日期直接读文件。 */
    function snapshot(date) {
        flush();
        if (!date || date === day.date) return day;
        if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) return null;
        return readJson(fileOf(date), null);
    }

    /** 有统计数据的日期列表（新→旧）。 */
    function availableDates() {
        flush();
        const dates = [day.date];
        try {
            if (fs.existsSync(statsDir)) {
                for (const name of fs.readdirSync(statsDir)) {
                    const match = /^traffic-(\d{4}-\d{2}-\d{2})\.json$/.exec(name);
                    if (match && match[1] !== day.date) dates.push(match[1]);
                }
            }
        } catch (_) {
            // 目录不可读时只返回今天
        }
        return dates.sort().reverse();
    }

    return { middleware, wsAttach, snapshot, availableDates };
}

module.exports = { createTrafficTracker, classifyIp };
