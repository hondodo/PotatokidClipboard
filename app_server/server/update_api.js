'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const express = require('express');

const { ApiError, ok, wrap, clientIp } = require('./apiutil');
const { signDownload, verifyDownload } = require('./security');
const { PLATFORMS, ABIS, nowIso } = require('./store');

// 签名下载地址（TTL 默认 600s，来自 downloadTokenTtlSec）。
function makeDownloadUrl(config, secret, releaseId) {
  const ttl = Number(config.downloadTokenTtlSec) || 600;
  const exp = Math.floor(Date.now() / 1000) + ttl;
  const base = String(config.publicBaseUrl || '').replace(/\/+$/, '');
  return {
    url: `${base}/api/download/${releaseId}?exp=${exp}&sig=${signDownload(secret, releaseId, exp)}`,
    expiresAt: new Date(exp * 1000).toISOString(),
  };
}

function timingSafeEqualStr(a, b) {
  const x = Buffer.from(String(a));
  const y = Buffer.from(String(b));
  return x.length === y.length && crypto.timingSafeEqual(x, y);
}

// 取链限流：同 IP linksPer10Min 次 / 10 分钟。
class LinkLimiter {
  constructor({ limit = 20, windowMs = 10 * 60 * 1000 } = {}) {
    this.limit = limit;
    this.windowMs = windowMs;
    this.map = new Map();
  }

  take(key) {
    const now = Date.now();
    const arr = (this.map.get(key) || []).filter((t) => now - t < this.windowMs);
    if (arr.length >= this.limit) {
      this.map.set(key, arr);
      return { allowed: false, retryAfterSec: Math.ceil((this.windowMs - (now - arr[0])) / 1000) };
    }
    arr.push(now);
    this.map.set(key, arr);
    return { allowed: true, retryAfterSec: 0 };
  }
}

function parseBuild(raw) {
  const n = Number.parseInt(String(raw === undefined ? 0 : raw), 10);
  return Number.isFinite(n) && n >= 0 ? n : 0;
}

