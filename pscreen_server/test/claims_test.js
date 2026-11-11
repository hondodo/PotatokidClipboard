// node test/claims_test.js
// 家长自定义登录名：名称校验 + 账号改名迁移 + ticket 一次性核销。
'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const claims = require('../server/claims');

let passed = 0;
function ok(name, fn) {
    try {
        fn();
        passed++;
        console.log(`✓ ${name}`);
    } catch (error) {
        console.error(`✗ ${name}`);
        console.error(error);
        process.exit(1);
    }
}

function readJson(file) {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function writeJson(file, value) {
    fs.mkdirSync(path.dirname(file), { recursive: true });
    fs.writeFileSync(file, JSON.stringify(value, null, 2), 'utf8');
}

const OLD = 'parent.parent.65e60b477c6a676f';
const NEW = 'mama_01';
const DEFAULT_MD5 = 'e10adc3949ba59abbe56e057f20f883e';
const NEW_MD5 = 'b'.repeat(32);

function makeFixture() {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), 'pk_claim_test_'));
    const usersDir = path.join(root, 'register', 'users');
    const adminDir = path.join(root, 'admin');
    const realtimeDir = path.join(root, 'realtime');
    fs.mkdirSync(usersDir, { recursive: true });
    fs.mkdirSync(adminDir, { recursive: true });
    fs.mkdirSync(path.join(realtimeDir, 'outbox'), { recursive: true });
    fs.mkdirSync(path.join(realtimeDir, 'reads'), { recursive: true });

    fs.writeFileSync(path.join(usersDir, OLD), 'e10adc3949ba59abbe56e057f20f883e', 'utf8');
    writeJson(path.join(usersDir, `${OLD}_info.txt`), {
        id: 42, name: OLD, role: 'parent', createdAt: '2026-01-01T00:00:00.000Z',
        displayName: '妈妈',
    });

    writeJson(path.join(adminDir, 'machines.json'), {
        android_tv01: {
            id: 'android_tv01', kind: 'tv', name: '客厅电视',
            owner: OLD,
            parents: [OLD, 'parent.parent.1111111111111111'],
            commAccount: 'tv.tv.65e60b477c6a676f',
            aliases: { [OLD]: '客厅', 'parent.parent.1111111111111111': '卧室' },
            parental: { mode: 'on', ownerAccount: OLD, unlockMode: 'remote', children: [] },
        },
        android_parent01: {
            id: 'android_parent01', kind: 'parent', name: '家长手机',
            commAccount: OLD, parents: [],
        },
    });
    writeJson(path.join(adminDir, 'layouts.json'), {
        [OLD]: { all: ['a', 'b'], updatedAt: 1 },
        device_android_tv01: { all: ['c'], updatedAt: 2 },
    });
    writeJson(path.join(adminDir, 'parental_avatars.json'), {
        android_tv01: [{ id: 'av1', uploadedBy: OLD, childIds: ['c1'] }],
    });
    writeJson(path.join(adminDir, 'parental_quizzes.json'), {
        android_tv01: { c1: { updatedAt: 1, questions: [] } },
    });

    fs.writeFileSync(
        path.join(realtimeDir, 'events.jsonl'),
        [
            JSON.stringify({ type: 'parental_watch', from: 'tv.tv.65e60b477c6a676f', to: 'tv.tv.x', audience: [OLD], data: { actor: OLD } }),
            JSON.stringify({ type: 'parental_unlock_request', from: 'tv.tv.65e60b477c6a676f', audience: [OLD] }),
            '{ this line is broken',
        ].join('\n') + '\n',
        'utf8',
    );
    fs.writeFileSync(
        path.join(realtimeDir, 'history.jsonl'),
        JSON.stringify({ from: OLD, to: 'tv.tv.65e60b477c6a676f', body: '{}' }) + '\n',
        'utf8',
    );
    writeJson(path.join(realtimeDir, 'outbox', `${OLD}.json`), [{ id: 1 }]);
    writeJson(path.join(realtimeDir, 'reads', `${OLD}.json`), { cursor: 7 });

    const userDir = path.join(root, 'users', OLD);
    fs.mkdirSync(userDir, { recursive: true });
    writeJson(path.join(userDir, 'remote_sessions.json'), {
        updatedAt: 1, items: [{ account: OLD, alias: '客厅' }],
    });
    fs.writeFileSync(path.join(userDir, 'clipboard_test.txt'), 'hello', 'utf8');

    return { root, usersDir, adminDir, realtimeDir };
}

