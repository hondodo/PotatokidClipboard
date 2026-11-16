// HA 实体目录：把 Home Assistant 的实体清单拉齐、分组、算好可用动作。
//
// 为什么需要这一层：
// - HA 的 REST /api/states 只给 entity_id + state + friendly_name，**不返回
//   area_id / device_id**，所以按「家 → 房间」分组必须走 WebSocket 注册表
//   （config/area_registry/list、config/entity_registry/list、
//   config/device_registry/list）。
// - HA 的 WebSocket auth 消息里 access_token 在**顶层**，不在 payload 里；
//   写成 payload.access_token 会直接 auth_invalid。
// - 各域支持的服务不同：cover 只有 open_cover/close_cover（没有 turn_on），
//   lock 是 lock/unlock，button 是 press。写死「domain/action」会让「选了就 404」，
//   所以这里按 /api/services 的实际结果算出每个域能用的动作与**真实服务名**。
//
// 存储契约：machines.json 里仍只存 action（toggle / turn_on / turn_off / run），
// 不新增字段。调用时由本模块按「域 + 域支持的服务」动态解析出该调的 HA 服务，
// 这样存量配置不用迁移，新配的 cover/turn_on 能正确落到 open_cover。
//
// 区域名约定：HA 的 area 没有层级字段，但名字是「家 房间」（如「金科1204 客厅」），
// 前缀即家名。这里按首个空格切分来还原「家 → 房间」。

const WebSocket = require('ws');

const DEFAULT_TIMEOUT_MS = 12000;
const DEFAULT_CACHE_TTL_MS = 60 * 1000;

// UI 动作 → HA 服务名的候选。同一动作在不同域可能对应不同服务，
// 例如「开」在 light 是 turn_on，在 cover 是 open_cover，在 lock 是 lock。
// 顺序即优先级：取该域实际支持的第一个。
const ACTION_SERVICE_CANDIDATES = {
    toggle: ['toggle'],
    turn_on: ['turn_on', 'open_cover', 'open_valve', 'lock', 'press', 'start'],
    turn_off: ['turn_off', 'close_cover', 'close_valve', 'unlock', 'stop', 'return_to_base'],
    run: ['turn_on', 'run', 'press', 'start'],
    // S5/S6：带参动作。候选按域实际支持的服务取第一个；参数由 callHaService 组装。
    set_temperature: ['set_temperature'],
    set_operation_mode: ['set_operation_mode', 'set_preset_mode'],
    set_hvac_mode: ['set_hvac_mode'],
    set_percentage: ['set_percentage', 'set_speed'],
    select_option: ['select_option'],
    number_set: ['set_value'],
    brightness: ['turn_on'],
    press: ['press'],
    next_effect: ['turn_on'],
    next_option: ['select_option'],
};

// 动作的中文标签：按解析出来的服务名给，比固定文案准（cover 的「开」其实是开盖）。
const SERVICE_LABELS = {
    toggle: '切换',
    turn_on: '开',
    turn_off: '关',
    open_cover: '开盖',
    close_cover: '关盖',
    open_valve: '开阀',
    close_valve: '关阀',
    lock: '上锁',
    unlock: '解锁',
    press: '按下',
    start: '开始',
    stop: '停止',
    return_to_base: '回充',
};

/** 归一化的动作名（与服务端存储口径一致，含 S5 带参动作）。 */
const ACTION_KINDS = [
    'toggle', 'turn_on', 'turn_off', 'run',
    'set_temperature', 'set_operation_mode', 'set_hvac_mode', 'set_percentage',
    'select_option', 'number_set', 'brightness', 'press', 'next_effect', 'next_option',
];

/** 域的中文标签，用于筛选条。 */
const DOMAIN_LABELS = {
    // 有可用开关动作的域
    light: '灯', switch: '开关', fan: '风扇', climate: '空调',
    media_player: '播放器', cover: '窗帘', valve: '阀门',
    script: '脚本', scene: '场景', automation: '自动化',
    input_boolean: '开关(输入)', humidifier: '加湿器', water_heater: '热水器',
    lock: '门锁', button: '按钮', vacuum: '扫地机', siren: '警报器',
    remote: '遥控器', todo: '待办', number: '数值', select: '选项',
    // 没有可用开关动作的域：实体库默认筛掉，但用户放开筛选后会显示，
    // 补上中文名免得满屏英文。
    sensor: '传感器', binary_sensor: '二进制传感器', sun: '日出日落',
    weather: '天气', date: '日期', time: '时间', calendar: '日历',
    zone: '时区', device_tracker: '设备追踪', person: '人员', group: '群组',
    counter: '计数器', timer: '定时器', schedule: '日程',
    conversation: '对话', stt: '语音识别', tts: '语音合成',
    notify: '通知', persistent_notification: '常驻通知', update: '更新',
    image: '图像', camera: '摄像头', event: '事件', geo_location: '地理位置',
    lawn_mower: '割草机',
};

