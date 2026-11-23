// 设备类型字典：home 端与 ESP 端共用的「唯一真源」。
//
// 为什么需要这一层：
// - home 端原来靠 entity_id 后缀猜设备类型（_status_p_2_2 被洗衣机/空气炸锅/
//   净水器共用），改一类规则就串到另一类。现在判定规则由 admin 后台显式配置，
//   判定统一在服务端算（deviceTypes.classify），home 拿结果直接选卡片。
// - 固件保持「哑巴」：服务端按字典把 HA 状态解析成 title/main/sub/keys 四行
//   纯文本下发，固件不认识任何设备类型，新类型接入不用重烧固件。
// - home 直连 HA WS 拿实时状态，但「某类设备的主状态取哪个属性、怎么拼副
//   状态」也读这份字典 → 两端同源、改一处全生效。
//
// 存储：默认规则在本文件（DEVICE_TYPES / DICT_DEFAULTS / DETAIL / DEFAULT_RULES）；
// admin 页的改动作为覆盖层写进 datas/admin/deviceTypes.json。覆盖层同时兼容
// 旧格式（顶层直接是 dict 字段）和新格式（{dict, rules, card, priority, meta}）。

const fs = require('fs');
const path = require('path');

// 类型清单：key 与 home 端 XXXSummary / 原型 DICT_DETAIL 对齐。
const DEVICE_TYPES = [
    { key: 'water_heater', icon: '♨', label: '热水器', color: '#ff6b6b', roles: ['主状态', '副状态1', '副状态2'] },
    { key: 'kettle', icon: '♨', label: '热水瓶', color: '#ffb454', roles: ['主状态', '副状态1', '副状态2'] },
    { key: 'fan', icon: '✦', label: '风扇', color: '#4dd4ac', roles: ['主状态', '副状态1', '副状态2'] },
    { key: 'climate', icon: '❄', label: '空调', color: '#2f9cff', roles: ['主状态', '副状态1', '副状态2'] },
    { key: 'light', icon: '☀', label: '灯光', color: '#facc15', roles: ['主状态', '副状态1', '副状态2'] },
    { key: 'projector', icon: '▤', label: '投影仪', color: '#60a5fa', roles: ['主状态', '副状态1', '副状态2'] },
    { key: 'air_fryer', icon: '▣', label: '空气炸锅', color: '#fb923c', roles: ['主状态', '副状态1', '副状态2'] },
    { key: 'washer', icon: '◉', label: '洗衣机', color: '#b98cff', roles: ['主状态', '副状态1', '副状态2'] },
    { key: 'fridge', icon: '▥', label: '冰箱', color: '#7dd3fc', roles: ['主状态', '副状态1', '副状态2'] },
    { key: 'rice_cooker', icon: '▢', label: '电饭煲', color: '#fda4af', roles: ['主状态', '副状态1', '副状态2'] },
    { key: 'socket', icon: '⏻', label: '插座', color: '#4dd4ac', roles: ['主状态', '副状态1', '副状态2'] },
    { key: 'purifier', icon: '◌', label: '净水器', color: '#38bdf8', roles: ['主状态', '副状态1', '副状态2'] },
    { key: 'range_hood', icon: '⌇', label: '油烟机', color: '#94a3b8', roles: ['主状态', '副状态1', '副状态2'] },
    { key: 'multi_switch', icon: '▦', label: '多路开关', color: '#a3a3a3', roles: ['主状态', '副状态1', '副状态2'] },
    { key: 'lock', icon: '⚿', label: '门锁', color: '#f87171', roles: ['主状态', '副状态1', '副状态2'] },
    { key: 'fan_light', icon: '✺', label: '风扇灯', color: '#fbbf24', roles: ['主状态', '副状态1', '副状态2'] },
    { key: 'smart_speaker', icon: '♫', label: '智能音箱', color: '#a78bfa', roles: ['主状态', '副状态1', '副状态2'] },
    { key: 'water_leak', icon: '◍', label: '水浸传感器', color: '#38bdf8', roles: ['主状态', '副状态1', '副状态2'] },
    { key: 'camera', icon: '⊙', label: '摄像机', color: '#60a5fa', roles: ['主状态', '副状态1', '副状态2'] },
    { key: 'tv_box', icon: '▧', label: '电视盒子', color: '#f472b6', roles: ['主状态', '副状态1', '副状态2'] },
    { key: 'router', icon: '⇄', label: '路由器', color: '#34d399', roles: ['主状态', '副状态1', '副状态2'] },
    { key: 'wireless_switch_1', icon: '▭', label: '无线开关（单键）', color: '#a3a3a3', roles: ['主状态', '副状态1', '副状态2'] },
    { key: 'wireless_switch_2', icon: '▬', label: '无线开关（双键）', color: '#a3a3a3', roles: ['主状态', '副状态1', '副状态2'] },
    { key: 'wireless_switch_3', icon: '▩', label: '无线开关（多键）', color: '#a3a3a3', roles: ['主状态', '副状态1', '副状态2'] },
    { key: 'home_climate', icon: '⌂', label: '全屋环境', color: '#5eead4', roles: ['主状态', '副状态1', '副状态2'] },
    { key: '', icon: '?', label: '通用兜底', color: '#9ca3af', roles: ['主状态', '副状态1', '副状态2'] },
];

// 通用默认字段：未单独声明的类型继承这些。
const DICT_DEFAULTS = {
    mainAttr: 'state', mainFmt: '{v}', subTpl: '{s1} · {s2}', step: '1',
    homeLabel: '当前状态', homeCtrls: '电源', homeActs: 'toggle',
    espTitle: '{device}', espMain: '{main}', espSub: '{sub}', espKeys: '{buttons}',
    simMain: '--', simSub1: '在线', simSub2: '就绪',
};

