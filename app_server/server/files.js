'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const express = require('express');
const Busboy = require('busboy');
const { pipeline } = require('stream/promises');
const { Transform } = require('stream');

const { ApiError, ok, wrap, clientIp } = require('./apiutil');
const { nowIso } = require('./store');

const DEFAULT_MAX_BYTES = 1073741824; // 1 GiB
const NAME_LIMIT = 120;

function maxBytesOf(config) {
  return Number(config.files && config.files.maxTotalBytes) || DEFAULT_MAX_BYTES;
}

// 元信息解码：本地 pscreen_server 会 URL 编码文件名/路径；解码一次，非法编码回退原值。
function decodeValue(raw) {
  const value = String(raw === undefined || raw === null ? '' : raw);
  if (!value.includes('%')) return value;
  try {
    return decodeURIComponent(value);
  } catch (_) {
    return value;
  }
}

// 路径按段解码，保留 '/' 分隔；避免整串解码把 %2F 变成真分隔符后丢层级。
function decodeOriginPath(raw) {
  return String(raw || '')
    .split('/')
    .map((segment) => decodeValue(segment))
    .join('/');
}

// 文件名消毒：去掉路径、控制字符与 Windows 保留字符，保留中文，限制长度。
function sanitizeName(raw, fallback = 'mirror.bin') {
  let name = String(raw || '')
    .split(/[\\/]/)
    .pop();
  name = name
    .replace(/[\u0000-\u001f\u007f]/g, '')
    .replace(/[<>:"|?*]/g, '_')
    .replace(/\s+/g, ' ')
    .trim();
  if (!name) name = fallback;
  if (name.length > NAME_LIMIT) {
    const dot = name.lastIndexOf('.');
    const ext = dot > 0 && name.length - dot <= 16 ? name.slice(dot) : '';
    name = name.slice(0, NAME_LIMIT - ext.length) + ext;
  }
  return name;
}

function newFileId() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  const stamp =
    `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}` +
    `${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}${pad(d.getUTCSeconds())}`;
  return `f_${stamp}_${crypto.randomBytes(4).toString('hex')}`;
}

function dayDir(date = new Date()) {
  const pad = (n) => String(n).padStart(2, '0');
  return `${date.getFullYear()}${pad(date.getMonth() + 1)}${pad(date.getDate())}`;
}

function absMirrorPath(config, record) {
  return path.resolve(config.mirrorRoot, record.storedPath);
}

function sumBytes(store) {
  return Object.values(store.data.files || {}).reduce((total, item) => total + Number(item.size || 0), 0);
}

function usagePayload(config, store) {
  const max = maxBytesOf(config);
  const used = sumBytes(store);
  return {
    usedBytes: used,
    maxBytes: max,
    remainingBytes: Math.max(0, max - used),
    count: Object.keys(store.data.files || {}).length,
    percent: max ? Math.min(100, Math.round((used / max) * 1000) / 10) : 0,
  };
}

// logs/files.log：追加 JSON 行，失败不影响主流程。
function createFileLog(config) {
  const dir = path.join(config.root, 'logs');
  fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
  const file = path.join(dir, 'files.log');
  let queue = Promise.resolve();
  function write(entry) {
    const record = { ts: nowIso(), ...entry };
    queue = queue.then(
      () =>
        new Promise((resolve) => {
          fs.appendFile(file, JSON.stringify(record) + '\n', { mode: 0o600 }, () => resolve());
        })
    );
    return queue;
  }
  return { write, file };
}

// 把可读流写入临时文件，同时统计大小与 sha256；超过上限立即中止。
async function saveStream(readable, tempPath, limitBytes) {
  let size = 0;
  const hash = crypto.createHash('sha256');
  let truncated = false;
  const meter = new Transform({
    transform(chunk, enc, cb) {
      size += chunk.length;
      if (size > limitBytes) {
        truncated = true;
        return cb(new ApiError(413, 300004, `镜像文件超过总量上限 ${limitBytes} 字节`, null));
      }
      hash.update(chunk);
      return cb(null, chunk);
    },
  });
  await pipeline(readable, meter, fs.createWriteStream(tempPath, { mode: 0o600 }));
  if (truncated) throw new ApiError(413, 300004, '镜像文件超过总量上限');
  return { size, sha256: hash.digest('hex') };
}

function requireServiceToken(config) {
  return (req, res, next) => {
    const expected = String((config.files && config.files.serviceToken) || '');
    const given = String(req.get('x-service-token') || '');
    const a = Buffer.from(given);
    const b = Buffer.from(expected);
    if (!expected || !given || a.length !== b.length || !crypto.timingSafeEqual(a, b)) {
      return next(new ApiError(401, 400001, '服务令牌无效'));
    }
    return next();
  };
}

// 空间不足时按 createdAt 最旧优先淘汰，只作用于 mirror 目录。
function planEvictions(store, incomingSize, maxBytes) {
  const used = sumBytes(store);
  if (incomingSize > maxBytes) {
    throw new ApiError(413, 300004, `单个文件超过镜像总量上限 ${maxBytes} 字节`);
  }
  const items = Object.values(store.data.files || {}).sort(
    (a, b) => String(a.createdAt).localeCompare(String(b.createdAt)) || String(a.id).localeCompare(String(b.id))
  );
  const evicted = [];
  let projected = used;
  for (const item of items) {
    if (projected + incomingSize <= maxBytes) break;
    evicted.push(item);
    projected -= Number(item.size || 0);
  }
  return { evicted, projected: projected + incomingSize };
}

function createFilesRouter({ config, store, audit }) {
  const router = express.Router();
  const log = createFileLog(config);
  let finalizeQueue = Promise.resolve();

  // 串行化「淘汰 + 落库」，避免并发上传互相踩总量。
  function serializedFinalize(task) {
    const run = task();
    finalizeQueue = finalizeQueue.then(() => run, () => run);
    return finalizeQueue;
  }

  function removeFileQuietly(config, record) {
    const abs = absMirrorPath(config, record);
    try {
      fs.unlinkSync(abs);
    } catch (_) {
      /* 文件可能已不存在 */
    }
    try {
      fs.rmdirSync(path.dirname(abs));
    } catch (_) {
      /* 目录非空或无权限 */
    }
  }

  async function commit({ tempPath, name, size, sha256, originServer, originPath, actor, ip }) {
    const id = newFileId();
    const relPath = path.join(dayDir(), `${id}_${name}`);
    const abs = path.resolve(config.mirrorRoot, relPath);
    const max = maxBytesOf(config);

    return serializedFinalize(async () => {
      const { evicted } = planEvictions(store, size, max);
      fs.mkdirSync(path.dirname(abs), { recursive: true, mode: 0o700 });
      fs.renameSync(tempPath, abs);

      // 落库与淘汰元数据原子化；文件删除放在持久化之后。
      const result = await store.mutate(() => {
        const db = store.data;
        if (!db.files) db.files = {};
        for (const item of evicted) delete db.files[item.id];
        const record = {
          id,
          name,
          size,
          sha256,
          createdAt: nowIso(),
          originServer: originServer || '',
          originPath: originPath || '',
          storedPath: relPath,
          uploadedBy: actor || '',
          uploadedIp: ip || '',
        };
        db.files[id] = record;
        return { record, evicted };
      });

      for (const item of result.evicted) {
        removeFileQuietly(config, item);
        await log.write({ action: 'cleanup', id: item.id, name: item.name, size: item.size, reason: 'cap' });
        await audit.log({
          actor: 'system',
          ip: '',
          action: 'file_cleanup',
          target: item.id,
          before: { name: item.name, size: item.size },
          after: { reason: 'cap_exceeded', freeBeforeBytes: null },
        });
      }

      const base = String(config.publicBaseUrl || '').replace(/\/+$/, '');
      await log.write({ action: 'mirror', id, name, size, sha256, originServer: originServer || '', from: ip || '' });
      await audit.log({
        actor: actor || 'system',
        ip: ip || '',
        action: 'file_mirror',
        target: id,
        before: null,
        after: { name, size, sha256, originServer: originServer || '', originPath: originPath || '' },
      });

      return {
        record: result.record,
        evicted: result.evicted.map((item) => ({ id: item.id, name: item.name, size: item.size })),
        downloadUrl: `${base}/api/files/${id}/download`,
      };
    });
  }

  // POST /api/files/mirror：服务令牌 + multipart(file) 或原始 body。
  router.post(
    '/api/files/mirror',
    requireServiceToken(config),
    wrap(async (req, res) => {
      const max = maxBytesOf(config);
      const tempPath = path.join(config.mirrorRoot, '.tmp', `${crypto.randomBytes(8).toString('hex')}.part`);
      let headerName = decodeValue(req.get('x-file-name') || '');
      let originServer = decodeValue(req.get('x-origin-server') || '');
      let originPath = decodeOriginPath(req.get('x-origin-path') || '');
      let name = headerName;
      let saved = null;

      try {
        const contentType = String(req.get('content-type') || '');
        if (contentType.startsWith('multipart/form-data')) {
          const bb = Busboy({
            headers: req.headers,
            defParamCharset: 'utf8',
            limits: { files: 1, fields: 20, fieldSize: 8192 },
          });
          let fileTask = null;
          let fileLimitHit = false;
          bb.on('field', (field, value) => {
            const key = String(field || '').toLowerCase();
            if (key === 'x-file-name' || key === 'file-name' || key === 'name') name = decodeValue(value);
            else if (key === 'x-origin-server' || key === 'origin-server') originServer = decodeValue(value);
            else if (key === 'x-origin-path' || key === 'origin-path') originPath = decodeOriginPath(value);
          });
          bb.on('file', (field, file, info) => {
            if (!name) name = decodeValue(info.filename || '');
            file.on('limit', () => {
              fileLimitHit = true;
            });
            fileTask = saveStream(file, tempPath, max);
          });
          const finished = new Promise((resolve, reject) => {
            bb.on('close', resolve);
            bb.on('error', reject);
            req.on('aborted', () => reject(new ApiError(400, 400005, '上传被中断')));
          });
          req.pipe(bb);
          await finished;
          if (!fileTask) throw new ApiError(200, 400005, 'multipart 缺少 file 字段');
          saved = await fileTask;
          if (fileLimitHit) throw new ApiError(413, 300004, '镜像文件超过总量上限');
        } else {
          if (!name) throw new ApiError(200, 400005, '缺少 X-File-Name 请求头（原始 body 上传时必须提供）');
          saved = await saveStream(req, tempPath, max);
        }

        if (!saved || saved.size <= 0) throw new ApiError(200, 400005, '文件为空');
        const safeName = sanitizeName(name);
        const result = await commit({
          tempPath,
          name: safeName,
          size: saved.size,
          sha256: saved.sha256,
          originServer,
          originPath,
          actor: 'service',
          ip: clientIp(req),
        });
        ok(
          res,
          {
            id: result.record.id,
            name: result.record.name,
            size: result.record.size,
            sha256: result.record.sha256,
            createdAt: result.record.createdAt,
            downloadUrl: result.downloadUrl,
            evicted: result.evicted,
          },
          '镜像上传成功'
        );
      } catch (err) {
        try {
          if (fs.existsSync(tempPath)) fs.unlinkSync(tempPath);
        } catch (_) {
          /* ignore */
        }
        throw err;
      }
    })
  );

  // GET /api/files/:id/download：给本地服务的带令牌下载（支持 Range/HEAD）。
  const serviceDownload = wrap(async (req, res, next) => {
    const record = (store.data.files || {})[req.params.id];
    if (!record) throw new ApiError(404, 400018, '镜像文件不存在');
    const abs = absMirrorPath(config, record);
    if (!abs.startsWith(path.resolve(config.mirrorRoot) + path.sep) || !fs.existsSync(abs)) {
      throw new ApiError(410, 400018, '镜像文件已被清理');
    }
    const filename = record.name || path.basename(abs);
    const asciiName = filename.replace(/[^\x20-\x7e]/g, '_').replace(/["\\]/g, '_');
    res.setHeader('Content-Type', 'application/octet-stream');
    res.setHeader(
      'Content-Disposition',
      `attachment; filename="${asciiName}"; filename*=UTF-8''${encodeURIComponent(filename)}`
    );
    res.setHeader('Cache-Control', 'no-store');
    res.sendFile(abs, (err) => {
      if (!err) return;
      if (!res.headersSent) return next(err);
      return undefined;
    });
  });

  router.get('/api/files/:id/download', requireServiceToken(config), serviceDownload);
  router.head('/api/files/:id/download', requireServiceToken(config), serviceDownload);

  return router;
}

// ---- 管理端（files 角色）----
function createFilesAdminRouter({ config, store, audit }) {
  const router = express.Router();

  router.get(
    '/files/list',
    wrap((req, res) => {
      const q = String(req.query.q || '').trim().toLowerCase();
      const sort = String(req.query.sort || 'createdAt');
      const order = String(req.query.order || 'desc') === 'asc' ? 1 : -1;
      const page = Math.max(1, Number.parseInt(req.query.page, 10) || 1);
      const pageSize = Math.min(100, Math.max(1, Number.parseInt(req.query.pageSize, 10) || 20));

      let items = Object.values(store.data.files || {});
      if (q) {
        items = items.filter((item) =>
          [item.name, item.originServer, item.originPath, item.id]
            .filter(Boolean)
            .some((value) => String(value).toLowerCase().includes(q))
        );
      }
      const key = ['name', 'size', 'createdAt', 'originServer'].includes(sort) ? sort : 'createdAt';
      items.sort((a, b) => {
        const x = a[key];
        const y = b[key];
        if (key === 'size') return (Number(x) - Number(y)) * order;
        return String(x || '').localeCompare(String(y || '')) * order;
      });
      const total = items.length;
      const start = (page - 1) * pageSize;
      const pageItems = items.slice(start, start + pageSize).map((item) => ({
        id: item.id,
        name: item.name,
        size: item.size,
        sha256: item.sha256,
        createdAt: item.createdAt,
        originServer: item.originServer || '',
        originPath: item.originPath || '',
        downloadUrl: `/api/admin/files/${item.id}/download`,
      }));
      ok(res, { items: pageItems, total, page, pageSize, usage: usagePayload(config, store) });
    })
  );

  router.get(
    '/files/usage',
    wrap((req, res) => ok(res, usagePayload(config, store)))
  );

  const adminDownload = wrap(async (req, res, next) => {
    const record = (store.data.files || {})[req.params.id];
    if (!record) throw new ApiError(404, 400018, '镜像文件不存在');
    const abs = absMirrorPath(config, record);
    if (!abs.startsWith(path.resolve(config.mirrorRoot) + path.sep) || !fs.existsSync(abs)) {
      throw new ApiError(410, 400018, '镜像文件已被清理');
    }
    const filename = record.name || path.basename(abs);
    const asciiName = filename.replace(/[^\x20-\x7e]/g, '_').replace(/["\\]/g, '_');
    res.setHeader('Content-Type', 'application/octet-stream');
    res.setHeader(
      'Content-Disposition',
      `attachment; filename="${asciiName}"; filename*=UTF-8''${encodeURIComponent(filename)}`
    );
    res.setHeader('Cache-Control', 'no-store');
    res.sendFile(abs, (err) => {
      if (!err) return;
      if (!res.headersSent) return next(err);
      return undefined;
    });
  });

  router.get('/files/:id/download', adminDownload);
  router.head('/files/:id/download', adminDownload);

  router.delete(
    '/files/:id',
    wrap(async (req, res) => {
      const id = req.params.id;
      const record = (store.data.files || {})[id];
      if (!record) throw new ApiError(404, 400018, '镜像文件不存在');
      await store.mutate(() => {
        delete store.data.files[id];
      });
      try {
        fs.unlinkSync(absMirrorPath(config, record));
      } catch (_) {
        /* 文件可能已不存在 */
      }
      try {
        fs.rmdirSync(path.dirname(absMirrorPath(config, record)));
      } catch (_) {
        /* 目录非空 */
      }
      const log = createFileLog(config);
      await log.write({ action: 'delete', id, name: record.name, size: record.size, by: req.actor });
      await audit.log({
        actor: req.actor,
        ip: req.clientIp,
        action: 'file_delete',
        target: id,
        before: { name: record.name, size: record.size },
        after: null,
      });
      ok(res, { id }, '镜像文件已删除');
    })
  );

  return router;
}

// 巡检：超过上限时按 createdAt 最旧优先删除（供手动/每小时兜底复用）。
async function enforceMirrorCap({ config, store, audit, dryRun = false, reason = 'sweep' }) {
  const max = maxBytesOf(config);
  const used = sumBytes(store);
  if (used <= max) {
    return { usedBytes: used, maxBytes: max, deleted: [], freedBytes: 0, dryRun };
  }

  const items = Object.values(store.data.files || {}).sort((a, b) =>
    String(a.createdAt).localeCompare(String(b.createdAt)) || String(a.id).localeCompare(String(b.id))
  );
  const picked = [];
  let projected = used;
  for (const item of items) {
    if (projected <= max) break;
    picked.push(item);
    projected -= Number(item.size || 0);
  }

  const deleted = [];
  let freedBytes = 0;
  for (const item of picked) {
    if (!dryRun) {
      await store.mutate(() => {
        delete store.data.files[item.id];
      });
      try {
        fs.unlinkSync(absMirrorPath(config, item));
      } catch (_) {
        /* ignore */
      }
      try {
        fs.rmdirSync(path.dirname(absMirrorPath(config, item)));
      } catch (_) {
        /* ignore */
      }
      await audit.log({
        actor: 'system',
        ip: '',
        action: 'file_cleanup',
        target: item.id,
        before: { name: item.name, size: item.size },
        after: { reason },
      });
    }
    freedBytes += Number(item.size || 0);
    deleted.push({ id: item.id, name: item.name, size: item.size });
  }

  if (!dryRun && deleted.length) {
    await createFileLog(config).write({ action: 'cleanup', reason, deleted });
  }
  return { usedBytes: used, maxBytes: max, deleted, freedBytes, dryRun };
}

function startFilesScheduler({ config, store, audit }) {
  const minutes = Number(config.files && config.files.checkIntervalMinutes) || 60;
  const timer = setInterval(() => {
    enforceMirrorCap({ config, store, audit, dryRun: false, reason: 'sweep' }).catch((err) => {
      console.error('[files] 镜像巡检失败', err && err.message);
    });
  }, minutes * 60 * 1000);
  timer.unref();
  return timer;
}

module.exports = {
  createFilesRouter,
  createFilesAdminRouter,
  enforceMirrorCap,
  startFilesScheduler,
  usagePayload,
  sanitizeName,
  maxBytesOf,
};
