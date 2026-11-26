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
const http = require('http');
const https = require('https');
const multer = require('multer');
const express = require('express');
const definds = require('./definds');
const { attachPrograms } = require('./programs');
const { ACCOUNT_PATTERN, roleForNewAccount } = require('./accounts');
const claims = require('./claims');
const parentalShare = require('./parental_share');
const { FamilyStore } = require('./parental_family');
const haCatalog = require('./ha_catalog');
const deviceTypes = require('./deviceTypes');
const haDeviceVisibility = require('./haDeviceVisibility');
const { attachScenes } = require('./scenes');
const { createEspSys, lunarText } = require('./esp_sys');

// D-02 硬阻塞地基：家庭级主档案模型。默认关闭，开标志位才启用读路径切换
// （连同客户端/电视端同批次部署，见实施计划第 12 节第 8 条铁律）。
const USE_FAMILY_MODEL = process.env.PARENTAL_FAMILY_MODEL === '1';


const ADMIN_USERNAME = (process.env.ADMIN_USERNAME || 'honghao').trim();
const SESSION_COOKIE = 'pk_admin';
const SESSION_TTL_MS = 7 * 24 * 60 * 60 * 1000;
// 家长自定义登录名的一次性凭证：短时有效，且带独立前缀，不能当 pk_admin 会话用。
const CLAIM_TICKET_TTL_MS = 10 * 60 * 1000;
const CLAIM_TOKEN_PREFIX = 'clm.';
const MACHINE_ONLINE_MS = 90 * 1000;
const MAX_HOMES = 50;
const MAX_HOME_NAME = 64;
const MAX_LAYOUT_ITEMS = 1000;
const MAX_LAYOUT_HOMES = 100;
// 儿童模式（方案 §2.2）：档案数量与各名单字段的上限。
const MAX_PARENTAL_CHILDREN = 12;
const MAX_PARENTAL_LIST = 200;
// 答题解锁题库：单档案题量、单题选项数、题干/选项文案长度、图片体积上限。
const MAX_QUIZ_PER_CHILD = 200;
const MAX_QUIZ_OPTIONS = 10;
const MAX_QUIZ_TEXT = 300;
// 上传走 JSON base64（express jsonLimit 5MB），原图上限取 3MB 留出编码余量。
const MAX_QUIZ_IMAGE_BYTES = 3 * 1024 * 1024;
// 题库图片只接受本服务自己生成的 URL（禁止外链，避免电视端加载任意地址）。
const QUIZ_IMAGE_URL_RE = /^\/api\/parental\/quiz-image\/[a-z0-9]+\.(?:png|jpg|jpeg|webp|gif)$/;
const QUIZ_IMAGE_FILE_RE = /^[a-z0-9]+\.(?:png|jpg|jpeg|webp|gif)$/;
// 一台设备可绑定的家长账号上限。
const MAX_PARENT_ACCOUNTS = 20;
// 头像字段校验：preset:xxx 或 http(s)://...；空字符串 = 客户端回落。
const AVATAR_PRESET_RE = /^preset:[A-Za-z0-9_-]{1,32}$/;
const AVATAR_URL_RE = /^https?:\/\//;
const MAX_AVATAR_URL_LEN = 512;
// 设备备注 / 家长私有别名的长度上限；占位名视为「未设置」，避免历史脏数据被当成真名。
const MAX_MACHINE_NAME = 40;
const MAX_ALIAS_LENGTH = 40;
const UNNAMED_DEVICE = '未命名设备';
// ESP 屏幕页面：一页 = 一台被控设备（屏幕内容 + 一组按键）。
// 页面数量上限只是防御性约束；按键槽位 1..8 是逻辑编号，物理 GPIO 在
// 设备本地设置页分配（NVS），后台只引用槽位号，换接线不用改配置。
const MAX_ESP_PAGES = 12;
const MAX_ESP_BUTTONS = 8;
const MAX_ESP_BUTTONS_PER_PAGE = 8;
const ESP_ENTITY_RE = /^[a-z][a-z0-9_]*\.[a-z0-9_]+$/i;
// 「值替换 / 按实体替换」的键：HA 实体 `domain.object_id`，或遥控语义字段
// `remote.<设备>.<字段>`（对应模板里的三段式标签，如 remote.android_xxx.sleep）。
const ESP_VALUE_TARGET_RE = /^(?:[a-z][a-z0-9_]*\.[a-z0-9_]+|remote\.[a-z0-9_]+\.[a-z]+)$/i;
// S5：带参动作与系统动作一并纳入白名单，配合字典里 set_temperature(+0.5) 这类带值写法。
// 解析时按「动作名(参数)」拆开，动作名必须落在白名单里才放行。
const ESP_ACTION_KINDS = new Set([
    'toggle', 'turn_on', 'turn_off', 'run',
    'set_temperature', 'set_operation_mode', 'set_hvac_mode', 'set_percentage',
    'select_option', 'number_set', 'brightness', 'press', 'next_effect', 'next_option',
]);
const ESP_SYS_ACTIONS = new Set(['next_page', 'prev_page', 'home_page']);
// 遥控设备（中控 / 电视）：一页绑定一台设备，按键从该设备的能力表里挑命令。
// 命令名与 TV 端 MessageCommandExecutor 对齐；参数按 args 描述由后台生成输入，
// 服务端只认这里登记过的命令，避免把任意字符串投给对端。
// kind 为空 = 中控与电视都支持；home / tv 表示只对对应设备类型出现。
const REMOTE_COMMANDS = [
    {
        cmd: 'nav', label: '切换页面', args: [{
            key: 'page', label: '页面', type: 'enum', options: [
                { value: 'home', label: '主页' },
                { value: 'live', label: '直播' },
                { value: 'weather', label: '天气' },
                { value: 'settings', label: '设置' },
                { value: 'screensaver', label: '屏保' },
            ],
        }],
    },
    { cmd: 'volume_up', label: '音量 +' },
    { cmd: 'volume_down', label: '音量 -' },
    { cmd: 'mute', label: '静音' },
    { cmd: 'channel_next', label: '频道 +' },
    { cmd: 'channel_prev', label: '频道 -' },
    { cmd: 'switch_source', label: '切换播放源' },
    {
        cmd: 'channel_digit', label: '数字选台', args: [
            { key: 'digit', label: '数字', type: 'number', min: 0, max: 9 },
        ],
    },
    { cmd: 'channel_digit_resolve', label: '立即跳台' },
    {
        cmd: 'channel', label: '指定频道', args: [
            { key: 'name', label: '频道名', type: 'text' },
        ],
    },
    {
        cmd: 'sleep_timer', label: '定时关闭', args: [
            { key: 'minutes', label: '分钟', type: 'number', min: 0, max: 720 },
        ],
    },
    { cmd: 'live_float', label: '直播悬浮', kind: 'home' },
    // 录制开关：开始取被控端当前播放源，停止并保存。两端共享包都支持。
    { cmd: 'recording_start', label: '开始录制' },
    { cmd: 'recording_stop', label: '停止录制' },
    // 录制切换：不带动作，由被控端按自身录制状态自动开始/停止（状态最准，
    // 不受控制端上报滞后的影响）。等价于远端按一下本机录制按钮。
    { cmd: 'recording_toggle', label: '录制切换' },
    // 儿童模式开关（仅电视）：按下即幂等设为开/关，走服务端 device-local，
    // 不投 cmd 帧、不受短码解锁逻辑影响（见 esp/press 的专门分支）。
    { cmd: 'parental_on', label: '儿童模式·开启', kind: 'tv' },
    { cmd: 'parental_off', label: '儿童模式·关闭', kind: 'tv' },
];
const REMOTE_CMD_MAP = new Map(REMOTE_COMMANDS.map((item) => [item.cmd, item]));
// 页面绑定的目标设备主键（machines.json 的 key）。
const REMOTE_TARGET_RE = /^[A-Za-z0-9_.:-]{1,128}$/;
// 客户端包名 → 设备类型。中控（home）不参与儿童模式与家长绑定，只有电视
// （tv）可作为家长管控对象；家长端（parent）只是控制端，也不是管控对象，
// 但同样上报心跳、走实时通道、可遥控电视。
const HOME_APP_IDS = new Set([
    'potatokid.tools.homecontroller',
    'potatokid.tools.homecontroller.phone',
    'pscreen_home',
]);
const PARENT_APP_IDS = new Set(['potatokid.tools.homecontroller.parent']);
const TV_APP_IDS = new Set([
    'screen.potatokid.tools',
    'screen.potatokid.tools.phone',
    'screen.potatokid.tools.board',
    'screen.potatokid.potatokid_screen',
    'potatokid_screen',
]);

/** 设备类型：home（中控）/ tv（电视）/ parent（家长端）/ ''（尚未上报包名）。 */
function machineKind(machine) {
    const app = machine && typeof machine.commApp === 'string' ? machine.commApp : '';
    if (HOME_APP_IDS.has(app)) return 'home';
    if (PARENT_APP_IDS.has(app)) return 'parent';
    if (TV_APP_IDS.has(app)) return 'tv';
    return '';
}

function isHomeMachine(machine) {
    return machineKind(machine) === 'home';
}

function isTvMachine(machine) {
    return machineKind(machine) === 'tv';
}

/**
 * ESP 小屏设备：固件上报 platform=esp32*，或配置过 OLED 型号 / ESP 页面。
 * 判定口径与 admin 设备列表的筛选保持一致（见 web/admin_js/11-esp.js）。
 */
function isEspMachine(machine) {
    const platform = String((machine && machine.platform) || '').toLowerCase();
    const model = String((machine && machine.model) || '').toLowerCase();
    return platform.includes('esp') || model.includes('oled')
        || (Array.isArray(machine.espPages) && machine.espPages.length > 0);
}


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

function jsonFail(res, msg, code = definds.code.FAILED, status = 200, data) {
    const body = {
        [definds.txt.CODE]: code,
        [definds.txt.MSG]: msg,
    };
    // D-01：冲突响应需要把服务端当前实体一并回带，供客户端展示/覆盖。
    if (data !== undefined) body[definds.txt.DATA] = data;
    return res.status(status).json(body);
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
    // 上限与 accounts.js 的 ACCOUNT_PATTERN 对齐：设备派生账号
    // `<flavor>.<kind>.<设备号16hex>` 会超过旧的 20 位上限。
    if (!name || name.length < 2 || name.length > 64) return '';
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
 * 设备备注归一：空值 / 「未命名设备」占位符都视为「未设置」。
 *
 * 历史版本把 PUT 空值写成字面量 `未命名设备` 并置 `nameSet=true`，导致
 * 客户端把占位符当成用户设置的真名。这里在读取时统一纠正，存量脏数据
 * 无需迁移即可正确回落。
 */
function normalizeMachineName(value) {
    const rawName = typeof value === 'string' ? value.trim().slice(0, MAX_MACHINE_NAME) : '';
    const nameSet = rawName !== '' && rawName !== UNNAMED_DEVICE;
    return { name: rawName || UNNAMED_DEVICE, nameSet };
}

/**
 * 家长私有别名索引：`{账号: 别名}`（方案 B）。
 *
 * - 只接受合法账号作为 key，非法 key 丢弃（防止脏数据写坏 machines.json）；
 * - 别名 trim 后长度 ≤ [MAX_ALIAS_LENGTH]，空值直接删除该项；
 * - 别名只属于某个家长账号，不参与设备全局备注 `name`，对别的家长不可见。
 */
function normalizeMachineAliases(value) {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
    const result = {};
    for (const [rawAccount, rawAlias] of Object.entries(value)) {
        const account = String(rawAccount || '').trim();
        if (!ACCOUNT_PATTERN.test(account)) continue;
        if (typeof rawAlias !== 'string') continue;
        const alias = rawAlias.trim().slice(0, MAX_ALIAS_LENGTH);
        if (!alias) continue;
        result[account] = alias;
    }
    return result;
}

/** 显示绑定：哪个实体做主状态 / 副状态1 / 副状态2（格式非法一律置空）。 */
function normalizeEspBindings(value) {
    const src = value && typeof value === 'object' ? value : {};
    const bindings = {};
    for (const slot of ['main', 's1', 's2']) {
        const entityId = String(src[slot] || '').trim().slice(0, 128);
        bindings[slot] = ESP_ENTITY_RE.test(entityId) ? entityId : '';
    }
    return bindings;
}

/**
 * 屏幕字库只覆盖 GB2312 + ASCII：把常见的排版符号折成等价 ASCII。
 * 例如从手机输入法打出的「温度 −」用的是 U+2212（数学减号），不在字库里会显示成空白。
 */
function normalizeEspOnscreenText(value) {
    return String(value || '')
        .replace(/[\u2212\u2010-\u2015\uff0d]/g, '-')
        .replace(/\uff0b/g, '+');
}

/**
 * 槽位显示名：`{ "1": "蓝色按钮", "2": "红色按钮" }`。
 *
 * 槽位号是设备上的物理按键编号，后台和屏幕提示默认只显示数字；
 * 这里允许给每个槽位起一个名字，屏幕底部提示就变成「蓝色按钮:空调开关」。
 * 只认 1..8，空名称视为未设置（继续显示数字）。
 */
function normalizeEspSlotNames(value) {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return {};
    const out = {};
    for (const [rawSlot, rawName] of Object.entries(value)) {
        const slot = Number(rawSlot);
        if (!Number.isInteger(slot) || slot < 1 || slot > MAX_ESP_BUTTONS) continue;
        const name = normalizeEspOnscreenText(String(rawName == null ? '' : rawName).trim().slice(0, 16));
        if (name) out[String(slot)] = name;
    }
    return out;
}

/**
 * 熄屏配置（设备级）：人体感应亮屏后，人离开多少秒熄屏。
 * 0 = 常亮；上限 30 分钟，避免误填超大值导致屏幕永不熄。
 */
function normalizeEspScreen(value) {
    const raw = value && typeof value === 'object' ? value : {};
    const seconds = Number(raw.onSeconds);
    const onSeconds = Number.isFinite(seconds) && seconds > 0
        ? Math.min(Math.round(seconds), 1800)
        : 0;
    return { onSeconds };
}

/**
 * 每页状态栏配置（v0.5 由设备级下沉到页面级）：显示/隐藏 + 元素勾选。
 * 缺省时给「按现状」的安全默认：页码 + 时间 + WiFi 图标开，IP/RSSI 关。
 * 128×64 单行放不下全部元素，勾选过多由 admin 预览提示、不自动删。
 */
function normalizeEspStatusBar(value) {
    const raw = value && typeof value === 'object' ? value : {};
    const on = (key, fallback) => (typeof raw[key] === 'boolean' ? raw[key] : fallback);
    return {
        enabled: on('enabled', true),
        showPage: on('showPage', true),
        showTime: on('showTime', true),
        showWifiIcon: on('showWifiIcon', true),
        showRssi: on('showRssi', false),
        showIp: on('showIp', false),
        showBatt: on('showBatt', false),
        showVolt: on('showVolt', false),
    };
}

/**
 * 人体感应状态（设备上报 pir: 0/1）。
 * lastEnterAt / lastLeaveAt 只在状态跳变时刷新，避免每次心跳都把时间改成「刚刚」。
 * 未接感应或老固件从来不上报时返回 null，后台显示「未接」。
 */
function normalizeEspPresence(value) {
    if (!value || typeof value !== 'object') return null;
    return {
        present: value.present === true,
        lastEnterAt: Number(value.lastEnterAt) || 0,
        lastLeaveAt: Number(value.lastLeaveAt) || 0,
        updatedAt: Number(value.updatedAt) || 0,
    };
}

/** 设备类型 key 只做格式校验，不认识的自定义 key 交给字典层回落。 */
function normalizeEspTypeKey(value) {
    const raw = String(value || '').trim();
    return /^[a-z][a-z0-9_]{0,39}$/i.test(raw) ? raw : '';
}

/** 自定义模板：单行文案，`|` 是文本协议分隔符，必须挡掉。 */
function normalizeEspTemplate(value) {
    return String(value || '')
        .replace(/[|\r\n]/g, ' ')
        .replace(/\s+/g, ' ')
        .trim()
        .slice(0, 160);
}

/** 值替换表：允许多行，`on=开启` / `off=关闭`；只挡掉协议分隔符 `|`。 */
function normalizeEspValueMap(value) {
    return String(value || '')
        .replace(/\r/g, '')
        .replace(/\|/g, ' ')
        .split('\n')
        .map((line) => line.trim())
        .filter(Boolean)
        .slice(0, 50)
        .join('\n')
        .slice(0, 800);
}

/**
 * 按实体的值替换表：一行一个实体，`entity_id: on=有人, off=无人`。
 *
 * 只用于服务端渲染（不下发设备），所以不需要挡 `|`；
 * 实体名固定在前，冒号后的内容复用全局值替换的解析规则。
 */
function normalizeEspEntityValueMap(value) {
    return String(value || '')
        .replace(/\r/g, '')
        .split('\n')
        .map((line) => line.trim())
        .filter((line) => {
            const idx = line.search(/[:：]/);
            if (idx <= 0) return false;
            return ESP_VALUE_TARGET_RE.test(line.slice(0, idx).trim());
        })
        .slice(0, 50)
        .join('\n')
        .slice(0, 2000);
}

/**
 * 单个按键归一（白名单）。
 *
 * `kind=sys` 是翻页/回首页这类系统动作，不需要实体；`kind=ha` 必须带合法
 * entity_id，且动作名落在白名单里。非法项直接丢弃，避免把设备变成任意
 * 服务调用器。`slot=0` 表示只在网页里点，不绑物理按键。
 */
function normalizeEspButton(raw, index, usedSlots) {
    if (!raw || typeof raw !== 'object') return null;
    // 动作别名：原型里「回首页」写成 home，统一归一到 home_page。
    const rawActionText = String(raw.action || 'toggle').trim();
    const rawAction = rawActionText === 'home' ? 'home_page' : rawActionText;
    // 手动控制（场景）：按下按键直接执行「智能」页里配好的那组动作，不用在
    // 自动化的按键触发里把动作再抄一遍。sceneId 只做格式校验——场景可能已被
    // 删除，这里丢掉整条按键会让用户的配置静默消失，改由按下时明确报错。
    const isScene = raw.kind === 'scene';
    // 录音键：长按在设备本地采集，松开后把 WAV 上传到本服务；不绑实体、不执行 HA。
    const isRec = raw.kind === 'rec';
    const sceneId = isScene ? String(raw.sceneId || '').trim() : '';
    if (isScene && !/^[A-Za-z0-9_-]{1,40}$/.test(sceneId)) return null;
    const isSys = !isScene && !isRec && ESP_SYS_ACTIONS.has(rawAction);
    // 遥控动作：命令必须登记在 REMOTE_COMMANDS 里，实体字段留空。
    const isRemote = raw.kind === 'remote';
    const remoteSpec = isRemote ? REMOTE_CMD_MAP.get(rawAction) : null;
    if (isRemote && !remoteSpec) return null;
    const entityId = isRemote || isScene || isRec ? '' : String(raw.entityId || '').trim().slice(0, 128);
    if (!isSys && !isRemote && !isScene && !isRec && !ESP_ENTITY_RE.test(entityId)) return null;
    // 动作可能是带参写法 `set_temperature(+0.5)` / `select_option(制冷)`；
    // 拆成 {action, param}，只按动作名做白名单校验，参数原样留给 callHaService。
    const m = rawAction.match(/^([a-z_]+)(?:\(([^)]*)\))?$/i);
    const action = isRec ? 'record'
        : isRemote ? remoteSpec.cmd
            : isSys ? rawAction
                : isScene ? 'run'
                    : (m && ESP_ACTION_KINDS.has(m[1]) ? m[1] : 'toggle');
    const param = isRec ? ''
        : isRemote ? normalizeRemoteParam(remoteSpec, raw.param)
            : (isSys || isScene) ? ''
                // 优先用动作串里的 `(+0.5)`；没有括号时回落到独立 param 字段，
                // 兼容「动作选 set_temperature、参数单独填」的配置。
                : ((m && m[2] != null ? m[2].slice(0, 40) : '')
                    || String(raw.param || '').trim().slice(0, 40));
    let id = String(raw.id || '').trim();
    if (!/^[A-Za-z0-9_-]{1,32}$/.test(id)) id = `b${index + 1}`;
    const name = normalizeEspOnscreenText(String(raw.name || raw.label || '').trim().replace(/[|\r\n]/g, ' ').slice(0, 40)) || entityId || (isScene ? '手动控制' : (isRec ? '录音' : action));
    // 名称就是屏幕上显示的文字，不再另存「短标签」：底部提示行本来就会按
    // 自己的节拍滚动，放不下时自动走马灯，不需要提前缩成两个字。
    // 旧数据里的 label 可能是被截断的短名，这里统一以完整 name 为准。
    const label = name;
    const rawSlot = Number(raw.slot == null ? raw.button : raw.slot);
    let slot = Number.isInteger(rawSlot) && rawSlot >= 1 && rawSlot <= MAX_ESP_BUTTONS ? rawSlot : 0;
    // 同一页一个槽位只能绑一个动作：重复的自动降级为「仅网页」，避免按键歧义。
    if (slot && usedSlots && usedSlots.has(slot)) slot = 0;
    if (slot && usedSlots) usedSlots.add(slot);
    return {
        id,
        name,
        label,
        entityId: isSys || isRemote || isScene || isRec ? '' : entityId,
        kind: isRec ? 'rec' : (isRemote ? 'remote' : (isSys ? 'sys' : (isScene ? 'scene' : 'ha'))),
        // 只有手动控制按键带该字段；切到别的类型时自然清空，不留脏引用。
        sceneId,
        // 遥控按键各自的目标设备；非遥控按键不留该字段。
        remoteTarget: isRemote && REMOTE_TARGET_RE.test(String(raw.remoteTarget || '').trim())
            ? String(raw.remoteTarget).trim() : '',
        action,
        param,
        slot,
        enabled: raw.enabled !== false,
    };
}

/**
 * 遥控命令参数归一：只有带 args 的命令才保留参数。
 *
 * - enum：必须落在 options 里，非法值回落到第一项；
 * - number：取整并夹在 [min,max] 内，非法值取 min（通常 0）；
 * - text：原样保留（去首尾空白、截 40 字），交给客户端按频道名匹配。
 * 其余命令一律返回空串，避免把脏参数投给对端。
 */
function normalizeRemoteParam(spec, value) {
    const arg = spec && spec.args && spec.args[0];
    if (!arg) return '';
    const raw = String(value == null ? '' : value).trim().slice(0, 40);
    if (arg.type === 'number') {
        const num = Number(raw);
        const min = Number.isFinite(arg.min) ? arg.min : 0;
        const max = Number.isFinite(arg.max) ? arg.max : 999;
        const safe = Number.isFinite(num) ? Math.min(max, Math.max(min, Math.round(num))) : min;
        return String(safe);
    }
    if (arg.type === 'text') return raw;
    const values = (arg.options || []).map((item) => item.value);
    if (values.includes(raw)) return raw;
    return values[0] || '';
}

/** 目标设备的实体 id：`remote.<设备主键>`（点号换成下划线，符合模板占位符格式）。 */
function remoteEntityId(deviceId) {
    return `remote.${String(deviceId || '').replace(/[^A-Za-z0-9]+/g, '_').toLowerCase()}`;
}

/** 按设备类型过滤能力表：kind 为空的命令两类设备都支持。 */
function remoteCapabilities(kind) {
    return REMOTE_COMMANDS
        .filter((item) => !item.kind || item.kind === kind)
        .map((item) => ({
            cmd: item.cmd,
            label: item.label,
            args: item.args || [],
        }));
}

/** 遥控命令信封：与 home/TV 端 EnvelopeBuilder 的 cmd 帧一致。 */
function remoteCommandArgs(action) {
    const spec = REMOTE_CMD_MAP.get(action.action);
    const arg = spec && spec.args && spec.args[0];
    if (!arg || action.param === '' || action.param == null) return {};
    return { [arg.key]: arg.type === 'number' ? Number(action.param) : action.param };
}

// 模板里 `{remote.<设备id>.<字段>}` 可用的语义字段（白名单，防注入）。
// 字段名必须全小写字母：REMOTE_TPL_TOKEN_RE 只认 [a-z]+。
const REMOTE_STATE_FIELDS = ['page', 'channel', 'volume', 'sleep', 'sleepLeft', 'recchannel', 'rectime'];
// 匹配三段式遥控标签：`remote.android_xxx.channel`。设备 id 只含小写/数字/下划线。
const REMOTE_TPL_TOKEN_RE = /\{remote\.([a-z0-9_]+)\.([a-z]+)\}/g;

/**
 * 遥控设备实时状态拆成语义字段（ESP 模板标签用）。
 *
 * 上报帧的 scene 里：title=当前页、channelName=当前频道、volume=音量、
 * sleepTimer={active,remaining,label}=定时关闭、recording={active,channel,elapsed,label}=录制。
 * 客户端旧版本没有 sleepTimer/recording，缺失时对应字段回落空串，不报错。
 */
function remoteStateFields(state) {
    const blank = {
        page: '', channel: '', volume: '', sleep: '', sleepLeft: '',
        recchannel: '', rectime: '', text: '',
    };
    if (!state || typeof state !== 'object') return blank;
    const scene = state.scene && typeof state.scene === 'object' ? state.scene : null;
    if (!scene) return blank;
    const page = scene.title != null ? String(scene.title) : '';
    const channel = scene.channelName != null ? String(scene.channelName) : '';
    const rawVolume = scene.volume != null ? scene.volume
        : (state.volume != null ? state.volume : null);
    const volume = rawVolume != null && Number.isFinite(Number(rawVolume))
        ? String(Number(rawVolume)) : '';
    const sleepTimer = scene.sleepTimer && typeof scene.sleepTimer === 'object'
        ? scene.sleepTimer : null;
    const sleepActive = Boolean(sleepTimer && sleepTimer.active);
    const sleep = sleepActive ? '开启' : '关闭';
    const sleepLeft = sleepActive
        ? (sleepTimer.label != null ? String(sleepTimer.label) : '')
        : '';
    // 录制：仅在录制中暴露频道与时长，停录后回落空串（避免旧值误导）。
    const recording = scene.recording && typeof scene.recording === 'object'
        ? scene.recording : null;
    const recordingActive = Boolean(recording && recording.active);
    const recchannel = recordingActive && recording.channel != null
        ? String(recording.channel) : '';
    const rectime = recordingActive && recording.label != null
        ? String(recording.label) : '';
    const parts = [];
    if (channel) parts.push(channel);
    else if (page) parts.push(page);
    if (volume) parts.push(`音量${volume}`);
    if (recordingActive) parts.push(`录制${recchannel} ${rectime}`.trim());
    return {
        page, channel, volume, sleep, sleepLeft, recchannel, rectime,
        text: parts.join(' '),
    };
}

/** 实时状态摘要：模板 `{remote.xxx}` 显示「珠江台 音量20」。 */
function remoteStateText(state) {
    return remoteStateFields(state).text;
}

/** 单页归一：页面名 + 图标 + 显示类型/绑定 + 按键表 + 翻页/空闲策略。 */
function normalizeEspPage(raw, index) {
    if (!raw || typeof raw !== 'object') return null;
    let id = String(raw.id || '').trim();
    if (!/^[A-Za-z0-9_-]{1,32}$/.test(id)) id = `p${index + 1}`;
    const name = String(raw.name || '').trim().replace(/[|\r\n]/g, ' ').slice(0, 20) || `页面 ${index + 1}`;
    const icon = String(raw.icon || '').trim().slice(0, 2);
    const buttons = [];
    const usedSlots = new Set();
    const seenIds = new Set();
    const rawButtons = Array.isArray(raw.buttons) ? raw.buttons : [];
    for (const item of rawButtons) {
        if (buttons.length >= MAX_ESP_BUTTONS_PER_PAGE) break;
        const button = normalizeEspButton(item, buttons.length, usedSlots);
        if (!button) continue;
        while (seenIds.has(button.id)) button.id = `${button.id}x`;
        seenIds.add(button.id);
        buttons.push(button);
    }
    const idleRaw = Number(raw.idle);
    const idle = Number.isFinite(idleRaw) && idleRaw > 0 ? Math.min(Math.round(idleRaw), 3600) : 0;
    return {
        id,
        name,
        icon,
        deviceType: normalizeEspTypeKey(raw.deviceType),
        bindings: normalizeEspBindings(raw.bindings),
        // 自定义显示模板与值替换：留空则完全走设备类型字典。
        // 4 个模板位：主/副恒定可用；行3/行4 由页面名/按键提示的显示开关「让位」而来，
        // 老配置没有这两个字段时留空，屏幕行为与升级前一致。
        tplMain: normalizeEspTemplate(raw.tplMain),
        tplSub: normalizeEspTemplate(raw.tplSub),
        tplLine3: normalizeEspTemplate(raw.tplLine3),
        tplLine4: normalizeEspTemplate(raw.tplLine4),
        showTitle: raw.showTitle !== false,
        showKeys: raw.showKeys !== false,
        valueMap: normalizeEspValueMap(raw.valueMap),
        entityValueMap: normalizeEspEntityValueMap(raw.entityValueMap),
        // 绑定的遥控设备（中控/电视主键）；空串 = 这页仍是普通 HA 页面。
        remoteTarget: REMOTE_TARGET_RE.test(String(raw.remoteTarget || '').trim())
            ? String(raw.remoteTarget).trim()
            : '',
        buttons,
        loop: raw.loop !== false,
        idle,
        // 每页状态栏：老页面缺省时给安全默认（页码+时间+WiFi图标），行为近似现状。
        statusBar: normalizeEspStatusBar(raw.statusBar),
        // 图片：服务端下发的 1-bit 点阵（base64），不烧固件。单图 ≤2KB。
        image: normalizeEspImage(raw.image),
    };
}

/** 页面图片：{data(base64), invert}；data 超长/非法则丢弃，不阻塞页面保存。 */
function normalizeEspImage(value) {
    const raw = value && typeof value === 'object' ? value : {};
    const data = typeof raw.data === 'string' && raw.data.length <= 4096 ? raw.data : '';
    // enabled 由「显示图片」勾选控制；空数据时强制关掉，避免留下空壳开关。
    return { data, invert: raw.invert === true, enabled: raw.enabled === true && !!data };
}

/**
 * 旧数据迁移：平铺 espActions（带 page/button）+ 设备级 espDisplay →
 * 页面数组。只读路径调用，用户无感；下一次保存时落成新结构。
 */
function migrateEspActionsToPages(actions, display, deviceName) {
    const groups = new Map();
    for (const item of actions) {
        if (!item || typeof item !== 'object') continue;
        const page = Number(item.page) || 1;
        if (!groups.has(page)) groups.set(page, []);
        groups.get(page).push(item);
    }
    const disp = display && typeof display === 'object' ? display : {};
    const pages = [];
    for (const [pageNo, items] of [...groups.entries()].sort((a, b) => a[0] - b[0])) {
        pages.push({
            id: `p${pageNo}`,
            // 第 1 页沿用设备名做标题，保持旧版屏幕的观感；后续页面用通用名。
            name: pageNo === 1 && deviceName ? deviceName : `页面 ${pageNo}`,
            icon: '',
            // 旧的设备级分类/绑定只对第 1 页有意义，其余页保持未分类。
            deviceType: pageNo === 1 ? normalizeEspTypeKey(disp.deviceType) : '',
            bindings: pageNo === 1 ? normalizeEspBindings(disp.bindings) : { main: '', s1: '', s2: '' },
            tplMain: '',
            tplSub: '',
            tplLine3: '',
            tplLine4: '',
            showTitle: true,
            showKeys: true,
            valueMap: '',
            entityValueMap: '',
            remoteTarget: '',
            buttons: items.map((item) => ({
                id: item.id,
                name: item.name,
                label: item.name || item.label || '',
                kind: item.sys ? 'sys' : 'ha',
                action: item.action,
                param: item.param,
                entityId: item.entityId,
                slot: item.button || 0,
                enabled: item.enabled === true,
            })),
            loop: true,
            idle: 0,
            statusBar: normalizeEspStatusBar(null),
            image: { data: '', invert: false },
        });
    }
    return pages;
}