// 各类型的默认解析规则（字段与 admin 字典 Tab 一致）。
const DICT_DETAIL = {
    water_heater: { mainAttr: 'current_temperature', mainFmt: '{v}°C', subTpl: '{s1} · 目标 {s2}°C', step: '0.5', homeLabel: '当前水温', homeCtrls: '电源 温度− 温度+ 预热', homeActs: 'toggle set_temperature(-0.5) set_temperature(+0.5) toggle', simMain: '42.5', simSub1: '制热中', simSub2: '45' },
    kettle: { mainAttr: 'temperature', mainFmt: '{v}°C', subTpl: '{s1} · 保温 {s2}°C', step: '1', homeLabel: '当前温度', homeCtrls: '电源 保温', homeActs: 'toggle select_option', simMain: '98', simSub1: '加热中', simSub2: '55' },
    fan: { mainAttr: 'percentage', mainFmt: '风速 {v}%', subTpl: '{s1} · {s2}', step: '25', homeLabel: '当前风速', homeCtrls: '电源 风+ 风− 摆头', homeActs: 'toggle set_percentage(+25) set_percentage(-25) toggle', simMain: '60', simSub1: '自然风', simSub2: '延时 30min' },
    climate: { mainAttr: 'current_temperature', mainFmt: '{v}°C', subTpl: '{s1} · 目标 {s2}°C', step: '0.5', homeLabel: '当前室温', homeCtrls: '电源 温度− 温度+ 模式', homeActs: 'toggle set_temperature(-0.5) set_temperature(+0.5) set_hvac_mode', simMain: '26', simSub1: '制冷', simSub2: '24' },
    light: { mainAttr: 'state', mainFmt: '{v}', subTpl: '{s1} · {s2}', step: '10', homeLabel: '灯光状态', homeCtrls: '电源 亮度+ 亮度− 场景', homeActs: 'turn_on brightness(+10) brightness(-10) next_effect', simMain: '已开启', simSub1: '亮度 80%', simSub2: '4000K' },
    projector: { mainAttr: 'state', mainFmt: '{v}', subTpl: '{s1} · {s2}', step: '—', homeLabel: '播放状态', homeCtrls: '电源 信号源 亮度', homeActs: 'toggle select_option set_percentage', simMain: '播放中', simSub1: 'HDMI1', simSub2: '亮度 70%' },
    air_fryer: { mainAttr: 'state', mainFmt: '{v}', subTpl: '{s1} · 剩 {s2}min', step: '5', homeLabel: '工作状态', homeCtrls: '开始 温度+ 时间+ 取消', homeActs: 'press number(+5) number(+1) press', simMain: '烹饪中', simSub1: '180°C', simSub2: '12' },
    washer: { mainAttr: 'state', mainFmt: '{v}', subTpl: '剩 {s1} · {s2}', step: '—', homeLabel: '运行状态', homeCtrls: '启动 暂停 停止 模式', homeActs: 'press press press next_option', simMain: '洗涤中', simSub1: '23min', simSub2: '标准洗' },
    fridge: { mainAttr: 'temperature', mainFmt: '{v}°C', subTpl: '{s1} · {s2}', step: '1', homeLabel: '冷藏温度', homeCtrls: '模式', homeActs: '只读', simMain: '4', simSub1: '冷冻 −18°C', simSub2: '节能' },
    rice_cooker: { mainAttr: 'state', mainFmt: '{v}', subTpl: '{s1} · 剩 {s2}min', step: '—', homeLabel: '工作状态', homeCtrls: '开始 取消 预约', homeActs: 'press press select_option', simMain: '煮饭中', simSub1: '标准', simSub2: '18' },
    socket: { mainAttr: 'state', mainFmt: '{v}', subTpl: '{s1} · {s2}', step: '—', homeLabel: '开关状态', homeCtrls: '电源', homeActs: 'toggle', simMain: '已开启', simSub1: '功率 65W', simSub2: '220V' },
    purifier: { mainAttr: 'state', mainFmt: '{v}', subTpl: '{s1} · {s2}', step: '—', homeLabel: '运行状态', homeCtrls: '电源', homeActs: 'toggle', simMain: '制水中', simSub1: '滤芯 82%', simSub2: 'TDS 18' },
    range_hood: { mainAttr: 'state', mainFmt: '{v}', subTpl: '{s1} · {s2}', step: '1', homeLabel: '运行状态', homeCtrls: '电源 档位+ 档位− 照明', homeActs: 'toggle set_percentage(+25) set_percentage(-25) toggle', simMain: '已开启', simSub1: '档位 2', simSub2: '照明开' },
    multi_switch: { mainAttr: 'state', mainFmt: '开启 {v}', subTpl: '{s1} · {s2}', step: '—', homeLabel: '已开启路数', homeCtrls: '1 2 3 4', homeActs: 'toggle ×4', simMain: '2/4', simSub1: '1开 2开', simSub2: '3关 4关' },
    lock: { mainAttr: 'state', mainFmt: '{v}', subTpl: '{s1}', step: '—', homeLabel: '门锁状态', homeCtrls: '只读', homeActs: '只读', simMain: '已上锁', simSub1: '安全', simSub2: '' },
    fan_light: { mainAttr: 'state', mainFmt: '{v}', subTpl: '{s1} · {s2}', step: '10', homeLabel: '风扇灯状态', homeCtrls: '电源 灯 风扇 亮度+ 亮度−', homeActs: 'toggle toggle toggle brightness(+10) brightness(-10)', simMain: '已开启', simSub1: '灯开', simSub2: '风速 3档' },
    smart_speaker: { mainAttr: 'state', mainFmt: '{v}', subTpl: '{s1} · {s2}', step: '—', homeLabel: '播放状态', homeCtrls: '电源 播放 音量+ 音量−', homeActs: 'toggle media_play_pause volume_up volume_down', simMain: '待机', simSub1: '音量 30%', simSub2: 'Wi-Fi 已连接' },
    water_leak: { mainAttr: 'state', mainFmt: '{v}', subTpl: '{s1}', step: '—', homeLabel: '水浸状态', homeCtrls: '只读', homeActs: '只读', simMain: '正常', simSub1: '电池 86%', simSub2: '' },
    camera: { mainAttr: 'state', mainFmt: '{v}', subTpl: '{s1} · {s2}', step: '—', homeLabel: '监控状态', homeCtrls: '电源 录像', homeActs: 'toggle toggle', simMain: '已开启', simSub1: '已接入 7/18', simSub2: '存储正常' },
    tv_box: { mainAttr: 'state', mainFmt: '{v}', subTpl: '{s1} · {s2}', step: '—', homeLabel: '播放状态', homeCtrls: '电源 信号源', homeActs: 'toggle select_option', simMain: '待机', simSub1: 'HDMI2', simSub2: '可用 2/21' },
    router: { mainAttr: 'state', mainFmt: '{v}', subTpl: '{s1} · {s2}', step: '—', homeLabel: '运行状态', homeCtrls: '重启', homeActs: 'press', simMain: '在线', simSub1: '已开启 1/1', simSub2: '局域网正常' },
    wireless_switch_1: { mainAttr: 'state', mainFmt: '{v}', subTpl: '{s1}', step: '—', homeLabel: '开关状态', homeCtrls: '按键', homeActs: 'toggle', simMain: '可用', simSub1: '电量 90%', simSub2: '' },
    wireless_switch_2: { mainAttr: 'state', mainFmt: '开启 {v}', subTpl: '{s1} · {s2}', step: '—', homeLabel: '已开启路数', homeCtrls: '按键1 按键2', homeActs: 'toggle toggle', simMain: '2/2', simSub1: '1开', simSub2: '2关' },
    wireless_switch_3: { mainAttr: 'state', mainFmt: '开启 {v}', subTpl: '{s1} · {s2}', step: '—', homeLabel: '已开启路数', homeCtrls: '按键1 按键2 按键3', homeActs: 'toggle ×3', simMain: '3/4', simSub1: '1开 2开', simSub2: '3关 4关' },
    home_climate: { mainAttr: 'temperature', mainFmt: '{v}°C', subTpl: '{s1} · 湿度 {s2}%', step: '1', homeLabel: '室内温度', homeCtrls: '只读', homeActs: '只读', simMain: '26', simSub1: '舒适', simSub2: '55' },
    '': { mainAttr: 'state', mainFmt: '{v}', subTpl: '{s1}', step: '—', homeLabel: '当前状态', homeCtrls: '电源', homeActs: 'toggle', simMain: '开启', simSub1: 'switch · 在线', simSub2: '' },
};

