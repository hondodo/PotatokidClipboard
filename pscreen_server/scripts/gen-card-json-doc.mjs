#!/usr/bin/env node
/**
 * 从源码提取 Home 设备卡片 JSON 协议的真实能力，写回
 * <repo>/admin页Home设备卡片json配置说明.md 的 <!-- AUTO:xxx --> 区块。
 *
 * 用法：
 *   node pscreen_server/scripts/gen-card-json-doc.mjs          # 更新文档
 *   node pscreen_server/scripts/gen-card-json-doc.mjs --check  # 只检查是否过期（CI / hook）
 *
 * 新增解析类型后，只要源码里有对应分支，运行本脚本即可自动同步文档。
 * 描述取自分支上方紧邻的 // 注释；未写注释时会显示「源码未注释」，
 * 所以在源码里顺手写一行注释就能让文档自动带上说明。
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(HERE, '..', '..');
const DOC = path.join(ROOT, 'admin页Home设备卡片json配置说明.md');
const SRC = {
  dart: path.join(ROOT, 'pscreen_home/lib/features/home/domain/models/card_layout.dart'),
  server: path.join(ROOT, 'pscreen_server/server/deviceTypes.js'),
  board: path.join(ROOT, 'pscreen_home/lib/features/home/presentation/pages/home_controll_board.dart'),
};
const CHECK_ONLY = process.argv.includes('--check');

const read = (p) => fs.readFileSync(p, 'utf8').replace(/\r\n/g, '\n');
const src = Object.fromEntries(Object.entries(SRC).map(([k, p]) => [k, read(p)]));
const docOriginal = read(DOC);

function between(text, startMark, endMark) {
  const a = text.indexOf(startMark);
  if (a < 0) return '';
  const b = endMark ? text.indexOf(endMark, a + startMark.length) : -1;
  return text.slice(a + startMark.length, b < 0 ? text.length : b);
}

function lines(text) {
  return text.split('\n');
}

/** 取描述：优先紧邻的连续 // 注释；找不到时向上搜含关键字的最近注释块。 */
function commentAbove(arr, idx, keyword) {
  const collect = (start, dir) => {
    const out = [];
    for (let i = start; i >= 0 && i < arr.length; i += dir) {
      const t = arr[i].trim();
      if (!t.startsWith('//')) break;
      out.unshift(t.replace(/^\/\/\/?\s?/, '').trim());
    }
    return out.filter(Boolean).join(' ').replace(/\s+/g, ' ').slice(0, 220);
  };
  let out = collect(idx - 1, -1);
  if (keyword && !out.toLowerCase().includes(keyword.toLowerCase())) {
    for (let i = idx - 1, scanned = 0; i >= 0 && scanned < 30; i -= 1, scanned += 1) {
      const t = arr[i].trim();
      if (!t.startsWith('//') || !t.toLowerCase().includes(keyword.toLowerCase())) continue;
      out = collect(i, 1);
      break;
    }
  }
  return out;
}

function table(header, rows) {
  const cols = Math.max(1, header.split('|').length - 2);
  const sep = `| ${Array(cols).fill('---').join(' | ')} |`;
  return [header, sep, ...rows.map((r) => `| ${r.join(' | ')} |`)].join('\n');
}

// ---------------------------------------------------------------- 占位符
const PLACEHOLDER_DESC = {
  title: '卡片标题；渲染层在多房间时自动拼房间名，不要再写 {room}',
  room: '房间名',
  icon: '类型图标',
  color: '类型主题色',
  label: '类型标签（如「当前温度」）',
  main: '按 mainAttr / mainFmt 算出的主数值',
  sub: '按 subTpl 算出的副文案',
  state: '主实体 state',
  s1: '组内第 2 个实体的 state',
  s2: '组内第 3 个实体的 state',
  status: '分组状态文案',
  gangCount: '可开关路数',
  gangOnCount: '已开启路数',
  'primary.entityId': '主实体完整 entity_id',
  'primary.switchable': '主实体是否可切换（常用于 visibleWhen）',
  brightnessPercent: '亮度百分比 0-100',
  brightness: '亮度原始值 0-255',
  'attr.xxx': '主实体任意属性（如 {attr.friendly_name}）',
  'entity.N.state': '组内第 N 个实体 state（N 从 0 起，最多 16）',
  'entity.N.id': '组内第 N 个实体 entity_id',
  'entity.N.name': '组内第 N 个实体显示名',
  'gang.xxx': 'repeat/source=gangs 时每路的字段（label/state/stateLabel/style/entityId/index）',
  'item.xxx': 'repeat 模板项字段（等价于 gang.xxx 的通用写法）',
  's:后缀': '按 entity_id 子串匹配组内实体，取 state；支持 {s:后缀.属性} 读属性',
  'a:后缀.属性': '按后缀匹配实体，取指定 attribute',
  'id:后缀': '按后缀匹配实体，取完整 entity_id（动作通道常用）',
};

