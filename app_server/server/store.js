'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const { ensureDir, writeFilePrivate } = require('./config');

const PLATFORMS = ['windows', 'apk', 'ios', 'macos', 'linux'];
// ABI 轨道：release 按 CPU 架构分轨发布；'universal' 是老客户端/未分轨平台的
// 兜底轨。取用语义：客户端带 abi 时精确取该轨，**该轨无记录才回落 universal**，
// 不比较 build——某 abi 轨一旦发布过就始终以该轨为准，避免"v7a 轨还没发到
// build=N、universal 已到"时 32 位板拿到装不上的 universal 包。
const ABIS = ['universal', 'armeabi-v7a', 'arm64-v8a', 'x86_64'];
const ROLES = ['admin', 'apps', 'files'];
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
    version: 2,
    createdAt: nowIso(),
    updatedAt: nowIso(),
    applications: {},
    releases: {},
    latest: {},
    accounts: [],
    tokens: {},
    files: {},
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

// ABI 归一：空/缺省一律视为 'universal'（兼容老记录与不带 abi 的老客户端）。
function normalizeAbi(raw) {
  const abi = String(raw || '').trim().toLowerCase();
  if (!abi) return 'universal';
  if (!ABIS.includes(abi)) throw new DataError(400005, `不支持的 ABI：${raw}`);
  return abi;
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

function normalizeRoles(input) {
  if (!Array.isArray(input)) throw new DataError(400005, 'roles 必须为数组');
  const out = [];
  for (const raw of input) {
    const role = String(raw || '').trim().toLowerCase();
    if (!ROLES.includes(role)) throw new DataError(400011, `未知角色：${raw}`);
    if (!out.includes(role)) out.push(role);
  }
  if (!out.length) throw new DataError(400005, 'roles 至少选择一个角色');
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
    let migrated = false;
    if (fs.existsSync(this.dbPath)) {
      const raw = JSON.parse(fs.readFileSync(this.dbPath, 'utf8'));
      this.db = { ...emptyDb(), ...raw };
      this.db.applications = raw.applications || {};
      this.db.releases = raw.releases || {};
      this.db.latest = raw.latest || {};
      this.db.stats = raw.stats || { daily: {} };
      this.db.accounts = Array.isArray(raw.accounts) ? raw.accounts : [];
      this.db.tokens = raw.tokens || {};
      this.db.files = raw.files || {};

      // 向后兼容：v1 的单 admin 迁移为 accounts[0]，授予三角色，保留原密码哈希与会话状态。
      if (!this.db.accounts.length && raw.admin) {
        this.db.accounts = [
          {
            username: raw.admin.username,
            passwordHash: raw.admin.passwordHash,
            roles: ['admin', 'apps', 'files'],
            createdAt: raw.admin.createdAt || nowIso(),
            updatedAt: nowIso(),
            disabled: false,
            lastLoginAt: null,
            mustChangePassword: Boolean(raw.admin.mustChangePassword),
            authEpoch: Number(raw.admin.authEpoch) || 1,
            sessionId: raw.admin.sessionId || null,
            sessionIssuedAt: raw.admin.sessionIssuedAt || null,
            sessionExpiresAt: raw.admin.sessionExpiresAt || null,
          },
        ];
        delete this.db.admin;
        this.db.version = 2;
        migrated = true;
      }
      // ABI 轨道迁移（幂等，无版本号依赖）：老 release 补 abi='universal'；
      // latest[app][platform] 由「直接存 releaseId」升级为 { [abi]: releaseId }
      // 槽位结构，老指针归入 universal 轨。
      let migratedAbi = false;
      for (const r of Object.values(this.db.releases)) {
        if (r.abi === undefined || r.abi === null || r.abi === '') {
          r.abi = 'universal';
          migratedAbi = true;
        }
      }
      for (const byPlatform of Object.values(this.db.latest)) {
        if (!byPlatform || typeof byPlatform !== 'object') continue;
        for (const [platform, value] of Object.entries(byPlatform)) {
          if (typeof value === 'string') {
            byPlatform[platform] = { universal: value };
            migratedAbi = true;
          }
        }
      }
      if (migratedAbi) migrated = true;

      if (migrated) this.persistSync();
      this.migratedFromV1 = migrated;
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

  // ---- 账号 ----
  findAccount(username) {
    return (this.db.accounts || []).find((a) => a.username === username) || null;
  }

  listAccounts() {
    return [...(this.db.accounts || [])].sort((a, b) => String(a.createdAt).localeCompare(String(b.createdAt)));
  }

  assertAccountUsername(username) {
    const value = String(username || '').trim();
    if (!/^[A-Za-z0-9][A-Za-z0-9._-]{1,31}$/.test(value)) {
      throw new DataError(400005, '用户名需为 2-32 位字母/数字/点/下划线/连字符，且以字母或数字开头');
    }
    return value;
  }

  createAccount({ username, passwordHash, roles }) {
    const name = this.assertAccountUsername(username);
    if (this.findAccount(name)) throw new DataError(400016, '账号已存在', 409);
    const account = {
      username: name,
      passwordHash,
      roles: normalizeRoles(roles),
      createdAt: nowIso(),
      updatedAt: nowIso(),
      disabled: false,
      lastLoginAt: null,
      mustChangePassword: false,
      authEpoch: 1,
      sessionId: null,
      sessionIssuedAt: null,
      sessionExpiresAt: null,
    };
    this.db.accounts.push(account);
    return account;
  }

  updateAccountRoles(username, roles) {
    const account = this.findAccount(username);
    if (!account) throw new DataError(400014, '账号不存在', 404);
    const next = normalizeRoles(roles);
    const admins = (this.db.accounts || []).filter((a) => !a.disabled && a.roles.includes('admin'));
    if (account.roles.includes('admin') && !next.includes('admin') && admins.length <= 1) {
      throw new DataError(400017, '至少保留一个 admin 角色账号');
    }
    account.roles = next;
    account.authEpoch = Number(account.authEpoch || 1) + 1;
    account.sessionId = null;
    account.sessionIssuedAt = null;
    account.sessionExpiresAt = null;
    account.updatedAt = nowIso();
    return account;
  }

  resetAccountPassword(username, passwordHash) {
    const account = this.findAccount(username);
    if (!account) throw new DataError(400014, '账号不存在', 404);
    account.passwordHash = passwordHash;
    account.mustChangePassword = true;
    account.authEpoch = Number(account.authEpoch || 1) + 1;
    account.sessionId = null;
    account.sessionIssuedAt = null;
    account.sessionExpiresAt = null;
    account.updatedAt = nowIso();
    return account;
  }

  deleteAccount(username) {
    const account = this.findAccount(username);
    if (!account) throw new DataError(400014, '账号不存在', 404);
    const admins = (this.db.accounts || []).filter((a) => a.roles.includes('admin'));
    if (account.roles.includes('admin') && admins.length <= 1) {
      throw new DataError(400017, '至少保留一个 admin 角色账号，无法删除');
    }
    this.db.accounts = this.db.accounts.filter((a) => a.username !== username);
    return true;
  }

  // ---- 临时访问口令 ----
  getToken(tokenId) {
    return (this.db.tokens || {})[tokenId] || null;
  }

  listTokens() {
    return Object.values(this.db.tokens || {}).sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));
  }

  createTokenRecord(record) {
    if (!this.db.tokens) this.db.tokens = {};
    this.db.tokens[record.id] = record;
    return record;
  }

  revokeToken(tokenId) {
    const token = this.getToken(tokenId);
    if (!token) throw new DataError(400013, '口令不存在', 404);
    token.revokedAt = token.revokedAt || nowIso();
    return token;
  }

  markTokenUsed(tokenId) {
    const token = this.getToken(tokenId);
    if (!token) return null;
    token.lastUsedAt = nowIso();
    if (!token.usedAt) token.usedAt = token.lastUsedAt;
    token.useCount = Number(token.useCount || 0) + 1;
    return token;
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

  // build 唯一性按 (app, platform, abi) 轨道：同一 build 的不同架构变体可共存
  //（一次更新的 v7a/arm64 包 build 号相同、abi 不同）。
  findReleaseByBuild(appId, platform, build, abi = 'universal') {
    const a = normalizeAbi(abi);
    return Object.values(this.db.releases).find(
      (r) =>
        r.appId === appId &&
        r.platform === platform &&
        r.build === Number(build) &&
        normalizeAbi(r.abi) === a
    );
  }

  // build 单调递增校验（按 abi 轨道）；回滚是唯一允许指向更小 build 的操作。
  assertBuildMonotonic(app, platform, build, { rollback = false, abi = 'universal' } = {}) {
    const latestId = this.getLatestId(app.appId, platform, abi);
    if (!latestId) return true;
    const latest = this.db.releases[latestId];
    if (!latest) return true;
    if (rollback) return true;
    if (Number(build) <= latest.build) {
      throw new DataError(300003, `build 必须大于该 ABI 轨道当前 latest(${latest.build})；如需回退请使用 rollback`);
    }
    return true;
  }

  createReleaseRecord(input) {
    const app = this.getApplication(input.appId);
    const platform = this.assertPlatformAllowed(app, input.platform);
    const abi = normalizeAbi(input.abi);
    const meta = validateReleaseMeta(input);

    if (platform === 'ios' && input.distribution !== 'external') {
      throw new DataError(300009, 'iOS 只接受外部链接版本（TestFlight / App Store）');
    }
    if (platform !== 'ios' && input.distribution !== 'file') {
      throw new DataError(400005, '除 iOS 外必须上传安装包文件');
    }
    if (this.findReleaseByBuild(app.appId, platform, meta.build, abi)) {
      throw new DataError(300002, `该平台该 ABI 已存在 build=${meta.build} 的版本`);
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
      abi,
      forceUpdate: input.forceUpdate === true, // 上传时预勾选；发布时再按 publish 传参决定
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

  // latest 是 { [abi]: releaseId } 槽位结构（见 init 迁移）。
  getLatestId(appId, platform, abi = 'universal') {
    const byAbi = (this.db.latest[appId] || {})[platform];
    if (!byAbi) return null;
    if (typeof byAbi === 'string') return byAbi; // 迁移前旧结构，按 universal 轨读
    return byAbi[normalizeAbi(abi)] || null;
  }

  getLatest(appId, platform, abi = 'universal') {
    const id = this.getLatestId(appId, platform, abi);
    return id ? this.db.releases[id] || null : null;
  }

  // 客户端取 latest：先按请求 abi 精确取该轨，**该轨无记录才回落 universal**，
  // 不比较 build——某 abi 轨一旦发布过即以该轨为准，避免发布顺序差异让 32 位
  // 板拿到装不上的 universal 包。abi 空/非法值由 normalizeAbi 归到 universal。
  getLatestForAbi(appId, platform, abi) {
    const a = normalizeAbi(abi);
    if (a === 'universal') return this.getLatest(appId, platform, 'universal');
    return this.getLatest(appId, platform, a) || this.getLatest(appId, platform, 'universal');
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
    if (release.distribution === 'file' && !release.fileAvailable) {
      throw new DataError(300008, '安装包文件不可用，请重新上传', 410);
    }
    if (!rollback) {
      this.assertBuildMonotonic(app, release.platform, release.build, { abi: release.abi });
    }
    const abi = normalizeAbi(release.abi);
    const previousId = this.getLatestId(release.appId, release.platform, abi);
    if (previousId && previousId !== release.releaseId) {
      const previous = this.db.releases[previousId];
      if (previous) {
        previous.status = 'archived';
        previous.archivedAt = nowIso();
        previous.forceUpdate = false;
      }
    }
    if (!this.db.latest[release.appId]) this.db.latest[release.appId] = {};
    const byPlatform = this.db.latest[release.appId];
    if (!byPlatform[release.platform] || typeof byPlatform[release.platform] === 'string') {
      const legacy = typeof byPlatform[release.platform] === 'string' ? byPlatform[release.platform] : null;
      byPlatform[release.platform] = legacy ? { universal: legacy } : {};
    }
    byPlatform[release.platform][abi] = release.releaseId; // 只切本 abi 轨道的指针
    release.status = 'published';
    release.archivedAt = null;
    release.publishedAt = release.publishedAt || nowIso();
    const nextForce = forceUpdate === undefined ? Boolean(release.forceUpdate) : Boolean(forceUpdate);
    release.forceUpdate = release.platform === 'ios' ? false : nextForce;
    return release;
  }

  latestSummary(appId) {
    const out = {};
    for (const platform of PLATFORMS) {
      // 摘要优先 universal 轨（老语义）；该轨没有则取任一 abi 轨 build 最大者。
      let latest = this.getLatest(appId, platform, 'universal');
      if (!latest) {
        latest = Object.values(this.db.releases)
          .filter((r) => r.appId === appId && r.platform === platform && r.status === 'published')
          .sort((a, b) => b.build - a.build)[0] || null;
      }
      if (latest) {
        out[platform] = {
          releaseId: latest.releaseId,
          version: latest.version,
          build: latest.build,
          abi: latest.abi || 'universal',
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
  ABIS,
  normalizeAbi,
  ROLES,
  APP_ID_RE,
  VERSION_RE,
  validateReleaseMeta,
  assertAppId,
  normalizePlatforms,
  normalizeRoles,
  nowIso,
};
