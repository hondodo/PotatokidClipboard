'use strict';

const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// 部署根目录：源码位于 <root>/server/，数据位于 <root>/datas/app_update/。
// 本地调试可用 APP_SERVER_ROOT 覆盖（避免在开发机上创建 /home/honghao 路径）。
const ROOT = process.env.APP_SERVER_ROOT
  ? path.resolve(process.env.APP_SERVER_ROOT)
  : path.resolve(__dirname, '..');

const DATA_DIR = path.join(ROOT, 'datas', 'app_update');
const CONFIG_PATH = path.join(DATA_DIR, 'server.config.json');
const EXAMPLE_PATH = path.resolve(__dirname, '..', 'deploy', 'server.config.example.json');

const DEFAULTS = {
  port: 47292,
  adminPort: 47293,
  adminBind: '0.0.0.0',
  publicBaseUrl: 'http://143.203.52.132:47292',
  apiKey: '',
  adminUsername: 'honghao',
  admin: {
    ipAllowlist: [],
    singleSession: true,
    sessionHours: 12,
    cookieSecure: false,
    lockMinutes: 30,
    totpEnabled: false,
  },
  password: { minLength: 6, maxLength: 64 },
  storageRoot: path.join(ROOT, 'uploads', 'packages'),
  tmpDir: path.join(ROOT, 'uploads', 'tmp'),
  maxUploadBytes: 1073741824,
  maxStorageBytes: 4294967296,
  minFreeBytes: 1073741824,
  downloadTokenTtlSec: 600,
  download: { maxConcurrentPerIp: 4, linksPer10Min: 20 },
  chunk: {
    sizeBytes: 8388608,
    maxConcurrentPerUpload: 3,
    maxActivePerAdmin: 2,
    expireHours: 24,
    tmpQuotaBytes: 2147483648,
  },
  retention: {
    mode: 'space-adaptive',
    keepPrevious: 1,
    checkIntervalMinutes: 60,
    cleanupTargetFreeBytes: 1610612736,
    stopUploadFreeBytes: 1073741824,
    draftDays: 7,
  },
  ios: { mode: 'external-only' },
  files: {
    maxTotalBytes: 1073741824,
    serviceToken: '',
    checkIntervalMinutes: 60,
  },
  https: { enabled: false, keyPath: '', certPath: '', redirectHttp: false },
  trustProxy: false,
};

function isPlainObject(value) {
  return value !== null && typeof value === 'object' && !Array.isArray(value);
}

function mergeDefaults(target, defaults) {
  const out = { ...defaults, ...target };
  for (const key of Object.keys(defaults)) {
    if (isPlainObject(defaults[key]) && isPlainObject(target[key])) {
      out[key] = mergeDefaults(target[key], defaults[key]);
    }
  }
  return out;
}

function ensureDir(dir, mode = 0o700) {
  fs.mkdirSync(dir, { recursive: true, mode });
  try {
    fs.chmodSync(dir, mode);
  } catch (_) {
    /* 某些文件系统不支持 chmod，忽略 */
  }
}

function writeFilePrivate(file, content) {
  fs.writeFileSync(file, content, { mode: 0o600 });
  try {
    fs.chmodSync(file, 0o600);
  } catch (_) {
    /* ignore */
  }
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(file, 'utf8'));
}

function loadConfig() {
  ensureDir(DATA_DIR);
  ensureDir(path.join(ROOT, 'uploads', 'packages'));
  ensureDir(path.join(ROOT, 'uploads', 'tmp'));

  if (!fs.existsSync(CONFIG_PATH)) {
    let example = DEFAULTS;
    if (fs.existsSync(EXAMPLE_PATH)) {
      example = mergeDefaults(readJson(EXAMPLE_PATH), DEFAULTS);
    }
    example.apiKey = crypto.randomBytes(24).toString('hex');
    writeFilePrivate(CONFIG_PATH, JSON.stringify(example, null, 2) + '\n');
  }

  const cfg = mergeDefaults(readJson(CONFIG_PATH), DEFAULTS);

  // 运行期路径统一落在部署根目录下，防止配置示例中的绝对路径在别的机器上误用。
  if (!cfg.storageRoot || !path.isAbsolute(cfg.storageRoot)) {
    cfg.storageRoot = path.join(ROOT, 'uploads', 'packages');
  }
  if (!cfg.tmpDir || !path.isAbsolute(cfg.tmpDir)) {
    cfg.tmpDir = path.join(ROOT, 'uploads', 'tmp');
  }
  ensureDir(cfg.storageRoot);
  ensureDir(cfg.tmpDir);
  cfg.mirrorRoot = path.join(ROOT, 'uploads', 'mirror');
  ensureDir(cfg.mirrorRoot);
  ensureDir(path.join(cfg.mirrorRoot, '.tmp'));

  if (!cfg.apiKey || cfg.apiKey.length < 24) {
    cfg.apiKey = crypto.randomBytes(24).toString('hex');
    const persisted = { ...readJson(CONFIG_PATH), apiKey: cfg.apiKey };
    writeFilePrivate(CONFIG_PATH, JSON.stringify(persisted, null, 2) + '\n');
  }

  // 文件镜像服务令牌：缺失时自动生成（32 字节 hex）并写回配置（0600）。
  if (!cfg.files.serviceToken || String(cfg.files.serviceToken).length < 32) {
    cfg.files.serviceToken = crypto.randomBytes(32).toString('hex');
    const persisted = readJson(CONFIG_PATH);
    persisted.files = { ...(persisted.files || {}), serviceToken: cfg.files.serviceToken };
    writeFilePrivate(CONFIG_PATH, JSON.stringify(persisted, null, 2) + '\n');
  }

  cfg.dataDir = DATA_DIR;
  cfg.root = ROOT;
  cfg.configPath = CONFIG_PATH;
  return cfg;
}

module.exports = { loadConfig, ensureDir, writeFilePrivate, DATA_DIR, ROOT };
