// ESP 模板令牌（含第三段属性）前后端同构测试。
// 运行：node test/esp_template_token_test.js（在 pscreen_server 目录下）。
'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const root = path.join(__dirname, '..');
const beSource = fs.readFileSync(path.join(root, 'server', 'admin.js'), 'utf8');
const feSource = fs.readFileSync(path.join(root, 'web', 'admin_js', '11-esp.js'), 'utf8');

/** 从源码里抽出指定缩进的顶层函数（浏览器脚本 2 空格 / admin.js 闭包内 4 空格）。 */
function extractFunction(source, name, indent) {
  const pad = ' '.repeat(indent);
  const re = new RegExp(`^${pad}function ${name}\\([\\s\\S]*?^${pad}\\}`, 'm');
  const found = source.match(re);
  if (!found) throw new Error(`未找到函数 ${name}（缩进 ${indent}）`);
  return found[0];
}

function loadBackend() {
  const tokenRe = beSource.match(/^    const ESP_TPL_TOKEN_RE = .*$/m);
  if (!tokenRe) throw new Error('未找到后端 ESP_TPL_TOKEN_RE');
  const sandbox = {};
  vm.createContext(sandbox);
  vm.runInContext([
    tokenRe[0],
    extractFunction(beSource, 'parseEspTemplateTokens', 4),
    extractFunction(beSource, 'renderEspTemplate', 4),
    extractFunction(beSource, 'espStateValue', 4),
    'this.api = { parse: parseEspTemplateTokens, render: renderEspTemplate, value: espStateValue };',
  ].join('\n'), sandbox);
  return sandbox.api;
}

function loadFrontend() {
  const sandbox = {};
  vm.createContext(sandbox);
  vm.runInContext([
    extractFunction(feSource, 'espTemplateTokens', 2),
    extractFunction(feSource, 'espRenderTemplate', 2),
    extractFunction(feSource, 'espEntityValue', 2),
    'this.api = { parse: espTemplateTokens, render: espRenderTemplate, value: espEntityValue };',
  ].join('\n'), sandbox);
  return sandbox.api;
}

const be = loadBackend();
const fe = loadFrontend();

// VM 里造出的对象原型不属于宿主 realm，deepStrictEqual 会误判；先过一层 JSON 归一化。
const plain = (value) => JSON.parse(JSON.stringify(value));

let passed = 0;
function ok(name, fn) {
  fn();
  passed += 1;
  console.log(`  ✓ ${name}`);
}

console.log('[esp template] 前后端同构测试');

ok('两段令牌仍是 state，三段令牌带属性', () => {
  const tpl = '{main} {climate.bed} {climate.bed.temperature} {remote.tv.channel}';
  assert.deepStrictEqual(plain(be.parse(tpl)), plain(fe.parse(tpl)));
  assert.deepStrictEqual(plain(be.parse(tpl)), [
    { baseId: 'climate.bed', attr: 'state', key: 'climate.bed' },
    { baseId: 'climate.bed', attr: 'temperature', key: 'climate.bed.temperature' },
    { baseId: 'remote.tv', attr: 'channel', key: 'remote.tv.channel' },
  ]);
});

ok('同名实体不同属性各自保留 key，不互相覆盖', () => {
  const tpl = '{climate.bed.current_temperature}° / {climate.bed.temperature}°';
  const keys = plain(be.parse(tpl)).map((t) => t.key);
  assert.deepStrictEqual(keys, [
    'climate.bed.current_temperature',
    'climate.bed.temperature',
  ]);
  assert.deepStrictEqual(plain(be.parse(tpl)).map((t) => t.key), plain(fe.parse(tpl)).map((t) => t.key));
});

ok('正则不跨占位符误吞中文/标点', () => {
  const tpl = '当前{climate.bed.current_temperature}℃·目标{climate.bed.temperature}℃';
  assert.strictEqual(be.parse(tpl).length, 2);
  assert.deepStrictEqual(plain(be.parse(tpl)), plain(fe.parse(tpl)));
});

ok('温度模板渲染：前后端逐字节一致', () => {
  const tpl = '{climate.bed}档 当前{climate.bed.current_temperature}° 目标{climate.bed.temperature}°';
  const entities = {
    'climate.bed': '关',
    'climate.bed.current_temperature': '25.9',
    'climate.bed.temperature': '27',
  };
  const ctx = { main: '', s1: '', s2: '', title: '', entities };
  const expect = '关档 当前25.9° 目标27°';
  assert.strictEqual(be.render(tpl, ctx), expect);
  assert.strictEqual(fe.render(tpl, ctx), expect);
});

ok('属性缺失回落 state（前后端一致）', () => {
  const stateObj = { state: 'off', attributes: { current_temperature: 25.9, temperature: 27 } };
  const index = new Map([['climate.bed', stateObj]]);
  assert.strictEqual(be.value(stateObj, 'temperature'), '27');
  assert.strictEqual(fe.value(index, new Map(), new Map(), 'climate.bed', 'temperature'), '27');
  assert.strictEqual(be.value(stateObj, 'not_exist'), 'off');
  assert.strictEqual(fe.value(index, new Map(), new Map(), 'climate.bed', 'not_exist'), 'off');
});

ok('remote 三段令牌仍由语义字段填充，不被 HA 解析覆盖', () => {
  const tpl = '{remote.tv.channel} / {climate.bed.temperature}';
  const ctx = {
    main: '', s1: '', s2: '', title: '',
    entities: { 'remote.tv.channel': '6', 'climate.bed.temperature': '27' },
  };
  assert.strictEqual(be.render(tpl, ctx), '6 / 27');
  assert.strictEqual(fe.render(tpl, ctx), '6 / 27');
});

ok('属性走值替换但不影响 state（前端取值链路）', () => {
  const stateObj = { state: 'off', attributes: { temperature: 'cool' } };
  const index = new Map([['climate.bed', stateObj]]);
  const map = new Map([['off', '关'], ['cool', '制冷']]);
  assert.strictEqual(fe.value(index, map, new Map(), 'climate.bed', 'state'), '关');
  assert.strictEqual(fe.value(index, map, new Map(), 'climate.bed', 'temperature'), '制冷');
});

console.log(`[esp template] 通过 ${passed} 项`);
