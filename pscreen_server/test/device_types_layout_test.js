// 设备类型布局清洗测试：占位符/内联规则字段不能被 40 字上限截断。
// 线上故障：空调模式 chip 的 {state|cool=...,heat=...} 被截成 40 字，
// 右花括号丢失后客户端把模板原文直接显示出来并溢出卡片。
// 运行：node test/device_types_layout_test.js（在 pscreen_server 目录下）。
'use strict';

const assert = require('assert');
const path = require('path');
const { normalizeCard } = require(path.join(__dirname, '..', 'server', 'deviceTypes'));

let passed = 0;
function ok(name, fn) {
    fn();
    passed += 1;
    console.log(`  ✓ ${name}`);
}

/** 占位符必须闭合；截断后最常见的症状就是没有右花括号。 */
function assertTemplateIntact(value, label) {
    assert.ok(value.includes('{'), `${label} 应包含占位符`);
    const open = (value.match(/\{/g) || []).length;
    const close = (value.match(/\}/g) || []).length;
    assert.strictEqual(open, close, `${label} 占位符未闭合：${value}`);
}

console.log('[device types] 布局模板完整性：');

const layout = normalizeCard({}, 'climate').layout;
const chips = layout.children[2].children;

ok('空调默认布局右上角电源键走主实体 toggle 通道', () => {
    const header = layout.children[0].children;
    const power = header[2];
    assert.strictEqual(power.type, 'chip');
    assert.strictEqual(power.round, true);
    assert.strictEqual(power.icon, 'power_settings_new');
    assert.strictEqual(power.onClick, 'toggle@{primary.entityId}');
});

ok('空调默认布局 chip label 保留完整内联规则', () => {
    const mode = chips[0].label;
    assert.strictEqual(mode, '{state|cool=制冷,dry=除湿,fan_only=送风,heat=制热,off=已关闭,auto=自动}');
    assertTemplateIntact(mode, '模式 chip label');
    assertTemplateIntact(chips[2].label, '节能 chip label');
    assertTemplateIntact(chips[3].label, '睡眠 chip label');
    assertTemplateIntact(chips[4].label, '防直吹 chip label');
});

ok('空调默认布局条件 color 不被截断', () => {
    for (const chip of chips.slice(2)) assertTemplateIntact(chip.color, `${chip.label} color`);
});

ok('自定义 chip/text 的长表达式也能通过清洗', () => {
    const label = '{s:switch.a|on=✓ 已开启,off=已关闭,unavailable=未知,when=s:switch.b:on=联动中}';
    const color = '{s:switch.a|on=#2f9cff,off=#64748b,unavailable=#9ca3af}';
    const custom = normalizeCard({ layout: { type: 'chip', label, color, onClick: 'toggle@a' } }, 'light').layout;
    assert.strictEqual(custom.label, label);
    assert.strictEqual(custom.color, color);
    assertTemplateIntact(custom.label, '自定义 chip label');
    assertTemplateIntact(custom.color, '自定义 chip color');
});

console.log(`[device types] 通过 ${passed} 项`);
