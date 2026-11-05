'use strict';

const crypto = require('crypto');
const express = require('express');

const { ApiError, ok, wrap } = require('./apiutil');
const {
  COOKIE_NAME,
  VIEWER_COOKIE,
  scryptHash,
  scryptVerify,
  validatePassword,
  signCookie,
  cookieOptions,
  viewerPayload,
  generateAccessToken,
  sessionPayload,
} = require('./security');
const { nowIso } = require('./store');

const TOKEN_SCOPES = ['files:read', 'apps:read'];
const MIN_TTL_MINUTES = 10;
const MAX_TTL_MINUTES = 7 * 24 * 60; // 7 天

function accountView(account) {
  return {
    username: account.username,
    roles: [...account.roles],
    disabled: Boolean(account.disabled),
    createdAt: account.createdAt,
    updatedAt: account.updatedAt,
    lastLoginAt: account.lastLoginAt,
    mustChangePassword: Boolean(account.mustChangePassword),
  };
}

function tokenView(record) {
  return {
    id: record.id,
    token: record.token,
    scopes: [...record.scope],
    expiresAt: new Date(Number(record.expiresAt)).toISOString(),
    singleUse: Boolean(record.singleUse),
    createdBy: record.createdBy,
    createdAt: record.createdAt,
    usedAt: record.usedAt,
    lastUsedAt: record.lastUsedAt,
    useCount: Number(record.useCount || 0),
    revokedAt: record.revokedAt,
    note: record.note || '',
  };
}

function normalizeScopes(input) {
  if (!Array.isArray(input) || !input.length) throw new ApiError(400, 400005, 'scopes 至少选择一项');
  const out = [];
  for (const raw of input) {
    const scope = String(raw || '').trim();
    if (!TOKEN_SCOPES.includes(scope)) throw new ApiError(400, 400005, `不支持的 scope：${raw}`);
    if (!out.includes(scope)) out.push(scope);
  }
  return out;
}

function findTokenByValue(store, value) {
  const raw = String(value || '');
  if (!raw) return null;
  for (const record of Object.values(store.data.tokens || {})) {
    const a = Buffer.from(String(record.token || ''));
    const b = Buffer.from(raw);
    if (a.length === b.length && crypto.timingSafeEqual(a, b)) return record;
  }
  return null;
}

// 临时口令登录：写被 viewer 会话 Cookie（TTL = 口令剩余时间），不产生账号会话。
function tokenLogin({ config, store, audit, secret }) {
  return wrap(async (req, res) => {
    const body = req.body || {};
    const value = typeof body.token === 'string' ? body.token.trim() : '';
    if (!value || value.length > 256) throw new ApiError(401, 400013, '临时口令无效或已过期');

    const record = findTokenByValue(store, value);
    if (!record || record.revokedAt || Number(record.expiresAt) <= Date.now()) {
      await audit.log({
        actor: 'anonymous',
        ip: req.clientIp,
        action: 'token_login_fail',
        target: value.slice(0, 8) + '…',
        before: null,
        after: null,
      });
      throw new ApiError(401, 400013, '临时口令无效、已过期或已被吊销');
    }
    if (record.singleUse && record.usedAt) {
      throw new ApiError(401, 400013, '该临时口令为一次性口令，已被使用');
    }

    const remainingMs = Number(record.expiresAt) - Date.now();
    const exp = Math.floor((Date.now() + remainingMs) / 1000);
    await store.mutate(() => store.markTokenUsed(record.id));
    const token = signCookie(viewerPayload(record.id, record.scope, exp), secret);
    res.cookie(VIEWER_COOKIE, token, {
      ...cookieOptions(config),
      maxAge: Math.max(60 * 1000, remainingMs),
    });

    await audit.log({
      actor: `token:${record.id}`,
      ip: req.clientIp,
      action: 'token_login',
      target: record.id,
      before: null,
      after: { scopes: record.scope, expiresAt: new Date(Number(record.expiresAt)).toISOString() },
    });

    ok(res, {
      scopes: [...record.scope],
      expiresAt: new Date(Number(record.expiresAt)).toISOString(),
      readOnly: true,
    }, '临时口令已生效（只读）');
  });
}

