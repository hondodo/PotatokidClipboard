// 家长自定义登录名（claim）：设备派生账号 → 自定义账号的一次性迁移。
//
// 设计前提（见 pscreen_home/FLAVORS.md 的「自定义登录名（claim）」一节）：
// - 不改 /api/login 与 accounts.js 的校验链路，中控端 / 电视端登录行为保持原样；
// - claim 只在持有短时一次性 ticket 且已登录 pk_admin 会话时发生；
// - 一次改名必须把散落在各数据文件里的「旧账号名」全部替换，否则家长会丢掉
//   已绑定的电视、私有别名、观看记录与解锁历史。
//
// 本模块只做「名称校验 + 文件级迁移」，ticket 的签发/核销在 admin.js 内复用
// 现成的 signSession / verifySession（HMAC 密钥不导出到模块外）。
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// 目标登录名必须同时满足：
// - accounts.js 的 ACCOUNT_PATTERN（仅 ASCII，ws 握手 / 别名 key 依赖）
// - admin.js 的 safeUsername（2-64 位，不允许冒号与中文）
// 两者交集即下面这一条。中文名会在 ptools /api/login 被判 invalid_account，故拒绝。
const CLAIM_NAME_PATTERN = /^[A-Za-z0-9_.-]{2,64}$/;

// `parent.` / `tv.` / `board.` 等前缀属于设备派生账号命名空间：
// 否则自定义名可能撞上 roleForNewAccount() 的 parent 派生正则，白拿家长角色。
const RESERVED_SCOPE_PATTERN = /^(parent|tv|board|phone|home)\./i;

// `<flavor>.<kind>.<设备号16hex>`：所有现网设备自举账号都符合此格式。
const DERIVED_ACCOUNT_PATTERN = /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[0-9a-fA-F]{16}$/;
const DEFAULT_PASSWORD_MD5 = crypto.createHash('md5').update('123456').digest('hex');

function isDerivedAccount(account) {
    return DERIVED_ACCOUNT_PATTERN.test(String(account || ''));
}

/**
 * 校验目标登录名。
 * @param {string} name 用户输入的登录名
 * @param {{adminUsername?: string, accountExists?: (name:string)=>boolean}} ctx
 * @returns {{ok: boolean, name?: string, reason?: string}}
 */
function validateClaimName(name, ctx) {
    const options = ctx || {};
    const value = String(name == null ? '' : name).trim();
    if (!CLAIM_NAME_PATTERN.test(value)) {
        return { ok: false, reason: '登录名需为 2-64 位字母、数字、下划线、点或连字符' };
    }
    if (value === '.' || value === '..' || value.startsWith('.')) {
        return { ok: false, reason: '登录名不能以点开头' };
    }
    if (RESERVED_SCOPE_PATTERN.test(value)) {
        return { ok: false, reason: '该前缀为设备账号保留，请换一个登录名' };
    }
    if (isDerivedAccount(value)) {
        return { ok: false, reason: '不能使用设备派生账号格式' };
    }
    if (options.adminUsername && value === options.adminUsername) {
        return { ok: false, reason: '该登录名已被管理员占用' };
    }
    if (typeof options.accountExists === 'function' && options.accountExists(value)) {
        return { ok: false, reason: '该登录名已被占用' };
    }
    return { ok: true, name: value };
}

