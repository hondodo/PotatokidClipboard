// 「智能」场景引擎：手动控制（点一下执行一组动作）+ 自动化（满足触发条件自动执行）。
//
// 数据落 datas/admin/scenes.json，与 ha.json / deviceTypes.json 同级：
// - settings：全局配置（occupiedWindowSec 等）
// - scenes：手动控制与自动化共用一套结构，用 kind 区分
//
// 触发条件组（v3）：trigger = { rules:[ { conditions:[...] }, ... ] }
// - 一条规则 = 一张触发卡片，规则内的条件按 AND 求值；规则之间按 OR 求值。
//   这样既能表达「A 且 B」，也能表达「A 且 B，或者 C」，不再二选一。
// - 条件类型：presence（人体感应虚拟实体）/ button（小屏按键）/ time（定时）
//   / ha_state（HA 实体状态，15 秒可配轮询）/ window（允许触发时间窗）
// - 触发时机不变：条件满足即触发，冷却时间负责防重复；不做边沿、不做状态保持。
// - 旧的 {logic:'and'|'or', conditions:[...]} 和单 trigger 在读配置时迁移为 rules。
// - 人体感应不是真 HA 实体，只是本服务内的虚拟实体 presence.<deviceId>。
// - pending 计时放内存。进程重启最多漏一次触发，比持久化状态机更不容易留脏数据。
//
// 动作执行本身不在这里实现：由 admin.js 注入 runAction，直接复用现有
// callHaService（HA）与 pushRemoteCommand（中控/电视），保证与 ESP 按键行为一致。

const fs = require('fs');
const path = require('path');

const MAX_ACTIONS = 20;
const MAX_NAME_LEN = 40;
const MAX_DELAY_SEC = 600;
const MAX_COOLDOWN_SEC = 3600;
const MAX_HOLD_SEC = 3600;
const ACTION_TIMEOUT_MS = 10 * 1000;
const DEFAULT_HOLD_SEC = 10;
const DEFAULT_COOLDOWN_SEC = 30;
const DEFAULT_OCCUPIED_SEC = 90;
// 设备在线判定窗口：与 admin.js 的 MACHINE_ONLINE_MS（90 秒）保持一致。
// 心跳停了感应数据就冻结在最后一次上报，离线期间的旧电平不能拿来判自动化。
const MACHINE_ONLINE_MS = 90 * 1000;
// 深睡从机休眠宽限：预期唤醒点之后再等 10 分钟没心跳才算真掉线（与 admin 列表一致）。
const SLEEP_GRACE_MS = 10 * 60 * 1000;
const DEFAULT_HA_POLL_SEC = 15;
const MIN_HA_POLL_SEC = 5;
const MAX_HA_POLL_SEC = 60;
// 规则卡片上限，以及每条规则/整条自动化的条件上限。
const MAX_RULES = 8;
const MAX_CONDITIONS_PER_RULE = 8;
const MAX_CONDITIONS_TOTAL = 16;
const SOFT_DELETE_KEEP_MS = 30 * 24 * 60 * 60 * 1000;
// 定时触发的最小判定间隔：一分钟内的多次 tick 只认一次。
const TIME_TICK_MS = 30 * 1000;

const TRIGGER_TYPES = new Set(['presence', 'button', 'time', 'ha_state', 'window']);
const ACTION_TYPES = new Set(['ha', 'remote', 'delay', 'scene']);
// HA 实体状态比较：等于 / 不等于 / 包含 / 大于 / 小于 / 存在
const HA_STATE_OPS = new Set(['eq', 'neq', 'contains', 'gt', 'lt', 'exists']);
// 场景 id 允许的字符集（与 ESP 按键里 sceneId 的校验保持一致）。
const SCENE_ID_RE = /^[A-Za-z0-9_-]{1,40}$/;
// 动作调动作最多套几层：再深就不是「复用」而是把编排写乱了。
const MAX_SCENE_DEPTH = 3;
const WEEKDAYS = new Set([0, 1, 2, 3, 4, 5, 6]);

const DEFAULT_CONFIG = {
    version: 1,
    settings: { occupiedWindowSec: DEFAULT_OCCUPIED_SEC, haPollSec: DEFAULT_HA_POLL_SEC },
    scenes: [],
};

function pad2(value) {
    return String(value).padStart(2, '0');
}

