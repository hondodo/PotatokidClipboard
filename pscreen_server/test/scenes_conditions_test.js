// 自动化触发规则测试：规则内 AND / 规则间 OR、旧结构迁移、ha_state 轮询、window 条件。
// 运行：node test/scenes_conditions_test.js（在 pscreen_server 目录下）。
'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const { attachScenes, normalizeScene, describeTrigger } = require('../server/scenes');

const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'scenes-cond-'));
const configFile = path.join(tmpDir, 'scenes.json');

let pass = 0;
let fail = 0;
function ok(name, fn) {
  try { fn(); pass += 1; console.log(`OK   ${name}`); }
  catch (error) { fail += 1; console.log(`FAIL ${name}\n     ${error.message}`); }
}
async function aok(name, fn) {
  try { await fn(); pass += 1; console.log(`OK   ${name}`); }
  catch (error) { fail += 1; console.log(`FAIL ${name}\n     ${error.message}`); }
}

const HA_STATES = {
  'light.living': { entity_id: 'light.living', state: 'on', attributes: { brightness: '120' } },
  'sensor.temp': { entity_id: 'sensor.temp', state: '26', attributes: {} },
};
const machines = [
  { id: 'esp-a', name: '小屏A', espPresence: { present: true, lastEnterAt: Date.now(), lastLeaveAt: 0, updatedAt: Date.now() } },
];
const getStates = async (ids) => {
  const out = {};
  for (const id of ids) if (HA_STATES[id]) out[id] = HA_STATES[id];
  return out;
};

const engine = attachScenes({
  file: configFile,
  listMachines: () => machines,
  getStates,
  readRemoteState: (id) => (id === 'remote.tv_01.page' ? '首页' : ''),
  runAction: async () => ({ result: 'ok' }),
  log: () => {},
});

function write(raw) {
  fs.writeFileSync(configFile, JSON.stringify({ version: 1, settings: { occupiedWindowSec: 90, haPollSec: 5 }, scenes: raw }, null, 2));
}

const baseAction = [{ type: 'ha', entityId: 'light.living', action: 'turn_on' }];
const lightOn = { type: 'ha_state', entityId: 'light.living', op: 'eq', value: 'on' };
const lightOff = { type: 'ha_state', entityId: 'light.living', op: 'eq', value: 'off' };
const tempHigh = { type: 'ha_state', entityId: 'sensor.temp', op: 'gt', value: '30' };
const remoteHome = { type: 'ha_state', entityId: 'remote.tv_01.page', op: 'eq', value: '首页' };

console.log('=== 自动化触发规则测试（规则内 AND，规则间 OR）===');

ok('normalizeScene: 旧单 trigger 迁移成一条规则一条条件', () => {
  const scene = normalizeScene({
    name: '旧规则', kind: 'auto',
    trigger: { type: 'presence', deviceId: 'esp-a', state: 'present', holdSec: 5 },
    actions: baseAction,
  });
  assert.strictEqual(scene.trigger.rules.length, 1);
  assert.strictEqual(scene.trigger.rules[0].conditions.length, 1);
  assert.strictEqual(scene.trigger.rules[0].conditions[0].type, 'presence');
  assert.strictEqual(scene.trigger.rules[0].conditions[0].holdSec, 5);
});

ok('normalizeScene: 旧 AND 组 → 一条规则多条件；旧 OR 组 → 每条条件一条规则', () => {
  const andScene = normalizeScene({
    name: '旧AND', kind: 'auto',
    trigger: { logic: 'and', conditions: [lightOn, remoteHome] },
    actions: baseAction,
  });
  assert.strictEqual(andScene.trigger.rules.length, 1);
  assert.strictEqual(andScene.trigger.rules[0].conditions.length, 2);

  const orScene = normalizeScene({
    name: '旧OR', kind: 'auto',
    trigger: { logic: 'or', conditions: [lightOn, remoteHome] },
    actions: baseAction,
  });
  assert.strictEqual(orScene.trigger.rules.length, 2);
  assert.deepStrictEqual(orScene.trigger.rules.map((r) => r.conditions.length), [1, 1]);
});

ok('normalizeScene: 新 rules 结构保留五类条件', () => {
  const scene = normalizeScene({
    name: '多规则', kind: 'auto',
    trigger: { rules: [
      { conditions: [
        { type: 'presence', deviceId: 'esp-a', state: 'present', holdSec: 10 },
        { type: 'ha_state', entityId: 'sensor.temp', op: 'gt', value: '30' },
      ] },
      { conditions: [
        { type: 'window', days: [1, 2], start: '22:00', end: '02:00' },
        { type: 'time', at: '07:30' },
        { type: 'button', deviceId: 'esp-a', slot: 1 },
      ] },
    ] },
    actions: baseAction,
  });
  assert.strictEqual(scene.trigger.rules.length, 2);
  assert.deepStrictEqual(scene.trigger.rules[0].conditions.map((c) => c.type), ['presence', 'ha_state']);
  assert.deepStrictEqual(scene.trigger.rules[1].conditions.map((c) => c.type), ['window', 'time', 'button']);
  assert.strictEqual(scene.trigger.rules[0].conditions[1].op, 'gt');
});

