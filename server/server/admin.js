// Admin 管理接口 + 设备配置/布局同步接口。
//
// 数据全部落在 ../datas/admin 下（与现有 register/users 同级）：
// - users 仍复用 ../datas/register/users/<name> 与 <name>_info.txt，
//   这里只在 info JSON 上扩展 role / homes / displayName / enabled；
// - machines.json：每台中控屏的注册信息、所属用户、家庭覆盖与最近心跳；
// - layouts.json：按用户（未绑定用户时按设备）保存的首页卡片顺序；
// - secret.key：Admin 会话签名密钥（首次启动自动生成）。
//
// 家庭字段约定（users.homes / machines.homes）：
// - null / 缺失：未配置，回落到下一层（机器 → 用户 → .env）；
// - []：不限制（全部家庭）；
// - ["棠德304"]：只显示这些家庭。

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const definds = require('./definds');

const ADMIN_USERNAME = (process.env.ADMIN_USERNAME || 'honghao').trim();
const SESSION_COOKIE = 'pk_admin';
const SESSION_TTL_MS = 7 * 24 * 60 * 60 * 1000;
const MACHINE_ONLINE_MS = 90 * 1000;
const MAX_HOMES = 50;
const MAX_HOME_NAME = 64;
const MAX_LAYOUT_ITEMS = 1000;
const MAX_LAYOUT_HOMES = 100;

function nowMs() {
    return Date.now();
}

function jsonOk(res, data, msg = '成功') {
    return res.json({
        [definds.txt.CODE]: definds.code.SUCCESS,
        [definds.txt.MSG]: msg,
        [definds.txt.DATA]: data,
    });
}

function jsonFail(res, msg, code = definds.code.FAILED, status = 200) {
    return res.status(status).json({
        [definds.txt.CODE]: code,
        [definds.txt.MSG]: msg,
    });
}

