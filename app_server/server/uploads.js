'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const express = require('express');
const { Transform } = require('stream');
const { pipeline } = require('stream/promises');

const { ApiError, ok, wrap, freeBytes, dirSizeBytes } = require('./apiutil');
const { validateReleaseMeta, nowIso } = require('./store');
const { ensureDir } = require('./config');

// 扩展名白名单（PLAN 4.3 分片规则）。
const EXT_WHITELIST = {
  windows: ['.exe', '.msi', '.zip'],
  apk: ['.apk'],
  macos: ['.dmg', '.pkg', '.zip'],
  linux: ['.appimage', '.deb', '.tar.gz', '.zip'],
  ios: [],
};

const FILENAME_RE = /^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/;
const SHA256_RE = /^[0-9a-f]{64}$/i;

function sanitizeCheck(filename) {
  const name = String(filename || '').trim();
  if (!name || !FILENAME_RE.test(name) || name.includes('..')) {
    throw new ApiError(200, 400005, '文件名只能包含字母/数字/点/下划线/连字符，且不能包含 .. 或路径分隔符');
  }
  return name;
}

function extAllowed(platform, filename) {
  const lower = filename.toLowerCase();
  const list = EXT_WHITELIST[platform] || [];
  return list.some((ext) => lower.endsWith(ext));
}

function newUploadId() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  const stamp = `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}`;
  return `up_${stamp}_${crypto.randomBytes(3).toString('hex')}`;
}

class UploadManager {
  constructor({ config, store, audit }) {
    this.config = config;
    this.store = store;
    this.audit = audit;
    this.sessions = new Map();
    this.inflight = new Map();
    this.chunkSize = Number(config.chunk && config.chunk.sizeBytes) || 8388608;
    this.expireHours = Number(config.chunk && config.chunk.expireHours) || 24;
    this.maxActive = Number(config.chunk && config.chunk.maxActivePerAdmin) || 2;
    this.maxConcurrent = Number(config.chunk && config.chunk.maxConcurrentPerUpload) || 3;
    this.tmpQuota = Number(config.chunk && config.chunk.tmpQuotaBytes) || 2147483648;
  }

  dir(uploadId) {
    return path.join(this.config.tmpDir, uploadId);
  }

  metaFile(uploadId) {
    return path.join(this.dir(uploadId), 'meta.json');
  }

  chunkFile(uploadId, index) {
    return path.join(this.dir(uploadId), 'chunks', `${String(index).padStart(5, '0')}.part`);
  }

  persistMeta(upload) {
    const tmp = `${this.metaFile(upload.uploadId)}.tmp`;
    fs.writeFileSync(tmp, JSON.stringify(upload, null, 2) + '\n', { mode: 0o600 });
    fs.renameSync(tmp, this.metaFile(upload.uploadId));
  }

  // 启动时恢复未完成任务（进程重启后仍可续传）。
  init() {
    ensureDir(this.config.tmpDir, 0o700);
    let entries = [];
    try {
      entries = fs.readdirSync(this.config.tmpDir, { withFileTypes: true });
    } catch (_) {
      entries = [];
    }
    for (const entry of entries) {
      if (!entry.isDirectory() || !entry.name.startsWith('up_')) continue;
      const metaPath = path.join(this.config.tmpDir, entry.name, 'meta.json');
      try {
        const meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'));
        if (!meta.expiresAt || Date.parse(meta.expiresAt) <= Date.now() || meta.completed) {
          this.removeDir(entry.name);
          continue;
        }
        this.sessions.set(meta.uploadId, meta);
      } catch (_) {
        this.removeDir(entry.name);
      }
    }
  }

  removeDir(uploadId) {
    try {
      fs.rmSync(this.dir(uploadId), { recursive: true, force: true });
    } catch (_) {
      /* ignore */
    }
    this.sessions.delete(uploadId);
    this.inflight.delete(uploadId);
  }

  getSession(uploadId) {
    const upload = this.sessions.get(uploadId);
    if (!upload) throw new ApiError(200, 400005, '上传任务不存在或已过期，请重新初始化');
    if (Date.parse(upload.expiresAt) <= Date.now()) {
      this.removeDir(uploadId);
      throw new ApiError(200, 400005, '上传任务已过期，请重新初始化');
    }
    return upload;
  }

  activeCount(username) {
    let count = 0;
    for (const item of this.sessions.values()) {
      if (item.adminUsername === username && !item.completed) count += 1;
    }
    return count;
  }

  tmpUsedBytes() {
    let total = 0;
    for (const item of this.sessions.values()) total += Number(item.bytesReceived || 0);
    return total;
  }