// 默认判定规则 + 通用卡片配置（从 docs/device-type-rule-engine-prototype.html 迁移）。
// 字段可在 admin「设备判定规则」Tab 里改；规则间 OR、规则内条件 AND。
const DEFAULT_RULES = {
    climate: { priority: 10, rules: [
        { id: 'c1', name: '米家空调（有当前温度）', enabled: true, conds: [
            { field: 'domain', op: 'eq', value: 'climate' },
            { field: 'attr.current_temperature', op: 'exists', value: '' },
        ] },
    ] },
    socket: { priority: 20, rules: [
        { id: 's1', name: '空调插座（按名称识别）', enabled: true, conds: [
            { field: 'name', op: 'contains', value: '插座' },
            { field: 'domain', op: 'eq', value: 'climate' },
        ] },
        { id: 's2', name: '普通开关插座', enabled: true, conds: [
            { field: 'domain', op: 'eq', value: 'switch' },
        ] },
    ] },
    kettle: { priority: 15, rules: [
        { id: 'k1', name: '米家电热水瓶', enabled: true, conds: [
            { field: 'entity_id', op: 'contains', value: '_temperature_p_2_6' },
            { field: 'attr.options', op: 'contains', value: '自来水' },
        ] },
    ] },
    water_heater: { priority: 12, rules: [
        { id: 'w1', name: '米家热水器', enabled: true, conds: [
            { field: 'domain', op: 'eq', value: 'water_heater' },
        ] },
    ] },
    washer: { priority: 12, rules: [
        { id: 'wa1', name: '米家洗衣机', enabled: true, conds: [
            { field: 'entity_id', op: 'contains', value: '_status_p_2_2' },
            { field: 'attr.options', op: 'contains', value: '标准洗' },
        ] },
    ] },
    fan: { priority: 8, rules: [
        { id: 'f1', name: '米家风扇', enabled: true, conds: [
            { field: 'attr.percentage', op: 'exists', value: '' },
            { field: 'name', op: 'contains', value: '风扇' },
        ] },
    ] },
    // 新增类型默认只给按名称识别的宽松规则；admin 里可随时改成 entity_id / 属性条件。
    fan_light: { priority: 12, rules: [
        { id: 'fl1', name: '风扇灯（名称 + 亮度属性）', enabled: true, conds: [
            { field: 'name', op: 'contains', value: '风扇灯' },
            { field: 'attr.brightness', op: 'exists', value: '' },
        ] },
    ] },
    smart_speaker: { priority: 6, rules: [
        { id: 'sp1', name: '智能音箱（按名称）', enabled: true, conds: [
            { field: 'name', op: 'contains', value: '音箱' },
        ] },
    ] },
    water_leak: { priority: 6, rules: [
        { id: 'wl1', name: '水浸传感器（按名称）', enabled: true, conds: [
            { field: 'name', op: 'contains', value: '水浸' },
        ] },
    ] },
    camera: { priority: 6, rules: [
        { id: 'cam1', name: '摄像机（按名称）', enabled: true, conds: [
            { field: 'name', op: 'contains', value: '摄像' },
        ] },
    ] },
    tv_box: { priority: 6, rules: [
        { id: 'tb1', name: '电视盒子（按名称）', enabled: true, conds: [
            { field: 'name', op: 'contains', value: '盒子' },
        ] },
    ] },
    router: { priority: 6, rules: [
        { id: 'rt1', name: 'Potatokid 路由器', enabled: true, conds: [
            { field: 'name', op: 'contains', value: 'Potatokid' },
        ] },
    ] },
    wireless_switch_1: { priority: 6, rules: [
        { id: 'ws1', name: '单键无线开关', enabled: true, conds: [
            { field: 'name', op: 'contains', value: '单键' },
        ] },
    ] },
    wireless_switch_2: { priority: 6, rules: [
        { id: 'ws2a', name: '双键无线开关', enabled: true, conds: [
            { field: 'name', op: 'contains', value: '双键' },
        ] },
        { id: 'ws2b', name: '双开无线开关', enabled: true, conds: [
            { field: 'name', op: 'contains', value: '双开' },
        ] },
    ] },
    wireless_switch_3: { priority: 6, rules: [
        { id: 'ws3', name: '多键无线开关', enabled: true, conds: [
            { field: 'name', op: 'contains', value: '多键' },
        ] },
    ] },
};

