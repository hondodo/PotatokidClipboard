'use strict';

const fs = require('fs');
const http = require('http');
const https = require('https');
const path = require('path');
const express = require('express');

const { loadConfig } = require('./config');
const { Store } = require('./store');
const { createAudit } = require('./audit');
const { ensureSecret, bootstrapAdmin } = require('./security');
const { createAdminApp } = require('./admin');
const { ok, wrap, freeBytes, dirSizeBytes, securityHeaders, handleError } = require('./apiutil');

const config = loadConfig();
const VERSION = JSON.parse(fs.readFileSync(path.join(__dirname, 'package.json'), 'utf8')).version;
const store = new Store({ dataDir: config.dataDir });
store.init();

const secret = ensureSecret(config.dataDir);
const audit = createAudit(config.dataDir);

if (!store.data.admin) {
  const boot = bootstrapAdmin({ dataDir: config.dataDir, username: config.adminUsername });
  store.mutate(() => {
    store.data.admin = boot.admin;
  });
  console.log(`[init] 已创建初始管理员 ${config.adminUsername}`);
  console.log(`[init] 初始密码仅写入：${boot.initialPasswordFile}（0600），首次登录必须改密，请勿提交到仓库`);
}

if (!fs.existsSync(`${config.dataDir}/db.json`)) {
  store.persistSync();
}

// 安装包占用统计（60s 缓存，避免健康检查频繁遍历目录）。
let storageCache = { at: 0, bytes: 0 };
function storageBytes() {
  if (Date.now() - storageCache.at > 60 * 1000) {
    storageCache = { at: Date.now(), bytes: dirSizeBytes(config.storageRoot) };
  }
  return storageCache.bytes;
}

function healthPayload() {
  const free = freeBytes(config.root);
  return {
    ok: true,
    uptime: Math.round(process.uptime()),
    diskFreeBytes: free,
    diskLow: free !== null && free < config.retention.cleanupTargetFreeBytes,
    storageBytes: storageBytes(),
    maxStorageBytes: config.maxStorageBytes,
    applications: Object.keys(store.data.applications).length,
    releases: Object.keys(store.data.releases).length,
    version: VERSION,
  };
}

function createBusinessApp() {
  const app = express();
  if (config.trustProxy) app.set('trust proxy', true);
  app.disable('x-powered-by');
  app.use(securityHeaders);

  const health = wrap((req, res) => ok(res, healthPayload()));
  app.get('/healthz', health);
  app.get('/api/health', health);
  app.head('/healthz', (req, res) => res.status(200).end());

  // 管理面只存在于 47293：业务端口显式拒绝，避免误暴露。
  app.use(['/admin', '/api/admin'], (req, res) =>
    res.status(404).json({ code: 300000, msg: '接口不存在', data: null })
  );
  app.use((req, res) => res.status(404).json({ code: 300000, msg: '接口不存在', data: null }));
  app.use(handleError);
  return app;
}

function listen(app, port, bind, label, hasTls) {
  const handler = hasTls ? https.createServer({ key: fs.readFileSync(config.https.keyPath), cert: fs.readFileSync(config.https.certPath) }, app) : http.createServer(app);
  handler.listen(port, bind, () => {
    const scheme = hasTls ? 'https' : 'http';
    console.log(`[start] ${label} listening on ${scheme}://${bind}:${port}`);
  });
  handler.on('error', (err) => {
    console.error(`[fatal] ${label} 监听 ${bind}:${port} 失败：${err.message}`);
    process.exit(1);
  });
  return handler;
}

const useTls = Boolean(config.https && config.https.enabled);
if (useTls && (!config.https.keyPath || !config.https.certPath)) {
  console.error('[fatal] https.enabled=true 但缺少 keyPath/certPath');
  process.exit(1);
}

const businessApp = createBusinessApp();
const adminApp = createAdminApp({ config, store, audit, secret });

const servers = [
  listen(businessApp, config.port, '0.0.0.0', 'business', useTls),
  listen(adminApp, config.adminPort, config.adminBind || '0.0.0.0', 'admin', useTls),
];

console.log(`[start] 数据目录 ${config.dataDir}`);
console.log(`[start] 管理页 ${useTls ? 'https' : 'http'}://${config.adminBind || '0.0.0.0'}:${config.adminPort}/admin`);

function shutdown(signal) {
  console.log(`[shutdown] 收到 ${signal}，正在停止服务`);
  let pending = servers.length;
  const done = () => {
    pending -= 1;
    if (pending <= 0) process.exit(0);
  };
  for (const server of servers) {
    server.close(done);
    setTimeout(done, 5000).unref();
  }
  setTimeout(() => process.exit(0), 8000).unref();
}

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('unhandledRejection', (reason) => console.error('[unhandledRejection]', reason));
process.on('uncaughtException', (err) => console.error('[uncaughtException]', err));
