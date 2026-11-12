// 家长号与设备派生号「关联」（新模型：两层身份并存，互不替代）。
//
// 旧模型把派生号「改名迁移」+ 旧号禁用成墓碑，导致三个问题：实时通道被一起
// 切成家长号、重装即锁死、后端多一个登不上的僵尸账号。
//
// 新模型（见 docs/parent-app-redesign-prototype.html 的「家长号与跨设备」页）：
// - 派生号 `<flavor>.<kind>.<设备号>` = 设备身份证：实时通道、心跳、设备表
//   commAccount 永远用它，账号文件口令恒为默认 123456、永不改名/禁用；
// - 家长号（如 mi10s）= 「家长这个人」的账号：仅用于 HTTP 管理登录与
//   machine.parents 可见性判定，口令由用户自设、可重置、可跨设备登录。
//
// 本模块只做「家长号账号建档 + 儿童信息绑定关系映射」；ticket 的签发/核销仍在
// admin.js 内复用现成的 signSession / verifySession（HMAC 密钥不导出到模块外）。
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// 家长号必须同时满足：
// - accounts.js 的 ACCOUNT_PATTERN（仅 ASCII，ws 握手 / 别名 key 依赖）
// - admin.js 的 safeUsername（2-64 位，不允许冒号与中文）
// 两者交集即下面这一条。中文名会在 ptools /api/login 被判 invalid_account，故拒绝。
const CLAIM_NAME_PATTERN = /^[A-Za-z0-9_.-]{2,64}$/;

// `parent.` / `tv.` / `board.` 等前缀属于设备派生账号命名空间：
// 否则家长号可能撞上 roleForNewAccount() 的 parent 派生正则，白拿家长角色。
const RESERVED_SCOPE_PATTERN = /^(parent|tv|board|phone|home)\./i;

// `<flavor>.<kind>.<设备号16hex>`：所有现网设备自举账号都符合此格式。
const DERIVED_ACCOUNT_PATTERN = /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[0-9a-fA-F]{16}$/;
const DEFAULT_PASSWORD_MD5 = crypto.createHash('md5').update('123456').digest('hex');

function isDerivedAccount(account) {
    return DERIVED_ACCOUNT_PATTERN.test(String(account || ''));
}

/**
 * 校验家长号。
 * @param {string} name 用户输入的家长号
 * @param {{adminUsername?: string, accountExists?: (name:string)=>boolean}} ctx
 * @returns {{ok: boolean, name?: string, reason?: string}}
 */
