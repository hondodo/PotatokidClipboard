// 实时消息网关（WebSocket）。
//
// 与 server.js 共用同一个 HTTP 服务：客户端连接 `/ws?account=..&token=..&deviceId=..&role=..&name=..&app=..&version=..&build=..`，
// 鉴权与 HTTP 登录共用同一账号体系（datas/register/users，token 为密码 MD5），
// 通过后按账号路由消息、广播在线状态，并把离线消息与历史落到 datas/realtime。
const fs = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');

const MAX_HISTORY = 20000;
const MAX_EVENTS = 5000;
const MAX_BODY_LENGTH = 16 * 1024;
const MAX_EVENT_DATA_LENGTH = 16 * 1024;
// 状态帧（场景 + 完整频道列表）比普通事件大得多：近千个频道名约 20KB。
const MAX_STATE_LENGTH = 64 * 1024;
const MAX_OUTBOX = 200;
const HEARTBEAT_MS = 30000;
const ACCOUNT_PATTERN = /^[A-Za-z0-9_.:-]{1,64}$/;
const EVENT_NAME_PATTERN = /^[A-Za-z0-9_.:-]{1,64}$/;

/** 面板类型：中控屏 home / 电视端 tv。 */
const KIND_PATTERN = /^[A-Za-z0-9_.:-]{1,16}$/;

/** 旧版客户端不显式声明 kind 时，按包名兜底推断（与服务端/客户端同一张表）。 */
const APP_KIND_ALIASES = {
    'potatokid.tools.homecontroller': 'home',
    'screen.potatokid.tools': 'tv',
    'screen.potatokid.potatokid_screen': 'tv',
    potatokid_screen: 'tv',
};

function kindOf(app) {
    return APP_KIND_ALIASES[app] || '';
}

/** 逐帧调试日志开关：REALTIME_DEBUG=1 时打印每个入站帧及请求类命令。 */
const DEBUG = process.env.REALTIME_DEBUG === '1';

function log(...args) {
    if (DEBUG) console.log('[realtime]', ...args);
}

/** 从文件尾部倒序分块读取，凑够 maxRecords 行即停止，避免启动时全量加载。 */
function readTail(file, maxRecords) {
    const chunkSize = 1024 * 1024;
    let fd;
    try {
        fd = fs.openSync(file, 'r');
    } catch (_) {
        return '';
    }
    try {
        let pos = fs.fstatSync(fd).size;
        const chunks = [];
        let newlines = 0;
        while (pos > 0 && newlines <= maxRecords) {
            const len = Math.min(chunkSize, pos);
            pos -= len;
            const buf = Buffer.allocUnsafe(len);
            fs.readSync(fd, buf, 0, len, pos);
            chunks.unshift(buf);
            for (let i = 0; i < len; i++) {
                if (buf[i] === 0x0a) newlines++;
            }
        }
        const text = Buffer.concat(chunks).toString('utf8');
        if (pos === 0) return text;
        // 块边界可能截断首行，丢弃这段不完整的行
        const nl = text.indexOf('\n');
        return nl === -1 ? '' : text.slice(nl + 1);
    } finally {
        fs.closeSync(fd);
    }
}

/** 读取 JSONL 历史（启动时只载入尾部最近的 MAX_HISTORY 条，写入时追加）。 */
function loadHistory(file) {
    const records = [];
    if (!fs.existsSync(file)) return records;
    for (const line of readTail(file, MAX_HISTORY).split('\n')) {
        const raw = line.trim();
        if (!raw) continue;
        try {
            const item = JSON.parse(raw);
            if (item && item.id && item.from && item.to) records.push(item);
        } catch (_) {
            // 跳过损坏行
        }
    }
    return records.length > MAX_HISTORY ? records.slice(records.length - MAX_HISTORY) : records;
}

/** 读取结构化事件 JSONL，仅保留尾部最近 MAX_EVENTS 条。 */
function loadEvents(file) {
    const records = [];
    if (!fs.existsSync(file)) return records;
    for (const line of readTail(file, MAX_EVENTS).split('\n')) {
        const raw = line.trim();
        if (!raw) continue;
        try {
            const item = JSON.parse(raw);
            if (item && item.id && item.from && item.event) records.push(item);
        } catch (_) {
            // 跳过损坏行
        }
    }
    return records.length > MAX_EVENTS ? records.slice(records.length - MAX_EVENTS) : records;
}

function readJson(file, fallback) {
    try {
        if (!fs.existsSync(file)) return fallback;
        return JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch (_) {
        return fallback;
    }
}

function writeJson(file, value) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, JSON.stringify(value));
}

