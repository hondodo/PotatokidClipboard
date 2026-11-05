'use strict';

const { ApiError } = require('./apiutil');
const { readSession, readViewerSession } = require('./security');

// 角色与临时口令 scope 的映射：口令只授予只读能力。
const ROLE_SCOPES = {
  apps: 'apps:read',
  files: 'files:read',
};

// 解析会话：账号会话（Cookie pk_app_admin）优先，其次临时口令会话（pk_app_viewer）。
function authenticate({ store, secret }) {
  return (req, res, next) => {
    const account = readSession(req, store.data, secret);
    if (account) {
      req.principal = account;
      req.actor = account.username;
      req.admin = { username: account.username, roles: account.roles, type: 'account' };
      return next();
    }
    const viewer = readViewerSession(req, store.data, secret);
    if (viewer) {
      req.principal = viewer;
      req.actor = `token:${viewer.tokenId}`;
      req.admin = { username: req.actor, roles: [], type: 'viewer' };
    }
    return next();
  };
}

function requireAuth(req, res, next) {
  if (!req.principal) return next(new ApiError(401, 400001, '未登录或会话已过期'));
  return next();
}

// 账号专属接口（账号管理、口令管理）：临时口令一律拒绝。
function requireAccountRole(role) {
  return (req, res, next) => {
    const p = req.principal;
    if (!p) return next(new ApiError(401, 400001, '未登录或会话已过期'));
    if (p.type !== 'account') {
      return next(new ApiError(403, 400011, '临时访问口令无权访问该接口'));
    }
    if (p.roles.includes(role) || p.roles.includes('admin')) return next();
    return next(new ApiError(403, 400011, `缺少 ${role} 角色权限`));
  };
}

// 通用接口：账号要求角色（admin 通吃）；口令要求 scope 且仅限只读方法。
function requireRole(role) {
  const scope = ROLE_SCOPES[role];
  return (req, res, next) => {
    const p = req.principal;
    if (!p) return next(new ApiError(401, 400001, '未登录或会话已过期'));
    if (p.type === 'account') {
      if (p.roles.includes(role) || p.roles.includes('admin')) return next();
      return next(new ApiError(403, 400011, `缺少 ${role} 角色权限`));
    }
    if (!scope || !p.scopes.includes(scope)) {
      return next(new ApiError(403, 400011, `临时口令缺少 ${scope} 权限`));
    }
    if (!['GET', 'HEAD'].includes(req.method)) {
      return next(new ApiError(403, 400012, '临时口令仅允许只读访问，禁止写操作'));
    }
    return next();
  };
}

module.exports = { authenticate, requireAuth, requireAccountRole, requireRole, ROLE_SCOPES };
