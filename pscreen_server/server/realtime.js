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
const MAX_OUTBOX = 200;
const HEARTBEAT_MS = 30000;
const ACCOUNT_PATTERN = /^[A-Za-z0-9_.:-]{1,64}$/;
const EVENT_NAME_PATTERN = /^[A-Za-z0-9_.:-]{1,64}$/;

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
    // 账号存储（datas/register/users）：与 HTTP 登录同一校验；未传时拒绝所有连接。
    const accountStore = options.accountStore || null;
    const dataDir = path.resolve(options.dataDir || path.join(__dirname, '../datas/realtime'));
    const historyFile = path.join(dataDir, 'history.jsonl');
    const eventsFile = path.join(dataDir, 'events.jsonl');
    const outboxDir = path.join(dataDir, 'outbox');
    const readsDir = path.join(dataDir, 'reads');

    fs.mkdirSync(outboxDir, { recursive: true });
    fs.mkdirSync(readsDir, { recursive: true });

    /** account -> Set<WebSocket> */
    const connections = new Map();
    const history = loadHistory(historyFile);
    const events = loadEvents(eventsFile);

    const wss = new WebSocketServer({ noServer: true, maxPayload: 128 * 1024 });

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
                app: sock.app || '',
                version: sock.version || '',
                build: sock.build || '',
            });
        }
        return roster;
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

    function handleUpgrade(request, socket, head) {
        let url;
        try {
            url = new URL(request.url, 'http://localhost');
        } catch (_) {
            log(`upgrade ignored malformed url=${request.url} ip=${request.socket.remoteAddress}`);
            socket.destroy();
            return;
        }
        if (url.pathname !== wsPath) {
            log(`upgrade ignored path=${url.pathname} ip=${request.socket.remoteAddress}`);
            socket.destroy();
            return;
        }
        wss.handleUpgrade(request, socket, head, (ws) => {
            wss.emit('connection', ws, request, url);
        });
    }

    wss.on('connection', (ws, request, url) => {
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
        ws.name = name;
        ws.app = app;
        ws.version = version;
        ws.build = build;

        // ws 握手带 deviceId 时，把通信账号与客户端标识（app/version/build）
        // 一并回写到 admin 设备表（machines.json.commAccount/commApp/…）。
        if (deviceId && typeof options.setCommInfo === 'function') {
            try {
                options.setCommInfo(deviceId, { account, app, version, build });
            } catch (error) {
                console.warn('[realtime] 记录通信账号失败:', error.message);
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
            `[realtime] online ${account} device=${deviceId || '-'} role=${role} name=${name || '-'} ` +
            `app=${app || '-'} version=${version || '-'} build=${build || '-'} ` +
            `ip=${request.socket.remoteAddress} sockets=${sockets.size} total=${wss.clients.size}`,
        );

        sendJson(ws, {
            t: 'ready',
            account,
            deviceId,
            app,
            version,
            build,
            online: onlineAccounts(),
            roster: onlineRoster(),
            serverTime: Date.now(),
        });
        flushOffline(account);
        if (firstConnection) {
            broadcast({ t: 'presence', account, deviceId, app, version, build, online: true }, ws);
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
                    sendJson(ws, { t: 'pong', ts: Date.now() });
                    break;

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

                default:
                    console.warn(`[realtime] bad frame from ${account}: unknown type "${frame.t}"`);
                    sendJson(ws, { t: 'error', code: 400, msg: `unknown type: ${frame.t}` });
            }
        });

        ws.on('close', (code, reason) => {
            const set = connections.get(account);
            if (set) {
                set.delete(ws);
                if (set.size === 0) {
                    connections.delete(account);
                    broadcast({
                        t: 'presence',
                        account,
                        deviceId: ws.deviceId || '',
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

    console.log(`[realtime] WebSocket 网关已挂载: ${wsPath}`);
    return { wss, onlineAccounts };
}

module.exports = { attachRealtime };
