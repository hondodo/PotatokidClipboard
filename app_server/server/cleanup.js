'use strict';

const fs = require('fs');
const path = require('path');

const { freeBytes, dirSizeBytes } = require('./apiutil');
const { ensureDir } = require('./config');
const { nowIso } = require('./store');

function cleanupLogFile(config) {
  return path.join(config.root, 'logs', 'cleanup.log');
}

function appendCleanupLog(config, entry) {
  const file = cleanupLogFile(config);
  ensureDir(path.dirname(file), 0o700);
  try {
    fs.appendFileSync(file, JSON.stringify({ ts: nowIso(), ...entry }) + '\n', { mode: 0o600 });
  } catch (_) {
    /* 日志失败不影响清理 */
  }
}

function archivedTime(release) {
  return release.archivedAt || release.createdAt || '';
}

// 按 7.3.1 顺序：组内 archivedAt 升序，跨组轮询取最旧，绝不包含 latest。
function listCandidates(store) {
  const groups = new Map();
  for (const release of Object.values(store.data.releases)) {
    if (release.status !== 'archived' || !release.fileAvailable) continue;
    const key = `${release.appId}|${release.platform}`;
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(release);
  }
  for (const items of groups.values()) items.sort((a, b) => archivedTime(a).localeCompare(archivedTime(b)));
  const ordered = [...groups.values()].sort((a, b) => archivedTime(a[0]).localeCompare(archivedTime(b[0])));

  const out = [];
  let round = 0;
  let more = true;
  while (more) {
    more = false;
    for (const items of ordered) {
      if (items.length > round) {
        out.push(items[round]);
        more = true;
      }
    }
    round += 1;
  }
  return out;
}

function releasePath(config, release) {
  const abs = path.resolve(config.storageRoot, release.storedPath || '');
  if (!abs.startsWith(path.resolve(config.storageRoot) + path.sep)) return null;
  return abs;
}

function fileSize(abs) {
  try {
    return fs.statSync(abs).size;
  } catch (_) {
    return 0;
  }
}

// 删除单个 release 的物理文件并保留元数据；返回释放字节数。
async function deleteReleaseFile({ config, store, release, reason, freeBeforeBytes, actor, ip }) {
  const abs = releasePath(config, release);
  let bytes = Number(release.size) || 0;
  if (abs) {
    bytes = fileSize(abs);
    try {
      fs.unlinkSync(abs);
      const dir = path.dirname(abs);
      if (fs.readdirSync(dir).length === 0) fs.rmdirSync(dir);
    } catch (err) {
      if (err.code !== 'ENOENT') {
        console.error('[cleanup] 删除文件失败', abs, err.message);
        return 0;
      }
    }
  }
  const now = nowIso();
  await store.mutate(() => {
    release.fileAvailable = false;
    release.fileDeletedAt = now;
  });
  appendCleanupLog(config, {
    releaseId: release.releaseId,
    appId: release.appId,
    platform: release.platform,
    build: release.build,
    sizeBytes: bytes,
    archivedAt: release.archivedAt || null,
    deletedAt: now,
    reason,
    freeBeforeBytes: freeBeforeBytes === undefined ? null : freeBeforeBytes,
    freeAfterBytes: freeBytes(config.root),
  });
  return bytes;
}

// 发布后维持 keepPrevious：同 app+platform+abi 轨道只保留最新的 N 个 archived 文件。
async function enforceKeepPrevious({ config, store, audit, appId, platform, abi = 'universal', actor = 'system', ip = '' }) {
  const keep = Number(config.retention && config.retention.keepPrevious);
  const keepCount = Number.isFinite(keep) && keep >= 0 ? keep : 1;
  const abiKey = String(abi || 'universal').toLowerCase();
  const archived = Object.values(store.data.releases)
    .filter(
      (r) =>
        r.appId === appId &&
        r.platform === platform &&
        String(r.abi || 'universal').toLowerCase() === abiKey &&
        r.status === 'archived' &&
        r.fileAvailable
    )
    .sort((a, b) => archivedTime(a).localeCompare(archivedTime(b)));
  const removable = archived.slice(0, Math.max(0, archived.length - keepCount));
  let freedBytes = 0;
  const deleted = [];
  for (const release of removable) {
    const bytes = await deleteReleaseFile({
      config,
      store,
      release,
      reason: 'keep_previous_limit',
      freeBeforeBytes: freeBytes(config.root),
      actor,
      ip,
    });
    freedBytes += bytes;
    deleted.push({ releaseId: release.releaseId, appId, platform, abi: abiKey, build: release.build, size: bytes });
  }
  if (deleted.length) {
    await audit.log({
      actor,
      ip,
      action: 'cleanup',
      target: `${appId}|${platform}|${abiKey}`,
      before: null,
      after: { reason: 'keep_previous_limit', keepPrevious: keepCount, abi: abiKey, deleted, freedBytes },
    });
  }
  return { deleted, freedBytes };
}