function createAccountsRouter({ config, store, audit, secret }) {
  const router = express.Router();

  router.get(
    '/accounts',
    wrap((req, res) => {
      ok(res, { items: store.listAccounts().map(accountView) });
    })
  );

  router.post(
    '/accounts',
    wrap(async (req, res) => {
      const body = req.body || {};
      const username = typeof body.username === 'string' ? body.username.trim() : '';
      const password = typeof body.password === 'string' ? body.password : '';
      const reason = validatePassword(password, username, config.password);
      if (reason) throw new ApiError(200, 400005, reason);
      const created = await store.mutate(() =>
        store.createAccount({ username, passwordHash: scryptHash(password), roles: body.roles })
      );
      await audit.log({
        actor: req.actor,
        ip: req.clientIp,
        action: 'account_create',
        target: created.username,
        before: null,
        after: { roles: created.roles },
      });
      ok(res, accountView(created), '账号已创建');
    })
  );

  router.put(
    '/accounts/:username',
    wrap(async (req, res) => {
      const username = req.params.username;
      const body = req.body || {};
      const before = store.findAccount(username);
      if (!before) throw new ApiError(404, 400014, '账号不存在');
      if (username === req.principal.username && Array.isArray(body.roles) && !body.roles.includes('admin')) {
        throw new ApiError(200, 400017, '不能移除自己的 admin 角色');
      }
      const updated = await store.mutate(() => {
        const account = store.findAccount(username);
        if (body.roles !== undefined) store.updateAccountRoles(username, body.roles);
        if (body.disabled !== undefined) {
          account.disabled = Boolean(body.disabled);
          account.authEpoch = Number(account.authEpoch || 1) + 1;
          account.sessionId = null;
          account.sessionIssuedAt = null;
          account.sessionExpiresAt = null;
          account.updatedAt = nowIso();
        }
        return account;
      });
      await audit.log({
        actor: req.actor,
        ip: req.clientIp,
        action: 'account_update',
        target: username,
        before: { roles: before.roles, disabled: before.disabled },
        after: { roles: updated.roles, disabled: updated.disabled },
      });
      ok(res, accountView(updated), '账号已更新');
    })
  );

  router.post(
    '/accounts/:username/password',
    wrap(async (req, res) => {
      const username = req.params.username;
      if (!store.findAccount(username)) throw new ApiError(404, 400014, '账号不存在');
      const body = req.body || {};
      const password = typeof body.newPassword === 'string' ? body.newPassword : '';
      const reason = validatePassword(password, username, config.password);
      if (reason) throw new ApiError(200, 400005, reason);
      await store.mutate(() => store.resetAccountPassword(username, scryptHash(password)));
      await audit.log({
        actor: req.actor,
        ip: req.clientIp,
        action: 'account_reset_password',
        target: username,
        before: null,
        after: { mustChangePassword: true, sessionsRevoked: true },
      });
      ok(res, { username, mustChangePassword: true }, '密码已重置，该账号下次登录需先改密');
    })
  );

  router.delete(
    '/accounts/:username',
    wrap(async (req, res) => {
      const username = req.params.username;
      if (username === req.principal.username) throw new ApiError(200, 400017, '不能删除当前登录的账号');
      await store.mutate(() => store.deleteAccount(username));
      await audit.log({
        actor: req.actor,
        ip: req.clientIp,
        action: 'account_delete',
        target: username,
        before: null,
        after: null,
      });
      ok(res, { username }, '账号已删除');
    })
  );

  // ---- 临时访问口令 ----
  router.get(
    '/tokens',
    wrap((req, res) => {
      ok(res, { items: store.listTokens().map(tokenView), scopes: TOKEN_SCOPES });
    })
  );

  router.post(
    '/tokens',
    wrap(async (req, res) => {
      const body = req.body || {};
      const scopes = normalizeScopes(body.scopes);
      const ttlMinutes = body.ttlMinutes === undefined ? 1440 : Number(body.ttlMinutes);
      if (!Number.isInteger(ttlMinutes) || ttlMinutes < MIN_TTL_MINUTES || ttlMinutes > MAX_TTL_MINUTES) {
        throw new ApiError(200, 400005, `ttlMinutes 需在 ${MIN_TTL_MINUTES}～${MAX_TTL_MINUTES} 之间`);
      }
      const note = typeof body.note === 'string' ? body.note.trim().slice(0, 200) : '';
      const record = {
        id: `tok_${Date.now().toString(36)}_${crypto.randomBytes(3).toString('hex')}`,
        token: generateAccessToken(),
        scope: scopes,
        expiresAt: Date.now() + ttlMinutes * 60 * 1000,
        createdAt: nowIso(),
        createdBy: req.actor,
        singleUse: Boolean(body.singleUse),
        usedAt: null,
        lastUsedAt: null,
        useCount: 0,
        revokedAt: null,
        note,
      };
      const created = await store.mutate(() => store.createTokenRecord(record));
      await audit.log({
        actor: req.actor,
        ip: req.clientIp,
        action: 'token_create',
        target: created.id,
        before: null,
        after: { scopes, ttlMinutes, singleUse: created.singleUse, expiresAt: new Date(created.expiresAt).toISOString() },
      });
      ok(
        res,
        {
          ...tokenView(created),
          links: scopes.map((scope) => ({
            scope,
            path: scope === 'files:read' ? `/files?token=${encodeURIComponent(created.token)}` : `/apps?token=${encodeURIComponent(created.token)}`,
          })),
        },
        '临时口令已生成'
      );
    })
  );

  router.delete(
    '/tokens/:id',
    wrap(async (req, res) => {
      const id = req.params.id;
      const before = store.getToken(id);
      if (!before) throw new ApiError(404, 400013, '口令不存在');
      await store.mutate(() => store.revokeToken(id));
      await audit.log({
        actor: req.actor,
        ip: req.clientIp,
        action: 'token_revoke',
        target: id,
        before: { revokedAt: before.revokedAt },
        after: { revokedAt: store.getToken(id).revokedAt },
      });
      ok(res, { id }, '口令已吊销');
    })
  );

  return router;
}

// 供 /api/admin/login 使用：签发账号会话 Cookie。
function setAccountCookie(res, config, account, session, secret) {
  const value = signCookie(sessionPayload(account, session), secret);
  const hours = Number(config.admin.sessionHours) || 12;
  res.cookie(COOKIE_NAME, value, { ...cookieOptions(config), maxAge: hours * 3600 * 1000 });
  return value;
}

module.exports = { createAccountsRouter, tokenLogin, setAccountCookie, TOKEN_SCOPES, accountView, tokenView };