function domainLabel(domain) {
    return DOMAIN_LABELS[domain] || domain;
}

/**
 * 某个域上，一个 UI 动作能否落地，以及实际该调哪个 HA 服务。
 * 返回 null 表示该域不支持这个动作。
 */
function resolveService(domain, action, domainServices) {
    const available = domainServices[domain];
    if (!available) return null;
    const candidates = ACTION_SERVICE_CANDIDATES[action] || [];
    for (const service of candidates) {
        if (available.has(service)) return service;
    }
    return null;
}

/**
 * 某域可用的动作列表 [{action, service, label}]，供前端下拉按实体域收窄。
 *
 * 去重规则：多个 action 解析到同一个服务时只保留第一个（按 ACTION_KINDS 顺序）。
 * 例：button 域只有 press，turn_on 与 run 都落到 press，只留「按下」一条，
 * 避免下拉里出现两个同名项。
 */
function actionsForDomain(domain, domainServices) {
    const list = [];
    const used = new Set();
    for (const action of ACTION_KINDS) {
        const service = resolveService(domain, action, domainServices);
        if (!service || used.has(service)) continue;
        used.add(service);
        list.push({ action, service, label: SERVICE_LABELS[service] || action });
    }
    return list;
}

/** 区域名 → {home, room}：按首个空格切分；没有空格就是「未归属家」的公共区域。 */
function splitAreaName(name) {
    const raw = String(name || '').trim();
    const index = raw.indexOf(' ');
    if (index <= 0) return { home: '', room: raw || '未命名区域' };
    return { home: raw.slice(0, index).trim(), room: raw.slice(index + 1).trim() || raw };
}

/**
 * 一次 WS 连接取回多条命令的结果。
 * @param {string} wsUrl ws://host/api/websocket
 * @param {string} token 长期访问令牌（放顶层）
 * @param {Array<{key: string, type: string}>} commands
 * @returns {Promise<Object<string, any>>} key → result
 */
function wsRequest(wsUrl, token, commands, timeoutMs = DEFAULT_TIMEOUT_MS) {
    return new Promise((resolve, reject) => {
        const socket = new WebSocket(wsUrl, { handshakeTimeout: timeoutMs });
        const pending = new Map();   // message id → command key
        const results = {};
        let nextId = 0;
        let settled = false;

        const finish = (error, value) => {
            if (settled) return;
            settled = true;
            clearTimeout(timer);
            try { socket.close(); } catch (_) { /* 已断开，忽略 */ }
            if (error) reject(error);
            else resolve(value);
        };

        const timer = setTimeout(
            () => finish(new Error('连接 Home Assistant 超时')),
            timeoutMs,
        );

        socket.on('open', () => {
            // access_token 必须在顶层：写成 payload.access_token 会被判 auth_invalid。
            socket.send(JSON.stringify({ type: 'auth', access_token: token }));
        });

        socket.on('message', (raw) => {
            let message;
            try { message = JSON.parse(raw.toString()); } catch (_) { return; }

            if (message.type === 'auth_ok') {
                for (const command of commands) {
                    nextId += 1;
                    pending.set(nextId, command.key);
                    socket.send(JSON.stringify({ id: nextId, type: command.type }));
                }
                return;
            }
            if (message.type === 'auth_invalid') {
                finish(new Error('Home Assistant 令牌无效'));
                return;
            }
            if (!message.id || !pending.has(message.id)) return;

            const key = pending.get(message.id);
            pending.delete(message.id);
            results[key] = message.success === false ? null : (message.result || null);
            if (!pending.size) finish(null, results);
        });

        socket.on('error', (error) => {
            finish(new Error(`连接 Home Assistant 失败：${error.message}`));
        });

        socket.on('close', () => {
            if (!settled) finish(new Error('Home Assistant 连接意外关闭'));
        });
    });
}

/** REST GET，失败时抛带状态码的错误。 */
async function restGet(url, token, timeoutMs = DEFAULT_TIMEOUT_MS) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
        const res = await fetch(url, {
            headers: { Authorization: `Bearer ${token}` },
            signal: controller.signal,
        });
        if (!res.ok) {
            const text = await res.text().catch(() => '');
            throw new Error(`HA 返回 HTTP ${res.status}${text ? `：${text.slice(0, 120)}` : ''}`);
        }
        return await res.json();
    } catch (error) {
        if (error.name === 'AbortError') throw new Error('调用 HA 超时');
        throw error;
    } finally {
        clearTimeout(timer);
    }
}