  // 24h 超时清理，每 10 分钟由调度器调用。
  sweepExpired() {
    const now = Date.now();
    let removed = 0;
    for (const [uploadId, upload] of this.sessions) {
      if (Date.parse(upload.expiresAt) <= now) {
        this.removeDir(uploadId);
        removed += 1;
      }
    }
    return { removed };
  }

  beginInit({ body, admin, ip }) {
    const appId = String(body.appId || '').trim();
    const platform = String(body.platform || '').trim().toLowerCase();
    const app = this.store.getApplication(appId);
    const checkedPlatform = this.store.assertPlatformAllowed(app, platform);
    if (checkedPlatform === 'ios') {
      throw new ApiError(200, 300009, 'iOS 版本只接受外部链接，请使用“iOS 外部链接”录入，不上传安装包');
    }

    const filename = sanitizeCheck(body.filename);
    if (!extAllowed(checkedPlatform, filename)) {
      throw new ApiError(200, 300005, `平台 ${checkedPlatform} 的安装包扩展名不匹配（允许：${EXT_WHITELIST[checkedPlatform].join(' ')}）`);
    }

    const meta = validateReleaseMeta({
      version: body.version,
      build: body.build,
      pubspecBuildConfirmed: body.pubspecBuildConfirmed,
    });

    if (this.store.findReleaseByBuild(appId, checkedPlatform, meta.build)) {
      throw new ApiError(200, 300002, `该平台已存在 build=${meta.build} 的版本`);
    }

    const size = Number(body.size);
    if (!Number.isInteger(size) || size <= 0) throw new ApiError(200, 400005, 'size 必须为正整数（字节）');
    if (size > Number(this.config.maxUploadBytes)) {
      const mb = (Number(this.config.maxUploadBytes) / 1024 / 1024).toFixed(0);
      throw new ApiError(413, 300004, `安装包超过单包上限 ${mb} MiB`);
    }

    let declaredSha = '';
    if (body.sha256 !== undefined && body.sha256 !== null && body.sha256 !== '') {
      declaredSha = String(body.sha256).trim().toLowerCase();
      if (!SHA256_RE.test(declaredSha)) throw new ApiError(200, 400005, 'sha256 必须为 64 位十六进制');
    }

    const free = freeBytes(this.config.root);
    const minFree = Number(this.config.minFreeBytes) || 1073741824;
    const stopFree = Number(this.config.retention && this.config.retention.stopUploadFreeBytes) || 1073741824;
    if (free !== null && (free < stopFree || free < Math.max(minFree, 2 * size))) {
      throw new ApiError(200, 300006, '磁盘可用空间不足，已暂停接收上传');
    }
    const used = dirSizeBytes(this.config.storageRoot) + size;
    if (used > Number(this.config.maxStorageBytes)) {
      throw new ApiError(200, 300006, '安装包总占用将超过上限，拒绝上传');
    }
    const quotaBase = free === null ? this.tmpQuota : Math.min(this.tmpQuota, Math.floor(free * 0.3));
    if (this.tmpUsedBytes() + size > quotaBase) {
      throw new ApiError(200, 300006, '上传临时目录配额不足，请等待其它上传完成或清理');
    }
    if (this.activeCount(admin.username) >= this.maxActive) {
      throw new ApiError(429, 400002, `同时进行的上传不能超过 ${this.maxActive} 个，请先完成或放弃进行中的任务`);
    }

    const uploadId = newUploadId();
    const chunkSize = this.chunkSize;
    const totalChunks = Math.ceil(size / chunkSize);
    const upload = {
      uploadId,
      appId,
      platform: checkedPlatform,
      filename,
      size,
      sha256: declaredSha,
      version: meta.version,
      build: meta.build,
      notes: String(body.notes || '').slice(0, 2000),
      forceUpdate: Boolean(body.forceUpdate),
      status: 'draft',
      adminUsername: admin.username,
      chunkSize,
      totalChunks,
      received: {},
      bytesReceived: 0,
      createdAt: nowIso(),
      expiresAt: new Date(Date.now() + this.expireHours * 3600 * 1000).toISOString(),
      completed: false,
    };
    ensureDir(path.join(this.dir(uploadId), 'chunks'), 0o700);
    this.sessions.set(uploadId, upload);
    this.persistMeta(upload);
    return upload;
  }