ok('合法登录名通过校验', () => {
    assert.strictEqual(claims.validateClaimName('mama_01').ok, true);
    assert.strictEqual(claims.validateClaimName('  Mama.01  ').name, 'Mama.01');
    assert.strictEqual(claims.validateClaimName('a-b_c.d').ok, true);
});

ok('拒绝中文、冒号、过短、隐藏名与保留前缀', () => {
    assert.strictEqual(claims.validateClaimName('妈妈').ok, false);
    assert.strictEqual(claims.validateClaimName('mama:01').ok, false);
    assert.strictEqual(claims.validateClaimName('a').ok, false);
    assert.strictEqual(claims.validateClaimName('.hidden').ok, false);
    assert.strictEqual(claims.validateClaimName('..').ok, false);
    assert.strictEqual(claims.validateClaimName('parent.my.phone').ok, false);
    assert.strictEqual(claims.validateClaimName('tv.home').ok, false);
});

ok('拒绝设备派生格式与占用名', () => {
    assert.strictEqual(claims.validateClaimName(OLD).ok, false);
    assert.strictEqual(claims.validateClaimName('honghao', { adminUsername: 'honghao' }).ok, false);
    assert.strictEqual(claims.validateClaimName('taken', { accountExists: () => true }).ok, false);
    assert.strictEqual(claims.isDerivedAccount(OLD), true);
    assert.strictEqual(claims.isDerivedAccount('tv.tv.65e60b477c6a676f'), true);
    assert.strictEqual(claims.isDerivedAccount('mama_01'), false);
});

ok('renameMapKeys 在新旧 key 并存时保留新值', () => {
    const result = claims.renameMapKeys({ [OLD]: '旧别名', [NEW]: '新别名' }, OLD, NEW);
    assert.deepStrictEqual(result, { [NEW]: '新别名' });
});

