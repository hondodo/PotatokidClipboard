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
  freeBytes,
  dirSizeBytes,
  handleError,
} = require('./apiutil');
const {
  COOKIE_NAME,
  scryptVerify,
  scryptHash,
  validatePassword,
  LoginLimiter,
  signCookie,
  cookieOptions,
  issueSession,
  sessionPayload,
  readSession,
} = require('./security');
const { createAppsRouter } = require('./apps');
const { nowIso } = require('./store');

const CHANGE_PASSWORD_PREFIX = '/api/admin/password';
const ME_PREFIX = '/api/admin/me';
const LOGOUT_PREFIX = '/api/admin/logout';

function createAdminRouter({ config, store, audit, secret }) {
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

  // 登录不需要会话；其余 /api/admin/* 全部要求已登录。
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

      const admin = store.data.admin;
      const valid = Boolean(admin) && username === admin.username && scryptVerify(password, admin.passwordHash);
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
      const session = await store.mutate(() => issueSession(store.data, config));
      const token = signCookie(sessionPayload(store.data.admin, session), secret);
      const hours = Number(config.admin.sessionHours) || 12;
      res.cookie(COOKIE_NAME, token, { ...cookieOptions(config), maxAge: hours * 3600 * 1000 });

      await audit.log({
        actor: username,
        ip,
        action: 'login_success',
        target: username,
        before: null,
        after: { sessionId: session.sid, expiresAt: session.expiresAt },
      });

      ok(res, {
        name: username,
        role: 'admin',
        username,
        expiresAt: session.expiresAt,
        mustChangePassword: Boolean(store.data.admin.mustChangePassword),
      });
    })
  );

  router.post(
    '/api/admin/logout',
    wrap(async (req, res) => {
      res.clearCookie(COOKIE_NAME, cookieOptions(config));
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

  // 以下全部需要有效会话。
  router.use(
    '/api/admin',
    wrap((req, res, next) => {
      const session = readSession(req, store.data, secret);
      if (!session) throw new ApiError(401, 400001, '未登录或会话已过期');
      req.admin = session;
      const admin = store.data.admin;
      const url = req.originalUrl.split('?')[0];
      const allowed = url === ME_PREFIX || url === CHANGE_PASSWORD_PREFIX || url === LOGOUT_PREFIX;
      if (admin.mustChangePassword && !allowed) {
        throw new ApiError(403, 400010, '首次登录请先修改初始密码');
      }
      next();
    })
  );

  router.use('/api/admin', csrfGuard);

  router.get(
    '/api/admin/me',
    wrap((req, res) => {
      ok(res, {
        name: req.admin.username,
        username: req.admin.username,
        role: 'admin',
        expiresAt: req.admin.expiresAt,
        mustChangePassword: Boolean(store.data.admin.mustChangePassword),
      });
    })
  );

  router.put(
    '/api/admin/password',
    wrap(async (req, res) => {
      const body = req.body || {};
      const currentPassword = typeof body.currentPassword === 'string' ? body.currentPassword : '';
      const newPassword = typeof body.newPassword === 'string' ? body.newPassword : '';
      const admin = store.data.admin;

      if (!scryptVerify(currentPassword, admin.passwordHash)) {
        throw new ApiError(401, 400001, '当前密码不正确');
      }
      const reason = validatePassword(newPassword, admin.username, config.password);
      if (reason) throw new ApiError(200, 400005, reason);
      if (newPassword === currentPassword) throw new ApiError(200, 400005, '新密码不能与当前密码相同');

      await store.mutate(() => {
        const db = store.data;
        db.admin.passwordHash = scryptHash(newPassword);
        db.admin.mustChangePassword = false;
        db.admin.authEpoch = Number(db.admin.authEpoch) + 1;
        db.admin.sessionId = null;
        db.admin.sessionIssuedAt = null;
        db.admin.sessionExpiresAt = null;
        db.admin.updatedAt = nowIso();
      });
      res.clearCookie(COOKIE_NAME, cookieOptions(config));
      // 初始密码文件已完成使命，改密成功后立即删除。
      try {
        fs.unlinkSync(path.join(config.dataDir, 'initial_admin_password.txt'));
      } catch (_) {
        /* 文件可能已不存在 */
      }
      await audit.log({
        actor: req.admin.username,
        ip: req.clientIp,
        action: 'password_change',
        target: req.admin.username,
        before: { mustChangePassword: true },
        after: { mustChangePassword: false, allSessionsRevoked: true },
      });
      ok(res, { mustReLogin: true }, '密码已更新，所有会话已失效，请重新登录');
    })
  );

  router.post(
    '/api/admin/sessions/revoke',
    wrap(async (req, res) => {
      await store.mutate(() => {
        const db = store.data;
        db.admin.authEpoch = Number(db.admin.authEpoch) + 1;
        db.admin.sessionId = null;
        db.admin.sessionIssuedAt = null;
        db.admin.sessionExpiresAt = null;
        db.admin.updatedAt = nowIso();
      });
      res.clearCookie(COOKIE_NAME, cookieOptions(config));
      await audit.log({
        actor: req.admin.username,
        ip: req.clientIp,
        action: 'sessions_revoke',
        target: req.admin.username,
        before: { sessionId: req.admin.sessionId },
        after: { authEpoch: store.data.admin.authEpoch },
      });
      ok(res, { mustReLogin: true }, '已强制下线全部会话');
    })
  );

  // 维护占位：阶段 0/1 只提供状态查询，实际清理在阶段 2 的 cleanup.js 实现。
  router.get(
    '/api/admin/maintenance/status',
    wrap((req, res) => {
      const free = freeBytes(config.storageRoot);
      const archived = Object.values(store.data.releases).filter((r) => r.status === 'archived');
      ok(res, {
        diskFreeBytes: free,
        diskLow: free !== null && free < config.retention.cleanupTargetFreeBytes,
        stopUploadFreeBytes: config.retention.stopUploadFreeBytes,
        cleanupTargetFreeBytes: config.retention.cleanupTargetFreeBytes,
        maxStorageBytes: config.maxStorageBytes,
        storageBytes: dirSizeBytes(config.storageRoot),
        archivedCount: archived.length,
        archivedFileAvailableCount: archived.filter((r) => r.fileAvailable).length,
        cleanupImplemented: false,
        checkedAt: nowIso(),
      });
    })
  );

  router.post(
    '/api/admin/maintenance/cleanup',
    wrap(async (req, res) => {
      const body = req.body || {};
      const dryRun = body.dryRun === undefined ? true : Boolean(body.dryRun);
      await audit.log({
        actor: req.admin.username,
        ip: req.clientIp,
        action: 'cleanup_manual',
        target: 'storage',
        before: { dryRun },
        after: { implemented: false, candidates: [] },
      });
      ok(
        res,
        {
          implemented: false,
          dryRun,
          candidates: [],
          freedBytes: 0,
          diskFreeBytes: freeBytes(config.storageRoot),
        },
        '阶段 1 尚未实现自动/手动清理，将在阶段 2 提供'
      );
    })
  );

  router.use('/api/admin', createAppsRouter({ store, audit }));

  return router;
}

function createAdminApp({ config, store, audit, secret }) {
  const app = express();
  if (config.trustProxy) app.set('trust proxy', true);
  app.disable('x-powered-by');
  app.use(express.json({ limit: '32kb' }));
  app.use(express.urlencoded({ extended: false, limit: '32kb' }));
  app.use(cookieParser());
  app.use(createAdminRouter({ config, store, audit, secret }));

  const pageCandidates = [
    path.join(config.root, 'build', 'web', 'admin.html'),
    path.join(__dirname, '..', 'web', 'admin.html'),
  ];
  const page = pageCandidates.find((candidate) => fs.existsSync(candidate)) || pageCandidates[0];
  app.get(['/admin', '/admin/'], (req, res) => res.sendFile(page));
  app.get('/', (req, res) => res.redirect('/admin'));
  app.get('/favicon.ico', (req, res) => res.status(204).end());

  app.use((req, res) => res.status(404).json({ code: 300000, msg: '接口不存在', data: null }));
  app.use(handleError);
  return app;
}

module.exports = { createAdminApp, createAdminRouter };
