'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { ensureDir, writeFilePrivate } = require('./config');

const PLATFORMS = ['windows', 'apk', 'ios', 'macos', 'linux'];
const APP_ID_RE = /^[a-z0-9][a-z0-9-]{1,47}$/;
const VERSION_RE = /^[0-9]+(\.[0-9]+){1,3}$/;

class DataError extends Error {
  constructor(code, msg, http = 200) {
    super(msg);
    this.code = code;
    this.http = http;
  }
}

function nowIso() {
  return new Date().toISOString();
}

function emptyDb() {
  return {
    version: 1,
    createdAt: nowIso(),
    updatedAt: nowIso(),
    applications: {},
    releases: {},
    latest: {},
    admin: null,
    stats: { daily: {} },
  };
}

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function assertAppId(appId) {
  if (typeof appId !== 'string' || !APP_ID_RE.test(appId) || appId.startsWith('-') || appId.endsWith('-')) {
    throw new DataError(400005, 'appId 必须为 2-48 位小写字母/数字/连字符，且不以连字符开头或结尾');
  }
}

function normalizePlatforms(input) {
  if (!Array.isArray(input)) throw new DataError(400005, 'platforms 必须为数组');
  const out = [];
  for (const raw of input) {
    const p = String(raw || '').trim().toLowerCase();
    if (!PLATFORMS.includes(p)) throw new DataError(300005, `不支持的平台：${raw}`);
    if (!out.includes(p)) out.push(p);
  }
  if (!out.length) throw new DataError(400005, 'platforms 至少选择一个平台');
  return out;
}

function assertText(value, field, max) {
  if (value === undefined || value === null) return '';
  if (typeof value !== 'string') throw new DataError(400005, `${field} 必须为字符串`);
  const text = value.trim();
  if (text.length > max) throw new DataError(400005, `${field} 长度不能超过 ${max} 字`);
  return text;
}

// `+N == build` 硬规则：后台不解析安装包，改由管理员录入 version/build 并显式确认。
function validateReleaseMeta({ version, build, pubspecBuildConfirmed }) {
  if (typeof version !== 'string' || !VERSION_RE.test(version)) {
    throw new DataError(400005, 'version 必须形如 1.0.3 / 1.0.3.4');
  }
  const buildNo = Number(build);
  if (!Number.isInteger(buildNo) || buildNo <= 0) {
    throw new DataError(400005, 'build 必须为正整数');
  }
  if (pubspecBuildConfirmed !== true) {
    throw new DataError(400005, '必须确认 pubspec.yaml 的 +N 与 build 一致');
  }
  return { version, build: buildNo, pubspecBuildConfirmed: true };
}

function newReleaseId() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  const stamp =
    `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}` +
    `${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}${pad(d.getUTCSeconds())}`;
  return `rel_${stamp}_${crypto.randomBytes(3).toString('hex')}`;
}

class Store {
  constructor({ dataDir }) {
    this.dataDir = dataDir;
    this.dbPath = path.join(dataDir, 'db.json');
    this.db = null;
    this.queue = Promise.resolve();
  }

  init() {
    ensureDir(this.dataDir);
    if (fs.existsSync(this.dbPath)) {
      const raw = JSON.parse(fs.readFileSync(this.dbPath, 'utf8'));
      this.db = { ...emptyDb(), ...raw };
      this.db.applications = raw.applications || {};
      this.db.releases = raw.releases || {};
      this.db.latest = raw.latest || {};
      this.db.stats = raw.stats || { daily: {} };
    } else {
      this.db = emptyDb();
      this.persistSync();
    }
    try {
      fs.chmodSync(this.dbPath, 0o600);
    } catch (_) {
      /* ignore */
    }
    return this.db;
  }

  get data() {
    return this.db;
  }

  persistSync() {
    this.db.updatedAt = nowIso();
    const tmp = `${this.dbPath}.tmp-${process.pid}-${Date.now()}`;
    writeFilePrivate(tmp, JSON.stringify(this.db, null, 2) + '\n');
    fs.renameSync(tmp, this.dbPath);
  }

