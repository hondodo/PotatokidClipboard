// node test/parental_share_test.js
// 档案引用共享：白名单校验 + 引用展开(主本/只读/broken) + 可见性护栏 + 题库落点 + 时长归并。
'use strict';

const assert = require('assert');
const path = require('path');
const admin = require(path.join(__dirname, '..', 'server', 'admin.js'));
const share = require(path.join(__dirname, '..', 'server', 'parental_share.js'));

let passed = 0;
function ok(name, fn) {
    try { fn(); passed++; console.log(`  ✓ ${name}`); }
    catch (e) { console.error(`  ✗ ${name}`); console.error(e); process.exit(1); }
}
function reject(name, fn, keyword) {
    ok(name, () => {
        assert.throws(fn, (err) => {
            assert.ok(String(err.message).includes(keyword), `期望含「${keyword}」，实际：${err.message}`);
            return true;
        });
    });
}

console.log('[parental-share] 档案引用共享测试');

// ---------- 1. normalizeParental 对新增字段的校验 ----------
ok('children[].sharedTo 默认 []，parental.shared 默认 []', () => {
    const r = admin.normalizeParental({ mode: 'on', children: [{ id: 'c1', name: '小薯' }] });
    assert.deepStrictEqual(r.children[0].sharedTo, []);
    assert.deepStrictEqual(r.shared, []);
});

ok('sharedTo 去重去空，正常归一', () => {
    const r = admin.normalizeParental({
        mode: 'on',
        children: [{ id: 'c1', name: '小薯', sharedTo: [' mama88 ', 'AA_parent', 'mama88', ''] }],
    });
    assert.deepStrictEqual(r.children[0].sharedTo, ['mama88', 'AA_parent']);
});

reject('sharedTo 元素非字符串 → 拒绝', () => admin.normalizeParental({
    mode: 'on', children: [{ id: 'c1', name: 'x', sharedTo: [123] }],
}), 'sharedTo 的元素必须是字符串');

ok('parental.shared 坐标归一（补 refId、去重）', () => {
    const r = admin.normalizeParental({
        mode: 'on', children: [],
        shared: [
            { owner: 'mama88', machineId: 'tvA', childId: 'c1' },
            { owner: 'mama88', machineId: 'tvA', childId: 'c1' },
            { owner: 'papa', machineId: 'tvB', childId: 'c2', refId: 'custom', createdAt: 123 },
        ],
    });
    assert.strictEqual(r.shared.length, 2);
    assert.strictEqual(r.shared[0].refId, 'tvA:c1');
    assert.strictEqual(r.shared[1].refId, 'custom');
    assert.strictEqual(r.shared[1].createdAt, 123);
});

reject('shared 缺 owner → 拒绝', () => admin.normalizeParental({
    mode: 'on', children: [], shared: [{ machineId: 'tvA', childId: 'c1' }],
}), 'owner');

reject('shared 超过上限 → 拒绝', () => admin.normalizeParental({
    mode: 'on', children: [],
    shared: new Array(share.MAX_SHARED_REFS + 1).fill(0).map((_, i) => ({ owner: 'p', machineId: 'm', childId: 'c' + i })),
}), '最多');

// ---------- 2. 夹具：客厅(主本) + 卧室(引用) ----------
function machines() {
    return {
        tvLiving: {
            id: 'tvLiving', name: '客厅电视', commApp: 'screen.potatokid.tools',
            commAccount: 'tv.tv.1111111111111111', parents: ['papa'],
            parental: {
                mode: 'on', shared: [],
                children: [
                    { id: 'c1', name: '逗逗', dailyLimitMin: 60, sharedTo: ['mama'] },
                    { id: 'c2', name: '果果', dailyLimitMin: 30, sharedTo: ['grandpa'] },
                    { id: 'c3', name: '小宝', dailyLimitMin: 45, sharedTo: [] },
                    { id: 'c4', name: '乐乐', dailyLimitMin: 25, sharedTo: ['mama'] },
                ],
            },
        },
        tvBed: {
            id: 'tvBed', name: '卧室电视', commApp: 'screen.potatokid.tools',
            commAccount: 'tv.tv.2222222222222222', parents: ['mama'],
            parental: {
                mode: 'on',
                children: [{ id: 'c9', name: '妈妈自建', dailyLimitMin: 20, sharedTo: [] }],
                shared: [
                    { refId: 'tvLiving:c1', owner: 'papa', machineId: 'tvLiving', childId: 'c1', createdAt: 1 },
                    { refId: 'tvLiving:c2', owner: 'papa', machineId: 'tvLiving', childId: 'c2', createdAt: 2 },
                    { refId: 'tvGone:c7', owner: 'old', machineId: 'tvGone', childId: 'c7', createdAt: 3 },
                ],
            },
        },
    };
}

