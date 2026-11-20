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
  { id: 'esp-a', name: '小屏A', role: 'master', lastSeen: Date.now(), espPresence: { present: true, lastEnterAt: Date.now(), lastLeaveAt: 0, updatedAt: Date.now() } },
  // 深睡从机：1 小时定时唤醒，5 分钟前睡下去（上次心跳），睡前报了无人。
  { id: 'esp-b', name: '从机B', role: 'slave', sleepSec: 3600, lastSeen: Date.now() - 5 * 60 * 1000,
    espPresence: { present: false, lastEnterAt: Date.now() - 10 * 60 * 1000, lastLeaveAt: Date.now() - 6 * 60 * 1000, updatedAt: Date.now() - 5 * 60 * 1000 } },
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

  // ---- 设备离线时的感应判定（2026-11-20 修的 bug：断电设备冻结在「有人」反复点火）----

  ok('感应实体：在线设备沿用上报电平，present=true 报「有人」', () => {
    machines[0].lastSeen = Date.now();
    const entity = engine.presenceEntities().find((e) => e.deviceId === 'esp-a');
    assert.ok(entity, '应返回 esp-a 的感应实体');
    assert.strictEqual(entity.online, true);
    assert.strictEqual(entity.presence, 'present');
    assert.strictEqual(entity.occupied, true);
  });

  ok('感应实体：设备离线时报 unknown/离线，occupied 强制空闲', () => {
    machines[0].lastSeen = Date.now() - 120 * 1000; // 心停 2 分钟 > 90 秒窗口
    const entity = engine.presenceEntities().find((e) => e.deviceId === 'esp-a');
    assert.strictEqual(entity.online, false);
    assert.strictEqual(entity.presence, 'unknown');
    assert.strictEqual(entity.presenceText, '离线');
    assert.strictEqual(entity.occupied, false);
  });

  await aok('离线设备：「有人持续」条件不触发', async () => {
    machines[0].lastSeen = Date.now() - 120 * 1000;
    write([sceneOf({ rules: [{ conditions: [
      { type: 'presence', deviceId: 'esp-a', state: 'present', holdSec: 0 },
      lightOn,
    ] }] }, '离线有人')]);
    engine.setSettings({ haPollSec: 5 });
    await runTick();
    assert.strictEqual(savedScene().runCount, 0);
  });

  await aok('离线设备：「无人」条件同样不触发（状态未知 ≠ 无人）', async () => {
    machines[0].lastSeen = Date.now() - 120 * 1000;
    write([sceneOf({ rules: [{ conditions: [
      { type: 'presence', deviceId: 'esp-a', state: 'absent', holdSec: 0 },
      lightOff,
    ] }] }, '离线无人')]);
    engine.setSettings({ haPollSec: 5 });
    await runTick();
    assert.strictEqual(savedScene().runCount, 0);
  });

  await aok('恢复心跳后：有人条件重新按真实上报判定', async () => {
    machines[0].lastSeen = Date.now(); // present=true 仍在上报
    write([sceneOf({ rules: [{ conditions: [
      { type: 'presence', deviceId: 'esp-a', state: 'present', holdSec: 0 },
      lightOn,
    ] }] }, '恢复有人')]);
    engine.setSettings({ haPollSec: 5 });
    await runTick();
    assert.ok(savedScene().runCount >= 1, `runCount=${savedScene().runCount}`);
  });

  // ---- 深睡从机休眠：四态（有人/无人/休眠/离线），休眠按「无人」判定 ----

  ok('感应实体：休眠窗口内的从机报「休眠」，occupied 为空闲', () => {
    // esp-b：slave + sleepSec=3600，5 分钟前心跳 → 距预期唤醒点还有 55 分钟
    const entity = engine.presenceEntities().find((e) => e.deviceId === 'esp-b');
    assert.ok(entity, '应返回 esp-b 的感应实体');
    assert.strictEqual(entity.online, false);
    assert.strictEqual(entity.sleeping, true);
    assert.strictEqual(entity.presence, 'sleep');
    assert.strictEqual(entity.presenceText, '休眠');
    assert.strictEqual(entity.occupied, false);
    assert.ok(entity.expectedWakeAt > Date.now(), '应能推算出预期唤醒时间');
  });

  await aok('休眠从机：「无人」条件照常触发（休眠 = 无人）', async () => {
    write([sceneOf({ rules: [{ conditions: [
      { type: 'presence', deviceId: 'esp-b', state: 'absent', holdSec: 0 },
      lightOn, // fixture 里 light.living = on
    ] }] }, '休眠无人')]);
    engine.setSettings({ haPollSec: 5 });
    await runTick();
    assert.ok(savedScene().runCount >= 1, `runCount=${savedScene().runCount}`);
  });

  await aok('休眠从机：「有人」条件不触发', async () => {
    write([sceneOf({ rules: [{ conditions: [
      { type: 'presence', deviceId: 'esp-b', state: 'present', holdSec: 0 },
      lightOn,
    ] }] }, '休眠有人')]);
    engine.setSettings({ haPollSec: 5 });
    await runTick();
    assert.strictEqual(savedScene().runCount, 0);
  });

  await aok('休眠超预期唤醒 +10 分钟宽限仍无心跳：判真离线，无人条件也不触发', async () => {
    // lastSeen = now - 71min → 预期唤醒点 = lastSeen + 60min = now - 11min，已超 10 分钟宽限 1 分钟
    machines[1].lastSeen = Date.now() - 71 * 60 * 1000;
    const entity = engine.presenceEntities().find((e) => e.deviceId === 'esp-b');
    assert.strictEqual(entity.presence, 'unknown');
    assert.strictEqual(entity.presenceText, '离线');
    assert.strictEqual(entity.sleeping, false);
    write([sceneOf({ rules: [{ conditions: [
      { type: 'presence', deviceId: 'esp-b', state: 'absent', holdSec: 0 },
      lightOff,
    ] }] }, '掉线从机')]);
    engine.setSettings({ haPollSec: 5 });
    await runTick();
    assert.strictEqual(savedScene().runCount, 0);
    machines[1].lastSeen = Date.now() - 5 * 60 * 1000; // 还原成休眠窗口内
  });

  console.log(`\n结果：${pass} 通过 / ${fail} 失败`);
  fs.rmSync(tmpDir, { recursive: true, force: true });
  process.exit(fail ? 1 : 0);
})();