  // 进程内串行锁：所有写操作排队执行，避免并发写坏 JSON。
  mutate(fn) {
    const run = async () => {
      const result = fn(this.db);
      this.persistSync();
      return result;
    };
    this.queue = this.queue.then(run, run);
    return this.queue;
  }

  // ---- 管理员 ----
  setAdmin(admin) {
    this.db.admin = admin;
  }

  // ---- 应用 ----
  listApplications() {
    return Object.values(this.db.applications).sort((a, b) => a.createdAt.localeCompare(b.createdAt));
  }

  getApplication(appId) {
    const app = this.db.applications[appId];
    if (!app) throw new DataError(300000, '应用不存在');
    return app;
  }

  getApplicationOrNull(appId) {
    return this.db.applications[appId] || null;
  }

  createApplication({ appId, name, description, platforms, enabled }) {
    assertAppId(appId);
    if (this.db.applications[appId]) throw new DataError(300010, 'appId 已存在');
    const cleanName = assertText(name, 'name', 64);
    if (!cleanName) throw new DataError(400005, 'name 不能为空');
    const app = {
      appId,
      name: cleanName,
      description: assertText(description, 'description', 500),
      platforms: normalizePlatforms(platforms),
      enabled: enabled === undefined ? true : Boolean(enabled),
      createdAt: nowIso(),
      updatedAt: nowIso(),
    };
    this.db.applications[appId] = app;
    return app;
  }

  updateApplication(appId, patch) {
    const app = this.getApplication(appId);
    if (patch.name !== undefined) {
      const name = assertText(patch.name, 'name', 64);
      if (!name) throw new DataError(400005, 'name 不能为空');
      app.name = name;
    }
    if (patch.description !== undefined) {
      app.description = assertText(patch.description, 'description', 500);
    }
    if (patch.enabled !== undefined) {
      app.enabled = Boolean(patch.enabled);
    }
    if (patch.platforms !== undefined) {
      const next = normalizePlatforms(patch.platforms);
      const removed = app.platforms.filter((p) => !next.includes(p));
      for (const platform of removed) {
        const hasRelease = Object.values(this.db.releases).some((r) => r.appId === appId && r.platform === platform);
        if (hasRelease) throw new DataError(300005, `平台 ${platform} 已有版本记录，不能从允许列表移除`);
      }
      app.platforms = next;
    }
    app.updatedAt = nowIso();
    return app;
  }

  deleteApplication(appId) {
    this.getApplication(appId);
    const hasRelease = Object.values(this.db.releases).some((r) => r.appId === appId);
    if (hasRelease) throw new DataError(300011, '该应用已有版本记录，不能删除；请改为停用');
    delete this.db.applications[appId];
    delete this.db.latest[appId];
    return true;
  }

  // ---- 版本 ----
  assertPlatformAllowed(app, platform) {
    const p = String(platform || '').trim().toLowerCase();
    if (!PLATFORMS.includes(p)) throw new DataError(300005, `不支持的平台：${platform}`);
    if (!app.platforms.includes(p)) throw new DataError(300005, `平台 ${p} 不在应用的允许列表`);
    return p;
  }

  findReleaseByBuild(appId, platform, build) {
    return Object.values(this.db.releases).find(
      (r) => r.appId === appId && r.platform === platform && r.build === Number(build)
    );
  }

  // build 单调递增校验；回滚是唯一允许指向更小 build 的操作。
  assertBuildMonotonic(app, platform, build, { rollback = false } = {}) {
    const latestId = this.getLatestId(app.appId, platform);
    if (!latestId) return true;
    const latest = this.db.releases[latestId];
    if (!latest) return true;
    if (rollback) return true;
    if (Number(build) <= latest.build) {
      throw new DataError(300003, `build 必须大于当前 latest(${latest.build})；如需回退请使用 rollback`);
    }
    return true;
  }