function attachRealtime(httpServer, options = {}) {
    const wsPath = options.path || '/ws';
    // 剪贴板推送通道：与 GET /api/clipboards 同一 Cookie 身份，用推送替代客户端轮询。
    const clipboardPath = options.clipboardPath || '/ws/clipboard';
    const readClipboardList =
        typeof options.clipboardList === 'function' ? options.clipboardList : null;
    const clipboardSummary =
        typeof options.clipboardSummary === 'function' ? options.clipboardSummary : (item) => item;
    /** account -> Set<WebSocket>：正在订阅剪贴板推送的客户端 */
    const clipboardConnections = new Map();
    // 账号存储（datas/register/users）：与 HTTP 登录同一校验；未传时拒绝所有连接。
    const accountStore = options.accountStore || null;
    // 设备表入口（由 server.js 注入 admin 的实现）：ws 保活 / 上报 / 取配置。
    const touchDevice = typeof options.touchDevice === 'function' ? options.touchDevice : () => {};
    const updateDeviceReport =
        typeof options.updateDeviceReport === 'function' ? options.updateDeviceReport : () => null;
    const configForDevice = typeof options.configFor === 'function' ? options.configFor : () => null;
    const dataDir = path.resolve(options.dataDir || path.join(__dirname, '../datas/realtime'));
    const historyFile = path.join(dataDir, 'history.jsonl');
    const eventsFile = path.join(dataDir, 'events.jsonl');
    const outboxDir = path.join(dataDir, 'outbox');
    const readsDir = path.join(dataDir, 'reads');

    fs.mkdirSync(outboxDir, { recursive: true });
    fs.mkdirSync(readsDir, { recursive: true });

    /** account -> Set<WebSocket> */
    const connections = new Map();
    /** account -> Set<WebSocket>：正在 watch 该设备状态的控制端 */
    const watchersByAccount = new Map();
    /** account -> 最近一次 state（场景 + 频道列表）；只存内存，重连由设备整体重发 */
    const states = new Map();
    const history = loadHistory(historyFile);
    const events = loadEvents(eventsFile);

    // permessage-deflate：频道列表约 20KB 且高度重复，压缩后只剩几十字节。
    const wss = new WebSocketServer({
        noServer: true,
        maxPayload: 128 * 1024,
        perMessageDeflate: { threshold: 1024, zlibDeflateOptions: { level: 6 } },
    });

    function sendJson(ws, payload) {
        if (ws.readyState !== ws.OPEN) return;
        try {
            ws.send(JSON.stringify(payload));
        } catch (error) {
            console.error(`[realtime] send failed ${ws.account || 'unknown'}:`, error.message);
        }
    }

    function broadcast(payload, except) {
        for (const sockets of connections.values()) {
            for (const ws of sockets) {
                if (ws !== except) sendJson(ws, payload);
            }
        }
    }

    function isOnline(account) {
        const sockets = connections.get(account);
        return !!sockets && sockets.size > 0;
    }

    function onlineAccounts() {
        return Array.from(connections.keys());
    }

    // 当前在线端明细（账号 + 设备号 + app/version/build）：
    // presence 只在对方新连接时广播，页面刷新后拿不到已有在线端的标识，
    // 故在 ready 帧附带 roster，加载即填充。
    function onlineRoster() {
        const roster = [];
        for (const [account, sockets] of connections.entries()) {
            const sock = Array.from(sockets).find((s) => s.deviceId || s.app) || Array.from(sockets)[0];
            if (!sock) continue;
            roster.push({
                account,
                deviceId: sock.deviceId || '',
                kind: sock.kind || kindOf(sock.app),
                app: sock.app || '',
                version: sock.version || '',
                build: sock.build || '',
            });
        }
        return roster;
    }

    /** 按设备号向在线 socket 推帧（target 是设备表主键，ws.deviceId 可能不带前缀）。 */
    function pushToDevice(targetDeviceId, payload) {
        const target = String(targetDeviceId || '').trim();
        if (!target) return 0;
        let sent = 0;
        for (const sockets of connections.values()) {
            for (const ws of sockets) {
                const id = ws.deviceId || '';
                if (!id) continue;
                if (id !== target && !target.endsWith(id)) continue;
                sendJson(ws, payload);
                sent++;
            }
        }
        return sent;
    }

    /** 把某设备的最新状态推给一个控制端（无缓存则不发）。 */
    function sendStateTo(ws, account, state) {
        if (!state) return;
        const payload = {
            t: 'state',
            from: account,
            scene: state.scene || {},
            playback: state.playback || null,
            ts: state.ts || 0,
        };
        if (state.channels) {
            payload.channels = {
                version: state.listVersion || '',
                names: state.channels,
            };
        }
        sendJson(ws, payload);
    }

    function addWatcher(account, ws) {
        let set = watchersByAccount.get(account);
        if (!set) {
            set = new Set();
            watchersByAccount.set(account, set);
        }
        set.add(ws);
        ws.watches.add(account);
    }

    function removeWatcher(account, ws) {
        ws.watches.delete(account);
        const set = watchersByAccount.get(account);
        if (!set) return;
        set.delete(ws);
        if (set.size === 0) watchersByAccount.delete(account);
    }

    /** 清理 socket 的全部订阅关系（断开/被踢时调用）。 */
    function clearWatchers(ws) {
        for (const account of Array.from(ws.watches || [])) {
            removeWatcher(account, ws);
        }
    }

    function outboxPath(account) {
        return path.join(outboxDir, `${account}.json`);
    }

    function enqueueOffline(account, message) {
        const list = readJson(outboxPath(account), []);
        list.push(message);
        const trimmed = list.length > MAX_OUTBOX ? list.slice(list.length - MAX_OUTBOX) : list;
        writeJson(outboxPath(account), trimmed);
    }

    function flushOffline(account) {
        const file = outboxPath(account);
        if (!fs.existsSync(file)) return;
        const list = readJson(file, []);
        try {
            fs.unlinkSync(file);
        } catch (_) {
            // 删除失败不影响本次投递
        }
        if (list.length > 0) {
            console.log(`[realtime] flush ${account} count=${list.length}`);
        }
        const sockets = connections.get(account);
        if (!sockets) return;
        for (const message of list) {
            for (const ws of sockets) {
                sendJson(ws, {
                    t: 'msg',
                    id: message.id,
                    from: message.from,
                    to: message.to,
                    body: message.body,
                    ts: message.ts,
                });
            }
        }
    }

    function persistMessage(message) {
        history.push(message);
        if (history.length > MAX_HISTORY) history.splice(0, history.length - MAX_HISTORY);
        try {
            fs.appendFileSync(historyFile, `${JSON.stringify(message)}\n`);
        } catch (error) {
            console.error('[realtime] persist history failed:', error.message);
        }
    }

    /** 结构化事件与聊天历史分开存放，避免动作/场景上报污染会话列表。 */
    function persistEvent(record) {
        events.push(record);
        if (events.length > MAX_EVENTS) events.splice(0, events.length - MAX_EVENTS);
        try {
            fs.appendFileSync(eventsFile, `${JSON.stringify(record)}\n`);
        } catch (error) {
            console.error('[realtime] persist event failed:', error.message);
        }
    }

    function eventsFor(account, frame) {
        const limit = Math.min(Math.max(parseInt(frame.limit, 10) || 100, 1), 200);
        const eventName = typeof frame.event === 'string' ? frame.event.trim() : '';
        const since = Math.max(parseInt(frame.since, 10) || 0, 0);
        return events
            .filter((item) => item.from === account || item.to === account)
            .filter((item) => !eventName || item.event === eventName)
            .filter((item) => !since || item.ts > since)
            .slice(-limit);
    }

    /** account -> 已读游标，启动后只在内存更新，不再每次读盘 */
    const readsCache = new Map();

    function readsFor(account) {
        let reads = readsCache.get(account);
        if (!reads) {
            reads = readJson(path.join(readsDir, `${account}.json`), {});
            readsCache.set(account, reads);
        }
        return reads;
    }

    function conversationsFor(account) {
        const byPeer = new Map();
        for (const message of history) {
            if (message.from !== account && message.to !== account) continue;
            const peer = message.from === account ? message.to : message.from;
            const current = byPeer.get(peer);
            if (!current || message.ts >= current.ts) byPeer.set(peer, message);
        }
        // 未读数单次遍历累计，避免每个会话都把整表过滤一遍
        const reads = readsFor(account);
        const unreadByPeer = new Map();
        for (const message of history) {
            if (message.to !== account) continue;
            if (!byPeer.has(message.from)) continue;
            if (message.ts > (reads[message.from] || 0)) {
                unreadByPeer.set(message.from, (unreadByPeer.get(message.from) || 0) + 1);
            }
        }
        return Array.from(byPeer.entries())
            .map(([peer, last]) => ({
                account: peer,
                lastMessage: last.body,
                ts: last.ts,
                unread: unreadByPeer.get(peer) || 0,
            }))
            .sort((a, b) => b.ts - a.ts)
            .slice(0, 100);
    }

    function historyFor(account, peer, limit) {
        const list = history.filter(
            (m) =>
                (m.from === account && m.to === peer) ||
                (m.from === peer && m.to === account),
        );
        return list.slice(Math.max(0, list.length - limit));
    }

    // ---- 合并会话线程 ---------------------------------------------------
    // 控制端进入某设备的会话时订阅：把「当前账号 + also 账号（管理员）」与
    // 该设备的聊天消息和结构化事件合并成一条时间线，并把之后的新帧转发给
    // 订阅者——这样非管理员中控端也能看到管理员与设备之间的往来。

    const MAX_THREAD_LIMIT = 200;

    /** 该帧是否属于某 socket 订阅的会话线程；命中返回 peer，否则 null。 */
    function threadPeerOf(ws, record) {
        if (!ws.threads || ws.threads.size === 0) return null;
        if (!record.from || !record.to) return null;
        for (const [peer, alsoSet] of ws.threads) {
            if (record.from !== peer && record.to !== peer) continue;
            const other = record.from === peer ? record.to : record.from;
            if (other === ws.account || alsoSet.has(other)) return peer;
        }
        return null;
    }

    /** 把符合订阅条件的帧转发给线程订阅者（已直投的 socket 跳过，避免重复）。 */
    function forwardThread(payload, skip) {
        for (const client of wss.clients) {
            if (client.readyState !== 1) continue;
            if (skip && skip.has(client)) continue;
            if (threadPeerOf(client, payload)) sendJson(client, payload);
        }
    }

    /** 合并线程快照：消息与事件按时间升序，取最近 limit 条。 */
    function threadItemsFor(account, peer, also, limit) {
        const alsoSet = new Set(also);
        const involves = (from, to) =>
            (from === peer && (to === account || alsoSet.has(to))) ||
            (to === peer && (from === account || alsoSet.has(from)));
        const items = [];
        for (const message of history) {
            if (!involves(message.from, message.to)) continue;
            items.push({
                kind: 'msg',
                id: message.id,
                from: message.from,
                to: message.to,
                text: message.body,
                ts: message.ts,
            });
        }
        for (const record of events) {
            if (!involves(record.from, record.to)) continue;
            items.push({
                kind: 'event',
                id: record.id,
                from: record.from,
                to: record.to,
                event: record.event,
                data: record.data || {},
                ts: record.ts,
            });
        }
        items.sort((a, b) => a.ts - b.ts);
        return items.slice(Math.max(0, items.length - limit));
    }

    function handleUpgrade(request, socket, head) {
        let url;
        try {
            url = new URL(request.url, 'http://localhost');
        } catch (_) {
            log(`upgrade ignored malformed url=${request.url} ip=${request.socket.remoteAddress}`);
            socket.destroy();
            return;
        }
        if (url.pathname !== wsPath && url.pathname !== clipboardPath) {
            log(`upgrade ignored path=${url.pathname} ip=${request.socket.remoteAddress}`);
            socket.destroy();
            return;
        }
        wss.handleUpgrade(request, socket, head, (ws) => {
            wss.emit('connection', ws, request, url);
        });
    }

    /** 解析 Upgrade 请求里的 Cookie（HTTP 接口用 cookie-parser，这里手工解析）。 */
    function parseCookieHeader(header) {
        const out = {};
        String(header || '').split(';').forEach((pair) => {
            const idx = pair.indexOf('=');
            if (idx <= 0) return;
            const key = pair.slice(0, idx).trim();
            if (!key) return;
            try {
                out[key] = decodeURIComponent(pair.slice(idx + 1).trim());
            } catch (_) {
                out[key] = pair.slice(idx + 1).trim();
            }
        });
        return out;
    }

    /** 读取某账号的剪贴板列表（与 GET /api/clipboards 共用同一实现）。 */
    function clipboardSnapshot(account, fromId, summary) {
        if (!readClipboardList) return [];
        try {
            return readClipboardList(account, fromId, summary) || [];
        } catch (error) {
            console.error(`[realtime] read clipboards failed for ${account}:`, error.message);
            return [];
        }
    }

    /** 新剪贴板落盘后调用：推给该账号所有已连接的剪贴板客户端。 */
    function pushClipboard(account, clipboard) {
        const sockets = clipboardConnections.get(account);
        if (!sockets || sockets.size === 0) return 0;
        let delivered = 0;
        for (const ws of sockets) {
            sendJson(ws, {
                t: 'clipboard_new',
                clipboard: ws.clipboardSummary ? clipboardSummary(clipboard) : clipboard,
            });
            delivered++;
        }
        if (delivered > 0) {
            console.log(`[realtime] clipboard push ${account} delivered=${delivered}`);
        }
        return delivered;
    }

    // 剪贴板通道：Cookie 鉴权（与 HTTP 接口同一信任级别），连接即回快照，之后只推增量。
    function handleClipboardConnection(ws, request, url) {
        const account = parseCookieHeader(request.headers.cookie).username || '';
        if (!ACCOUNT_PATTERN.test(account) || (accountStore && !accountStore.exists(account))) {
            console.warn(
                `[realtime] reject clipboard socket account="${account}" ip=${request.socket.remoteAddress}`,
            );
            ws.close(4001, 'unauthorized');
            return;
        }

        ws.isAlive = true;
        ws.connectedAt = Date.now();
        ws.account = account;
        ws.clipboard = true;
        ws.clipboardSummary = url.searchParams.get('summary') === '1';
        let sockets = clipboardConnections.get(account);
        if (!sockets) {
            sockets = new Set();
            clipboardConnections.set(account, sockets);
        }
        sockets.add(ws);
        console.log(
            `[realtime] clipboard online ${account} ip=${request.socket.remoteAddress} ` +
            `sockets=${sockets.size} total=${wss.clients.size}`,
        );

        sendJson(ws, { t: 'clipboard_list', clipboards: clipboardSnapshot(account, 0, ws.clipboardSummary) });

        ws.on('pong', () => {
            ws.isAlive = true;
        });

        ws.on('message', (raw) => {
            let frame;
            try {
                frame = JSON.parse(raw.toString());
            } catch (_) {
                sendJson(ws, { t: 'error', code: 400, msg: 'invalid json' });
                return;
            }
            if (!frame || typeof frame.t !== 'string') {
                sendJson(ws, { t: 'error', code: 400, msg: 'missing type' });
                return;
            }
            if (frame.t === 'ping') {
                sendJson(ws, { t: 'pong', ts: Date.now() });
                return;
            }
            if (frame.t === 'clipboard_watch') {
                const fromId = parseInt(frame.fromId, 10) || 0;
                sendJson(ws, { t: 'clipboard_list', clipboards: clipboardSnapshot(account, fromId, ws.clipboardSummary) });
                return;
            }
            sendJson(ws, { t: 'error', code: 400, msg: `unknown type: ${frame.t}` });
        });

        ws.on('close', () => {
            const set = clipboardConnections.get(account);
            if (set) {
                set.delete(ws);
                if (set.size === 0) clipboardConnections.delete(account);
            }
            const alive = ws.connectedAt ? Math.round((Date.now() - ws.connectedAt) / 1000) : 0;
            console.log(
                `[realtime] clipboard offline ${account} sockets=${set ? set.size : 0} ` +
                `total=${wss.clients.size} alive=${alive}s`,
            );
        });

        ws.on('error', (error) => {
            console.error(`[realtime] clipboard socket error ${account}:`, error.message);
        });
    }

    wss.on('connection', (ws, request, url) => {
        if (url.pathname === clipboardPath) {
            handleClipboardConnection(ws, request, url);
            return;
        }
        const account = (url.searchParams.get('account') || '').trim();
        const clientToken = url.searchParams.get('token') || '';
        const deviceId = (url.searchParams.get('deviceId') || '').trim().slice(0, 64);
        const role = url.searchParams.get('role') || 'tv';
        const name = (url.searchParams.get('name') || '').slice(0, 64);
        // 客户端标识（包名 / 版本 / 构建号）：用于区分不同控制端，
        // 回显到 ready、presence 与在线日志，realtime.html 据此展示。
        const app = (url.searchParams.get('app') || '').trim().slice(0, 64);
        const version = (url.searchParams.get('version') || '').trim().slice(0, 32);
        const build = (url.searchParams.get('build') || '').trim().slice(0, 32);
        // 面板类型（home/tv）：显式声明优先，旧客户端按包名兜底。
        const declaredKind = (url.searchParams.get('kind') || '').trim().slice(0, 16);
        const kind = KIND_PATTERN.test(declaredKind) ? declaredKind : kindOf(app);

        if (!ACCOUNT_PATTERN.test(account)) {
            console.warn(`[realtime] reject account "${account}" from ${request.socket.remoteAddress}`);
            sendJson(ws, { t: 'error', code: 400, msg: 'invalid account' });
            ws.close(4001, 'invalid account');
            return;
        }
        // 与 HTTP /api/login 同一校验：账号文件存在且 token（密码 MD5）一致。
        const verdict = accountStore ? accountStore.verify(account, clientToken) : { ok: false };
        if (!verdict.ok) {
            const msg = verdict.reason === 'not_exists' ? 'unknown account' : 'invalid token';
            console.warn(`[realtime] reject ${msg} for ${account} from ${request.socket.remoteAddress}`);
            sendJson(ws, { t: 'error', code: 401, msg });
            ws.close(4001, msg);
            return;
        }

        ws.isAlive = true;
        ws.connectedAt = Date.now();
        ws.account = account;
        ws.deviceId = deviceId;
        ws.role = role;
        ws.kind = kind;
        ws.name = name;
        ws.app = app;
        ws.version = version;
        ws.build = build;
        /** 该 socket 正在 watch 的设备账号集合 */
        ws.watches = new Set();
        /** 该 socket 订阅的合并会话线程：peer -> Set(additional accounts) */
        ws.threads = new Map();

        // ws 握手带 deviceId 时，把通信账号与客户端标识（app/version/build）
        // 一并回写到 admin 设备表（machines.json.commAccount/commApp/…）。
        if (deviceId && typeof options.setCommInfo === 'function') {
            try {
                options.setCommInfo(deviceId, { account, app, version, build });
            } catch (error) {
                console.warn('[realtime] 记录通信账号失败:', error.message);
            }
        }
        // 连接即视为在线：等价于原 HTTP 心跳的 lastSeen 刷新。
        if (deviceId) {
            try {
                touchDevice(deviceId);
            } catch (error) {
                console.warn('[realtime] 刷新设备在线状态失败:', error.message);
            }
        }

        let sockets = connections.get(account);
        const firstConnection = !sockets || sockets.size === 0;
        if (!sockets) {
            sockets = new Set();
            connections.set(account, sockets);
        }
        sockets.add(ws);
        console.log(
            `[realtime] online ${account} device=${deviceId || '-'} role=${role} kind=${kind || '-'} name=${name || '-'} ` +
            `app=${app || '-'} version=${version || '-'} build=${build || '-'} ` +
            `ip=${request.socket.remoteAddress} sockets=${sockets.size} total=${wss.clients.size}`,
        );

        sendJson(ws, {
            t: 'ready',
            account,
            deviceId,
            kind,
            app,
            version,
            build,
            online: onlineAccounts(),
            roster: onlineRoster(),
            serverTime: Date.now(),
        });
        flushOffline(account);
        if (firstConnection) {
            broadcast({ t: 'presence', account, deviceId, kind, app, version, build, online: true }, ws);
        }

        ws.on('pong', () => {
            ws.isAlive = true;
        });

        ws.on('message', (raw) => {
            let frame;
            try {
                frame = JSON.parse(raw.toString());
            } catch (_) {
                console.warn(`[realtime] bad frame from ${account}: invalid json len=${raw.length}`);
                sendJson(ws, { t: 'error', code: 400, msg: 'invalid json' });
                return;
            }
            if (!frame || typeof frame.t !== 'string') {
                console.warn(`[realtime] bad frame from ${account}: missing type`);
                sendJson(ws, { t: 'error', code: 400, msg: 'missing type' });
                return;
            }
            log(`recv ${account} t=${frame.t}`);

            switch (frame.t) {
                case 'ping':
                    // 客户端 25s 一次 ping：顺带保活设备表，替代 HTTP 心跳。
                    if (ws.deviceId) touchDevice(ws.deviceId);
                    sendJson(ws, { t: 'pong', ts: Date.now() });
                    break;

                case 'report': {
                    // 设备状态上报（已知家庭 / 当前家庭 / HA 连接）：替代 HTTP 心跳的上行字段。
                    // 回包里附带最新生效配置，客户端重连后据此自愈。
                    const id = typeof frame.id === 'string' ? frame.id : '';
                    const machine = ws.deviceId ? updateDeviceReport(ws.deviceId, frame) : null;
                    const snapshot = ws.deviceId ? configForDevice(ws.deviceId) : null;
                    sendJson(ws, {
                        t: 'result',
                        id,
                        ok: !!machine,
                        ...(snapshot ? { config: snapshot.config } : {}),
                    });
                    break;
                }

                case 'msg': {
                    const to = typeof frame.to === 'string' ? frame.to.trim() : '';
                    const body = typeof frame.body === 'string' ? frame.body : '';
                    const clientId = typeof frame.id === 'string' ? frame.id : '';
                    if (!ACCOUNT_PATTERN.test(to) || body.length === 0) {
                        console.warn(`[realtime] bad msg from ${account}: invalid target or empty body`);
                        sendJson(ws, { t: 'error', code: 400, msg: 'invalid message' });
                        return;
                    }
                    if (body.length > MAX_BODY_LENGTH) {
                        console.warn(`[realtime] bad msg from ${account}: too large len=${body.length}`);
                        sendJson(ws, { t: 'error', code: 413, msg: 'message too large' });
                        return;
                    }
                    const message = {
                        id: clientId || `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`,
                        from: account,
                        to,
                        body,
                        ts: Date.now(),
                    };
                    persistMessage(message);

                    let delivered = false;
                    const targets = connections.get(to);
                    if (targets) {
                        for (const target of targets) {
                            sendJson(target, {
                                t: 'msg',
                                id: message.id,
                                from: message.from,
                                to: message.to,
                                body: message.body,
                                ts: message.ts,
                            });
                            delivered = true;
                        }
                    }
                    console.log(
                        `[realtime] msg ${account}->${to} id=${message.id} bytes=${body.length} delivered=${delivered}`,
                    );
                    if (!delivered) {
                        enqueueOffline(to, message);
                        console.log(`[realtime] offline-queued ${to} id=${message.id} from=${account}`);
                    }

                    // 会话线程订阅者（如非管理员中控端）也要看到这条往来；
                    // 已直投的 socket 跳过，客户端按 id 去重。
                    forwardThread(
                        {
                            t: 'msg',
                            id: message.id,
                            from: message.from,
                            to: message.to,
                            body: message.body,
                            ts: message.ts,
                        },
                        new Set([ws, ...(targets ? Array.from(targets) : [])]),
                    );

                    sendJson(ws, {
                        t: 'result',
                        id: clientId,
                        messageId: message.id,
                        ok: true,
                        delivered,
                        ts: message.ts,
                    });
                    break;
                }

                case 'event': {
                    const eventName = typeof frame.event === 'string' ? frame.event.trim() : '';
                    const clientId = typeof frame.id === 'string' ? frame.id : '';
                    const to = typeof frame.to === 'string' ? frame.to.trim() : '';
                    const reject = (reason) => {
                        console.warn(`[realtime] bad event from ${account}: ${reason}`);
                        sendJson(ws, {
                            t: 'result',
                            id: clientId,
                            ok: false,
                            error: reason,
                            ts: Date.now(),
                        });
                    };
                    if (!EVENT_NAME_PATTERN.test(eventName)) {
                        reject(`invalid name "${eventName}"`);
                        return;
                    }
                    if (to && !ACCOUNT_PATTERN.test(to)) {
                        reject(`invalid target "${to}"`);
                        return;
                    }
                    if (frame.data !== undefined && (frame.data === null || typeof frame.data !== 'object' || Array.isArray(frame.data))) {
                        reject('data must be an object');
                        return;
                    }
                    const data = frame.data || {};
                    let dataText;
                    try {
                        dataText = JSON.stringify(data);
                    } catch (_) {
                        reject('data is not serializable');
                        return;
                    }
                    if (dataText.length > MAX_EVENT_DATA_LENGTH) {
                        reject(`data too large len=${dataText.length}`);
                        return;
                    }

                    const record = {
                        id: clientId || `${Date.now()}-${Math.random().toString(36).slice(2, 10)}`,
                        from: account,
                        to,
                        event: eventName,
                        data,
                        ts: Date.now(),
                    };
                    persistEvent(record);

                    let delivered = false;
                    if (to) {
                        const targets = connections.get(to);
                        if (targets) {
                            for (const target of targets) {
                                sendJson(target, { t: 'event', ...record });
                                delivered = true;
                            }
                        }
                    }
                    console.log(
                        `[realtime] event ${account} event=${eventName} to=${to || '-'} id=${record.id} ` +
                        `bytes=${dataText.length} delivered=${delivered}`,
                    );

                    // 同 msg：把管理员与设备之间的事件同步给线程订阅者。
                    const eventTargets = to && connections.get(to);
                    forwardThread(
                        { t: 'event', ...record },
                        new Set([ws, ...(eventTargets ? Array.from(eventTargets) : [])]),
                    );

                    sendJson(ws, {
                        t: 'result',
                        id: clientId,
                        eventId: record.id,
                        ok: true,
                        delivered,
                        ts: record.ts,
                    });
                    break;
                }

                case 'events': {
                    const items = eventsFor(account, frame);
                    sendJson(ws, {
                        t: 'events',
                        id: frame.id,
                        items,
                    });
                    log(`events ${account} count=${items.length}`);
                    break;
                }

                case 'history': {
                    const peer = typeof frame.peer === 'string' ? frame.peer.trim() : '';
                    const limit = Math.min(Math.max(parseInt(frame.limit, 10) || 50, 1), 200);
                    if (!ACCOUNT_PATTERN.test(peer)) {
                        console.warn(`[realtime] bad history from ${account}: invalid peer "${peer}"`);
                        sendJson(ws, { t: 'error', code: 400, msg: 'invalid peer' });
                        return;
                    }
                    const messages = historyFor(account, peer, limit);
                    sendJson(ws, {
                        t: 'history',
                        id: frame.id,
                        peer,
                        messages,
                    });
                    log(`history ${account}<->${peer} limit=${limit} count=${messages.length}`);
                    break;
                }

                case 'conversations': {
                    const items = conversationsFor(account);
                    sendJson(ws, {
                        t: 'conversations',
                        id: frame.id,
                        items,
                    });
                    log(`conversations ${account} count=${items.length}`);
                    break;
                }

                case 'read': {
                    const peer = typeof frame.peer === 'string' ? frame.peer.trim() : '';
                    if (!ACCOUNT_PATTERN.test(peer)) {
                        console.warn(`[realtime] bad read from ${account}: invalid peer "${peer}"`);
                        return;
                    }
                    const file = path.join(readsDir, `${account}.json`);
                    const reads = readsFor(account);
                    reads[peer] = Date.now();
                    writeJson(file, reads);
                    sendJson(ws, { t: 'read_ok', peer });
                    log(`read ${account} peer=${peer}`);
                    break;
                }

                case 'watch': {
                    const to = typeof frame.to === 'string' ? frame.to.trim() : '';
                    if (!ACCOUNT_PATTERN.test(to)) {
                        sendJson(ws, { t: 'error', code: 400, msg: 'invalid watch target' });
                        return;
                    }
                    addWatcher(to, ws);
                    // 立即回推缓存状态：控制端进入面板即拿到场景，无需向设备反查。
                    sendStateTo(ws, to, states.get(to));
                    log(`watch ${account}->${to}`);
                    break;
                }

                case 'unwatch': {
                    const to = typeof frame.to === 'string' ? frame.to.trim() : '';
                    if (!ACCOUNT_PATTERN.test(to)) return;
                    removeWatcher(to, ws);
                    log(`unwatch ${account}->${to}`);
                    break;
                }

                case 'thread_watch': {
                    // 进入设备会话：返回合并快照，并订阅之后的新帧。
                    const peer = typeof frame.peer === 'string' ? frame.peer.trim() : '';
                    const clientId = typeof frame.id === 'string' ? frame.id : '';
                    if (!ACCOUNT_PATTERN.test(peer)) {
                        sendJson(ws, { t: 'error', id: clientId, code: 400, msg: 'invalid peer' });
                        return;
                    }
                    const rawAlso = Array.isArray(frame.also) ? frame.also : [];
                    const also = Array.from(
                        new Set(
                            rawAlso
                                .filter((item) => typeof item === 'string')
                                .map((item) => item.trim())
                                .filter((item) => ACCOUNT_PATTERN.test(item) && item !== account),
                        ),
                    ).slice(0, 5);
                    if (!ws.threads) ws.threads = new Map();
                    ws.threads.set(peer, new Set(also));
                    const limit = Math.min(
                        Math.max(parseInt(frame.limit, 10) || 100, 1),
                        MAX_THREAD_LIMIT,
                    );
                    const items = threadItemsFor(account, peer, also, limit);
                    sendJson(ws, { t: 'thread', id: clientId, peer, items });
                    log(`thread_watch ${account}->${peer} also=[${also.join(',')}] count=${items.length}`);
                    break;
                }

                case 'thread_unwatch': {
                    const peer = typeof frame.peer === 'string' ? frame.peer.trim() : '';
                    if (!ACCOUNT_PATTERN.test(peer)) return;
                    if (ws.threads) ws.threads.delete(peer);
                    log(`thread_unwatch ${account}->${peer}`);
                    break;
                }

                case 'state': {
                    // 设备自身上报：scene 覆盖、channels 仅在变化时携带（服务端合并）。
                    const rawScene = frame.scene;
                    if (
                        rawScene !== undefined &&
                        (rawScene === null || typeof rawScene !== 'object' || Array.isArray(rawScene))
                    ) {
                        sendJson(ws, { t: 'error', code: 400, msg: 'invalid state scene' });
                        return;
                    }
                    let channels = null;
                    let listVersion = '';
                    if (frame.channels !== undefined) {
                        const rawChannels = frame.channels;
                        if (!rawChannels || typeof rawChannels !== 'object' || !Array.isArray(rawChannels.names)) {
                            sendJson(ws, { t: 'error', code: 400, msg: 'invalid state channels' });
                            return;
                        }
                        channels = rawChannels.names
                            .filter((name) => typeof name === 'string' && name.length > 0)
                            .map((name) => name.slice(0, 128));
                        listVersion = typeof rawChannels.version === 'string' ? rawChannels.version.slice(0, 32) : '';
                    }
                    const prev = states.get(account) || {
                        scene: {},
                        channels: null,
                        listVersion: '',
                        playback: null,
                        ts: 0,
                    };
                    // playback：字段缺失 = 沿用缓存；显式 null = 已离开直播/无播放。
                    let playback;
                    if ('playback' in frame) {
                        const rawPlayback = frame.playback;
                        if (
                            rawPlayback !== null &&
                            (typeof rawPlayback !== 'object' || Array.isArray(rawPlayback))
                        ) {
                            sendJson(ws, { t: 'error', code: 400, msg: 'invalid state playback' });
                            return;
                        }
                        playback =
                            rawPlayback === null
                                ? null
                                : {
                                      channel:
                                          typeof rawPlayback.channel === 'string'
                                              ? rawPlayback.channel.slice(0, 128)
                                              : '',
                                      state:
                                          typeof rawPlayback.state === 'string'
                                              ? rawPlayback.state.slice(0, 32)
                                              : '',
                                      label:
                                          typeof rawPlayback.label === 'string'
                                              ? rawPlayback.label.slice(0, 32)
                                              : '',
                                      ts: Number(rawPlayback.ts) || Date.now(),
                                  };
                    }
                    const next = {
                        scene: rawScene ? rawScene : prev.scene,
                        channels: channels || prev.channels,
                        listVersion: channels ? listVersion : prev.listVersion,
                        playback: playback !== undefined ? playback : prev.playback || null,
                        ts: Date.now(),
                    };
                    let size = 0;
                    try {
                        size = Buffer.byteLength(JSON.stringify(next));
                    } catch (_) {
                        sendJson(ws, { t: 'error', code: 400, msg: 'state not serializable' });
                        return;
                    }
                    if (size > MAX_STATE_LENGTH) {
                        console.warn(`[realtime] state too large ${account} len=${size}`);
                        sendJson(ws, { t: 'error', code: 413, msg: 'state too large' });
                        return;
                    }
                    states.set(account, next);
                    const watchers = watchersByAccount.get(account);
                    let forwarded = 0;
                    if (watchers) {
                        for (const watcher of watchers) {
                            sendStateTo(watcher, account, next);
                            forwarded++;
                        }
                    }
                    log(`state ${account} kind=${next.scene && next.scene.kind} bytes=${size} watchers=${forwarded}`);
                    break;
                }

                default:
                    console.warn(`[realtime] bad frame from ${account}: unknown type "${frame.t}"`);
                    sendJson(ws, { t: 'error', code: 400, msg: `unknown type: ${frame.t}` });
            }
        });

        ws.on('close', (code, reason) => {
            clearWatchers(ws);
            ws.threads = null;
            const set = connections.get(account);
            if (set) {
                set.delete(ws);
                if (set.size === 0) {
                    connections.delete(account);
                    broadcast({
                        t: 'presence',
                        account,
                        deviceId: ws.deviceId || '',
                        kind: ws.kind || '',
                        app: ws.app || '',
                        version: ws.version || '',
                        build: ws.build || '',
                        online: false,
                    });
                }
            }
            const alive = ws.connectedAt ? Math.round((Date.now() - ws.connectedAt) / 1000) : 0;
            console.log(
                `[realtime] offline ${account} code=${code} reason=${reason ? reason.toString() : '-'} ` +
                `sockets=${set ? set.size : 0} total=${wss.clients.size} alive=${alive}s`,
            );
        });

        ws.on('error', (error) => {
            console.error(`[realtime] socket error ${account}:`, error.message);
        });
    });

    const heartbeat = setInterval(() => {
        for (const ws of wss.clients) {
            if (ws.isAlive === false) {
                console.warn(`[realtime] heartbeat timeout, terminate ${ws.account || 'unknown'}`);
                ws.terminate();
                continue;
            }
            ws.isAlive = false;
            try {
                ws.ping();
            } catch (_) {
                // 忽略：下一轮会 terminate
            }
        }
    }, HEARTBEAT_MS);
    heartbeat.unref();

    const stats = setInterval(() => {
        console.log(
            `[realtime] stats clients=${wss.clients.size} accounts=${connections.size} ` +
            `history=${history.length} events=${events.length} online=[${onlineAccounts().join(',')}]`,
        );
    }, 60000);
    stats.unref();

    httpServer.on('upgrade', handleUpgrade);
    httpServer.on('close', () => {
        clearInterval(heartbeat);
        clearInterval(stats);
        wss.close();
    });

    console.log(`[realtime] WebSocket 网关已挂载: ${wsPath} (剪贴板推送: ${clipboardPath})`);
    return { wss, onlineAccounts, pushClipboard, pushToDevice };
}

module.exports = { attachRealtime };