function validateClaimName(name, ctx) {
    const options = ctx || {};
    const value = String(name == null ? '' : name).trim();
    if (!CLAIM_NAME_PATTERN.test(value)) {
        return { ok: false, reason: '家长号需为 2-64 位字母、数字、下划线、点或连字符' };
    }
    if (value === '.' || value === '..' || value.startsWith('.')) {
        return { ok: false, reason: '家长号不能以点开头' };
    }
    if (RESERVED_SCOPE_PATTERN.test(value)) {
        return { ok: false, reason: '该前缀为设备账号保留，请换一个' };
    }
    if (isDerivedAccount(value)) {
        return { ok: false, reason: '不能使用设备派生账号格式' };
    }
    if (options.adminUsername && value === options.adminUsername) {
        return { ok: false, reason: '该登录名已被管理员占用' };
    }
    if (typeof options.accountExists === 'function' && options.accountExists(value)) {
        return { ok: false, reason: '该家长号已被占用' };
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
 * 把一台机器上的「家长可见性绑定」从派生号视角映射到家长号视角。
 *
 * 只动三处与「哪个家长能看/管这台电视」直接相关的字段：
 * - parents：绑定关系数组（驱动 overview 可见性与 parental_* 事件扇出）；
 * - aliases[账号]：该家长对这台电视的私有别名（跟随家长号）；
 * - parental.ownerAccount：儿童模式配置归属家长（跟随家长号）。
 *
 * 刻意**不动** commAccount / owner / id 等设备身份字段——它们是设备身份证，
 * 派生号实时通道、心跳、遥控投递都要靠 commAccount 保持派生号不变。
 */
function migrateMachineBinding(machine, oldName, newName) {
    if (!machine || typeof machine !== 'object') return machine;
    const next = Object.assign({}, machine);
    if (Array.isArray(next.parents)) {
        const mapped = next.parents.map((item) => (item === oldName ? newName : item));
        next.parents = Array.from(new Set(mapped));
    }
    if (next.aliases && typeof next.aliases === 'object' && !Array.isArray(next.aliases)) {
        next.aliases = renameMapKeys(next.aliases, oldName, newName);
    }
    if (next.parental && typeof next.parental === 'object'
        && next.parental.ownerAccount === oldName) {
        next.parental = Object.assign({}, next.parental, { ownerAccount: newName });
    }
    return next;
}

/**
 * 建立家长号与设备派生号的关联（两层身份并存，派生号永不受损）。
 *
 * 覆盖：
 * 1. 新建家长号账号（role=parent，口令为用户自设摘要）；
 * 2. machines.json 的 parents / 私有别名 / 儿童模式归属，从派生号映射到家长号；
 * 3. 按账号名存储的 outbox / reads / users 私有数据迁到家长号名下（使其上线即可读）。
 *
 * **不再**做的事（这是与旧模型的关键区别）：
 * - 不改派生号口令（保持默认 123456，随时可登录）；
 * - 不把派生号标记为 disabled / 墓碑；
 * - 不动设备 commAccount / owner、题库、事件历史——这些属于设备身份或按设备索引，
 *   家长号拉历史由 realtime.js 的 machineAccountsForParent(家长号) 补拉解决。
 *
 * 因此家长号口令一旦丢失，客户端回落到「派生号 + 123456」仍可登录，不会重装即锁死。
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
        throw new Error('关联参数不完整');
    }
    if (!/^[a-f0-9]{32}$/.test(newPasswordMd5)) {
        throw new Error('家长号口令摘要无效');
    }
    if (newPasswordMd5 === DEFAULT_PASSWORD_MD5) {
        throw new Error('家长号不能沿用设备自举的默认口令，请自设一个更安全的口令');
    }
    const oldPasswordFile = path.join(registerUsersDir, oldName);
    const oldInfoFile = path.join(registerUsersDir, `${oldName}_info.txt`);
    const newPasswordFile = path.join(registerUsersDir, newName);
    const newInfoFile = path.join(registerUsersDir, `${newName}_info.txt`);

    if (!fs.existsSync(oldPasswordFile)) throw new Error('原设备派生账号不存在');
    if (fs.existsSync(newPasswordFile) || fs.existsSync(newInfoFile)) {
        throw new Error('该家长号已被占用');
    }
    const oldInfo = readJson(oldInfoFile, null);
    if (!oldInfo || oldInfo.role !== 'parent') {
        throw new Error('只有家长端设备账号可以设置家长号');
    }
    // 一台设备只允许关联一次家长号（防止误操作把绑定关系反复改写）。
    // 兼容旧数据：claimedAt / claimedTo 是旧模型的迁移标记，parentAccount 是新标记。
    if (oldInfo.parentAccount || oldInfo.claimedAt || oldInfo.claimedTo) {
        throw new Error('该设备已关联过家长号，若要改口令请在设置页操作');
    }

    const adminDir = path.join(datasDir, 'admin');
    const realtimeDir = path.join(datasDir, 'realtime');
    const usersDir = path.join(datasDir, 'users');
    const machinesFile = path.join(adminDir, 'machines.json');
    const eventsFile = path.join(realtimeDir, 'events.jsonl');
    const historyFile = path.join(realtimeDir, 'history.jsonl');

    const stamp = new Date().toISOString().replace(/[:.]/g, '-');
    const backupDir = path.join(adminDir, 'claim-backups', `${stamp}_${oldName.replace(/[^A-Za-z0-9_.-]/g, '_')}`);
    snapshot([
        oldPasswordFile, oldInfoFile, machinesFile, eventsFile, historyFile,
    ], backupDir);

    const changed = [];

    // 1. 新建家长号账号（自设口令摘要）。派生号账号文件原样保留、口令不变、不禁用。
    const newInfo = Object.assign({}, oldInfo, {
        name: newName,
        role: 'parent', // 显式保留：migrateUsers 在 role 缺失时会降级成 user
        claimedAt: new Date().toISOString(),
        claimFrom: oldName,
    });
    delete newInfo.enabled;
    delete newInfo.loginTime;
    delete newInfo.parentAccount;
    fs.writeFileSync(newInfoFile, JSON.stringify(newInfo, null, 2), 'utf8');
    fs.writeFileSync(newPasswordFile, newPasswordMd5, 'utf8');
    changed.push('register/users（新建家长号）');

    // 2. 在派生号 info 上记录正向关联标记（仅标记，不改口令、不设 disabled）。
    oldInfo.parentAccount = newName;
    fs.writeFileSync(oldInfoFile, JSON.stringify(oldInfo, null, 2), 'utf8');

    // 3. machines.json：只映射家长可见性绑定，不动设备身份字段。
    const machines = readJson(machinesFile, {});
    let machinesChanged = 0;
    for (const id of Object.keys(machines)) {
        const next = migrateMachineBinding(machines[id], oldName, newName);
        if (JSON.stringify(next) !== JSON.stringify(machines[id])) machinesChanged++;
        machines[id] = next;
    }
    if (machinesChanged) {
        writeJsonOrThrow(machinesFile, machines);
        changed.push(`machines.json（${machinesChanged} 台的家长绑定）`);
    }

    // 4. 离线队列与已读游标：文件名即账号名，迁到家长号使其上线即可收。
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

    // 5. 按 cookie username 分目录的用户私有数据（剪贴板 / 上传 / 遥控会话）。
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
        changed.push('users/<家长号>/');
    }

    // 说明：events.jsonl / history.jsonl / layouts.json / parental_avatars.json /
    // parental_quizzes.json 刻意不动。设备事件按 commAccount 索引，家长号拉历史由
    // realtime.js 的 machineAccountsForParent(家长号) 补拉；题库按 deviceId 存储；
    // 布局与头像审计字段与家长可见性无关。
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
    migrateMachineBinding,
    readConsumedTickets,
    consumeTicket,
    replaceValues,
    renameMapKeys,
    rewriteJsonl,
};
