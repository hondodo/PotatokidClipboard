'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { ensureDir, writeFilePrivate } = require('./config');
const { nowIso } = require('./store');

const COOKIE_NAME = 'pk_app_admin';
const SCRYPT = { N: 16384, r: 8, p: 1, maxmem: 64 * 1024 * 1024 };

function ensureSecret(dataDir) {
  const file = path.join(dataDir, 'secret.key');
  ensureDir(dataDir);
  if (!fs.existsSync(file)) {
    writeFilePrivate(file, crypto.randomBytes(32).toString('hex') + '\n');
  }
  try {
    fs.chmodSync(file, 0o600);
  } catch (_) {
    /* ignore */
  }
  const hex = fs.readFileSync(file, 'utf8').trim();
  if (hex.length < 32) throw new Error('datas/app_update/secret.key 内容过短');
  return Buffer.from(hex, 'hex');
}

function scryptHash(password, saltHex) {
  const salt = saltHex ? Buffer.from(saltHex, 'hex') : crypto.randomBytes(16);
  const hash = crypto.scryptSync(password, salt, 32, SCRYPT);
  return `scrypt$${SCRYPT.N}$${SCRYPT.r}$${SCRYPT.p}$${salt.toString('hex')}$${hash.toString('hex')}`;
}

function scryptVerify(password, stored) {
  try {
    const parts = String(stored || '').split('$');
    if (parts.length !== 6 || parts[0] !== 'scrypt') return false;
    const [, n, r, p, saltHex, hashHex] = parts;
    const expected = Buffer.from(hashHex, 'hex');
    const actual = crypto.scryptSync(password, Buffer.from(saltHex, 'hex'), expected.length, {
      N: Number(n),
      r: Number(r),
      p: Number(p),
      maxmem: SCRYPT.maxmem,
    });
    return expected.length === actual.length && crypto.timingSafeEqual(expected, actual);
  } catch (_) {
    return false;
  }
}

// 密码策略：长度可配置（默认 6–64），不强制字符类别；仅禁止纯空白与和用户名相同。
function validatePassword(password, username, policy = {}) {
  const minLength = Number(policy.minLength) || 6;
  const maxLength = Number(policy.maxLength) || 64;
  if (typeof password !== 'string') return '密码必须为字符串';
  if (password.length < minLength) return `密码长度至少 ${minLength} 位`;
  if (password.length > maxLength) return `密码长度不能超过 ${maxLength} 位`;
  if (!password.trim()) return '密码不能为纯空白';
  if (username && password.toLowerCase() === String(username).toLowerCase()) return '密码不能与用户名相同';
  return null;
}

function generateInitialPassword() {
  const alphabet = 'abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789!@#$%^&*-_=+';
  const pick = () => crypto.randomInt(0, alphabet.length);
  const chars = ['a', 'A', '9', '!', ...Array.from({ length: 14 }, pick).map((i) => alphabet[i])];
  for (let i = chars.length - 1; i > 0; i--) {
    const j = crypto.randomInt(0, i + 1);
    [chars[i], chars[j]] = [chars[j], chars[i]];
  }
  return chars.join('');
}

// 首次启动生成初始管理员：密码只落盘到 datas/app_update/initial_admin_password.txt（0600），不入库、不入仓库。
function bootstrapAdmin({ dataDir, username }) {
  const password = generateInitialPassword();
  const file = path.join(dataDir, 'initial_admin_password.txt');
  writeFilePrivate(file, password + '\n');
  return {
    admin: {
      username,
      passwordHash: scryptHash(password),
      mustChangePassword: true,
      authEpoch: 1,
      sessionId: null,
      sessionIssuedAt: null,
      sessionExpiresAt: null,
      updatedAt: nowIso(),
    },
    initialPasswordFile: file,
  };
}

class LoginLimiter {
  constructor({ ipLimit = 5, ipWindowMs = 15 * 60 * 1000, accountLimit = 10, accountWindowMs = 60 * 60 * 1000, lockMs = 30 * 60 * 1000 } = {}) {
    this.ipLimit = ipLimit;
    this.ipWindowMs = ipWindowMs;
    this.accountLimit = accountLimit;
    this.accountWindowMs = accountWindowMs;
    this.lockMs = lockMs;
    this.ips = new Map();
    this.accounts = new Map();
  }