  createReleaseRecord(input) {
    const app = this.getApplication(input.appId);
    const platform = this.assertPlatformAllowed(app, input.platform);
    const meta = validateReleaseMeta(input);

    if (platform === 'ios' && input.distribution !== 'external') {
      throw new DataError(300009, 'iOS 只接受外部链接版本（TestFlight / App Store）');
    }
    if (platform !== 'ios' && input.distribution !== 'file') {
      throw new DataError(400005, '除 iOS 外必须上传安装包文件');
    }
    if (this.findReleaseByBuild(app.appId, platform, meta.build)) {
      throw new DataError(300002, `该平台已存在 build=${meta.build} 的版本`);
    }

    const releaseId = newReleaseId();
    const release = {
      releaseId,
      appId: app.appId,
      platform,
      version: meta.version,
      build: meta.build,
      pubspecBuildConfirmed: true,
      filename: input.filename || '',
      storedPath: input.storedPath || '',
      size: Number(input.size) || 0,
      sha256: input.sha256 || '',
      distribution: input.distribution,
      externalUrl: input.externalUrl || null,
      fileAvailable: input.fileAvailable !== false,
      fileDeletedAt: null,
      notes: assertText(input.notes, 'notes', 2000),
      forceUpdate: false, // iOS 恒为 false；其它平台发布时再决定
      status: 'draft',
      publishedAt: null,
      archivedAt: null,
      createdAt: nowIso(),
      downloadCount: 0,
      lastDownloadAt: null,
      uploadedBy: input.uploadedBy || '',
    };
    this.db.releases[releaseId] = release;
    return release;
  }

  getRelease(releaseId) {
    const release = this.db.releases[releaseId];
    if (!release) throw new DataError(300001, '版本不存在');
    return release;
  }

  getLatestId(appId, platform) {
    return (this.db.latest[appId] || {})[platform] || null;
  }

  getLatest(appId, platform) {
    const id = this.getLatestId(appId, platform);
    return id ? this.db.releases[id] || null : null;
  }

  listReleases(appId, platform) {
    return Object.values(this.db.releases)
      .filter((r) => r.appId === appId && (!platform || r.platform === platform))
      .sort((a, b) => b.build - a.build);
  }

  // 发布 = 切换 latest 指针；旧 latest 进入 archived（文件暂不删，阶段 2 由清理模块处理）。
  publishRelease(releaseId, { forceUpdate, rollback = false } = {}) {
    const release = this.getRelease(releaseId);
    const app = this.getApplication(release.appId);
    if (release.status === 'draft' && release.distribution === 'file' && !release.fileAvailable) {
      throw new DataError(300008, '安装包文件不可用，无法发布');
    }
    if (!rollback) {
      this.assertBuildMonotonic(app, release.platform, release.build);
    }
    const previousId = this.getLatestId(release.appId, release.platform);
    if (previousId) {
      const previous = this.db.releases[previousId];
      if (previous) {
        previous.status = 'archived';
        previous.archivedAt = nowIso();
        previous.forceUpdate = false;
      }
    }
    if (!this.db.latest[release.appId]) this.db.latest[release.appId] = {};
    this.db.latest[release.appId][release.platform] = release.releaseId;
    release.status = 'published';
    release.publishedAt = release.publishedAt || nowIso();
    release.forceUpdate = release.platform === 'ios' ? false : Boolean(forceUpdate);
    return release;
  }

  latestSummary(appId) {
    const out = {};
    for (const platform of PLATFORMS) {
      const latest = this.getLatest(appId, platform);
      if (latest) {
        out[platform] = {
          releaseId: latest.releaseId,
          version: latest.version,
          build: latest.build,
          publishedAt: latest.publishedAt,
          forceUpdate: latest.forceUpdate,
          fileAvailable: latest.fileAvailable,
          distribution: latest.distribution,
        };
      }
    }
    return out;
  }
}

module.exports = {
  Store,
  DataError,
  PLATFORMS,
  APP_ID_RE,
  VERSION_RE,
  validateReleaseMeta,
  assertAppId,
  normalizePlatforms,
  nowIso,
};