// ---------- 3. resolveChild 三态 ----------
ok('本台主本 → master 可读写', () => {
    const m = machines();
    const r = share.resolveChild(m.tvBed, m, 'c9', 'mama');
    assert.strictEqual(r.kind, 'master');
    assert.strictEqual(r.child.name, '妈妈自建');
});

ok('引用且 viewer 在 sharedTo → shared 只读，含主本内容', () => {
    const m = machines();
    // 客厅逗逗 sharedTo=['mama']，卧室 viewer=mama 可见
    const r = share.resolveChild(m.tvBed, m, 'c1', 'mama');
    assert.strictEqual(r.kind, 'shared');
    assert.strictEqual(r.child.name, '逗逗');
    assert.strictEqual(r.source.id, 'tvLiving');
});

ok('引用但 viewer 不在 sharedTo → broken（not-shared-to-viewer）', () => {
    const m = machines();
    // 客厅果果 sharedTo=['grandpa']，卧室 viewer=mama 不在名单
    const r = share.resolveChild(m.tvBed, m, 'c2', 'mama');
    assert.strictEqual(r.kind, 'broken');
    assert.strictEqual(r.reason, 'not-shared-to-viewer');
});

ok('同一家长号名下电视的引用：sharedTo 为空也应展开 shared（非 broken）', () => {
    // 回归线上 bug：m10s 引用糖果电视（parents 含 m10s、sharedTo=[]），
    // 写入与候选都按 same-account 放行，但旧 resolveRef 只认 sharedTo 导致误判 broken。
    const m = machines();
    m.tvBed.parents = ['mama', 'papa'];            // 卧室也归 papa，来源客厅的绑定家长是 papa
    m.tvLiving.parental.children.push({ id: 'c5', name: '同号档案', dailyLimitMin: 15, sharedTo: [] });
    m.tvBed.parental.shared.push({ refId: 'tvLiving:c5', owner: 'papa', machineId: 'tvLiving', childId: 'c5', createdAt: 4 });
    const r = share.resolveChild(m.tvBed, m, 'c5', 'papa');
    assert.strictEqual(r.kind, 'shared', 'same-account 引用应展开 shared');
    assert.strictEqual(r.child.name, '同号档案');
    const v = share.buildShareView(m.tvBed, m, 'papa');
    assert.strictEqual(v.imported.find((x) => x.id === 'c5').status, 'ok');
});

ok('来源电视不存在 → broken（machine-missing）', () => {
    const m = machines();
    const r = share.resolveChild(m.tvBed, m, 'c7', 'mama');
    assert.strictEqual(r.kind, 'broken');
    assert.strictEqual(r.reason, 'machine-missing');
});

ok('来源档案被删 → broken（child-missing）', () => {
    const m = machines();
    m.tvLiving.parental.children = m.tvLiving.parental.children.filter((c) => c.id !== 'c1');
    const r = share.resolveChild(m.tvBed, m, 'c1', 'mama');
    assert.strictEqual(r.kind, 'broken');
    assert.strictEqual(r.reason, 'child-missing');
});

ok('来源家长解绑 → broken（owner-unbound）', () => {
    const m = machines();
    m.tvLiving.parents = ['someone-else'];
    const r = share.resolveChild(m.tvBed, m, 'c1', 'mama');
    assert.strictEqual(r.kind, 'broken');
    assert.strictEqual(r.reason, 'owner-unbound');
});

ok('既非本台档案也无引用 → missing', () => {
    const m = machines();
    const r = share.resolveChild(m.tvBed, m, 'nope', 'mama');
    assert.strictEqual(r.kind, 'missing');
});

ok('TV 内部展开（viewer 空）跳过 sharedTo 校验，只认主本存在', () => {
    const m = machines();
    const r = share.resolveChild(m.tvBed, m, 'c2', null);
    assert.strictEqual(r.kind, 'shared');
    assert.strictEqual(r.child.name, '果果');
});

