'use strict';

const path = require('path');
const fs = require('fs');
const express = require('express');
const cookieParser = require('cookie-parser');
const {
  ApiError,
  ok,
  wrap,
  clientIp,
  securityHeaders,
  csrfGuard,
  handleError,
} = require('./apiutil');
const {
  COOKIE_NAME,
  VIEWER_COOKIE,
  scryptVerify,
  scryptHash,
  validatePassword,
  LoginLimiter,
  cookieOptions,
} = require('./security');
const { createAppsRouter } = require('./apps');
const { createReleasesRouter } = require('./releases');
const { maintenanceStatus, runCleanup } = require('./cleanup');
const { createAccountsRouter, tokenLogin, setAccountCookie } = require('./accounts');
const { createFilesAdminRouter } = require('./files');
const { createRelayRouter } = require('./relay');
const { authenticate, requireAccountRole, requireRole } = require('./auth');
const { issueSession } = require('./security');
const { nowIso } = require('./store');

const OPEN_AFTER_LOGIN = ['/api/admin/me', '/api/admin/logout', '/api/admin/password', '/api/admin/sessions/revoke'];

function permissionPayload(principal) {
  if (!principal) return { accounts: false, apps: false, files: false };
  if (principal.type === 'viewer') {
    return {
      accounts: false,
      apps: principal.scopes.includes('apps:read'),
      files: principal.scopes.includes('files:read'),
    };
  }
  return {
    accounts: principal.roles.includes('admin'),
    apps: principal.roles.includes('apps') || principal.roles.includes('admin'),
    files: principal.roles.includes('files') || principal.roles.includes('admin'),
  };
}

// 按路径分组鉴权：/accounts、/tokens 只允许 admin 账号；/files 允许 files 或 admin；其余应用相关要求 apps。
function guardByPath(req, res, next) {
  // 挂载在 '/api/admin' 上，req.path 已去掉前缀，必须用 originalUrl 判断完整路径。
  const url = req.originalUrl.split('?')[0];
  if (OPEN_AFTER_LOGIN.includes(url)) return next();
  if (url.startsWith('/api/admin/relay')) return requireAccountRole('admin')(req, res, next);
  if (url.startsWith('/api/admin/accounts') || url.startsWith('/api/admin/tokens')) {
    return requireAccountRole('admin')(req, res, next);
  }
  if (url.startsWith('/api/admin/files')) return requireRole('files')(req, res, next);
  return requireRole('apps')(req, res, next);
}

