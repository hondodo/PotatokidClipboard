// Admin 管理接口 + 设备配置/布局同步接口。
//
// 数据全部落在 ../datas/admin 下（与现有 register/users 同级）：
// - users 仍复用 ../datas/register/users/<name> 与 <name>_info.txt，
//   这里只在 info JSON 上扩展 role（admin | parent | user 三级）/ homes / displayName / enabled；
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
// 儿童模式（方案 §2.2）：档案数量与各名单字段的上限。
const MAX_PARENTAL_CHILDREN = 12;
const MAX_PARENTAL_LIST = 200;
// 禁看时段条目格式 `HH:MM-HH:MM`（与 Flutter 端 QuietHour.tryParse 对齐，从严校验）。
const PARENTAL_QUIET_HOURS_RE = /^(?:[01]\d|2[0-3]):[0-5]\d-(?:[01]\d|2[0-3]):[0-5]\d$/;

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

/**
 * 儿童模式配置校验（方案 §2.2 配置结构，PUT parental body 分支用）。
 *
 * 取舍（整体拒绝 vs 逐字段归一）：
 * - **整体拒绝（throw → jsonFail）**：结构/类型/枚举/数值非法——`mode` 缺失或
 *   枚举外、`profileMode`/`unlockMode` 枚举外、`children`/名单字段非数组、
 *   档案 id/name 缺失、限额为负或非数值、`quietHours` 条目格式非法。理由：
 *   静默归一会让家长误以为规则已生效（白名单被清空 = 没生效，格式错的
 *   禁看时段被丢 = 没禁）。
 * - **安全归一**：字符串裁剪到长度上限、名单去重/截断、`age` 取整、
 *   缺失的可选字段补默认值（与 Flutter 端 `ParentalConfig.fromJson` 默认一致）。
 *
 * 返回 null 表示清除 parental（body 给 `parental: null` 或字段缺失时读路径）。
 */
