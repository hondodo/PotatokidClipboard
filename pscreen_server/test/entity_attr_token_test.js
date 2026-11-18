// 实体属性候选（haAttributeTokens）测试。
// 目的：保证 admin 实体选择器能列出 "目标温度" 这类属性，供插入 {entity.attr} 令牌。
// 运行：node test/entity_attr_token_test.js（在 pscreen_server 目录下）。
'use strict';

const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const haSource = fs.readFileSync(
  path.join(__dirname, '..', 'web', 'admin_js', '04-ha.js'),
  'utf8',
);

/** 抽出浏览器脚本里的顶层函数（2 空格缩进）。 */
function extractFunction(source, name) {
  const re = new RegExp(`^  function ${name}\\([\\s\\S]*?^  \\}`, 'm');
  const found = source.match(re);
  if (!found) throw new Error(`未找到函数 ${name}`);
  return found[0];
}

function loadHa() {
  const skip = haSource.match(/^  const HA_ATTR_SKIP = new Set\(\[[\s\S]*?^  \]\);$/m);
  const prio = haSource.match(/^  const HA_ATTR_PRIORITY = \{[\s\S]*?^  \};$/m);
  if (!skip) throw new Error('未找到 HA_ATTR_SKIP');
  if (!prio) throw new Error('未找到 HA_ATTR_PRIORITY');
  const sandbox = {};
  vm.createContext(sandbox);
  vm.runInContext(
    [
      skip[0],
      prio[0],
      extractFunction(haSource, 'haAttributeTokens'),
      'this.api = { attrTokens: haAttributeTokens };',
    ].join('\n'),
    sandbox,
  );
  return sandbox.api;
}

const api = loadHa();

// VM 里造出的数组原型不属于宿主 realm，deepStrictEqual 会误判；先过一层 JSON 归一化。
const plain = (value) => JSON.parse(JSON.stringify(value));

let passed = 0;
function ok(name, fn) {
  fn();
  passed += 1;
  console.log(`  ✓ ${name}`);
}

// 线上真实结构（棠德304 小米空调），只保留与测试相关的属性。
const climate = {
  id: 'climate.xiaomi_cn_735376016_m9',
  state: 'off',
  attributes: {
    hvac_modes: ['cool', 'dry', 'fan_only', 'heat', 'off'],
    min_temp: 16,
    max_temp: 31,
    target_temp_step: 0.5,
    current_temperature: 25.9,
    temperature: 27,
    current_humidity: 62,
    humidity: 0,
    fan_mode: '二档',
    hvac_action: 'off',
    friendly_name: '小米空调 空调',
    icon: 'mdi:air-conditioner',
    supported_features: 429,
  },
};

console.log('haAttributeTokens：');

ok('空调：目标温度 / 当前温度排在前面', () => {
  const attrs = api.attrTokens(climate).map((t) => t.attr);
  assert.deepStrictEqual(plain(attrs.slice(0, 4)), [
    'current_temperature',
    'temperature',
    'current_humidity',
    'humidity',
  ]);
});

ok('空调：目标温度取值就是 27（不是独立实体也能取到）', () => {
  const token = api.attrTokens(climate).find((t) => t.attr === 'temperature');
  assert.ok(token, '必须能取到 temperature');
  assert.strictEqual(token.value, '27');
});

ok('空调：跳过元信息与数组属性', () => {
  const attrs = api.attrTokens(climate).map((t) => t.attr);
  for (const skipped of ['friendly_name', 'icon', 'supported_features', 'hvac_modes']) {
    assert.ok(!attrs.includes(skipped), `不应包含 ${skipped}`);
  }
});

ok('空调：其余标量属性仍然保留', () => {
  const attrs = api.attrTokens(climate).map((t) => t.attr);
  for (const kept of ['max_temp', 'min_temp', 'target_temp_step', 'fan_mode']) {
    assert.ok(attrs.includes(kept), `应包含 ${kept}`);
  }
});

ok('湿度 0 是有效值，不能被当成空值丢掉', () => {
  const token = api.attrTokens(climate).find((t) => t.attr === 'humidity');
  assert.ok(token, 'humidity=0 应保留');
  assert.strictEqual(token.value, '0');
});

ok('属性值统一转成字符串', () => {
  const tokens = api.attrTokens({ id: 'cover.a', attributes: { current_position: 50 } });
  assert.strictEqual(tokens[0].value, '50');
});

ok('没有可显示属性的实体返回空数组（选择器直接插入实体本身）', () => {
  assert.deepStrictEqual(
    plain(api.attrTokens({ id: 'sensor.a', attributes: { friendly_name: '温度' } })),
    [],
  );
  assert.deepStrictEqual(plain(api.attrTokens({ id: 'switch.b' })), []);
  assert.deepStrictEqual(plain(api.attrTokens(null)), []);
  assert.deepStrictEqual(plain(api.attrTokens(undefined)), []);
});

ok('灯：亮度优先', () => {
  const attrs = api.attrTokens({
    id: 'light.bedroom',
    attributes: { brightness: 180, color_temp_kelvin: 4000, friendly_name: '灯' },
  }).map((t) => t.attr);
  assert.strictEqual(attrs[0], 'brightness');
});

console.log(`\n${passed} 项全部通过`);