function createUpdateRouter({ config, store, audit, secret }) {
  const router = express.Router();
  const limiter = new LinkLimiter({
    limit: Number(config.download && config.download.linksPer10Min) || 20,
    windowMs: 10 * 60 * 1000,
  });
  const activeByIp = new Map();

  function requireApiKey(req) {
    const expected = config.apiKey;
    if (!expected) return;
    const given = req.get('x-api-key') || '';
    if (!given || !timingSafeEqualStr(given, expected)) {
      throw new ApiError(401, 400001, 'API Key 无效');
    }
  }

  // 查询：同时支持 PLAN 的 /api/update/check 与 /api/apps/:appId/update 别名。
  const check = wrap(async (req, res) => {
    requireApiKey(req);
    const ip = clientIp(req);
    const gate = limiter.take(ip);
    if (!gate.allowed) {
      throw new ApiError(429, 400002, `取链过于频繁，请 ${Math.ceil(gate.retryAfterSec / 60)} 分钟后再试`);
    }

    const appId = String(req.query.app || req.params.appId || '').trim();
    const platform = String(req.query.platform || '').trim().toLowerCase();
    const version = req.query.version === undefined ? '' : String(req.query.version);
    const currentBuild = parseBuild(req.query.build);

    if (!appId) throw new ApiError(200, 400005, '缺少 app 参数');
    if (!PLATFORMS.includes(platform)) throw new ApiError(200, 300005, `不支持的平台：${platform || '(空)'}`);

    const app = store.getApplicationOrNull(appId);
    if (!app || !app.enabled) throw new ApiError(200, 300000, '应用不存在或已停用');

    // abi：设备架构（新版客户端携带，老版不带）。空值/非法值一律按 universal
    // 处理；getLatestForAbi 实现「精确 abi 轨优先、该轨无记录回落 universal」。
    const abiRaw = String(req.query.abi || '').trim().toLowerCase();
    const abi = ABIS.includes(abiRaw) ? abiRaw : '';
    const latest = store.getLatestForAbi(appId, platform, abi);
    const hasUpdate = Boolean(latest && latest.build > currentBuild);
    const forceUpdate = Boolean(hasUpdate && latest.forceUpdate && platform !== 'ios');

    let download = null;
    if (hasUpdate && latest.distribution === 'file' && latest.fileAvailable) {
      const signed = makeDownloadUrl(config, secret, latest.releaseId);
      download = {
        url: signed.url,
        size: latest.size,
        sha256: latest.sha256,
        filename: latest.filename,
        expiresAt: signed.expiresAt,
      };
    }

    ok(res, {
      app: appId,
      platform,
      checkedAt: nowIso(),
      hasUpdate,
      forceUpdate,
      current: { version, build: currentBuild },
      latest: latest
        ? {
            releaseId: latest.releaseId,
            version: latest.version,
            build: latest.build,
            distribution: latest.distribution,
            fileAvailable: Boolean(latest.fileAvailable),
            externalUrl: latest.externalUrl || null,
            publishedAt: latest.publishedAt,
            notes: latest.notes || '',
            forceUpdate: Boolean(latest.forceUpdate),
          }
        : null,
      download,
    });
  });

  router.get('/api/update/check', check);
  router.get('/api/apps/:appId/update', check);

  // 签名下载：校验签名/过期/文件可用，支持 Range 与 HEAD，同 IP 并发 ≤4。
  const downloadHandler = wrap(async (req, res, next) => {
    const releaseId = String(req.params.releaseId || '');
    const exp = Number(req.query.exp);
    const sig = String(req.query.sig || '');
    if (!verifyDownload(secret, releaseId, exp, sig)) {
      throw new ApiError(403, 400003, '下载签名无效或已过期');
    }
    if (exp * 1000 <= Date.now()) throw new ApiError(403, 400003, '下载链接已过期，请重新查询');

    const release = store.getRelease(releaseId);
    if (release.distribution !== 'file' || !release.fileAvailable) {
      throw new ApiError(410, 300008, '该版本安装包已被清理，请重新上传');
    }

    const abs = path.resolve(config.storageRoot, release.storedPath);
    if (!abs.startsWith(path.resolve(config.storageRoot) + path.sep) || !fs.existsSync(abs)) {
      throw new ApiError(410, 300008, '该版本安装包文件不存在，请重新上传');
    }

    const ip = clientIp(req);
    const active = activeByIp.get(ip) || 0;
    const maxConcurrent = Number(config.download && config.download.maxConcurrentPerIp) || 4;
    if (active >= maxConcurrent) {
      throw new ApiError(429, 400002, '并发下载数超过限制，请稍后重试');
    }
    activeByIp.set(ip, active + 1);
    let released = false;
    const releaseSlot = () => {
      if (released) return;
      released = true;
      const left = (activeByIp.get(ip) || 1) - 1;
      if (left <= 0) activeByIp.delete(ip);
      else activeByIp.set(ip, left);
    };
    res.on('close', releaseSlot);

    const today = new Date().toISOString().slice(0, 10);
    await store.mutate(() => {
      release.downloadCount = Number(release.downloadCount || 0) + 1;
      release.lastDownloadAt = nowIso();
      const db = store.data;
      if (!db.stats) db.stats = { daily: {} };
      if (!db.stats.daily[today]) db.stats.daily[today] = {};
      const key = `${release.appId}|${release.platform}`;
      db.stats.daily[today][key] = Number(db.stats.daily[today][key] || 0) + 1;
    });

    const filename = release.filename || path.basename(abs);
    const asciiName = filename.replace(/[^\x20-\x7e]/g, '_').replace(/["\\]/g, '_');
    res.setHeader('Content-Type', 'application/octet-stream');
    res.setHeader('Content-Disposition', `attachment; filename="${asciiName}"; filename*=UTF-8''${encodeURIComponent(filename)}`);
    res.setHeader('Cache-Control', 'no-store');
    res.sendFile(abs, (err) => {
      if (!err) return;
      if (!res.headersSent) return next(err);
      audit
        .log({
          actor: 'anonymous',
          ip,
          action: 'download_error',
          target: releaseId,
          before: null,
          after: { message: err.message },
        })
        .catch(() => {});
    });
  });

  router.get('/api/download/:releaseId', downloadHandler);
  router.head('/api/download/:releaseId', downloadHandler);

  return router;
}

module.exports = { createUpdateRouter, makeDownloadUrl, LinkLimiter };