function normalizeParental(value) {
    if (value === null || value === undefined) return null;
    if (typeof value !== 'object' || Array.isArray(value)) {
        throw new Error('parental 必须是对象或 null');
    }
    // mode 是全局总开关：必填且只能 off|on（缺失或拼错整体拒绝，避免静默不生效）。
    if (value.mode !== 'off' && value.mode !== 'on') {
        throw new Error('parental.mode 必须是 off 或 on');
    }
    // 解锁方式：缺失默认 remote（与客户端 fromJson 一致）；给出但非法 → 拒绝。
    let unlockMode = 'remote';
    if (value.unlockMode !== undefined && value.unlockMode !== null) {
        if (value.unlockMode !== 'remote' && value.unlockMode !== 'pin' && value.unlockMode !== 'arith') {
            throw new Error('parental.unlockMode 必须是 remote、pin 或 arith');
        }
        unlockMode = value.unlockMode;
    }
    if (value.pin !== undefined && value.pin !== null && typeof value.pin !== 'string') {
        throw new Error('parental.pin 必须是字符串');
    }
    if (value.ownerAccount !== undefined && value.ownerAccount !== null && typeof value.ownerAccount !== 'string') {
        throw new Error('parental.ownerAccount 必须是字符串');
    }
    // activeChildIds：电视端持久化自己的选择，后台一般不下发；给则必须是字符串数组。
    const activeChildIds = normalizeParentalIdList(value.activeChildIds, 'parental.activeChildIds');

    if (value.children !== undefined && value.children !== null && !Array.isArray(value.children)) {
        throw new Error('parental.children 必须是数组');
    }
    const rawChildren = Array.isArray(value.children) ? value.children : [];
    if (rawChildren.length > MAX_PARENTAL_CHILDREN) {
        throw new Error(`parental.children 最多 ${MAX_PARENTAL_CHILDREN} 个档案`);
    }
    const children = [];
    const seenIds = new Set();
    rawChildren.forEach((child, index) => {
        const at = `parental.children[${index}]`;
        if (!child || typeof child !== 'object' || Array.isArray(child)) {
            throw new Error(`${at} 必须是对象`);
        }
        if (typeof child.id !== 'string' || !child.id.trim() || child.id.trim().length > 64) {
            throw new Error(`${at}.id 必须是非空字符串（≤64 字符）`);
        }
        const id = child.id.trim();
        if (seenIds.has(id)) throw new Error(`${at}.id 重复：${id}`);
        seenIds.add(id);
        if (typeof child.name !== 'string' || !child.name.trim()) {
            throw new Error(`${at}.name 必须是非空字符串`);
        }
        // 档位：缺失默认 mild（与客户端 fromJson 一致）；给出但非法 → 拒绝。
        let profileMode = 'mild';
        if (child.profileMode !== undefined && child.profileMode !== null) {
            if (child.profileMode !== 'mild' && child.profileMode !== 'strict') {
                throw new Error(`${at}.profileMode 必须是 mild 或 strict`);
            }
            profileMode = child.profileMode;
        }
        // age：缺失/null = 未知；给出则必须是 0~150 的数值。
        let age;
        if (child.age !== undefined && child.age !== null) {
            if (typeof child.age !== 'number' || !Number.isFinite(child.age) || child.age < 0 || child.age > 150) {
                throw new Error(`${at}.age 必须是 0~150 的数值`);
            }
            age = Math.trunc(child.age);
        }
        // 限额：缺失默认 0（不启用）；给出则必须是非负数值（负数/非数值拒绝）。
        const sessionLimitMin = normalizeParentalLimit(child.sessionLimitMin, `${at}.sessionLimitMin`);
        const dailyLimitMin = normalizeParentalLimit(child.dailyLimitMin, `${at}.dailyLimitMin`);
        if (child.locked !== undefined && child.locked !== null && typeof child.locked !== 'boolean') {
            throw new Error(`${at}.locked 必须是布尔值`);
        }
        children.push({
            id,
            name: child.name.trim().slice(0, 40),
            ...(age !== undefined ? { age } : {}),
            profileMode,
            locked: child.locked === true,
            hideGroups: normalizeParentalNameList(child.hideGroups, `${at}.hideGroups`),
            hideChannels: normalizeParentalNameList(child.hideChannels, `${at}.hideChannels`),
            allowGroups: normalizeParentalNameList(child.allowGroups, `${at}.allowGroups`),
            allowChannels: normalizeParentalNameList(child.allowChannels, `${at}.allowChannels`),
            sessionLimitMin,
            dailyLimitMin,
            quietHours: normalizeParentalQuietHours(child.quietHours, `${at}.quietHours`),
        });
    });

    return {
        mode: value.mode,
        activeChildIds,
        children,
        unlockMode,
        pin: typeof value.pin === 'string' ? value.pin.trim().slice(0, 32) : '',
        ownerAccount: typeof value.ownerAccount === 'string' ? value.ownerAccount.trim().slice(0, 64) : '',
    };
}

/** 限额字段：缺失/null → 0（不启用）；给出则必须是非负数值。 */
function normalizeParentalLimit(value, field) {
    if (value === undefined || value === null) return 0;
    if (typeof value !== 'number' || !Number.isFinite(value) || value < 0) {
        throw new Error(`${field} 必须是非负数值`);
    }
    return Math.trunc(value);
}

/** 名单字段（hide/allow 四件套）：缺失 → []；非数组或元素非字符串 → 拒绝（静默丢条目会让规则看似生效实则失效）。 */
function normalizeParentalNameList(value, field) {
    if (value === undefined || value === null) return [];
    if (!Array.isArray(value)) throw new Error(`${field} 必须是数组`);
    for (const item of value) {
        if (typeof item !== 'string') throw new Error(`${field} 的元素必须是字符串`);
    }
    return normalizeStringList(value, MAX_PARENTAL_LIST);
}