  async addChunk({ uploadId, index, req, chunkSha }) {
    const upload = this.getSession(uploadId);
    if (upload.completed) throw new ApiError(200, 400005, '上传已完成，不能继续上传分片');
    const idx = Number(index);
    if (!Number.isInteger(idx) || idx < 0 || idx >= upload.totalChunks) {
      throw new ApiError(200, 400005, `分片序号必须在 0..${upload.totalChunks - 1} 之间`);
    }

    const target = this.chunkFile(uploadId, idx);
    const tmpTarget = `${target}.tmp`;
    const expected = idx === upload.totalChunks - 1 ? upload.size - upload.chunkSize * (upload.totalChunks - 1) : upload.chunkSize;
    const declaredLength = Number(req.get('content-length'));
    if (Number.isFinite(declaredLength) && declaredLength > expected) {
      throw new ApiError(413, 300004, `分片 ${idx} 超过预期大小 ${expected} 字节`);
    }

    const current = this.inflight.get(uploadId) || 0;
    if (current >= this.maxConcurrent) {
      throw new ApiError(429, 400002, `同一上传的分片并发不能超过 ${this.maxConcurrent} 个`);
    }
    this.inflight.set(uploadId, current + 1);
    const release = () => {
      const left = (this.inflight.get(uploadId) || 1) - 1;
      if (left <= 0) this.inflight.delete(uploadId);
      else this.inflight.set(uploadId, left);
    };

    const hash = crypto.createHash('sha256');
    let received = 0;
    let overflow = false;

    try {
      // 超长分片不再向前写盘，但仍把请求体读完，避免破坏连接后无法返回 JSON 错误。
      const meter = new Transform({
        transform(chunk, enc, cb) {
          received += chunk.length;
          if (received > expected) {
            overflow = true;
            cb(null);
            return;
          }
          hash.update(chunk);
          cb(null, chunk);
        },
      });
      await pipeline(req, meter, fs.createWriteStream(tmpTarget, { mode: 0o600 }));
    } catch (err) {
      try {
        fs.unlinkSync(tmpTarget);
      } catch (_) {
        /* ignore */
      }
      throw err instanceof ApiError ? err : new ApiError(200, 400005, `分片 ${idx} 写入失败：${err.message || err}`);
    } finally {
      release();
    }

    if (overflow || received !== expected) {
      try {
        fs.unlinkSync(tmpTarget);
      } catch (_) {
        /* ignore */
      }
      throw new ApiError(200, 400005, `分片 ${idx} 大小不符：期望 ${expected}，实际 ${received}`);
    }
    if (chunkSha && String(chunkSha).trim() !== '') {
      const declared = String(chunkSha).trim().toLowerCase();
      if (!SHA256_RE.test(declared)) {
        fs.unlinkSync(tmpTarget);
        throw new ApiError(200, 400005, 'X-Chunk-SHA256 必须为 64 位十六进制');
      }
      if (declared !== hash.digest('hex')) {
        try {
          fs.unlinkSync(tmpTarget);
        } catch (_) {
          /* ignore */
        }
        throw new ApiError(200, 400005, `分片 ${idx} sha256 校验失败`);
      }
    }

    fs.renameSync(tmpTarget, target);
    upload.received[idx] = received;
    upload.bytesReceived = Object.values(upload.received).reduce((a, b) => a + b, 0);
    this.persistMeta(upload);
    return { index: idx, received: Object.keys(upload.received).length, total: upload.totalChunks, chunkSize: upload.chunkSize };
  }

