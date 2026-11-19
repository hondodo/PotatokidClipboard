// ESP sys 变量 / 天气城市映射表 / 每页状态栏 端到端测试。
// 运行：node test/esp_sys_test.js（在 pscreen_server 目录下）。
// 无心知 key 时天气变量降级为空（不阻塞），本地造 machines.json 桩数据。
'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const express = require('express');
const TEST_IMG_B64 = Buffer.alloc(1024, 0xff).toString('base64');
const cookieParser = require('cookie-parser');
const { attachAdmin } = require(path.join(__dirname, '..', 'server', 'admin.js'));

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), 'espsys-'));
const datasDir = path.join(tmp, 'datas');
fs.mkdirSync(path.join(datasDir, 'admin'), { recursive: true });
fs.mkdirSync(path.join(datasDir, 'screen', 'datas'), { recursive: true });
const machinesFile = path.join(datasDir, 'admin', 'machines.json');

// 一台 ESP：第 1 页只有 sys 变量（无 HA 实体），验证解耦 entityIds 后仍能渲染。
const testDeviceId = 'esp_sys_test_001';
fs.writeFileSync(machinesFile, JSON.stringify({
  [testDeviceId]: {
    id: testDeviceId,
    kind: 'esp',
    name: '测试小屏',
    espPages: [{
      id: 'p1',
      name: '客厅状态',
      tplMain: '人在 {sys.present} · {sys.time}',
      tplSub: '广州 {sys.weather.gz}｜{sys.lunar}',
      bindings: { main: '', s1: '', s2: '' },
      valueMap: '',
      entityValueMap: '',
      remoteTarget: '',
      buttons: [],
      loop: true,
      idle: 0,
      statusBar: { enabled: true, showPage: true, showTime: true, showWifiIcon: true, showRssi: false, showIp: false },
    }, {
      // 第 2 页：勾选「显示图片」+ 反色 + 状态栏全关。
      // 模板故意留文字，验证开关优先于模板（勾选后整页只出图）。
      id: 'p2',
      name: '图片页',
      tplMain: '这行不该出现在真机',
      tplSub: '{sys.time}',
      bindings: {},
      valueMap: '',
      entityValueMap: '',
      remoteTarget: '',
      buttons: [],
      loop: true,
      idle: 0,
      statusBar: { enabled: false, showPage: false, showTime: false, showWifiIcon: false, showRssi: false, showIp: false },
      image: { data: TEST_IMG_B64, invert: true, enabled: true },
    }, {
      // 第 3 页：旧配置兼容 —— 没有 enabled 字段，模板只有 {image}。
      id: 'p3',
      name: '旧图片页',
      tplMain: '{image}',
      tplSub: '',
      bindings: {},
      valueMap: '',
      entityValueMap: '',
      remoteTarget: '',
      buttons: [],
      loop: true,
      idle: 0,
      statusBar: { enabled: true, showPage: true, showTime: true, showWifiIcon: true, showRssi: false, showIp: false },
      image: { data: TEST_IMG_B64, invert: false },
    }, {
      // 第 4 页：勾了但没有图片数据 —— 不应下发 IMG，也不该清空文字。
      id: 'p4',
      name: '空图片页',
      tplMain: '正常文字 {sys.time}',
      tplSub: '',
      bindings: {},
      valueMap: '',
      entityValueMap: '',
      remoteTarget: '',
      buttons: [],
      loop: true,
      idle: 0,
      statusBar: { enabled: true, showPage: true, showTime: true, showWifiIcon: true, showRssi: false, showIp: false },
      image: { data: '', invert: false, enabled: true },
    }, {
      // 第 5 页：四行内容位 —— 页面名/按键提示都隐藏，行3/4 填模板。
      id: 'p5',
      name: '不该显示',
      tplMain: '主状态一',
      tplSub: '副状态二',
      tplLine3: '内容第三行',
      tplLine4: '内容第四行',
      showTitle: false,
      showKeys: true,
      bindings: {},
      valueMap: '',
      entityValueMap: '',
      remoteTarget: '',
      buttons: [{
        id: 'btn1', name: '翻页', label: '翻页', kind: 'sys', action: 'next_page',
        param: '', entityId: '', slot: 1, enabled: true,
      }],
      loop: true,
      idle: 0,
      statusBar: { enabled: true, showPage: true, showTime: true, showWifiIcon: true, showRssi: false, showIp: false },
    }, {
      // 第 6 页：默认开关（页面名/按键提示都显示）→ 行3/4 即便填了也不开放。
      id: 'p6',
      name: '默认页面名',
      tplMain: '主{A}',
      tplSub: '',
      tplLine3: '不该出现的第三行',
      tplLine4: '不该出现的第四行',
      bindings: { A: '' },
      valueMap: 'A=甲',
      entityValueMap: '',
      remoteTarget: '',
      buttons: [{
        id: 'btn2', name: '下一页', label: '下一页', kind: 'sys', action: 'next_page',
        param: '', entityId: '', slot: 2, enabled: true,
      }],
      loop: true,
      idle: 0,
      statusBar: { enabled: true, showPage: true, showTime: true, showWifiIcon: true, showRssi: false, showIp: false },
    }],
    espButtons: [],
    espSlotNames: {},
    espScreen: { onSeconds: 0 },
  },
}), 'utf8');