const CARD_DEFAULTS = {
    label: '当前值', mainAttr: 'state', mainFmt: '{v}', subTpl: '{state}',
    icon: '✦', color: '#4dd4ac', mainEntity: '主实体', buttons: [{ label: '开关', action: 'toggle' }],
    // 灰度开关：home 端是否启用通用卡片渲染（全量切换后所有类型都为 true）。
    genericEnabled: false,
    // 跨格尺寸：col/row 各 1~4；默认 1×1。
    span: { col: 1, row: 1 },
    // JSON 布局树：admin 可配；为空时 home 用 defaultLayoutFor 生成的通用布局。
    layout: null,
};

// ---------------------------------------------------------------------------
// 通用卡片布局协议（JSON 布局树）
// ---------------------------------------------------------------------------
// 节点类型（一期）：row / column / wrap / text / icon / button / chip /
// progress / sparkline / repeat / divider。占位符在 home 端求值（{title}
// {sub} {main} {label} {icon} {color} {state} {attr.xxx} {gangCount}
// {gangOnCount}，repeat 项用 {item.xxx}），服务端只做白名单校验与透传。
const LAYOUT_NODE_TYPES = new Set([
    'row', 'column', 'wrap', 'text', 'icon', 'button', 'chip',
    'progress', 'sparkline', 'repeat', 'divider',
]);
const LAYOUT_MAX_DEPTH = 8;
const LAYOUT_MAX_NODES = 120;
const LAYOUT_MAX_CHILDREN = 24;