/**
 * 设备本地配置（远程下发）：按键映射、角色、休眠、自动更新等原本只能在设备
 * 自己的设置页改，设备深睡后根本连不上。这里在服务端存一份「期望值」，
 * 带版本号 ver；设备心跳发现版本变了就拉取并写入 NVS。
 */
function normalizeEspCfg(value) {
    const src = value && typeof value === 'object' ? value : {};
    const clamp = (n, min, max, fallback) => {
        const v = Number(n);
        if (!Number.isFinite(v)) return fallback;
        return Math.min(max, Math.max(min, Math.round(v)));
    };
    const pins = Array.isArray(src.pins)
        ? src.pins.slice(0, MAX_ESP_BUTTONS).map((p) => {
            const n = Number(p);
            return Number.isInteger(n) && n >= 0 && n <= 48 ? n : -1;
        })
        : [];
    return {
        role: src.role === 'slave' ? 'slave' : 'master',
        masterMac: typeof src.masterMac === 'string' ? src.masterMac.trim().toUpperCase().slice(0, 32) : '',
        autoUpdate: src.autoUpdate !== false,
        idleSleep: clamp(src.idleSleep, 0, 3600, 0),
        otaCheckSec: clamp(src.otaCheckSec, 300, 21600, 21600),
        pirPin: Number.isInteger(Number(src.pirPin)) ? Number(src.pirPin) : -1,
        netSlot: clamp(src.netSlot, 0, MAX_ESP_BUTTONS, 0),
        batPin: Number.isInteger(Number(src.batPin)) ? Number(src.batPin) : -1,
        batDiv: clamp(src.batDiv, 1, 10, 2),
        pins,
        // 版本号用「秒级时间戳」：设备端是 uint32，毫秒会溢出。
        ver: (() => {
            const raw = Number(src.ver) || 0;
            return raw > 4000000000 ? Math.floor(raw / 1000) : raw;
        })(),
    };
}

/** 设备上报的槽位→GPIO 映射：`[{slot:1,pin:4}]`，只做展示与诊断，不反向下发。 */
function normalizeEspButtons(value) {
    if (!Array.isArray(value)) return [];
    const list = [];
    const seen = new Set();
    for (const raw of value) {
        if (!raw || typeof raw !== 'object') continue;
        const slot = Number(raw.slot);
        const pin = Number(raw.pin);
        if (!Number.isInteger(slot) || slot < 1 || slot > MAX_ESP_BUTTONS) continue;
        if (!Number.isInteger(pin) || pin < 0 || pin > 48) continue;
        if (seen.has(slot)) continue;
        seen.add(slot);
        list.push({ slot, pin });
        if (list.length >= MAX_ESP_BUTTONS) break;
    }
    return list.sort((a, b) => a.slot - b.slot);
}

