// 账号体系：datas/register/users/<账号> 存密码 MD5，HTTP 登录与 WebSocket 握手共用同一校验。
//
// - verifyAccount(account, md5Token)：账号文件存在且内容与 md5Token 一致才通过。
// - ensureAccount(account, md5Token)：账号不存在且 md5Token 等于默认口令的 MD5 时自动建档
//   （设备首次登录即开通），否则拒绝。
// - 默认口令 123456 仅用于自动建档；已存在的账号（如管理员 honghao）始终按各自原密码校验。
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// 自动建档口令：123456
const DEFAULT_PASSWORD_MD5 = crypto.createHash('md5').update('123456').digest('hex');

const ACCOUNT_PATTERN = /^[A-Za-z0-9_.:-]{1,64}$/;

function isValidAccount(account) {
    return typeof account === 'string' && ACCOUNT_PATTERN.test(account);
}

function md5Of(text) {
    return crypto.createHash('md5').update(String(text)).digest('hex');
}

/**
 * 用账号目录构造一组操作函数。
 * @param {string} registerUsersDir datas/register/users 目录
 */
function createAccountStore(registerUsersDir) {
    const userFile = (account) => path.join(registerUsersDir, account);
    const infoFile = (account) => path.join(registerUsersDir, `${account}_info.txt`);

    function exists(account) {
        return isValidAccount(account) && fs.existsSync(userFile(account));
    }

    /** 校验账号与 MD5 口令；返回 { ok, reason }，reason: not_exists | bad_password。 */
    function verify(account, md5Token) {
        if (!isValidAccount(account)) return { ok: false, reason: 'invalid_account' };
        if (!fs.existsSync(userFile(account))) return { ok: false, reason: 'not_exists' };
        let stored = '';
        try {
            stored = fs.readFileSync(userFile(account), 'utf8').trim();
        } catch (_) {
            return { ok: false, reason: 'not_exists' };
        }
        if (stored !== String(md5Token || '')) return { ok: false, reason: 'bad_password' };
        return { ok: true };
    }

    /** 建档（账号文件 + 信息文件 + 自增 id）；账号已存在时直接返回 false。 */
    function create(account, md5Token) {
        if (!isValidAccount(account) || fs.existsSync(userFile(account))) return false;
        fs.mkdirSync(registerUsersDir, { recursive: true });
        fs.writeFileSync(userFile(account), String(md5Token), 'utf8');

        const maxIdFilePath = path.join(registerUsersDir, 'max_id.txt');
        let maxId = 0;
        if (fs.existsSync(maxIdFilePath)) {
            const content = fs.readFileSync(maxIdFilePath, 'utf8').trim();
            maxId = parseInt(content) || 0;
        }
        const newUserId = maxId + 1;
        fs.writeFileSync(maxIdFilePath, String(newUserId), 'utf8');

        const userInfo = {
            id: newUserId,
            name: account,
            createdAt: new Date().toISOString(),
        };
        fs.writeFileSync(infoFile(account), JSON.stringify(userInfo, null, 2), 'utf8');
        console.log(`账号自动开通: ${account} id=${newUserId}`);
        return true;
    }

    /**
     * 登录用：校验，不存在且口令为默认口令时自动建档后通过。
     * @returns {{ ok: boolean, reason?: string }}
     */
    function verifyOrProvision(account, md5Token) {
        const result = verify(account, md5Token);
        if (result.ok) return result;
        if (result.reason === 'not_exists' && String(md5Token) === DEFAULT_PASSWORD_MD5) {
            create(account, md5Token);
            return { ok: true };
        }
        return result;
    }

    function readInfo(account) {
        if (!isValidAccount(account) || !fs.existsSync(infoFile(account))) return null;
        try {
            return JSON.parse(fs.readFileSync(infoFile(account), 'utf8'));
        } catch (_) {
            return null;
        }
    }

    function writeInfo(account, info) {
        fs.writeFileSync(infoFile(account), JSON.stringify(info, null, 2), 'utf8');
    }

    return { exists, verify, verifyOrProvision, create, readInfo, writeInfo };
}

module.exports = { createAccountStore, isValidAccount, md5Of, DEFAULT_PASSWORD_MD5, ACCOUNT_PATTERN };
