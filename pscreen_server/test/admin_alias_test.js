// 家长私有别名（方案 B）与设备备注归一的最小测试。
// 运行：node test/admin_alias_test.js（在 pscreen_server 目录下）。
'use strict';

const assert = require('assert');
const path = require('path');
const { normalizeMachineName, normalizeMachineAliases } = require(path.join(__dirname, '..', 'server', 'admin.js'));

let passed = 0;
function ok(name, fn) {
    fn();
    passed += 1;
    console.log(`  ✓ ${name}`);
}

console.log('[admin alias] 归一测试');

ok('历史占位名不再算「已设置备注」', () => {
    // 线上存量脏数据：旧 PUT 空值写成了字面量「未命名设备」并置 nameSet=true。
    const name = normalizeMachineName('未命名设备');
    assert.strictEqual(name.name, '未命名设备');
    assert.strictEqual(name.nameSet, false);
});

ok('空名称回落占位且 nameSet=false', () => {
    const name = normalizeMachineName('   ');
    assert.strictEqual(name.name, '未命名设备');
    assert.strictEqual(name.nameSet, false);
});

ok('真实备注保留并置 nameSet=true', () => {
    const name = normalizeMachineName(' 客厅电视 ');
    assert.strictEqual(name.name, '客厅电视');
    assert.strictEqual(name.nameSet, true);
});

ok('别名表只保留合法账号，trim 后截断到 40 字', () => {
    const aliases = normalizeMachineAliases({
        'parent.parent.65e60b477c6a676f': '  客厅电视  ',
        'bad account!': '非法账号',
        empty: '   ',
        number: 123,
        long: 'x'.repeat(60),
    });
    assert.deepStrictEqual(Object.keys(aliases), ['parent.parent.65e60b477c6a676f', 'long']);
    assert.strictEqual(aliases['parent.parent.65e60b477c6a676f'], '客厅电视');
    assert.strictEqual(aliases.long.length, 40);
});

ok('别名表非对象一律清空', () => {
    assert.deepStrictEqual(normalizeMachineAliases(null), {});
    assert.deepStrictEqual(normalizeMachineAliases(['a']), {});
    assert.deepStrictEqual(normalizeMachineAliases('x'), {});
});

ok('写盘回读别名不丢（normalize 幂等）', () => {
    const aliases = { 'parent.parent.65e60b477c6a676f': '电视' };
    assert.deepStrictEqual(normalizeMachineAliases(normalizeMachineAliases(aliases)), aliases);
});

console.log(`[admin alias] 通过 ${passed} 项`);