/** 服务器本地时区的 `YYYY-MM-DD HH:MM`，定时触发与日志都按这个口径。 */
function minuteKey(date) {
    const d = date || new Date();
    return `${d.getFullYear()}-${pad2(d.getMonth() + 1)}-${pad2(d.getDate())} ${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
}

function clockKey(date) {
    const d = date || new Date();
    return `${pad2(d.getHours())}:${pad2(d.getMinutes())}`;
}

const HHMM_RE = /^([01]\d|2[0-3]):[0-5]\d$/;

function clampInt(value, min, max, fallback) {
    const n = Number(value);
    if (!Number.isFinite(n)) return fallback;
    return Math.min(max, Math.max(min, Math.round(n)));
}

function safeString(value, max) {
    return String(value == null ? '' : value).trim().slice(0, max);
}

function newSceneId() {
    return `s_${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
}

function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

function withTimeout(promise, ms) {
    let timer = null;
    return Promise.race([
        Promise.resolve(promise),
        new Promise((resolve, reject) => {
            timer = setTimeout(() => reject(new Error(`执行超时（${Math.round(ms / 1000)} 秒）`)), ms);
        }),
    ]).finally(() => { if (timer) clearTimeout(timer); });
}

/**
 * 人体感应归一化：固件只上报 present / 进入 / 离开时间。
 * occupied 是派生值——「最近 N 秒内出现过有人」，用来判断「人还在不在」。
 * HC-SR501 只认移动，人坐着 2 秒后 present 就变 false，所以必须有这一层。
 */
function presenceEntityOf(machine, occupiedWindowSec) {
    const raw = machine && machine.espPresence;
    if (!raw || typeof raw !== 'object') return null;
    // 四态：有人 / 无人 / 休眠 / 离线。
    // 在线判定：最近一次心跳（lastSeen）在 90 秒窗口内（与 admin.js 的 MACHINE_ONLINE_MS 一致）。
    // 深睡从机休眠判定：与 admin 列表（02-machines.js sleepStatus）同一规则——
    // role=slave 且自报了 sleepSec，预期唤醒点（lastSeen + sleepSec）后留 10 分钟宽限，
    // 窗口内算「休眠」而非离线；超过宽限还没心跳才是真的掉线。
    const now = Date.now();
    const lastSeen = Number(machine.lastSeen) || 0;
    const online = lastSeen > 0 && (now - lastSeen) < MACHINE_ONLINE_MS;
    const sleepSec = Number(machine.sleepSec) || 0;
    const expectedWakeAt = lastSeen + sleepSec * 1000;
    const sleeping = !online && machine.role === 'slave' && sleepSec > 0
        && now < expectedWakeAt + SLEEP_GRACE_MS;
    const present = raw.present === true;
    const lastEnterAt = Number(raw.lastEnterAt) || 0;
    const lastLeaveAt = Number(raw.lastLeaveAt) || 0;
    const updatedAt = Number(raw.updatedAt) || 0;
    const windowMs = clampInt(occupiedWindowSec, 10, 3600, DEFAULT_OCCUPIED_SEC) * 1000;
    const idleMs = lastEnterAt ? Math.max(0, now - lastEnterAt) : 0;
    // 设备断电/断网后 espPresence.present 会永远停在最后一次上报值——
    // 真离线（unknown）按「未知」处理：occupied 强制空闲，求值层有人/无人都不触发。
    // 休眠是可预期的离线：深睡从机只在 PIR 跳变 / 定时唤醒时才发心跳，
    // 不能因为「90 秒没心跳」就翻成无人——否则每次上报有人后 1 分半就判无人，
    // 「有人开灯 / 无人关灯」两条自动化会来回抖，表现成灯打不开。
    // 休眠期间以最后一次上报的 present 为准；人离开要等它下次唤醒报 pir=0 才知道。
    const state = online ? (present ? 'present' : 'absent') : (sleeping ? 'sleep' : 'unknown');
    const occupied = state !== 'unknown' && (present || Boolean(lastEnterAt && idleMs <= windowMs));
    return {
        entityId: `presence.${machine.id}`,
        deviceId: machine.id,
        name: machine.name || machine.id,
        online,
        sleeping,
        state,
        presence: state,
        presenceText: { present: '有人', absent: '无人', sleep: '休眠', unknown: '离线' }[state],
        occupied,
        occupiedText: state === 'sleep'
            ? (occupied ? '休眠（保持有人）' : '休眠（按无人判）')
            : (state === 'unknown' ? '离线' : (occupied ? '占用中' : '空闲')),
        lastEnterAt,
        lastLeaveAt,
        updatedAt,
        lastSeen,
        expectedWakeAt: sleeping ? expectedWakeAt : 0,
        idleSec: lastEnterAt ? Math.round(idleMs / 1000) : null,
        // 距离「判空闲」还有多少秒，界面上用来解释为什么还显示占用中。
        occupiedLeftSec: online && occupied && lastEnterAt
            ? Math.max(0, Math.round((windowMs - idleMs) / 1000))
            : 0,
    };
}

/** 单条触发条件的人话描述。 */
function describeCondition(cond, ctx) {
    const deviceName = (id) => (ctx && ctx.deviceName && ctx.deviceName(id)) || id || '设备';
    if (cond.type === 'presence') {
        const hold = Number(cond.holdSec) || 0;
        const stateText = cond.state === 'absent' ? '无人' : '有人';
        return hold > 0 ? `${deviceName(cond.deviceId)} 持续${stateText} ${hold} 秒` : `${deviceName(cond.deviceId)} 检测到${stateText}`;
    }
    if (cond.type === 'button') {
        const slot = cond.slot ? `槽位 ${cond.slot}` : '任意按键';
        return `${deviceName(cond.deviceId)} 按下${slot}`;
    }
    if (cond.type === 'time') return `每天 ${cond.at || '--:--'}`;
    if (cond.type === 'ha_state') {
        const opText = { eq: '=', neq: '≠', contains: '含', gt: '>', lt: '<', exists: '存在' }[cond.op] || '=';
        const field = cond.attr ? `.${cond.attr}` : '';
        const valueText = cond.op === 'exists' ? '' : ` ${opText} ${cond.value}`;
        return `HA ${cond.entityId || '实体'}${field}${valueText}`;
    }
    if (cond.type === 'window') {
        const dayText = (cond.days && cond.days.length)
            ? `${cond.days.map((d) => '日一二三四五六'[d]).join('')} ` : '每天 ';
        return `${dayText}${cond.start || '00:00'}-${cond.end || '24:00'}`;
    }
    return '未知条件';
}

/**
 * 把任意历史形态的 trigger 归一成规则列表（不校验字段，只定结构）：
 * - 新版 { rules:[{ conditions:[...] }] }
 * - 旧条件组 { logic:'and', conditions:[A,B] } → 一条规则 [A,B]
 * - 旧条件组 { logic:'or',  conditions:[A,B] } → 两条规则 [A] / [B]
 * - 更早的单 trigger { type:'presence', ... } → 一条规则一条条件
 * 空规则直接丢弃：读取旧配置时不能因为一条脏数据让整个场景消失。
 */
function ruleListOf(trigger) {
    if (!trigger || typeof trigger !== 'object') return [];
    if (Array.isArray(trigger.rules)) {
        return trigger.rules
            .filter((rule) => rule && typeof rule === 'object' && Array.isArray(rule.conditions) && rule.conditions.length)
            .map((rule) => ({ conditions: rule.conditions }));
    }
    if (Array.isArray(trigger.conditions) && trigger.conditions.length) {
        if (trigger.logic === 'or') return trigger.conditions.map((cond) => ({ conditions: [cond] }));
        return [{ conditions: trigger.conditions }];
    }
    if (trigger.type) return [{ conditions: [trigger] }];
    return [];
}

/** 所有规则里条件的扁平列表。轮询/心跳用它判断「这条自动化关心哪些实体」。 */
function conditionsOf(trigger) {
    const out = [];
    for (const rule of ruleListOf(trigger)) out.push(...rule.conditions);
    return out;
}

/** 触发条件组的人话描述，卡片和日志共用。规则间「或」，规则内「且」。 */
function describeTrigger(trigger, ctx) {
    if (!trigger) return '手动';
    const rules = ruleListOf(trigger);
    if (!rules.length) return '未设置条件';
    return rules.map((rule) => {
        const text = rule.conditions.map((cond) => describeCondition(cond, ctx)).join(' 且 ');
        return rule.conditions.length > 1 ? `(${text})` : text;
    }).join(' 或 ');
}

function describeAction(action, ctx) {
    const label = (ctx && ctx.labelOf) ? ctx.labelOf(action) : '';
    if (label) return label;
    if (action.type === 'delay') return `等待 ${action.seconds} 秒`;
    if (action.type === 'scene') {
        const name = (ctx && ctx.sceneName) ? ctx.sceneName(action.sceneId) : '';
        return name ? `手动控制「${name}」` : `手动控制（${action.sceneId || '未选'}）`;
    }
    if (action.type === 'ha') return `${action.entityId || '实体'} ${action.action || ''}`.trim();
    if (action.type === 'remote') return `${action.target || '设备'} ${action.action || ''}`.trim();
    return '动作';
}

/**
 * 归一化一条触发条件。任何非法字段直接抛错，保存时就让前端看到。
 * 兼容两种输入：新结构 {type,...}；旧的单 trigger 也是同一套字段。
 */
function normalizeCondition(raw, index) {
    const c = raw && typeof raw === 'object' ? raw : {};
    const type = String(c.type || '').trim();
    if (!TRIGGER_TYPES.has(type)) {
        throw new Error(`第 ${index + 1} 条触发条件类型不支持`);
    }
    const cond = { type };
    if (type === 'presence') {
        cond.deviceId = safeString(c.deviceId, 64);
        if (!cond.deviceId) throw new Error(`第 ${index + 1} 条（人体感应）请选择哪台小屏`);
        cond.state = c.state === 'absent' ? 'absent' : 'present';
        cond.holdSec = clampInt(c.holdSec, 0, MAX_HOLD_SEC, DEFAULT_HOLD_SEC);
    } else if (type === 'button') {
        cond.deviceId = safeString(c.deviceId, 64);
        if (!cond.deviceId) throw new Error(`第 ${index + 1} 条（小屏按键）请选择哪台小屏`);
        cond.slot = clampInt(c.slot, 0, 8, 0);
    } else if (type === 'time') {
        cond.at = HHMM_RE.test(String(c.at || '')) ? String(c.at) : '';
        if (!cond.at) throw new Error(`第 ${index + 1} 条（定时）需要填写 HH:MM 时间`);
    } else if (type === 'ha_state') {
        const entityId = safeString(c.entityId, 128);
        // 支持 HA 两段式，以及遥控伪实体三段式 remote.<设备>.<字段>
        if (!/^[a-z_]+\.[a-z0-9_]+(\.[a-z0-9_]+)?$/i.test(entityId)) {
            throw new Error(`第 ${index + 1} 条（实体状态）的实体 ID 格式不对`);
        }
        cond.entityId = entityId;
        cond.attr = safeString(c.attr, 40);
        const op = String(c.op || 'eq').trim();
        if (!HA_STATE_OPS.has(op)) throw new Error(`第 ${index + 1} 条（实体状态）的比较方式不支持`);
        cond.op = op;
        cond.value = safeString(c.value, 80);
        if (op !== 'exists' && !cond.value) throw new Error(`第 ${index + 1} 条（实体状态）需要填写比较值`);
    } else if (type === 'window') {
        const days = Array.isArray(c.days)
            ? c.days.map((d) => Number(d)).filter((d) => WEEKDAYS.has(d)).slice(0, 7)
            : [];
        cond.days = days;
        cond.start = HHMM_RE.test(String(c.start || '')) ? String(c.start) : '';
        cond.end = HHMM_RE.test(String(c.end || '')) ? String(c.end) : '';
    }
    return cond;
}

/**
 * 触发条件组归一化：新版 rules 结构落库；旧的单 trigger / 单条件组按
 * ruleListOf 的口径迁移（AND 组一条规则，OR 组一条条件一条规则）。
 */
function normalizeTrigger(raw) {
    const src = raw && typeof raw === 'object' ? raw : null;
    if (!src) return null;
    let rawRules;
    if (Array.isArray(src.rules)) {
        rawRules = src.rules.map((rule, index) => {
            const conds = rule && Array.isArray(rule.conditions) ? rule.conditions : [];
            if (!conds.length) throw new Error(`第 ${index + 1} 条规则至少需要一条条件`);
            return conds;
        });
    } else {
        rawRules = ruleListOf(src).map((rule) => rule.conditions);
    }
    if (!rawRules.length) throw new Error('自动化至少需要一条触发条件');
    if (rawRules.length > MAX_RULES) throw new Error(`最多 ${MAX_RULES} 条触发规则`);
    const rules = [];
    let total = 0;
    rawRules.forEach((conds, ruleIndex) => {
        if (conds.length > MAX_CONDITIONS_PER_RULE) {
            throw new Error(`第 ${ruleIndex + 1} 条规则最多 ${MAX_CONDITIONS_PER_RULE} 条条件`);
        }
        total += conds.length;
        if (total > MAX_CONDITIONS_TOTAL) throw new Error(`触发条件总数不能超过 ${MAX_CONDITIONS_TOTAL} 条`);
        rules.push({
            conditions: conds.map((item, index) => normalizeCondition(item, total - conds.length + index)),
        });
    });
    return { rules };
}

/**
 * 归一化 + 校验。任何非法字段直接抛错，让前端在保存时就看到问题，
 * 而不是等到执行时才失败（设计文档第七节「动作引用的实体被删」那条）。
 */
function normalizeScene(input, ctx = {}) {
    const src = input && typeof input === 'object' ? input : {};
    const existing = ctx.existing || null;
    const name = safeString(src.name, MAX_NAME_LEN);
    if (!name) throw new Error('场景名称不能为空');

    const kind = src.kind === 'manual' ? 'manual' : 'auto';
    const enabled = src.enabled === undefined
        ? (existing ? existing.enabled !== false : true)
        : src.enabled === true || src.enabled === 'true';

    let trigger = null;
    if (kind === 'auto') {
        trigger = normalizeTrigger(src.trigger);
        if (!trigger) throw new Error('自动化需要至少一条触发条件');
    }

    const rawWindow = src.window && typeof src.window === 'object' ? src.window : {};
    const days = Array.isArray(rawWindow.days)
        ? rawWindow.days.map((d) => Number(d)).filter((d) => WEEKDAYS.has(d)).slice(0, 7)
        : [];
    const window = {
        days,
        start: HHMM_RE.test(String(rawWindow.start || '')) ? String(rawWindow.start) : '',
        end: HHMM_RE.test(String(rawWindow.end || '')) ? String(rawWindow.end) : '',
    };

    const rawActions = Array.isArray(src.actions) ? src.actions : [];
    if (!rawActions.length) throw new Error('至少要有一个动作');
    if (rawActions.length > MAX_ACTIONS) throw new Error(`单个场景最多 ${MAX_ACTIONS} 个动作`);
    const actions = rawActions.map((item, index) => {
        const a = item && typeof item === 'object' ? item : {};
        const type = String(a.type || '').trim();
        if (!ACTION_TYPES.has(type)) throw new Error(`第 ${index + 1} 个动作类型不支持`);
        const onError = a.onError === 'continue' ? 'continue' : 'stop';
        if (type === 'delay') {
            const seconds = clampInt(a.seconds, 1, MAX_DELAY_SEC, 0);
            if (!seconds) throw new Error(`第 ${index + 1} 个动作（等待）需要 1–${MAX_DELAY_SEC} 秒`);
            return { type, seconds, onError };
        }
        if (type === 'scene') {
            const sceneId = safeString(a.sceneId, 40);
            if (!SCENE_ID_RE.test(sceneId)) throw new Error(`第 ${index + 1} 个动作没选手动控制`);
            if (existing && sceneId === existing.id) throw new Error(`第 ${index + 1} 个动作不能引用自己`);
            // 只校验「引用的不是自动化」；目标被删了不阻断保存 —— 否则别的字段也改不动了，
            // 运行时由执行器报错（与 ESP 按键的取舍一致）。
            if (typeof ctx.checkScene === 'function') ctx.checkScene(sceneId, index + 1);
            return { type, sceneId, onError };
        }
        if (type === 'ha') {
            const entityId = safeString(a.entityId, 128);
            const action = safeString(a.action, 40);
            if (!/^[a-z_]+\.[a-z0-9_]+$/i.test(entityId)) throw new Error(`第 ${index + 1} 个动作的实体 ID 格式不对`);
            if (!action) throw new Error(`第 ${index + 1} 个动作没选 HA 动作`);
            return { type, entityId, action, param: safeString(a.param, 32), label: safeString(a.label, 60), onError };
        }
        const target = safeString(a.target, 64);
        const action = safeString(a.action, 40);
        if (!target) throw new Error(`第 ${index + 1} 个动作没选中控或电视`);
        if (!action) throw new Error(`第 ${index + 1} 个动作没选遥控命令`);
        if (typeof ctx.checkRemote === 'function') ctx.checkRemote(target, action, index + 1);
        return { type, target, action, param: safeString(a.param, 32), label: safeString(a.label, 60), onError };
    });

    const now = Date.now();
    return {
        id: existing ? existing.id : safeString(src.id, 40) || newSceneId(),
        name,
        kind,
        enabled,
        trigger,
        window,
        actions,
        cooldownSec: clampInt(src.cooldownSec, 0, MAX_COOLDOWN_SEC, DEFAULT_COOLDOWN_SEC),
        lastRunAt: existing ? existing.lastRunAt || 0 : 0,
        lastResult: existing ? existing.lastResult || '' : '',
        lastError: existing ? existing.lastError || '' : '',
        runCount: existing ? existing.runCount || 0 : 0,
        createdAt: existing ? existing.createdAt || now : now,
        updatedAt: now,
        deletedAt: 0,
    };
}

function attachScenes(options = {}) {
    const file = options.file;
    if (!file) throw new Error('attachScenes 需要 file 参数');
    // 动作执行器由 admin.js 注入：直接复用 callHaService / pushRemoteCommand，
    // 避免另写一套与 ESP 按键不一致的调用逻辑。
    const runAction = typeof options.runAction === 'function' ? options.runAction : null;
    // 感应实体来源：() => [{ id, name, espPresence }]
    const listMachines = typeof options.listMachines === 'function' ? options.listMachines : () => [];
    const log = typeof options.log === 'function' ? options.log : () => {};
    const labelOf = typeof options.labelOf === 'function' ? options.labelOf : () => '';
    const checkRemote = typeof options.checkRemote === 'function' ? options.checkRemote : null;
    // HA 实体状态轮询：注入 () => Promise<{ [entityId]: { state, attributes } }>。
    // 直接复用 admin.js 里 haCatalogService.getStates，不另起一套 HA 客户端。
    const getStates = typeof options.getStates === 'function' ? options.getStates : null;
    // 遥控伪实体状态读取：注入 (entityId) => string，返回该实体当前状态文本。
    // 与「插入实体」弹窗里的遥控状态同源（remoteStateFields）。
    const readRemoteState = typeof options.readRemoteState === 'function' ? options.readRemoteState : () => '';

    /** @type {Map<string, {at:number, matcher:object}>} 等待 holdSec 到期的场景 */
    const pending = new Map();
    /** @type {Set<string>} 正在执行的场景（同场景串行，重入直接丢弃） */
    const running = new Set();
    /** @type {Map<string,string>} 定时触发「本分钟已执行过」的标记 */
    const lastTimeKey = new Map();
    /** @type {Map<string,string>} ha_state 条件上一次读到的状态文本，仅用于描述/排障 */
    const haStateText = new Map();
    let lastTimeCheck = 0;
    let lastHaPoll = 0;
    const stats = { triggered: 0, cancelled: 0, skipped: 0, failed: 0 };

    function readConfig() {
        let raw = null;
        try {
            if (fs.existsSync(file)) raw = JSON.parse(fs.readFileSync(file, 'utf8'));
        } catch (error) {
            console.error(`[scenes] 读取 ${file} 失败:`, error.message);
        }
        if (!raw || typeof raw !== 'object') return { ...DEFAULT_CONFIG, scenes: [] };
        return {
            version: 1,
            settings: {
                occupiedWindowSec: clampInt(
                    raw.settings && raw.settings.occupiedWindowSec,
                    10, 3600, DEFAULT_OCCUPIED_SEC,
                ),
                haPollSec: clampInt(
                    raw.settings && raw.settings.haPollSec,
                    MIN_HA_POLL_SEC, MAX_HA_POLL_SEC, DEFAULT_HA_POLL_SEC,
                ),
            },
            // 旧的单 trigger / 单条件组在读取时迁移成规则卡片结构（不写回磁盘，
            // 保存时才落库）。保证列表描述、引擎求值、前端编辑三处结构一致。
            scenes: Array.isArray(raw.scenes)
                ? raw.scenes.filter((s) => s && typeof s === 'object').map((s) => {
                    if (s.kind !== 'auto' || !s.trigger || s.trigger.rules) return s;
                    const rules = ruleListOf(s.trigger);
                    if (!rules.length) return s;
                    return { ...s, trigger: { rules } };
                })
                : [],
        };
    }

    /** 原子写：先写 tmp 再 rename，进程中断不会留下半个 JSON。 */
    function writeConfig(config) {
        fs.mkdirSync(path.dirname(file), { recursive: true });
        const tmp = `${file}.tmp`;
        fs.writeFileSync(tmp, JSON.stringify(config, null, 2), 'utf8');
        fs.renameSync(tmp, file);
    }

    /** 软删记录超过 30 天就清掉，避免文件无限增长。 */
    function prune(config) {
        const cutoff = Date.now() - SOFT_DELETE_KEEP_MS;
        config.scenes = config.scenes.filter((s) => !s.deletedAt || Number(s.deletedAt) > cutoff);
        return config;
    }

    function activeScenes() {
        return readConfig().scenes.filter((s) => !s.deletedAt);
    }

    function findScene(id) {
        return activeScenes().find((s) => s.id === id) || null;
    }

    function scenesFor(kind) {
        return activeScenes().filter((s) => (kind ? s.kind === kind : true));
    }

    function settings() {
        return readConfig().settings;
    }

    function setSettings(patch) {
        const config = readConfig();
        if (patch && patch.occupiedWindowSec !== undefined) {
            config.settings.occupiedWindowSec = clampInt(patch.occupiedWindowSec, 10, 3600, DEFAULT_OCCUPIED_SEC);
        }
        if (patch && patch.haPollSec !== undefined) {
            config.settings.haPollSec = clampInt(patch.haPollSec, MIN_HA_POLL_SEC, MAX_HA_POLL_SEC, DEFAULT_HA_POLL_SEC);
            lastHaPoll = 0; // 改了间隔立即重取一次，不用等旧周期
        }
        writeConfig(prune(config));
        return config.settings;
    }

    /** 保存期校验动作里引用的手动控制：不能指向自动化。目标不存在时不阻断（运行时报）。 */
    function checkSceneRef(sceneId, index) {
        const target = findScene(sceneId);
        if (!target) return;
        if (target.kind !== 'manual') {
            throw new Error(`第 ${index} 个动作只能引用手动控制，「${target.name}」是自动化`);
        }
    }

    function ctxOf() {
        return { labelOf, checkRemote, checkScene: checkSceneRef };
    }

    /**
     * 保存前拦环：A 的动作里有 B、B 的动作里又有 A，执行时只会打转。
     * 运行时也有 chain 兜底，但那时用户看到的是「执行失败」，不如保存时就说清。
     */
    function assertNoCycle(scene, config) {
        const byId = new Map();
        for (const item of config.scenes) if (!item.deletedAt) byId.set(item.id, item);
        byId.set(scene.id, scene);
        const seen = new Set([scene.id]);
        const walk = (id, path) => {
            const node = byId.get(id);
            if (!node) return null;
            for (const action of node.actions) {
                if (!action || action.type !== 'scene') continue;
                if (action.sceneId === scene.id) return [...path, id, scene.id];
                if (seen.has(action.sceneId)) continue;
                seen.add(action.sceneId);
                const hit = walk(action.sceneId, [...path, id]);
                if (hit) return hit;
            }
            return null;
        };
        const cycle = walk(scene.id, []);
        if (cycle) {
            const names = cycle.map((id) => (byId.get(id) || {}).name || id);
            throw new Error(`动作会形成循环引用：${names.join(' → ')}`);
        }
    }

    function create(input) {
        const scene = normalizeScene(input, ctxOf());
        const config = readConfig();
        assertNoCycle(scene, config);
        config.scenes.push(scene);
        writeConfig(prune(config));
        log(`新建${scene.kind === 'manual' ? '手动控制' : '自动化'}「${scene.name}」`);
        return scene;
    }

    function update(id, patch) {
        const config = readConfig();
        const index = config.scenes.findIndex((s) => s.id === id && !s.deletedAt);
        if (index < 0) throw new Error('场景不存在或已删除');
        const existing = config.scenes[index];
        const merged = normalizeScene({ ...existing, ...patch }, { ...ctxOf(), existing });
        // kind 不允许从自动化改成手动（触发器会残留），要改就删了重建。
        merged.kind = existing.kind;
        assertNoCycle(merged, config);
        config.scenes[index] = merged;
        writeConfig(prune(config));
        log(`更新「${merged.name}」`);
        return merged;
    }

    function remove(id) {
        const config = readConfig();
        const scene = config.scenes.find((s) => s.id === id && !s.deletedAt);
        if (!scene) throw new Error('场景不存在或已删除');
        scene.deletedAt = Date.now();
        pending.delete(id);
        writeConfig(prune(config));
        log(`删除「${scene.name}」`);
        return { id };
    }

    function setEnabled(id, enabled) {
        const config = readConfig();
        const scene = config.scenes.find((s) => s.id === id && !s.deletedAt);
        if (!scene) throw new Error('场景不存在或已删除');
        scene.enabled = enabled === true || enabled === 'true';
        scene.updatedAt = Date.now();
        if (!scene.enabled) pending.delete(id);
        writeConfig(prune(config));
        return { id, enabled: scene.enabled };
    }

    function writeResult(id, result) {
        const config = readConfig();
        const scene = config.scenes.find((s) => s.id === id);
        if (!scene) return;
        scene.lastRunAt = Date.now();
        scene.lastResult = result.result;
        scene.lastError = result.error || '';
        scene.runCount = (Number(scene.runCount) || 0) + 1;
        writeConfig(prune(config));
    }

    /**
     * 按顺序执行动作。手动执行（force）忽略 enabled 与冷却，但仍防重入；
     * 自动触发受 enabled / 冷却 / 时间窗约束。
     */
    async function run(id, { reason = 'manual', force = false, chain = [], ignoreCooldown = false } = {}) {
        if (chain.includes(id)) throw new Error('循环引用：手动控制之间互相调用');
        if (chain.length >= MAX_SCENE_DEPTH) {
            throw new Error(`动作嵌套超过 ${MAX_SCENE_DEPTH} 层，请把中间那层拆开`);
        }
        const scene = findScene(id);
        if (!scene) throw new Error('场景不存在或已删除');
        if (running.has(id)) {
            stats.skipped += 1;
            return { ok: false, skipped: true, reason: '上一次执行还没结束', steps: [] };
        }
        if (!force) {
            if (!scene.enabled) {
                stats.skipped += 1;
                return { ok: false, skipped: true, reason: '场景已关闭', steps: [] };
            }
            const cooldownMs = Math.max(0, Number(scene.cooldownSec) || 0) * 1000;
            // 被别的场景当动作调用时忽略冷却：冷却的意义是防外部重复触发，
            // 而不是让「点一次自动化」因为中间那条手动控制刚被执行过就半途失败。
            if (!ignoreCooldown && cooldownMs && Date.now() - (Number(scene.lastRunAt) || 0) < cooldownMs) {
                stats.skipped += 1;
                return { ok: false, skipped: true, reason: '冷却中', steps: [] };
            }
        }
        if (!runAction) throw new Error('动作执行器未就绪');

        running.add(id);
        const steps = [];
        let firstError = '';
        let interrupted = false;
        const startedAt = Date.now();
        try {
            for (let i = 0; i < scene.actions.length; i += 1) {
                const action = scene.actions[i];
                const label = describeAction(action, { labelOf });
                const t0 = Date.now();
                if (action.type === 'delay') {
                    const total = Math.min(MAX_DELAY_SEC, Math.max(1, Number(action.seconds) || 1)) * 1000;
                    const until = Date.now() + total;
                    // 分片等待：期间场景被停用或删除就中断后续动作，避免「关掉了还在跑」。
                    while (Date.now() < until) {
                        await sleep(Math.min(500, until - Date.now()));
                        const fresh = findScene(id);
                        if (!fresh || (!force && !fresh.enabled)) { interrupted = true; break; }
                    }
                    if (interrupted) {
                        steps.push({ i: i + 1, type: 'delay', label, status: 'cancelled', ms: Date.now() - t0 });
                        break;
                    }
                    steps.push({ i: i + 1, type: 'delay', label, status: 'ok', ms: Date.now() - t0 });
                    continue;
                }
                if (action.type === 'scene') {
                    // 嵌套执行：不走 runAction（那是单一 HA/遥控动作的执行器），
                    // 直接调自身 run，让它自己的冷却记录、执行结果、日志都照常更新。
                    try {
                        const nested = await run(action.sceneId, {
                            reason: 'nested',
                            chain: [...chain, id],
                            ignoreCooldown: true,
                        });
                        if (!nested.ok) {
                            throw new Error(nested.reason || nested.error || '被调用的手动控制没有执行成功');
                        }
                        steps.push({ i: i + 1, type: 'scene', label, status: 'ok', ms: Date.now() - t0 });
                    } catch (error) {
                        if (!firstError) firstError = `${label}：${error.message}`;
                        steps.push({
                            i: i + 1, type: 'scene', label, status: 'failed',
                            error: error.message, ms: Date.now() - t0,
                        });
                        if (action.onError !== 'continue') break;
                    }
                    continue;
                }
                try {
                    await withTimeout(runAction(action, { scene, reason }), ACTION_TIMEOUT_MS);
                    steps.push({ i: i + 1, type: action.type, label, status: 'ok', ms: Date.now() - t0 });
                } catch (error) {
                    if (!firstError) firstError = `${label}：${error.message}`;
                    steps.push({
                        i: i + 1, type: action.type, label, status: 'failed',
                        error: error.message, ms: Date.now() - t0,
                    });
                    if (action.onError !== 'continue') break;
                }
            }
        } finally {
            running.delete(id);
        }

        const okCount = steps.filter((s) => s.status === 'ok').length;
        const failCount = steps.filter((s) => s.status === 'failed').length;
        const result = failCount === 0
            ? (interrupted ? 'cancelled' : 'ok')
            : (okCount > 0 ? 'partial' : 'failed');
        if (failCount) stats.failed += 1;
        writeResult(id, { result, error: firstError });
        log(`执行「${scene.name}」${result}${failCount ? `（${firstError}）` : ''} 用时 ${Date.now() - startedAt}ms`);
        return {
            ok: failCount === 0,
            sceneId: id,
            sceneName: scene.name,
            result,
            steps,
            error: firstError,
        };
    }

    /** 当前该设备的感应实体，没有上报过则返回 null。 */
    function presenceOf(deviceId) {
        const windowSec = settings().occupiedWindowSec;
        const machine = listMachines().find((item) => item.id === deviceId);
        if (!machine) return null;
        return presenceEntityOf(machine, windowSec);
    }

    function presenceEntities() {
        const windowSec = settings().occupiedWindowSec;
        return listMachines()
            .map((machine) => presenceEntityOf(machine, windowSec))
            .filter(Boolean);
    }

    /** 时间窗：days 空 = 每天；start/end 空 = 全天；跨零点区间自动识别。 */
    function inWindow(win) {
        if (!win) return true;
        const now = new Date();
        const days = Array.isArray(win.days) ? win.days : [];
        if (days.length && !days.includes(now.getDay())) return false;
        if (!win.start || !win.end) return true;
        const current = clockKey(now);
        if (win.start <= win.end) return current >= win.start && current <= win.end;
        // 跨零点：22:00-02:00
        return current >= win.start || current <= win.end;
    }

    /**
     * 单条条件求值。返回 true / false。
     * 事件型条件（button）只在事件路径里为 true；周期 tick 里恒 false，
     * 避免「按键按下过一次」导致后续每次轮询都重复触发。
     */
    function evalCondition(cond, now, ctx) {
        if (!cond || !cond.type) return false;
        if (cond.type === 'presence') {
            const entity = presenceOf(cond.deviceId);
            if (!entity) return false;
            // 真离线（心跳超时且不是休眠中的从机）：感应状态已冻结，按未知处理，
            // 有人/无人都不触发。否则断电的设备会拿最后一次上报的「有人」反复点火。
            if (entity.presence === 'unknown') return false;
            // 休眠中的从机沿用最后一次上报的状态（不算无人），
            // 人来了 PIR 会唤醒设备立刻上报有人，人走了要等下次唤醒报无人。
            // 用 occupied 窗口判定（有人，或最近 N 秒内出现过有人）：
            // PIR 电平两秒就掉，用瞬时电平会让 AND 组合反复失效。
            const occupied = entity.occupied === true;
            return cond.state === 'absent' ? !occupied : occupied;
        }
        if (cond.type === 'button') {
            return !!(ctx && ctx.kind === 'button'
                && ctx.deviceId === cond.deviceId
                && (!cond.slot || cond.slot === ctx.slot));
        }
        if (cond.type === 'time') return clockKey(new Date(now)) === cond.at;
        if (cond.type === 'window') return inWindow(cond);
        if (cond.type === 'ha_state') {
            // 缓存 key 带属性：同一实体可同时比 state 和某个 attribute，互不干扰。
            const cacheKey = cond.attr ? `${cond.entityId}|${cond.attr}` : cond.entityId;
            const text = haStateText.has(cacheKey) ? haStateText.get(cacheKey) : '';
            if (cond.op === 'exists') return text !== '' && text !== undefined && text !== null;
            const value = String(cond.value == null ? '' : cond.value);
            if (cond.op === 'eq') return text === value;
            if (cond.op === 'neq') return text !== value;
            if (cond.op === 'contains') return String(text).indexOf(value) >= 0;
            const a = parseFloat(text);
            const b = parseFloat(value);
            if (!Number.isFinite(a) || !Number.isFinite(b)) return false;
            if (cond.op === 'gt') return a > b;
            if (cond.op === 'lt') return a < b;
            return false;
        }
        return false;
    }

    /** 规则内 AND、规则间 OR。旧 scene.window 作为额外的全局闸门（兼容旧配置）。 */
    function conditionsMet(scene, now, ctx) {
        if (!scene.trigger) return false;
        if (!inWindow(scene.window)) return false; // 旧字段：独立于规则的总时间窗
        const rules = ruleListOf(scene.trigger);
        if (!rules.length) return false;
        return rules.some((rule) => rule.conditions.every((cond) => evalCondition(cond, now, ctx)));
    }

    /** 满足条件就触发。重复触发由 run() 里的冷却时间拦，不在求值层做边沿判断。 */
    function fireIfMatch(scene, reason, now, ctx) {
        if (scene.kind !== 'auto' || !scene.enabled) return false;
        if (!conditionsMet(scene, now || Date.now(), ctx)) return false;
        trigger(scene, reason);
        return true;
    }

    /** 条件里引用到的 HA 实体；遥控伪实体（remote.*）单独走注入的状态读取。 */
    function haIdsFrom(scenes) {
        const haIds = new Set();
        for (const scene of scenes) {
            for (const cond of conditionsOf(scene.trigger)) {
                if (cond.type === 'ha_state' && cond.entityId && !cond.entityId.startsWith('remote.')) {
                    haIds.add(cond.entityId);
                }
            }
        }
        return [...haIds];
    }

    /** 轮询 HA + 遥控状态，更新状态文本缓存；失败保留旧值，不影响其它条件。 */
    async function pollHaStates(now) {
        if (!getStates) return;
        const scenes = activeScenes().filter((s) => s.kind === 'auto' && s.enabled && s.trigger);
        const ids = haIdsFrom(scenes);
        // entityId → attr（同一实体被多条条件引用、各自比不同属性时，取第一条非空 attr）
        const attrById = new Map();
        // 遥控伪实体：直接从注入的读取器取当前文本。
        for (const scene of scenes) {
            for (const cond of conditionsOf(scene.trigger)) {
                if (cond.type !== 'ha_state' || !cond.entityId) continue;
                if (cond.entityId.startsWith('remote.')) {
                    const text = readRemoteState(cond.entityId);
                    haStateText.set(cond.attr ? `${cond.entityId}|${cond.attr}` : cond.entityId,
                        text == null ? '' : String(text));
                } else if (cond.attr) {
                    if (!attrById.has(cond.entityId)) attrById.set(cond.entityId, new Set());
                    attrById.get(cond.entityId).add(cond.attr);
                }
            }
        }
        if (!ids.length) return;
        try {
            const states = await getStates(ids);
            for (const id of ids) {
                const entity = states && states[id];
                if (!entity) continue;
                const baseText = entity.state == null ? '' : String(entity.state);
                haStateText.set(id, baseText);
                // 同一实体的每个属性各存一份，条件里按 entityId|attr 精确取值。
                for (const attr of (attrById.get(id) || [])) {
                    const value = (entity.attributes || {})[attr];
                    haStateText.set(`${id}|${attr}`, value == null ? '' : String(value));
                }
            }
        } catch (error) {
            log(`读 HA 实体状态失败（保留上次值）: ${error.message}`);
        }
    }

    /**
     * 人体感应跳变。固件在 0/1 变化时立刻发心跳（不受 60 秒心跳影响），
     * 所以这里天然是秒级的；holdSec 只是防「人走过走廊」的误触发。
     */
    function onPresence(event) {
        const deviceId = event && event.deviceId;
        if (!deviceId) return;
        const present = event.present === true;
        const autoScenes = activeScenes().filter((s) => s.kind === 'auto' && s.enabled && s.trigger);
        for (const scene of autoScenes) {
            // pending 是场景级的：多条规则里任一 presence 条件命中就先记下来，
            // holdSec 到点后由 fireIfMatch 按完整的「规则内 AND / 规则间 OR」重算。
            const hits = conditionsOf(scene.trigger).filter((c) => c.type === 'presence'
                && c.deviceId === deviceId && (c.state !== 'absent') === present);
            if (!hits.length) {
                if (pending.delete(scene.id)) {
                    stats.cancelled += 1;
                    log(`撤销「${scene.name}」的触发（${present ? '有人' : '无人'}未保持住）`);
                }
                continue;
            }
            if (pending.has(scene.id)) continue;
            const holdSec = Math.max(0, ...hits.map((c) => Number(c.holdSec) || 0));
            if (holdSec === 0) { fireIfMatch(scene, 'presence', Date.now(), { kind: 'presence', deviceId }); continue; }
            pending.set(scene.id, { at: Date.now(), matcher: { kind: 'presence', deviceId, want: present } });
        }
    }

    /** 小屏物理按键。按键动作本身由 esp/press 执行完，这里只做联动。 */
    function onButton(event) {
        const deviceId = event && event.deviceId;
        if (!deviceId) return;
        const slot = Number(event.slot) || 0;
        const ctx = { kind: 'button', deviceId, slot };
        for (const scene of activeScenes()) {
            if (scene.kind !== 'auto' || !scene.enabled) continue;
            fireIfMatch(scene, 'button', Date.now(), ctx);
        }
    }

    function trigger(scene, reason) {
        stats.triggered += 1;
        run(scene.id, { reason }).catch((error) => {
            console.error(`[scenes] 触发「${scene.name}」失败:`, error.message);
        });
    }

    /**
     * 心跳驱动：1 秒一次（由 admin.js 的 setInterval 调）。
     * - 推进 presence 的 holdSec 计时
     * - 每 30 秒做一次定时（time）判定
     * - 每 haPollSec（默认 15，可配）轮询一次 HA / 遥控实体状态并判定
     */
    function tick(now = Date.now()) {
        if (pending.size) {
            for (const [sceneId, item] of pending) {
                const scene = findScene(sceneId);
                if (!scene || !scene.enabled) { pending.delete(sceneId); continue; }
                const holdSec = Math.max(0, ...conditionsOf(scene.trigger)
                    .filter((c) => c.type === 'presence' && c.deviceId === item.matcher.deviceId)
                    .map((c) => Number(c.holdSec) || 0));
                if (now - item.at < holdSec * 1000) continue;
                // 到点前再确认一次状态仍满足：中途走了就不执行。
                if (item.matcher.kind === 'presence') {
                    const entity = presenceOf(item.matcher.deviceId);
                    const stillOn = entity && entity.occupied === true;
                    if (Boolean(stillOn) !== item.matcher.want) {
                        pending.delete(sceneId);
                        stats.cancelled += 1;
                        log(`撤销「${scene.name}」的触发（状态已变化）`);
                        continue;
                    }
                }
                pending.delete(sceneId);
                fireIfMatch(scene, 'presence', now, { kind: 'presence', deviceId: item.matcher.deviceId });
            }
        }

        // HA / 遥控状态轮询：独立节流（haPollSec），不能落在 time 的 30 秒节流后面，
        // 否则配 15 秒实际会变成 30 秒。
        const pollMs = Math.max(MIN_HA_POLL_SEC, Number(settings().haPollSec) || DEFAULT_HA_POLL_SEC) * 1000;
        if (getStates && now - lastHaPoll >= pollMs) {
            lastHaPoll = now;
            const stateScenes = activeScenes().filter((s) => {
                if (s.kind !== 'auto' || !s.enabled || !s.trigger) return false;
                return conditionsOf(s.trigger).some((c) => c.type === 'ha_state'
                    || c.type === 'window' || c.type === 'presence');
            });
            if (stateScenes.length) {
                pollHaStates(now).then(() => {
                    // 轮询完成后按当前状态再判一次：AND 组合里 presence/窗口/实体状态
                    // 都是持续型条件，靠冷却时间防止重复执行。
                    for (const scene of activeScenes()) {
                        if (scene.kind !== 'auto' || !scene.enabled || !scene.trigger) continue;
                        if (!conditionsOf(scene.trigger).some((c) => c.type === 'ha_state'
                            || c.type === 'window' || c.type === 'presence')) continue;
                        fireIfMatch(scene, 'state', Date.now(), null);
                    }
                }).catch((error) => console.error('[scenes] 状态轮询失败:', error.message));
            }
        }

        if (now - lastTimeCheck < TIME_TICK_MS) return;
        lastTimeCheck = now;
        if (!listMachines().length && !getStates) return; // 还没有设备/状态源时不用白跑
        const key = minuteKey(new Date(now));
        const current = clockKey(new Date(now));
        for (const scene of activeScenes()) {
            if (scene.kind !== 'auto' || !scene.enabled || !scene.trigger) continue;
            if (!conditionsOf(scene.trigger).some((c) => c.type === 'time' && c.at === current)) continue;
            if (lastTimeKey.get(scene.id) === key) continue;
            if (fireIfMatch(scene, 'time', now, null)) lastTimeKey.set(scene.id, key);
        }
    }

    /** 供前端渲染：把内部结构翻译成人话，前端不再自己拼字符串。 */
    function decorate(scene) {
        const machineName = (deviceId) => {
            const machine = listMachines().find((item) => item.id === deviceId);
            return machine ? (machine.name || machine.id) : '';
        };
        const sceneName = (sceneId) => {
            const target = findScene(sceneId);
            return target ? target.name : '';
        };
        return {
            ...scene,
            triggerText: scene.kind === 'manual'
                ? '点一下执行'
                : describeTrigger(scene.trigger, { deviceName: machineName }),
            actionTexts: scene.actions.map((action) => describeAction(action, { labelOf, sceneName })),
        };
    }

    function list() {
        return activeScenes()
            .map(decorate)
            .sort((a, b) => (a.kind === b.kind
                ? (b.lastRunAt || 0) - (a.lastRunAt || 0) || a.name.localeCompare(b.name)
                : (a.kind === 'manual' ? -1 : 1)));
    }

    // 启动时把上次崩溃遗留的「执行中」状态清掉：内存里本来就没有，这里只是日志提示。
    return {
        list,
        create,
        update,
        remove,
        setEnabled,
        run,
        tick,
        onPresence,
        onButton,
        presenceOf,
        presenceEntities,
        settings,
        setSettings,
        findScene,
        stats,
        inWindow,
    };
}

module.exports = {
    attachScenes,
    presenceEntityOf,
    normalizeScene,
    normalizeTrigger,
    ruleListOf,
    conditionsOf,
    describeTrigger,
    describeAction,
    DEFAULT_OCCUPIED_SEC,
};