/** id 列表（activeChildIds）：缺失 → []；结构非法 → 拒绝；字符串条目去重截断。 */
function normalizeParentalIdList(value, field) {
    if (value === undefined || value === null) return [];
    if (!Array.isArray(value)) throw new Error(`${field} 必须是数组`);
    for (const item of value) {
        if (typeof item !== 'string') throw new Error(`${field} 的元素必须是字符串`);
    }
    const list = [];
    for (const item of value) {
        const id = item.trim();
        if (!id || id.length > 64) continue;
        if (!list.includes(id)) list.push(id);
        if (list.length >= MAX_PARENTAL_CHILDREN) break;
    }
    return list;
}

/** 禁看时段：缺失 → []；非数组/条目格式非法 → 拒绝（拼错的时段静默失效会让家长误以为已禁）。 */
function normalizeParentalQuietHours(value, field) {
    if (value === undefined || value === null) return [];
    if (!Array.isArray(value)) throw new Error(`${field} 必须是数组`);
    const list = [];
    for (const item of value) {
        if (typeof item !== 'string') throw new Error(`${field} 的元素必须是字符串`);
        const text = item.trim();
        if (!PARENTAL_QUIET_HOURS_RE.test(text)) {
            throw new Error(`${field} 条目格式必须是 HH:MM-HH:MM：${item}`);
        }
        // 起止相同 = 全天不生效的空条目（Flutter 端 tryParse 同样判无效），视为拼错。
        if (text.slice(0, 5) === text.slice(6, 11)) {
            throw new Error(`${field} 起止时间不能相同：${item}`);
        }
        if (!list.includes(text)) list.push(text);
        if (list.length >= MAX_PARENTAL_LIST) break;
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
        // 角色归一（方案 §4.2 三级角色 admin | parent | user）：家长操作
        // 允许 parent + admin、拒绝 user——parent 原样透传、其余归一为 user；
        // 阶段 3 的家长操作入口按同一口径（role ∈ {parent, admin}）判定。
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
            role: isAdmin ? 'admin' : (info.role === 'parent' ? 'parent' : 'user'),
            homes,
            enabled: info.enabled !== false,
            createdAt: info.createdAt || '',
            loginTime: info.loginTime || '',
        };
    }

    // 角色排序权重：admin > parent > user（listUsers 排序用）。
    function roleRank(role) {
        return role === 'admin' ? 0 : role === 'parent' ? 1 : 2;
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
            if (a.role !== b.role) return roleRank(a.role) - roleRank(b.role);
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
        // 儿童模式配置（方案 §2.2）：按白名单重建记录时必须保留 parental，
        // 否则 PUT 后立刻被丢掉。读路径对坏数据 try/catch 容错（丢弃不抛，
        // 单条损坏不能让整份 machines.json 读不出来）。
        let parental = null;
        try {
            parental = normalizeParental(machine.parental);
        } catch (_) {
            parental = null;
        }
        return {
            id,
            name: typeof machine.name === 'string' && machine.name.trim()
                ? machine.name.trim().slice(0, 40)
                : '未命名设备',
            owner: typeof machine.owner === 'string' ? machine.owner.trim() : '',
            homes,
            parental,
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
            // 儿童模式配置透传（方案 §2.2：parental 挂机器记录，经 config 帧下发）。
            parental: machine.parental || null,
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

    function currentSession(req) {
        const payload = verifySession(req.cookies ? req.cookies[SESSION_COOKIE] : '');
        if (!payload) return null;
        const user = normalizeUser(readUserInfo(payload.u));
        if (user.enabled === false) return null;
        return user;
    }

    function currentAdmin(req) {
        const user = currentSession(req);
        if (!user || user.role !== 'admin') return null;
        return user;
    }

    // 家长操作门禁（方案 §4.2 三级角色）：parent + admin 放行、user 拒绝。
    // 覆盖概览查看与机器配置（含 parental）编辑；用户管理/布局/删机器仍 admin-only。
    function currentParentOperator(req) {
        const user = currentSession(req);
        if (!user || (user.role !== 'admin' && user.role !== 'parent')) return null;
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

    function requireParentOperator(req, res, next) {
        const operator = currentParentOperator(req);
        if (!operator) {
            return jsonFail(res, '未登录或无家长操作权限', 401, 401);
        }
        req.adminUser = operator;
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
            // 登录放行 admin|parent（家长要用管理页配置儿童模式），user 拒绝。
            if (user.role !== 'admin' && user.role !== 'parent') {
                return jsonFail(res, '该账号无管理页访问权限', 403, 403);
            }
            if (user.enabled === false) {
                return jsonFail(res, '该账号已被禁用', 403, 403);
            }
            loginFailures.delete(ip);

            const info = readUserInfo(username);
            info.loginTime = new Date().toISOString();
            writeUserInfo(username, info);
            setSessionCookie(res, username);
            console.log(`[admin] 管理页登录: ${username} role=${user.role} ip=${ip}`);
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
        // admin.html 自动登录用；parent 登录也需通过（否则家长登录后 401 循环）。
        const operator = currentParentOperator(req);
        if (!operator) return jsonFail(res, '未登录', 401, 401);
        return jsonOk(res, { user: operator });
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

    app.get('/api/admin/overview', requireParentOperator, (req, res) => {
        try {
            return jsonOk(res, buildOverview(req.adminUser));
        } catch (error) {
            console.error('[admin] 读取概览失败:', error);
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
                // 三级角色：admin / parent / user（其余值按 user 归一）。
                info.role = req.body.role === 'admin' ? 'admin' : (req.body.role === 'parent' ? 'parent' : 'user');
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

    app.put('/api/admin/machines/:id', requireParentOperator, (req, res) => {
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
            // 儿童模式配置（方案 §2.2 三处小改之一）：body 给 parental 对象则校验后
            // 整体替换（整对象替换语义，后台表单先读后改再全量回传）；给 null 清除；
            // 不给该键则保持原值。校验失败 throw → 走下方 catch 整体拒绝，不落盘。
            if (Object.prototype.hasOwnProperty.call(req.body || {}, 'parental')) {
                machine.parental = normalizeParental(req.body.parental);
            }
            machines[id] = normalizeMachine(id, machine);
            saveMachines(machines);
            console.log(`[admin] 更新设备 ${id}: owner=${machine.owner} homes=${JSON.stringify(machine.homes)} parental=${machine.parental ? machine.parental.mode : 'null'}`);
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

    /** 登录侧自动建档：登录请求携带 deviceId 且设备表无该记录时，复用 upsertMachine 建档。 */
    function ensureMachineForLogin(req, body) {
        const id = safeDeviceId(body && body.deviceId);
        if (!id) return null;
        if (findMachineKey(readMachines(), id)) return null; // 已有记录：登录不改动既有数据
        return upsertMachine(req, body);
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

    // 生效配置读取（含 parental/PIN）：按家长操作门禁放行 parent+admin。
    // 设备自身不走此端点（注册/心跳与 WS config 帧自带配置），唯一调用方
    // pscreen_home 家长视图在 ensureAdminSession 后由持久化 Cookie 携带会话。
    app.get('/api/device/config', requireParentOperator, (req, res) => {
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
        // 登录链路（HTTP /api/login、ws 握手）携带 deviceId 时自动建档
        ensureMachineForLogin,
        // ws 通道复用：保活 / 上报 / 取配置
        touchDevice,
        updateDeviceReport,
        configFor,
    };
}

// normalizeParental 导出仅供测试直接驱动校验逻辑（attachAdmin 需要完整服务环境）。
module.exports = { attachAdmin, ADMIN_USERNAME, normalizeParental };