/** 页面数组归一 + 旧数据自动迁移（传了 espPages 就忽略旧字段）。 */
function normalizeEspPages(value, legacyActions, legacyDisplay, deviceName) {
    let rawPages = Array.isArray(value) ? value : [];
    if (!rawPages.length && Array.isArray(legacyActions) && legacyActions.length) {
        rawPages = migrateEspActionsToPages(legacyActions, legacyDisplay, deviceName);
    }
    const pages = [];
    const seenIds = new Set();
    for (const raw of rawPages) {
        if (pages.length >= MAX_ESP_PAGES) break;
        const page = normalizeEspPage(raw, pages.length);
        if (!page) continue;
        while (seenIds.has(page.id)) page.id = `${page.id}x`;
        seenIds.add(page.id);
        pages.push(page);
    }
    return pages;
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
        if (value.unlockMode !== 'remote' && value.unlockMode !== 'pin' && value.unlockMode !== 'arith' && value.unlockMode !== 'quiz') {
            throw new Error('parental.unlockMode 必须是 remote、pin、arith 或 quiz');
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
        // avatar：可选字段；缺省 → 客户端回落（preset 或派生）；给出则必须是
        // preset:xxx 或 http(s):// 开头的 URL（长度 ≤ 512）；禁止外链白名单以外。
        let avatar;
        if (child.avatar !== undefined && child.avatar !== null && child.avatar !== '') {
            if (typeof child.avatar !== 'string') {
                throw new Error(`${at}.avatar 必须是字符串`);
            }
            const trimmed = child.avatar.trim();
            if (trimmed.length > MAX_AVATAR_URL_LEN) {
                throw new Error(`${at}.avatar 长度不能超过 ${MAX_AVATAR_URL_LEN} 字符`);
            }
            if (AVATAR_PRESET_RE.test(trimmed) || AVATAR_URL_RE.test(trimmed)) {
                avatar = trimmed;
            } else {
                throw new Error(`${at}.avatar 必须是 preset:xxx 或以 http(s):// 开头的 URL`);
            }
        }
        children.push({
            id,
            name: child.name.trim().slice(0, 40),
            ...(age !== undefined ? { age } : {}),
            profileMode,
            locked: child.locked === true,
            ...(avatar !== undefined ? { avatar } : {}),
            hideGroups: normalizeParentalNameList(child.hideGroups, `${at}.hideGroups`),
            hideChannels: normalizeParentalNameList(child.hideChannels, `${at}.hideChannels`),
            allowGroups: normalizeParentalNameList(child.allowGroups, `${at}.allowGroups`),
            allowChannels: normalizeParentalNameList(child.allowChannels, `${at}.allowChannels`),
            sessionLimitMin,
            dailyLimitMin,
            quietHours: normalizeParentalQuietHours(child.quietHours, `${at}.quietHours`),
            // 档案引用共享：本档案可被引用的家长号白名单（owner opt-in）。
            // 默认 []＝不对任何其他家长分享；只在共享页显式指定后才有值。
            sharedTo: parentalShare.normalizeSharedTo(child.sharedTo, `${at}.sharedTo`),
        });
    });

    // 档案引用共享：本台「引用进来」的档案坐标（只存指针不存副本）。
    const shared = parentalShare.normalizeSharedRefs(value.shared);

    return {
        mode: value.mode,
        activeChildIds,
        children,
        shared,
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

/**
 * 答题解锁题库校验（单档案整库替换语义，PUT /api/admin/parental/quiz 用）。
 *
 * 结构/类型/范围非法一律 throw（整体拒绝），避免家长以为题目已生效；
 * 文案裁剪、选项去重属于安全归一。题量上限 [MAX_QUIZ_PER_CHILD]。
 */
function normalizeQuizQuestions(value) {
    if (value === undefined || value === null) return [];
    if (!Array.isArray(value)) throw new Error('questions 必须是数组');
    if (value.length > MAX_QUIZ_PER_CHILD) {
        throw new Error(`单档案题库最多 ${MAX_QUIZ_PER_CHILD} 题`);
    }
    const seenIds = new Set();
    const list = value.map((raw, index) => {
        const at = `questions[${index}]`;
        if (!raw || typeof raw !== 'object' || Array.isArray(raw)) {
            throw new Error(`${at} 必须是对象`);
        }
        if (typeof raw.id !== 'string' || !raw.id.trim() || raw.id.trim().length > 64) {
            throw new Error(`${at}.id 必须是非空字符串（≤64 字符）`);
        }
        const id = raw.id.trim();
        if (seenIds.has(id)) throw new Error(`${at}.id 重复：${id}`);
        seenIds.add(id);
        const type = raw.type === 'fill' ? 'fill' : (raw.type === 'choice' ? 'choice' : null);
        if (!type) throw new Error(`${at}.type 必须是 choice 或 fill`);
        const prompt = typeof raw.prompt === 'string' ? raw.prompt.trim().slice(0, MAX_QUIZ_TEXT) : '';
        const promptImage = typeof raw.promptImage === 'string' ? raw.promptImage.trim() : '';
        if (promptImage && !QUIZ_IMAGE_URL_RE.test(promptImage)) {
            throw new Error(`${at}.promptImage 必须是题库图片地址`);
        }
        if (!prompt && !promptImage) throw new Error(`${at} 题干文案与题干图片不能同时为空`);
        if (type === 'choice') {
            if (!Array.isArray(raw.options) || raw.options.length < 2 || raw.options.length > MAX_QUIZ_OPTIONS) {
                throw new Error(`${at}.options 必须是 2~${MAX_QUIZ_OPTIONS} 个选项`);
            }
            const options = raw.options.map((option, optionIndex) => {
                const oat = `${at}.options[${optionIndex}]`;
                const source = typeof option === 'string' ? { text: option } : option;
                if (!source || typeof source !== 'object' || Array.isArray(source)) {
                    throw new Error(`${oat} 必须是对象或字符串`);
                }
                const text = typeof source.text === 'string' ? source.text.trim().slice(0, MAX_QUIZ_TEXT) : '';
                const image = typeof source.image === 'string' ? source.image.trim() : '';
                if (image && !QUIZ_IMAGE_URL_RE.test(image)) {
                    throw new Error(`${oat}.image 必须是题库图片地址`);
                }
                if (!text && !image) throw new Error(`${oat} 文案与图片不能同时为空`);
                return { text, image };
            });
            const multiple = raw.multiple === true;
            const rawAnswers = Array.isArray(raw.answers) ? raw.answers : [];
            const answers = [];
            for (const item of rawAnswers) {
                if (typeof item !== 'number' || !Number.isInteger(item) || item < 0 || item >= options.length) {
                    throw new Error(`${at}.answers 必须是选项下标的整数数组`);
                }
                if (!answers.includes(item)) answers.push(item);
            }
            if (answers.length === 0) throw new Error(`${at}.answers 至少包含一个正确选项`);
            if (!multiple && answers.length !== 1) throw new Error(`${at} 单选题只能有一个正确选项`);
            if (multiple && answers.length > options.length) throw new Error(`${at}.answers 超出选项范围`);
            return { id, type, prompt, promptImage, multiple, options, answers };
        }
        const rawAccept = Array.isArray(raw.accept) ? raw.accept : [];
        const accept = [];
        for (const item of rawAccept) {
            if (typeof item !== 'string') throw new Error(`${at}.accept 的元素必须是字符串`);
            const text = item.trim().slice(0, MAX_QUIZ_TEXT);
            if (!text) continue;
            if (!accept.includes(text)) accept.push(text);
            if (accept.length >= MAX_QUIZ_OPTIONS) break;
        }
        if (accept.length === 0) throw new Error(`${at}.accept 至少包含一个可接受答案`);
        return { id, type, prompt, promptImage, multiple: false, options: [], answers: [], accept };
    });
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
    // realtime 未挂载时安全降级为空；parental 记录查询用。
    const eventsForAccounts = typeof options.eventsForAccounts === 'function'
        ? options.eventsForAccounts
        : () => [];
    // 由 server.js 注入：把配置变更推给在线设备（realtime 在 admin 之后挂载）。
    const pushDeviceConfig = typeof options.pushDeviceConfig === 'function'
        ? options.pushDeviceConfig
        : () => {};
    // 遥控命令投递：按设备通信账号推 cmd 帧，返回送达的连接数（未注入时为 0）。
    const pushRemoteCommand = typeof options.pushRemoteCommand === 'function'
        ? options.pushRemoteCommand
        : () => 0;
    // 遥控设备实时状态（场景/音量），模板 `{remote.xxx}` 用；未注入时为空。
    const remoteStateOf = typeof options.remoteState === 'function'
        ? options.remoteState
        : () => null;
    // 上传镜像转发实例（forward.js）；未注入时状态接口降级为不可用。
    const forward = options.forward || null;

    const adminDir = path.join(datasDir, 'admin');
    fs.mkdirSync(adminDir, { recursive: true });

    // ESP 系统变量服务（天气 / 农历 / 城市映射表），独立于 machines 配置。
    const espSys = createEspSys({
        adminDir,
        readJson,
        writeJson,
        log: (msg) => console.log(msg),
    });
    // 城市删除前的引用检查：扫描所有 ESP 页面模板里用到的 sys.weather.<id>。
    espSys.setReferencedIdsScanner(() => {
        const refs = new Set();
        for (const machine of Object.values(readMachines())) {
            for (const page of (machine.espPages || [])) {
                for (const tpl of [page.tplMain, page.tplSub]) {
                    const re = /\{sys\.weather\.([a-zA-Z0-9_]+)\}/g;
                    let m;
                    while ((m = re.exec(String(tpl || ''))) !== null) refs.add(m[1]);
                }
            }
        }
        return refs;
    });

    const machinesFile = path.join(adminDir, 'machines.json');
    // ESP 小屏控制 HA 用的连接信息（地址 + 长期令牌），由 admin 页维护。
    // 也可用环境变量 HA_BASE_URL / HA_TOKEN 提供，两者都没有时按键会明确报错。
    const haFile = path.join(adminDir, 'ha.json');
    // ESP 固件托管：admin 页上传 bin，设备检测到版本不同时自行下载写 OTA 槽。
    const firmwareDir = path.join(datasDir, 'firmware');
    fs.mkdirSync(firmwareDir, { recursive: true });
    const firmwareBin = path.join(firmwareDir, 'firmware.bin');
    const firmwareMeta = path.join(firmwareDir, 'meta.json');
    // 双芯片 OTA：S3 沿用上面的旧文件名（兼容既有发布），C6 单独一条轨。
    const firmwareBinC6 = path.join(firmwareDir, 'firmware-c6.bin');
    const firmwareMetaC6 = path.join(firmwareDir, 'meta-c6.json');
    const layoutsFile = path.join(adminDir, 'layouts.json');
    // 「智能」场景：手动控制 + 自动化（触发 → 动作）。settings 与 scenes 同文件。
    const scenesFile = path.join(adminDir, 'scenes.json');
    const secretFile = path.join(adminDir, 'secret.key');
    // 答题解锁题库：按「设备 → 儿童档案」独立存储，不塞进 machines.json，
    // 避免管理页保存 parental 时把题库冲掉，也避开 ws config 帧 128KiB 上限。
    const quizFile = path.join(adminDir, 'parental_quizzes.json');
    const quizImageDir = path.join(adminDir, 'parental-quiz-images');
    // 儿童档案头像：上传到 app_server（公网直链），本地只存索引 + sha256 去重。
    const avatarFile = path.join(adminDir, 'parental_avatars.json');
    const avatarImageDir = path.join(adminDir, 'parental-avatars');
    const MAX_AVATAR_IMAGE_BYTES = 2 * 1024 * 1024; // 客户端已压到 ≤300KB，留余量
    // 设备类型卡片图标：和头像走同一条镜像转发链路，但只存相对路径，避免 yuntu IP 写死在配置里。
    const cardIconFile = path.join(adminDir, 'card_icons.json');
    const cardIconDir = path.join(adminDir, 'card-icons');
    const MAX_CARD_ICON_BYTES = 2 * 1024 * 1024;
    const CARD_ICON_URL_RE = /^\/api\/files\/[A-Za-z0-9_-]{1,80}\/avatar$/;

    // D-02 家庭级主档案存储：按 childId 全局唯一，分配/本台设置按 deviceId。
    // 仅 USE_FAMILY_MODEL 开启时参与读路径；首次启用会从旧 machine.parental 迁移。
    const familyStore = new FamilyStore(path.join(adminDir, 'parental_family.json'));

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
        const rawDisplayName = typeof info.displayName === 'string'
            ? info.displayName.trim().slice(0, 40)
            : '';
        return {
            id: Number(info.id) || 0,
            name,
            // displayName 为空时回落账号 id（name）；displayNameSet 供后台区分「未设置」。
            displayName: rawDisplayName || name,
            displayNameSet: rawDisplayName !== '',
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
    // 派生账号（<flavor>.<kind>.<设备号>）若历史数据缺 role，按账号规则补齐：
    // 家长端 parent.* 补 parent，其余补 user（不覆盖已显式设置的角色）。
    (function migrateUsers() {
        for (const user of listUsers()) {
            const info = readUserInfo(user.name);
            const nextRole = user.name === ADMIN_USERNAME
                ? 'admin'
                : (info.role || roleForNewAccount(user.name));
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
        const owner = typeof machine.owner === 'string' ? machine.owner.trim() : '';
        const kind = machineKind(machine);
        // `owner` 表示「设备所属中控账号」，`parents` 只表示家长绑定关系，
        // 两者不再互相推导。中控设备不参与家长绑定：强制清空 parents，避免
        // 历史数据把中控误当成可管控的电视。家长端（parent）不是管控对象，
        // 但也不强行清空 parents（历史数据保留，其它按 tv 过滤的逻辑不会纳入它）。
        let parents = normalizeStringList(machine.parents, MAX_PARENT_ACCOUNTS);
        if (kind === 'home') {
            parents = [];
        }
        const nameInfo = normalizeMachineName(machine.name);
        return {
            id,
            kind,
            // name 为空时用「未命名设备」占位；nameSet 供后台/客户端区分是否真的设置过备注。
            ...nameInfo,
            // 家长私有别名（方案 B）：{账号: 别名}，只对本人生效，不下发给其他家长。
            aliases: normalizeMachineAliases(machine.aliases),
            owner,
            parents,
            homes,
            // 儿童模式只对电视生效：home / parent 即便带了历史字段也一律置空。
            parental: kind === 'tv' ? parental : null,
            // ESP 屏幕页面：一页 = 一台被控设备（显示类型/绑定 + 一组按键）。
            // 旧机器的平铺 espActions / espDisplay 在这里自动迁移，不丢历史配置。
            espPages: normalizeEspPages(machine.espPages, machine.espActions, machine.espDisplay,
                nameInfo.nameSet ? nameInfo.name : ''),
            // 设备本地上报的按键槽位→GPIO（只读展示，后台不反向下发）。
            espButtons: normalizeEspButtons(machine.espButtons),
            // 远程配置下发：期望值（espCfg，带 ver）+ 设备最近一次自报（cfgNow、已应用版本）。
            espCfg: normalizeEspCfg(machine.espCfg),
            cfgNow: machine.cfgNow && typeof machine.cfgNow === 'object' ? machine.cfgNow : null,
            cfgApplied: Number(machine.cfgApplied) || 0,
            // 唤醒诊断：最近一次唤醒来源 + PIR 唤醒累计次数。
            lastWake: typeof machine.lastWake === 'string' ? machine.lastWake : '',
            pirWakes: Number(machine.pirWakes) || 0,
            pirLevel: Number(machine.pirLevel) === 1 ? 1 : 0,
            slpErr: machine.slpErr && typeof machine.slpErr === 'object' ? machine.slpErr : null,
            pirMode: Number(machine.pirMode) || 0,
            diag: machine.diag && typeof machine.diag === 'object' ? machine.diag : null,
            // 槽位显示名（1..8）：设备级，屏幕底部提示用名字代替数字。
            espSlotNames: normalizeEspSlotNames(machine.espSlotNames),
            // 熄屏（人体感应）：设备级，SCREEN 行下发给固件。
            espScreen: normalizeEspScreen(machine.espScreen),
            // 人体感应状态（设备上报）：后台只读展示。
            espPresence: normalizeEspPresence(machine.espPresence),
            platform: typeof machine.platform === 'string' ? machine.platform.slice(0, 32) : '',
            model: typeof machine.model === 'string' ? machine.model.slice(0, 64) : '',
            // 主从角色由设备本机设置页或后台维护；芯片型号（model）决定 OTA 轨道。
            role: machine.role === 'slave' ? 'slave' : 'master',
            masterMac: typeof machine.masterMac === 'string' ? machine.masterMac.slice(0, 32) : '',
            batteryMv: Number(machine.batteryMv) || 0,
            appVersion: typeof machine.appVersion === 'string' ? machine.appVersion.slice(0, 32) : '',
            ip: typeof machine.ip === 'string' ? machine.ip.slice(0, 64) : '',
            lanIp: typeof machine.lanIp === 'string' ? machine.lanIp.slice(0, 64) : '',
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
            // 最后一次「建立连接」（ws 握手 / 首次建档）的时间，不被 ping/report
            // 这类保活刷新；与 lastSeen（最后活跃）分开，便于后台区分在线时长。
            lastConnectedAt: Number(machine.lastConnectedAt) || 0,
            // 远程更新：后台点「远程更新」写入的时间戳，随心跳/注册下发。
            // 设备据此强制检查并安装固件（即使本机把「自动更新」关了）。
            fwPushAt: Number(machine.fwPushAt) || 0,
            // 设备自报的 OTA 轨道（esp32s3 / esp32c6）：后台据此找对应的发布版本。
            fwTarget: typeof machine.fwTarget === 'string' ? machine.fwTarget.slice(0, 16) : '',
            // 深睡从机自报的定时唤醒间隔（秒）：后台据此显示「预计唤醒时间」。
            sleepSec: Number(machine.sleepSec) || 0,
        };
    }

    function saveMachines(machines) {
        writeJson(machinesFile, machines);
    }

    // ------------------------------------------------------------ HA 调用（ESP 按键）

    /** 读取 HA 连接信息：admin 页保存值优先，环境变量兜底。 */
    function readHaConfig() {
        const raw = readJson(haFile, {}) || {};
        const pick = (fileValue, envValue) => {
            const fromFile = typeof fileValue === 'string' ? fileValue.trim() : '';
            if (fromFile) return fromFile;
            return typeof envValue === 'string' ? envValue.trim() : '';
        };
        return {
            baseUrl: pick(raw.baseUrl, process.env.HA_BASE_URL),
            token: pick(raw.token, process.env.HA_TOKEN),
        };
    }

    function haConfigView() {
        const { baseUrl, token } = readHaConfig();
        return { baseUrl, hasToken: token !== '', configured: baseUrl !== '' && token !== '' };
    }

    // 设备类型字典服务（S1/S3）：home 与 ESP 共用的唯一真源。覆盖层落在
    // datas/admin/deviceTypes.json，admin 页改一处两端生效。
    const deviceTypesFile = path.join(adminDir, 'deviceTypes.json');
    const deviceTypeService = deviceTypes.createDeviceTypeService({ file: deviceTypesFile });

    // HA 设备「是否显示到中控屏」开关（三态：未配置/显示/隐藏）。
    const haDeviceVisibilityFile = path.join(adminDir, 'haDeviceVisibility.json');
    const haDeviceVisibilityService = haDeviceVisibility.createHaDeviceVisibilityService({ file: haDeviceVisibilityFile });

    // HA 实体目录服务：拉注册表 + 状态 + 服务清单，按「家 → 房间」分组。
    // 带 60 秒缓存（HA 在同一局域网内，实时性要求不高）；HA 短暂不可用时
    // 服务清单沿用上一份缓存，避免按键全挂。
    const haCatalogService = haCatalog.createHaCatalog({ readHaConfig });

    /**
     * 调一次 HA REST 服务。抛错由调用方转成业务失败。
     *
     * ⚠️ 服务名不能写死「domain/action」：HA 各域支持的服务不一样，
     * 例如 cover 只有 open_cover/close_cover（没有 turn_on）、lock 是 lock/unlock、
     * button 是 press。写死会让「选了就 404」。这里按该域实际支持的服务
     * 动态解析（见 ha_catalog.resolveActionService），解析不出直接报错。
     */
    // 带参动作 → HA 服务请求体的字段名（Home Assistant 各服务的数据键不同）。
    const HA_PARAM_KEYS = {
        set_temperature: 'temperature',
        set_operation_mode: 'operation_mode',
        set_hvac_mode: 'hvac_mode',
        set_percentage: 'percentage',
        select_option: 'option',
        number_set: 'value',
        brightness: 'brightness_pct',
        next_effect: 'effect',
        next_option: 'option',
    };
    // 相对参数（如 +0.5 / -25）需要读取当前值再相加，各动作取当前值的属性不同。
    const HA_PARAM_ATTRS = {
        set_temperature: 'temperature',
        set_percentage: 'percentage',
        brightness: 'brightness',
        number_set: 'value',
    };

    /**
     * 调一次 HA REST 服务。抛错由调用方转成业务失败。
     *
     * ⚠️ 服务名不能写死「domain/action」：HA 各域支持的服务不一样，
     * 例如 cover 只有 open_cover/close_cover（没有 turn_on）、lock 是 lock/unlock、
     * button 是 press。写死会让「选了就 404」。这里按该域实际支持的服务
     * 动态解析（见 ha_catalog.resolveActionService），解析不出直接报错。
     *
     * S5：param 是带参动作的值（如 "0.5" / "+0.5" / "制冷"）。相对值先读当前
     * 状态属性再相加；所有计算在服务端完成，令牌和数值运算都不进设备。
     */
    async function callHaService(entityId, action, param) {
        const { baseUrl, token } = readHaConfig();
        if (!baseUrl || !token) throw new Error('服务端未配置 HA 地址或令牌');
        const base = /^https?:\/\//i.test(baseUrl) ? baseUrl : `http://${baseUrl}`;
        const domain = entityId.split('.')[0].toLowerCase();
        // HA REST 的服务路径是 /api/services/<domain>/<service>（斜杠，不是点号）
        const service = await haCatalogService.resolveActionService(entityId, action);
        const url = `${base.replace(/\/+$/, '')}/api/services/${domain}/${service}`;

        const body = { entity_id: entityId };
        const paramKey = HA_PARAM_KEYS[action];
        // 带参动作必须有参数：缺了直接报可读错误，别把半截请求丢给 HA 换 400。
        if (paramKey && !param) {
            throw new Error(`「${action}」需要参数（例如 +0.5 / 制冷），请在后台该按键的「参数」里填写`);
        }
        if (paramKey && param) {
            let value = param;
            // 相对值：+0.5 / -25 —— 读当前属性算好绝对值，服务端 clamp 交给 HA 域自身。
            const relMatch = String(param).match(/^([+-])(\d+(?:\.\d+)?)$/);
            if (relMatch) {
                const attr = HA_PARAM_ATTRS[action];
                const current = await haCatalogService.getStates([entityId]);
                const stateObj = current[entityId];
                const attrs = (stateObj && stateObj.attributes) || {};
                const baseVal = Number(attr ? attrs[attr] : stateObj && stateObj.state);
                if (!Number.isFinite(baseVal)) throw new Error(`无法读取 ${entityId} 当前值，相对调节失败`);
                const delta = Number(relMatch[2]);
                value = relMatch[1] === '-' ? baseVal - delta : baseVal + delta;
                // 浮点误差收敛到 2 位小数（温度 step 常见 0.5）
                value = Math.round(value * 100) / 100;
            }
            // brightness 服务要 0-255，界面用的是百分比；做一次换算。
            if (action === 'brightness' && /^\d+(?:\.\d+)?$/.test(String(value))) {
                value = Math.max(0, Math.min(255, Math.round(Number(value) * 255 / 100)));
            }
            body[paramKey] = value;
        }

        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), 6000);
        try {
            const res = await fetch(url, {
                method: 'POST',
                headers: {
                    Authorization: `Bearer ${token}`,
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify(body),
                signal: controller.signal,
            });
            if (!res.ok) {
                const text = await res.text().catch(() => '');
                throw new Error(`HA 返回 HTTP ${res.status}${text ? `：${text.slice(0, 120)}` : ''}`);
            }
        } catch (error) {
            if (error.name === 'AbortError') throw new Error('调用 HA 超时');
            throw error;
        } finally {
            clearTimeout(timer);
        }
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

    // ------------------------------------------------------------ 答题题库

    /** 读题库存储（坏条目容错丢弃，单条损坏不能让整份 JSON 读不出来）。 */
    function readQuizStore() {
        const raw = readJson(quizFile, {});
        if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return {};
        const result = {};
        for (const [deviceId, children] of Object.entries(raw)) {
            if (!safeDeviceId(deviceId) || !children || typeof children !== 'object' || Array.isArray(children)) continue;
            const banks = {};
            for (const [childId, bank] of Object.entries(children)) {
                const id = String(childId || '').trim();
                if (!id || id.length > 64) continue;
                try {
                    banks[id] = {
                        updatedAt: Math.max(0, Math.trunc(Number(bank && bank.updatedAt) || 0)),
                        questions: normalizeQuizQuestions(bank && bank.questions),
                    };
                } catch (error) {
                    console.warn(`[quiz] 丢弃损坏题库 ${deviceId}/${id}: ${error.message}`);
                }
            }
            result[deviceId] = banks;
        }
        return result;
    }

    function saveQuizStore(store) {
        writeJson(quizFile, store);
    }

    /** 家长操作权限：parent 只能改自己绑定电视的题库，admin 全放行。 */
    function canEditMachineQuizzes(req, machine) {
        if (!machine) return false;
        if (req.adminUser.role === 'parent') return machine.parents.includes(req.adminUser.name);
        return true;
    }

    /**
     * 儿童档案写护栏三态（档案引用共享）：
     * - master：本台主本档案，可读写；
     * - shared：引用进来的档案（主本在别台），只读，写操作须拒绝并提示去主本改；
     * - missing：既非本台档案也无此引用。
     * 保留 childExists 布尔版供既有调用点先兼容，新逻辑统一走 childWriteState。
     */
    function childWriteState(machine, childId, viewerParent) {
        return parentalShare.resolveChild(machine, readMachines(), childId, viewerParent || null);
    }

    function childExists(machine, childId) {
        const children = machine.parental && Array.isArray(machine.parental.children) ? machine.parental.children : [];
        return children.some((child) => child.id === childId);
    }

    /** 题库/头像读取落点：引用档案重定向到主本电视。 */
    function quizLookup(machine, childId, viewerParent) {
        return parentalShare.resolveQuizTarget(machine, readMachines(), childId, viewerParent || null);
    }

    // ------------------------------------------------------------ 头像索引

    /** 头像素材索引：{ "<deviceId>": [ { id, url, sha256, mime, size, uploadedBy, createdAt, childIds: [] } ] }。
     *  跨设备相同 sha256 的图片视为同一张（列表接口会按 sha256 去重）。 */
    function readAvatarStore() {
        const raw = readJson(avatarFile, {});
        if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return {};
        const result = {};
        for (const [deviceId, list] of Object.entries(raw)) {
            if (!safeDeviceId(deviceId) || !Array.isArray(list)) continue;
            const items = [];
            const seenSha = new Set();
            for (const item of list) {
                if (!item || typeof item !== 'object') continue;
                const sha = typeof item.sha256 === 'string' ? item.sha256 : '';
                if (!sha || seenSha.has(sha)) continue;
                seenSha.add(sha);
                const url = typeof item.url === 'string' ? item.url.trim() : '';
                if (!url) continue;
                items.push({
                    id: typeof item.id === 'string' ? item.id.trim() : '',
                    url,
                    sha256: sha,
                    mime: typeof item.mime === 'string' ? item.mime : 'image/png',
                    size: Number.isFinite(Number(item.size)) ? Number(item.size) : 0,
                    uploadedBy: typeof item.uploadedBy === 'string' ? item.uploadedBy : '',
                    createdAt: typeof item.createdAt === 'string' ? item.createdAt : new Date().toISOString(),
                    childIds: Array.isArray(item.childIds) ? item.childIds.filter((x) => typeof x === 'string') : [],
                });
            }
            if (items.length > 0) result[deviceId] = items;
        }
        return result;
    }

    function saveAvatarStore(store) {
        writeJson(avatarFile, store);
    }

    // ------------------------------------------------------------ 卡片图标索引（sha256 → 相对路径）
    function readCardIconStore() {
        const raw = readJson(cardIconFile, {});
        if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return {};
        const out = {};
        for (const [sha, item] of Object.entries(raw)) {
            if (!/^[0-9a-f]{64}$/i.test(sha) || !item || typeof item !== 'object') continue;
            const url = typeof item.url === 'string' ? item.url.trim() : '';
            if (!CARD_ICON_URL_RE.test(url)) continue;
            out[sha.toLowerCase()] = {
                id: typeof item.id === 'string' ? item.id : '',
                url,
                mime: typeof item.mime === 'string' ? item.mime : 'image/png',
                size: Number.isFinite(Number(item.size)) ? Number(item.size) : 0,
                createdAt: typeof item.createdAt === 'string' ? item.createdAt : new Date().toISOString(),
            };
        }
        return out;
    }

    /** 按 family 维度合并头像（同一家长能管的所有 tv 的头像，按 sha256 去重）。 */
    function listAvatarsForParent(parentName) {
        const store = readAvatarStore();
        const machines = readMachines();
        const merged = [];
        const seenSha = new Set();
        for (const [deviceId, items] of Object.entries(store)) {
            const machine = machines[deviceId];
            if (!machine || machineKind(machine) !== 'tv') continue;
            const isOwner = machine.owner === parentName;
            const isParent = Array.isArray(machine.parents) && machine.parents.includes(parentName);
            if (!isOwner && !isParent) continue;
            for (const item of items) {
                if (seenSha.has(item.sha256)) continue;
                seenSha.add(item.sha256);
                merged.push(item);
            }
        }
        return merged;
    }

    /** 图片 magic bytes → mime；不合法返回 null（防止伪装成图片上传任意字节）。 */
    function detectImageMime(buffer) {
        if (!buffer || buffer.length < 8) return null;
        if (buffer[0] === 0x89 && buffer[1] === 0x50 && buffer[2] === 0x4E && buffer[3] === 0x47) return 'image/png';
        if (buffer[0] === 0xFF && buffer[1] === 0xD8 && buffer[2] === 0xFF) return 'image/jpeg';
        if (buffer[0] === 0x52 && buffer[1] === 0x49 && buffer[2] === 0x46 && buffer[3] === 0x46
            && buffer.length >= 12
            && buffer.toString('ascii', 8, 12) === 'WEBP') return 'image/webp';
        // GIF 87a / 89a
        if (buffer[0] === 0x47 && buffer[1] === 0x49 && buffer[2] === 0x46 && buffer[3] === 0x38
            && (buffer[4] === 0x37 || buffer[4] === 0x39) && buffer[5] === 0x61) return 'image/gif';
        return null;
    }

    /**
     * 机器 → 生效配置：机器设置 > 所属用户设置 > 未配置（App 回落 .env）。
     *
     * `allMachines` 可复用调用方已读出的设备表，避免逐台解析时重复读盘
     * （只在设备有共享引用时才会用到）。
     */
    /**
     * D-02 写路径（仅 USE_FAMILY_MODEL 开启时调用）：把进来的整份 parental 配置
     * 拆分写入家庭级存储——children → FamilyChild、分配 → Assignment、本台设置 →
     * DeviceLocal。映射关系严格对应 projectDevice 的投影，保证「写后读」一致。
     * 操作者为家长号；admin 已在调用方被 requireParentWriter 拒绝。
     */
    function applyParentalToFamily(machine, parentalBlob, operator) {
        const normalized = normalizeParental(parentalBlob || {});
        const deviceId = machine.id;
        const childIds = [];
        for (const child of normalized.children) {
            const id = typeof child.id === 'string' ? child.id.trim() : '';
            if (!id) continue;
            familyStore.upsertChild(
                {
                    childId: id,
                    name: child.name,
                    age: child.age,
                    avatarId: child.avatarId,
                    profileMode: child.profileMode,
                    dailyLimitMin: child.dailyLimitMin,
                    sessionLimitMin: child.sessionLimitMin,
                    bedtimeStart: child.bedtimeStart,
                    bedtimeEnd: child.bedtimeEnd,
                    blacklist: child.blacklist,
                    whitelist: child.whitelist,
                    locked: child.locked,
                },
                operator,
            );
            childIds.push(id);
        }
        const existingAssignment = familyStore.data.assignments[deviceId];
        const existingIds = existingAssignment && Array.isArray(existingAssignment.childIds)
            ? existingAssignment.childIds : [];
        // 防御：整份 parental 里 children 为空，多半是客户端只改了本台设置（旧缓存/
        // 旧版 TV 页开关），不能据此清空该电视的档案分配——否则电视端 children 为空，
        // 儿童模式会立即被自动关闭（线上已复现）。清空分配走 assignment 接口。
        if (childIds.length > 0 || existingIds.length === 0) {
            familyStore.setAssignment(deviceId, childIds, operator);
        }
        familyStore.setDeviceLocal(
            deviceId,
            {
                mode: normalized.mode,
                unlockMode: normalized.unlockMode,
                pin: normalized.pin,
                activeChildIds: normalized.activeChildIds && normalized.activeChildIds.length > 0
                    ? normalized.activeChildIds
                    : childIds,
            },
            operator,
        );
    }

    function resolveMachineConfig(machine, usersByName, allMachines) {
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
        // 儿童模式配置：默认沿用旧透传（本机 children + 共享引用展开）。
        // D-02 开启后改走家庭级投影：按 deviceId 取已分配的家庭主档案，
        // 旧 machine.parental 不再作为生效来源（首次启用会原地迁移一次）。
        let parental;
        if (USE_FAMILY_MODEL) {
            if (Object.keys(familyStore.data.children).length === 0) {
                familyStore.migrateFromLegacy(allMachines || readMachines());
            }
            parental = familyStore.projectDevice(machine.id);
        } else {
            parental = machine.parental || null;
            if (parental && Array.isArray(parental.shared) && parental.shared.length > 0) {
                parental = parentalShare.expandSharedChildren(machine, allMachines || readMachines()) || parental;
            }
        }
        return {
            homes,
            source,
            owner,
            parents: machine.parents || (owner ? [owner] : []),
            ownerName: user ? user.displayName || user.name : '',
            layoutKey: owner || `device_${machine.id}`,
            parental,
            // 节目文件版本：保存后时间戳变化，设备据此重新拉取频道（只带版本号，不带文件内容）。
            programsUpdatedAt: programs ? programs.updatedAt() : 0,
            programsRevision: programs ? programs.revision() : 0,
            // 设备类型/布局字典版本：admin 保存类型后递增，home 端据此重新拉取布局，
            // 不必重启 App（只带版本号，不带字典本体）。
            deviceTypesUpdatedAt: deviceTypeService ? deviceTypeService.version() : 0,
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

    // 家长配置写门禁（D-03 只读代管）：仅 parent 角色可写；admin 放行读但禁止写。
    // 只覆盖「家长域配置写接口」（儿童模式 / 档案共享 / 题库 / 头像 / 解锁方式），
    // 不用于用户管理、布局、删机器等管理员后台自有接口（避免误伤）。
    function requireParentWriter(req, res, next) {
        const operator = currentParentOperator(req);
        if (!operator) {
            return jsonFail(res, '未登录或无家长操作权限', 401, 401);
        }
        if (operator.role !== 'parent') {
            return jsonFail(res, '只读代管不支持修改家长配置，请使用家长号操作', 403, 403);
        }
        req.adminUser = operator;
        next();
    }

    // 节目编辑：全局一份，仅 admin 可读写。数据目录沿用线上 screen/datas。
    const programs = attachPrograms(app, {
        screenDir: options.screenDatasDir
            ? path.resolve(options.screenDatasDir)
            : path.join(datasDir, 'screen', 'datas'),
        backupRoot: path.join(datasDir, 'backups', 'programs'),
        stateFile: path.join(adminDir, 'programs_state.json'),
        requireAdmin,
        jsonOk,
        jsonFail,
        // 节目文件变更后给在线 TV / 中控推一次完整 config 帧（含 programsUpdatedAt），
        // 不推文件本体，避免触碰 ws 128KiB 上限。
        pushToOnlineDevices: () => {
            const machines = readMachines();
            let sent = 0;
            for (const machine of Object.values(machines)) {
                if (machineKind(machine) === 'parent') continue;
                sent += pushConfigToMachine(machine) || 0;
            }
            return sent;
        },
    });

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

    // claim ticket 复用会话的 HMAC 密钥，但加独立前缀：带上前缀的串无法被
    // verifySession() 解析，因此即便被塞进 pk_admin cookie 也不能冒充登录态。
    const claimTicketsFile = path.join(adminDir, 'claim_tickets.json');

    function signClaimTicket(account) {
        const payload = {
            u: account,
            exp: nowMs() + CLAIM_TICKET_TTL_MS,
            kind: 'claim',
            jti: crypto.randomBytes(16).toString('hex'),
        };
        return CLAIM_TOKEN_PREFIX + signSession(payload);
    }

    function verifyClaimTicket(token, account) {
        if (typeof token !== 'string' || !token.startsWith(CLAIM_TOKEN_PREFIX)) return null;
        const payload = verifySession(token.slice(CLAIM_TOKEN_PREFIX.length));
        if (!payload || payload.kind !== 'claim' || payload.u !== account) return null;
        if (typeof payload.jti !== 'string' || !payload.jti) return null;
        return payload;
    }

    // ------------------------------------------------------------ Admin API

    // 设置家长号（route 2 / claim）：设备派生号与家长号是两层身份，互不替代。
    // 派生号（设备身份证，实时通道恒用）永不改名/禁用；这里只新建家长号账号，
    // 并把「家长可见性绑定」从派生号映射到家长号。口令由用户自设、可跨设备登录。
    // 认证来源是已登录的 pk_admin 会话，不碰 /api/login，也不改中控端登录链路。
    app.post('/api/admin/claim/ticket', requireParentOperator, (req, res) => {
        try {
            const name = req.adminUser.name;
            const info = readUserInfo(name);
            if (req.adminUser.role !== 'parent' || !claims.isDerivedAccount(name)) {
                return jsonFail(res, '只有设备自举的家长账号可以设置家长号', 403, 403);
            }
            // 已通过家长号登录（req.adminUser.name 非派生号）时无需再领票；
            // 派生号已关联过家长号时也不允许重复关联，改口令走独立接口。
            if (info.parentAccount || info.claimedAt || info.claimedTo) {
                return jsonFail(res, '该设备已关联过家长号，改口令请在设置页操作', 403, 403);
            }
            return jsonOk(res, {
                claimToken: signClaimTicket(name),
                expiresIn: Math.round(CLAIM_TICKET_TTL_MS / 1000),
            });
        } catch (error) {
            console.error('[admin] 签发 claim 凭证失败:', error);
            return jsonFail(res, error.message);
        }
    });

    app.post('/api/admin/claim', requireParentOperator, (req, res) => {
        try {
            const oldName = req.adminUser.name;
            const body = req.body || {};
            const payload = verifyClaimTicket(body.claimToken, oldName);
            if (!payload) return jsonFail(res, '凭证无效或已过期，请重新获取', 403, 403);
            const verdict = claims.validateClaimName(body.account, {
                adminUsername: ADMIN_USERNAME,
                accountExists: (name) => fs.existsSync(passwordPath(name)),
            });
            if (!verdict.ok) return jsonFail(res, verdict.reason);
            // 家长号口令由用户自设（不再服务端随机下发只存本机）：换设备凭
            // 「家长号 + 自设口令」即可登录，不再有「重装即锁死」的问题。
            const password = String(body.password || '');
            if (password.length < 6 || password.length > 128) {
                return jsonFail(res, '家长号口令需为 6-128 位');
            }
            if (password === '123456') {
                return jsonFail(res, '家长号口令不能与设备默认口令相同，请自设一个');
            }
            const info = readUserInfo(oldName);
            if (req.adminUser.role !== 'parent' || !claims.isDerivedAccount(oldName)
                || info.role !== 'parent' || info.parentAccount || info.claimedAt || info.claimedTo) {
                return jsonFail(res, '该设备不能重复关联家长号', 403, 403);
            }
            // 先核销 jti 再建档：并发重复提交只会有一个请求真正生效。
            if (!claims.consumeTicket(claimTicketsFile, payload.jti, nowMs(), CLAIM_TICKET_TTL_MS)) {
                return jsonFail(res, '凭证已被使用，请重新获取', 403, 403);
            }
            const result = claims.applyAccountRename({
                datasDir,
                registerUsersDir,
                oldName,
                newName: verdict.name,
                newPasswordMd5: hashPassword(password),
            });
            // 管理会话切到家长号：后续 /api/admin/* 的可见性按 machine.parents
            // （已映射到家长号）判定。实时通道另用派生号 + principal 握手，不受影响。
            setSessionCookie(res, verdict.name);
            console.log(`[admin] 家长号关联: 派生号 ${oldName} -> ${verdict.name} 备份=${result.backupDir}`);
            return jsonOk(res, {
                account: verdict.name,
                changed: result.changed,
            }, '家长号已设置');
        } catch (error) {
            console.error('[admin] 设置家长号失败:', error);
            return jsonFail(res, error.message);
        }
    });

    // 家长号改口令：已用「家长号 + 旧口令」登录后即可自设新口令。
    // 派生号账号本身保持默认口令不变（实时通道恒用），这里只动家长号这一层。
    app.post('/api/admin/parent-account/password', requireParentOperator, (req, res) => {
        try {
            const name = req.adminUser.name;
            const info = readUserInfo(name);
            if (req.adminUser.role !== 'parent' || !info || info.role !== 'parent'
                || claims.isDerivedAccount(name)) {
                return jsonFail(res, '请先使用家长号登录', 403, 403);
            }
            const body = req.body || {};
            const current = String(body.currentPassword || '');
            const next = String(body.newPassword || '');
            // 与 /api/login、ws 握手同一校验源：账号文件里存的就是口令 MD5。
            const stored = fs.existsSync(passwordPath(name))
                ? fs.readFileSync(passwordPath(name), 'utf8').trim()
                : '';
            if (stored !== hashPassword(current)) {
                return jsonFail(res, '当前口令不正确');
            }
            if (next.length < 6 || next.length > 128 || next === '123456') {
                return jsonFail(res, '新口令需为 6-128 位且不同于默认口令');
            }
            fs.writeFileSync(passwordPath(name), hashPassword(next), 'utf8');
            console.log(`[admin] 家长号改口令: ${name}`);
            return jsonOk(res, { account: name }, '口令已更新');
        } catch (error) {
            console.error('[admin] 家长号改口令失败:', error);
            return jsonFail(res, error.message);
        }
    });

    // 公开自助注册已关闭：过去开放此端点产生了大量无人认领的账号。
    // 家长登录名改由 /api/admin/claim 的 ticket 流程产生；这里仅允许管理员补建账号。
    app.post('/api/admin/register', requireAdmin, (req, res) => {
        try {
            const username = safeUsername(req.body ? req.body.username : '');
            const password = typeof req.body?.password === 'string' ? req.body.password.trim() : '';
            if (!username) {
                return jsonFail(res, '用户名需为 2-64 位字母、数字、下划线或中文');
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
        const isParent = admin.role === 'parent';
        const users = listUsers();
        const usersByName = new Map(users.map((user) => [user.name, user]));
        const machineMap = readMachines();
        const allMachines = Object.values(machineMap).map((machine) => {
            const config = resolveMachineConfig(machine, usersByName, machineMap);
            // 别名是家长私有数据：只回传当前操作者自己的那一条，绝不把
            // aliases 整表（含其他家长的别名）下发给前端。
            const alias = (machine.aliases && machine.aliases[admin.name]) || '';
            const machineFields = { ...machine };
            delete machineFields.aliases;
            // 管理员额外拿到只读的完整别名表（家长仍只拿自己那一条），
            // 供后台排查「这台电视在谁那里叫什么」，不影响设备备注。
            if (admin.role === 'admin') machineFields.aliases = machine.aliases || {};
            // 档案引用共享：为电视展开家长端共享视图（主本 + 引用 + 可引用候选）。
            // 只做派生，不落盘；viewer 为当前家长号，引用可见性按 source.sharedTo 白名单校验。
            const shareView = machineKind(machine) === 'tv'
                ? parentalShare.buildShareView(machine, machineMap, admin.name)
                : null;
            return {
                ...machineFields,
                alias,
                kind: machineKind(machine),
                ownerName: config.ownerName,
                parentalShareView: shareView,
                // 设备通信账号的展示名（后台设备列表 / 家长端按此列回落）。
                commDisplayName: usersByName.get(machine.commAccount)?.displayName || '',
                parents: config.parents,
                effectiveHomes: config.homes,
                homesSource: config.source,
                layoutKey: config.layoutKey,
                online: machine.lastSeen > 0 && nowMs() - machine.lastSeen < MACHINE_ONLINE_MS,
            };
        });
        allMachines.sort((a, b) => {
            if (a.online !== b.online) return a.online ? -1 : 1;
            return (b.lastSeen || 0) - (a.lastSeen || 0);
        });
        // 家长只能看到绑定到自己名下的电视；中控设备不参与家长绑定。
        // 未绑定的电视单独给出，供家长自助认领。
        const tvMachines = allMachines.filter((machine) => machine.kind === 'tv');
        const machines = isParent
            ? tvMachines.filter((machine) => machine.parents.includes(admin.name))
            : allMachines;
        // 一台电视可被多个家长绑定，家长也可绑定任意多台电视：未包含当前
        // 家长的电视都作为「可加入」项返回，不再要求设备完全未绑定。
        const availableMachines = isParent
            ? tvMachines.filter((machine) => !machine.parents.includes(admin.name))
            : [];

        // 账号 → 关联设备（通信账号或所属中控）：后台用户列表展示设备备注名用。
        const machinesByAccount = new Map();
        for (const machine of machines) {
            const keys = new Set([machine.commAccount, machine.owner].filter(Boolean));
            for (const key of keys) {
                const list = machinesByAccount.get(key) || [];
                if (!list.some((item) => item.id === machine.id)) {
                    list.push({ id: machine.id, name: machine.name, nameSet: machine.nameSet });
                }
                machinesByAccount.set(key, list);
            }
        }

        const homeSet = new Set();
        for (const machine of machines) {
            for (const home of machine.knownHomes) homeSet.add(home);
            if (machine.homes) for (const home of machine.homes) homeSet.add(home);
        }
        for (const user of (isParent ? users.filter((item) => item.name === admin.name) : users)) {
            if (user.homes) for (const home of user.homes) homeSet.add(home);
        }
        const homes = Array.from(homeSet).sort((a, b) => a.localeCompare(b, 'zh-CN'));

        const allLayouts = Object.entries(readLayouts()).map(([key, layout]) => ({
            key,
            owner: key.startsWith('device_') ? '' : key,
            ...layout,
        }));
        // 家长只能看到自己账号名下 / 自己绑定设备的布局，避免顺带拿到全部
        // 家庭的数据（布局 Tab 本身已对家长隐藏，这里做服务端兜底）。
        const layouts = isParent
            ? allLayouts.filter(
                (layout) => layout.owner === admin.name || machines.some((machine) => machine.layoutKey === layout.key),
            )
            : allLayouts;

        const realtime = onlineAccounts() || [];
        const visibleAccounts = new Set([admin.name]);
        for (const machine of machines) {
            if (machine.commAccount) visibleAccounts.add(machine.commAccount);
            visibleAccounts.add(machine.id);
        }
        return {
            serverTime: nowMs(),
            admin,
            users: (isParent ? users.filter((user) => user.name === admin.name) : users).map((user) => ({
                ...user,
                machineCount: tvMachines.filter((machine) => machine.parents.includes(user.name)).length,
                machines: machinesByAccount.get(user.name) || [],
            })),
            machines,
            availableMachines,
            homes,
            layouts,
            realtimeOnline: isParent ? realtime.filter((account) => visibleAccounts.has(account)) : realtime,
            stats: {
                users: isParent ? 1 : users.length,
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

    // ------------------------------------------------------------ 智能场景引擎

    /** ESP 小屏列表：感应实体与「感应/按键」触发源都从这里选。 */
    function espMachines() {
        return Object.values(readMachines()).filter((machine) => isEspMachine(machine));
    }

    // 只翻译最常见的几个，其余原样露出 service 名（自定义动作不该被硬编码挡住）。
    const HA_ACTION_TEXT = { turn_on: '开', turn_off: '关', toggle: '切换', run: '执行' };

    /** 动作的人话标签：卡片摘要、执行结果、日志三处共用。 */
    function sceneActionLabel(action) {
        if (!action) return '';
        if (action.label) return action.label;
        if (action.type === 'delay') return `等待 ${action.seconds} 秒`;
        if (action.type === 'ha') {
            const text = HA_ACTION_TEXT[action.action] || action.action;
            return `${action.entityId} ${text}${action.param ? `(${action.param})` : ''}`;
        }
        if (action.type === 'remote') {
            const target = readMachines()[action.target];
            const cmd = REMOTE_CMD_MAP.get(action.action);
            return `${target ? (target.name || target.id) : action.target} ${cmd ? cmd.label : action.action}`;
        }
        return '';
    }

    /**
     * 场景动作执行：直接复用 ESP 按键那两条路径（HA / 遥控），
     * 不另写一套，避免同一个动作在按键和自动化里行为不一致。
     *
     * 与按键的一处差异：遥控送达数为 0 在这里算失败。按键是「有人在屏前按，
     * 提示已发送即可」；自动化没人看着，发出去了却没人接，等于没做到，
     * 应该让卡片标红而不是假装成功。
     */
    async function runSceneAction(action) {
        if (!action || typeof action !== 'object') throw new Error('动作配置无效');
        if (action.type === 'ha') {
            await callHaService(action.entityId, action.action, action.param);
            return;
        }
        if (action.type === 'remote') {
            const target = readMachines()[action.target];
            if (!target) throw new Error('绑定的中控/电视已不存在');
            if (target.kind !== 'home' && target.kind !== 'tv') throw new Error('绑定的设备不是中控或电视');
            if (!remoteCapabilities(target.kind).some((item) => item.cmd === action.action)) {
                throw new Error(`${target.name || '目标设备'} 不支持「${action.action}」`);
            }
            const account = target.commAccount || '';
            if (!account) throw new Error('目标设备缺少通信账号，请让它重新连接一次');
            const lastSeen = Number(target.lastSeen) || 0;
            if (!lastSeen || nowMs() - lastSeen > MACHINE_ONLINE_MS) {
                throw new Error(`${target.name || '目标设备'} 离线`);
            }
            const frame = {
                t: 'msg',
                from: 'scene',
                to: account,
                body: JSON.stringify({ t: 'cmd', name: action.action, args: remoteCommandArgs(action) }),
                ts: nowMs(),
            };
            const delivered = pushRemoteCommand(account, frame) || 0;
            if (!delivered) throw new Error(`${target.name || '目标设备'} 暂无在线连接`);
            return;
        }
        throw new Error(`不支持的动作类型：${action.type}`);
    }

    /** 保存时校验遥控目标，避免存进一个永远失败的动作（设计文档第七节）。 */
    function checkSceneRemote(targetId, cmd, index) {
        const machines = readMachines();
        const target = machines[targetId];
        if (!target) throw new Error(`第 ${index} 个动作：绑定的设备不存在，请重新选择`);
        if (target.kind !== 'home' && target.kind !== 'tv') {
            throw new Error(`第 ${index} 个动作：只能遥控中控或电视`);
        }
        if (!remoteCapabilities(target.kind).some((item) => item.cmd === cmd)) {
            throw new Error(`第 ${index} 个动作：${target.name || '目标设备'} 不支持该命令`);
        }
    }

    // 场景条件的实体状态来源，与 ESP「插入实体」弹窗里的遥控伪实体同源：
    // HA 实体走 haCatalogService.getStates；remote.<设备>.<字段> 走机器表反查。
    const sceneReadRemoteState = (entityId) => {
        const match = /^remote\.([a-z0-9_]+)(?:\.([a-z]+))?$/i.exec(String(entityId || ''));
        if (!match) return '';
        const machines = readMachines();
        const machine = Object.values(machines).find((m) => remoteEntityId(m.id) === `remote.${match[1].toLowerCase()}`);
        if (!machine || (machine.kind !== 'home' && machine.kind !== 'tv')) return '';
        const fields = remoteStateFields(remoteStateOf(machine.commAccount || ''));
        if (match[2] && REMOTE_STATE_FIELDS.includes(match[2])) return fields[match[2]] || '';
        return fields.text || '';
    };

    const sceneEngine = attachScenes({
        file: scenesFile,
        runAction: runSceneAction,
        listMachines: espMachines,
        labelOf: sceneActionLabel,
        checkRemote: checkSceneRemote,
        getStates: (ids) => haCatalogService.getStates(ids),
        readRemoteState: sceneReadRemoteState,
        log: (message) => console.log(`[scenes] ${message}`),
    });

    // 1 秒推进 holdSec 计时（定时触发的 30 秒节流在引擎内部）。unref 让进程不被它挂住。
    const sceneTickTimer = setInterval(() => {
        try {
            sceneEngine.tick();
        } catch (error) {
            console.error('[scenes] tick 失败:', error.message);
        }
    }, 1000);
    if (typeof sceneTickTimer.unref === 'function') sceneTickTimer.unref();

    /**
     * 轻量人体感应状态：admin 设备列表高频轮询专用。
     *
     * 上游固件在 PIR 电平跳变时立刻发心跳（不受 60 秒心跳影响），所以链路本身
     * 是秒级的；界面的滞后完全取决于这个轮询间隔。走 buildOverview 太重
     * （整机列表 + 页面配置），这里只回 id + espPresence。
     */
    app.get('/api/admin/esp/presence', requireParentOperator, (req, res) => {
        try {
            // 感应四态（有人/无人/休眠/离线）统一走场景引擎的归一化，前端只管展示。
            const entityById = new Map(sceneEngine.presenceEntities()
                .map((entity) => [entity.deviceId, entity]));
            const devices = Object.values(readMachines())
                .filter((machine) => isEspMachine(machine))
                .map((machine) => {
                    const entity = entityById.get(machine.id);
                    return {
                        id: machine.id,
                        espPresence: normalizeEspPresence(machine.espPresence),
                        // 兼容旧字段：online = 心跳窗口内；sleeping = 深睡从机休眠窗口内。
                        online: entity ? entity.online
                            : (Boolean(machine.lastSeen) && nowMs() - machine.lastSeen <= MACHINE_ONLINE_MS),
                        sleeping: entity ? Boolean(entity.sleeping) : false,
                        // presenceState：present/absent/sleep/unknown，没上报过感应为 null。
                        presenceState: entity ? entity.presence : null,
                        presenceText: entity ? entity.presenceText : '',
                        lastSeen: machine.lastSeen || 0,
                    };
                });
            return jsonOk(res, { devices });
        } catch (error) {
            console.error('[admin] 读取感应状态失败:', error);
            return jsonFail(res, error.message);
        }
    });

    // ------------------------------------------------------------ 智能 Tab 接口

    /**
     * 场景列表：一次拉全量（量级小），前端切 Tab 时调一次就够。
     * 顺带回感应实体与全局设置，省掉两次请求。
     */
    app.get('/api/admin/scenes', requireParentOperator, (req, res) => {
        try {
            return jsonOk(res, {
                scenes: sceneEngine.list(),
                settings: sceneEngine.settings(),
                presence: sceneEngine.presenceEntities(),
            });
        } catch (error) {
            console.error('[admin] 读取场景失败:', error);
            return jsonFail(res, error.message);
        }
    });

    /** 全局设置只有一项：occupied 判空闲窗口（秒）。 */
    app.put('/api/admin/scenes/settings', requireParentOperator, (req, res) => {
        try {
            return jsonOk(res, sceneEngine.setSettings(req.body || {}), '已保存');
        } catch (error) {
            return jsonFail(res, error.message);
        }
    });

    app.post('/api/admin/scenes', requireParentOperator, (req, res) => {
        try {
            return jsonOk(res, sceneEngine.create(req.body || {}), '已创建');
        } catch (error) {
            return jsonFail(res, error.message);
        }
    });

    app.put('/api/admin/scenes/:id', requireParentOperator, (req, res) => {
        try {
            return jsonOk(res, sceneEngine.update(String(req.params.id || ''), req.body || {}), '已保存');
        } catch (error) {
            return jsonFail(res, error.message);
        }
    });

    app.delete('/api/admin/scenes/:id', requireParentOperator, (req, res) => {
        try {
            return jsonOk(res, sceneEngine.remove(String(req.params.id || '')), '已删除');
        } catch (error) {
            return jsonFail(res, error.message);
        }
    });

    /** 开关单独一条：列表上高频点，避免整表覆盖把别人的编辑冲掉。 */
    app.patch('/api/admin/scenes/:id/enabled', requireParentOperator, (req, res) => {
        try {
            const body = req.body || {};
            return jsonOk(res, sceneEngine.setEnabled(String(req.params.id || ''), body.enabled), '已更新');
        } catch (error) {
            return jsonFail(res, error.message);
        }
    });

    /**
     * 执行 / 试运行。手动执行 force=true，忽略 enabled 与冷却；
     * 返回逐步结果，前端按 steps 渲染哪一步失败、失败原因。
     */
    app.post('/api/admin/scenes/:id/run', requireParentOperator, async (req, res) => {
        try {
            const result = await sceneEngine.run(String(req.params.id || ''), { reason: 'manual', force: true });
            if (result.skipped) return jsonFail(res, result.reason);
            return jsonOk(res, result, result.ok ? '已执行' : '部分动作失败');
        } catch (error) {
            console.error('[admin] 执行场景失败:', error.message);
            return jsonFail(res, error.message);
        }
    });

    /**
     * 感应实体（虚拟，不是 HA 实体）。
     *
     * `presence` 是传感器电平，人坐着不动 2 秒就会变无人；`occupied` 是
     * 「最近 occupiedWindowSec 秒内出现过有人」的去抖值，判断「人还在不在」用它。
     */
    app.get('/api/admin/presence/entities', requireParentOperator, (req, res) => {
        try {
            return jsonOk(res, {
                windowSec: sceneEngine.settings().occupiedWindowSec,
                entities: sceneEngine.presenceEntities(),
            });
        } catch (error) {
            return jsonFail(res, error.message);
        }
    });

    /** 儿童模式相关查询只涉及电视设备（中控不参与）。 */
    function scopedMachines(user) {
        const tvs = Object.values(readMachines()).filter((machine) => isTvMachine(machine));
        if (user.role === 'admin') return tvs;
        return tvs.filter((machine) => machine.parents.includes(user.name));
    }

    /** 设备对应的通信账号集合：事件 from/to 命中任一即可纳入记录。 */
    function machineAccounts(machines) {
        const accounts = new Set();
        for (const machine of machines) {
            if (machine.commAccount) accounts.add(machine.commAccount);
            accounts.add(machine.id);
        }
        return Array.from(accounts);
    }

    function machineForEvent(machines, event) {
        return machines.find((machine) => machine.commAccount === event.from || machine.id === event.from);
    }

    /**
     * 从 `parental_watch` 心跳还原会话级观看记录。
     *
     * 心跳里带每个孩子的累计 `sessionSec`，因此可用 `event.ts - sessionSec`
     * 反推本次会话起点；同一孩子会话内的心跳会命中同一段时间窗。
     */
    function deriveParentalSessions(machines, events) {
        const sessions = [];
        const lastByChild = new Map();
        const seen = new Set();
        const sorted = events
            .filter((event) => event && event.event === 'parental_watch' && event.data)
            .sort((a, b) => a.ts - b.ts);
        for (const event of sorted) {
            // 兼容旧版按家长扇出时落库的副本：同一事件 id 只处理一次。
            if (event.id) {
                if (seen.has(event.id)) continue;
                seen.add(event.id);
            }
            const machine = machineForEvent(machines, event);
            if (!machine) continue;
            const data = event.data || {};
            const childIds = Array.isArray(data.childIds) ? data.childIds : [];
            const sessionSecByChild = data.sessionSecByChild && typeof data.sessionSecByChild === 'object'
                ? data.sessionSecByChild
                : {};
            const dailySecByChild = data.dailySecByChild && typeof data.dailySecByChild === 'object'
                ? data.dailySecByChild
                : {};
            for (const childId of childIds) {
                const sessionSec = Number(sessionSecByChild[childId]);
                if (!Number.isFinite(sessionSec) || sessionSec <= 0) continue;
                const startMs = event.ts - sessionSec * 1000;
                // 时长按「主本档案坐标」归并：引用档案归到来源电视 / 主本档案，
                // 使同一档案在客厅 + 卧室的观看会话累加到同一条（每日限额共用）。
                // 实际观看的电视仍记录在本条 session 的 machineId/machineName（分台明细）。
                const anchor = parentalShare.durationAnchorKey(machine, readMachines(), childId);
                const key = anchor;
                const anchorChildId = anchor.slice(anchor.indexOf(':') + 1);
                const last = lastByChild.get(key);
                if (last && Math.abs(last.startMs - startMs) < 120000) {
                    last.endMs = Math.max(last.endMs, event.ts);
                    last.durationSec = Math.max(last.durationSec, sessionSec);
                    last.dailySec = Math.max(last.dailySec, Number(dailySecByChild[childId]) || 0);
                    continue;
                }
                const resolved = parentalShare.resolveChild(machine, readMachines(), childId, null);
                const child = resolved.kind === 'master' ? resolved.child
                    : resolved.kind === 'shared' ? resolved.child
                        : (machine.parental && machine.parental.children || []).find((item) => item.id === childId);
                const session = {
                    machineId: machine.id,
                    machineName: machine.name,
                    // anchorKey / anchorChildId：家长端据此跨电视合并时长。
                    anchorKey: anchor,
                    anchorChildId,
                    childId,
                    childName: child ? child.name : childId,
                    date: data.date || '',
                    startMs,
                    endMs: event.ts,
                    durationSec: sessionSec,
                    dailySec: Number(dailySecByChild[childId]) || 0,
                };
                sessions.push(session);
                lastByChild.set(key, session);
            }
        }
        sessions.sort((a, b) => b.endMs - a.endMs);
        return sessions.slice(0, 200);
    }

    app.get('/api/admin/parental/records', requireParentOperator, (req, res) => {
        try {
            const user = req.adminUser;
            const machines = scopedMachines(user);
            const accounts = machineAccounts(machines);
            // 观看心跳改为 25 秒后，放宽到内存上限 5000 条以保留接近一天的会话。
            const limit = Math.min(Math.max(parseInt(req.query.limit, 10) || 5000, 1), 5000);
            const watch = eventsForAccounts(accounts, { event: 'parental_watch', limit });
            const unlock = eventsForAccounts(accounts, { event: 'parental_unlock_request', limit });
            // 电视端同一解锁请求会「owner 直投 + 管理员」双发（id 不同、短码
            // 相同），按短码去重，避免记录页出现两条一样的请求。
            const unlockSeen = new Set();
            const uniqueUnlock = unlock.filter((event) => {
                const code = String((event.data && event.data.code) || '').trim();
                const key = code ? `${event.from}|${code}` : (event.id || `${event.ts}`);
                if (unlockSeen.has(key)) return false;
                unlockSeen.add(key);
                return true;
            });
            return jsonOk(res, {
                machines: machines.map((machine) => ({
                    ...machine,
                    online: machine.lastSeen > 0 && nowMs() - machine.lastSeen < MACHINE_ONLINE_MS,
                })),
                sessions: deriveParentalSessions(machines, watch),
                unlockRequests: uniqueUnlock.map((event) => {
                    const machine = machineForEvent(machines, event);
                    return {
                        ...event,
                        machineName: machine ? machine.name : '',
                    };
                }),
            });
        } catch (error) {
            console.error('[admin] 读取家长记录失败:', error);
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

    // 上传镜像转发状态（只读，admin 权限；不含 serviceToken 明文）。
    app.get('/api/admin/forward/status', requireAdmin, (req, res) => {
        try {
            if (!forward) return jsonFail(res, '镜像转发未启用');
            return jsonOk(res, forward.status());
        } catch (error) {
            console.error('[admin] 读取镜像转发状态失败:', error);
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
                // 空串 = 清除展示名，回落账号 id（与本人自助改名接口口径一致）。
                const nextDisplayName = String(req.body.displayName || '').trim().slice(0, 40);
                if (nextDisplayName) info.displayName = nextDisplayName;
                else delete info.displayName;
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
            const isParent = req.adminUser.role === 'parent';
            const kind = machineKind(machine);
            if (isParent && !machine.parents.includes(req.adminUser.name)) {
                return jsonFail(res, '家长只能编辑已绑定到自己名下的设备', 403, 403);
            }
            if (kind === 'home' && Object.prototype.hasOwnProperty.call(req.body || {}, 'parents')) {
                return jsonFail(res, '中控设备不支持绑定家长');
            }
            if (kind === 'home' && Object.prototype.hasOwnProperty.call(req.body || {}, 'parental')) {
                return jsonFail(res, '中控设备没有儿童模式');
            }
            if (kind === 'parent' && Object.prototype.hasOwnProperty.call(req.body || {}, 'parents')) {
                return jsonFail(res, '家长端设备不支持绑定家长');
            }
            if (kind === 'parent' && Object.prototype.hasOwnProperty.call(req.body || {}, 'parental')) {
                return jsonFail(res, '家长端设备没有儿童模式');
            }

            if (Object.prototype.hasOwnProperty.call(req.body || {}, 'name')) {
                // 空值 = 清除备注：normalizeMachine 会把 name 回落成占位符并置
                // nameSet=false，不再把「未命名设备」当成用户设置的真名。
                machine.name = String(req.body.name || '').trim().slice(0, MAX_MACHINE_NAME);
            }
            if (Object.prototype.hasOwnProperty.call(req.body || {}, 'owner')) {
                // 归属变更会重排 parents，家长无权改写（否则可挤掉其他家长）。
                if (isParent) return jsonFail(res, '家长不能修改设备归属', 403, 403);
                const owner = String(req.body.owner || '').trim();
                if (owner && !usersByName.has(owner)) {
                    return jsonFail(res, '所属用户不存在');
                }
                machine.owner = owner;
            }
            if (Object.prototype.hasOwnProperty.call(req.body || {}, 'parents')) {
                const raw = req.body.parents;
                if (!Array.isArray(raw)) return jsonFail(res, 'parents 必须是账号数组');
                const requested = normalizeStringList(raw, MAX_PARENT_ACCOUNTS);
                for (const name of requested) {
                    const user = usersByName.get(name);
                    if (!user) return jsonFail(res, `家长账号不存在：${name}`);
                    if (user.role !== 'parent' && user.role !== 'admin') {
                        return jsonFail(res, `账号不是家长角色：${name}`);
                    }
                }
                if (isParent) {
                    const self = req.adminUser.name;
                    const others = machine.parents.filter((name) => name !== self);
                    if (requested.some((name) => name !== self)) {
                        return jsonFail(res, '家长只能绑定自己，其他家长需由管理员分配', 403, 403);
                    }
                    // 已有其他家长时只允许增删自己，不能把别人挤掉。
                    machine.parents = others.concat(requested.includes(self) ? [self] : []);
                } else {
                    machine.parents = requested;
                }
            }
            if (Object.prototype.hasOwnProperty.call(req.body || {}, 'homes')) {
                machine.homes = normalizeHomes(req.body.homes);
            }
            // 儿童模式配置（方案 §2.2 三处小改之一）：body 给 parental 对象则校验后
            // 整体替换（整对象替换语义，后台表单先读后改再全量回传）；给 null 清除；
            // 不给该键则保持原值。校验失败 throw → 走下方 catch 整体拒绝，不落盘。
            if (Object.prototype.hasOwnProperty.call(req.body || {}, 'parental')) {
                // D-03 只读代管：admin 可看全量但禁止写家长配置。
                if (req.adminUser.role === 'admin') {
                    return jsonFail(res, '只读代管不支持修改儿童模式配置，请使用家长号操作', 403, 403);
                }
                if (USE_FAMILY_MODEL) {
                    // D-02 写路径：把整份 parental 拆分写入家庭级存储
                    // （children→FamilyChild / 分配→Assignment / 本台设置→DeviceLocal），
                    // 不再以 machine.parental 为生效来源。读路径由 resolveMachineConfig
                    // 改走 projectDevice 投影。这里把投影写回 machine.parental，使响应
                    // 回声与 GET /config 一致（客户端 saveParental 据此回读校验）。
                    applyParentalToFamily(machine, req.body.parental, req.adminUser.name);
                    machine.parental = familyStore.projectDevice(machine.id);
                } else {
                    machine.parental = normalizeParental(req.body.parental);
                }
            }
            machines[id] = normalizeMachine(id, machine);
            saveMachines(machines);
            console.log(`[admin] 更新设备 ${id}: parents=${JSON.stringify(machine.parents)} homes=${JSON.stringify(machine.homes)} parental=${machine.parental ? machine.parental.mode : 'null'}`);
            pushConfigToMachine(machines[id], { reason: 'machine' });
            return jsonOk(res, { machine: machines[id] });
        } catch (error) {
            console.error('[admin] 更新设备失败:', error);
            return jsonFail(res, error.message);
        }
    });

    /**
     * 家长私有别名（方案 B）：只写当前操作者自己的 `aliases[账号]`，
     * 不改设备全局备注 `machine.name`，也不影响其他家长看到的名称。
     *
     * 权限与改名一致：家长必须是该设备的绑定家长；管理员可写任意设备
     *（写的是管理员自己账号下的别名）。
     */
    app.put('/api/admin/machines/:id/alias', requireParentOperator, (req, res) => {
        try {
            const id = safeDeviceId(req.params.id);
            if (!id) return jsonFail(res, '设备 ID 无效');
            const machines = readMachines();
            const machine = machines[id];
            if (!machine) return jsonFail(res, '设备不存在');
            const operator = req.adminUser;
            if (operator.role !== 'admin' && !machine.parents.includes(operator.name)) {
                return jsonFail(res, '只能给已绑定到自己名下的设备设置别名', 403, 403);
            }
            const alias = String((req.body && req.body.alias) || '').trim().slice(0, MAX_ALIAS_LENGTH);
            const nextAliases = { ...(machine.aliases || {}) };
            if (alias) nextAliases[operator.name] = alias;
            else delete nextAliases[operator.name];
            machine.aliases = nextAliases;
            machines[id] = normalizeMachine(id, machine);
            saveMachines(machines);
            const deviceAccount = machines[id].commAccount || id;
            console.log(`[admin] 设备别名 ${id} ${operator.name}=${alias || '(清除)'}`);
            // 只通知改名者自己的连接：别名是私有数据，不能发给其他家长。
            if (typeof options.pushAlias === 'function') {
                options.pushAlias(operator.name, { id, account: deviceAccount, alias });
            }
            return jsonOk(res, { id, alias });
        } catch (error) {
            console.error('[admin] 更新设备别名失败:', error);
            return jsonFail(res, error.message);
        }
    });

    // ------------------------------------------------------------ 档案引用共享

    /** 家长可写某台电视：必须是绑定家长；管理员放行。 */
    function canManageTv(req, machine) {
        if (!machine) return false;
        if (req.adminUser.role === 'parent') return Array.isArray(machine.parents) && machine.parents.includes(req.adminUser.name);
        return true;
    }

    /**
     * 设置本台某个主本档案的「对外分享」家长号白名单（owner opt-in）。
     * 只能改本台 children[] 里的主本档案；引用来的档案无权设置。
     */
    app.put('/api/admin/parental/share-to', requireParentWriter, (req, res) => {
        try {
            const body = req.body || {};
            const id = safeDeviceId(body.deviceId);
            const childId = String(body.childId || '').trim();
            if (!id) return jsonFail(res, 'deviceId 无效');
            if (!childId) return jsonFail(res, 'childId 无效');
            const machines = readMachines();
            const machine = machines[id];
            if (!machine) return jsonFail(res, '设备不存在', 404, 404);
            if (machineKind(machine) !== 'tv') return jsonFail(res, '只有电视设备支持儿童档案');
            if (!canManageTv(req, machine)) return jsonFail(res, '只能管理绑定到自己名下的电视', 403, 403);
            const children = machine.parental && Array.isArray(machine.parental.children) ? machine.parental.children : [];
            const child = children.find((c) => c.id === childId);
            if (!child) return jsonFail(res, '本台主本档案不存在（引用档案不能设置分享）', 404, 404);
            child.sharedTo = parentalShare.normalizeSharedTo(body.sharedTo, 'sharedTo');
            machines[id] = normalizeMachine(id, machine);
            saveMachines(machines);
            const view = parentalShare.buildShareView(machines[id], machines, req.adminUser.name);
            console.log(`[share] ${req.adminUser.name} 设置 ${id}/${childId} sharedTo=${JSON.stringify(child.sharedTo)}`);
            return jsonOk(res, { deviceId: id, childId, sharedTo: child.sharedTo, view }, '分享范围已保存');
        } catch (error) {
            console.error('[share] 设置分享范围失败:', error);
            return jsonFail(res, error.message);
        }
    });

    /**
     * 添加一条引用：当前家长在自己绑定的目标电视上，引用一个可见的主本档案。
     * 可见性：来源档案是同一家长号名下其它电视（默认可见），或来源档案 sharedTo 含当前家长号。
     * 只引用主本（来源 children[]），不允许引用别人「引用进来」的档案（杜绝多级链与环）。
     */
    app.post('/api/admin/parental/shared', requireParentWriter, (req, res) => {
        try {
            const body = req.body || {};
            const id = safeDeviceId(body.deviceId);
            const fromMachineId = safeDeviceId(body.fromMachineId);
            const fromChildId = String(body.fromChildId || '').trim();
            if (!id || !fromMachineId || !fromChildId) return jsonFail(res, 'deviceId / fromMachineId / fromChildId 不能为空');
            if (id === fromMachineId) return jsonFail(res, '不能引用本台自己的档案');
            const machines = readMachines();
            const machine = machines[id];
            if (!machine) return jsonFail(res, '目标电视不存在', 404, 404);
            if (machineKind(machine) !== 'tv') return jsonFail(res, '只有电视设备支持档案引用');
            if (!canManageTv(req, machine)) return jsonFail(res, '只能管理绑定到自己名下的电视', 403, 403);
            const source = machines[fromMachineId];
            if (!source || machineKind(source) !== 'tv') return jsonFail(res, '来源电视不存在', 404, 404);
            // 来源档案必须是主本（children[]），不能是引用（shared[]）。
            const sourceChildren = source.parental && Array.isArray(source.parental.children) ? source.parental.children : [];
            const child = sourceChildren.find((c) => c.id === fromChildId);
            if (!child) {
                // 引用失败的现场：多半是客户端缓存的旧 childId（档案被重建/换 id）或选了「引用进来」的档案。
                console.warn('[parental/share] 引用失败: 来源档案不存在', JSON.stringify({
                    viewer: req.adminUser.name,
                    target: id,
                    fromMachineId,
                    fromChildId,
                    sourceChildren: sourceChildren.map((c) => `${c.id}:${c.name}`),
                    sourceRefs: ((source.parental && source.parental.shared) || []).map((r) => `${r.childId}:${r.name}`),
                }));
                return jsonFail(res, '来源档案不存在或不是主本档案', 404, 404);
            }
            const viewer = req.adminUser.name;
            const sameAccount = Array.isArray(source.parents) && source.parents.includes(viewer);
            const sharedTo = Array.isArray(child.sharedTo) ? child.sharedTo : [];
            if (!sameAccount && !sharedTo.includes(viewer)) {
                // 管理员可代管引用做排查；家长必须命中白名单或同账号。
                if (req.adminUser.role !== 'admin') {
                    return jsonFail(res, '该档案未分享给你（需档案所有者在主本上把你加入分享名单）', 403, 403);
                }
            }
            const refs = machine.parental && Array.isArray(machine.parental.shared)
                ? machine.parental.shared.slice() : [];
            if (refs.some((r) => r.machineId === fromMachineId && r.childId === fromChildId)) {
                return jsonFail(res, '已经引用过该档案');
            }
            if (refs.length >= parentalShare.MAX_SHARED_REFS) {
                return jsonFail(res, `最多引用 ${parentalShare.MAX_SHARED_REFS} 个档案`);
            }
            refs.push({
                refId: `${fromMachineId}:${fromChildId}`,
                owner: (source.parents && source.parents[0]) || viewer,
                machineId: fromMachineId,
                childId: fromChildId,
                createdAt: nowMs(),
            });
            if (!machine.parental) machine.parental = { mode: 'off', children: [], shared: [] };
            machine.parental.shared = parentalShare.normalizeSharedRefs(refs);
            machines[id] = normalizeMachine(id, machine);
            saveMachines(machines);
            const view = parentalShare.buildShareView(machines[id], machines, viewer);
            console.log(`[share] ${viewer} 在 ${id} 引用 ${fromMachineId}/${fromChildId}`);
            return jsonOk(res, { deviceId: id, view }, '已引用，主本改一次本台自动同步');
        } catch (error) {
            console.error('[share] 添加引用失败:', error);
            return jsonFail(res, error.message);
        }
    });

    /** 取消一条引用：只删本台 shared[] 里的坐标，绝不触碰主本档案。 */
    app.delete('/api/admin/parental/shared', requireParentWriter, (req, res) => {
        try {
            const body = req.body || {};
            const id = safeDeviceId(body.deviceId);
            const refId = String(body.refId || '').trim();
            if (!id || !refId) return jsonFail(res, 'deviceId / refId 不能为空');
            const machines = readMachines();
            const machine = machines[id];
            if (!machine) return jsonFail(res, '设备不存在', 404, 404);
            if (!canManageTv(req, machine)) return jsonFail(res, '只能管理绑定到自己名下的电视', 403, 403);
            const refs = machine.parental && Array.isArray(machine.parental.shared) ? machine.parental.shared : [];
            const next = refs.filter((r) => r.refId !== refId);
            if (next.length === refs.length) return jsonFail(res, '引用不存在', 404, 404);
            machine.parental.shared = next;
            machines[id] = normalizeMachine(id, machine);
            saveMachines(machines);
            const view = parentalShare.buildShareView(machines[id], machines, req.adminUser.name);
            console.log(`[share] ${req.adminUser.name} 在 ${id} 取消引用 ${refId}`);
            return jsonOk(res, { deviceId: id, view }, '已取消引用（不影响主本档案）');
        } catch (error) {
            console.error('[share] 取消引用失败:', error);
            return jsonFail(res, error.message);
        }
    });

    /** 读取某台电视的完整共享视图（主本 / 已引用含 broken / 可引用候选）。 */
    app.get('/api/admin/parental/shared-view', requireParentOperator, (req, res) => {
        try {
            const id = safeDeviceId(req.query.deviceId);
            if (!id) return jsonFail(res, 'deviceId 无效');
            const machines = readMachines();
            const machine = machines[id];
            if (!machine) return jsonFail(res, '设备不存在', 404, 404);
            if (!canManageTv(req, machine)) return jsonFail(res, '只能管理绑定到自己名下的电视', 403, 403);
            const view = parentalShare.buildShareView(machine, machines, req.adminUser.name);
            return jsonOk(res, { deviceId: id, machineName: machine.name, ...view });
        } catch (error) {
            console.error('[share] 读取共享视图失败:', error);
            return jsonFail(res, error.message);
        }
    });

    // ------------------------------------------------------------ 答题解锁题库

    /** 读取某台电视 / 某个儿童档案的题库（家长视图编辑前拉取）。 */
    app.get('/api/admin/parental/quiz', requireParentOperator, (req, res) => {
        try {
            const id = safeDeviceId(req.query.deviceId);
            const childId = String(req.query.childId || '').trim();
            if (!id) return jsonFail(res, 'deviceId 无效');
            if (!childId) return jsonFail(res, 'childId 无效');
            const machine = readMachines()[id];
            if (!machine) return jsonFail(res, '设备不存在', 404, 404);
            if (machineKind(machine) !== 'tv') return jsonFail(res, '只有电视设备支持答题解锁');
            if (!canEditMachineQuizzes(req, machine)) return jsonFail(res, '家长只能编辑已绑定到自己名下的设备', 403, 403);
            if (USE_FAMILY_MODEL) {
                // D-02：题库按家庭 childId 分库（S5 / CR-01），直接读家庭题库实体，
                // 不再有「引用重定向 / 只读」三态（CR-01 取消跨电视档案引用）。
                familyStore.load();
                const bank = familyStore.data.quizzes[childId] || { questions: [], updatedAt: 0 };
                return jsonOk(res, {
                    deviceId: id, childId,
                    sourceDeviceId: id,
                    sourceChildId: childId,
                    readOnly: false,
                    updatedAt: bank.updatedAt || 0,
                    revision: bank.revision || 0,
                    questions: Array.isArray(bank.questions) ? bank.questions : [],
                });
            }
            const lookup = quizLookup(machine, childId, req.adminUser.name);
            if (!lookup.ok) return jsonFail(res, lookup.reason, 404, 404);
            // 引用档案的题库读主本：落点重定向到来源电视 / 主本档案 id。
            const bank = (readQuizStore()[lookup.deviceIdForLookup] || {})[lookup.childIdForLookup]
                || { updatedAt: 0, questions: [] };
            return jsonOk(res, {
                deviceId: id, childId,
                sourceDeviceId: lookup.deviceIdForLookup,
                sourceChildId: lookup.childIdForLookup,
                readOnly: lookup.readOnly,
                updatedAt: bank.updatedAt, questions: bank.questions,
            });
        } catch (error) {
            console.error('[quiz] 读取失败:', error);
            return jsonFail(res, error.message);
        }
    });

    /** 整库替换保存（先读后改再全量回传；空数组 = 清空该档案题库）。 */
    app.put('/api/admin/parental/quiz', requireParentWriter, (req, res) => {
        try {
            const body = req.body || {};
            const id = safeDeviceId(body.deviceId);
            const childId = String(body.childId || '').trim();
            if (!id) return jsonFail(res, 'deviceId 无效');
            if (!childId) return jsonFail(res, 'childId 无效');
            const machine = readMachines()[id];
            if (!machine) return jsonFail(res, '设备不存在', 404, 404);
            if (machineKind(machine) !== 'tv') return jsonFail(res, '只有电视设备支持答题解锁');
            if (!canEditMachineQuizzes(req, machine)) return jsonFail(res, '家长只能编辑已绑定到自己名下的设备', 403, 403);
            if (USE_FAMILY_MODEL) {
                // D-02：题库按家庭 childId 分库；childId 必须是已存在的家庭主档案。
                familyStore.load();
                if (!familyStore.data.children[childId]) {
                    return jsonFail(res, '儿童档案不存在', 404, 404);
                }
                const questions = normalizeQuizQuestions(body.questions);
                // D-01：题库实体版本守卫。
                if (guardRevision(res, body.baseRevision, familyStore.data.quizzes[childId], '该题库')) return;
                familyStore.setQuiz(childId, questions, req.adminUser.name);
                const saved = familyStore.data.quizzes[childId];
                console.log(`[quiz] 保存 ${id}/${childId}: ${questions.length} 题 (family)`);
                // 题库变更后立即把 config 推给所有分配了该档案的电视，
                // 让电视端无需等下一次重启 / 锁屏才重新拉题库。
                pushToAssignedTvs(childId, 'family-quiz');
                return jsonOk(res, { deviceId: id, childId, updatedAt: saved.updatedAt, revision: saved.revision || 0, questions }, '题库已保存');
            }
            const state = childWriteState(machine, childId, req.adminUser.name);
            if (state.kind === 'missing') return jsonFail(res, '儿童档案不存在', 404, 404);
            if (state.kind === 'broken') return jsonFail(res, '该档案的引用来源已失效，请在「档案共享」页重新选择');
            if (state.kind === 'shared') {
                const src = state.source ? (state.source.name || state.source.id) : '主本电视';
                return jsonFail(res, `该档案由「${src}」维护，只读；请到主本电视修改题库`, 403, 403);
            }
            const questions = normalizeQuizQuestions(body.questions);
            const store = readQuizStore();
            if (!store[id]) store[id] = {};
            store[id][childId] = { updatedAt: Date.now(), questions };
            saveQuizStore(store);
            console.log(`[quiz] 保存 ${id}/${childId}: ${questions.length} 题`);
            return jsonOk(res, { deviceId: id, childId, updatedAt: store[id][childId].updatedAt, questions }, '题库已保存');
        } catch (error) {
            console.error('[quiz] 保存失败:', error);
            return jsonFail(res, error.message);
        }
    });

    // ------------------------------------------------------------ 家庭级档案（D-02 全局儿童主档案 + CR-01 题库分享）
    // 以下接口仅在 USE_FAMILY_MODEL 开启时提供完整语义；关闭时返回 409 提示先开标志。

    /**
     * D-01 并发写入保护：请求带 `baseRevision` 且与当前实体版本不一致时，
     * 不落盘并返回 409（同时回带服务端当前实体，供客户端展示差异 / 覆盖）。
     * 返回 true 表示已响应、调用方应直接 return；不带 baseRevision 维持旧行为。
     */
    function guardRevision(res, baseRevision, current, label) {
        if (baseRevision === undefined || baseRevision === null || baseRevision === '') return false;
        const want = Number(baseRevision);
        const cur = current && Number.isFinite(Number(current.revision)) ? Number(current.revision) : 0;
        if (Number.isFinite(want) && want === cur) return false;
        jsonFail(res, `${label}已被其他设备修改，请刷新后再试`, 409, 409, { current: current || null });
        return true;
    }

    /** 把某儿童档案的变更推送到所有分配了该档案的电视（家庭内改一次、各电视同步）。 */
    function pushToAssignedTvs(childId, reason) {
        try {
            const machines = readMachines();
            const assignments = familyStore.data.assignments;
            for (const m of Object.values(machines)) {
                if ((m.kind || '') !== 'tv') continue;
                const ass = assignments[m.id];
                if (ass && Array.isArray(ass.childIds) && ass.childIds.includes(childId)) {
                    pushConfigToMachine(m, { reason });
                }
            }
        } catch (error) {
            console.warn('[family] 推送失败:', error.message);
        }
    }

    /** 列出全部家庭儿童主档案（全局），并附每台电视的分配情况。 */
    app.get('/api/admin/parental/children', requireParentOperator, (req, res) => {
        try {
            if (!USE_FAMILY_MODEL) return jsonFail(res, '家庭级模型未启用', 409, 409);
            familyStore.load();
            const machines = readMachines();
            const assignmentsByChild = {};
            for (const [deviceId, a] of Object.entries(familyStore.data.assignments)) {
                for (const cid of (a.childIds || [])) {
                    (assignmentsByChild[cid] = assignmentsByChild[cid] || []).push(deviceId);
                }
            }
            const tvNames = {};
            for (const m of Object.values(machines)) {
                if ((m.kind || '') === 'tv') tvNames[m.id] = m.name || m.id;
            }
            const children = Object.values(familyStore.data.children).map((fc) => ({
                id: fc.childId,
                name: fc.name,
                age: fc.age,
                avatarId: fc.avatarId,
                profileMode: fc.profileMode,
                dailyLimitMin: fc.dailyLimitMin,
                sessionLimitMin: fc.sessionLimitMin,
                bedtimeStart: fc.bedtimeStart,
                bedtimeEnd: fc.bedtimeEnd,
                blacklist: fc.blacklist,
                whitelist: fc.whitelist,
                locked: fc.locked === true,
                revision: fc.revision || 0,
                updatedBy: fc.updatedBy || '',
                updatedAt: fc.updatedAt || 0,
                sharedTo: (familyStore.data.quizzes[fc.childId] && familyStore.data.quizzes[fc.childId].sharedTo) || [],
                // D-01：题库实体版本号（与档案版本分开），供题库分享保存携带 baseRevision。
                quizRevision: (familyStore.data.quizzes[fc.childId] && familyStore.data.quizzes[fc.childId].revision) || 0,
                assignedTo: (assignmentsByChild[fc.childId] || []).map((id) => ({ id, name: tvNames[id] || id })),
            }));
            return jsonOk(res, { children });
        } catch (error) {
            console.error('[family] 列出儿童失败:', error);
            return jsonFail(res, error.message);
        }
    });

    /** 新增 / 更新一个全局儿童主档案（按 childId 全局唯一）。 */
    app.post('/api/admin/parental/child', requireParentWriter, (req, res) => {
        try {
            if (!USE_FAMILY_MODEL) return jsonFail(res, '家庭级模型未启用', 409, 409);
            const body = req.body || {};
            const child = {
                childId: String(body.id || body.childId || '').trim(),
                name: String(body.name || '').trim(),
                age: Number(body.age) || 0,
                avatarId: String(body.avatarId || body.avatar || '').trim(),
                profileMode: body.profileMode === 'strict' ? 'strict' : 'mild',
                dailyLimitMin: Number(body.dailyLimitMin) || 0,
                sessionLimitMin: Number(body.sessionLimitMin) || 0,
                bedtimeStart: String(body.bedtimeStart || '').trim(),
                bedtimeEnd: String(body.bedtimeEnd || '').trim(),
                blacklist: Array.isArray(body.blacklist) ? body.blacklist.map(String) : [],
                whitelist: Array.isArray(body.whitelist) ? body.whitelist.map(String) : [],
                locked: body.locked === true,
            };
            if (!child.childId) return jsonFail(res, 'childId 不能为空');
            if (!child.name) return jsonFail(res, '姓名不能为空');
            // D-01：更新已有档案时校验版本号，避免多端并发静默覆盖。
            familyStore.load();
            if (guardRevision(res, body.baseRevision, familyStore.data.children[child.childId], '该儿童档案')) return;
            const saved = familyStore.upsertChild(child, req.adminUser.name);
            pushToAssignedTvs(saved.childId, 'family-child');
            return jsonOk(res, { child: saved }, '已保存');
        } catch (error) {
            console.error('[family] 保存儿童失败:', error);
            return jsonFail(res, error.message);
        }
    });

    /** 删除一个全局儿童主档案（级联清空各电视分配）。 */
    app.delete('/api/admin/parental/child', requireParentWriter, (req, res) => {
        try {
            if (!USE_FAMILY_MODEL) return jsonFail(res, '家庭级模型未启用', 409, 409);
            const childId = String((req.body && req.body.childId) || req.query.childId || '').trim();
            if (!childId) return jsonFail(res, 'childId 不能为空');
            const ok = familyStore.removeChild(childId, req.adminUser.name);
            if (!ok) return jsonFail(res, '档案不存在', 404, 404);
            return jsonOk(res, { childId }, '已删除');
        } catch (error) {
            console.error('[family] 删除儿童失败:', error);
            return jsonFail(res, error.message);
        }
    });

    /** 读取某台电视的分配（启用了哪些家庭儿童档案）。 */
    app.get('/api/admin/parental/assignment', requireParentOperator, (req, res) => {
        try {
            if (!USE_FAMILY_MODEL) return jsonFail(res, '家庭级模型未启用', 409, 409);
            const id = safeDeviceId(req.query.deviceId);
            if (!id) return jsonFail(res, 'deviceId 无效');
            const a = familyStore.data.assignments[id];
            return jsonOk(res, { deviceId: id, childIds: a ? a.childIds.slice() : [], revision: a ? (a.revision || 0) : 0 });
        } catch (error) {
            console.error('[family] 读取分配失败:', error);
            return jsonFail(res, error.message);
        }
    });

    /** 设置某台电视的分配（启用了哪些家庭儿童档案）。 */
    app.put('/api/admin/parental/assignment', requireParentWriter, (req, res) => {
        try {
            if (!USE_FAMILY_MODEL) return jsonFail(res, '家庭级模型未启用', 409, 409);
            const body = req.body || {};
            const id = safeDeviceId(body.deviceId);
            if (!id) return jsonFail(res, 'deviceId 无效');
            const machine = readMachines()[id];
            if (!machine) return jsonFail(res, '设备不存在', 404, 404);
            if ((machine.kind || '') !== 'tv') return jsonFail(res, '只有电视设备支持分配');
            if (!canManageTv(req, machine)) return jsonFail(res, '只能管理绑定到自己名下的电视', 403, 403);
            const childIds = Array.isArray(body.childIds) ? body.childIds.map(String).filter(Boolean) : [];
            for (const cid of childIds) {
                if (!familyStore.data.children[cid]) return jsonFail(res, `儿童档案不存在：${cid}`, 404, 404);
            }
            // D-01：分配实体版本守卫。
            if (guardRevision(res, body.baseRevision, familyStore.data.assignments[id], '该电视的档案分配')) return;
            familyStore.setAssignment(id, childIds, req.adminUser.name);
            pushConfigToMachine(machine, { reason: 'family-assign' });
            return jsonOk(res, { deviceId: id, childIds: familyStore.data.assignments[id].childIds.slice(), revision: familyStore.data.assignments[id].revision || 0 }, '分配已保存');
        } catch (error) {
            console.error('[family] 保存分配失败:', error);
            return jsonFail(res, error.message);
        }
    });

    /** 读取某台电视的本台设置（儿童模式开关 / 解锁方式 / PIN / 已应用档案，CR-02 U1）。 */
    app.get('/api/admin/parental/device-local', requireParentOperator, (req, res) => {
        try {
            if (!USE_FAMILY_MODEL) return jsonFail(res, '家庭级模型未启用', 409, 409);
            const id = safeDeviceId(req.query.deviceId);
            if (!id) return jsonFail(res, 'deviceId 无效');
            familyStore.load();
            const dl = familyStore.data.deviceLocal[id] || { deviceId: id, mode: 'off', unlockMode: 'remote', pin: '', activeChildIds: [], revision: 0 };
            return jsonOk(res, {
                deviceId: id,
                mode: dl.mode === 'on' ? 'on' : 'off',
                unlockMode: dl.unlockMode || 'remote',
                pin: dl.pin || '',
                activeChildIds: Array.isArray(dl.activeChildIds) ? dl.activeChildIds.slice() : [],
                revision: dl.revision || 0,
                updatedBy: dl.updatedBy || '',
                updatedAt: dl.updatedAt || 0,
            });
        } catch (error) {
            console.error('[family] 读取本台设置失败:', error);
            return jsonFail(res, error.message);
        }
    });

    /** 写入某台电视的本台设置（CR-02：解锁方式 / PIN / 儿童模式开关，按 deviceId 独立保存）。 */
    app.put('/api/admin/parental/device-local', requireParentWriter, (req, res) => {
        try {
            if (!USE_FAMILY_MODEL) return jsonFail(res, '家庭级模型未启用', 409, 409);
            const body = req.body || {};
            const id = safeDeviceId(body.deviceId);
            if (!id) return jsonFail(res, 'deviceId 无效');
            const machine = readMachines()[id];
            if (!machine) return jsonFail(res, '设备不存在', 404, 404);
            if ((machine.kind || '') !== 'tv') return jsonFail(res, '只有电视设备支持本台设置');
            if (!canManageTv(req, machine)) return jsonFail(res, '只能管理绑定到自己名下的电视', 403, 403);
            familyStore.load();
            if (guardRevision(res, body.baseRevision, familyStore.data.deviceLocal[id], '该电视的本台设置')) return;
            const patch = {};
            if (body.mode === 'on' || body.mode === 'off') patch.mode = body.mode;
            if (body.unlockMode !== undefined) patch.unlockMode = body.unlockMode;
            if (body.pin !== undefined) patch.pin = String(body.pin || '');
            if (Array.isArray(body.activeChildIds)) patch.activeChildIds = body.activeChildIds.map(String).filter(Boolean);
            const saved = familyStore.setDeviceLocal(id, patch, req.adminUser.name);
            pushConfigToMachine(machine, { reason: 'device-local' });
            return jsonOk(res, {
                deviceId: id,
                mode: saved.mode === 'on' ? 'on' : 'off',
                unlockMode: saved.unlockMode || 'remote',
                pin: saved.pin || '',
                activeChildIds: Array.isArray(saved.activeChildIds) ? saved.activeChildIds.slice() : [],
                revision: saved.revision || 0,
                updatedBy: saved.updatedBy || '',
                updatedAt: saved.updatedAt || 0,
            }, '本台设置已保存');
        } catch (error) {
            console.error('[family] 保存本台设置失败:', error);
            return jsonFail(res, error.message);
        }
    });

    /** 设置某儿童题库的跨家长分享白名单（CR-01：sharedTo 挂 Quiz 实体）。 */
    app.put('/api/admin/parental/quiz/share', requireParentWriter, (req, res) => {
        try {
            if (!USE_FAMILY_MODEL) return jsonFail(res, '家庭级模型未启用', 409, 409);
            const body = req.body || {};
            const childId = String(body.childId || '').trim();
            if (!childId) return jsonFail(res, 'childId 无效');
            if (!familyStore.data.children[childId]) return jsonFail(res, '儿童档案不存在', 404, 404);
            const sharedTo = Array.isArray(body.sharedTo) ? body.sharedTo.map(String).filter(Boolean) : [];
            // D-01：题库实体版本守卫（授权写只改 sharedTo，不触碰家庭档案）。
            familyStore.load();
            if (guardRevision(res, body.baseRevision, familyStore.data.quizzes[childId], '该题库分享设置')) return;
            familyStore.setQuizSharedTo(childId, sharedTo, req.adminUser.name);
            pushToAssignedTvs(childId, 'family-quiz-share');
            return jsonOk(res, { childId, sharedTo: familyStore.data.quizzes[childId].sharedTo, revision: familyStore.data.quizzes[childId].revision || 0 }, '分享范围已保存');
        } catch (error) {
            console.error('[family] 设置题库分享失败:', error);
            return jsonFail(res, error.message);
        }
    });

    /** 从他人分享的题库复制一份到自己的儿童档案（CR-01 Q1 复制副本）。 */
    app.post('/api/admin/parental/quiz/import', requireParentWriter, (req, res) => {
        try {
            if (!USE_FAMILY_MODEL) return jsonFail(res, '家庭级模型未启用', 409, 409);
            const body = req.body || {};
            const targetChildId = String(body.targetChildId || '').trim();
            const sourceChildId = String(body.sourceChildId || '').trim();
            const sourceAccount = String(body.sourceAccount || req.adminUser.name).trim();
            if (!targetChildId || !sourceChildId) return jsonFail(res, 'targetChildId / sourceChildId 不能为空');
            if (!familyStore.data.children[targetChildId]) return jsonFail(res, '目标儿童档案不存在', 404, 404);
            const src = familyStore.data.quizzes[sourceChildId];
            if (!src) return jsonFail(res, '来源题库不存在', 404, 404);
            const viewer = req.adminUser.name;
            const allowed = (src.sharedTo || []).includes(viewer) || src.sourceAccount === viewer;
            if (!allowed) return jsonFail(res, '该题库未分享给你', 403, 403);
            const copy = familyStore.importQuizCopy(targetChildId, src, sourceAccount, req.adminUser.name);
            pushToAssignedTvs(targetChildId, 'family-quiz-import');
            return jsonOk(res, { targetChildId, isCopy: copy.isCopy, questionCount: copy.questions.length }, '已复制题库副本');
        } catch (error) {
            console.error('[family] 导入题库副本失败:', error);
            return jsonFail(res, error.message);
        }
    });

    /** 列出分享给我的题库（CR-01 Q3：仅显示哪些家长号分享给了我，不含任何使用统计）。 */
    app.get('/api/admin/parental/quiz/shared-to-me', requireParentOperator, (req, res) => {
        try {
            if (!USE_FAMILY_MODEL) return jsonFail(res, '家庭级模型未启用', 409, 409);
            familyStore.load();
            const viewer = req.adminUser.name;
            const list = [];
            for (const [childId, q] of Object.entries(familyStore.data.quizzes || {})) {
                if (!q || !Array.isArray(q.sharedTo) || !q.sharedTo.includes(viewer)) continue;
                if (q.sourceAccount === viewer) continue; // 自己的题库不算「分享给我」
                const ownerChild = familyStore.data.children[childId];
                list.push({
                    sourceAccount: q.sourceAccount || '',
                    sourceChildId: childId,
                    childName: ownerChild ? ownerChild.name : childId,
                    questionCount: Array.isArray(q.questions) ? q.questions.length : 0,
                });
            }
            return jsonOk(res, { quizzes: list });
        } catch (error) {
            console.error('[family] 列出分享题库失败:', error);
            return jsonFail(res, error.message);
        }
    });

    /** 题干 / 选项配图上传：base64 落盘，题目里只存 URL。 */
    app.post('/api/admin/parental/quiz/image', requireParentWriter, (req, res) => {
        try {
            const body = req.body || {};
            const id = safeDeviceId(body.deviceId);
            const childId = String(body.childId || '').trim();
            if (!id) return jsonFail(res, 'deviceId 无效');
            if (!childId) return jsonFail(res, 'childId 无效');
            const machine = readMachines()[id];
            if (!machine) return jsonFail(res, '设备不存在', 404, 404);
            if (machineKind(machine) !== 'tv') return jsonFail(res, '只有电视设备支持答题解锁');
            if (!canEditMachineQuizzes(req, machine)) return jsonFail(res, '家长只能编辑已绑定到自己名下的设备', 403, 403);
            const mimeToExt = { 'image/png': 'png', 'image/jpeg': 'jpg', 'image/jpg': 'jpg', 'image/webp': 'webp', 'image/gif': 'gif' };
            let data = typeof body.data === 'string' ? body.data : '';
            let mime = typeof body.mime === 'string' ? body.mime.toLowerCase() : '';
            const dataUrl = data.match(/^data:(image\/[a-z+]+);base64,([\s\S]*)$/i);
            if (dataUrl) {
                mime = dataUrl[1].toLowerCase();
                data = dataUrl[2];
            }
            const ext = mimeToExt[mime];
            if (!ext) return jsonFail(res, '仅支持 PNG / JPEG / WebP / GIF 图片');
            if (!data) return jsonFail(res, '图片内容为空');
            const buffer = Buffer.from(data, 'base64');
            if (!buffer.length) return jsonFail(res, '图片内容为空');
            if (buffer.length > MAX_QUIZ_IMAGE_BYTES) {
                return jsonFail(res, `图片不能超过 ${MAX_QUIZ_IMAGE_BYTES / 1024 / 1024}MB`);
            }
            fs.mkdirSync(quizImageDir, { recursive: true });
            const name = `${crypto.randomBytes(16).toString('hex')}.${ext}`;
            fs.writeFileSync(path.join(quizImageDir, name), buffer);
            return jsonOk(res, { url: `/api/parental/quiz-image/${name}` }, '图片已上传');
        } catch (error) {
            console.error('[quiz] 图片上传失败:', error);
            return jsonFail(res, error.message);
        }
    });

    /** 儿童档案头像上传：base64 → magic bytes 校验 → sha256 去重 → 同步转发 app_server。
     *  同一个 sha256 第二次上传会直接返回已有的 URL（不重复转发）。
     *  必须走 mirrorAndWait（同步等待公网 URL 回来再存索引），这样客户端拿到的一定是可直连地址。 */
    app.post('/api/admin/parental/avatar', requireParentWriter, async (req, res) => {
        try {
            const body = req.body || {};
            const id = safeDeviceId(body.deviceId);
            if (!id) return jsonFail(res, 'deviceId 无效');
            const machine = readMachines()[id];
            if (!machine) return jsonFail(res, '设备不存在', 404, 404);
            if (machineKind(machine) !== 'tv') return jsonFail(res, '只有电视设备支持儿童档案');
            if (req.adminUser.role === 'parent' && !machine.parents.includes(req.adminUser.name)) {
                return jsonFail(res, '只能给你管理的电视上传头像', 403, 403);
            }
            let data = typeof body.data === 'string' ? body.data : '';
            const dataUrl = data.match(/^data:(image\/[a-z+]+);base64,([\s\S]*)$/i);
            if (dataUrl) data = dataUrl[2];
            if (!data) return jsonFail(res, '图片内容为空');
            const buffer = Buffer.from(data, 'base64');
            if (!buffer.length) return jsonFail(res, '图片内容为空');
            if (buffer.length > MAX_AVATAR_IMAGE_BYTES) {
                return jsonFail(res, `图片不能超过 ${MAX_AVATAR_IMAGE_BYTES / 1024 / 1024}MB`);
            }
            const mime = detectImageMime(buffer);
            if (!mime) return jsonFail(res, '仅支持 PNG / JPEG / WebP / GIF 图片（magic bytes 校验未通过）');

            const sha = crypto.createHash('sha256').update(buffer).digest('hex');
            const store = readAvatarStore();
            const existing = (store[id] || []).find((item) => item.sha256 === sha);
            if (existing) {
                return jsonOk(res, { url: existing.url, sha256: sha, id: existing.id, reused: true }, '头像已存在');
            }

            fs.mkdirSync(avatarImageDir, { recursive: true });
            const extMap = { 'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp', 'image/gif': 'gif' };
            const ext = extMap[mime] || 'png';
            const localName = `${sha.slice(0, 16)}.${ext}`;
            const localPath = path.join(avatarImageDir, localName);
            if (!fs.existsSync(localPath)) fs.writeFileSync(localPath, buffer);

            if (!forward || typeof forward.mirrorAndWait !== 'function') {
                return jsonFail(res, '上传镜像转发未配置（请先配置 datas/forward_config.json 的 baseUrl 和 serviceToken）');
            }
            const mirrorResult = await forward.mirrorAndWait(localPath, `parental-avatars/${id}/${localName}`, { 'x-pinned': 'true' });
            // app_server mirror 返回的是 /download 路由（需要 Service Token），
            // 我们要 /avatar 公开路由（无令牌、返回 image/*、长缓存）。两者只差路径段，直接替换。
            let downloadUrl = mirrorResult.downloadUrl;
            if (downloadUrl && downloadUrl.endsWith('/download')) {
                downloadUrl = downloadUrl.slice(0, -'/download'.length) + '/avatar';
            }
            if (!downloadUrl || !AVATAR_URL_RE.test(downloadUrl)) {
                return jsonFail(res, '镜像转发成功但未返回有效的下载地址');
            }

            const avatarId = mirrorResult.id || `local_${sha.slice(0, 12)}`;
            const record = {
                id: avatarId,
                url: downloadUrl,
                sha256: sha,
                mime,
                size: buffer.length,
                uploadedBy: req.adminUser.name,
                createdAt: new Date().toISOString(),
                childIds: [],
            };
            if (!store[id]) store[id] = [];
            store[id].push(record);
            saveAvatarStore(store);
            console.log(`[avatar] ${req.adminUser.name} 上传头像 ${avatarId} → ${downloadUrl}`);
            return jsonOk(res, { url: downloadUrl, sha256: sha, id: avatarId, mime: mime }, '头像已上传');
        } catch (error) {
            console.error('[avatar] 上传失败:', error);
            return jsonFail(res, error.message);
        }
    });

    /** 列出可用头像素材：按家庭维度合并（所有该家长能管的 tv 的头像，按 sha256 去重）。 */
    app.get('/api/admin/parental/avatars', requireParentOperator, (req, res) => {
        try {
            const avatars = listAvatarsForParent(req.adminUser.name);
            return jsonOk(res, { avatars });
        } catch (error) {
            console.error('[avatar] 列表失败:', error);
            return jsonFail(res, error.message);
        }
    });

    /** 从索引移除头像素材（app_server 那边的物理文件不动，避免其他电视/档案还在引用）。 */
    app.delete('/api/admin/parental/avatar/:avatarId', requireParentWriter, (req, res) => {
        try {
            const avatarId = String(req.params.avatarId || '').trim();
            if (!avatarId) return jsonFail(res, 'avatarId 无效');
            const store = readAvatarStore();
            let removed = 0;
            const machines = readMachines();
            const parentName = req.adminUser.name;
            for (const [deviceId, list] of Object.entries(store)) {
                const machine = machines[deviceId];
                if (!machine) continue;
                if (req.adminUser.role === 'parent') {
                    const isOwner = machine.owner === parentName;
                    const isParent = Array.isArray(machine.parents) && machine.parents.includes(parentName);
                    if (!isOwner && !isParent) continue;
                }
                const before = list.length;
                store[deviceId] = list.filter((item) => item.id !== avatarId);
                removed += before - store[deviceId].length;
            }
            saveAvatarStore(store);
            return jsonOk(res, { removed }, removed > 0 ? '头像已移除' : '头像未找到');
        } catch (error) {
            console.error('[avatar] 删除失败:', error);
            return jsonFail(res, error.message);
        }
    });

    /** 设备类型卡片图标上传：与头像共用镜像转发链路，但只返回相对路径。
     *  配置里存 /api/files/<id>/avatar，客户端按当前 serverBaseUrl 拼接，
     *  yuntu IP 变化只需改 forward_config.json，旧图标不会失效。 */
    app.post('/api/admin/device-type/icon', requireAdmin, async (req, res) => {
        try {
            const body = req.body || {};
            let data = typeof body.data === 'string' ? body.data : '';
            const dataUrl = data.match(/^data:(image\/[a-z+]+);base64,([\s\S]*)$/i);
            if (dataUrl) data = dataUrl[2];
            if (!data) return jsonFail(res, '图片内容为空');
            const buffer = Buffer.from(data, 'base64');
            if (!buffer.length) return jsonFail(res, '图片内容为空');
            if (buffer.length > MAX_CARD_ICON_BYTES) {
                return jsonFail(res, `图片不能超过 ${MAX_CARD_ICON_BYTES / 1024 / 1024}MB`);
            }
            const mime = detectImageMime(buffer);
            if (!mime) return jsonFail(res, '仅支持 PNG / JPEG / WebP / GIF 图片（magic bytes 校验未通过）');

            const sha = crypto.createHash('sha256').update(buffer).digest('hex');
            const store = readCardIconStore();
            if (store[sha]) {
                const old = store[sha];
                return jsonOk(res, {
                    url: old.url, sha256: sha, id: old.id, mime: old.mime, reused: true,
                }, '图标已存在');
            }
            if (!forward || typeof forward.mirrorAndWait !== 'function') {
                return jsonFail(res, '上传镜像转发未配置（请检查 datas/forward_config.json）');
            }
            const extMap = { 'image/png': 'png', 'image/jpeg': 'jpg', 'image/webp': 'webp', 'image/gif': 'gif' };
            const localName = `${sha.slice(0, 16)}.${extMap[mime] || 'png'}`;
            fs.mkdirSync(cardIconDir, { recursive: true });
            const localPath = path.join(cardIconDir, localName);
            if (!fs.existsSync(localPath)) fs.writeFileSync(localPath, buffer);
            const mirrorResult = await forward.mirrorAndWait(localPath, `device-type-icons/${localName}`, { 'x-pinned': 'true' });

            let url = '';
            try {
                let pathname = new URL(mirrorResult.downloadUrl).pathname;
                if (pathname.endsWith('/download')) {
                    pathname = pathname.slice(0, -'/download'.length) + '/avatar';
                }
                if (CARD_ICON_URL_RE.test(pathname)) url = pathname;
            } catch (_) { /* 返回值不合法时下面统一报错 */ }
            if (!url) return jsonFail(res, '镜像转发成功但未返回有效的资源路径');

            const record = {
                id: mirrorResult.id || '',
                url,
                mime,
                size: buffer.length,
                createdAt: new Date().toISOString(),
            };
            store[sha] = record;
            writeJson(cardIconFile, store);
            console.log(`[card-icon] 上传图标 ${sha.slice(0, 12)} → ${url}`);
            return jsonOk(res, {
                url, sha256: sha, id: record.id, mime,
            }, '图标已上传');
        } catch (error) {
            console.error('[card-icon] 上传失败:', error);
            return jsonFail(res, error.message);
        }
    });

    /** 公共资源代理：客户端只存 /api/files/:id/avatar；这里按当前 forward 配置
     *  解析到 yuntu。IP / 端口变化只改 forward_config.json，历史图标路径不变。 */
    app.get('/api/files/:id/avatar', (req, res) => {
        const id = String(req.params.id || '').trim();
        if (!/^[A-Za-z0-9_-]{1,80}$/.test(id)) return res.status(400).end();
        let base = '';
        try {
            base = String((forward && typeof forward.status === 'function' ? forward.status().baseUrl : '') || '')
                .replace(/\/+$/, '');
        } catch (_) { /* forward 未注入 */ }
        if (!base) return res.status(503).end();
        let target;
        try {
            target = new URL(`${base}/api/files/${encodeURIComponent(id)}/avatar`);
        } catch (_) {
            return res.status(502).end();
        }
        const client = target.protocol === 'https:' ? https : http;
        const upstream = client.get(target, (upstreamRes) => {
            const status = upstreamRes.statusCode || 502;
            if (status >= 300 && status < 400 && upstreamRes.headers.location) {
                upstreamRes.resume();
                return res.redirect(302, upstreamRes.headers.location);
            }
            res.status(status);
            for (const key of ['content-type', 'content-length', 'cache-control', 'etag', 'last-modified']) {
                if (upstreamRes.headers[key]) res.setHeader(key, upstreamRes.headers[key]);
            }
            upstreamRes.pipe(res);
        });
        upstream.on('error', (error) => {
            console.error('[card-icon] 代理失败:', error.message);
            if (!res.headersSent) res.status(502).end();
            else res.end();
        });
    });

    /**
     * 电视端拉取题库：不走管理会话，用登录后的 `username` cookie 鉴权
     * （电视用设备账号登录，与 commAccount / owner / 绑定家长比对）。
     */
    app.get('/api/parental/quiz', (req, res) => {
        try {
            const id = safeDeviceId(req.query.deviceId);
            if (!id) return jsonFail(res, 'deviceId 无效');
            const username = String((req.cookies && req.cookies.username) || '').trim();
            // 用业务码 100000（而不是 HTTP 401）才能被电视端 fetchUrl 识别并自动重登。
            if (!username) return jsonFail(res, '未登录', definds.code.UNLOGIN);
            const machine = readMachines()[id];
            if (!machine) return jsonFail(res, '设备未注册', 404, 404);
            if (username !== ADMIN_USERNAME) {
                const accounts = [machine.owner, machine.commAccount, ...(machine.parents || [])].filter(Boolean);
                if (accounts.length > 0 && !accounts.includes(username)) {
                    return jsonFail(res, '无权读取该设备题库', 403, 403);
                }
                if (!listUsers().some((user) => user.name === username)) {
                    return jsonFail(res, '账号不存在', definds.code.UNLOGIN);
                }
            }
            if (USE_FAMILY_MODEL) {
                // D-02：电视按本台分配的家庭 childId 取各自家庭题库（S5 / CR-01）。
                // 题库缺失也返回空 bank，电视端据此把答题解锁降级为远程确认（U2）。
                familyStore.load();
                const assignment = familyStore.data.assignments[id];
                const childIds = assignment ? assignment.childIds.slice() : [];
                const banks = childIds.map((cid) => {
                    const q = familyStore.data.quizzes[cid] || { questions: [], updatedAt: 0 };
                    return { childId: cid, updatedAt: q.updatedAt || 0, questions: Array.isArray(q.questions) ? q.questions : [] };
                });
                return jsonOk(res, { deviceId: id, banks });
            }
            const banks = readQuizStore()[id] || {};
            // 共享档案的题库存在主本电视的目录下：按引用解析后合并进来，
            // 电视端「多孩题库合并」才能覆盖共享的孩子。来源失效 / 与本机
            // childId 冲突的引用直接跳过（与 config 展开口径一致）。
            const merged = { ...banks };
            const refs = machine.parental && Array.isArray(machine.parental.shared)
                ? machine.parental.shared : [];
            if (refs.length > 0) {
                const allMachines = readMachines();
                const store = readQuizStore();
                for (const ref of refs) {
                    if (!ref || !ref.childId || merged[ref.childId]) continue;
                    const target = parentalShare.resolveQuizTarget(machine, allMachines, ref.childId, null);
                    if (!target.ok) continue;
                    const sourceBank = (store[target.deviceIdForLookup] || {})[target.childIdForLookup];
                    if (!sourceBank || !Array.isArray(sourceBank.questions) || sourceBank.questions.length === 0) continue;
                    merged[ref.childId] = { ...sourceBank, shared: true };
                }
            }
            return jsonOk(res, {
                deviceId: id,
                banks: Object.entries(merged).map(([childId, bank]) => ({
                    childId,
                    updatedAt: bank.updatedAt,
                    questions: bank.questions,
                    ...(bank.shared ? { shared: true } : {}),
                })),
            });
        } catch (error) {
            console.error('[quiz] 电视拉取失败:', error);
            return jsonFail(res, error.message);
        }
    });

    /** 题库配图静态读取（随机文件名不可枚举，家庭场景不做额外鉴权）。 */
    app.get('/api/parental/quiz-image/:name', (req, res) => {
        const name = String(req.params.name || '');
        if (!QUIZ_IMAGE_FILE_RE.test(name)) return res.status(404).end();
        const file = path.join(quizImageDir, name);
        if (!fs.existsSync(file)) return res.status(404).end();
        res.setHeader('Cache-Control', 'public, max-age=31536000, immutable');
        return res.sendFile(file);
    });

    // 家长自助绑定/解绑：只能增删自己；一台电视可同时属于多个家长。
    app.post('/api/admin/parental/bind', requireParentOperator, (req, res) => {
        try {
            const user = req.adminUser;
            const id = safeDeviceId(req.body ? req.body.deviceId : '');
            const bind = req.body ? req.body.bind !== false : true;
            if (!id) return jsonFail(res, '设备 ID 无效');
            const machines = readMachines();
            const machine = machines[id];
            if (!machine) return jsonFail(res, '设备不存在');
            if (machineKind(machine) !== 'tv') {
                return jsonFail(res, '只有电视设备支持绑定家长');
            }
            if (user.role === 'parent') {
                machine.parents = bind
                    ? Array.from(new Set(machine.parents.concat(user.name)))
                    : machine.parents.filter((name) => name !== user.name);
            } else {
                // 管理员走完整 parents 分配（PUT），这里只做单账号增删。
                const next = bind
                    ? Array.from(new Set(machine.parents.concat(user.name)))
                    : machine.parents.filter((name) => name !== user.name);
                machine.parents = next;
            }
            machines[id] = normalizeMachine(id, machine);
            saveMachines(machines);
            pushConfigToMachine(machines[id], { reason: 'parent-bind' });
            return jsonOk(res, { machine: machines[id] });
        } catch (error) {
            console.error('[admin] 家长绑定设备失败:', error);
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

    /**
     * 远程更新：给设备打一个「立即升级」标记。
     * 设备下次心跳（或下次唤醒并联网）会带着它，即使本机关掉了「自动更新」也会装。
     * 只对 ESP 屏幕设备有意义（它们用 version 字符串比对固件版本）。
     */
    app.post('/api/admin/machines/:id/fw_push', requireAdmin, (req, res) => {
        const id = safeDeviceId(req.params.id);
        if (!id) return jsonFail(res, '设备 ID 无效');
        const machines = readMachines();
        if (!machines[id]) return jsonFail(res, '设备不存在');
        const machine = machines[id];
        if (machine.platform !== 'esp32') return jsonFail(res, '只有 ESP 屏幕设备支持远程更新');
        machine.fwPushAt = Date.now();
        machines[id] = machine;
        saveMachines(machines);
        pushConfigToMachine(machines[id], { reason: 'fw-push' });
        return jsonOk(res, { fwPushAt: machine.fwPushAt }, '已下发远程更新标记');
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
            // 首次建档本身就发生在这次连接里，给「最后连接时间」一个初值，
            // 否则仅靠 HTTP 登录建档的老设备该字段会一直是 0。
            machine.lastConnectedAt = now;
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
        // 主从角色与所属主机 MAC：设备设置页保存后随注册/心跳上报。
        if (body.role === 'master' || body.role === 'slave') machine.role = body.role;
        if (typeof body.masterMac === 'string') machine.masterMac = body.masterMac.trim().slice(0, 32);
        // 电池电压（mV）：从机休眠前上报，后台用于展示电量。
        if (Number.isFinite(Number(body.batteryMv)) && Number(body.batteryMv) > 0) {
            machine.batteryMv = Math.round(Number(body.batteryMv));
        }
        if (typeof body.appVersion === 'string' && body.appVersion.trim()) {
            machine.appVersion = body.appVersion.trim().slice(0, 32);
        }
        // OTA 轨道：设备自报 esp32s3 / esp32c6，后台按它下发对应版本号。
        if (typeof body.target === 'string' && /^esp32[a-z0-9]+$/i.test(body.target.trim())) {
            machine.fwTarget = body.target.trim().toLowerCase().slice(0, 16);
        }
        // 深睡从机自报的定时唤醒间隔（秒），用于后台显示「预计唤醒时间」。
        if (Number.isFinite(Number(body.sleepSec)) && Number(body.sleepSec) > 0) {
            machine.sleepSec = Math.round(Number(body.sleepSec));
        }
        // 远程配置：本机已应用到的配置版本 + 本机当前实际值（供后台对照编辑）。
        if (Number.isFinite(Number(body.cfgVer))) machine.cfgApplied = Math.round(Number(body.cfgVer));
        if (body.cfgNow && typeof body.cfgNow === 'object') machine.cfgNow = body.cfgNow;
        // 唤醒诊断：PIR 唤醒累计次数（RTC 内存），用来判断人体感应能否唤醒深睡。
        if (Number.isFinite(Number(body.pirWakes))) machine.pirWakes = Math.round(Number(body.pirWakes));
        if (typeof body.wake === 'string') machine.lastWake = body.wake.slice(0, 12);
        if (Number.isFinite(Number(body.pirLevel))) machine.pirLevel = Math.round(Number(body.pirLevel));
        if (body.slpErr && typeof body.slpErr === 'object') machine.slpErr = body.slpErr;
        if (Number.isFinite(Number(body.pirMode))) machine.pirMode = Math.round(Number(body.pirMode));
        // 唤醒原始诊断：复位原因 / 唤醒原因 / 两条唤醒通道的引脚掩码。
        if (body.diag && typeof body.diag === 'object') machine.diag = body.diag;
        // ESP 设备每次注册/心跳上报本机槽位→GPIO 映射；后台据此展示实际引脚，
        // 并提示「后台配了槽位但本机没启用」的情况。
        if (Array.isArray(body.espButtons)) {
            machine.espButtons = normalizeEspButtons(body.espButtons);
        }
        // 人体感应状态：固件在 0/1 跳变时会立刻发一次心跳。
        // 只在跳变时刷新进入/离开时间，普通心跳只更新 updatedAt。
        const pirRaw = body.pir;
        // 只在电平跳变时联动自动化：普通心跳也会带 pir，每次都跑会白耗。
        // 引擎读的是落盘后的 machines.json，所以事件要等 saveMachines 之后再发。
        let pirJump = null;
        if (pirRaw === 0 || pirRaw === 1 || pirRaw === '0' || pirRaw === '1') {
            const present = Number(pirRaw) === 1;
            const prev = normalizeEspPresence(machine.espPresence);
            if (!prev || prev.present !== present) pirJump = present;
            machine.espPresence = {
                present,
                lastEnterAt: present
                    ? ((prev && prev.present) ? prev.lastEnterAt : now)
                    : ((prev && prev.lastEnterAt) || 0),
                lastLeaveAt: present
                    ? ((prev && prev.lastLeaveAt) || 0)
                    : ((prev && !prev.present) ? prev.lastLeaveAt : now),
                updatedAt: now,
            };
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
        // req.ip 是请求来源（经公网隧道的出口地址），拿它打不开设备的设置页。
        // 设备自己上报的 WiFi.localIP() 才是局域网地址，单独存 lanIp 供后台展示。
        const bodyIp = typeof body.ip === 'string' ? normalizeIp(body.ip) : '';
        if (bodyIp && /^(10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/.test(bodyIp)) machine.lanIp = bodyIp;
        machine.ip = normalizeIp(req.ip || req.socket.remoteAddress);
        machine.lastSeen = now;
        machines[id] = normalizeMachine(id, machine);
        saveMachines(machines);
        // 感应跳变 → 自动化联动（读的是刚落盘的状态，保证引擎算 occupied 用的是新值）。
        if (pirJump !== null) {
            try {
                sceneEngine.onPresence({ deviceId: id, present: pirJump });
            } catch (error) {
                console.error('[scenes] 感应联动失败:', error.message);
            }
        }
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
                // 远程更新标记：设备心跳里看到比本地记录更新的时间戳就强制升级。
                fwPush: Number(machine.fwPushAt) || 0,
                // 当前发布版本：设备定时唤醒时一次往返即可完成「上报状态 + 查版本」，
                // 不用再单独请求 /firmware/latest。轨道未知时不下发，避免装错固件。
                latestFw: machine.fwTarget ? ((readFirmwareMeta(machine.fwTarget) || {}).version || '') : '',
                // 远程配置版本号：与本机已应用版本不同就去 /api/device/esp/config 拉取。
                cfgVer: normalizeEspCfg(machine.espCfg).ver,
                // 语音播放音量（0~100）：跟心跳一起下发，改完最多 60 秒生效，不重启设备。
                vol: normalizeEspVolume(machine.espVolume),
            },
        };
    }

    // ws 通道专用：设备上报 / 保活不再走 HTTP 心跳，直接操作设备表。
    // lastSeen 写盘节流：machines.json 是全量写，客户端 25s 一次 ping 若每次都
    // 落盘代价过高；60s 仍远小于 90s 的在线判定阈值。
    const TOUCH_THROTTLE_MS = 60 * 1000;
    const lastTouchAt = new Map();
    // 连接时间同样节流：重连风暴时每次握手都全量写 machines.json 不划算，
    // 分钟级精度对后台「x 分钟前」展示已经足够。
    const lastConnectAt = new Map();

    /**
     * 设备主键精确匹配。
     *
     * 不能再用后缀匹配：同一台物理设备上的中控（`android_<hex>`）与电视
     * （裸 `<hex>`）会因此被并成一条记录，`commApp/commAccount` 被双方互相
     * 覆盖，家长端也就无法区分中控和电视。
     */
    function findMachineKey(machines, id) {
        if (!id) return null;
        return machines[id] ? id : null;
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
        if (!machine) return 0;
        const usersByName = new Map(listUsers().map((user) => [user.name, user]));
        const config = resolveMachineConfig(machine, usersByName);
        const layout = readLayouts()[config.layoutKey] || null;
        const sent = pushDeviceConfig(machine.id, {
            t: 'config',
            deviceId: machine.id,
            config: { ...config, layoutUpdatedAt: layout ? layout.updatedAt : 0 },
            ...extra,
        });
        return sent || 0;
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

    /** 设备类型字典变更：给所有在线 home 推一次 config 帧（含新的 deviceTypesUpdatedAt）。
     *  parent（家长端）不用卡片布局，跳过。config 帧只带版本号，App 收到后自行重拉字典。 */
    function pushConfigForDeviceTypes(extra = {}) {
        const machines = readMachines();
        let sent = 0;
        for (const machine of Object.values(machines)) {
            if (machineKind(machine) === 'parent') continue;
            sent += pushConfigToMachine(machine, extra) || 0;
        }
        return sent;
    }

    app.post('/api/device/register', (req, res) => {
        try {
            const machine = upsertMachine(req, req.body || {});
            return jsonOk(res, deviceConfigResponse(machine), '设备已注册');
        } catch (error) {
            return jsonFail(res, error.message);
        }
    });
    // 极轻量保活：主机每 25 秒打一次，让经隧道的 TCP 连接不因空闲被代理掐掉，
    // 这样按键/中继请求能复用热连接（省掉跨城市的三次握手）。
    app.get('/api/device/ping', (req, res) => {
        res.set('Cache-Control', 'no-store');
        return jsonOk(res, { t: Date.now() }, 'pong');
    });
    app.post('/api/device/heartbeat', (req, res) => {
        try {
            const machine = upsertMachine(req, req.body || {});
            return jsonOk(res, deviceConfigResponse(machine), '心跳已记录');
        } catch (error) {
            return jsonFail(res, error.message);
        }
    });

    /**
     * 设备自助设置本机备注名：TV / 中控用 ptools 登录 cookie 鉴权，
     * 按「通信账号」定位自己那台 machine，只写 `name`（空串 = 清除）。
     *
     * 与后台 `PUT /api/admin/machines/:id` 的区别：这里无需管理员会话，
     * 设备改不了 kind / owner / 绑定关系；且只认 `commAccount`，无法越权改别台。
     * 不改 deviceId / commAccount（上传通道名保持不变）。
     */
    app.post('/api/account/machine_name', (req, res) => {
        try {
            const username = String((req.cookies && req.cookies.username) || '').trim();
            if (!username) return jsonFail(res, '未登录', definds.code.UNLOGIN);
            if (typeof req.body?.name !== 'string') return jsonFail(res, '名称格式错误');
            const name = req.body.name.trim().slice(0, MAX_MACHINE_NAME);

            const machines = readMachines();
            const key = Object.keys(machines).find((k) => machines[k].commAccount === username);
            if (!key) return jsonFail(res, '未找到本机设备记录', 404, 404);
            // admin 账号可代管任意设备（用 body.deviceId 指定）；设备本人只认自己的 commAccount。
            const targetKey = username === ADMIN_USERNAME && typeof req.body.deviceId === 'string'
                ? (findMachineKey(machines, req.body.deviceId) || key)
                : key;
            const machine = machines[targetKey];
            machine.name = name;
            machines[targetKey] = normalizeMachine(targetKey, machine);
            saveMachines(machines);
            return jsonOk(res, {
                deviceId: targetKey,
                name: machines[targetKey].name,
                nameSet: machines[targetKey].nameSet,
            }, '设备名称已保存');
        } catch (error) {
            return jsonFail(res, error.message);
        }
    });

    // ------------------------------------------------------------ ESP 小屏控制
    //
    // 一页 = 一台被控设备：屏幕四行文本 + 一组按键。设备端只认「当前页」，
    // 后台配置决定每页显示什么、每个槽位按下做什么；物理 GPIO 在设备本地
    // 设置页分配，不在服务端配置里。

    /** 取设备记录并校验存在；无效时已写响应，返回 null。 */
    function espMachineOrFail(req, res, id) {
        if (!id) {
            jsonFail(res, 'deviceId 无效');
            return null;
        }
        const machine = readMachines()[id];
        if (!machine) {
            jsonFail(res, '设备未注册', definds.code.FAILED, 404);
            return null;
        }
        return machine;
    }

    /** 页码收敛：越界落在本次配置的页数内（设备本地缓存过期时也能返回有效页）。 */
    function clampEspPage(value, total) {
        const page = Number(value);
        if (!Number.isInteger(page) || page < 1) return 1;
        return page > total ? total : page;
    }

    /**
     * 屏幕底部按键提示：`1:空调开关  2:客厅灯`（一页最多 8 个）。
     *
     * 槽位号与名称之间用中文冒号，按键之间用两个空格分隔——直接拼接
     * `1空调开关2客厅灯` 在 128px 屏上完全分不清哪里是一个按键。
     * 槽位配了显示名（如「蓝色按钮」）时用名字代替数字。
     * 这里用**完整名称**，超出一行时由固件按自己的节拍走马灯滚动。
     */
    function espKeyHints(buttons, slotNames) {
        const names = slotNames || {};
        return buttons
            .filter((item) => item.enabled && item.slot >= 1)
            .sort((a, b) => a.slot - b.slot)
            .map((item) => `${names[String(item.slot)] || item.slot}:${(item.name || item.label || '').trim()}`)
            .join('  ');
    }

    /**
     * 空白行清洗：只由占位符 `--`、分隔符 `·` 和空白组成的行视为「没有值」。
     *
     * 设备类型字典在实体缺状态时会产出 `--` / `-- · --`，直接下发会让
     * 128×64 屏幕多出一行噪音；这里统一置空，固件遇到空串就不绘制。
     */
    function cleanEspDisplayLine(value) {
        const text = String(value == null ? '' : value).trim();
        if (!text) return '';
        return text.replace(/--/g, '').replace(/·/g, '').trim() ? text : '';
    }

    // 自定义模板里可直接写实体 id 或属性：
    // `卧室灯{switch.bedroom_light}`、`当前{climate.bed.current_temperature}`。
    const ESP_TPL_TOKEN_RE = /\{([a-z][a-z0-9_]*\.[a-z0-9_]+)(?:\.([a-z0-9_]+))?\}/gi;
    // 这些 sys 变量由固件在绘制时取本机实时值，服务端不下发、原样保留 token。
    const ESP_FIRMWARE_SYS_KEYS = new Set([
        'sys.online', 'sys.wifi', 'sys.rssi', 'sys.present', 'sys.occupied',
        'sys.ip', 'sys.page', 'sys.total', 'sys.pageof', 'sys.batt', 'sys.volt',
    ]);

    /**
     * 抽出模板里的实体令牌（含可选第三段属性），供取状态与渲染共用。
     * key 与 `{token}` 原文一致，renderEspTemplate 直接查 ctx.entities[key]。
     * 与前端 11-esp.js 的 espTemplateTokens 同构。
     */
    function parseEspTemplateTokens(text) {
        const out = [];
        ESP_TPL_TOKEN_RE.lastIndex = 0;
        let m;
        while ((m = ESP_TPL_TOKEN_RE.exec(String(text || '')))) {
            // sys.* 是内置变量，不是 HA 实体：从 HA 取数集合里排除，避免被当实体查成空。
            if (m[1].toLowerCase() === 'sys' || m[1].toLowerCase().startsWith('sys.')) continue;
            const attr = m[2] || 'state';
            out.push({ baseId: m[1], attr, key: attr === 'state' ? m[1] : `${m[1]}.${attr}` });
        }
        return out;
    }

    /** 抽出模板里用到的系统变量全名（sys.time / sys.weather.gz / image …），供按需取数。 */
    function parseEspSysTokens(text) {
        const out = new Set();
        const re = /\{([a-zA-Z][a-zA-Z0-9_.]*)\}/g;
        let m;
        while ((m = re.exec(String(text || ''))) !== null) {
            const key = m[1];
            if (key === 'image' || key.toLowerCase().startsWith('sys.')) out.add(key);
        }
        return out;
    }

    /** 值替换：`on=开启, off=关闭`（逗号 / 分号 / 换行分隔）。 */
    function parseEspValueMap(text) {
        const map = new Map();
        for (const line of String(text || '').split(/[\n,;，；]+/)) {
            const m = line.match(/^\s*([^=:：]+?)\s*[=:：]\s*(.*?)\s*$/);
            if (!m || !m[1]) continue;
            map.set(m[1], m[2]);
        }
        return map;
    }

    /** 按实体的值替换：`entity_id: on=有人, off=无人`（一行一个实体）。 */
    function parseEspEntityValueMap(text) {
        const map = new Map();
        for (const line of String(text || '').split('\n')) {
            const idx = line.search(/[:：]/);
            if (idx <= 0) continue;
            const entityId = line.slice(0, idx).trim();
            if (!ESP_VALUE_TARGET_RE.test(entityId)) continue;
            const rules = parseEspValueMap(line.slice(idx + 1));
            if (rules.size) map.set(entityId, rules);
        }
        return map;
    }

    /**
     * 把 HA 状态里的 state 按值替换表翻译。
     *
     * 优先用该实体自己的替换表，没有命中再落到页面级兜底表；
     * 只动 state，温度等属性原样保留。
     */
    function mapEspStates(states, globalMap, entityMap) {
        const out = {};
        for (const [id, state] of Object.entries(states || {})) {
            if (!state || typeof state !== 'object') continue;
            const next = Object.assign({}, state);
            const raw = next.state == null ? '' : String(next.state);
            const own = entityMap && entityMap.get(id);
            if (own && own.has(raw)) next.state = own.get(raw);
            else if (globalMap.has(raw)) next.state = globalMap.get(raw);
            out[id] = next;
        }
        return out;
    }

    /** 取实体的显示值：优先指定属性，缺失时回落 state，都没有返回空串。 */
    function espStateValue(stateObj, attr) {
        if (!stateObj || typeof stateObj !== 'object') return '';
        const attrs = stateObj.attributes || {};
        if (attr && attrs[attr] != null && attrs[attr] !== '') return String(attrs[attr]);
        if (stateObj.state != null && stateObj.state !== '') return String(stateObj.state);
        return '';
    }

    /**
     * 渲染页面自定义模板。
     *
     * 占位符：
     * - `{main}` / `{s1}` / `{s2}`：三个绑定实体的值；
     * - `{title}` / `{名称}`：页面名；
     * - `{domain.entity_id}`：任意实体当前 state（可放多个）。
     * - `{domain.entity_id.attr}`：该实体的指定属性（如 temperature/current_temperature），
     *   属性缺失时回落 state；同名属性不存在时不影响其它占位符。
     * 缺值替换为空串，不留下 `--`。
     */
    function renderEspTemplate(tpl, ctx) {
        return String(tpl || '')
            .replace(/\{([^{}]+)\}/g, (all, rawKey) => {
                const key = rawKey.trim();
                if (key === 'main') return ctx.main;
                if (key === 's1') return ctx.s1;
                if (key === 's2') return ctx.s2;
                if (key === 'title' || key === '名称') return ctx.title;
                // 系统变量：从 ctx.sys 字典取（时间/农历/天气/图片由服务端算好）。
                // 本机类变量（online/wifi/rssi/present/occupied/ip/page/total/pageOf）
                // 由固件绘制时替换，服务端原样保留 token 交给固件识别。
                const lowerKey = key.toLowerCase();
                if (lowerKey.startsWith('sys.') || key === 'image') {
                    // 图片由独立 IMG 行下发点阵，不占文本行：正文 {image} 必须渲染为空，
                    // 否则 base64 数据会被 DISPLAY 行当文字画到屏幕上（真机乱码）。
                    if (key === 'image') return '';
                    if (ctx.sys && Object.prototype.hasOwnProperty.call(ctx.sys, key)) return ctx.sys[key];
                    // 未定义变量整段省略（拍板项 2）；本机类留给固件。
                    return ESP_FIRMWARE_SYS_KEYS.has(lowerKey) ? `{${key}}` : '';
                }
                return ctx.entities[key] || '';
            })
            .replace(/[ \t]+/g, ' ')
            .replace(/--/g, '')
            .trim();
    }

    app.get('/api/device/esp/actions', async (req, res) => {
        const id = safeDeviceId(req.query.deviceId);
        const machine = espMachineOrFail(req, res, id);
        if (!machine) return undefined;
        const pages = machine.espPages;
        const pageTotal = Math.max(1, pages.length);
        const page = clampEspPage(req.query.page, pageTotal);
        const pageObj = pages[page - 1] || null;
        const actions = pageObj ? pageObj.buttons.filter((item) => item.enabled) : [];

        // 按页内模板里写的实体读 HA 状态，解析屏幕四行文本。
        // 内容完全由模板决定，无设备类型字典兜底；固件只收纯文本。
        let display = {
            title: pageObj ? pageObj.name : (machine.name || ''),
            main: pageObj ? '' : '未配置',
            sub: pageObj ? '' : '请在 Admin「ESP 设备分类」添加页面',
            keys: espKeyHints(actions, machine.espSlotNames),
            homeLabel: '当前状态',
        };
        // 「显示图片」勾选后整页只出点阵图：标题/正文/按键提示全部清空。
        // 老配置没有 enabled 字段时，模板只写 {image} 仍按纯图片页兼容。
        let showImageOnly = false;
        // 显示开关在 if(pageObj) 外也要用（ROWS 行组装），缺省按显示处理。
        const showTitle = !pageObj || pageObj.showTitle !== false;
        const showKeys = !pageObj || pageObj.showKeys !== false;
        const line3On = !showTitle || !showKeys;
        const line4On = !showTitle && !showKeys;
        if (pageObj) {
            const tplMain = pageObj.tplMain || '';
            const tplSub = pageObj.tplSub || '';
            // 行3/行4 只有对应开关关掉（让出屏幕行）时才参与取数与下发，
            // 避免「编辑了但真机看不到」以及无谓的 HA 状态查询。
            const tplLine3 = line3On ? (pageObj.tplLine3 || '') : '';
            const tplLine4 = line4On ? (pageObj.tplLine4 || '') : '';
            // 主/副状态模板 + 已开放的行3/行4，供令牌解析与实体收集共用。
            const tplAll = `${tplMain} ${tplSub} ${tplLine3} ${tplLine4}`;
            // 模板里可直接写 {switch.xxx} / {climate.xxx.temperature}，这些实体也要一起取状态。
            const tplTokens = parseEspTemplateTokens(tplAll);
            const tplEntityIds = tplTokens.map((token) => token.baseId);
            // 三段式遥控标签 `{remote.xxx.channel}`：把基础实体 id 也纳入取状态，
            // 但主正则只匹配两段，这里单独收集（去重在下面统一做）。
            REMOTE_TPL_TOKEN_RE.lastIndex = 0;
            let remoteMatch;
            while ((remoteMatch = REMOTE_TPL_TOKEN_RE.exec(tplAll))) {
                if (REMOTE_STATE_FIELDS.includes(remoteMatch[2])) {
                    tplEntityIds.push(`remote.${remoteMatch[1]}`);
                }
            }
            // 屏幕内容只认页内模板里写的实体；无设备类型字典兜底。
            const entityIds = [...new Set(tplEntityIds.filter(Boolean))];
            const remoteIds = entityIds.filter((eid) => eid.startsWith('remote.'));
            const haIds = entityIds.filter((eid) => !eid.startsWith('remote.'));

            // ctx 构造不再被 entityIds.length 包裹：纯 sys 变量页（无 HA 实体）也要渲染。
            const ctx = {
                title: pageObj.name,
                entities: {},
                sys: {},
            };
            // 值替换（全局 + 按实体）对字典、自定义模板与遥控语义字段同时生效。
            const globalMap = parseEspValueMap(pageObj.valueMap);
            const entityMap = parseEspEntityValueMap(pageObj.entityValueMap);

            // ---- 系统变量（按需取数）----
            const sysTokens = parseEspSysTokens(tplAll);
            // 显示图片开关优先于模板；旧配置按「模板只有 {image}」兼容。
            // 混编页（不勾选、模板里图 + 文字）不受影响，文字照常显示。
            const legacyImageOnly = sysTokens.has('image')
                && !tplAll.replace(/\{image\}/g, ' ').trim();
            showImageOnly = !!(pageObj.image && pageObj.image.enabled && pageObj.image.data)
                || legacyImageOnly;
            if (sysTokens.size) {
                // 时间：按设备时区算好字符串；设备本地再按 millis 走秒。
                // espTimezone 是相对 UTC 的分钟偏移；缺省按东八区 +480。
                const tzRaw = Number(machine.espTimezone);
                const tzOffsetMin = Number.isFinite(tzRaw) ? tzRaw : 480;
                const now = new Date(Date.now() + tzOffsetMin * 60000);
                const pad2 = (n) => String(n).padStart(2, '0');
                const hhmm = `${pad2(now.getUTCHours())}:${pad2(now.getUTCMinutes())}`;
                const hhmmss = `${hhmm}:${pad2(now.getUTCSeconds())}`;
                const weekCn = ['日', '一', '二', '三', '四', '五', '六'][now.getUTCDay()];
                const mmdd = `${pad2(now.getUTCMonth() + 1)}-${pad2(now.getUTCDate())}`;
                ctx.sys['sys.time'] = hhmm;
                ctx.sys['sys.timeSec'] = hhmmss;
                ctx.sys['sys.date'] = `${mmdd} 周${weekCn}`;
                ctx.sys['sys.lunar'] = lunarText(now);

                // 天气：只对模板引用到的 id 取数。
                const weatherIds = [...sysTokens]
                    .filter((k) => k.startsWith('sys.weather.'))
                    .map((k) => k.slice('sys.weather.'.length));
                if (weatherIds.length) {
                    try {
                        const built = await espSys.buildWeatherDict(weatherIds);
                        for (const [wid, value] of Object.entries(built.dict)) {
                            ctx.sys[`sys.weather.${wid}`] = value;
                        }
                    } catch (error) {
                        console.warn(`[esp] ${id} 天气取数降级:`, error.message);
                    }
                }
                // 图片不进文本 ctx：点阵走独立 IMG 行下发，{image} 在正文里恒为空串。
            }

            if (haIds.length) {
                try {
                    const rawStates = await haCatalogService.getStates(haIds);
                    const states = mapEspStates(rawStates, globalMap, entityMap);
                    for (const token of tplTokens) {
                        if (remoteIds.includes(token.baseId) || token.baseId.startsWith('remote.')) continue;
                        let value = espStateValue(states[token.baseId], token.attr);
                        // 属性也走值替换，与前端 espEntityValue 同构；
                        // state 已在 mapEspStates 里翻译过，避免二次替换。
                        if (token.attr !== 'state') {
                            const own = entityMap.get(token.baseId);
                            if (own && own.has(value)) value = own.get(value);
                            else if (globalMap.has(value)) value = globalMap.get(value);
                        }
                        ctx.entities[token.key] = value;
                    }
                } catch (error) {
                    // 读 HA 失败不挡按键：显示层降级，按键白名单照常下发。
                    console.warn(`[esp] ${id} 第 ${page} 页解析显示文本失败，降级:`, error.message);
                }
            }
            if (remoteIds.length) {
                const machines = readMachines();
                const byEntity = new Map();
                for (const item of Object.values(machines)) {
                    if (item.kind !== 'home' && item.kind !== 'tv') continue;
                    byEntity.set(remoteEntityId(item.id), item);
                }
                for (const entityId of remoteIds) {
                    const target = byEntity.get(entityId);
                    const fields = target
                        ? remoteStateFields(remoteStateOf(target.commAccount || ''))
                        : null;
                    // 整体摘要 `{remote.xxx}`（兼容旧模板）。
                    ctx.entities[entityId] = fields ? fields.text : '';
                    // 语义字段 `{remote.xxx.page/channel/volume/sleep/sleepLeft}`。
                    for (const key of REMOTE_STATE_FIELDS) {
                        const tokenKey = `${entityId}.${key}`;
                        let value = fields ? (fields[key] || '') : '';
                        // 遥控字段是「开启/关闭」这类中文值，按实体替换优先，
                        // 再接页面级兜底；与 HA 属性的替换链路一致。
                        const own = entityMap.get(tokenKey);
                        if (own && own.has(value)) value = own.get(value);
                        else if (globalMap.has(value)) value = globalMap.get(value);
                        ctx.entities[tokenKey] = value;
                    }
                }
            }
            // 屏幕内容完全来自页内模板：填了才显示，留空就是空行（无字典兜底）。
            if (tplMain) display.main = renderEspTemplate(tplMain, ctx);
            if (tplSub) display.sub = renderEspTemplate(tplSub, ctx);
            if (tplLine3) display.line3 = renderEspTemplate(tplLine3, ctx);
            if (tplLine4) display.line4 = renderEspTemplate(tplLine4, ctx);
        }
        // 没有值就留空：`--` / `-- · --` 只在后台预览里提示「未绑定」，
        // 不上屏，避免 128×64 上多出两行噪音。
        display.main = cleanEspDisplayLine(display.main);
        display.sub = cleanEspDisplayLine(display.sub);
        display.line3 = cleanEspDisplayLine(display.line3);
        display.line4 = cleanEspDisplayLine(display.line4);
        // 显示开关关掉的行直接置空，固件按「空行不绘制 + 后续行上移」处理。
        if (pageObj && pageObj.showTitle === false) display.title = '';
        if (pageObj && pageObj.showKeys === false) display.keys = '';
        if (showImageOnly) {
            // 纯图片页不叠任何文字：标题、所有内容行、按键提示都留空。
            display.title = '';
            display.main = '';
            display.sub = '';
            display.line3 = '';
            display.line4 = '';
            display.keys = '';
        }

        // 固件没接 JSON 库，`format=text` 给：
        // PAGE|当前页|总页数|循环|空闲秒 → SCREEN|熄屏秒
        // → DISPLAY|标题|主状态|副状态|按键提示
        // → 每行一个按键 slot|名称|名称|entityId|action|id
        //   （第 2 段保留旧固件的 label 字段，值与完整名称一致）。
        if (String(req.query.format || '') === 'text') {
            const pageLine = ['PAGE', page, pageTotal, pageObj && pageObj.loop === false ? '0' : '1', (pageObj && pageObj.idle) || 0].join('|');
            // 熄屏秒数（设备级）：固件据此在人离开后熄屏，0 = 常亮。
            const screenLine = ['SCREEN', normalizeEspScreen(machine.espScreen).onSeconds].join('|');
            // 每页状态栏配置（v0.5）：enabled/showPage/showTime/showWifiIcon/showRssi/showIp/showBatt/showVolt → 0/1。
            // 固件按此绘制顶部状态栏；enabled=0 时内容区上移重排。
            const sb = normalizeEspStatusBar(pageObj && pageObj.statusBar);
            const barLine = ['BAR', sb.enabled ? 1 : 0, sb.showPage ? 1 : 0, sb.showTime ? 1 : 0,
                sb.showWifiIcon ? 1 : 0, sb.showRssi ? 1 : 0, sb.showIp ? 1 : 0,
                sb.showBatt ? 1 : 0, sb.showVolt ? 1 : 0].join('|');
            // 状态栏时间（HH:MM）：服务端按设备时区算好；设备无需 RTC/NTP。
            const tzRawText = Number(machine.espTimezone);
            const tzMinText = Number.isFinite(tzRawText) ? tzRawText : 480;
            const nowText = new Date(Date.now() + tzMinText * 60000);
            const p2 = (n) => String(n).padStart(2, '0');
            const timeLine = ['TIME', `${p2(nowText.getUTCHours())}:${p2(nowText.getUTCMinutes())}`].join('|');
            // DISPLAY 保留老四段（老固件只读前 4 段，行为不变），末尾追加行3/行4 供测试与新客户端核对。
            const displayLine = ['DISPLAY', display.title, display.main, display.sub, display.keys,
                display.line3 || '', display.line4 || ''].join('|');
            // ROWS 是 v4.2 起真正绘制的四行：按显示开关把「让位」出来的内容行排进去。
            // 老固件不认这一行会跳过，继续按 DISPLAY 画，OTA 后由新固件接管。
            // 空行不占位：隐藏标题/按键或模板留空时，后续内容整体向上收拢。
            const allRows = [];
            if (showTitle) allRows.push(display.title);
            allRows.push(display.main, display.sub);
            if (line3On) allRows.push(display.line3 || '');
            if (line4On) allRows.push(display.line4 || '');
            if (showKeys) allRows.push(display.keys);
            const rows = allRows.filter((text) => String(text || '').trim() !== '').slice(0, 4);
            const rowsLine = ['ROWS', ...rows].join('|');
            const lines = actions.map((item) => [item.slot, item.label, item.name, item.entityId, item.action + (item.param ? `(${item.param})` : ''), item.id].join('|'));
            // 图片（v0.5）：页面配了 {image} 且有数据时下发一行 IMG|id|base64|invert。
            // 第 4 段是新增的反色位；老固件只读前 3 段，仍按原样显示，兼容。
            const extra = [];
            if (pageObj && pageObj.image && pageObj.image.data
                && (pageObj.image.enabled === true
                    || /\{image\}/.test(`${pageObj.tplMain || ''} ${pageObj.tplSub || ''}`))) {
                extra.push(['IMG', pageObj.id,
                    String(pageObj.image.data).replace(/[|\r\n]/g, ''),
                    pageObj.image.invert ? 1 : 0].join('|'));
            }
            return res.type('text/plain; charset=utf-8').send(
                [pageLine, screenLine, barLine, timeLine, displayLine, rowsLine].concat(extra, lines).join('\n'));
        }
        return jsonOk(res, { deviceId: id, page, pageTotal, actions, display });
    });

    // ------------------------------------------------------------ ESP 长按录音
    //
    // 设备在录音键上松开手指后，把 16kHz/16bit/单声道 WAV 作为原始请求体 POST 上来；
    // 后台「ESP 设备分类」页可试听。每台设备只保留最近 20 条，避免占满磁盘。
    const espAudioDir = path.join(datasDir, 'esp_audio');
    fs.mkdirSync(espAudioDir, { recursive: true });
    const ESP_AUDIO_FILE_RE = /^[A-Za-z0-9_-]+_\d{10,16}_\d{1,2}\.wav$/;
    const ESP_AUDIO_MAX_BYTES = 2 * 1024 * 1024;
    const ESP_AUDIO_KEEP = 20;

    // 录音与语音文件都存到 yuntu（公网直连，设备下载比隧道快一个量级）。
    // 本地只作转发失败时的兜底：成功即删本地文件，列表优先查 yuntu。
    const espAudioIndexFile = path.join(espAudioDir, 'index.json');

    function readYuntuConfig() {
        const cfg = readJson(path.join(datasDir, 'forward_config.json'), {}) || {};
        return {
            // enabled：普通上传镜像转发总开关（原有行为）。
            enabled: cfg.enabled !== false,
            // espAudioEnabled：仅控制设备录音 / 语音播放文件要不要存 yuntu，
            // 与总开关解耦——关掉它不影响原有上传转发。
            audioEnabled: cfg.espAudioEnabled !== false,
            baseUrl: String(cfg.baseUrl || '').replace(/\/+$/, ''),
            serviceToken: String(cfg.serviceToken || ''),
        };
    }

    function readAudioIndex() {
        const raw = readJson(espAudioIndexFile, {});
        return raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {};
    }

    function writeAudioIndex(map) {
        const keys = Object.keys(map)
            .sort((a, b) => (Number(map[b].ts) || 0) - (Number(map[a].ts) || 0))
            .slice(0, 200);
        const out = {};
        for (const key of keys) out[key] = map[key];
        writeJson(espAudioIndexFile, out);
    }

    /** 给 yuntu 文件签一个 7 天有效的免登录下载链接（HMAC 与服务端一致）。 */
    function yuntuAudioUrl(fileId) {
        const { enabled, audioEnabled, baseUrl, serviceToken } = readYuntuConfig();
        if (!enabled || !audioEnabled || !baseUrl || !serviceToken || !fileId) return '';
        const exp = nowMs() + 7 * 24 * 3600 * 1000;
        const sig = crypto.createHmac('sha256', serviceToken)
            .update(`${fileId}.${exp}`).digest('hex').slice(0, 32);
        return `${baseUrl}/api/files/${encodeURIComponent(fileId)}/audio?exp=${exp}&sig=${sig}`;
    }

    // 只按 originPath 前缀查：originServer 是转发方主机名，不同机器不一样，不能用来过滤。
    async function yuntuListAudio(prefix, limit) {
        const { enabled, audioEnabled, baseUrl, serviceToken } = readYuntuConfig();
        if (!enabled || !audioEnabled || !baseUrl || !serviceToken) throw new Error('yuntu 未启用');
        const url = `${baseUrl}/api/files/list?prefix=${encodeURIComponent(prefix)}&limit=${limit}`;
        const resp = await fetch(url, {
            headers: { 'x-service-token': serviceToken },
            signal: AbortSignal.timeout(8000),
        });
        const body = await resp.json().catch(() => null);
        if (!resp.ok || !body || Number(body.code) !== 0) throw new Error(`yuntu list ${resp.status}`);
        return body.data && Array.isArray(body.data.items) ? body.data.items : [];
    }

    /** 录音文件名 → yuntu 文件 id：先查本地索引，再按设备前缀列一次。 */
    async function findRecordingId(safeId, name) {
        const index = readAudioIndex();
        const hit = index[`${safeId}/${name}`];
        if (hit && hit.id) return hit.id;
        try {
            const items = await yuntuListAudio(`esp_audio/${safeId}/`, ESP_AUDIO_KEEP);
            const found = items.find((item) => String(item.name || '') === name);
            if (found) {
                index[`${safeId}/${name}`] = { id: found.id, ts: nowMs() };
                writeAudioIndex(index);
                return found.id;
            }
        } catch (_) { /* 交给本地兜底 */ }
        return '';
    }

    app.post('/api/device/esp/audio',
        express.raw({ type: ['audio/wav', 'application/octet-stream'], limit: '2mb' }),
        async (req, res) => {
            const id = safeDeviceId(req.query.deviceId);
            const machine = espMachineOrFail(req, res, id);
            if (!machine) return undefined;
            const buf = Buffer.isBuffer(req.body) ? req.body : null;
            if (!buf || buf.length < 200) return jsonFail(res, '录音数据为空或过短');
            if (buf.length > ESP_AUDIO_MAX_BYTES) return jsonFail(res, '录音文件过大');
            if (buf.slice(0, 4).toString('ascii') !== 'RIFF'
                || buf.slice(8, 12).toString('ascii') !== 'WAVE') {
                return jsonFail(res, '不是合法的 WAV 数据');
            }
            const slot = Math.min(MAX_ESP_BUTTONS, Math.max(0, Number(req.query.slot) || 0));
            const ms = Math.min(60000, Math.max(0, Number(req.query.ms) || 0));
            const safeId = id.replace(/[^A-Za-z0-9_-]/g, '_');
            const name = `${safeId}_${Date.now()}_${slot}.wav`;
            try {
                fs.writeFileSync(path.join(espAudioDir, name), buf);
            } catch (error) {
                console.error('[esp] 录音写入失败:', error.message);
                return jsonFail(res, '录音保存失败');
            }
            // 只保留本设备最近 N 条；清理失败不影响本次上传。
            try {
                const files = fs.readdirSync(espAudioDir)
                    .filter((n) => n.startsWith(`${safeId}_`) && ESP_AUDIO_FILE_RE.test(n))
                    .map((n) => ({ n, t: Number(n.slice(safeId.length + 1).split('_')[0]) || 0 }))
                    .sort((a, b) => b.t - a.t);
                for (const item of files.slice(ESP_AUDIO_KEEP)) {
                    fs.unlinkSync(path.join(espAudioDir, item.n));
                }
            } catch (_) { /* 忽略清理错误 */ }
            // 转发到 yuntu，成功后删本地；失败保留本地兜底。
            if (forward && readYuntuConfig().audioEnabled) {
                try {
                    const result = await forward.mirrorAndWait(
                        path.join(espAudioDir, name), `esp_audio/${safeId}/${name}`);
                    if (result && result.id) {
                        const index = readAudioIndex();
                        index[`${safeId}/${name}`] = { id: result.id, ts: nowMs() };
                        writeAudioIndex(index);
                        try { fs.unlinkSync(path.join(espAudioDir, name)); } catch (_) { /* 已删 */ }
                    }
                } catch (error) {
                    console.warn('[esp] 录音转发 yuntu 失败，保留本地文件:', error.message);
                }
            }
            console.log(`[esp] ${id} 录音已上传：${name}（${buf.length} 字节 / ${ms}ms）`);
            return jsonOk(res, { name, size: buf.length, ms }, '录音已收到');
        });

    // 录音列表：优先从 yuntu 取（带 7 天签名直链），取不到再回落到本地兜底目录。
    app.get('/api/admin/machines/:id/esp/audio', requireAdmin, async (req, res) => {
        const id = safeDeviceId(req.params.id);
        const safeId = id.replace(/[^A-Za-z0-9_-]/g, '_');
        const localFiles = () => {
            let names = [];
            try { names = fs.readdirSync(espAudioDir); } catch (_) { names = []; }
            return names
                .filter((n) => n.startsWith(`${safeId}_`) && ESP_AUDIO_FILE_RE.test(n))
                .map((n) => {
                    const rest = n.slice(safeId.length + 1, -4);
                    const [ts, slot] = rest.split('_');
                    let size = 0;
                    try { size = fs.statSync(path.join(espAudioDir, n)).size; } catch (_) { /* 已删除 */ }
                    return {
                        name: n,
                        ts: Number(ts) || 0,
                        slot: Number(slot) || 0,
                        size,
                        url: `/api/admin/esp/audio/${encodeURIComponent(n)}`,
                    };
                })
                .sort((a, b) => b.ts - a.ts)
                .slice(0, ESP_AUDIO_KEEP);
        };
        let files = [];
        try {
            const items = await yuntuListAudio(`esp_audio/${safeId}/`, ESP_AUDIO_KEEP);
            files = items
                .map((item) => {
                    const name = String(item.name || '');
                    if (!ESP_AUDIO_FILE_RE.test(name)) return null;
                    const rest = name.slice(safeId.length + 1, -4);
                    const [ts, slot] = rest.split('_');
                    return {
                        name,
                        ts: Number(ts) || Date.parse(item.createdAt) || 0,
                        slot: Number(slot) || 0,
                        size: Number(item.size) || 0,
                        url: yuntuAudioUrl(item.id),
                        remote: true,
                    };
                })
                .filter(Boolean)
                .sort((a, b) => b.ts - a.ts)
                .slice(0, ESP_AUDIO_KEEP);
        } catch (error) {
            console.warn('[esp] 读取 yuntu 录音列表失败，回落本地:', error.message);
        }
        if (!files.length) files = localFiles();
        return jsonOk(res, { deviceId: id, files });
    });

    // 试听：<audio> 同源请求会自动带上后台会话 cookie，直接用 requireAdmin 保护。
    app.get('/api/admin/esp/audio/:name', requireAdmin, (req, res) => {
        const name = String(req.params.name || '');
        if (!ESP_AUDIO_FILE_RE.test(name)) return res.status(404).end();
        const file = path.join(espAudioDir, name);
        if (!fs.existsSync(file)) return res.status(404).end();
        res.setHeader('Cache-Control', 'no-store');
        res.type('audio/wav');
        return res.sendFile(file);
    });

    // ------------------------------------------------------------ ESP 语音播放
    //
    // 后台把一段 PCM WAV（上传，或直接复用刚录的音）排进该设备的播放队列；
    // 设备每 5 秒问一次，取到任务后下载播放，播完回报 done。队列与文件都在 datas/esp_speech。
    const espSpeechDir = path.join(datasDir, 'esp_speech');
    fs.mkdirSync(espSpeechDir, { recursive: true });
    const espSpeechJobsFile = path.join(espSpeechDir, 'jobs.json');
    const ESP_SPEECH_KEEP = 5;                 // 每台设备最多排队条数
    const ESP_SPEECH_TTL_MS = 10 * 60 * 1000;  // 没被取走就过期，避免设备离线时无限堆积
    const ESP_SPEECH_FILE_RE = /^speech_[a-f0-9]{12}\.wav$/;

    /** 生成一段 PCM WAV 测试音（16kHz 单声道 16bit），用来排查接线。 */
    function makeToneWav(ms, hz, volume) {
        const rate = 16000;
        const samples = Math.max(1, Math.round(rate * ms / 1000));
        const dataSize = samples * 2;
        const buf = Buffer.alloc(44 + dataSize);
        buf.write('RIFF', 0, 'ascii');
        buf.writeUInt32LE(36 + dataSize, 4);
        buf.write('WAVE', 8, 'ascii');
        buf.write('fmt ', 12, 'ascii');
        buf.writeUInt32LE(16, 16);
        buf.writeUInt16LE(1, 20);
        buf.writeUInt16LE(1, 22);
        buf.writeUInt32LE(rate, 24);
        buf.writeUInt32LE(rate * 2, 28);
        buf.writeUInt16LE(2, 32);
        buf.writeUInt16LE(16, 34);
        buf.write('data', 36, 'ascii');
        buf.writeUInt32LE(dataSize, 40);
        const amp = Math.round(32767 * Math.max(0.05, Math.min(1, volume || 0.3)));
        const fade = rate * 0.02;
        for (let i = 0; i < samples; i++) {
            const edge = Math.min(i, samples - 1 - i) / fade;
            const gain = Math.min(1, Math.max(0, edge));
            buf.writeInt16LE(Math.round(Math.sin(2 * Math.PI * hz * i / rate) * amp * gain), 44 + i * 2);
        }
        return buf;
    }

    function readSpeechJobs() {
        const raw = readJson(espSpeechJobsFile, {});
        return raw && typeof raw === 'object' && !Array.isArray(raw) ? raw : {};
    }

    function writeSpeechJobs(jobs) {
        writeJson(espSpeechJobsFile, jobs);
    }

    /** 从队列移除一条任务并删文件；返回被移除的任务。 */
    function dropSpeechJob(jobs, deviceId, jobId) {
        const list = Array.isArray(jobs[deviceId]) ? jobs[deviceId] : [];
        const job = list.find((item) => item.id === jobId) || null;
        if (job && ESP_SPEECH_FILE_RE.test(job.file)) {
            try {
                fs.rmSync(path.join(espSpeechDir, job.file), { force: true });
            } catch (_) { /* 忽略删除失败 */ }
        }
        jobs[deviceId] = list.filter((item) => item.id !== jobId);
        if (!jobs[deviceId].length) delete jobs[deviceId];
        return job;
    }

    // 后台：上传 WAV（原始请求体），或用 ?rec=<录音文件名> 把设备刚录的音发回去播放。
    // 录音与上传文件都先放 yuntu，设备拿签名直链下载；转发失败才用本地副本。
    app.post('/api/admin/machines/:id/esp/speech', requireAdmin,
        express.raw({ type: ['audio/wav', 'application/octet-stream'], limit: '2mb' }),
        async (req, res) => {
            const id = safeDeviceId(req.params.id);
            if (!id) return jsonFail(res, '设备 id 无效');
            const safeId = id.replace(/[^A-Za-z0-9_-]/g, '_');
            const jobs = readSpeechJobs();
            // 顺手清掉过期的旧任务。
            for (const key of Object.keys(jobs)) {
                for (const job of [...(jobs[key] || [])]) {
                    if (nowMs() - (Number(job.createdAt) || 0) > ESP_SPEECH_TTL_MS) {
                        dropSpeechJob(jobs, key, job.id);
                    }
                }
            }
            const recName = String(req.query.rec || '');
            let buf = Buffer.isBuffer(req.body) ? req.body : null;
            let label = String(req.query.name || '').trim().replace(/[|\r\n]/g, ' ').slice(0, 40) || '语音';
            let fileUrl = '';
            if (String(req.query.tone || '') === '1') {
                buf = makeToneWav(1200, 880, 0.45);
                label = '测试音';
            } else if (recName) {
                if (!ESP_AUDIO_FILE_RE.test(recName)) return jsonFail(res, '录音文件名无效');
                // 录音本身已在 yuntu：直接签直链，不再本地存一份。
                const recId = await findRecordingId(safeId, recName);
                if (recId) fileUrl = yuntuAudioUrl(recId);
                if (!fileUrl) {
                    const src = path.join(espAudioDir, recName);
                    if (!fs.existsSync(src)) return jsonFail(res, '录音已不存在');
                    buf = fs.readFileSync(src);
                }
                label = '录音回放';
            }
            if (!fileUrl) {
                if (!buf || buf.length < 200) return jsonFail(res, '音频数据为空或过短');
                if (buf.length > ESP_AUDIO_MAX_BYTES) return jsonFail(res, '音频文件过大（上限 2MB）');
                if (buf.slice(0, 4).toString('ascii') !== 'RIFF'
                    || buf.slice(8, 12).toString('ascii') !== 'WAVE') {
                    return jsonFail(res, '只支持 PCM WAV（RIFF/WAVE）');
                }
            }
            const jobId = crypto.randomBytes(6).toString('hex');
            const file = `speech_${jobId}.wav`;
            let localFile = '';
            if (!fileUrl && buf) {
                try {
                    fs.writeFileSync(path.join(espSpeechDir, file), buf);
                    localFile = file;
                } catch (error) {
                    return jsonFail(res, `保存失败：${error.message}`);
                }
                // 能上 yuntu 就上，设备直连下载比走隧道快得多。
                if (forward && readYuntuConfig().audioEnabled) {
                    try {
                        const result = await forward.mirrorAndWait(
                            path.join(espSpeechDir, file), `esp_speech/${safeId}/${file}`);
                        if (result && result.id) {
                            fileUrl = yuntuAudioUrl(result.id);
                            try { fs.rmSync(path.join(espSpeechDir, file), { force: true }); } catch (_) { /* 已删 */ }
                            localFile = '';
                        }
                    } catch (error) {
                        console.warn('[esp] 语音转发 yuntu 失败，保留本地副本:', error.message);
                    }
                }
            }
            const list = Array.isArray(jobs[id]) ? jobs[id] : [];
            list.push({
                id: jobId,
                file: localFile,
                fileUrl,
                name: label,
                size: buf ? buf.length : 0,
                createdAt: nowMs(),
                state: 'queued',
                updatedAt: nowMs(),
            });
            // 超上限先丢最旧的（含文件）。
            while (list.length > ESP_SPEECH_KEEP) {
                const old = list.shift();
                if (old && ESP_SPEECH_FILE_RE.test(old.file || '')) {
                    try { fs.rmSync(path.join(espSpeechDir, old.file), { force: true }); } catch (_) { /* 忽略 */ }
                }
            }
            jobs[id] = list;
            writeSpeechJobs(jobs);
            console.log(`[esp] ${id} 语音已排队：${jobId}（${fileUrl ? 'yuntu' : '本地'}）`);
            return jsonOk(res, { id: jobId, size: buf ? buf.length : 0, queued: list.length }, '已加入播放队列');
        });

    // 设备：取当前待播放任务；文本格式 `id|url`，没有任务时返回空。
    app.get('/api/device/esp/speech', (req, res) => {
        const id = safeDeviceId(req.query.deviceId);
        const machine = espMachineOrFail(req, res, id);
        if (!machine) return undefined;
        const jobs = readSpeechJobs();
        const list = (Array.isArray(jobs[id]) ? jobs[id] : [])
            .filter((job) => nowMs() - (Number(job.createdAt) || 0) <= ESP_SPEECH_TTL_MS);
        if (list.length) jobs[id] = list;
        else delete jobs[id];
        writeSpeechJobs(jobs);
        if (!list.length) return res.type('text/plain; charset=utf-8').send('');
        const job = list[0];
        // 设备来取任务就算开始下载，后台据此显示「下载中」；播放时设备再单独回报。
        if (job.state !== 'fetching' && job.state !== 'playing') {
            job.state = 'fetching';
            job.updatedAt = nowMs();
            writeSpeechJobs(jobs);
        }
        // 有 yuntu 直链就下发绝对地址（设备直连更快）；否则用本地兜底路径。
        const url = (job.fileUrl && /^https?:\/\//i.test(job.fileUrl))
            ? job.fileUrl
            : `/api/device/esp/speech/file?id=${encodeURIComponent(job.id)}`
                + `&deviceId=${encodeURIComponent(id)}`;
        if (String(req.query.format || '') === 'text') {
            return res.type('text/plain; charset=utf-8').send(`${job.id}|${url}`);
        }
        return jsonOk(res, { id: job.id, name: job.name, size: job.size, url });
    });

    // 设备：下载任务音频。
    app.get('/api/device/esp/speech/file', (req, res) => {
        const id = safeDeviceId(req.query.deviceId);
        const jobId = String(req.query.id || '');
        if (!id || !/^[a-f0-9]{12}$/.test(jobId)) return res.status(404).end();
        const jobs = readSpeechJobs();
        const job = (jobs[id] || []).find((item) => item.id === jobId);
        if (!job || !ESP_SPEECH_FILE_RE.test(job.file)) return res.status(404).end();
        const file = path.join(espSpeechDir, job.file);
        if (!fs.existsSync(file)) return res.status(404).end();
        res.setHeader('Cache-Control', 'no-store');
        res.type('audio/wav');
        return res.sendFile(file);
    });

    // 设备：播放结束（无论成功与否）回报，服务端删除任务，避免反复播放。
    app.post('/api/device/esp/speech/done', (req, res) => {
        const body = req.body || {};
        const id = safeDeviceId(body.deviceId);
        const jobId = String(body.id || '');
        if (!id || !jobId) return jsonFail(res, '参数不完整');
        const jobs = readSpeechJobs();
        const job = dropSpeechJob(jobs, id, jobId);
        writeSpeechJobs(jobs);
        console.log(`[esp] ${id} 播放结束 id=${jobId} ok=${body.ok === true}`);
        return jsonOk(res, { removed: !!job });
    });

    // 设备：开始真正放音时回报，后台据此把「下载中」切成「播放中」。
    app.post('/api/device/esp/speech/status', (req, res) => {
        const body = req.body || {};
        const id = safeDeviceId(body.deviceId);
        const jobId = String(body.id || '');
        if (!id || !jobId) return jsonFail(res, '参数不完整');
        const jobs = readSpeechJobs();
        const job = (jobs[id] || []).find((item) => item.id === jobId);
        if (job) {
            job.state = body.state === 'playing' ? 'playing' : 'fetching';
            job.updatedAt = nowMs();
            writeSpeechJobs(jobs);
        }
        return jsonOk(res, { found: !!job });
    });

    // 后台：看当前播放任务与阶段（排队 / 下载中 / 播放中），用于面板状态提示。
    app.get('/api/admin/machines/:id/esp/speech', requireAdmin, (req, res) => {
        const id = safeDeviceId(req.params.id);
        if (!id) return jsonFail(res, '设备 id 无效');
        const jobs = readSpeechJobs();
        const list = (Array.isArray(jobs[id]) ? jobs[id] : [])
            .filter((job) => nowMs() - (Number(job.createdAt) || 0) <= ESP_SPEECH_TTL_MS);
        const job = list[0] || null;
        return jsonOk(res, {
            job: job ? { id: job.id, name: job.name, size: job.size, state: job.state || 'queued' } : null,
            pending: list.length,
        });
    });

    app.post('/api/device/esp/press', async (req, res) => {
        const body = req.body || {};
        const id = safeDeviceId(body.deviceId);
        const machine = espMachineOrFail(req, res, id);
        if (!machine) return undefined;
        const pages = machine.espPages;
        let action = null;
        let pageNo = 1;
        let pageObj = null;
        if (body.actionId) {
            // 网页「测试」按 actionId 直取，不受页码影响。
            for (let i = 0; i < pages.length; i += 1) {
                const found = pages[i].buttons.find((item) => item.enabled && item.id === String(body.actionId));
                if (found) {
                    action = found;
                    pageNo = i + 1;
                    pageObj = pages[i];
                    break;
                }
            }
        } else {
            const slot = Number(body.slot == null ? body.button : body.slot);
            if (!Number.isInteger(slot) || slot < 1) return jsonFail(res, 'slot 无效');
            pageNo = clampEspPage(body.page, Math.max(1, pages.length));
            pageObj = pages[pageNo - 1] || null;
            action = pageObj
                ? pageObj.buttons.find((item) => item.enabled && item.slot === slot) || null
                : null;
        }
        if (!action) return jsonFail(res, '该按键未配置动作，或尚未在后台启用', definds.code.FAILED, 403);

        // 录音键：由设备本地长按采集、松开上传，服务端不执行任何 HA/场景动作。
        // 这里回执成功，兼容还没升级固件、仍按普通按键上报的情况。
        if (action.kind === 'rec') {
            console.log(`[esp] ${id} 第${pageNo}页 槽位${action.slot || '-'} → 录音键`);
            return jsonOk(res, { name: action.name, rec: true, page: pageNo }, '录音由设备本地处理');
        }

        // 按键联动：按下即触发，不依赖该按键自己的动作是否成功
        // （用户的心智是「我按了这个键」，而不是「这个键成功执行了」）。
        try {
            sceneEngine.onButton({ deviceId: id, slot: action.slot || 0, page: pageNo });
        } catch (error) {
            console.error('[scenes] 按键联动失败:', error.message);
        }

        // 手动控制（场景）：按下即执行「智能」页里那条场景的动作组。
        // 尊重场景自己的 enabled 与冷却——冷却中如实回「冷却中」，不假装成功，
        // 否则用户连按两下会以为按键坏了。
        if (action.kind === 'scene') {
            if (!action.sceneId) return jsonFail(res, '该按键还没选择手动控制，请先在后台选一个');
            let result = null;
            try {
                result = await sceneEngine.run(action.sceneId, { reason: 'esp-button' });
            } catch (error) {
                console.error(`[esp] ${id} 手动控制执行失败:`, error.message);
                return jsonFail(res, error.message);
            }
            console.log(`[esp] ${id} 第${pageNo}页 槽位${action.slot || '-'} → 手动控制 ${action.sceneId} ${result.result}`);
            if (result.skipped) return jsonFail(res, result.reason || '本次未执行');
            if (!result.ok) {
                const failed = (result.steps || []).find((step) => step.status === 'failed');
                return jsonFail(res, failed
                    ? `${failed.label}：${failed.error || '执行失败'}`
                    : (result.error || '执行失败'));
            }
            return jsonOk(res, {
                name: action.name,
                scene: action.sceneId,
                steps: (result.steps || []).length,
                page: pageNo,
            }, `已执行 ${result.steps.length} 个动作`);
        }

        // 系统动作（翻页/回首页）：不改 HA，只回执让固件本地切页。
        if (action.kind === 'sys') {
            console.log(`[esp] ${id} 第${pageNo}页 槽位${action.slot || '-'} → 系统动作 ${action.action}`);
            return jsonOk(res, { name: action.name, sys: action.action, page: pageNo }, '已执行');
        }

        // 遥控动作（中控/电视）：不走 HA，按账号把 cmd 帧投给该按键选中的设备。
        // 每个遥控按键各自绑定目标；旧配置没有时回退页面级 remoteTarget。
        if (action.kind === 'remote') {
            const targetId = action.remoteTarget || (pageObj && pageObj.remoteTarget);
            if (!targetId) return jsonFail(res, '该按键还没选择目标设备，请先在后台为它选一台中控或电视');
            const machines = readMachines();
            const target = machines[targetId];
            if (!target) return jsonFail(res, '绑定的遥控设备已不存在，请重新选择');
            if (target.kind !== 'home' && target.kind !== 'tv') return jsonFail(res, '绑定的设备不是中控或电视');
            // 命令必须在该设备类型的能力表里（防止换绑后残留了一个不支持的命令）。
            if (!remoteCapabilities(target.kind).some((item) => item.cmd === action.action)) {
                return jsonFail(res, `${target.name || '目标设备'} 不支持「${action.action}」，请重新选择命令`);
            }
            // 儿童模式开关（仅电视）：幂等设置服务端 device-local.mode 并推送配置，
            // 不投 cmd 帧（客户端没有对应命令，也不该走短码解锁那套校验）。
            if (action.action === 'parental_on' || action.action === 'parental_off') {
                if (target.kind !== 'tv') return jsonFail(res, '儿童模式只对电视设备生效');
                if (!USE_FAMILY_MODEL) return jsonFail(res, '家庭级模型未启用', 409, 409);
                const mode = action.action === 'parental_on' ? 'on' : 'off';
                const saved = familyStore.setDeviceLocal(targetId, { mode }, 'esp-remote');
                pushConfigToMachine(target, { reason: 'esp-parental' });
                console.log(`[esp] ${id} 第${pageNo}页 槽位${action.slot || '-'} → 电视 ${targetId} 儿童模式 ${saved.mode}`);
                return jsonOk(res, {
                    name: action.name,
                    remote: action.action,
                    target: targetId,
                    mode: saved.mode,
                    revision: saved.revision || 0,
                    page: pageNo,
                }, mode === 'on' ? '儿童模式已开启' : '儿童模式已关闭');
            }
            const account = target.commAccount || '';
            if (!account) return jsonFail(res, '目标设备缺少通信账号，请让它重新连接一次');
            const lastSeen = Number(target.lastSeen) || 0;
            if (!lastSeen || nowMs() - lastSeen > MACHINE_ONLINE_MS) {
                return jsonFail(res, `${target.name || '目标设备'} 离线，暂时不能遥控`);
            }
            const frame = {
                t: 'msg',
                from: 'esp-remote',
                to: account,
                body: JSON.stringify({ t: 'cmd', name: action.action, args: remoteCommandArgs(action) }),
                ts: nowMs(),
            };
            const delivered = pushRemoteCommand(account, frame) || 0;
            console.log(`[esp] ${id} 第${pageNo}页 槽位${action.slot || '-'} → 遥控 ${targetId} ${action.action}${action.param ? `(${action.param})` : ''} delivered=${delivered}`);
            return jsonOk(res, {
                name: action.name,
                remote: action.action,
                param: action.param,
                target: targetId,
                delivered,
                page: pageNo,
            }, delivered ? '已执行' : '已发送（目标设备暂无在线连接）');
        }

        try {
            await callHaService(action.entityId, action.action, action.param);
            console.log(`[esp] ${id} 第${pageNo}页 槽位${action.slot || '-'} → ${action.entityId} ${action.action}${action.param ? `(${action.param})` : ''} ok`);
            return jsonOk(res, { name: action.name, entityId: action.entityId, action: action.action, param: action.param, page: pageNo }, '已执行');
        } catch (error) {
            console.error(`[esp] ${id} 调用 HA 失败:`, error.message);
            return jsonFail(res, `调用 HA 失败：${error.message}`);
        }
    });

    /**
     * admin：遥控设备目录（中控 / 电视）。
     *
     * 把 machines.json 里的 home/tv 记录映射成「一台设备一个实体」：
     * `entityId = remote.<设备主键>`，附带能力表与实时状态。
     * ESP 页面绑定 remoteTarget 后，按键就能从 capabilities 里挑命令。
     */
    app.get('/api/admin/remote/devices', requireAdmin, (req, res) => {
        const machines = readMachines();
        const devices = [];
        for (const machine of Object.values(machines)) {
            if (machine.kind !== 'home' && machine.kind !== 'tv') continue;
            const account = machine.commAccount || '';
            devices.push({
                entityId: remoteEntityId(machine.id),
                deviceId: machine.id,
                account,
                name: machine.nameSet ? machine.name : (machine.kind === 'home' ? '中控屏' : '电视'),
                kind: machine.kind,
                online: Boolean(machine.lastSeen) && nowMs() - machine.lastSeen <= MACHINE_ONLINE_MS,
                lastSeen: machine.lastSeen || 0,
                home: machine.currentHome || (machine.homes && machine.homes[0]) || '',
                state: remoteStateText(remoteStateOf(account)),
                fields: remoteStateFields(remoteStateOf(account)),
                capabilities: remoteCapabilities(machine.kind),
            });
        }
        devices.sort((a, b) => (Number(b.online) - Number(a.online)) || a.name.localeCompare(b.name));
        return jsonOk(res, { devices });
    });

    /**
     * 设备侧：拉取远程配置。用 key=value 纯文本逐行下发，固件按行解析即可，
     * 不需要在 MCU 上引入 JSON 解析器。
     */
    app.get('/api/device/esp/config', (req, res) => {
        const id = safeDeviceId(req.query.deviceId);
        const machines = readMachines();
        const machine = id ? machines[id] : null;
        if (!machine) return res.status(404).send('device not found');
        const cfg = normalizeEspCfg(machine.espCfg);
        const lines = [
            `ver=${cfg.ver}`,
            `role=${cfg.role}`,
            `master=${cfg.masterMac}`,
            `auto=${cfg.autoUpdate ? 1 : 0}`,
            `sleep=${cfg.idleSleep}`,
            `otachk=${cfg.otaCheckSec}`,
            `pir=${cfg.pirPin}`,
            `net=${cfg.netSlot}`,
            `batpin=${cfg.batPin}`,
            `batdiv=${cfg.batDiv}`,
            `npins=${cfg.pins.length}`,
        ];
        cfg.pins.forEach((pin, index) => lines.push(`p${index + 1}=${pin}`));
        res.setHeader('Cache-Control', 'no-store');
        return res.type('text/plain; charset=utf-8').send(`${lines.join('\n')}\n`);
    });

    /** admin 页：读取远程配置（期望值 + 设备当前实际值）。 */
    app.get('/api/admin/machines/:id/devicecfg', requireAdmin, (req, res) => {
        const machine = espMachineOrFail(req, res, safeDeviceId(req.params.id));
        if (!machine) return undefined;
        const cfg = normalizeEspCfg(machine.espCfg);
        const now = machine.cfgNow || null;
        // 从未下发过配置时，用设备自报的实际值预填；否则后台弹窗是空的，
        // 直接点保存就会把设备现有配置（按键/角色/PIR 等）清空。
        if (!cfg.ver && now) {
            cfg.role = now.role === 'slave' ? 'slave' : 'master';
            cfg.masterMac = typeof now.master === 'string' ? now.master : '';
            cfg.autoUpdate = Number(now.auto) === 1;
            cfg.idleSleep = Number(now.sleep) || 0;
            const interval = Number(now.otachk);
            cfg.otaCheckSec = interval >= 300 && interval <= 21600 ? interval : 21600;
            cfg.pirPin = Number.isInteger(Number(now.pir)) ? Number(now.pir) : -1;
            cfg.netSlot = Math.min(8, Math.max(0, Number(now.net) || 0));
            cfg.batPin = Number.isInteger(Number(now.batpin)) ? Number(now.batpin) : -1;
            cfg.batDiv = Math.min(10, Math.max(1, Number(now.batdiv) || 2));
            cfg.pins = Array.isArray(now.pins) ? now.pins.slice(0, MAX_ESP_BUTTONS) : [];
        }
        return jsonOk(res, {
            cfg,
            now,
            applied: Number(machine.cfgApplied) || 0,
        });
    });

    /** admin 页：保存远程配置。写入后 ver 变化，设备下次心跳拉取并应用。 */
    app.put('/api/admin/machines/:id/devicecfg', requireAdmin, (req, res) => {
        const id = safeDeviceId(req.params.id);
        const machine = espMachineOrFail(req, res, id);
        if (!machine) return undefined;
        const cfg = normalizeEspCfg(req.body || {});
        cfg.ver = Math.floor(Date.now() / 1000);   // 秒级：设备端是 uint32
        const machines = readMachines();
        machines[id].espCfg = cfg;
        saveMachines(machines);
        return jsonOk(res, { cfg }, '已保存，设备下次心跳或唤醒时生效');
    });

    /** 语音播放音量：0~100，未配置时 70。 */
    function normalizeEspVolume(value, fallback = 70) {
        const n = Number(value);
        if (!Number.isFinite(n)) return fallback;
        return Math.max(0, Math.min(100, Math.round(n)));
    }

    /** admin 页：读取某台 ESP 设备的页面配置 + 可选设备类型。 */
    app.get('/api/admin/machines/:id/pages', requireAdmin, (req, res) => {
        const machine = espMachineOrFail(req, res, safeDeviceId(req.params.id));
        if (!machine) return undefined;
        return jsonOk(res, {
            pages: machine.espPages,
            // 设备本机上报的槽位→GPIO，用于后台展示「实际引脚 / 未映射」。
            buttons: machine.espButtons,
            // 槽位显示名（1..8），屏幕底部提示与后台表格共用。
            slotNames: machine.espSlotNames || {},
            // 熄屏（人体感应）：人离开后多少秒熄屏，0 = 常亮。
            screen: normalizeEspScreen(machine.espScreen),
            // 语音播放音量（0~100）。
            volume: normalizeEspVolume(machine.espVolume),
            types: deviceTypeService.list(),
        });
    });

    /** admin 页：整表保存页面配置（每页含显示类型/绑定 + 按键表）。 */
    app.put('/api/admin/machines/:id/pages', requireAdmin, (req, res) => {
        const id = safeDeviceId(req.params.id);
        const machine = espMachineOrFail(req, res, id);
        if (!machine) return undefined;
        const body = req.body || {};
        const pages = normalizeEspPages(body.pages);
        const machines = readMachines();
        machines[id].espPages = pages;
        // 槽位显示名是设备级配置；老后台没传时保留原值。
        if (body.slotNames !== undefined) {
            machines[id].espSlotNames = normalizeEspSlotNames(body.slotNames);
        }
        // 熄屏（人体感应）也是设备级配置；没传时保留原值。
        if (body.screen !== undefined) {
            machines[id].espScreen = normalizeEspScreen(body.screen);
        }
        // 语音音量（设备级）；没传时保留原值。
        if (body.volume !== undefined) {
            machines[id].espVolume = normalizeEspVolume(body.volume);
        }
        // 迁移落盘：旧字段不再保留，避免下次读取又走迁移分支。
        delete machines[id].espActions;
        delete machines[id].espDisplay;
        saveMachines(machines);
        const buttonCount = pages.reduce((sum, page) => sum + page.buttons.length, 0);
        console.log(`[esp] ${id} 页面已更新：${pages.length} 页 / ${buttonCount} 个按键`);
        return jsonOk(res, { pages }, '已保存');
    });

    /* ---- ESP 天气城市映射表（sys.weather.<id> 的唯一真源，仅 admin 一处维护）---- */

    /** 读映射表 + 缓存状态 + 各 id 被多少模板引用（删除前提示用）。 */
    app.get('/api/admin/weather/cities', requireAdmin, (req, res) => {
        try {
            const cities = espSys.readCities();
            // 现场扫一遍模板，统计每个 id 被引用次数（删除前提示用）。
            const refCounts = {};
            for (const machine of Object.values(readMachines())) {
                for (const page of (machine.espPages || [])) {
                    for (const tpl of [page.tplMain, page.tplSub]) {
                        const re = /\{sys\.weather\.([a-zA-Z0-9_]+)\}/g;
                        let m;
                        while ((m = re.exec(String(tpl || ''))) !== null) {
                            refCounts[m[1]] = (refCounts[m[1]] || 0) + 1;
                        }
                    }
                }
            }
            // 种子名单只读展示：让 admin 看得见与 weather_cities.txt 的差异，
            // 但不能反向写入（home/tv 那份名单是独立副本）。
            const seedPath = path.join(datasDir, 'screen', 'datas', 'weather_cities.txt');
            const seedNames = fs.existsSync(seedPath)
                ? fs.readFileSync(seedPath, 'utf8').split(/[\r\n,，]+/).map((s) => s.trim()).filter(Boolean)
                : [];
            return jsonOk(res, {
                cities,
                refCounts,
                cache: espSys.cacheStatus(),
                seedNames,
            });
        } catch (error) {
            return jsonFail(res, error.message);
        }
    });

    /** 新增城市：自动生成拼音 id，冲突降级全拼/序号；id 落库后不可改。 */
    app.post('/api/admin/weather/cities', requireAdmin, (req, res) => {
        try {
            const body = req.body || {};
            const name = String(body.name || '').trim().slice(0, 20);
            if (!name) return jsonFail(res, '城市名不能为空');
            const cities = espSys.readCities();
            if (cities.some((c) => c.name === name)) return jsonFail(res, `「${name}」已存在`);
            const gen = espSys.generateCityId(name, cities);
            const location = String(body.location || '').trim().slice(0, 40) || name;
            cities.push({ id: gen.id, name, location });
            espSys.saveCities(cities);
            console.log(`[esp] 新增天气城市 ${name} → ${gen.id}${gen.note ? `（${gen.note}）` : ''}`);
            return jsonOk(res, { city: { id: gen.id, name, location }, note: gen.note, cities }, '已新增');
        } catch (error) {
            return jsonFail(res, error.message);
        }
    });

    /** 改城市名 / location（不改 id；缓存 key = id，改名不影响命中）。 */
    app.put('/api/admin/weather/cities/:id', requireAdmin, (req, res) => {
        try {
            const id = String(req.params.id || '').trim().toLowerCase();
            if (id === 'auto') return jsonFail(res, '「自动」为固定项，不可修改');
            const cities = espSys.readCities();
            const idx = cities.findIndex((c) => c.id === id);
            if (idx < 0) return jsonFail(res, '城市不存在');
            const body = req.body || {};
            const updated = Object.assign({}, cities[idx]);
            if (body.name !== undefined) {
                const name = String(body.name).trim().slice(0, 20);
                if (name) updated.name = name;
            }
            if (body.location !== undefined) {
                const location = String(body.location).trim().slice(0, 40);
                if (location) updated.location = location;
            }
            cities[idx] = updated;
            espSys.saveCities(cities);
            return jsonOk(res, { city: updated, cities }, '已更新');
        } catch (error) {
            return jsonFail(res, error.message);
        }
    });

    /** 删除城市：有模板引用则禁止删，逼用户先替换变量。 */
    app.delete('/api/admin/weather/cities/:id', requireAdmin, (req, res) => {
        try {
            const id = String(req.params.id || '').trim().toLowerCase();
            if (id === 'auto') return jsonFail(res, '「自动」为固定项，不可删除');
            const cities = espSys.readCities();
            if (!cities.some((c) => c.id === id)) return jsonFail(res, '城市不存在');
            let count = 0;
            for (const machine of Object.values(readMachines())) {
                for (const page of (machine.espPages || [])) {
                    for (const tpl of [page.tplMain, page.tplSub]) {
                        const re = new RegExp(`\\{sys\\.weather\\.${id}\\}`, 'g');
                        count += (String(tpl || '').match(re) || []).length;
                    }
                }
            }
            if (count > 0) {
                return jsonFail(res, `有 ${count} 处模板仍在使用 {sys.weather.${id}}，请先替换再删除`);
            }
            espSys.saveCities(cities.filter((c) => c.id !== id));
            return jsonOk(res, { cities: espSys.readCities() }, '已删除');
        } catch (error) {
            return jsonFail(res, error.message);
        }
    });

    /** 从 weather_cities.txt 重新导入种子：只补缺失城市名，不覆盖已有 id。 */
    app.post('/api/admin/weather/cities/reseed', requireAdmin, (req, res) => {
        try {
            const seedPath = path.join(datasDir, 'screen', 'datas', 'weather_cities.txt');
            const seedText = fs.existsSync(seedPath) ? fs.readFileSync(seedPath, 'utf8') : '';
            const seedNames = seedText.split(/[\r\n,，]+/).map((s) => s.trim()).filter(Boolean);
            const cities = espSys.readCities();
            const existingNames = new Set(cities.map((c) => c.name));
            const added = [];
            for (const name of seedNames) {
                if (name === '自动' || existingNames.has(name)) continue;
                const gen = espSys.generateCityId(name, cities.concat(added));
                added.push({ id: gen.id, name, location: name });
                existingNames.add(name);
            }
            if (added.length) espSys.saveCities(cities.concat(added));
            return jsonOk(res, { added, cities: espSys.readCities(), seedNames }, `已补入 ${added.length} 个城市`);
        } catch (error) {
            return jsonFail(res, error.message);
        }
    });

    /* ---- 设备类型字典 CRUD（S3）：home 与 ESP 共用的唯一真源 ---- */
    app.get('/api/admin/device-types', requireAdmin, (req, res) => {
        return jsonOk(res, { types: deviceTypeService.list() });
    });

    app.post('/api/admin/device-types', requireAdmin, (req, res) => {
        const body = req.body || {};
        const key = String(body.key == null ? '' : body.key);
        try {
            // 新格式可同时保存 dict / rules / card / priority / meta；旧格式只给 dict。
            const hasRulePatch = body.rules != null || body.card != null
                || body.priority != null || body.meta != null;
            const patch = hasRulePatch
                ? { dict: body.dict, rules: body.rules, card: body.card, priority: body.priority, meta: body.meta }
                : (body.dict || {});
            const updated = deviceTypeService.update(key, patch);
            const sent = pushConfigForDeviceTypes();
            console.log(`[deviceTypes] 更新类型 ${key || '通用兜底'}（规则 ${updated.rules.length} 条），字典同步生效，config 推送 ${sent} 台`);
            return jsonOk(res, { type: updated, revision: deviceTypeService.version(), pushed: sent }, '字典已保存，在线设备自动更新布局');
        } catch (error) {
            return jsonFail(res, error.message);
        }
    });

    /** admin：新建自定义设备类型（规则引擎支持动态类型）。 */
    app.post('/api/admin/device-types/create', requireAdmin, (req, res) => {
        const body = req.body || {};
        try {
            const created = deviceTypeService.create(body.key, {
                label: body.label, icon: body.icon, color: body.color,
                rules: body.rules, card: body.card, priority: body.priority,
            });
            const sent = pushConfigForDeviceTypes();
            console.log(`[deviceTypes] 新建类型 ${created.key}（${created.label}），config 推送 ${sent} 台`);
            return jsonOk(res, { type: created, revision: deviceTypeService.version(), pushed: sent }, '类型已创建，在线设备自动更新');
        } catch (error) {
            return jsonFail(res, error.message);
        }
    });

    /** admin：规则命中测试——传一组实体，返回判定结果（单一真源，前端不自己算）。
     *  可传 types（编辑器当前态，含未保存改动）以便不保存也能试；不传则用已保存规则。
     *  附带 includeAll 返回全部命中类型，便于看清裁决过程。 */
    app.post('/api/admin/device-types/classify', requireAdmin, (req, res) => {
        try {
            const body = req.body || {};
            const entities = Array.isArray(body.entities) ? body.entities : [];
            const types = Array.isArray(body.types) ? body.types : deviceTypeService.list();
            const result = deviceTypes.classify(entities, types, { includeAll: true });
            return jsonOk(res, { result });
        } catch (error) {
            return jsonFail(res, error.message);
        }
    });

    /**
     * admin：全局判定测试——用「编辑器当前态」的规则对所有 HA 设备跑一遍判定，
     * 返回每台设备最新被识别的类型。前端据 currentKey 高亮当前编辑类型命中的设备。
     * 不传 types 则用已保存规则；onlyVisible=true 时只返回「显示到中控屏」的设备。
     */
    app.post('/api/admin/device-types/classify-all', requireAdmin, async (req, res) => {
        try {
            const body = req.body || {};
            const types = Array.isArray(body.types) ? body.types : deviceTypeService.list();
            const onlyVisible = body.onlyVisible === true;
            const catalog = await haCatalogService.getCatalog();
            const visibility = haDeviceVisibilityService.list();
            const devices = catalog.devices || [];
            const results = [];
            for (const dev of devices) {
                const visible = Object.prototype.hasOwnProperty.call(visibility, dev.id) ? visibility[dev.id] : null;
                if (onlyVisible && visible === false) continue;
                const entities = (dev.entities || []).map((e) => ({
                    id: e.id, domain: e.domain, name: e.name, state: e.state,
                    attrs: e.attributes || {},
                    device: {
                        name: dev.name || '',
                        model: dev.model || '',
                        manufacturer: dev.manufacturer || '',
                    },
                }));
                const hit = deviceTypes.classify(entities, types, { includeAll: true });
                results.push({
                    id: dev.id,
                    name: dev.name,
                    areaName: dev.areaName || '',
                    visible,
                    key: hit ? hit.key : '',
                    label: hit ? hit.label : '',
                    specificity: hit ? hit.specificity : 0,
                    priority: hit ? hit.priority : 5,
                    allHits: hit ? (hit.allHits || []).map((h) => ({ key: h.key, label: h.label })) : [],
                    // 卡片预览用真实设备数据渲染：带上实体当前 state/attributes，
                    // 前端按 entity_id 后缀填充 {s:xxx}/{a:xxx.attr}/{id:xxx} 等占位符。
                    entities: entities.map((e) => ({
                        id: e.id, domain: e.domain, name: e.name, state: e.state, attrs: e.attrs,
                    })),
                });
            }
            return jsonOk(res, { results, total: results.length });
        } catch (error) {
            console.error('[admin] 全局判定测试失败:', error.message);
            return jsonFail(res, `全局判定测试失败：${error.message}`);
        }
    });

    app.post('/api/admin/device-types/reset', requireAdmin, (req, res) => {
        const key = String((req.body || {}).key == null ? '' : (req.body || {}).key);
        try {
            const type = deviceTypeService.reset(key);
            const sent = pushConfigForDeviceTypes();
            return jsonOk(res, { type, revision: deviceTypeService.version(), pushed: sent }, '已恢复默认规则，在线设备自动更新');
        } catch (error) {
            return jsonFail(res, error.message);
        }
    });

    /** admin 页：HA 地址 / 令牌（令牌回显为布尔值，不明文下发）。 */
    app.get('/api/admin/ha', requireAdmin, (req, res) => jsonOk(res, haConfigView()));

    /**
     * admin 页：HA 实体目录（按「家 → 房间」分组，含每个实体可用的动作）。
     *
     * 前端不直连 HA——令牌不下发到浏览器，由服务端代取。
     * query.refresh=1 时跳过缓存强制重取。
     */
    app.get('/api/admin/ha/entities', requireAdmin, async (req, res) => {
        try {
            const refresh = req.query && req.query.refresh === '1';
            const catalog = await haCatalogService.getCatalog(refresh);
            return jsonOk(res, {
                homes: catalog.homes,
                entities: catalog.entities,
                domains: catalog.domains,
                cached: catalog.cached === true,
                updatedAt: Date.now(),
            });
        } catch (error) {
            console.error('[ha] 拉取实体目录失败:', error.message);
            return jsonFail(res, `拉取 HA 实体目录失败：${error.message}`);
        }
    });

    /**
     * admin：「HA 设备」页数据——按 device_id 聚合的 HA 设备清单，
     * 附带每台设备的「是否显示到中控屏」开关状态（三态）。
     * 复用 haCatalogService 的缓存，不额外向 HA 发请求。
     */
    app.get('/api/admin/ha/devices', requireAdmin, async (req, res) => {
        try {
            const refresh = req.query && req.query.refresh === '1';
            const catalog = await haCatalogService.getCatalog(refresh);
            const visibility = haDeviceVisibilityService.list();
            const devices = (catalog.devices || []).map((d) => ({
                ...d,
                entityCount: (d.entities || []).length,
                visible: Object.prototype.hasOwnProperty.call(visibility, d.id) ? visibility[d.id] : null,
            }));
            return jsonOk(res, {
                devices,
                cached: catalog.cached === true,
                updatedAt: Date.now(),
            });
        } catch (error) {
            console.error('[admin] 拉取 HA 设备列表失败:', error.message);
            return jsonFail(res, `拉取 HA 设备列表失败：${error.message}`);
        }
    });

    /** admin：设置单台 / 批量 HA 设备的「是否显示到中控屏」。 */
    app.post('/api/admin/ha/devices/visibility', requireAdmin, (req, res) => {
        try {
            const body = req.body || {};
            let changed;
            if (Array.isArray(body.items)) {
                changed = haDeviceVisibilityService.setMany(body.items);
            } else {
                const deviceId = String(body.deviceId || '');
                if (!deviceId) return jsonFail(res, 'deviceId 不能为空');
                if (typeof body.visible !== 'boolean') return jsonFail(res, 'visible 必须是布尔值');
                changed = [haDeviceVisibilityService.set(deviceId, body.visible)];
            }
            return jsonOk(res, { changed }, '已保存');
        } catch (error) {
            return jsonFail(res, error.message);
        }
    });

    /** admin：清除某设备的显式显示配置（回归「未配置=保持现状」）。 */
    app.post('/api/admin/ha/devices/visibility/reset', requireAdmin, (req, res) => {
        try {
            const deviceId = String((req.body || {}).deviceId || '');
            if (!deviceId) return jsonFail(res, 'deviceId 不能为空');
            return jsonOk(res, haDeviceVisibilityService.remove(deviceId), '已恢复默认');
        } catch (error) {
            return jsonFail(res, error.message);
        }
    });

    app.put('/api/admin/ha', requireAdmin, (req, res) => {
        const body = req.body || {};
        const raw = readJson(haFile, {}) || {};
        const baseUrl = typeof body.baseUrl === 'string' ? body.baseUrl.trim().slice(0, 200) : (raw.baseUrl || '');
        let token = typeof raw.token === 'string' ? raw.token : '';
        if (body.clearToken === true) token = '';
        else if (typeof body.token === 'string' && body.token.trim()) token = body.token.trim();
        writeJson(haFile, { baseUrl, token });
        console.log(`[esp] HA 连接信息已更新: ${baseUrl || '(空)'} token=${token ? '已设置' : '未设置'}`);
        return jsonOk(res, haConfigView(), '已保存');
    });

    // ------------------------------------------------------------ ESP 固件升级（OTA）
    //
    // 发布流程：本地编译出 .bin → admin 页上传并填版本号 → 设备心跳时比对版本，
    // 不一致就在屏幕提示，用户在设备本地设置页点「立即升级」从本服务下载写入
    // 另一个 OTA 槽。分区方案必须是双 app 槽（no_fs / min_spiffs）。

    const FW_VERSION_RE = /^[A-Za-z0-9._-]{1,32}$/;
    const firmwareUpload = multer({
        storage: multer.memoryStorage(),
        limits: { fileSize: 8 * 1024 * 1024 },
    });

    // 固件按芯片分轨：esp32s3（默认，兼容旧客户端不传 target）/ esp32c6。
    // 角色（主机/从机）不参与分轨，同一芯片共用一份固件。
    const FW_TARGETS = {
        esp32s3: { bin: firmwareBin, meta: firmwareMeta },
        esp32c6: { bin: firmwareBinC6, meta: firmwareMetaC6 },
    };

    function firmwareTarget(value) {
        const target = String(value || '').trim().toLowerCase();
        return FW_TARGETS[target] ? target : 'esp32s3';
    }

    function readFirmwareMeta(target) {
        const paths = FW_TARGETS[firmwareTarget(target)];
        const raw = readJson(paths.meta, null);
        if (!raw || typeof raw !== 'object') return null;
        if (!FW_VERSION_RE.test(String(raw.version || ''))) return null;
        if (!fs.existsSync(paths.bin)) return null;
        return {
            target: firmwareTarget(target),
            version: String(raw.version),
            size: Number(raw.size) || fs.statSync(paths.bin).size,
            sha256: typeof raw.sha256 === 'string' ? raw.sha256 : '',
            notes: typeof raw.notes === 'string' ? raw.notes.slice(0, 200) : '',
            uploadedAt: Number(raw.uploadedAt) || 0,
        };
    }

    /** 设备侧：当前发布版本。没上传过固件时返回空文本。 */
    app.get('/api/device/firmware/latest', (req, res) => {
        const target = firmwareTarget(req.query.target);
        const meta = readFirmwareMeta(target);
        if (!meta) return res.type('text/plain; charset=utf-8').send('');
        if (String(req.query.format || '') === 'text') {
            // 固件不接 JSON 库：version|size|sha256|notes（notes 取到行尾）
            return res.type('text/plain; charset=utf-8')
                .send([meta.version, meta.size, meta.sha256, meta.notes].join('|'));
        }
        return jsonOk(res, {
            ...meta,
            url: `/api/device/firmware/download?target=${target}`,
        });
    });

    /** 设备侧：下载已发布的 bin。 */
    app.get('/api/device/firmware/download', (req, res) => {
        const target = firmwareTarget(req.query.target);
        if (!readFirmwareMeta(target)) return jsonFail(res, '暂无固件', definds.code.FAILED, 404);
        res.setHeader('Cache-Control', 'no-store');
        res.type('application/octet-stream');
        return res.sendFile(FW_TARGETS[target].bin);
    });

    app.get('/api/admin/firmware', requireAdmin, (req, res) => {
        const targets = {};
        for (const key of Object.keys(FW_TARGETS)) {
            const meta = readFirmwareMeta(key);
            targets[key] = meta ? { ...meta, published: true } : { published: false };
        }
        // 顶层保留 esp32s3 字段，兼容旧 admin 页面。
        return jsonOk(res, { ...targets.esp32s3, targets });
    });

    app.post('/api/admin/firmware', requireAdmin, firmwareUpload.single('file'), (req, res) => {
        try {
            const target = firmwareTarget(req.body && req.body.target);
            const paths = FW_TARGETS[target];
            const version = String((req.body && req.body.version) || '').trim();
            if (!FW_VERSION_RE.test(version)) return jsonFail(res, '版本号不合法（字母数字 . _ -，≤32 位）');
            if (!req.file || !req.file.buffer || !req.file.buffer.length) return jsonFail(res, '未收到固件文件');
            if (req.file.buffer.length < 64 * 1024) return jsonFail(res, '文件太小，不像是完整固件');
            const notes = String((req.body && req.body.notes) || '').trim().slice(0, 200);
            fs.writeFileSync(paths.bin, req.file.buffer);
            const meta = {
                version,
                size: req.file.buffer.length,
                sha256: crypto.createHash('sha256').update(req.file.buffer).digest('hex'),
                notes,
                uploadedAt: nowMs(),
            };
            writeJson(paths.meta, meta);
            console.log(`[ota] ${target} 固件已更新: v${version} ${(meta.size / 1024).toFixed(0)}KB sha256=${meta.sha256.slice(0, 12)}…`);
            return jsonOk(res, { ...meta, target }, '固件已发布');
        } catch (error) {
            console.error('[ota] 固件上传失败:', error.message);
            return jsonFail(res, `固件上传失败：${error.message}`);
        }
    });

    app.delete('/api/admin/firmware', requireAdmin, (req, res) => {
        try {
            const target = firmwareTarget(req.query.target);
            const paths = FW_TARGETS[target];
            fs.rmSync(paths.bin, { force: true });
            fs.rmSync(paths.meta, { force: true });
            console.log(`[ota] 已撤回 ${target} 固件发布`);
            return jsonOk(res, { published: false, target }, '已撤回');
        } catch (error) {
            return jsonFail(res, error.message);
        }
    });

    /**
     * 设备类型字典（公开读，无敏感信息）：home 端据此解析设备展示字段。
     * 只包含类型规则（属性/模板/标签）+ 显式设备分类映射，不含 HA 令牌。
     * home 直连 HA WS 取实时状态，只把这里当「类型→字段」的规则源；
     * 服务端不可达时 home 用内置 fallback，不阻塞启动。
     */
    app.get('/api/device/device-types', async (req, res) => {
        try {
            // 显式分类属于 ESP 屏幕页面（每页一台被控设备），不再按机器 id 下发；
            // home 端只用自动分类 + 字典规则，这里保持空表兼容旧字段。
            const manual = {};

            const types = deviceTypeService.list();
            const auto = {};
            try {
                const catalog = await haCatalogService.getCatalog();
                const byDevice = new Map();
                for (const e of (catalog.entities || [])) {
                    const devKey = e.deviceId || e.id;
                    if (!byDevice.has(devKey)) byDevice.set(devKey, []);
                    byDevice.get(devKey).push({
                        id: e.id, domain: e.domain, name: e.name, state: e.state,
                        attrs: e.attributes || {},
                        device: { name: e.device || '', model: e.deviceModel || '', manufacturer: e.manufacturer || '' },
                    });
                }
                for (const [devKey, entities] of byDevice.entries()) {
                    const hit = deviceTypes.classify(entities, types);
                    if (hit) auto[devKey] = hit.key;
                }
            } catch (error) {
                console.warn('[deviceTypes] 自动分类取 HA 目录失败（不影响显式分类）:', error.message);
            }

            return jsonOk(res, {
                types,
                classification: Object.assign({}, auto, manual),
                autoClassification: auto,
                manualClassification: manual,
                ruleEngineEnabled: true,
                genericCardTypes: deviceTypeService.genericCardTypes(),
                // HA 设备「是否显示到中控屏」显式配置（deviceId -> bool）。
                // home 端据此从首页网格过滤：false=隐藏；未出现的设备保持现状。
                deviceVisibility: haDeviceVisibilityService.publicMap(),
                // 真实字典版本号（保存后递增），App 可据此判断是否需要热更新布局。
                updatedAt: deviceTypeService.version() || Date.now(),
            });
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
    // ws 握手成功后由 realtime 回写设备的通信账号、客户端标识与设备型号
    // （app / version / build / model / platform），并刷新「最后连接时间」。
    // 型号是静态属性，只在每次连接时上报一次，心跳 / report 不再重复携带。
    // 设备主键必须精确匹配：中控与电视是两个独立客户端，不能共享一条记录。
    function setCommInfo(deviceId, comm) {
        const id = safeDeviceId(deviceId);
        if (!id) return;
        const info = comm && typeof comm === 'object' ? comm : {};
        // 只覆盖客户端确实上报了的字段：旧客户端不带 model/platform 时保留
        // 设备表里已有的型号，绝不能用空串把历史数据清掉。
        const fields = [
            ['account', 'commAccount', 64],
            ['app', 'commApp', 64],
            ['version', 'commVersion', 32],
            ['build', 'commBuild', 32],
            ['model', 'model', 64],
            ['platform', 'platform', 32],
        ];
        const next = {};
        for (const [source, field, max] of fields) {
            const value = typeof info[source] === 'string' ? info[source].trim() : '';
            if (value) next[field] = value.slice(0, max);
        }
        const machines = readMachines();
        const key = findMachineKey(machines, id);
        if (!key) return; // 只更新已建档设备，建档由 ensureMachineForLogin 负责
        const machine = machines[key];
        const now = nowMs();
        const refreshConnect = now - (lastConnectAt.get(key) || 0) >= TOUCH_THROTTLE_MS;
        const changed = Object.entries(next).some(([field, value]) => machine[field] !== value);
        if (!changed && !refreshConnect) return;
        if (refreshConnect) lastConnectAt.set(key, now);
        Object.assign(machine, next);
        if (refreshConnect) machine.lastConnectedAt = now;
        machines[key] = normalizeMachine(key, machine);
        saveMachines(machines);
    }
    /**
     * 通信账号 → 设备备注名（realtime roster/presence 下发用）。
     * 未设置备注（`nameSet=false`）返回空串，客户端据此回落到账号 id。
     */
    function machineNameForAccount(account) {
        const target = String(account || '').trim();
        if (!target) return '';
        for (const machine of Object.values(readMachines())) {
            if (machine.commAccount === target && machine.nameSet) return machine.name;
        }
        return '';
    }

    /**
     * 某查看者可见的设备别名索引：设备通信账号 / 设备 id → 该查看者的别名。
     *
     * realtime 的 roster / presence 按接收者注入这一层（方案 B 的同步路径）：
     * A 的别名只会出现在发给 A 的帧里，B 收到的仍是空串。
     */
    function aliasMapFor(viewer) {
        const name = String(viewer || '').trim();
        const map = {};
        if (!name) return map;
        for (const machine of Object.values(readMachines())) {
            const alias = (machine.aliases && machine.aliases[name]) || '';
            if (!alias) continue;
            if (machine.commAccount) map[machine.commAccount] = alias;
            map[machine.id] = alias;
        }
        return map;
    }

    /** 设备通信账号 → 绑定家长账号（realtime 事件扇出用，仅电视）。 */
    function parentAccountsFor(account) {
        if (!account) return [];
        const machines = readMachines();
        const machine = Object.values(machines)
            .find((item) => isTvMachine(item)
                && (item.commAccount === account || item.id === account));
        return machine ? machine.parents : [];
    }

    /**
     * parental_unlock 发送者校验：只有该电视绑定的家长或管理员可远程解锁。
     * 管理员解锁按「代管」处理（家长端展示时标注）。
     */
    function canParentalUnlock(sender, tvAccount) {
        const from = String(sender || '').trim();
        const tv = String(tvAccount || '').trim();
        if (!from || !tv) return false;
        if (from === ADMIN_USERNAME) return true;
        return parentAccountsFor(tv).includes(from);
    }

    /** 家长账号 → 其绑定电视的通信账号（含设备 id），用于家长端补拉历史事件。 */
    function machineAccountsForParent(account) {
        if (!account) return [];
        const accounts = [];
        for (const machine of Object.values(readMachines())) {
            if (!isTvMachine(machine) || !machine.parents.includes(account)) continue;
            if (machine.commAccount) accounts.push(machine.commAccount);
            accounts.push(machine.id);
        }
        return accounts;
    }

    return {
        adminDir,
        ADMIN_USERNAME,
        setCommInfo,
        // ws roster/presence 下发的设备备注名（displayName 之后的回落层）
        machineNameForAccount,
        // ws roster/presence 按接收者注入的家长私有别名索引
        aliasMapFor,
        // 登录链路（HTTP /api/login、ws 握手）携带 deviceId 时自动建档
        ensureMachineForLogin,
        // ws 通道复用：保活 / 上报 / 取配置
        touchDevice,
        updateDeviceReport,
        configFor,
        // parental 事件扇出：设备 → 绑定家长
        parentAccountsFor,
        // parental 历史补拉：家长 → 绑定设备账号
        machineAccountsForParent,
        // parental_unlock 服务端发送者校验（绑定家长 / 管理员）
        canParentalUnlock,
    };
}

// normalizeParental / normalizeQuizQuestions / normalizeMachine 导出仅供测试
// 直接驱动校验逻辑（attachAdmin 需要完整服务环境）。
module.exports = {
    attachAdmin,
    ADMIN_USERNAME,
    USE_FAMILY_MODEL,
    normalizeMachineName,
    normalizeMachineAliases,
    normalizeParental,
    normalizeQuizQuestions,
    parentalShare,
    FamilyStore,
};
