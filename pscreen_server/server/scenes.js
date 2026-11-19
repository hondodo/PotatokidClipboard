// 「智能」场景引擎：手动控制（点一下执行一组动作）+ 自动化（满足触发条件自动执行）。
//
// 数据落 datas/admin/scenes.json，与 ha.json / deviceTypes.json 同级：
// - settings：全局配置（occupiedWindowSec 等）
// - scenes：手动控制与自动化共用一套结构，用 kind 区分
//
// 刻意不做的三件事（对应设计文档 docs/esp-smart-tab-design.md）：
// 1. 不支持 HA 实体状态触发。服务端只有 HA REST，没有常驻 WS/MQTT，
//    做不到秒级订阅；二期用 15 秒轮询补齐，届时加 trigger.type='ha_state'。
// 2. 人体感应不是真 HA 实体，只是本服务内的虚拟实体 presence.<deviceId>。
// 3. pending 计时放内存。进程重启最多漏一次触发，比持久化状态机更不容易留脏数据。
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
const SOFT_DELETE_KEEP_MS = 30 * 24 * 60 * 60 * 1000;
// 定时触发的最小判定间隔：一分钟内的多次 tick 只认一次。
const TIME_TICK_MS = 30 * 1000;

const TRIGGER_TYPES = new Set(['presence', 'button', 'time']);
const ACTION_TYPES = new Set(['ha', 'remote', 'delay']);
const WEEKDAYS = new Set([0, 1, 2, 3, 4, 5, 6]);

const DEFAULT_CONFIG = {
    version: 1,
    settings: { occupiedWindowSec: DEFAULT_OCCUPIED_SEC },
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
    const present = raw.present === true;
    const lastEnterAt = Number(raw.lastEnterAt) || 0;
    const lastLeaveAt = Number(raw.lastLeaveAt) || 0;
    const updatedAt = Number(raw.updatedAt) || 0;
    const windowMs = clampInt(occupiedWindowSec, 10, 3600, DEFAULT_OCCUPIED_SEC) * 1000;
    const idleMs = lastEnterAt ? Math.max(0, Date.now() - lastEnterAt) : 0;
    const occupied = present || Boolean(lastEnterAt && idleMs <= windowMs);
    return {
        entityId: `presence.${machine.id}`,
        deviceId: machine.id,
        name: machine.name || machine.id,
        presence: present ? 'present' : 'absent',
        presenceText: present ? '有人' : '无人',
        occupied,
        occupiedText: occupied ? '占用中' : '空闲',
        lastEnterAt,
        lastLeaveAt,
        updatedAt,
        idleSec: lastEnterAt ? Math.round(idleMs / 1000) : null,
        // 距离「判空闲」还有多少秒，界面上用来解释为什么还显示占用中。
        occupiedLeftSec: occupied && lastEnterAt
            ? Math.max(0, Math.round((windowMs - idleMs) / 1000))
            : 0,
    };
}

/** 触发条件的人话描述，卡片和日志共用。 */
function describeTrigger(trigger, ctx) {
    if (!trigger) return '手动';
    const deviceName = (ctx && ctx.deviceName && ctx.deviceName(trigger.deviceId)) || trigger.deviceId || '设备';
    if (trigger.type === 'presence') {
        const hold = Number(trigger.holdSec) || 0;
        const stateText = trigger.state === 'absent' ? '无人' : '有人';
        return hold > 0 ? `${deviceName} 持续${stateText} ${hold} 秒` : `${deviceName} 检测到${stateText}`;
    }
    if (trigger.type === 'button') {
        const slot = trigger.slot ? `槽位 ${trigger.slot}` : '任意按键';
        return `${deviceName} 按下${slot}`;
    }
    if (trigger.type === 'time') return `每天 ${trigger.at || '--:--'}`;
    return '未知触发';
}