ok('改名迁移覆盖全部账号引用，并保留题库按设备存储', () => {
    const fx = makeFixture();
    try {
        const result = claims.applyAccountRename({
            datasDir: fx.root, registerUsersDir: fx.usersDir,
            oldName: OLD, newName: NEW, newPasswordMd5: NEW_MD5,
        });
        assert.ok(result.backupDir && fs.existsSync(result.backupDir), '应生成备份目录');
        assert.ok(result.changed.length >= 5, `应报告多处改动: ${result.changed}`);

        // 账号本体：新名可登录、role 保留 parent；旧名保留但不可登录。
        const newInfo = readJson(path.join(fx.usersDir, `${NEW}_info.txt`));
        assert.strictEqual(newInfo.name, NEW);
        assert.strictEqual(newInfo.role, 'parent');
        assert.strictEqual(newInfo.id, 42);
        assert.strictEqual(newInfo.claimFrom, OLD);
        assert.ok(newInfo.claimedAt);
        assert.strictEqual(
            fs.readFileSync(path.join(fx.usersDir, NEW), 'utf8'),
            NEW_MD5,
            '可猜的自定义登录名必须换成不可猜的新口令',
        );
        assert.notStrictEqual(
            fs.readFileSync(path.join(fx.usersDir, NEW), 'utf8'),
            DEFAULT_MD5,
            '绝不能沿用设备自举的默认口令',
        );
        assert.notStrictEqual(
            fs.readFileSync(path.join(fx.usersDir, OLD), 'utf8'),
            DEFAULT_MD5,
            '旧账号口令必须失效，防止被默认口令复活',
        );
        assert.strictEqual(readJson(path.join(fx.usersDir, `${OLD}_info.txt`)).enabled, false);

        // machines.json：parents / owner / commAccount / aliases key / ownerAccount。
        const machines = readJson(path.join(fx.adminDir, 'machines.json'));
        const tv = machines.android_tv01;
        assert.deepStrictEqual(tv.parents, [NEW, 'parent.parent.1111111111111111']);
        assert.strictEqual(tv.owner, NEW);
        assert.strictEqual(tv.parental.ownerAccount, NEW);
        assert.strictEqual(tv.aliases[NEW], '客厅');
        assert.strictEqual(tv.aliases[OLD], undefined);
        assert.strictEqual(machines.android_parent01.commAccount, NEW);

        const layouts = readJson(path.join(fx.adminDir, 'layouts.json'));
        assert.deepStrictEqual(layouts[NEW].all, ['a', 'b']);
        assert.strictEqual(layouts[OLD], undefined);
        assert.deepStrictEqual(layouts.device_android_tv01.all, ['c']);

        assert.strictEqual(
            readJson(path.join(fx.adminDir, 'parental_avatars.json')).android_tv01[0].uploadedBy,
            NEW,
        );
        assert.deepStrictEqual(
            readJson(path.join(fx.adminDir, 'parental_quizzes.json')),
            { android_tv01: { c1: { updatedAt: 1, questions: [] } } },
            '题库按 deviceId 存储，不应被改名改动',
        );

        // realtime：JSONL 保留坏行、保持末尾换行、替换 audience / actor。
        const eventsRaw = fs.readFileSync(path.join(fx.realtimeDir, 'events.jsonl'), 'utf8');
        assert.ok(eventsRaw.endsWith('\n'));
        assert.ok(!eventsRaw.endsWith('\n\n'), '不应产生多余空行');
        assert.ok(eventsRaw.includes('{ this line is broken'), '坏行应原样保留');
        const first = JSON.parse(eventsRaw.split('\n')[0]);
        assert.deepStrictEqual(first.audience, [NEW]);
        assert.strictEqual(first.data.actor, NEW);
        assert.strictEqual(first.from, 'tv.tv.65e60b477c6a676f', '设备账号不能改');
        assert.strictEqual(JSON.parse(fs.readFileSync(path.join(fx.realtimeDir, 'history.jsonl'), 'utf8').trim()).from, NEW);

        assert.ok(fs.existsSync(path.join(fx.realtimeDir, 'outbox', `${NEW}.json`)));
        assert.ok(fs.existsSync(path.join(fx.realtimeDir, 'reads', `${NEW}.json`)));
        assert.ok(!fs.existsSync(path.join(fx.realtimeDir, 'outbox', `${OLD}.json`)));

        const newUserDir = path.join(fx.root, 'users', NEW);
        assert.strictEqual(fs.readFileSync(path.join(newUserDir, 'clipboard_test.txt'), 'utf8'), 'hello');
        assert.strictEqual(
            readJson(path.join(newUserDir, 'remote_sessions.json')).items[0].account, NEW,
        );

        // 重复改名必须被拒绝（幂等保护）。
        assert.throws(() => claims.applyAccountRename({
            datasDir: fx.root, registerUsersDir: fx.usersDir,
            oldName: OLD, newName: 'another', newPasswordMd5: NEW_MD5,
        }), /已迁移过登录名/);
    } finally {
        fs.rmSync(fx.root, { recursive: true, force: true });
    }
});

ok('拒绝缺失新口令或沿用默认口令，且不留下半成品账号', () => {
    const fx = makeFixture();
    try {
        assert.throws(() => claims.applyAccountRename({
            datasDir: fx.root, registerUsersDir: fx.usersDir,
            oldName: OLD, newName: NEW,
        }), /新口令摘要无效/);
        assert.throws(() => claims.applyAccountRename({
            datasDir: fx.root, registerUsersDir: fx.usersDir,
            oldName: OLD, newName: NEW, newPasswordMd5: DEFAULT_MD5,
        }), /不能沿用设备自举的默认口令/);
        assert.ok(!fs.existsSync(path.join(fx.usersDir, `${NEW}_info.txt`)),
            '校验失败时不能产生半成品账号');
    } finally {
        fs.rmSync(fx.root, { recursive: true, force: true });
    }
});

ok('ticket 只能核销一次，过期记录会被清理', () => {
    const fx = makeFixture();
    try {
        const file = path.join(fx.adminDir, 'claim_tickets.json');
        const now = Date.now();
        assert.strictEqual(claims.consumeTicket(file, 'jti-1', now, 1000), true);
        assert.strictEqual(claims.consumeTicket(file, 'jti-1', now, 1000), false);
        assert.strictEqual(claims.consumeTicket(file, 'jti-2', now + 5000, 1000), true);
        const stored = claims.readConsumedTickets(file);
        assert.ok(stored['jti-2']);
        assert.strictEqual(stored['jti-1'], undefined, '过期 jti 应被清理');
    } finally {
        fs.rmSync(fx.root, { recursive: true, force: true });
    }
});

console.log(`\nclaims_test.js: ${passed} 项通过`);