function readJson(file, fallback) {
    try {
        if (!fs.existsSync(file)) return fallback;
        return JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch (error) {
        console.error(`[admin] 读取 ${file} 失败:`, error.message);
        return fallback;
    }
}

/** 原子写：先写临时文件再 rename，避免进程中断留下半个 JSON。 */
function writeJson(file, value) {
    try {
        fs.mkdirSync(path.dirname(file), { recursive: true });
        const tmp = `${file}.tmp`;
        fs.writeFileSync(tmp, JSON.stringify(value, null, 2), 'utf8');
        fs.renameSync(tmp, file);
    } catch (error) {
        console.error(`[admin] 写入 ${file} 失败:`, error.message);
    }
}

function normalizeIp(ip) {
    const value = String(ip || '').trim();
    if (value.startsWith('::ffff:')) return value.slice(7);
    if (value === '::1') return '127.0.0.1';
    return value;
}

/**
 * 密码归一化：现有客户端提交的是 32 位 MD5，Admin 页提交明文。
 * 两种都接受，统一存成 MD5，保证与 /api/login 的旧数据兼容。
 */
function hashPassword(input) {
    const value = String(input || '');
    if (/^[a-f0-9]{32}$/i.test(value)) return value.toLowerCase();
    return crypto.createHash('md5').update(value).digest('hex');
}

function safeUsername(value) {
    const name = typeof value === 'string' ? value.trim() : '';
    if (!name || name.length < 2 || name.length > 20) return '';
    if (!/^[A-Za-z0-9_\u4e00-\u9fa5.-]+$/.test(name)) return '';
    if (name === '.' || name === '..') return '';
    return name;
}

function safeDeviceId(value) {
    const id = typeof value === 'string' ? value.trim() : '';
    if (!id || id.length > 128) return '';
    return /^[A-Za-z0-9_.:-]+$/.test(id) ? id : '';
}

/** 家庭数组：null = 未配置；[] = 全部；否则去重后的白名单。 */
function normalizeHomes(value) {
    if (value === null || value === undefined) return null;
    if (!Array.isArray(value)) throw new Error('homes 必须是数组或 null');
    const homes = [];
    for (const item of value) {
        if (typeof item !== 'string') continue;
        const name = item.trim();
        if (!name || name.length > MAX_HOME_NAME) continue;
        if (!homes.includes(name)) homes.push(name);
        if (homes.length >= MAX_HOMES) break;
    }
    return homes;
}

function normalizeStringList(value, max = MAX_LAYOUT_ITEMS) {
    if (!Array.isArray(value)) return [];
    const list = [];
    for (const item of value) {
        if (typeof item !== 'string') continue;
        const key = item.trim();
        if (!key || key.length > 200) continue;
        if (!list.includes(key)) list.push(key);
        if (list.length >= max) break;
    }
    return list;
}

function normalizeByHome(value) {
    const result = {};
    if (!value || typeof value !== 'object' || Array.isArray(value)) return result;
    let count = 0;
    for (const [rawHome, rawList] of Object.entries(value)) {
        if (count >= MAX_LAYOUT_HOMES) break;
        const home = String(rawHome || '').trim();
        if (!home || home.length > MAX_HOME_NAME) continue;
        result[home] = normalizeStringList(rawList);
        count++;
    }
    return result;
}

function normalizeLayout(value) {
    const raw = value && typeof value === 'object' ? value : {};
    const updatedAt = Number.isFinite(Number(raw.updatedAt))
        ? Math.max(0, Math.trunc(Number(raw.updatedAt)))
        : 0;
    return {
        all: normalizeStringList(raw.all),
        byHome: normalizeByHome(raw.byHome),
        updatedAt,
        savedAt: Number.isFinite(Number(raw.savedAt))
            ? Math.max(0, Math.trunc(Number(raw.savedAt)))
            : 0,
    };
}

function attachAdmin(app, options = {}) {
    const datasDir = path.resolve(options.datasDir);
    const registerUsersDir = path.resolve(options.registerUsersDir);
    const webAppPath = path.resolve(options.webAppPath || path.join(datasDir, '../build/web'));
    const onlineAccounts = typeof options.onlineAccounts === 'function'
        ? options.onlineAccounts
        : () => [];
    // 由 server.js 注入：把配置变更推给在线设备（realtime 在 admin 之后挂载）。
    const pushDeviceConfig = typeof options.pushDeviceConfig === 'function'
        ? options.pushDeviceConfig
        : () => {};

    const adminDir = path.join(datasDir, 'admin');
    fs.mkdirSync(adminDir, { recursive: true });

    const machinesFile = path.join(adminDir, 'machines.json');
    const layoutsFile = path.join(adminDir, 'layouts.json');
    const secretFile = path.join(adminDir, 'secret.key');

    // 会话签名密钥：首次启动生成，之后保持不变（重启不会踢掉已登录会话）。
    let secret;
    try {
        if (fs.existsSync(secretFile)) {
            secret = fs.readFileSync(secretFile, 'utf8').trim();
        }
        if (!secret) {
            secret = crypto.randomBytes(32).toString('hex');
            fs.writeFileSync(secretFile, secret, { encoding: 'utf8', mode: 0o600 });
        }
    } catch (error) {
        console.error('[admin] 初始化会话密钥失败，使用临时密钥:', error.message);
        secret = crypto.randomBytes(32).toString('hex');
    }

    // ------------------------------------------------------------ 用户存储

    function userInfoPath(name) {
        return path.join(registerUsersDir, `${name}_info.txt`);
    }

    function passwordPath(name) {
        return path.join(registerUsersDir, name);
    }

    function readUserInfo(name) {
        const raw = readJson(userInfoPath(name), null);
        if (raw && typeof raw === 'object') return raw;
        return { id: 0, name, createdAt: new Date().toISOString() };
    }

    function writeUserInfo(name, info) {
        writeJson(userInfoPath(name), info);
    }

    function normalizeUser(info) {
        const name = String(info.name || '').trim();
        const isAdmin = info.role === 'admin' || name === ADMIN_USERNAME;
        let homes = null;
        try {
            homes = normalizeHomes(info.homes);
        } catch (_) {
            homes = null;
        }
        return {
            id: Number(info.id) || 0,
            name,
            displayName: typeof info.displayName === 'string' && info.displayName.trim()
                ? info.displayName.trim().slice(0, 40)
                : name,
            role: isAdmin ? 'admin' : 'user',
            homes,
            enabled: info.enabled !== false,
            createdAt: info.createdAt || '',
            loginTime: info.loginTime || '',
        };
    }

    function listUsers() {
        let files = [];
        try {
            files = fs.readdirSync(registerUsersDir)
                .filter((file) => file.endsWith('_info.txt'));
        } catch (error) {
            console.error('[admin] 读取用户目录失败:', error.message);
            return [];
        }
        const users = [];
        for (const file of files) {
            const name = file.slice(0, -'_info.txt'.length);
            if (!safeUsername(name)) continue;
            users.push(normalizeUser(readUserInfo(name)));
        }
        users.sort((a, b) => {
            if (a.role !== b.role) return a.role === 'admin' ? -1 : 1;
            return a.name.localeCompare(b.name, 'zh-CN');
        });
        return users;
    }

    // 启动时做一次轻量迁移：补齐 role，确保 honghao 是管理员。
    (function migrateUsers() {
        for (const user of listUsers()) {
            const info = readUserInfo(user.name);
            const nextRole = user.name === ADMIN_USERNAME ? 'admin' : (info.role || 'user');
            const needsWrite = info.role !== nextRole;
            if (needsWrite) {
                info.role = nextRole;
                writeUserInfo(user.name, info);
            }
        }
    })();

    // ------------------------------------------------------------ 机器存储

    function readMachines() {
        const raw = readJson(machinesFile, {});
        if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return {};
        const result = {};
        for (const [id, machine] of Object.entries(raw)) {
            if (!safeDeviceId(id) || !machine || typeof machine !== 'object') continue;
            result[id] = normalizeMachine(id, machine);
        }
        return result;
    }

    function normalizeMachine(id, machine) {
        let homes = null;
        try {
            homes = normalizeHomes(machine.homes);
        } catch (_) {
            homes = null;
        }
        return {
            id,
            name: typeof machine.name === 'string' && machine.name.trim()
                ? machine.name.trim().slice(0, 40)
                : '未命名设备',
            owner: typeof machine.owner === 'string' ? machine.owner.trim() : '',
            homes,
            platform: typeof machine.platform === 'string' ? machine.platform.slice(0, 32) : '',
            model: typeof machine.model === 'string' ? machine.model.slice(0, 64) : '',
            appVersion: typeof machine.appVersion === 'string' ? machine.appVersion.slice(0, 32) : '',
            ip: typeof machine.ip === 'string' ? machine.ip.slice(0, 64) : '',
            currentHome: typeof machine.currentHome === 'string' ? machine.currentHome.slice(0, MAX_HOME_NAME) : '',
            knownHomes: Array.isArray(machine.knownHomes)
                ? machine.knownHomes.filter((home) => typeof home === 'string' && home.trim())
                    .map((home) => home.trim().slice(0, MAX_HOME_NAME)).slice(0, MAX_HOMES)
                : [],
            haConnected: machine.haConnected === true,
            commAccount: typeof machine.commAccount === 'string' ? machine.commAccount.slice(0, 64) : '',
            // ws 握手回写的客户端标识（包名 / 版本 / 构建号），区分控制端形态。
            commApp: typeof machine.commApp === 'string' ? machine.commApp.slice(0, 64) : '',
            commVersion: typeof machine.commVersion === 'string' ? machine.commVersion.slice(0, 32) : '',
            commBuild: typeof machine.commBuild === 'string' ? machine.commBuild.slice(0, 32) : '',
            firstSeen: Number(machine.firstSeen) || 0,
            lastSeen: Number(machine.lastSeen) || 0,
        };
    }

    function saveMachines(machines) {
        writeJson(machinesFile, machines);
    }

    function readLayouts() {
        const raw = readJson(layoutsFile, {});
        if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return {};
        const result = {};
        for (const [key, layout] of Object.entries(raw)) {
            if (!key || key.length > 200) continue;
            result[key] = normalizeLayout(layout);
        }
        return result;
    }

    function saveLayouts(layouts) {
        writeJson(layoutsFile, layouts);
    }

    /** 机器 → 生效配置：机器设置 > 所属用户设置 > 未配置（App 回落 .env）。 */
    function resolveMachineConfig(machine, usersByName) {
        const owner = machine.owner || '';
        const user = owner ? usersByName.get(owner) : null;
        let homes = null;
        let source = 'none';
        if (machine.homes !== null && machine.homes !== undefined) {
            homes = machine.homes;
            source = 'machine';
        } else if (user && user.homes !== null && user.homes !== undefined) {
            homes = user.homes;
            source = 'user';
        }
        return {
            homes,
            source,
            owner,
            ownerName: user ? user.displayName || user.name : '',
            layoutKey: owner || `device_${machine.id}`,
        };
    }

    // ------------------------------------------------------------ 会话

    function signSession(payload) {
        const body = Buffer.from(JSON.stringify(payload), 'utf8').toString('base64url');
        const mac = crypto.createHmac('sha256', secret).update(body).digest('base64url');
        return `${body}.${mac}`;
    }

    function verifySession(token) {
        if (typeof token !== 'string' || !token.includes('.')) return null;
        const index = token.lastIndexOf('.');
        const body = token.slice(0, index);
        const mac = token.slice(index + 1);
        const expected = crypto.createHmac('sha256', secret).update(body).digest('base64url');
        const a = Buffer.from(mac);
        const b = Buffer.from(expected);
        if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
        try {
            const payload = JSON.parse(Buffer.from(body, 'base64url').toString('utf8'));
            if (!payload || typeof payload.u !== 'string' || !payload.exp) return null;
            if (Number(payload.exp) < nowMs()) return null;
            return payload;
        } catch (_) {
            return null;
        }
    }

    function currentAdmin(req) {
        const payload = verifySession(req.cookies ? req.cookies[SESSION_COOKIE] : '');
        if (!payload) return null;
        const user = normalizeUser(readUserInfo(payload.u));
        if (user.role !== 'admin' || user.enabled === false) return null;
        return user;
    }

    function requireAdmin(req, res, next) {
        const admin = currentAdmin(req);
        if (!admin) {
            return jsonFail(res, '未登录或会话已过期', 401, 401);
        }
        req.adminUser = admin;
        next();
    }

    // 登录失败限流：同一 IP 10 分钟内最多 8 次失败。
    const loginFailures = new Map();
    function isLoginBlocked(ip) {
        const item = loginFailures.get(ip);
        if (!item) return false;
        if (nowMs() > item.until) {
            loginFailures.delete(ip);
            return false;
        }
        return item.count >= 8;
    }
    function markLoginFailure(ip) {
        const item = loginFailures.get(ip) || { count: 0, until: nowMs() + 10 * 60 * 1000 };
        item.count += 1;
        item.until = nowMs() + 10 * 60 * 1000;
        loginFailures.set(ip, item);
    }

    function setSessionCookie(res, name) {
        const token = signSession({ u: name, exp: nowMs() + SESSION_TTL_MS });
        res.cookie(SESSION_COOKIE, token, {
            maxAge: SESSION_TTL_MS,
            httpOnly: true,
            secure: false,
            sameSite: 'lax',
            path: '/',
        });
    }

    // ------------------------------------------------------------ Admin API

    app.post('/api/admin/register', (req, res) => {
        try {
            const username = safeUsername(req.body ? req.body.username : '');
            const password = typeof req.body?.password === 'string' ? req.body.password.trim() : '';
            if (!username) {
                return jsonFail(res, '用户名需为 2-20 位字母、数字、下划线或中文');
            }
            if (username === ADMIN_USERNAME) {
                return jsonFail(res, '该用户名已被管理员占用');
            }
            if (!password || password.length < 4 || password.length > 128) {
                return jsonFail(res, '密码长度不合法');
            }
            if (fs.existsSync(passwordPath(username))) {
                return jsonFail(res, '用户名已存在');
            }

            fs.mkdirSync(registerUsersDir, { recursive: true });
            fs.writeFileSync(passwordPath(username), hashPassword(password), 'utf8');

            const maxIdFile = path.join(registerUsersDir, 'max_id.txt');
            let maxId = 0;
            try {
                if (fs.existsSync(maxIdFile)) {
                    maxId = parseInt(fs.readFileSync(maxIdFile, 'utf8').trim(), 10) || 0;
                }
            } catch (_) {
                maxId = 0;
            }
            const id = maxId + 1;
            fs.writeFileSync(maxIdFile, String(id), 'utf8');

            const info = {
                id,
                name: username,
                role: 'user',
                homes: null,
                enabled: true,
                createdAt: new Date().toISOString(),
            };
            writeUserInfo(username, info);
            console.log(`[admin] 新用户注册: ${username} (#${id})`);
            return jsonOk(res, { user: normalizeUser(info) }, '注册成功，请登录');
        } catch (error) {
            console.error('[admin] 注册失败:', error);
            return jsonFail(res, error.message);
        }
    });

    app.post('/api/admin/login', (req, res) => {
        try {
            const ip = normalizeIp(req.ip || req.socket.remoteAddress);
            if (isLoginBlocked(ip)) {
                return jsonFail(res, '尝试次数过多，请 10 分钟后再试', 429, 429);
            }
            const username = safeUsername(req.body ? req.body.username : '');
            const password = typeof req.body?.password === 'string' ? req.body.password.trim() : '';
            if (!username || !password) {
                return jsonFail(res, '用户名和密码不能为空');
            }
            if (!fs.existsSync(passwordPath(username))) {
                markLoginFailure(ip);
                return jsonFail(res, '用户不存在');
            }
            const stored = fs.readFileSync(passwordPath(username), 'utf8').trim();
            if (stored !== hashPassword(password)) {
                markLoginFailure(ip);
                return jsonFail(res, '密码错误');
            }
            const user = normalizeUser(readUserInfo(username));
            if (user.role !== 'admin') {
                return jsonFail(res, '该账号不是管理员', 403, 403);
            }
            if (user.enabled === false) {
                return jsonFail(res, '该账号已被禁用', 403, 403);
            }
            loginFailures.delete(ip);

            const info = readUserInfo(username);
            info.loginTime = new Date().toISOString();
            writeUserInfo(username, info);
            setSessionCookie(res, username);
            console.log(`[admin] 管理员登录: ${username} ip=${ip}`);
            return jsonOk(res, { user }, '登录成功');
        } catch (error) {
            console.error('[admin] 登录失败:', error);
            return jsonFail(res, error.message);
        }
    });

    app.post('/api/admin/logout', (req, res) => {
        res.clearCookie(SESSION_COOKIE, { path: '/' });
        return jsonOk(res, null, '已退出登录');
    });

    app.get('/api/admin/me', (req, res) => {
        const admin = currentAdmin(req);
        if (!admin) return jsonFail(res, '未登录', 401, 401);
        return jsonOk(res, { user: admin });
    });

    function buildOverview(admin) {
        const users = listUsers();
        const usersByName = new Map(users.map((user) => [user.name, user]));
        const machines = Object.values(readMachines()).map((machine) => {
            const config = resolveMachineConfig(machine, usersByName);
            return {
                ...machine,
                ownerName: config.ownerName,
                effectiveHomes: config.homes,
                homesSource: config.source,
                layoutKey: config.layoutKey,
                online: machine.lastSeen > 0 && nowMs() - machine.lastSeen < MACHINE_ONLINE_MS,
            };
        });
        machines.sort((a, b) => {
            if (a.online !== b.online) return a.online ? -1 : 1;
            return (b.lastSeen || 0) - (a.lastSeen || 0);
        });

        const homeSet = new Set();
        for (const machine of machines) {
            for (const home of machine.knownHomes) homeSet.add(home);
            if (machine.homes) for (const home of machine.homes) homeSet.add(home);
        }
        for (const user of users) {
            if (user.homes) for (const home of user.homes) homeSet.add(home);
        }
        const homes = Array.from(homeSet).sort((a, b) => a.localeCompare(b, 'zh-CN'));

        const layouts = Object.entries(readLayouts()).map(([key, layout]) => ({
            key,
            owner: key.startsWith('device_') ? '' : key,
            ...layout,
        }));

        const realtime = onlineAccounts();
        return {
            serverTime: nowMs(),
            admin,
            users: users.map((user) => ({
                ...user,
                machineCount: machines.filter((machine) => machine.owner === user.name).length,
            })),
            machines,
            homes,
            layouts,
            realtimeOnline: Array.isArray(realtime) ? realtime : [],
            stats: {
                users: users.length,
                machines: machines.length,
                online: machines.filter((machine) => machine.online).length,
                homes: homes.length,
            },
        };
    }

    app.get('/api/admin/overview', requireAdmin, (req, res) => {
        try {
            return jsonOk(res, buildOverview(req.adminUser));
        } catch (error) {
            console.error('[admin] 读取概览失败:', error);
            return jsonFail(res, error.message);
        }
    });

    // 接口流量统计查询：?date=YYYY-MM-DD（空 = 今天）。
    const traffic = options.traffic || null;
    app.get('/api/admin/traffic', requireAdmin, (req, res) => {
        try {
            if (!traffic) return jsonFail(res, '流量统计未启用');
            const date = String(req.query.date || '').trim();
            if (date && !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
                return jsonFail(res, '日期格式应为 YYYY-MM-DD');
            }
            const stats = traffic.snapshot(date);
            if (!stats) return jsonFail(res, '该日期没有统计数据');
            return jsonOk(res, {
                dates: traffic.availableDates(),
                stats,
            });
        } catch (error) {
            console.error('[admin] 读取流量统计失败:', error);
            return jsonFail(res, error.message);
        }
    });

    app.put('/api/admin/users/:name', requireAdmin, (req, res) => {
        try {
            const name = safeUsername(req.params.name);
            if (!name || !fs.existsSync(passwordPath(name))) {
                return jsonFail(res, '用户不存在');
            }
            const info = readUserInfo(name);
            const user = normalizeUser(info);

            if (Object.prototype.hasOwnProperty.call(req.body || {}, 'homes')) {
                info.homes = normalizeHomes(req.body.homes);
            }
            if (Object.prototype.hasOwnProperty.call(req.body || {}, 'displayName')) {
                info.displayName = String(req.body.displayName || '').trim().slice(0, 40) || name;
            }
            if (Object.prototype.hasOwnProperty.call(req.body || {}, 'enabled')) {
                if (name === ADMIN_USERNAME && req.body.enabled === false) {
                    return jsonFail(res, '不能禁用管理员账号');
                }
                info.enabled = req.body.enabled !== false;
            }
            if (Object.prototype.hasOwnProperty.call(req.body || {}, 'role')) {
                if (name === ADMIN_USERNAME && req.body.role !== 'admin') {
                    return jsonFail(res, '不能降级管理员账号');
                }
                info.role = req.body.role === 'admin' ? 'admin' : 'user';
            }
            writeUserInfo(name, info);
            console.log(`[admin] 更新用户 ${name}: homes=${JSON.stringify(info.homes)} role=${info.role}`);
            // 用户家庭白名单变化会影响其名下设备 → 逐台推送最新生效配置。
            for (const machine of Object.values(readMachines())) {
                if (machine.owner === name) pushConfigToMachine(machine, { reason: 'user' });
            }
            return jsonOk(res, { user: normalizeUser(readUserInfo(name)) });
        } catch (error) {
            console.error('[admin] 更新用户失败:', error);
            return jsonFail(res, error.message);
        }
    });

    app.put('/api/admin/machines/:id', requireAdmin, (req, res) => {
        try {
            const id = safeDeviceId(req.params.id);
            if (!id) return jsonFail(res, '设备 ID 无效');
            const machines = readMachines();
            const machine = machines[id];
            if (!machine) return jsonFail(res, '设备不存在');
            const usersByName = new Map(listUsers().map((user) => [user.name, user]));

            if (Object.prototype.hasOwnProperty.call(req.body || {}, 'name')) {
                machine.name = String(req.body.name || '').trim().slice(0, 40) || '未命名设备';
            }
            if (Object.prototype.hasOwnProperty.call(req.body || {}, 'owner')) {
                const owner = String(req.body.owner || '').trim();
                if (owner && !usersByName.has(owner)) {
                    return jsonFail(res, '所属用户不存在');
                }
                machine.owner = owner;
            }
            if (Object.prototype.hasOwnProperty.call(req.body || {}, 'homes')) {
                machine.homes = normalizeHomes(req.body.homes);
            }
            machines[id] = normalizeMachine(id, machine);
            saveMachines(machines);
            console.log(`[admin] 更新设备 ${id}: owner=${machine.owner} homes=${JSON.stringify(machine.homes)}`);
            pushConfigToMachine(machines[id], { reason: 'machine' });
            return jsonOk(res, { machine: machines[id] });
        } catch (error) {
            console.error('[admin] 更新设备失败:', error);
            return jsonFail(res, error.message);
        }
    });

    app.delete('/api/admin/machines/:id', requireAdmin, (req, res) => {
        const id = safeDeviceId(req.params.id);
        if (!id) return jsonFail(res, '设备 ID 无效');
        const machines = readMachines();
        if (!machines[id]) return jsonFail(res, '设备不存在');
        delete machines[id];
        saveMachines(machines);
        return jsonOk(res, null, '设备已删除');
    });

    app.put('/api/admin/layouts/:key', requireAdmin, (req, res) => {
        try {
            const key = String(req.params.key || '').trim();
            if (!key || key.length > 200) return jsonFail(res, '布局标识无效');
            const layouts = readLayouts();
            const layout = normalizeLayout({
                all: req.body ? req.body.all : [],
                byHome: req.body ? req.body.byHome : {},
                updatedAt: nowMs(),
                savedAt: nowMs(),
            });
            layouts[key] = layout;
            saveLayouts(layouts);
            pushConfigForLayout(key, { reason: 'layout', layoutChanged: true });
            return jsonOk(res, { key, layout });
        } catch (error) {
            console.error('[admin] 保存布局失败:', error);
            return jsonFail(res, error.message);
        }
    });

    app.delete('/api/admin/layouts/:key', requireAdmin, (req, res) => {
        const key = String(req.params.key || '').trim();
        if (!key || key.length > 200) return jsonFail(res, '布局标识无效');
        const layouts = readLayouts();
        // 不直接删除文件：写一个「更新的空布局」作为墓碑，
        // 否则 App 本地较新的顺序会在下次同步时把重置覆盖回去。
        const now = nowMs();
        layouts[key] = { all: [], byHome: {}, updatedAt: now, savedAt: now };
        saveLayouts(layouts);
        pushConfigForLayout(key, { reason: 'layout', layoutChanged: true });
        return jsonOk(res, null, '布局已重置');
    });

    // ------------------------------------------------------------ 设备 API

    /** 注册/上报共用：更新机器信息并返回生效配置。 */
    function upsertMachine(req, body) {
        const id = safeDeviceId(body.deviceId);
        if (!id) throw new Error('deviceId 无效');
        const machines = readMachines();
        const now = nowMs();
        let machine = machines[id];
        const isNew = !machine;
        if (!machine) {
            machine = normalizeMachine(id, {
                name: body.model || body.name || '未命名设备',
                firstSeen: now,
            });
        }
        if (typeof body.name === 'string' && body.name.trim() && (isNew || machine.name === '未命名设备')) {
            machine.name = body.name.trim().slice(0, 40);
        }
        if (typeof body.platform === 'string' && body.platform.trim()) {
            machine.platform = body.platform.trim().slice(0, 32);
        }
        if (typeof body.model === 'string' && body.model.trim()) {
            machine.model = body.model.trim().slice(0, 64);
        }
        if (typeof body.appVersion === 'string' && body.appVersion.trim()) {
            machine.appVersion = body.appVersion.trim().slice(0, 32);
        }
        if (Array.isArray(body.knownHomes)) {
            machine.knownHomes = body.knownHomes
                .filter((home) => typeof home === 'string' && home.trim())
                .map((home) => home.trim().slice(0, MAX_HOME_NAME))
                .slice(0, MAX_HOMES);
        }
        if (typeof body.currentHome === 'string') {
            machine.currentHome = body.currentHome.trim().slice(0, MAX_HOME_NAME);
        }
        if (typeof body.haConnected === 'boolean') {
            machine.haConnected = body.haConnected;
        }
        // 当前生效的通信账号（ptools 登录 / ws 上报用的账号，可能被自定义覆盖）
        if (typeof body.commAccount === 'string') {
            machine.commAccount = body.commAccount.trim().slice(0, 64);
        }
        machine.ip = normalizeIp(req.ip || req.socket.remoteAddress);
        machine.lastSeen = now;
        machines[id] = normalizeMachine(id, machine);
        saveMachines(machines);
        if (isNew) console.log(`[device] 新设备注册: ${id} ${machine.name} ip=${machine.ip}`);
        return machines[id];
    }

    function deviceConfigResponse(machine) {
        const usersByName = new Map(listUsers().map((user) => [user.name, user]));
        const config = resolveMachineConfig(machine, usersByName);
        const layouts = readLayouts();
        const layout = layouts[config.layoutKey] || null;
        return {
            machine,
            config: {
                ...config,
                layoutUpdatedAt: layout ? layout.updatedAt : 0,
            },
        };
    }

    // ws 通道专用：设备上报 / 保活不再走 HTTP 心跳，直接操作设备表。
    // lastSeen 写盘节流：machines.json 是全量写，客户端 25s 一次 ping 若每次都
    // 落盘代价过高；60s 仍远小于 90s 的在线判定阈值。
    const TOUCH_THROTTLE_MS = 60 * 1000;
    const lastTouchAt = new Map();

    /** 精确匹配优先，其次后缀匹配（ws 上报 16hex，表主键可能是 android_<hex>）。 */
    function findMachineKey(machines, id) {
        if (!id) return null;
        if (machines[id]) return id;
        return Object.keys(machines).find((candidate) => candidate.endsWith(id)) || null;
    }

    /** ws 连接 / ping 保活：仅刷新 lastSeen。 */
    function touchDevice(deviceId) {
        const id = safeDeviceId(deviceId);
        if (!id) return;
        const machines = readMachines();
        const key = findMachineKey(machines, id);
        if (!key) return;
        const now = nowMs();
        // 按设备表主键节流：同一设备无论用哪种 id 形式上报都只算一次。
        if (now - (lastTouchAt.get(key) || 0) < TOUCH_THROTTLE_MS) return;
        lastTouchAt.set(key, now);
        machines[key].lastSeen = now;
        saveMachines(machines);
    }

    /** ws report 帧：更新设备上报字段（已知家庭 / 当前家庭 / HA 连接状态）。 */
    function updateDeviceReport(deviceId, report) {
        const id = safeDeviceId(deviceId);
        if (!id) return null;
        const body = report && typeof report === 'object' ? report : {};
        const machines = readMachines();
        const key = findMachineKey(machines, id);
        if (!key) return null;
        const machine = machines[key];
        const now = nowMs();
        if (Array.isArray(body.knownHomes)) {
            machine.knownHomes = body.knownHomes
                .filter((home) => typeof home === 'string' && home.trim())
                .map((home) => home.trim().slice(0, MAX_HOME_NAME))
                .slice(0, MAX_HOMES);
        }
        if (typeof body.currentHome === 'string') {
            machine.currentHome = body.currentHome.trim().slice(0, MAX_HOME_NAME);
        }
        if (typeof body.haConnected === 'boolean') {
            machine.haConnected = body.haConnected;
        }
        if (typeof body.appVersion === 'string' && body.appVersion.trim()) {
            machine.appVersion = body.appVersion.trim().slice(0, 32);
        }
        machine.lastSeen = now;
        lastTouchAt.set(key, now);
        machines[key] = normalizeMachine(key, machine);
        saveMachines(machines);
        return machines[key];
    }

    /** 按 deviceId 取生效配置（供 ws 下发；未注册返回 null）。 */
    function configFor(deviceId) {
        const id = safeDeviceId(deviceId);
        if (!id) return null;
        const machines = readMachines();
        const key = findMachineKey(machines, id);
        if (!key) return null;
        return { deviceId: key, ...deviceConfigResponse(machines[key]) };
    }

    /** 配置变更后向在线设备推送最新生效配置（离线设备下次连接时由注册/拉取自愈）。 */
    function pushConfigToMachine(machine, extra = {}) {
        if (!machine) return;
        const usersByName = new Map(listUsers().map((user) => [user.name, user]));
        const config = resolveMachineConfig(machine, usersByName);
        const layout = readLayouts()[config.layoutKey] || null;
        pushDeviceConfig(machine.id, {
            t: 'config',
            deviceId: machine.id,
            config: { ...config, layoutUpdatedAt: layout ? layout.updatedAt : 0 },
            ...extra,
        });
    }

    /** 布局变更：只推布局归属（layoutKey）为该标识的设备。 */
    function pushConfigForLayout(key, extra = {}) {
        const machines = readMachines();
        const usersByName = new Map(listUsers().map((user) => [user.name, user]));
        for (const machine of Object.values(machines)) {
            if (resolveMachineConfig(machine, usersByName).layoutKey !== key) continue;
            pushConfigToMachine(machine, extra);
        }
    }

    app.post('/api/device/register', (req, res) => {
        try {
            const machine = upsertMachine(req, req.body || {});
            return jsonOk(res, deviceConfigResponse(machine), '设备已注册');
        } catch (error) {
            return jsonFail(res, error.message);
        }
    });
    app.post('/api/device/heartbeat', (req, res) => {
        try {
            const machine = upsertMachine(req, req.body || {});
            return jsonOk(res, deviceConfigResponse(machine), '心跳已记录');
        } catch (error) {
            return jsonFail(res, error.message);
        }
    });

    app.get('/api/device/config', (req, res) => {
        try {
            const id = safeDeviceId(req.query.deviceId);
            if (!id) return jsonFail(res, 'deviceId 无效');
            const machines = readMachines();
            const machine = machines[id];
            if (!machine) return jsonFail(res, '设备未注册', 404, 404);
            return jsonOk(res, deviceConfigResponse(machine));
        } catch (error) {
            return jsonFail(res, error.message);
        }
    });

    app.get('/api/device/layout', (req, res) => {
        try {
            const id = safeDeviceId(req.query.deviceId);
            if (!id) return jsonFail(res, 'deviceId 无效');
            const machines = readMachines();
            const machine = machines[id];
            if (!machine) return jsonFail(res, '设备未注册', 404, 404);
            const usersByName = new Map(listUsers().map((user) => [user.name, user]));
            const config = resolveMachineConfig(machine, usersByName);
            const layout = readLayouts()[config.layoutKey];
            return jsonOk(res, {
                key: config.layoutKey,
                layout: layout || { all: [], byHome: {}, updatedAt: 0, savedAt: 0 },
            });
        } catch (error) {
            return jsonFail(res, error.message);
        }
    });

    app.put('/api/device/layout', (req, res) => {
        try {
            const body = req.body || {};
            const id = safeDeviceId(body.deviceId);
            if (!id) return jsonFail(res, 'deviceId 无效');
            const machines = readMachines();
            const machine = machines[id];
            if (!machine) return jsonFail(res, '设备未注册', 404, 404);
            const usersByName = new Map(listUsers().map((user) => [user.name, user]));
            const config = resolveMachineConfig(machine, usersByName);
            const layouts = readLayouts();
            const incoming = normalizeLayout({
                all: body.all,
                byHome: body.byHome,
                updatedAt: body.updatedAt,
                savedAt: nowMs(),
            });
            const existing = layouts[config.layoutKey];
            // 冲突策略：时间戳旧的一方不覆盖新的一方，把服务端版本回给客户端。
            if (existing && existing.updatedAt > incoming.updatedAt) {
                return jsonOk(res, {
                    key: config.layoutKey,
                    layout: existing,
                    conflict: true,
                }, '服务端已有更新的布局');
            }
            layouts[config.layoutKey] = incoming;
            saveLayouts(layouts);
            console.log(`[layout] ${config.layoutKey} 已保存 updatedAt=${incoming.updatedAt}`);
            return jsonOk(res, {
                key: config.layoutKey,
                layout: incoming,
                conflict: false,
            });
        } catch (error) {
            console.error('[layout] 保存失败:', error);
            return jsonFail(res, error.message);
        }
    });

    // ------------------------------------------------------------ Admin 页面

    const adminHtml = path.join(webAppPath, 'admin.html');
    app.get(['/admin', '/admin/'], (req, res) => {
        if (!fs.existsSync(adminHtml)) {
            return res.status(404).send('admin.html 未部署');
        }
        res.setHeader('Cache-Control', 'no-cache');
        return res.sendFile(adminHtml);
    });

    console.log(`[admin] Admin 页面: /admin（管理员账号: ${ADMIN_USERNAME}）`);
    // ws 握手成功后由 realtime 回写设备的通信账号与客户端标识
    // （app / version / build，仅更新已注册设备，不新建）。
    // 客户端 ws 上报的是 16hex 设备号；admin 表主键可能是 `android_<hex>` /
    // `gen_<hex>` 这类带前缀形式，故先精确匹配再按后缀匹配。
    function setCommInfo(deviceId, comm) {
        const id = safeDeviceId(deviceId);
        const info = comm && typeof comm === 'object' ? comm : {};
        const next = {
            commAccount: typeof info.account === 'string' ? info.account.trim().slice(0, 64) : '',
            commApp: typeof info.app === 'string' ? info.app.trim().slice(0, 64) : '',
            commVersion: typeof info.version === 'string' ? info.version.trim().slice(0, 32) : '',
            commBuild: typeof info.build === 'string' ? info.build.trim().slice(0, 32) : '',
        };
        if (!id || !Object.values(next).some((value) => value)) return;
        const machines = readMachines();
        const key = machines[id]
            ? id
            : Object.keys(machines).find((candidate) => candidate.endsWith(id));
        const machine = key ? machines[key] : null;
        if (!machine || Object.entries(next).every(([field, value]) => machine[field] === value)) return;
        Object.assign(machine, next);
        machines[key] = normalizeMachine(key, machine);
        saveMachines(machines);
    }
    return {
        adminDir,
        ADMIN_USERNAME,
        setCommInfo,
        // ws 通道复用：保活 / 上报 / 取配置
        touchDevice,
        updateDeviceReport,
        configFor,
    };
}

module.exports = { attachAdmin, ADMIN_USERNAME };