  #bucket(map, key) {
    let b = map.get(key);
    if (!b) {
      b = { failures: [], lockedUntil: 0 };
      map.set(key, b);
    }
    return b;
  }

  #cleanup(bucket, windowMs, now) {
    bucket.failures = bucket.failures.filter((t) => now - t < windowMs);
  }

  status({ ip, username }) {
    const now = Date.now();
    const ipB = this.#bucket(this.ips, ip);
    const accB = this.#bucket(this.accounts, username || '');
    this.#cleanup(ipB, this.ipWindowMs, now);
    this.#cleanup(accB, this.accountWindowMs, now);
    const until = Math.max(ipB.lockedUntil, accB.lockedUntil);
    if (until > now) return { locked: true, retryAfterSec: Math.ceil((until - now) / 1000) };
    return { locked: false, retryAfterSec: 0 };
  }

  fail({ ip, username }) {
    const now = Date.now();
    const ipB = this.#bucket(this.ips, ip);
    const accB = this.#bucket(this.accounts, username || '');
    this.#cleanup(ipB, this.ipWindowMs, now);
    this.#cleanup(accB, this.accountWindowMs, now);
    ipB.failures.push(now);
    accB.failures.push(now);
    if (ipB.failures.length >= this.ipLimit) ipB.lockedUntil = now + this.lockMs;
    if (accB.failures.length >= this.accountLimit) accB.lockedUntil = now + this.lockMs;
    return this.status({ ip, username });
  }

  success({ ip, username }) {
    this.ips.delete(ip);
    this.accounts.delete(username || '');
  }
}

const b64url = (buf) => Buffer.from(buf).toString('base64url');

function signCookie(payload, secret) {
  const body = b64url(JSON.stringify(payload));
  const sig = b64url(crypto.createHmac('sha256', secret).update(body).digest());
  return `${body}.${sig}`;
}

function verifyCookie(value, secret) {
  if (typeof value !== 'string' || !value.includes('.')) return null;
  const idx = value.lastIndexOf('.');
  const body = value.slice(0, idx);
  const sig = value.slice(idx + 1);
  const expected = b64url(crypto.createHmac('sha256', secret).update(body).digest());
  const a = Buffer.from(sig);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !crypto.timingSafeEqual(a, b)) return null;
  try {
    return JSON.parse(Buffer.from(body, 'base64url').toString('utf8'));
  } catch (_) {
    return null;
  }
}

function cookieOptions(config) {
  return {
    httpOnly: true,
    sameSite: 'strict',
    secure: Boolean(config.admin && config.admin.cookieSecure),
    path: '/',
  };
}

function issueSession(db, config) {
  const hours = Number(config.admin.sessionHours) || 12;
  const now = Date.now();
  const admin = db.admin;
  admin.sessionId = crypto.randomBytes(16).toString('hex');
  admin.sessionIssuedAt = new Date(now).toISOString();
  admin.sessionExpiresAt = new Date(now + hours * 3600 * 1000).toISOString();
  return {
    sid: admin.sessionId,
    exp: Math.floor((now + hours * 3600 * 1000) / 1000),
    expiresAt: admin.sessionExpiresAt,
  };
}

function sessionPayload(admin, session) {
  return { u: admin.username, sid: session.sid, e: admin.authEpoch, exp: session.exp };
}

function readSession(req, db, secret) {
  const raw = req.cookies ? req.cookies[COOKIE_NAME] : null;
  const payload = verifyCookie(raw, secret);
  if (!payload) return null;
  const admin = db.admin;
  if (!admin || !admin.sessionId) return null;
  if (Number(payload.exp) * 1000 <= Date.now()) return null;
  if (payload.sid !== admin.sessionId || Number(payload.e) !== Number(admin.authEpoch)) return null;
  if (payload.u !== admin.username) return null;
  return { username: admin.username, sessionId: admin.sessionId, expiresAt: admin.sessionExpiresAt };
}

module.exports = {
  COOKIE_NAME,
  ensureSecret,
  scryptHash,
  scryptVerify,
  validatePassword,
  bootstrapAdmin,
  LoginLimiter,
  signCookie,
  verifyCookie,
  cookieOptions,
  issueSession,
  sessionPayload,
  readSession,
};