function describeAction(action, ctx) {
    const label = (ctx && ctx.labelOf) ? ctx.labelOf(action) : '';
    if (label) return label;
    if (action.type === 'delay') return `等待 ${action.seconds} 秒`;
    if (action.type === 'ha') return `${action.entityId || '实体'} ${action.action || ''}`.trim();
    if (action.type === 'remote') return `${action.target || '设备'} ${action.action || ''}`.trim();
    return '动作';
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
        const raw = src.trigger && typeof src.trigger === 'object' ? src.trigger : {};
        const type = String(raw.type || '').trim();
        if (!TRIGGER_TYPES.has(type)) throw new Error('触发类型只能是：人体感应 / 小屏按键 / 定时');
        trigger = {
            type,
            deviceId: safeString(raw.deviceId, 64),
            state: raw.state === 'absent' ? 'absent' : 'present',
            slot: clampInt(raw.slot, 0, 8, 0),
            at: HHMM_RE.test(String(raw.at || '')) ? String(raw.at) : '',
            holdSec: clampInt(raw.holdSec, 0, MAX_HOLD_SEC, type === 'presence' ? DEFAULT_HOLD_SEC : 0),
        };
        if (type === 'presence' && !trigger.deviceId) throw new Error('请选择人体感应来自哪台小屏');
        if (type === 'button' && !trigger.deviceId) throw new Error('请选择按键来自哪台小屏');
        if (type === 'time' && !trigger.at) throw new Error('定时触发需要填写 HH:MM 时间');
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

    /** @type {Map<string, {at:number, matcher:object}>} 等待 holdSec 到期的场景 */
    const pending = new Map();
    /** @type {Set<string>} 正在执行的场景（同场景串行，重入直接丢弃） */
    const running = new Set();
    /** @type {Map<string,string>} 定时触发「本分钟已执行过」的标记 */
    const lastTimeKey = new Map();
    let lastTimeCheck = 0;
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
            },
            scenes: Array.isArray(raw.scenes) ? raw.scenes.filter((s) => s && typeof s === 'object') : [],
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
        writeConfig(prune(config));
        return config.settings;
    }

    function ctxOf() {
        return { labelOf, checkRemote };
    }

    function create(input) {
        const scene = normalizeScene(input, ctxOf());
        const config = readConfig();
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
    async function run(id, { reason = 'manual', force = false } = {}) {
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
            if (cooldownMs && Date.now() - (Number(scene.lastRunAt) || 0) < cooldownMs) {
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

    /**
     * 人体感应跳变。固件在 0/1 变化时立刻发心跳（不受 60 秒心跳影响），
     * 所以这里天然是秒级的；holdSec 只是防「人走过走廊」的误触发。
     */
    function onPresence(event) {
        const deviceId = event && event.deviceId;
        if (!deviceId) return;
        const present = event.present === true;
        const autoScenes = activeScenes().filter((s) => s.kind === 'auto'
            && s.enabled
            && s.trigger
            && s.trigger.type === 'presence'
            && s.trigger.deviceId === deviceId);
        for (const scene of autoScenes) {
            const want = scene.trigger.state !== 'absent';
            if (present !== want) {
                // 状态不再匹配：撤销还没到点的 pending，记一次 cancelled 便于排障。
                if (pending.delete(scene.id)) {
                    stats.cancelled += 1;
                    log(`撤销「${scene.name}」的触发（${present ? '有人' : '无人'}未保持住）`);
                }
                continue;
            }
            if (pending.has(scene.id)) continue;
            const holdSec = Math.max(0, Number(scene.trigger.holdSec) || 0);
            if (holdSec === 0) { trigger(scene, 'presence'); continue; }
            pending.set(scene.id, {
                at: Date.now(),
                matcher: { kind: 'presence', deviceId, want },
            });
        }
    }

    /** 小屏物理按键。按键动作本身由 esp/press 执行完，这里只做联动。 */
    function onButton(event) {
        const deviceId = event && event.deviceId;
        if (!deviceId) return;
        const slot = Number(event.slot) || 0;
        const autoScenes = activeScenes().filter((s) => s.kind === 'auto'
            && s.enabled
            && s.trigger
            && s.trigger.type === 'button'
            && s.trigger.deviceId === deviceId);
        for (const scene of autoScenes) {
            if (scene.trigger.slot && scene.trigger.slot !== slot) continue;
            if (!inWindow(scene.window)) continue;
            trigger(scene, 'button');
        }
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

    function trigger(scene, reason) {
        stats.triggered += 1;
        run(scene.id, { reason }).catch((error) => {
            console.error(`[scenes] 触发「${scene.name}」失败:`, error.message);
        });
    }

    /**
     * 心跳驱动：1 秒一次（由 admin.js 的 setInterval 调）。
     * - 推进 presence 的 holdSec 计时
     * - 每 30 秒做一次定时触发判定
     */
    function tick(now = Date.now()) {
        if (pending.size) {
            for (const [sceneId, item] of pending) {
                const scene = findScene(sceneId);
                if (!scene || !scene.enabled) { pending.delete(sceneId); continue; }
                const holdMs = Math.max(0, Number(scene.trigger && scene.trigger.holdSec) || 0) * 1000;
                if (now - item.at < holdMs) continue;
                // 到点前再确认一次状态仍满足：中途走了就不执行。
                if (item.matcher.kind === 'presence') {
                    const entity = presenceOf(item.matcher.deviceId);
                    const present = Boolean(entity && entity.presence === 'present');
                    if (present !== item.matcher.want) {
                        pending.delete(sceneId);
                        stats.cancelled += 1;
                        log(`撤销「${scene.name}」的触发（状态已变化）`);
                        continue;
                    }
                }
                if (!inWindow(scene.window)) { pending.delete(sceneId); continue; }
                pending.delete(sceneId);
                trigger(scene, 'presence');
            }
        }

        if (now - lastTimeCheck < TIME_TICK_MS) return;
        lastTimeCheck = now;
        if (!listMachines().length) return; // 还没有设备时不用白跑
        const key = minuteKey(new Date(now));
        const current = clockKey(new Date(now));
        for (const scene of activeScenes()) {
            if (scene.kind !== 'auto' || !scene.enabled) continue;
            if (!scene.trigger || scene.trigger.type !== 'time') continue;
            if (scene.trigger.at !== current) continue;
            if (lastTimeKey.get(scene.id) === key) continue;
            if (!inWindow(scene.window)) continue;
            lastTimeKey.set(scene.id, key);
            trigger(scene, 'time');
        }
    }

    /** 供前端渲染：把内部结构翻译成人话，前端不再自己拼字符串。 */
    function decorate(scene) {
        const machineName = (deviceId) => {
            const machine = listMachines().find((item) => item.id === deviceId);
            return machine ? (machine.name || machine.id) : '';
        };
        return {
            ...scene,
            triggerText: scene.kind === 'manual'
                ? '点一下执行'
                : describeTrigger(scene.trigger, { deviceName: machineName }),
            actionTexts: scene.actions.map((action) => describeAction(action, { labelOf })),
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
    describeTrigger,
    describeAction,
    DEFAULT_OCCUPIED_SEC,
};