/** 递归清洗布局树：只保留白名单节点与已知字段，限深限宽，杜绝脏配置压垮渲染器。 */
function sanitizeLayout(value, depth = 0, counter = { n: 0 }) {
    if (!value || typeof value !== 'object' || Array.isArray(value)) return null;
    const type = String(value.type || '');
    if (!LAYOUT_NODE_TYPES.has(type) || depth > LAYOUT_MAX_DEPTH) return null;
    if (++counter.n > LAYOUT_MAX_NODES) return null;

    const str = (v, max = 120) => clampText(v == null ? '' : v, max);
    const num = (v, def, lo, hi) => {
        const n = Number(v);
        return Number.isFinite(n) ? Math.max(lo, Math.min(hi, n)) : def;
    };
    const node = { type };

    // 通用样式字段（各节点按需取用，统一校验避免遗漏）
    if (value.gap != null) node.gap = num(value.gap, 8, 0, 64);
    if (value.crossAlign === 'start' || value.crossAlign === 'center' || value.crossAlign === 'end') {
        node.crossAlign = value.crossAlign;
    }
    if (['start', 'center', 'end', 'spaceBetween', 'spaceAround', 'spaceEvenly'].includes(value.mainAlign)) {
        node.mainAlign = value.mainAlign;
    }
    if (value.expand === true) node.expand = true;
    // 节点级值替换（on=着灯,off=关闭），客户端 resolve() 应用；不影响 visibleWhen 条件。
    if (value.map != null) node.map = str(value.map, 240);
    if (value.padding != null) {
        const p = Array.isArray(value.padding) ? value.padding : [];
        node.padding = [num(p[0], 12, 0, 48), num(p[1] != null ? p[1] : p[0], 10, 0, 48)];
    }
    switch (type) {
        case 'text':
            node.value = str(value.value, 160);
            if (value.size != null) node.size = num(value.size, 14, 8, 48);
            if (value.weight != null) node.weight = num(value.weight, 400, 100, 900);
            if (value.color != null) node.color = str(value.color, 40);
            if (value.maxLines != null) node.maxLines = num(value.maxLines, 1, 1, 6);
            if (value.align === 'left' || value.align === 'center' || value.align === 'right') node.align = value.align;
            break;
        case 'icon':
            node.value = str(value.value, 40);
            if (value.size != null) node.size = num(value.size, 24, 8, 64);
            if (value.color != null) node.color = str(value.color, 40);
            if (value.box && typeof value.box === 'object') {
                node.box = {
                    size: num(value.box.size, 46, 16, 96),
                    radius: num(value.box.radius, 12, 0, 32),
                    bg: str(value.box.bg, 40),
                    color: str(value.box.color, 40),
                };
            }
            break;
        case 'button':
        case 'chip':
            node.label = str(value.label, 40);
            if (value.subLabel != null) node.subLabel = str(value.subLabel, 40);
            if (value.icon != null) node.icon = str(value.icon, 40);
            // value 复用为圆形按钮的图标名（round=true 时渲染器优先取 value）
            if (value.value != null) node.value = str(value.value, 40);
            if (value.round === true) node.round = true;
            if (value.size != null) node.size = num(value.size, 52, 16, 96);
            node.onClick = str(value.onClick, 120);
            // style 可为固定枚举，或运行时占位符（如 {gang.style} → active/normal）。
            const styleRaw = str(value.style, 40);
            if (['filled', 'outlined', 'active', 'tonal', 'normal'].includes(styleRaw) || /\{[^}]+\}/.test(styleRaw)) {
                node.style = styleRaw;
            }
            if (value.color != null) node.color = str(value.color, 40);
            if (value.visibleWhen != null) node.visibleWhen = str(value.visibleWhen, 120);
            if (value.confirm != null) node.confirm = str(value.confirm, 60);
            break;
        case 'progress':
            node.value = str(value.value, 40);
            if (value.min != null) node.min = str(value.min, 40);
            if (value.max != null) node.max = str(value.max, 40);
            if (value.color != null) node.color = str(value.color, 40);
            if (value.height != null) node.height = num(value.height, 6, 2, 24);
            if (value.interactive === true) node.interactive = true;
            if (value.visibleWhen != null) node.visibleWhen = str(value.visibleWhen, 120);
            break;
        case 'sparkline':
            node.metric = ['power', 'temperature', 'humidity'].includes(value.metric) ? value.metric : 'power';
            if (value.window != null) node.window = str(value.window, 20);
            if (value.color != null) node.color = str(value.color, 40);
            if (value.height != null) node.height = num(value.height, 60, 24, 180);
            node.showLabels = value.showLabels === true;
            break;
        case 'divider':
            if (value.color != null) node.color = str(value.color, 40);
            if (value.thickness != null) node.thickness = num(value.thickness, 1, 1, 8);
            break;
        case 'repeat':
            node.source = str(value.source || 'gangs', 40);
            node.item = str(value.item || 'item', 20).replace(/[^a-zA-Z0-9_]/g, '') || 'item';
            if (value.columns != null) node.columns = num(value.columns, 2, 1, 4);
            if (value.gap != null) node.gap = num(value.gap, 8, 0, 32);
            if (value.template && typeof value.template === 'object') {
                node.template = sanitizeLayout(value.template, depth + 1, counter);
            }
            return node;
        case 'row':
        case 'column':
        case 'wrap':
            break;
    }
    if (Array.isArray(value.children)) {
        node.children = value.children.slice(0, LAYOUT_MAX_CHILDREN)
            .map((c) => sanitizeLayout(c, depth + 1, counter))
            .filter(Boolean);
    }
    return node;
}

/** 为未配 layout 的类型生成通用默认布局——保证全量切换后每张卡都能渲染。
 *  复用 card 现有字段（icon/color/label/mainFmt 等），admin 可再逐个覆盖。 */
function defaultLayoutFor(key, card) {
    const c = card || {};
    const header = {
        type: 'row', gap: 10, crossAlign: 'center',
        children: [
            {
                type: 'icon', value: c.icon || '✦', size: 24,
                box: { size: 46, radius: 12, bg: '{color}', color: '{color}' },
            },
            {
                type: 'column', expand: 1, gap: 2,
                children: [
                    { type: 'text', value: '{title}', size: 14, weight: 600, maxLines: 1 },
                    { type: 'text', value: '{sub}', size: 12, color: '{color}', maxLines: 1 },
                ],
            },
        ],
    };
    // 多路开关：主区换成 N 个大按钮（每路一个），去掉「已开启路数」与总电源键。
    if (key === 'multi_switch') {
        return {
            type: 'column', gap: 8, padding: [12, 10],
            children: [
                header,
                {
                    type: 'repeat', source: 'gangs', item: 'gang', columns: 2, gap: 8,
                    template: {
                        type: 'button', label: '{gang.label}',
                        subLabel: '{gang.stateLabel}', style: '{gang.style}',
                        onClick: 'toggle@' + '{gang.entityId}',
                    },
                },
            ],
        };
    }
    // 通用卡片：主数值行（label + main + 可选电源键）+ 按钮组。
    const mainChildren = [
        {
            type: 'column', expand: 1, gap: 1,
            children: [
                { type: 'text', value: '{label}', size: 11, color: 'outline', maxLines: 1 },
                { type: 'text', value: '{main}', size: 24, weight: 700, color: '{color}', maxLines: 1 },
            ],
        },
    ];
    mainChildren.push({
        type: 'button', icon: 'power_settings_new', style: 'filled',
        onClick: 'toggle', visibleWhen: '{primary.switchable}',
    });
    const children = [header, { type: 'row', crossAlign: 'end', gap: 8, children: mainChildren }];
    if (Array.isArray(c.buttons) && c.buttons.length) {
        children.push({
            type: 'wrap', gap: 6,
            children: c.buttons.slice(0, 4).map((b, i) => ({
                type: 'chip', label: b.label || ('按钮' + (i + 1)),
                onClick: b.action || 'toggle', style: 'outlined',
            })),
        });
    }
    return { type: 'column', gap: 8, padding: [12, 10], children };
}