/**
 * 拉取 HA 的完整实体清单（原始数据，不做分组）。
 */
async function fetchHaRaw(baseUrl, token) {
    const base = /^https?:\/\//i.test(baseUrl) ? baseUrl : `http://${baseUrl}`;
    const root = base.replace(/\/+$/, '');
    const wsUrl = root.replace(/^http/i, 'ws') + '/api/websocket';

    const [states, services, registry] = await Promise.all([
        restGet(`${root}/api/states`, token),
        restGet(`${root}/api/services`, token),
        wsRequest(wsUrl, token, [
            { key: 'areas', type: 'config/area_registry/list' },
            { key: 'entities', type: 'config/entity_registry/list' },
            { key: 'devices', type: 'config/device_registry/list' },
        ]),
    ]);

    // /api/services 返回 [{domain, services:{名字:{...}}}]，转成 Set 便于查询。
    const domainServices = {};
    if (Array.isArray(services)) {
        for (const entry of services) {
            if (!entry || !entry.domain) continue;
            domainServices[entry.domain] = new Set(Object.keys(entry.services || {}));
        }
    }

    return {
        states: Array.isArray(states) ? states : [],
        domainServices,
        areas: Array.isArray(registry.areas) ? registry.areas : [],
        entities: Array.isArray(registry.entities) ? registry.entities : [],
        devices: Array.isArray(registry.devices) ? registry.devices : [],
    };
}

/**
 * 把原始数据组装成前端要的目录结构。
 *
 * 输出：
 * - homes: [{name, count, rooms:[{name, areaId, count}]}]（家 → 房间，带计数）
 * - entities: [{id, name, domain, domainLabel, state, attributes, areaId, areaName, home, room, device, deviceId, deviceModel, manufacturer, actions[]}]
 * - domains: [{id, label, count}]（筛选条用，只含有可用动作的域）
 */
function buildCatalog(raw) {
    const { states, domainServices, areas, entities, devices } = raw;

    const stateMap = {};
    for (const item of states) {
        if (item && item.entity_id) stateMap[item.entity_id] = item;
    }
    const deviceMap = {};
    for (const device of devices) {
        if (device && device.id) deviceMap[device.id] = device;
    }

    // 区域：id → {name, home, room}
    const areaMap = {};
    for (const area of areas) {
        if (!area || !area.area_id) continue;
        const { home, room } = splitAreaName(area.name);
        areaMap[area.area_id] = { id: area.area_id, name: area.name, home, room };
    }

    const rows = [];
    for (const entity of entities) {
        if (!entity || !entity.entity_id) continue;
        const domain = entity.entity_id.split('.')[0].toLowerCase();
        const device = entity.device_id ? deviceMap[entity.device_id] : null;
        const areaId = entity.area_id || (device && device.area_id) || '';
        const area = areaId ? areaMap[areaId] : null;
        const state = stateMap[entity.entity_id] || null;
        const friendly = (state && state.attributes && state.attributes.friendly_name)
            || entity.name
            || entity.original_name
            || entity.entity_id;
        rows.push({
            id: entity.entity_id,
            name: String(friendly),
            domain,
            domainLabel: domainLabel(domain),
            state: state ? String(state.state) : '',
            attributes: state && state.attributes && typeof state.attributes === 'object' ? state.attributes : {},
            areaId,
            areaName: area ? area.name : '',
            home: area ? area.home : '',
            room: area ? area.room : '',
            device: device ? String(device.name || '') : '',
            deviceId: entity.device_id || '',
            deviceModel: device && device.model ? String(device.model) : '',
            manufacturer: device && device.manufacturer ? String(device.manufacturer) : '',
            actions: actionsForDomain(domain, domainServices),
        });
    }

    // 家 → 房间 分组（按计数倒序）。
    const homeMap = new Map();
    for (const row of rows) {
        const homeName = row.home || '未归属家庭';
        if (!homeMap.has(homeName)) homeMap.set(homeName, new Map());
        const rooms = homeMap.get(homeName);
        const roomName = row.room || row.areaName || '未命名区域';
        if (!rooms.has(roomName)) rooms.set(roomName, { name: roomName, areaId: row.areaId, count: 0 });
        rooms.get(roomName).count += 1;
    }
    const homes = Array.from(homeMap.entries())
        .map(([name, rooms]) => ({
            name,
            count: Array.from(rooms.values()).reduce((sum, room) => sum + room.count, 0),
            rooms: Array.from(rooms.values()).sort((a, b) => b.count - a.count),
        }))
        .sort((a, b) => b.count - a.count);

    // 域筛选条（只列有实体且有可用动作的域，否则选了必然失败）。
    const domainCount = new Map();
    for (const row of rows) {
        if (!row.actions.length) continue;
        domainCount.set(row.domain, (domainCount.get(row.domain) || 0) + 1);
    }
    const domains = Array.from(domainCount.entries())
        .map(([id, count]) => ({ id, label: domainLabel(id), count }))
        .sort((a, b) => b.count - a.count);

    return { homes, entities: rows, domains };
}