function createAdminRouter({ config, store, audit, secret, uploads }) {
  const router = express.Router();
  const limiter = new LoginLimiter({
    ipLimit: 5,
    ipWindowMs: 15 * 60 * 1000,
    accountLimit: 10,
    accountWindowMs: 60 * 60 * 1000,
    lockMs: (Number(config.admin.lockMinutes) || 30) * 60 * 1000,
  });

  router.use(securityHeaders);
  router.use((req, res, next) => {
    req.clientIp = clientIp(req);
    next();
  });

  router.post(
    '/api/admin/login',
    wrap(async (req, res) => {
      const body = req.body || {};
      const username = typeof body.username === 'string' ? body.username.trim() : '';
      const password = typeof body.password === 'string' ? body.password : '';
      if (!username || !password || username.length > 64 || password.length > 128) {
        throw new ApiError(400, 400005, '用户名或密码参数不合法');
      }

      const ip = req.clientIp;
      const lock = limiter.status({ ip, username });
      if (lock.locked) {
        await audit.log({
          actor: username,
          ip,
          action: 'login_blocked',
          target: username,
          before: null,
          after: { reason: 'locked', retryAfterSec: lock.retryAfterSec },
        });
        throw new ApiError(429, 400002, `登录失败次数过多，请 ${Math.ceil(lock.retryAfterSec / 60)} 分钟后再试`);
      }

      const account = store.findAccount(username);
      const valid = Boolean(account) && !account.disabled && scryptVerify(password, account.passwordHash);
      if (!valid) {
        const state = limiter.fail({ ip, username });
        await audit.log({
          actor: username,
          ip,
          action: 'login_fail',
          target: username,
          before: null,
          after: { locked: state.locked },
        });
        if (state.locked) {
          throw new ApiError(429, 400002, '登录失败次数过多，账号或 IP 已锁定 30 分钟');
        }
        throw new ApiError(401, 400001, '用户名或密码错误');
      }

      limiter.success({ ip, username });
      const session = await store.mutate(() => {
        const sessionValue = issueSession(account, config);
        account.lastLoginAt = nowIso();
        account.updatedAt = nowIso();
        return sessionValue;
      });
      setAccountCookie(res, config, account, session, secret);

      await audit.log({
        actor: username,
        ip,
        action: 'login_success',
        target: username,
        before: null,
        after: { sessionId: session.sid, expiresAt: session.expiresAt, roles: account.roles },
      });

      ok(res, {
        name: username,
        username,
        role: 'admin',
        roles: [...account.roles],
        permissions: permissionPayload({ type: 'account', roles: account.roles }),
        expiresAt: session.expiresAt,
        mustChangePassword: Boolean(account.mustChangePassword),
      });
    })
  );

  // 临时口令登录（仅写只读 viewer 会话）：同样要求 X-Admin-Request 防 CSRF。
  router.post('/api/admin/token-login', csrfGuard, tokenLogin({ config, store, audit, secret }));

  router.post(
    '/api/admin/logout',
    wrap(async (req, res) => {
      res.clearCookie(COOKIE_NAME, cookieOptions(config));
      res.clearCookie(VIEWER_COOKIE, cookieOptions(config));
      await audit.log({
        actor: 'anonymous',
        ip: req.clientIp,
        action: 'logout',
        target: 'session',
        before: null,
        after: null,
      });
      ok(res, { loggedOut: true }, '已退出登录');
    })
  );

  // 以下全部需要有效会话（账号或临时口令）。
  router.use('/api/admin', authenticate({ store, secret }));

  router.use(
    '/api/admin',
    wrap((req, res, next) => {
      const p = req.principal;
      if (!p) throw new ApiError(401, 400001, '未登录或会话已过期');
      const url = req.originalUrl.split('?')[0];
      if (p.type === 'account' && p.mustChangePassword && !OPEN_AFTER_LOGIN.includes(url)) {
        throw new ApiError(403, 400010, '首次登录请先修改初始密码');
      }
      next();
    })
  );

  router.use('/api/admin', csrfGuard);
  router.use('/api/admin', guardByPath);

  router.get(
    '/api/admin/me',
    wrap((req, res) => {
      const p = req.principal;
      ok(res, {
        type: p.type,
        name: p.type === 'account' ? p.username : `临时口令 ${p.tokenId}`,
        username: p.type === 'account' ? p.username : null,
        role: p.type === 'account' && p.roles.includes('admin') ? 'admin' : p.type,
        roles: p.type === 'account' ? [...p.roles] : [],
        scopes: p.type === 'viewer' ? [...p.scopes] : [],
        permissions: permissionPayload(p),
        readOnly: p.type === 'viewer',
        expiresAt: p.expiresAt,
        mustChangePassword: Boolean(p.mustChangePassword),
      });
    })
  );

  router.put(
    '/api/admin/password',
    wrap(async (req, res) => {
      if (req.principal.type !== 'account') throw new ApiError(403, 400011, '临时口令不能修改密码');
      const body = req.body || {};
      const currentPassword = typeof body.currentPassword === 'string' ? body.currentPassword : '';
      const newPassword = typeof body.newPassword === 'string' ? body.newPassword : '';
      const account = store.findAccount(req.principal.username);
      if (!account) throw new ApiError(401, 400001, '账号不存在');

      if (!scryptVerify(currentPassword, account.passwordHash)) {
        throw new ApiError(401, 400001, '当前密码不正确');
      }
      const reason = validatePassword(newPassword, account.username, config.password);
      if (reason) throw new ApiError(200, 400005, reason);
      if (newPassword === currentPassword) throw new ApiError(200, 400005, '新密码不能与当前密码相同');

      await store.mutate(() => {
        account.passwordHash = scryptHash(newPassword);
        account.mustChangePassword = false;
        account.authEpoch = Number(account.authEpoch) + 1;
        account.sessionId = null;
        account.sessionIssuedAt = null;
        account.sessionExpiresAt = null;
        account.updatedAt = nowIso();
      });
      res.clearCookie(COOKIE_NAME, cookieOptions(config));
      // 初始密码文件已完成使命，改密成功后立即删除。
      try {
        fs.unlinkSync(path.join(config.dataDir, 'initial_admin_password.txt'));
      } catch (_) {
        /* 文件可能已不存在 */
      }
      await audit.log({
        actor: req.principal.username,
        ip: req.clientIp,
        action: 'password_change',
        target: req.principal.username,
        before: { mustChangePassword: true },
        after: { mustChangePassword: false, allSessionsRevoked: true },
      });
      ok(res, { mustReLogin: true }, '密码已更新，所有会话已失效，请重新登录');
    })
  );

  router.post(
    '/api/admin/sessions/revoke',
    wrap(async (req, res) => {
      if (req.principal.type !== 'account') throw new ApiError(403, 400011, '临时口令不能执行该操作');
      const account = store.findAccount(req.principal.username);
      await store.mutate(() => {
        account.authEpoch = Number(account.authEpoch) + 1;
        account.sessionId = null;
        account.sessionIssuedAt = null;
        account.sessionExpiresAt = null;
        account.updatedAt = nowIso();
      });
      res.clearCookie(COOKIE_NAME, cookieOptions(config));
      await audit.log({
        actor: req.principal.username,
        ip: req.clientIp,
        action: 'sessions_revoke',
        target: req.principal.username,
        before: { sessionId: req.principal.sessionId },
        after: { authEpoch: account.authEpoch },
      });
      ok(res, { mustReLogin: true }, '已强制下线全部会话');
    })
  );

  // relay 运维（仅 admin 角色）：status / logs / start / stop / restart。
  router.use('/api/admin', createRelayRouter({ audit }));

  // 账号管理 + 临时口令（仅 admin 角色）。
  router.use('/api/admin', createAccountsRouter({ config, store, audit, secret }));

  // 维护：状态查询 + 手动清理（默认 dryRun）；自动清理由 cleanup.js 每小时执行。
  router.get(
    '/api/admin/maintenance/status',
    wrap((req, res) => {
      ok(res, maintenanceStatus({ config, store }));
    })
  );

  router.post(
    '/api/admin/maintenance/cleanup',
    wrap(async (req, res) => {
      const body = req.body || {};
      const dryRun = body.dryRun === undefined ? true : Boolean(body.dryRun);
      const result = await runCleanup({
        config,
        store,
        audit,
        actor: req.admin.username,
        ip: req.clientIp,
        dryRun,
        targetFreeBytes: body.targetFreeBytes,
        reason: 'manual',
      });
      ok(res, result, dryRun ? '预演完成（未删除任何文件）' : '清理完成');
    })
  );

  if (uploads) router.use('/api/admin/uploads', uploads.router());
  router.use('/api/admin', createReleasesRouter({ config, store, audit, secret }));
  router.use('/api/admin', createAppsRouter({ store, audit }));

  // 文件镜像管理（files 角色）。
  router.use('/api/admin', createFilesAdminRouter({ config, store, audit }));

  return router;
}

