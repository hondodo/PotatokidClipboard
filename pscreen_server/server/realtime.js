// 实时消息网关（WebSocket）。
//
// 与 server.js 共用同一个 HTTP 服务：客户端连接 `/ws?account=..&token=..&role=..&name=..`，
// 鉴权通过后按账号路由消息、广播在线状态，并把离线消息与历史落到 datas/realtime。
const fs = require('fs');
const path = require('path');
const { WebSocketServer } = require('ws');

const MAX_HISTORY = 20000;
const MAX_BODY_LENGTH = 16 * 1024;
const MAX_OUTBOX = 200;
const HEARTBEAT_MS = 30000;
const ACCOUNT_PATTERN = /^[A-Za-z0-9_.:-]{1,64}$/;

/** 读取 JSONL 历史（启动时一次性载入内存，写入时追加）。 */
function loadHistory(file) {
    const records = [];
    if (!fs.existsSync(file)) return records;
    const lines = fs.readFileSync(file, 'utf8').split('\n');
    for (const line of lines) {
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
    const token = options.token || '12345678';
    const dataDir = path.resolve(options.dataDir || path.join(__dirname, '../datas/realtime'));
    const historyFile = path.join(dataDir, 'history.jsonl');
    const outboxDir = path.join(dataDir, 'outbox');
    const readsDir = path.join(dataDir, 'reads');

    fs.mkdirSync(outboxDir, { recursive: true });
    fs.mkdirSync(readsDir, { recursive: true });

    /** account -> Set<WebSocket> */
    const connections = new Map();
    const history = loadHistory(historyFile);

    const wss = new WebSocketServer({ noServer: true, maxPayload: 128 * 1024 });

    function sendJson(ws, payload) {
        if (ws.readyState !== ws.OPEN) return;
        try {
            ws.send(JSON.stringify(payload));
        } catch (error) {
            console.error('[realtime] send failed:', error.message);
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

    function unreadCount(account, peer) {
        const reads = readJson(path.join(readsDir, `${account}.json`), {});
        const since = reads[peer] || 0;
        return history.filter((m) => m.to === account && m.from === peer && m.ts > since).length;
    }

    function conversationsFor(account) {
        const byPeer = new Map();
        for (const message of history) {
            if (message.from !== account && message.to !== account) continue;
            const peer = message.from === account ? message.to : message.from;
            const current = byPeer.get(peer);
            if (!current || message.ts >= current.ts) byPeer.set(peer, message);
        }
        return Array.from(byPeer.entries())
            .map(([peer, last]) => ({
                account: peer,
                lastMessage: last.body,
                ts: last.ts,
                unread: unreadCount(account, peer),
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
            socket.destroy();
            return;
        }
        if (url.pathname !== wsPath) {
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
        const role = url.searchParams.get('role') || 'tv';
        const name = (url.searchParams.get('name') || '').slice(0, 64);

        if (!ACCOUNT_PATTERN.test(account)) {
            sendJson(ws, { t: 'error', code: 400, msg: 'invalid account' });
            ws.close(4001, 'invalid account');
            return;
        }
        if (clientToken !== token) {
            sendJson(ws, { t: 'error', code: 401, msg: 'invalid token' });
            ws.close(4001, 'invalid token');
            return;
        }

        ws.isAlive = true;
        ws.account = account;
        ws.role = role;
        ws.name = name;

        let sockets = connections.get(account);
        const firstConnection = !sockets || sockets.size === 0;
        if (!sockets) {
            sockets = new Set();
            connections.set(account, sockets);
        }
        sockets.add(ws);
        console.log(`[realtime] online ${account} (${role}), sockets=${sockets.size}`);

        sendJson(ws, {
            t: 'ready',
            account,
            online: onlineAccounts(),
            serverTime: Date.now(),
        });
        flushOffline(account);
        if (firstConnection) {
            broadcast({ t: 'presence', account, online: true }, ws);
        }

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

            switch (frame.t) {
                case 'ping':
                    sendJson(ws, { t: 'pong', ts: Date.now() });
                    break;

                case 'msg': {
                    const to = typeof frame.to === 'string' ? frame.to.trim() : '';
                    const body = typeof frame.body === 'string' ? frame.body : '';
                    const clientId = typeof frame.id === 'string' ? frame.id : '';
                    if (!ACCOUNT_PATTERN.test(to) || body.length === 0) {
                        sendJson(ws, { t: 'error', code: 400, msg: 'invalid message' });
                        return;
                    }
                    if (body.length > MAX_BODY_LENGTH) {
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
                    if (!delivered) enqueueOffline(to, message);

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

                case 'history': {
                    const peer = typeof frame.peer === 'string' ? frame.peer.trim() : '';
                    const limit = Math.min(Math.max(parseInt(frame.limit, 10) || 50, 1), 200);
                    if (!ACCOUNT_PATTERN.test(peer)) {
                        sendJson(ws, { t: 'error', code: 400, msg: 'invalid peer' });
                        return;
                    }
                    sendJson(ws, {
                        t: 'history',
                        id: frame.id,
                        peer,
                        messages: historyFor(account, peer, limit),
                    });
                    break;
                }

                case 'conversations':
                    sendJson(ws, {
                        t: 'conversations',
                        id: frame.id,
                        items: conversationsFor(account),
                    });
                    break;

                case 'read': {
                    const peer = typeof frame.peer === 'string' ? frame.peer.trim() : '';
                    if (!ACCOUNT_PATTERN.test(peer)) return;
                    const file = path.join(readsDir, `${account}.json`);
                    const reads = readJson(file, {});
                    reads[peer] = Date.now();
                    writeJson(file, reads);
                    sendJson(ws, { t: 'read_ok', peer });
                    break;
                }

                default:
                    sendJson(ws, { t: 'error', code: 400, msg: `unknown type: ${frame.t}` });
            }
        });

        ws.on('close', () => {
            const set = connections.get(account);
            if (set) {
                set.delete(ws);
                if (set.size === 0) {
                    connections.delete(account);
                    broadcast({ t: 'presence', account, online: false });
                }
            }
            console.log(`[realtime] offline ${account}`);
        });

        ws.on('error', (error) => {
            console.error(`[realtime] socket error ${account}:`, error.message);
        });
    });

    const heartbeat = setInterval(() => {
        for (const ws of wss.clients) {
            if (ws.isAlive === false) {
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

    httpServer.on('upgrade', handleUpgrade);
    httpServer.on('close', () => {
        clearInterval(heartbeat);
        wss.close();
    });

    console.log(`[realtime] WebSocket 网关已挂载: ${wsPath}`);
    return { wss, onlineAccounts };
}

module.exports = { attachRealtime };