/**
 * 目录服务：带缓存地提供实体目录与「域支持服务」查询。
 *
 * @param {object} options
 * @param {Function} options.readHaConfig () => {baseUrl, token}
 * @param {number} [options.ttlMs] 缓存有效期
 */
function createHaCatalog({ readHaConfig, ttlMs = DEFAULT_CACHE_TTL_MS } = {}) {
    let catalogCache = null;   // {at, value}
    let servicesCache = null;  // {at, value}

    async function loadServices() {
        const { baseUrl, token } = readHaConfig();
        if (!baseUrl || !token) throw new Error('服务端未配置 HA 地址或令牌');
        const base = /^https?:\/\//i.test(baseUrl) ? baseUrl : `http://${baseUrl}`;
        const services = await restGet(`${base.replace(/\/+$/, '')}/api/services`, token);
        const map = {};
        if (Array.isArray(services)) {
            for (const entry of services) {
                if (!entry || !entry.domain) continue;
                map[entry.domain] = new Set(Object.keys(entry.services || {}));
            }
        }
        return map;
    }

    /** 域 → 支持的服务集合（Set）。带缓存，HA 短暂不可用时复用上一份。 */
    async function getDomainServices(force = false) {
        const now = Date.now();
        if (!force && servicesCache && now - servicesCache.at < ttlMs) {
            return servicesCache.value;
        }
        try {
            const value = await loadServices();
            servicesCache = { at: now, value };
            return value;
        } catch (error) {
            if (servicesCache) {
                console.warn('[ha] 拉取服务清单失败，沿用缓存:', error.message);
                return servicesCache.value;
            }
            throw error;
        }
    }

    /** 完整实体目录（homes / entities / domains）。带缓存。 */
    async function getCatalog(force = false) {
        const now = Date.now();
        if (!force && catalogCache && now - catalogCache.at < ttlMs) {
            return { ...catalogCache.value, cached: true };
        }
        const { baseUrl, token } = readHaConfig();
        if (!baseUrl || !token) throw new Error('服务端未配置 HA 地址或令牌');
        const raw = await fetchHaRaw(baseUrl, token);
        const value = buildCatalog(raw);
        catalogCache = { at: now, value };
        return { ...value, cached: false };
    }

    /**
     * S4：读取若干实体的当前状态，返回 {entity_id: stateObject}。
     * 供服务端按字典把 HA 状态解析成屏幕四行文本（令牌留服务端）。
     * 单次 REST /api/states 拉全量再筛，避免逐实体请求；失败返回空对象。
     */
    async function getStates(entityIds = []) {
        const { baseUrl, token } = readHaConfig();
        if (!baseUrl || !token) return {};
        const wanted = new Set(entityIds.filter(Boolean));
        if (!wanted.size) return {};
        const base = /^https?:\/\//i.test(baseUrl) ? baseUrl : `http://${baseUrl}`;
        const states = await restGet(`${base.replace(/\/+$/, '')}/api/states`, token);
        const result = {};
        if (Array.isArray(states)) {
            for (const item of states) {
                if (item && wanted.has(item.entity_id)) result[item.entity_id] = item;
            }
        }
        return result;
    }

    /**
     * 解析某个实体 + 动作实际该调的 HA 服务名。
     * 解析不出（域不支持该动作）时抛错，避免静默打成 404。
     */
    async function resolveActionService(entityId, action) {
        const domain = String(entityId || '').split('.')[0].toLowerCase();
        const domainServices = await getDomainServices();
        const service = resolveService(domain, action, domainServices);
        if (!service) {
            throw new Error(`实体域 ${domain} 不支持「${action}」动作`);
        }
        return service;
    }

    return { getCatalog, getDomainServices, getStates, resolveActionService };
}

module.exports = {
    ACTION_KINDS,
    ACTION_SERVICE_CANDIDATES,
    DOMAIN_LABELS,
    SERVICE_LABELS,
    actionsForDomain,
    buildCatalog,
    createHaCatalog,
    domainLabel,
    fetchHaRaw,
    resolveService,
    splitAreaName,
    wsRequest,
};