const TYPE_KEYS = new Set(DEVICE_TYPES.map((t) => t.key));
const DICT_FIELDS = Object.keys(DICT_DEFAULTS);
const RULE_OPS = new Set(['eq', 'neq', 'contains', 'not_contains', 'startsWith', 'not_startsWith', 'exists', 'gt', 'lt']);

function clampText(value, max = 120) {
    return String(value == null ? '' : value).replace(/[\r\n]/g, ' ').slice(0, max);
}

/** 单条字典规则归一：默认 → 覆盖 → 字段白名单。 */
function normalizeDictEntry(key, value) {
    const base = Object.assign({}, DICT_DEFAULTS, DICT_DETAIL[key] || {});
    if (!value || typeof value !== 'object') return base;
    for (const field of DICT_FIELDS) {
        if (value[field] != null) base[field] = clampText(value[field]);
    }
    return base;
}

function normalizeRules(value) {
    if (!Array.isArray(value)) return [];
    return value.slice(0, 50).filter((r) => r && typeof r === 'object').map((r, i) => ({
        id: String(r.id || ('r' + i)).slice(0, 40),
        name: clampText(r.name || ('规则 ' + (i + 1)), 60),
        enabled: r.enabled !== false,
        conds: (Array.isArray(r.conds) ? r.conds : []).slice(0, 20).filter((c) => c && typeof c === 'object').map((c) => ({
            field: clampText(c.field || 'domain', 80),
            op: RULE_OPS.has(c.op) ? c.op : 'eq',
            value: clampText(c.value == null ? '' : c.value, 120),
        })),
    }));
}

function normalizeCard(value, key) {
    const meta = DEVICE_TYPES.find((t) => t.key === key) || {};
    const base = Object.assign({}, CARD_DEFAULTS, {
        label: (DICT_DETAIL[key] || {}).homeLabel || CARD_DEFAULTS.label,
        mainAttr: (DICT_DETAIL[key] || {}).mainAttr || CARD_DEFAULTS.mainAttr,
        mainFmt: (DICT_DETAIL[key] || {}).mainFmt || CARD_DEFAULTS.mainFmt,
        subTpl: (DICT_DETAIL[key] || {}).subTpl || CARD_DEFAULTS.subTpl,
        icon: meta.icon || CARD_DEFAULTS.icon,
        color: meta.color || CARD_DEFAULTS.color,
    });
    // 默认布局依赖 base 的 icon/buttons 等字段，这里先算好。
    const fallbackLayout = sanitizeLayout(defaultLayoutFor(key, base));
    if (!value || typeof value !== 'object') {
        return Object.assign({}, base, { span: { col: 1, row: 1 }, layout: fallbackLayout });
    }
    const out = Object.assign({}, base);
    for (const f of ['label', 'mainAttr', 'mainFmt', 'subTpl', 'icon', 'color', 'mainEntity']) {
        if (value[f] != null) out[f] = clampText(value[f], f === 'mainEntity' ? 120 : 80);
    }
    if (Array.isArray(value.buttons)) {
        out.buttons = value.buttons.slice(0, 8).filter((b) => b && typeof b === 'object').map((b) => ({
            label: clampText(b.label || '按钮', 24),
            action: clampText(b.action || 'toggle', 60),
        }));
    }
    out.genericEnabled = value.genericEnabled === true;
    // 跨格：col/row 各 1~4，默认 1×1。
    if (value.span && typeof value.span === 'object') {
        const col = Number(value.span.col), row = Number(value.span.row);
        out.span = {
            col: Number.isFinite(col) ? Math.max(1, Math.min(4, Math.round(col))) : 1,
            row: Number.isFinite(row) ? Math.max(1, Math.min(4, Math.round(row))) : 1,
        };
    } else {
        out.span = { col: 1, row: 1 };
    }
    // 布局树：配了就清洗；没配则服务端直接生成默认布局下发，
    // 这样 admin 编辑时能立刻看到当前布局、home 收到即渲染无需再算。
    // home 端仍保留一份同样的默认逻辑作为服务端不可达时的 fallback。
    out.layout = sanitizeLayout(value.layout) || fallbackLayout;
    return out;
}

/**
 * 创建字典服务：读默认规则 + 覆盖层，提供查询 / 更新 / 判定 / 状态解析。
 */