function buildPlaceholders() {
  const body = between(src.dart, "final Map<String, String> v = <String, String>{", '    return v;');
  // 只取 map 字面量的键（前面是 { 或 ,），避开三元表达式里的 'true' : 'false'
  const keys = [...body.matchAll(/[{,]\s*'([a-zA-Z][\w.]*)'\s*:/g)].map((m) => m[1]);
  const dynamic = ['attr.xxx', 'entity.N.state', 'entity.N.id', 'entity.N.name', 'gang.xxx', 'item.xxx'];
  const entityKinds = [...between(src.dart, 'String? _resolveEntityToken(String key)', '  /// 把原始值按 map')
    .matchAll(/case '(id|s|a)':/g)].map((m) => (m[1] === 'a' ? 'a:后缀.属性' : `${m[1]}:后缀`));
  const all = [...new Set([...keys, ...dynamic, ...entityKinds])];
  const known = Object.keys(PLACEHOLDER_DESC);
  const order = [...known, ...all.filter((k) => !known.includes(k))];
  return table('| 写法 | 取值 |', order.map((k) => [
    `\`{${k}}\``,
    PLACEHOLDER_DESC[k] || '源码有此字段；说明待补（在脚本 PLACEHOLDER_DESC 里加一条）',
  ]));
}

// ---------------------------------------------------------------- 内联规则
const INLINE_META = {
  pct: { name: 'pct', desc: 'HA light 的 0-255 → 0-100 百分比；>255 视为已是百分比，不再换算' },
  date: { name: 'date[:pattern]', desc: 'ISO 时间按 Flutter DateFormat 格式化，带时区偏移（如 `+00:00`）会先转本地时间再显示；支持 `zh:` / `en_US:` 前缀，省略 pattern 用 yMd' },
  maxwith: { name: 'maxWith=<占位符 key>', desc: '当前值与另一个占位符都是 ISO 时间时取较晚者；非时间值以可解析的一方为准' },
  ago: { name: 'ago', desc: 'ISO 时间 → 相对时间（刚刚 / N分钟前 / N小时前 / N天前）；非时间值原样返回' },
  when: { name: 'when=<key>:<期望值>=<文案>', desc: '另一个占位符当前值等于期望值时，把本占位符输出替换为文案（key 含冒号，如 s:_charging_state_p_5_2；如充电中覆盖开机文案）' },
};

function buildInlineRules() {
  const body = between(src.dart, '  /// 占位符内联规则：', '  /// 规则分段：');
  const arr = lines(body);
  const seen = new Set();
  const rows = [];
  arr.forEach((line, i) => {
    const m = line.match(/low\s*==\s*'([a-z]+)'/i) || line.match(/low\.startsWith\('([a-z]+)[=:]'/i);
    if (!m) return;
    const name = m[1].toLowerCase();
    if (seen.has(name)) return;
    seen.add(name);
    const meta = INLINE_META[name];
    const desc = (meta && meta.desc) || commentAbove(arr, i, name) || '源码未写注释';
    rows.push([`\`|${meta ? meta.name : name}\``, desc]);
  });
  rows.push(['`|key=值`', '通用映射：整值精确匹配（兼容旧写法），键也可写阈值 `>=30` / `>30` / `<=20` / `<20` / `=30` / `!=30`，从上往下取首个命中，`default=` 兜底（与位置无关）；值可用单/双引号包住以保护逗号；多条用逗号 / 中文逗号 / 分号分隔']);
  return table('| 规则 | 作用 |', rows);
}

// ---------------------------------------------------------------- 阈值映射 / 条件比较
function buildThresholdRules() {
  return [
    '数值类属性（温度、湿度、功率、电量、百分比……）可用**阈值区间**驱动文案 / 颜色 / 图标 / 背景，写法是在映射键前加比较符：',
    '',
    '```json',
    '{ "type": "text", "value": "{attr.current_temperature}",',
    '  "map": ">=30=高温,>=20=舒适,default=偏低" }',
    '{ "type": "icon", "value": "{s:_battery_level_p_5_1}",',
    '  "iconMap": ">=95=battery_full,>=75=battery_6_bar,>=50=battery_4_bar,>=20=battery_2_bar,default=battery_alert" }',
    '{ "type": "column", "bg": "{attr.current_temperature}",',
    '  "bgMap": ">=30=#FF5252,>=20=#FFB74D,default=#4CAF50", "bgRadius": 12,',
    '  "children": [ ... ] }',
    '```',
    '',
    '| 键 | 含义 |',
    '| --- | --- |',
    '| `>=30` / `>30` / `<=20` / `<20` / `=30` / `!=30` | 把求值结果转成数值后按阈值比较；多条**从上往下取首个命中**（所以降序写 `>=30,>=20`） |',
    '| `default=`（或 `else=`） | 前面都没命中时的兜底，位置无关；不写则保留原值 |',
    '| `on=` / `off=` 等普通键 | 整值精确匹配（兼容旧写法），优先于阈值判断 |',
    '',
    '适用字段：`map`、`colorMap`、`iconMap`、`labelMap`、`bgMap`（以及占位符内联 `|>=30=...`）。',
    '`iconMap` 的图标名必须是 App 内置白名单里的名字（如 `battery_full` / `battery_6_bar` … `battery_0_bar` / `battery_alert` / `battery_charging_full`、`power`、`lightbulb`、`ac_unit`、`water_drop`、`wind`、`tv`、`cloud`、`lock`、`show_chart` 等）；写成不认识的名字会显示成默认「设备」图标。也支持单个符号（☀ ❄ ⏻）或图片 URL。',
    '`bgMap` 操作的是 `bg` 求值出来的值；`bg` 留空时取 `value`。背景色支持 `#RRGGBB` / `#RRGGBBAA` / 语义色名 / `outline` 等。',
    '',
    '`visibleWhen` / `enabledWhen` 同样支持数值比较，例如 `"{attr.battery_level}>=20"`、`"{attr.current_temperature}<28"`；两边都能转成数字时按数值比，否则按字符串比。',
    '',
    '> 阈值映射与 `bgMap` 是新增解析能力，**旧版 App 不认识，需重编安装**；后台预览会尝试近似渲染，以 App 实际显示为准。',
  ].join('\n');
}

// ---------------------------------------------------------------- 节点类型
function buildNodeTypes() {
  const block = between(src.server, 'const LAYOUT_NODE_TYPES = new Set([', ']);');
  const types = [...block.matchAll(/'([^']+)'/g)].map((m) => m[1]);
  const desc = {
    row: '横向排列；gap / crossAlign / mainAlign。行内 column 建议显式写 crossAlign（start/center/end）：这样按内容宽度排布，配合 mainAlign:spaceBetween 均匀铺开；不写则默认 stretch 并占用等分宽度',
    column: '纵向排列；fill:true 撑满高度，配合 mainAlign:spaceBetween 贴底。作为 row 子节点时显式写 crossAlign 可按内容宽度排布',
    wrap: '横向自动换行',
    stack: '层叠；子节点用 stackAlign / position 定位',
    text: '文本；value / size / weight / color / maxLines / align / marquee*',
    icon: '图标；value / size / color / box(size/radius/bg/color)',
    button: '按钮；label / icon / value / style / onClick / round / height',
    chip: '小按钮；字段同 button，常用作快捷操作',
    progress: '进度条；value / min / max / color / height / interactive / onClick',
    sparkline: '功率曲线；metric(power/temperature/humidity) / window / height / showLabels',
    repeat: '重复模板；source / item / columns / gap / template',
    divider: '分割线；color / thickness',
    spacer: '弹性空白（等价 Flutter Spacer）；flex 权重 1~20（默认 1），必须作为 row/column 的直接子节点，容器需有有界尺寸',
    sizedBox: '固定空白（等价 Flutter SizedBox）；width / height 像素 0~2000，省略的维度不约束',
  };
  return table('| type | 主要字段 |', types.map((t) => [`\`${t}\``, desc[t] || '见源码 sanitizeLayout']));
}

// ---------------------------------------------------------------- 字段白名单
function buildFields() {
  const body = between(src.server, 'function sanitizeLayout(value, depth = 0', '/** 为未配 layout 的类型生成通用默认布局');
  const switchAt = body.indexOf('switch (type)');
  const segments = [{ scope: '通用', text: body.slice(0, switchAt) }];
  let rest = body.slice(switchAt);
  // 合并连续的 case 标签（button/chip、row/column/wrap/stack），否则字段会只归到最后一个 case
  let merged;
  do {
    merged = rest;
    rest = rest.replace(/case\s*'([a-z]+)':\s*\n\s*(case\s*'([a-z]+)':)/g, "case '$1,$3':");
  } while (rest !== merged);
  const caseRe = /case\s*'([a-z,]+)':([\s\S]*?)(?=\n\s*case\s*'|\n\s*default:|return node;)/g;
  for (const m of rest.matchAll(caseRe)) segments.push({ scope: m[1].split(',').join(' / '), text: m[2] });

  const found = new Map();
  const add = (name, type, scope) => {
    if (!name) return;
    const cur = found.get(name) || { types: [], scopes: [] };
    if (!cur.types.includes(type)) cur.types.push(type);
    if (!cur.scopes.includes(scope)) cur.scopes.push(scope);
    found.set(name, cur);
  };
  for (const seg of segments) {
    for (const m of seg.text.matchAll(/str\(value\.([A-Za-z]\w*),\s*(\d+)\)/g)) add(m[1], `字符串 ≤${m[2]}`, seg.scope);
    for (const m of seg.text.matchAll(/num\(value\.([A-Za-z]\w*),\s*([-\d.]+),\s*([-\d.]+),\s*([-\d.]+)\)/g)) {
      add(m[1], `数值 ${m[3]}~${m[4]}（默认 ${m[2]}）`, seg.scope);
    }
    for (const m of seg.text.matchAll(/\[([^\]]+)\]\.includes\(value\.([A-Za-z]\w*)\)/g)) {
      const vals = [...m[1].matchAll(/'([^']+)'/g)].map((x) => x[1]).join(' / ');
      add(m[2], `枚举：${vals}`, seg.scope);
    }
    for (const m of seg.text.matchAll(/value\.([A-Za-z]\w*)\s*===\s*true/g)) add(m[1], '布尔（true 才保留）', seg.scope);
    // 对象 / 数组字段：代码里只判空，没有 str()/num() 包裹
    const objectDesc = {
      padding: '数组 [垂直, 水平]，各 0~48',
      box: '对象 {size 16~96, radius 0~32, bg, color}',
      position: '对象 {left/top/right/bottom/width/height}，像素 -2000~2000',
      template: '节点对象（repeat 模板）',
    };
    for (const m of seg.text.matchAll(/if\s*\(value\.(padding|box|position|template)\b/g)) {
      add(m[1], objectDesc[m[1]], seg.scope);
    }
  }
  if (/Array\.isArray\(value\.children\)/.test(body)) {
    add('children', '子节点数组（最多 24 个）', '通用');
  }
  const rows = [...found.entries()]
    .sort((a, b) => a[0].localeCompare(b[0]))
    .map(([name, v]) => [`\`${name}\``, v.types.join('；'), v.scopes.join(' / ')]);
  return table('| 字段 | 类型 / 值域 | 适用节点 |', rows);
}

// ---------------------------------------------------------------- 限制 / 动作 / 时间
function buildLimits() {
  const keys = ['LAYOUT_MAX_DEPTH', 'LAYOUT_MAX_NODES', 'LAYOUT_MAX_CHILDREN'];
  const label = { LAYOUT_MAX_DEPTH: '布局最大深度', LAYOUT_MAX_NODES: '单卡最大节点数', LAYOUT_MAX_CHILDREN: '单节点最大子节点数' };
  return keys.map((k) => {
    const m = src.server.match(new RegExp(`const ${k} = (\\d+)`));
    return `${label[k]} ${m ? m[1] : '?'}`;
  }).join('；') + '。超限节点保存时会被丢弃。';
}

const ACTION_META = {
  'kettle@action': '热水瓶专用：按实时状态选择开始 / 停止，不猜实体',
  'climateTemp@': '空调目标温度 ±：climateTemp@<实体>:<增量>（如 -0.5 / +0.5）',
  'climateMode@': '空调模式循环：climateMode@<实体>，依次切下一个 hvac_mode',
  'climateFan@': '空调风速：climateFan@<实体> 循环下一档；climateFan@<实体>:+1 / :-1 按实体 fan_modes 索引步进并钳制在两端（± 按钮用，不会回绕）',
  toggle: '切换主实体（未指定 entityId 时）',
  turn_on: '兼容旧写法，同 toggle',
  turn_off: '兼容旧写法，同 toggle',
  press: '按主实体按钮（未指定 entityId 时）',
  notify: '主实体发通知动作',
};

function buildActions() {
  let a = src.board.indexOf("if (trimmed == 'kettle@action')");
  const commentStart = src.board.lastIndexOf('// 这里按 KettleSummary', a);
  if (commentStart >= 0 && a - commentStart < 400) a = commentStart;
  const b = src.board.indexOf('Future<bool> dispatchActionWithResult', a);
  const body = src.board.slice(a, b < 0 ? src.board.length : b);
  const arr = lines(body);
  const seen = new Set();
  const rows = [];
  arr.forEach((line, i) => {
    const m = line.match(/startsWith\('([A-Za-z_]+@)'\)/) || line.match(/trimmed\s*==\s*'([A-Za-z_]+@[\w]+)'/)
      || (/case\s*'/.test(line) ? line.match(/case\s*'([a-z_]+)'\s*:/i) : null);
    if (!m) return;
    const name = m[1];
    if (seen.has(name)) return;
    seen.add(name);
    rows.push([`\`${name}\``, ACTION_META[name] || commentAbove(arr, i, name) || '源码未写注释']);
  });
  return table('| onClick 写法 | 行为 |', rows);
}

const CARD_FIELD_DESC = {
  label: '类型标签 / 主数值说明',
  mainAttr: '主数值取自主实体的哪个属性',
  mainFmt: '主数值格式模板，{v} 为原始值',
  subTpl: '副文案模板，支持 {main}/{state}/{s1}/{s2}',
  icon: '卡片图标，布局里用 {icon} 引用',
  color: '主题色，布局里用 {color} 引用',
  bg: '卡片正常背景色：#RRGGBB / #RRGGBBAA / {color}26；留空跟随主题',
  disabledBg: '设备不可用 / 断线时的卡片背景色；留空跟随主题',
  mainEntity: '主实体匹配串（entity_id 或名称子串）',
  buttons: '旧版按钮定义（新布局一般用 layout 里的 button / chip）',
  genericEnabled: '是否启用通用卡片渲染',
  span: '跨格尺寸 {col,row}，各 1~4',
  layout: 'JSON 布局树，见第 4 节',
};

function buildCardFields() {
  const body = between(src.server, 'function normalizeCard(value, key)', '\n}\n');
  const m = body.match(/for \(const f of \[([^\]]+)\]\)/);
  const whitelisted = m ? [...m[1].matchAll(/'([^']+)'/g)].map((x) => x[1]) : [];
  const all = [...new Set([...whitelisted, 'buttons', 'genericEnabled', 'span', 'layout'])];
  return table('| card 字段 | 说明 |', all.map((f) => [
    `\`${f}\``,
    CARD_FIELD_DESC[f] || '见源码 normalizeCard',
  ]));
}

function buildDatePatterns() {
  const body = between(src.dart, 'static DateFormat _dateFormat(String pattern, String locale)', '  /// 按 entity_id 后缀查找组内实体');
  const pats = [...body.matchAll(/case\s*'([^']+)':/g)].map((m) => m[1]);
  return pats.map((p) => `\`${p}\``).join(' / ');
}

// ---------------------------------------------------------------- 写回文档
const sections = {
  placeholders: buildPlaceholders(),
  inlineRules: buildInlineRules(),
  thresholdRules: buildThresholdRules(),
  nodeTypes: buildNodeTypes(),
  cardFields: buildCardFields(),
  fields: buildFields(),
  limits: buildLimits(),
  actions: buildActions(),
  datePatterns: buildDatePatterns(),
};

let out = docOriginal;
for (const [name, content] of Object.entries(sections)) {
  const re = new RegExp(`(<!-- AUTO:${name} -->)[\\s\\S]*?(<!-- AUTO:END -->)`, 'g');
  if (!re.test(out)) {
    console.error(`文档缺少标记 <!-- AUTO:${name} --> ... <!-- AUTO:END -->，请先补标记`);
    process.exit(2);
  }
  out = out.replace(re, `$1\n${content}\n$2`);
}

if (CHECK_ONLY) {
  if (out !== docOriginal) {
    console.error('文档已过期：请运行 node pscreen_server/scripts/gen-card-json-doc.mjs 更新');
    process.exit(1);
  }
  console.log('文档与源码一致');
} else {
  fs.writeFileSync(DOC, out, 'utf8');
  console.log(`已更新 ${path.relative(ROOT, DOC)}（${Object.keys(sections).length} 个自动区块）`);
}
