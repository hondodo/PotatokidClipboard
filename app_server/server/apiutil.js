'use strict';

const fs = require('fs');

class ApiError extends Error {
  constructor(http, code, msg, data = null) {
    super(msg);
    this.http = http;
    this.code = code;
    this.data = data;
  }
}

function ok(res, data = null, msg = 'ok') {
  res.status(200).json({ code: 0, msg, data });
}

function fail(res, http, code, msg, data = null) {
  res.status(http).json({ code, msg, data });
}

// 统一把 DataError / ApiError 转成 {code,msg,data} 响应。
function handleError(err, req, res, next) {
  if (res.headersSent) return next(err);
  if (err && typeof err.code === 'number' && typeof err.http === 'number') {
    return fail(res, err.http, err.code, err.message, err.data || null);
  }
  if (err && err.type === 'entity.parse.failed') {
    return fail(res, 200, 400005, '请求体不是合法 JSON');
  }
  console.error('[error]', err && err.stack ? err.stack : err);
  return fail(res, 500, 500000, '服务器内部错误');
}

const wrap = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

function clientIp(req) {
  const raw = req.ip || (req.socket && req.socket.remoteAddress) || '';
  return raw.replace(/^::ffff:/, '');
}

function securityHeaders(req, res, next) {
  res.setHeader('X-Content-Type-Options', 'nosniff');
  res.setHeader('Referrer-Policy', 'no-referrer');
  next();
}

// CSRF：SameSite=Strict + 写操作必须带 X-Admin-Request: 1；若浏览器带 Origin，则必须与本机 Host 一致。
function csrfGuard(req, res, next) {
  if (!['POST', 'PUT', 'PATCH', 'DELETE'].includes(req.method)) return next();
  if (req.get('x-admin-request') !== '1') {
    return next(new ApiError(403, 400001, '缺少 X-Admin-Request 请求头'));
  }
  const origin = req.get('origin');
  if (origin) {
    let host = '';
    try {
      host = new URL(origin).host;
    } catch (_) {
      host = '';
    }
    if (!host || host !== req.get('host')) {
      return next(new ApiError(403, 400001, 'Origin 校验失败'));
    }
  }
  return next();
}

function freeBytes(target) {
  try {
    const st = fs.statfsSync(target);
    return Number(st.bavail) * Number(st.bsize);
  } catch (_) {
    return null;
  }
}

function dirSizeBytes(dir) {
  let total = 0;
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch (_) {
    return 0;
  }
  for (const entry of entries) {
    const full = require('path').join(dir, entry.name);
    if (entry.isDirectory()) total += dirSizeBytes(full);
    else if (entry.isFile()) {
      try {
        total += fs.statSync(full).size;
      } catch (_) {
        /* ignore */
      }
    }
  }
  return total;
}

module.exports = { ApiError, ok, fail, handleError, wrap, clientIp, securityHeaders, csrfGuard, freeBytes, dirSizeBytes };