function createDeviceTypeService({ file } = {}) {
    let overrides = {};
    if (file && fs.existsSync(file)) {
        try {
            const raw = JSON.parse(fs.readFileSync(file, 'utf8'));
            if (raw && typeof raw === 'object' && !Array.isArray(raw)) overrides = raw;
        } catch (error) {
            console.error('[deviceTypes] 读取覆盖层失败，使用默认:', error.message);
        }
    }

    function persist() {
        if (!file) return;
        try {
            fs.mkdirSync(path.dirname(file), { recursive: true });
            const tmp = `${file}.tmp`;
            fs.writeFileSync(tmp, JSON.stringify(overrides, null, 2), 'utf8');
            fs.renameSync(tmp, file);
        } catch (error) {
            console.error('[deviceTypes] 写入覆盖层失败:', error.message);
        }
    }

    // 兼容旧格式：旧覆盖层顶层直接是 dict 字段；新格式含 dict/rules/card。
    function entryOf(key) {
        const ov = overrides[key] || {};
        const isNew = Object.prototype.hasOwnProperty.call(ov, 'dict')
            || Object.prototype.hasOwnProperty.call(ov, 'rules')
            || Object.prototype.hasOwnProperty.call(ov, 'card')
            || Object.prototype.hasOwnProperty.call(ov, 'meta');
        const dictPatch = isNew ? (ov.dict || {}) : ov;
        const defaultRule = DEFAULT_RULES[key] || {};
        const meta = DEVICE_TYPES.find((t) => t.key === key);
        return {
            key,
            icon: (ov.meta && ov.meta.icon) || (meta && meta.icon) || '✦',
            label: clampText((ov.meta && ov.meta.label) || (meta && meta.label) || key || '未命名', 40),
            color: (ov.meta && ov.meta.color) || (meta && meta.color) || '#4dd4ac',
            roles: meta ? meta.roles : ['主状态', '副状态1', '副状态2'],
            dict: normalizeDictEntry(key, dictPatch),
            rules: normalizeRules(ov.rules != null ? ov.rules : defaultRule.rules),
            card: normalizeCard(ov.card, key),
            priority: Number.isFinite(ov.priority) ? ov.priority : (defaultRule.priority || 5),
            customized: Object.prototype.hasOwnProperty.call(overrides, key),
            dynamic: !meta,
        };
    }

    /** 返回完整字典（含默认），供 admin 编辑器与 home 端读取。 */
    function list() {
        const built = DEVICE_TYPES.map((t) => entryOf(t.key));
        const dynamic = Object.keys(overrides)
            .filter((k) => !TYPE_KEYS.has(k))
            .map((k) => entryOf(k));
        return built.concat(dynamic);
    }

    function get(key) {
        const k = String(key == null ? '' : key);
        if (!TYPE_KEYS.has(k) && !Object.prototype.hasOwnProperty.call(overrides, k)) {
            return entryOf('');
        }
        return entryOf(k);
    }

    /** admin 覆盖某个类型（支持 dict / rules / card / priority / meta）。 */
    function update(key, patch) {
        const k = String(key == null ? '' : key);
        if (!TYPE_KEYS.has(k) && !Object.prototype.hasOwnProperty.call(overrides, k)) {
            throw new Error('未知设备类型');
        }
        if (!patch || typeof patch !== 'object') throw new Error('字典内容无效');
        const cur = entryOf(k);
        const next = {
            dict: Object.assign({}, cur.dict),
            rules: patch.rules != null ? normalizeRules(patch.rules) : cur.rules,
            card: patch.card != null ? normalizeCard(patch.card, k) : cur.card,
            priority: patch.priority != null ? Number(patch.priority) || 5 : cur.priority,
            meta: patch.meta != null ? {
                label: clampText(patch.meta.label || cur.label, 40),
                icon: clampText(patch.meta.icon || cur.icon, 8),
                color: clampText(patch.meta.color || cur.color, 24),
            } : (cur.dynamic ? { label: cur.label, icon: cur.icon, color: cur.color } : undefined),
        };
        if (patch.dict && typeof patch.dict === 'object') {
            for (const f of DICT_FIELDS) {
                if (patch.dict[f] != null) next.dict[f] = clampText(patch.dict[f]);
            }
        }
        overrides[k] = next;
        persist();
        return entryOf(k);
    }

    /** 新建自定义类型（key 必须唯一）。 */
    function create(key, meta) {
        const k = String(key == null ? '' : key).trim();
        if (!k || !/^[a-z0-9_]{1,40}$/i.test(k)) throw new Error('类型 key 只能用字母数字下划线（1-40 位）');
        if (TYPE_KEYS.has(k) || Object.prototype.hasOwnProperty.call(overrides, k)) throw new Error('类型 key 已存在');
        overrides[k] = {
            dict: {},
            rules: normalizeRules((meta && meta.rules) || [{ id: 'r' + Date.now(), name: '新类型规则 1', enabled: true, conds: [{ field: 'domain', op: 'eq', value: '' }] }]),
            card: normalizeCard(meta && meta.card, k),
            priority: meta && meta.priority != null ? Number(meta.priority) || 5 : 5,
            meta: {
                label: clampText((meta && meta.label) || k, 40),
                icon: clampText((meta && meta.icon) || '✦', 8),
                color: clampText((meta && meta.color) || '#4dd4ac', 24),
            },
        };
        persist();
        return entryOf(k);
    }

    /** 恢复某类型为默认（删除覆盖层条目；内置类型恢复默认，动态类型删除）。 */
    function reset(key) {
        const k = String(key == null ? '' : key);
        if (!TYPE_KEYS.has(k) && !Object.prototype.hasOwnProperty.call(overrides, k)) {
            throw new Error('未知设备类型');
        }
        delete overrides[k];
        persist();
        return TYPE_KEYS.has(k) ? entryOf(k) : entryOf('');
    }

    /** 灰度开关：启用了通用卡片的类型 key 列表（home 据此决定是否替换专用卡片）。 */
    function genericCardTypes() {
        return list().filter((t) => t.card && t.card.genericEnabled === true).map((t) => t.key);
    }

    return { list, get, update, create, reset, genericCardTypes, typeKeys: TYPE_KEYS };
}

// ---------------------------------------------------------------------------
// 判定引擎：把「设备的一组实体」按类型规则判成某一类。
// 输入 entities: [{id, domain, name, state, attrs, device:{name,model,manufacturer}}]
// 规则间 OR、规则内条件 AND（每个条件可由不同实体满足），具体度优先、再按 priority。
// ---------------------------------------------------------------------------

function fieldValue(entity, field) {
    const f = String(field || '');
    if (f.indexOf('attr.') === 0) {
        const k = f.slice(5);
        return entity.attrs && entity.attrs[k] != null ? entity.attrs[k] : undefined;
    }
    if (f.indexOf('device.') === 0) {
        const k = f.slice(7);
        return entity.device && entity.device[k] != null ? entity.device[k] : undefined;
    }
    if (f === 'domain') return entity.domain;
    if (f === 'entity_id') return entity.id;
    if (f === 'name') return entity.name;
    if (f === 'state') return entity.state;
    return undefined;
}