// ---------- 4. buildShareView ----------
ok('共享视图：masters 标主本、imported 区分 ok/broken、candidates 按可见性', () => {
    const m = machines();
    const v = share.buildShareView(m.tvBed, m, 'mama');
    // 本台主本
    assert.strictEqual(v.masters.length, 1);
    assert.strictEqual(v.masters[0].isMaster, true);
    // 已引用：c1 ok（mama 在逗逗白名单），c2 broken（不在果果白名单），c7 broken（机器没了）
    const c1 = v.imported.find((x) => x.id === 'c1');
    const c2 = v.imported.find((x) => x.id === 'c2');
    const c7 = v.imported.find((x) => x.id === 'c7');
    assert.strictEqual(c1.status, 'ok');
    assert.strictEqual(c1.readOnly, true);
    assert.strictEqual(c1.source.machineName, '客厅电视');
    assert.strictEqual(c2.status, 'broken');
    assert.strictEqual(c7.status, 'broken');
    // 候选：客厅乐乐(sharedTo mama，未引用) 应出现 via shared-to-me；
    // 逗逗虽 share 给 mama 但已引用→排除；果果(grandpa)/小宝(空) 不出现。
    const names = v.candidates.map((c) => c.name);
    assert.ok(names.includes('乐乐'), '乐乐应作为可引用候选（分享给 mama 且未引用）');
    assert.ok(!names.includes('逗逗'), '逗逗已引用，不应重复出现在候选');
    assert.ok(!names.includes('果果'), '果果只分享给 grandpa，不应出现');
    assert.ok(!names.includes('小宝'), '小宝未分享，不应出现');
    assert.strictEqual(v.candidates.find((c) => c.name === '乐乐').via, 'shared-to-me');
});

ok('同一家长号名下其它电视档案默认可见（same-account），已引用仍排除', () => {
    const m = machines();
    m.tvBed.parents = ['papa']; // 卧室也归 papa
    const v = share.buildShareView(m.tvBed, m, 'papa');
    const cand = v.candidates.filter((c) => c.via === 'same-account');
    // 客厅 4 个档案，剔除已引用的 c1(逗逗)/c2(果果)，剩小宝/乐乐 2 个同账号候选。
    assert.strictEqual(cand.length, 2, '同账号候选=客厅档案减去已引用');
    assert.ok(cand.some((c) => c.name === '小宝'));
    assert.ok(cand.some((c) => c.name === '乐乐'));
    assert.ok(!cand.some((c) => c.name === '逗逗'), '已引用不重复列候选');
    // 自己台档案不作为候选
    assert.ok(!cand.some((c) => c.machineId === 'tvBed'));
});

ok('已引用的档案不再出现在候选（去重）', () => {
    const m = machines();
    const v = share.buildShareView(m.tvBed, m, 'mama');
    assert.ok(!v.candidates.some((c) => c.machineId === 'tvLiving' && c.childId === 'c1'));
});

// ---------- 5. resolveQuizTarget 题库落点 ----------
ok('主本档案题库落点=本台，可写', () => {
    const m = machines();
    const t = share.resolveQuizTarget(m.tvBed, m, 'c9', 'mama');
    assert.strictEqual(t.ok, true);
    assert.strictEqual(t.deviceIdForLookup, 'tvBed');
    assert.strictEqual(t.readOnly, false);
});

ok('引用档案题库落点=来源电视，只读', () => {
    const m = machines();
    const t = share.resolveQuizTarget(m.tvBed, m, 'c1', 'mama');
    assert.strictEqual(t.ok, true);
    assert.strictEqual(t.deviceIdForLookup, 'tvLiving');
    assert.strictEqual(t.childIdForLookup, 'c1');
    assert.strictEqual(t.readOnly, true);
});

ok('broken 引用题库读取被拒', () => {
    const m = machines();
    const t = share.resolveQuizTarget(m.tvBed, m, 'c7', 'mama');
    assert.strictEqual(t.ok, false);
    assert.ok(String(t.reason).includes('失效'));
});

// ---------- 6. durationAnchorKey 时长归并 ----------
ok('本台档案时长 key=本台坐标', () => {
    const m = machines();
    assert.strictEqual(share.durationAnchorKey(m.tvBed, m, 'c9'), 'tvBed:c9');
});

ok('引用档案时长归到主本坐标（跨电视合并）', () => {
    const m = machines();
    // 卧室引用客厅逗逗(c1) → 归到 tvLiving:c1，与客厅看逗逗同一 key
    assert.strictEqual(share.durationAnchorKey(m.tvBed, m, 'c1'), 'tvLiving:c1');
    assert.strictEqual(share.durationAnchorKey(m.tvLiving, m, 'c1'), 'tvLiving:c1');
});

ok('broken 引用时长回落本台坐标（不丢数据）', () => {
    const m = machines();
    assert.strictEqual(share.durationAnchorKey(m.tvBed, m, 'c7'), 'tvBed:c7');
});

console.log(`[parental-share] 通过 ${passed} 项`);
