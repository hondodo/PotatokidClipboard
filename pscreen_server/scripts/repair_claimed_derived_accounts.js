// 存量修复：把旧 claim 迁移时被「禁用成墓碑」的设备派生号恢复为可登录。
//
// 背景
// ----
// 旧版「设置登录名」会把派生号 parent.parent.<设备号> 整体迁移为家长号，
// 并把派生号口令改成随机值 + info.enabled=false（墓碑），防止默认口令复活。
// 这带来三个问题：实时通道被一起切成家长号、卸载重装即锁死、后端多一僵尸号。
//
// 新版已把「设备身份」与「家长身份」解耦（见 server/claims.js）：派生号
// 永不改名/禁用，实时通道恒用派生号 + 123456，家长号是独立账号。本脚本把
// **历史遗留的墓碑派生号**恢复到新模型，使旧用户升级后实时通道仍能登录。
//
// 脚本做什么（仅对命中的墓碑派生号）
// ----------------------------------
// 1. 派生号账号文件口令恢复为 MD5('123456')（默认口令，实时通道握手用）；
// 2. 派生号 _info.txt 去掉 enabled:false，清掉旧迁移标记 claimedAt/claimedTo，
//    写入 parentAccount = <它迁移到的家长号>（新模型的正向关联标记）；
// 3. 绝不改动家长号账号、machines.json 绑定关系、题库、事件历史。
//
// 用法
// ----
//   node scripts/repair_claimed_derived_accounts.js            # dry-run（默认，只打印不写）
//   node scripts/repair_claimed_derived_accounts.js --apply    # 实际执行（先自动备份）
//   node scripts/repair_claimed_derived_accounts.js --apply --datas /abs/path/to/datas
//
// 默认 datas 目录为 pscreen_server/datas（与 server.js 内 path.join(__dirname,'../datas') 一致）。
'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const args = process.argv.slice(2);
const apply = args.includes('--apply');
const datasArg = args.indexOf('--datas');
const datasDir = datasArg >= 0 && args[datasArg + 1]
    ? path.resolve(args[datasArg + 1])
    : path.resolve(__dirname, '..', 'datas');

const registerUsersDir = path.join(datasDir, 'register', 'users');
const DEFAULT_MD5 = crypto.createHash('md5').update('123456').digest('hex');
const DERIVED = /^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[0-9a-fA-F]{16}$/;

function readJson(file, fallback) {
    try {
        if (!fs.existsSync(file)) return fallback;
        return JSON.parse(fs.readFileSync(file, 'utf8'));
    } catch (_) {
        return fallback;
    }
}

function main() {
    console.log(`[repair] datas 目录: ${datasDir}`);
    console.log(`[repair] 模式: ${apply ? 'APPLY（会写入并备份）' : 'DRY-RUN（只预览，不写入）'}`);

    if (!fs.existsSync(registerUsersDir)) {
        console.error(`[repair] 账号目录不存在: ${registerUsersDir}`);
        process.exit(1);
    }

    const infoFiles = fs.readdirSync(registerUsersDir).filter((f) => f.endsWith('_info.txt'));
    const targets = [];
    for (const file of infoFiles) {
        const account = file.slice(0, -'_info.txt'.length);
        if (!DERIVED.test(account)) continue; // 只看设备派生号
        const info = readJson(path.join(registerUsersDir, file), null);
        if (!info || info.role !== 'parent') continue;
        // 命中墓碑：旧迁移标记存在，或曾被显式禁用。
        const tombstoned = info.claimedTo || info.claimedAt || info.enabled === false;
        if (!tombstoned) continue;
        const parentAccount = String(info.claimedTo || info.parentAccount || '').trim();
        targets.push({ account, info, parentAccount });
    }

    if (targets.length === 0) {
        console.log('[repair] 未发现需要修复的墓碑派生号，无需处理。');
        return;
    }

    console.log(`[repair] 发现 ${targets.length} 个待修复派生号：`);
    for (const t of targets) {
        console.log(`  - ${t.account} （原迁移到家长号: ${t.parentAccount || '未知'}）`);
        console.log(`      动作: 口令恢复 123456 · 去掉 enabled:false/墓碑标记`
            + `${t.parentAccount ? ` · 写 parentAccount=${t.parentAccount}` : ''}`);
    }

    if (!apply) {
        console.log('\n[repair] DRY-RUN 结束。确认无误后加 --apply 实际执行（会先备份）。');
        return;
    }

    const stamp = new Date().toISOString().replace(/[:.]/g, '-');
    const backupDir = path.join(datasDir, 'admin', 'repair-backups', stamp);
    fs.mkdirSync(backupDir, { recursive: true });

    for (const t of targets) {
        const pwdFile = path.join(registerUsersDir, t.account);
        const infoFile = path.join(registerUsersDir, `${t.account}_info.txt`);
        // 备份原始两个文件
        fs.copyFileSync(pwdFile, path.join(backupDir, t.account));
        fs.copyFileSync(infoFile, path.join(backupDir, `${t.account}_info.txt`));

        // 1. 派生号口令恢复为默认 123456（实时通道恒用）
        fs.writeFileSync(pwdFile, DEFAULT_MD5, 'utf8');

        // 2. info 去墓碑、写正向关联
        const info = Object.assign({}, t.info);
        delete info.enabled;
        delete info.claimedAt;
        delete info.claimedTo;
        if (t.parentAccount) info.parentAccount = t.parentAccount;
        fs.writeFileSync(infoFile, JSON.stringify(info, null, 2), 'utf8');
        console.log(`[repair] 已修复 ${t.account}`);
    }

    console.log(`\n[repair] 完成。备份目录: ${backupDir}`);
    console.log('[repair] 下一步：重启 pscreen_server 使账号文件变更生效；');
    console.log('        旧用户的家长端用「家长号 + 自设口令」登录管理端，');
    console.log('        实时通道会自动用恢复后的派生号 + 123456 连接。');
}

main();