function readJson(file, fallback) {
    try {
        if (!fs.existsSync(file)) return fallback;
        return JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch (_) {
        return fallback;
    }
}

/** 显式抛错的原子写：迁移中途失败必须让调用方知道，不能像 writeJson 那样吞掉。 */
function writeJsonOrThrow(file, value) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const tmp = `${file}.claim.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(value, null, 2), 'utf8');
    fs.renameSync(tmp, file);
}

/** 递归替换所有「精确等于旧账号名」的字符串值（不动 key，key 单独处理）。 */
function replaceValues(value, oldName, newName) {
    if (typeof value === 'string') return value === oldName ? newName : value;
    if (Array.isArray(value)) return value.map((item) => replaceValues(item, oldName, newName));
    if (value && typeof value === 'object') {
        const next = {};
        for (const key of Object.keys(value)) {
            next[key] = replaceValues(value[key], oldName, newName);
        }
        return next;
    }
    return value;
}

function renameMapKeys(map, oldName, newName) {
    if (!map || typeof map !== 'object' || Array.isArray(map)) return map;
    const next = {};
    for (const key of Object.keys(map)) next[key] = map[key];
    if (Object.prototype.hasOwnProperty.call(next, oldName)) {
        const value = next[oldName];
        delete next[oldName];
        // 新旧 key 同时存在时保留新 key 的既有值，不覆盖已有配置。
        if (!Object.prototype.hasOwnProperty.call(next, newName)) next[newName] = value;
    }
    return next;
}

/** JSONL 逐行替换：坏行原样保留，不因一条脏数据中断整个迁移。 */
function rewriteJsonl(file, oldName, newName) {
    if (!fs.existsSync(file)) return 0;
    const raw = fs.readFileSync(file, 'utf8');
    const trailingNewline = raw.endsWith('\n');
    const lines = (trailingNewline ? raw.slice(0, -1) : raw).split('\n');
    let changed = 0;
    const output = lines.map((line) => {
        if (!line.trim()) return line;
        let parsed;
        try {
            parsed = JSON.parse(line);
        } catch (_) {
            return line;
        }
        const next = replaceValues(parsed, oldName, newName);
        if (JSON.stringify(next) !== JSON.stringify(parsed)) changed++;
        return JSON.stringify(next);
    });
    const text = output.join('\n') + (trailingNewline ? '\n' : '');
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const tmp = `${file}.claim.tmp`;
    fs.writeFileSync(tmp, text, 'utf8');
    fs.renameSync(tmp, file);
    return changed;
}

function snapshot(files, backupDir) {
    fs.mkdirSync(backupDir, { recursive: true });
    let copied = 0;
    for (const file of files) {
        if (!fs.existsSync(file)) continue;
        fs.copyFileSync(file, path.join(backupDir, path.basename(file)));
        copied++;
    }
    return copied;
}

/**
 * 把 oldName 这个家长派生账号整体迁移为 newName。
 *
 * 覆盖：账号本体 / machines.json / layouts.json / parental_avatars.json /
 * realtime 事件与历史 / outbox / reads / datas/users 目录。
 * 题库（parental_quizzes.json）与图片目录按 deviceId 索引，不含账号名，无需改动。
 *
 * 旧账号文件**保留但改为不可登录**（随机口令 + enabled:false）：因为 /api/login
 * 的 verifyOrProvision 在「账号不存在 + 默认口令」时会自动重新建档，直接删除
 * 旧文件会让旧派生名凭空复活成第二个 parent 账号。
 *
 * 新账号**必须换一个新随机口令**：自定义登录名是可猜的，若沿用设备自举的
 * 默认口令 123456，任何人都能拿这个名字冒充家长登录。口令 MD5 由调用方
 * 生成并传入，客户端在 claim 响应里拿到一次明文后自行持久化；校验方式仍是
 * 「账号文件里的 MD5 比对」，/api/login 与 ws 握手链路不变。
 *
 * @returns {{backupDir: string, changed: string[]}}
 */
function applyAccountRename(options) {
    const opts = options || {};
    const datasDir = opts.datasDir;
    const registerUsersDir = opts.registerUsersDir || path.join(datasDir, 'register', 'users');
    const oldName = String(opts.oldName || '').trim();
    const newName = String(opts.newName || '').trim();
    const newPasswordMd5 = String(opts.newPasswordMd5 || '').trim().toLowerCase();

    if (!datasDir || !oldName || !newName || oldName === newName) {
        throw new Error('改名参数不完整');
    }
    if (!/^[a-f0-9]{32}$/.test(newPasswordMd5)) {
        throw new Error('新口令摘要无效');
    }
    if (newPasswordMd5 === DEFAULT_PASSWORD_MD5) {
        throw new Error('不能沿用设备自举的默认口令');
    }
    const oldPasswordFile = path.join(registerUsersDir, oldName);
    const oldInfoFile = path.join(registerUsersDir, `${oldName}_info.txt`);
    const newPasswordFile = path.join(registerUsersDir, newName);
    const newInfoFile = path.join(registerUsersDir, `${newName}_info.txt`);

    if (!fs.existsSync(oldPasswordFile)) throw new Error('原家长账号不存在');
    if (fs.existsSync(newPasswordFile) || fs.existsSync(newInfoFile)) {
        throw new Error('目标登录名已被占用');
    }
    const oldInfo = readJson(oldInfoFile, null);
    if (!oldInfo || oldInfo.role !== 'parent') {
        throw new Error('只有家长账号可以设置登录名');
    }
    // 旧账号文件会保留（防止默认口令复活），所以必须靠标记保证只能迁移一次。
    if (oldInfo.claimedTo || oldInfo.claimedAt) {
        throw new Error('该账号已迁移过登录名');
    }

    const adminDir = path.join(datasDir, 'admin');
    const realtimeDir = path.join(datasDir, 'realtime');
    const usersDir = path.join(datasDir, 'users');
    const machinesFile = path.join(adminDir, 'machines.json');
    const layoutsFile = path.join(adminDir, 'layouts.json');
    const avatarsFile = path.join(adminDir, 'parental_avatars.json');
    const eventsFile = path.join(realtimeDir, 'events.jsonl');
    const historyFile = path.join(realtimeDir, 'history.jsonl');

    const stamp = new Date().toISOString().replace(/[:.]/g, '-');
    const backupDir = path.join(adminDir, 'claim-backups', `${stamp}_${oldName.replace(/[^A-Za-z0-9_.-]/g, '_')}`);
    snapshot([
        oldPasswordFile, oldInfoFile, machinesFile, layoutsFile, avatarsFile,
        eventsFile, historyFile,
    ], backupDir);

    const changed = [];

    // 1. 账号本体：先建新文件，再让旧名失效，避免中途出现「两边都登不上」。
    const newInfo = Object.assign({}, oldInfo, {
        name: newName,
        role: 'parent', // 显式保留：migrateUsers 在 role 缺失时会降级成 user
        claimedAt: new Date().toISOString(),
        claimFrom: oldName,
    });
    delete newInfo.enabled;
    delete newInfo.loginTime;
    fs.writeFileSync(newInfoFile, JSON.stringify(newInfo, null, 2), 'utf8');
    fs.writeFileSync(newPasswordFile, newPasswordMd5, 'utf8'); // 换成不可猜的新口令
    changed.push('register/users');

    // 2. 旧名改为不可登录（保留文件以阻止默认口令自动建档复活）。
    fs.writeFileSync(oldPasswordFile, crypto.randomBytes(32).toString('hex'), 'utf8');
    oldInfo.enabled = false;
    oldInfo.claimedTo = newName;
    fs.writeFileSync(oldInfoFile, JSON.stringify(oldInfo, null, 2), 'utf8');

    // 3. machines.json：parents / owner / commAccount / parental.ownerAccount / aliases key。
    const machines = readJson(machinesFile, {});
    let machinesChanged = 0;
    for (const id of Object.keys(machines)) {
        const machine = machines[id];
        if (!machine || typeof machine !== 'object') continue;
        const next = replaceValues(machine, oldName, newName);
        if (next.aliases && typeof next.aliases === 'object') {
            next.aliases = renameMapKeys(next.aliases, oldName, newName);
        }
        if (JSON.stringify(next) !== JSON.stringify(machine)) machinesChanged++;
        machines[id] = next;
    }
    if (machinesChanged) {
        writeJsonOrThrow(machinesFile, machines);
        changed.push(`machines.json (${machinesChanged} 台)`);
    }

    // 4. layouts.json 的 key 可能就是账号名（layoutKey = owner || device_<id>）。
    const layouts = readJson(layoutsFile, {});
    const nextLayouts = renameMapKeys(layouts, oldName, newName);
    if (JSON.stringify(nextLayouts) !== JSON.stringify(layouts)) {
        writeJsonOrThrow(layoutsFile, nextLayouts);
        changed.push('layouts.json');
    }

    // 5. 头像索引里的 uploadedBy 仅作审计展示，但一并保持一致。
    const avatars = readJson(avatarsFile, null);
    if (avatars) {
        const nextAvatars = replaceValues(avatars, oldName, newName);
        if (JSON.stringify(nextAvatars) !== JSON.stringify(avatars)) {
            writeJsonOrThrow(avatarsFile, nextAvatars);
            changed.push('parental_avatars.json');
        }
    }

    // 6. 观看记录 / 解锁请求 / 历史会话：可见性靠 to / audience / actor 精确匹配账号名。
    const eventsChanged = rewriteJsonl(eventsFile, oldName, newName);
    const historyChanged = rewriteJsonl(historyFile, oldName, newName);
    if (eventsChanged || historyChanged) {
        changed.push(`realtime (events ${eventsChanged} / history ${historyChanged})`);
    }

    // 7. 离线消息队列与已读游标：文件名即账号名。
    for (const dirName of ['outbox', 'reads']) {
        const dir = path.join(realtimeDir, dirName);
        const source = path.join(dir, `${oldName}.json`);
        const target = path.join(dir, `${newName}.json`);
        if (!fs.existsSync(source) || fs.existsSync(target)) continue;
        fs.mkdirSync(dir, { recursive: true });
        fs.copyFileSync(source, target);
        fs.unlinkSync(source);
        changed.push(`realtime/${dirName}`);
    }

    // 8. 按 cookie username 分目录的用户私有数据（剪贴板 / 上传 / 笔记 / 遥控会话）。
    const oldUserDir = path.join(usersDir, oldName);
    const newUserDir = path.join(usersDir, newName);
    if (fs.existsSync(oldUserDir) && !fs.existsSync(newUserDir)) {
        fs.mkdirSync(usersDir, { recursive: true });
        fs.renameSync(oldUserDir, newUserDir);
        const sessionsFile = path.join(newUserDir, 'remote_sessions.json');
        const sessions = readJson(sessionsFile, null);
        if (sessions) {
            const nextSessions = replaceValues(sessions, oldName, newName);
            if (JSON.stringify(nextSessions) !== JSON.stringify(sessions)) {
                writeJsonOrThrow(sessionsFile, nextSessions);
            }
        }
        changed.push('users/<account>/');
    }

    return { backupDir, changed };
}

/** 已核销 ticket 记录：只存 jti → 时间戳，定期清掉过期项。 */
function readConsumedTickets(file) {
    const data = readJson(file, {});
    return data && typeof data === 'object' && !Array.isArray(data) ? data : {};
}

function consumeTicket(file, jti, nowMs, ttlMs) {
    const tickets = readConsumedTickets(file);
    if (Object.prototype.hasOwnProperty.call(tickets, jti)) return false;
    const now = Number(nowMs) || Date.now();
    const ttl = Number(ttlMs) || 10 * 60 * 1000;
    for (const key of Object.keys(tickets)) {
        if (now - Number(tickets[key]) > ttl) delete tickets[key];
    }
    tickets[jti] = now;
    writeJsonOrThrow(file, tickets);
    return true;
}

module.exports = {
    CLAIM_NAME_PATTERN,
    RESERVED_SCOPE_PATTERN,
    DERIVED_ACCOUNT_PATTERN,
    isDerivedAccount,
    validateClaimName,
    applyAccountRename,
    readConsumedTickets,
    consumeTicket,
    replaceValues,
    renameMapKeys,
};