const app = express();
app.use(express.json({ limit: '5mb' }));
app.use(cookieParser());
attachAdmin(app, {
  datasDir,
  registerUsersDir: path.join(tmp, 'register'),
  webAppPath: path.join(tmp, 'web'),
});

const server = app.listen(0, async () => {
  const port = server.address().port;
  const base = `http://127.0.0.1:${port}`;
  let passed = 0;
  const ok = (name, fn) => { fn(); passed += 1; console.log(`  ✓ ${name}`); };
  try {
    console.log('[esp sys] 端到端测试');

    // 1. actions text：纯 sys 页必须渲染（time/lunar 有值，天气无 key 降级空）。
    const actionsResp = await fetch(`${base}/api/device/esp/actions?format=text&deviceId=${testDeviceId}&page=1`);
    const text = await actionsResp.text();
    assert.strictEqual(actionsResp.status, 200);
    const lines = text.split('\n');
    const pageLine = lines.find((l) => l.startsWith('PAGE|'));
    const barLine = lines.find((l) => l.startsWith('BAR|'));
    const dispLine = lines.find((l) => l.startsWith('DISPLAY|'));
    ok('PAGE 行存在且页码正确', () => {
      assert.ok(pageLine);
      assert.strictEqual(pageLine.split('|')[1], '1');
      assert.strictEqual(pageLine.split('|')[2], '6'); // 桩数据六页
    });
    ok('BAR 行按每页配置下发 7 段', () => {
      assert.ok(barLine);
      const f = barLine.split('|');
      assert.deepStrictEqual(f, ['BAR', '1', '1', '1', '1', '0', '0']);
    });
    ok('纯 sys 页渲染出时间与农历（未被 entityIds.length 吞掉）', () => {
      assert.ok(dispLine, 'DISPLAY 行必须存在');
      const f = dispLine.split('|');
      const main = f[2];
      const sub = f[3];
      assert.ok(/\d{2}:\d{2}/.test(main), `main 应有 HH:MM，实际=${main}`);
      assert.ok(/[月初廿十]/.test(sub), `sub 应有农历，实际=${sub}`);
      // 本机类 token 原样保留给固件
      assert.ok(main.includes('{sys.present}'), `main 应保留 present token，实际=${main}`);
      // 无 key 时天气整段省略，不留 '广州 ' 尾巴里的 --（城市名是用户手写的，保留）
      assert.ok(!sub.includes('--'), `sub 不应有 --，实际=${sub}`);
    });

    // 1b. 图片页：IMG|id|base64|invert，状态栏按页独立（第 2 页全关）。
    const imgResp = await fetch(`${base}/api/device/esp/actions?format=text&deviceId=${testDeviceId}&page=2`);
    const imgText = await imgResp.text();
    const imgLines = imgText.split('\n');
    const imgLine = imgLines.find((l) => l.startsWith('IMG|'));
    const bar2 = imgLines.find((l) => l.startsWith('BAR|'));
    ok('IMG 行按页下发点阵与反色位', () => {
      assert.strictEqual(imgResp.status, 200);
      assert.ok(imgLine, '必须下发 IMG 行');
      const f = imgLine.split('|');
      assert.strictEqual(f[1], 'p2');
      assert.strictEqual(f[2], TEST_IMG_B64);
      assert.strictEqual(f[3], '1');
    });
    ok('状态栏配置按页独立（第 2 页全关）', () => {
      assert.ok(bar2);
      assert.deepStrictEqual(bar2.split('|'), ['BAR', '0', '0', '0', '0', '0', '0']);
    });
    ok('勾选显示图片后模板文字不生效，base64 不进 DISPLAY 行', () => {
      const disp2 = imgLines.find((l) => l.startsWith('DISPLAY|'));
      assert.ok(disp2, 'DISPLAY 行必须存在');
      const f = disp2.split('|');
      assert.strictEqual(f[1], '', '纯图片页标题必须留空（真机不叠页面名）');
      assert.strictEqual(f[2], '', '{image} 不渲染成文字，否则真机滚 base64');
      assert.strictEqual(f[3], '');
      assert.ok(!disp2.includes(TEST_IMG_B64.slice(0, 24)), 'DISPLAY 行不得包含点阵数据');
    });

    // 1c. 旧配置兼容：没有 enabled 字段，模板只有 {image} 仍按图片页处理。
    const legacyResp = await fetch(`${base}/api/device/esp/actions?format=text&deviceId=${testDeviceId}&page=3`);
    const legacyLines = (await legacyResp.text()).split('\n');
    ok('旧 {image} 模板无 enabled 仍下发 IMG 且文字留空', () => {
      assert.ok(legacyLines.some((l) => l.startsWith('IMG|')), '旧配置也应下发 IMG');
      const disp = legacyLines.find((l) => l.startsWith('DISPLAY|'));
      assert.ok(disp);
      const f = disp.split('|');
      assert.deepStrictEqual([f[1], f[2], f[3]], ['', '', '']);
    });

    // 1d. 勾了但没图：不下发 IMG，也不清空文字。
    const emptyLines = (await (await fetch(`${base}/api/device/esp/actions?format=text&deviceId=${testDeviceId}&page=4`)).text()).split('\n');
    ok('勾选但无图片数据：不下发 IMG 且保留正文', () => {
      assert.ok(!emptyLines.some((l) => l.startsWith('IMG|')), '空数据不应下发 IMG');
      const disp = emptyLines.find((l) => l.startsWith('DISPLAY|'));
      assert.ok(disp);
      assert.ok(/\d{2}:\d{2}/.test(disp.split('|')[2]), `正文应保留时间，实际=${disp}`);
    });

    // 1e. v4.2：ROWS 行按显示开关合并，隐藏行3/4 让出的内容位。
    const p5Text = await (await fetch(`${base}/api/device/esp/actions?format=text&deviceId=${testDeviceId}&page=5`)).text();
    const p5Lines = p5Text.split('\n');
    const p5Rows = p5Lines.find((l) => l.startsWith('ROWS|'));
    ok('隐藏页面名后 ROWS 不含页面名，内容行3 生效', () => {
      assert.ok(p5Rows, '必须下发 ROWS 行');
      const f = p5Rows.split('|').slice(1);
      assert.ok(!f.includes('不该显示'), '页面名已隐藏，不能出现');
      assert.deepStrictEqual(f, ['主状态一', '副状态二', '内容第三行', '1:翻页'],
        `隐藏一行时应把主/副/行3/按键提示上移成四行，实际=${f}`);
      assert.ok(!f.includes('内容第四行'), '只隐藏页面名时行4 不开放');
    });

    const p6Text = await (await fetch(`${base}/api/device/esp/actions?format=text&deviceId=${testDeviceId}&page=6`)).text();
    const p6Rows = p6Text.split('\n').find((l) => l.startsWith('ROWS|'));
    ok('默认开关下 ROWS 不含内容行3/4（编辑了也不下发）', () => {
      assert.ok(p6Rows);
      const f = p6Rows.split('|').slice(1);
      assert.deepStrictEqual(f, ['默认页面名', '主', '2:下一页'],
        `默认开关下只显示页面名/主/按键，实际=${f}`);
      assert.ok(!f.some((x) => x.includes('不该出现')), `行3/4 未开放时不得下发，实际=${f}`);
    });

    // 2. 城市映射表纯逻辑（generateCityId / normalizeCities），不依赖鉴权。
    const { createEspSys } = require(path.join(__dirname, '..', 'server', 'esp_sys.js'));
    const sys = createEspSys({
      adminDir: path.join(datasDir, 'admin'),
      readJson: (f, fb) => (fs.existsSync(f) ? JSON.parse(fs.readFileSync(f, 'utf8')) : fb),
      writeJson: (f, v) => fs.writeFileSync(f, JSON.stringify(v)),
    });
    const defaults = sys.readCities();
    ok('城市表默认含 auto/gz/zj/fs', () => {
      assert.deepStrictEqual(defaults.map((c) => c.id), ['auto', 'gz', 'zj', 'fs']);
    });
    ok('新增城市：首字母 zj 被占用，降级全拼 zhenjiang', () => {
      const gen = sys.generateCityId('镇江', defaults);
      assert.strictEqual(gen.id, 'zhenjiang');
      assert.ok(gen.note.includes('zj'));
    });
    ok('新增城市：首字母未占用则用短名', () => {
      const gen = sys.generateCityId('南京', defaults);
      assert.strictEqual(gen.id, 'nj');
      assert.strictEqual(gen.note, '');
    });
    ok('全拼也占用时追加序号', () => {
      const withZhenjiang = defaults.concat([{ id: 'zhenjiang', name: '镇江', location: '镇江' }]);
      const gen = sys.generateCityId('镇江', withZhenjiang);
      assert.strictEqual(gen.id, 'zhenjiang2');
    });
    ok('normalizeCities 挡掉非法 id 与重复，auto 固定置顶', () => {
      const norm = sys.normalizeCities([
        { id: 'BAD ID', name: 'x', location: 'x' },
        { id: 'gz', name: '广州', location: '广州' },
        { id: 'gz', name: '广州2', location: '广州' },
        { id: 'auto', name: '改自动', location: 'x' },
      ]);
      assert.strictEqual(norm[0].id, 'auto');
      assert.strictEqual(norm[0].name, '自动');
      assert.strictEqual(norm.filter((c) => c.id === 'gz').length, 1);
    });
    ok('农历跨年夜/闰月边界换算稳定', () => {
      assert.strictEqual(sys.lunarText(new Date('2024-02-10T12:00:00Z')), '正月初一');
      assert.strictEqual(sys.lunarText(new Date('2025-01-29T12:00:00Z')), '正月初一');
      assert.strictEqual(sys.lunarText(new Date('1989-01-01T12:00:00Z')).length > 0, true);
    });

    console.log(`[esp sys] 通过 ${passed} 项`);
  } catch (e) {
    console.error('[esp sys] 失败:', e);
    process.exitCode = 1;
  } finally {
    server.close();
  }
});