ok('normalizeScene: 非法条件类型 / 空规则直接抛错', () => {
  assert.throws(() => normalizeScene({
    name: '坏规则', kind: 'auto',
    trigger: { rules: [{ conditions: [{ type: 'nope' }] }] },
    actions: baseAction,
  }), /类型不支持/);
  assert.throws(() => normalizeScene({
    name: '空规则', kind: 'auto',
    trigger: { rules: [{ conditions: [] }] },
    actions: baseAction,
  }), /至少需要一条条件/);
});

ok('describeTrigger: 规则间「或」、规则内「且」，多条件规则带括号', () => {
  const text = describeTrigger({ rules: [
    { conditions: [
      { type: 'presence', deviceId: 'esp-a', state: 'present', holdSec: 5 },
      { type: 'ha_state', entityId: 'light.living', op: 'eq', value: 'on' },
    ] },
    { conditions: [{ type: 'time', at: '07:30' }] },
  ] }, { deviceName: () => '小屏A' });
  assert.ok(text.includes('(') && text.includes(')'), text);
  assert.ok(text.includes('且'), text);
  assert.ok(text.includes('或'), text);
  assert.ok(text.includes('小屏A') && text.includes('light.living'), text);
});

async function runTick() {
  engine.tick();
  // tick 里 HA 轮询是异步的，等一个宏任务让它完成
  await new Promise((resolve) => setTimeout(resolve, 20));
}
function savedScene() {
  return JSON.parse(fs.readFileSync(configFile, 'utf8')).scenes[0];
}
function sceneOf(trigger, name = 'T') {
  return {
    id: 'sx', name, kind: 'auto', enabled: true, cooldownSec: 0,
    trigger, window: { days: [], start: '', end: '' },
    actions: baseAction, lastRunAt: 0, runCount: 0,
  };
}

(async () => {
  await aok('ha_state 条件：状态匹配即触发', async () => {
    write([sceneOf({ rules: [{ conditions: [lightOn] }] })]);
    engine.setSettings({ haPollSec: 5 });
    await runTick();
    assert.ok(savedScene().runCount >= 1, `runCount=${savedScene().runCount}`);
  });

  await aok('ha_state 条件：状态不匹配不触发', async () => {
    write([sceneOf({ rules: [{ conditions: [lightOff] }] }, '灯关时')]);
    engine.setSettings({ haPollSec: 5 });
    await runTick();
    assert.strictEqual(savedScene().runCount, 0);
  });

  await aok('规则内 AND：一条不满足就不触发', async () => {
    write([sceneOf({ rules: [{ conditions: [lightOn, tempHigh] }] }, 'AND')]);
    engine.setSettings({ haPollSec: 5 });
    await runTick();
    assert.strictEqual(savedScene().runCount, 0);
  });

  await aok('规则间 OR：任一规则满足即触发', async () => {
    write([sceneOf({ rules: [
      { conditions: [lightOff, tempHigh] }, // 整条规则不满足
      { conditions: [lightOn] },            // 这条满足
    ] }, 'OR')]);
    engine.setSettings({ haPollSec: 5 });
    await runTick();
    assert.ok(savedScene().runCount >= 1);
  });

  await aok('全部规则都不满足时不触发', async () => {
    write([sceneOf({ rules: [
      { conditions: [lightOff] },
      { conditions: [tempHigh] },
    ] }, '全不满足')]);
    engine.setSettings({ haPollSec: 5 });
    await runTick();
    assert.strictEqual(savedScene().runCount, 0);
  });

  await aok('旧 OR 条件组读时迁移后仍按 OR 触发', async () => {
    write([sceneOf({ logic: 'or', conditions: [lightOff, remoteHome] }, '旧OR')]);
    engine.setSettings({ haPollSec: 5 });
    await runTick();
    assert.ok(savedScene().runCount >= 1);
  });

  await aok('遥控伪实体条件：remote.* 走注入的状态读取', async () => {
    write([sceneOf({ rules: [{ conditions: [remoteHome] }] }, '遥控首页')]);
    engine.setSettings({ haPollSec: 5 });
    await runTick();
    assert.ok(savedScene().runCount >= 1);
  });

  await aok('window 条件：不在允许时段不触发', async () => {
    const now = new Date();
    const h = now.getHours();
    const m = now.getMinutes();
    const start = `${String((h + 1) % 24).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
    const end = `${String((h + 2) % 24).padStart(2, '0')}:${String(m).padStart(2, '0')}`;
    write([sceneOf({ rules: [{ conditions: [
      lightOn,
      { type: 'window', days: [], start, end },
    ] }] }, '未来窗口')]);
    engine.setSettings({ haPollSec: 5 });
    await runTick();
    assert.strictEqual(savedScene().runCount, 0);
  });

  await aok('settings: haPollSec 归一化到 5–60', () => {
    const s = engine.setSettings({ haPollSec: 999 });
    assert.strictEqual(s.haPollSec, 60);
    const s2 = engine.setSettings({ haPollSec: 1 });
    assert.strictEqual(s2.haPollSec, 5);
  });

  console.log(`\n结果：${pass} 通过 / ${fail} 失败`);
  fs.rmSync(tmpDir, { recursive: true, force: true });
  process.exit(fail ? 1 : 0);
})();