  async complete({ uploadId, declaredSha, admin, ip }) {
    const upload = this.getSession(uploadId);
    if (upload.completed) throw new ApiError(200, 400005, '上传已完成');

    const missing = [];
    for (let i = 0; i < upload.totalChunks; i += 1) {
      if (!fs.existsSync(this.chunkFile(uploadId, i))) missing.push(i);
    }
    if (missing.length) {
      throw new ApiError(200, 400005, `缺少分片：${missing.join(',')}（可 GET 上传状态后补传）`);
    }

    const merged = path.join(this.dir(uploadId), 'package.bin');
    const hash = crypto.createHash('sha256');
    const ws = fs.createWriteStream(merged, { mode: 0o600 });
    try {
      for (let i = 0; i < upload.totalChunks; i += 1) {
        const part = this.chunkFile(uploadId, i);
        await new Promise((resolve, reject) => {
          const rs = fs.createReadStream(part);
          rs.on('data', (data) => {
            hash.update(data);
            if (!ws.write(data)) {
              rs.pause();
              ws.once('drain', () => rs.resume());
            }
          });
          rs.on('end', resolve);
          rs.on('error', reject);
        });
      }
      await new Promise((resolve, reject) => ws.end((err) => (err ? reject(err) : resolve())));
    } catch (err) {
      try {
        ws.destroy();
        fs.unlinkSync(merged);
      } catch (_) {
        /* ignore */
      }
      throw err instanceof ApiError ? err : new ApiError(200, 500000, `合并分片失败：${err.message || err}`);
    }

    const actualSha = hash.digest('hex');
    const expectSha = (declaredSha && String(declaredSha).trim().toLowerCase()) || upload.sha256;
    if (expectSha && expectSha !== actualSha) {
      try {
        fs.unlinkSync(merged);
      } catch (_) {
        /* ignore */
      }
      throw new ApiError(200, 400005, `整包 sha256 校验失败：期望 ${expectSha}，实际 ${actualSha}`);
    }
    const stat = fs.statSync(merged);
    if (stat.size !== upload.size) {
      try {
        fs.unlinkSync(merged);
      } catch (_) {
        /* ignore */
      }
      throw new ApiError(200, 400005, `合并后大小不符：期望 ${upload.size}，实际 ${stat.size}`);
    }

    const relPath = path.join(upload.appId, upload.platform, String(upload.build), `${upload.version}-${upload.build}-${upload.filename}`);
    const finalDir = path.join(this.config.storageRoot, upload.appId, upload.platform, String(upload.build));
    ensureDir(finalDir, 0o700);
    const finalAbs = path.join(this.config.storageRoot, relPath);
    fs.renameSync(merged, finalAbs);

    let release;
    try {
      release = await this.store.mutate(() =>
        this.store.createReleaseRecord({
          appId: upload.appId,
          platform: upload.platform,
          version: upload.version,
          build: upload.build,
          pubspecBuildConfirmed: true,
          filename: upload.filename,
          storedPath: relPath.split(path.sep).join('/'),
          size: upload.size,
          sha256: actualSha,
          distribution: 'file',
          externalUrl: null,
          fileAvailable: true,
          notes: upload.notes,
          uploadedBy: upload.adminUsername,
        })
      );
    } catch (err) {
      try {
        fs.unlinkSync(finalAbs);
      } catch (_) {
        /* ignore */
      }
      throw err;
    }

    upload.completed = true;
    this.removeDir(uploadId);

    await this.audit.log({
      actor: admin.username,
      ip,
      action: 'upload_complete',
      target: release.releaseId,
      before: null,
      after: {
        appId: release.appId,
        platform: release.platform,
        version: release.version,
        build: release.build,
        size: release.size,
        sha256: release.sha256,
        chunks: upload.totalChunks,
      },
    });

    return {
      releaseId: release.releaseId,
      appId: release.appId,
      platform: release.platform,
      version: release.version,
      build: release.build,
      size: release.size,
      sha256: release.sha256,
      fileAvailable: true,
      status: release.status,
    };
  }

  statusPayload(upload) {
    const received = [];
    const missing = [];
    for (let i = 0; i < upload.totalChunks; i += 1) {
      if (fs.existsSync(this.chunkFile(upload.uploadId, i))) received.push(i);
      else missing.push(i);
    }
    return {
      uploadId: upload.uploadId,
      appId: upload.appId,
      platform: upload.platform,
      filename: upload.filename,
      size: upload.size,
      chunkSize: upload.chunkSize,
      totalChunks: upload.totalChunks,
      received,
      missing,
      expiresAt: upload.expiresAt,
      completed: upload.completed,
    };
  }

  router() {
    const router = express.Router();
    const self = this;

    router.post(
      '/init',
      wrap(async (req, res) => {
        const upload = self.beginInit({ body: req.body || {}, admin: req.admin, ip: req.clientIp });
        ok(res, {
          uploadId: upload.uploadId,
          chunkSize: upload.chunkSize,
          totalChunks: upload.totalChunks,
          expiresAt: upload.expiresAt,
        }, '上传已初始化');
      })
    );

    router.get(
      '/:uploadId',
      wrap((req, res) => {
        const upload = self.getSession(req.params.uploadId);
        ok(res, self.statusPayload(upload));
      })
    );

    router.put(
      '/:uploadId/chunks/:index',
      wrap(async (req, res) => {
        const result = await self.addChunk({
          uploadId: req.params.uploadId,
          index: req.params.index,
          req,
          chunkSha: req.get('x-chunk-sha256'),
        });
        ok(res, result);
      })
    );

    router.post(
      '/:uploadId/complete',
      wrap(async (req, res) => {
        const body = req.body || {};
        const release = await self.complete({
          uploadId: req.params.uploadId,
          declaredSha: body.sha256,
          admin: req.admin,
          ip: req.clientIp,
        });
        ok(res, release, '上传完成，已创建草稿版本');
      })
    );

    router.delete(
      '/:uploadId',
      wrap(async (req, res) => {
        const upload = self.getSession(req.params.uploadId);
        const before = { appId: upload.appId, platform: upload.platform, version: upload.version, build: upload.build };
        self.removeDir(upload.uploadId);
        await self.audit.log({
          actor: req.admin.username,
          ip: req.clientIp,
          action: 'upload_abort',
          target: upload.uploadId,
          before,
          after: null,
        });
        ok(res, { uploadId: upload.uploadId }, '已放弃上传并清理临时文件');
      })
    );

    return router;
  }
}

module.exports = { UploadManager, EXT_WHITELIST, sanitizeCheck };