function opMatch(actualValue, op, value) {
    if (op === 'exists') return actualValue !== undefined && actualValue !== '' && actualValue !== null;
    if (actualValue === undefined || actualValue === null) return false;
    const a = String(actualValue);
    const v = String(value == null ? '' : value);
    if (op === 'eq') return a === v;
    if (op === 'neq') return a !== v;
    if (op === 'contains') {
        if (Array.isArray(actualValue)) return actualValue.join('|').indexOf(v) >= 0;
        return a.indexOf(v) >= 0;
    }
    if (op === 'not_contains') return a.indexOf(v) < 0;
    // entity_id 的「开头是」自动忽略 button. / switch. 域前缀。
    if (op === 'startsWith') {
        const bare = a.slice(a.indexOf('.') + 1);
        return a.indexOf(v) === 0 || bare.indexOf(v) === 0;
    }
    if (op === 'not_startsWith') {
        const bare = a.slice(a.indexOf('.') + 1);
        return a.indexOf(v) !== 0 && bare.indexOf(v) !== 0;
    }
    if (op === 'gt') return parseFloat(a) > parseFloat(v);
    if (op === 'lt') return parseFloat(a) < parseFloat(v);
    return false;
}

function condHit(cond, entities) {
    for (const entity of entities || []) {
        if (opMatch(fieldValue(entity, cond.field), cond.op, cond.value)) return true;
    }
    return false;
}

function ruleHit(rule, entities) {
    if (rule.enabled === false) return false;
    if (!Array.isArray(rule.conds) || !rule.conds.length) return false;
    return rule.conds.every((c) => condHit(c, entities));
}

/**
 * 判定设备类型。
 * @param {Array} entities 设备下的实体（含 device 元信息）
 * @param {Array} types deviceTypeService.list() 的类型清单
 * @returns {{key,label,specificity,priority,matchedRules}|null}
 */
function classify(entities, types, options) {
    let best = null;
    const allHits = [];
    for (const type of types || []) {
        const matched = (type.rules || []).filter((r) => ruleHit(r, entities));
        if (!matched.length) continue;
        const specificity = Math.max.apply(null, matched.map((r) => (r.conds || []).length));
        const priority = Number(type.priority) || 5;
        const hit = {
            key: type.key,
            label: type.label,
            specificity,
            priority,
            matchedRules: matched.map((r) => r.name),
        };
        allHits.push(hit);
        if (!best || specificity > best.specificity
            || (specificity === best.specificity && priority > best.priority)) {
            best = hit;
        }
    }
    // 命中测试用：附带全部命中类型，便于看清「为什么选了它」。
    // 普通调用（自动分类）不传 options，行为完全不变。
    if (best && options && options.includeAll) {
        best.allHits = allHits.slice().sort((a, b) =>
            b.specificity - a.specificity || b.priority - a.priority);
    }
    return best;
}

/**
 * 按字典把「设备类型 + 绑定实体的状态」解析成屏幕四行文本。
 */
function resolveDisplay({ deviceType, bindings, states, deviceName, buttonText }) {
    const dict = normalizeDictEntry(deviceType, null);
    const b = bindings || {};
    const stateMap = states || {};

    const mainState = b.main ? stateMap[b.main] : null;
    const s1State = b.s1 ? stateMap[b.s1] : null;
    const s2State = b.s2 ? stateMap[b.s2] : null;

    // 缺失值返回 null（而不是 '--'）：上层据此把整行/整段留白。
    // 例如副状态只绑了 s1 时，subTpl `{s1} · {s2}` 不能渲染成 `亮度 80% · --`。
    function valueOf(stateObj, attr) {
        if (!stateObj) return null;
        const attrs = stateObj.attributes || {};
        const v = attrs[attr];
        if (v != null && v !== '') return String(v);
        if (stateObj.state != null && stateObj.state !== '') return String(stateObj.state);
        return null;
    }

    // 用哨兵标记缺失段：按 `·` 切开后，含缺失值的段整段丢弃，
    // 这样既不会留下 `--`，也不会留下 `·` 或 `目标 °C` 这种半个单位。
    const MISSING = '\u0000';
    function renderSub(tpl, s1Value, s2Value) {
        const text = String(tpl || '')
            .replace('{s1}', s1Value == null ? MISSING : s1Value)
            .replace('{s2}', s2Value == null ? MISSING : s2Value);
        return text.split(/\s*·\s*/)
            .map((part) => part.trim())
            .filter((part) => part !== '' && !part.includes(MISSING))
            .join(' · ')
            .replace(/--/g, '')
            .trim();
    }

    const mainValue = valueOf(mainState, dict.mainAttr);
    const main = mainValue == null
        ? ''
        : dict.mainFmt.replace('{v}', mainValue).replace(/--/g, '').trim();
    const sub = renderSub(dict.subTpl, valueOf(s1State, 'state'), valueOf(s2State, 'state'));
    const title = deviceName || '';
    const keys = buttonText || '';

    return { title, main, sub, keys, homeLabel: dict.homeLabel, step: dict.step };
}

module.exports = {
    DEVICE_TYPES,
    DICT_DEFAULTS,
    DICT_DETAIL,
    DICT_FIELDS,
    DEFAULT_RULES,
    CARD_DEFAULTS,
    normalizeDictEntry,
    normalizeRules,
    normalizeCard,
    createDeviceTypeService,
    classify,
    fieldValue,
    opMatch,
    resolveDisplay,
};