// 磁盘余量不足时清理 archived，删到 >= target 即停；dryRun 只返回计划。
async function runCleanup({ config, store, audit, actor = 'system', ip = '', dryRun = false, targetFreeBytes, reason = 'disk_pressure' }) {
  const target = Number(targetFreeBytes) || Number(config.retention.cleanupTargetFreeBytes) || 1610612736;
  const freeBefore = freeBytes(config.root);
  const freeStart = freeBefore === null ? 0 : freeBefore;
  const planned = [];
  let projected = freeStart;
  let freedBytes = 0;

  if (freeBefore !== null && freeBefore < target) {
    for (const release of listCandidates(store)) {
      if (projected >= target) break;
      const abs = releasePath(config, release);
      const size = abs ? fileSize(abs) : Number(release.size) || 0;
      planned.push({
        releaseId: release.releaseId,
        appId: release.appId,
        platform: release.platform,
        build: release.build,
        archivedAt: release.archivedAt,
        sizeBytes: size,
      });
      projected += size;
      if (dryRun) continue;
      const freed = await deleteReleaseFile({
        config,
        store,
        release,
        reason,
        freeBeforeBytes: freeBytes(config.root),
        actor,
        ip,
      });
      freedBytes += freed;
      projected = freeBytes(config.root) === null ? projected : freeBytes(config.root);
    }
  }

  const freeAfter = freeBytes(config.root);
  if (!dryRun) {
    await audit.log({
      actor,
      ip,
      action: 'cleanup',
      target: 'storage',
      before: { diskFreeBytes: freeBefore, targetFreeBytes: target },
      after: { reason, deleted: planned, freedBytes, diskFreeBytes: freeAfter },
    });
  }
  return {
    dryRun,
    reason,
    targetFreeBytes: target,
    diskFreeBefore: freeBefore,
    diskFreeAfter: freeAfter,
    candidates: planned,
    freedBytes,
    lowBefore: freeBefore !== null && freeBefore < target,
    lowAfter: freeAfter !== null && freeAfter < Number(config.retention.stopUploadFreeBytes),
  };
}

// 清理超期草稿（默认 7 天），保留元数据之外不做额外策略。
async function cleanupDrafts({ config, store, audit }) {
  const days = Number(config.retention && config.retention.draftDays);
  const maxDays = Number.isFinite(days) && days > 0 ? days : 7;
  const cutoff = Date.now() - maxDays * 24 * 3600 * 1000;
  const drafts = Object.values(store.data.releases).filter(
    (r) => r.status === 'draft' && Date.parse(r.createdAt) < cutoff
  );
  let freedBytes = 0;
  const deleted = [];
  for (const release of drafts) {
    const abs = releasePath(config, release);
    const size = abs ? fileSize(abs) : 0;
    if (abs) {
      try {
        fs.unlinkSync(abs);
      } catch (_) {
        /* ignore */
      }
    }
    await store.mutate(() => {
      delete store.data.releases[release.releaseId];
    });
    appendCleanupLog(config, {
      releaseId: release.releaseId,
      appId: release.appId,
      platform: release.platform,
      build: release.build,
      sizeBytes: size,
      archivedAt: null,
      deletedAt: nowIso(),
      reason: 'draft_expired',
      freeBeforeBytes: freeBytes(config.root),
      freeAfterBytes: freeBytes(config.root),
    });
    freedBytes += size;
    deleted.push({ releaseId: release.releaseId, appId: release.appId, platform: release.platform, build: release.build, size });
  }
  if (deleted.length) {
    await audit.log({
      actor: 'system',
      ip: '',
      action: 'cleanup',
      target: 'drafts',
      before: null,
      after: { reason: 'draft_expired', days: maxDays, deleted, freedBytes },
    });
  }
  return { deleted, freedBytes };
}

function maintenanceStatus({ config, store }) {
  const free = freeBytes(config.storageRoot);
  const archived = Object.values(store.data.releases).filter((r) => r.status === 'archived' && r.fileAvailable);
  const belowTarget = free !== null && free < Number(config.retention.cleanupTargetFreeBytes);
  return {
    diskFreeBytes: free,
    diskLow: belowTarget,
    stopUpload: free !== null && free < Number(config.retention.stopUploadFreeBytes),
    cleanupTargetFreeBytes: Number(config.retention.cleanupTargetFreeBytes),
    stopUploadFreeBytes: Number(config.retention.stopUploadFreeBytes),
    maxStorageBytes: Number(config.maxStorageBytes),
    storageBytes: dirSizeBytes(config.storageRoot),
    keepPrevious: Number(config.retention.keepPrevious),
    archivedCount: Object.values(store.data.releases).filter((r) => r.status === 'archived').length,
    archivedFileAvailableCount: archived.length,
    cleanupImplemented: true,
    candidates: belowTarget
      ? listCandidates(store).map((r) => ({
          releaseId: r.releaseId,
          appId: r.appId,
          platform: r.platform,
          build: r.build,
          archivedAt: r.archivedAt,
          sizeBytes: Number(r.size) || 0,
        }))
      : [],
    checkedAt: nowIso(),
  };
}

// 每小时磁盘检查 + 每 10 分钟清理超时上传。
function startCleanupScheduler({ config, store, audit, uploads }) {
  const minutes = Number(config.retention && config.retention.checkIntervalMinutes) || 60;
  const hourly = setInterval(async () => {
    try {
      await runCleanup({ config, store, audit, reason: 'disk_pressure' });
      await cleanupDrafts({ config, store, audit });
    } catch (err) {
      console.error('[cleanup] 定时任务失败', err && err.message);
    }
  }, minutes * 60 * 1000);
  hourly.unref();

  const sweep = setInterval(() => {
    try {
      if (uploads) uploads.sweepExpired();
    } catch (err) {
      console.error('[cleanup] 上传超时清理失败', err && err.message);
    }
  }, 10 * 60 * 1000);
  sweep.unref();

  return { hourly, sweep };
}

module.exports = {
  listCandidates,
  enforceKeepPrevious,
  runCleanup,
  cleanupDrafts,
  maintenanceStatus,
  startCleanupScheduler,
  deleteReleaseFile,
};