function webDir(config) {
  const candidates = [path.join(config.root, 'build', 'web'), path.join(__dirname, '..', 'web')];
  return candidates.find((candidate) => fs.existsSync(candidate)) || candidates[0];
}

function createAdminApp({ config, store, audit, secret, uploads }) {
  const app = express();
  if (config.trustProxy) app.set('trust proxy', true);
  app.disable('x-powered-by');
  app.use(express.json({ limit: '32kb' }));
  app.use(express.urlencoded({ extended: false, limit: '32kb' }));
  app.use(cookieParser());
  app.use('/static', express.static(webDir(config), { index: false, maxAge: '5m' }));
  app.use(createAdminRouter({ config, store, audit, secret, uploads }));

  const page = (name) => (req, res) => res.sendFile(path.join(webDir(config), name));
  app.get(['/admin', '/admin/'], page('admin.html'));
  app.get(['/apps', '/apps/'], page('apps.html'));
  app.get(['/files', '/files/'], page('files.html'));
  app.get('/', page('index.html'));
  app.get('/favicon.ico', (req, res) => res.status(204).end());

  app.use((req, res) => res.status(404).json({ code: 300000, msg: '接口不存在', data: null }));
  app.use(handleError);
  return app;
}

module.exports = { createAdminApp, createAdminRouter };
