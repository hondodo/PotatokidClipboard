'use strict';
// 在 yuntu 上以 honghao 身份运行：把 route 2 的 parent build=10 APK 登记为已发布版本。
// 背景：yuntu app_server 的 chunk 上传接口被 body-parser 大小限制(PayloadTooLargeError)堵死，
// 官方分片上传不可用；故直接把包 scp 到位后，由本脚本把 release 记录写进 db.json。
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const DB = '/home/honghao/services/app_server/datas/app_update/db.json';
const APP_ID = 'potatokid-home-parent';
const PLATFORM = 'apk';
const VERSION = '1.0.6';
const BUILD = 10;

const NOW = new Date();
const pad = (n) => String(n).padStart(2, '0');
function newReleaseId() {
  const d = NOW;
  const stamp =
    `${d.getUTCFullYear()}${pad(d.getUTCMonth() + 1)}${pad(d.getUTCDate())}` +
    `${pad(d.getUTCHours())}${pad(d.getUTCMinutes())}${pad(d.getUTCSeconds())}`;
  return `rel_${stamp}_${crypto.randomBytes(3).toString('hex')}`;
}
const nowIso = () => NOW.toISOString();

// 与本地 build 10 产物一一对应（sha256/size 已核对）
const ARTIFACTS = [
  { filename: 'app-parent-release.apk',            abi: 'universal',    size: 124184336, sha256: '49b7d9cc86c946ddfa690f8bb48df4f27d27cdf17bdcab4420bd90988e808625' },
  { filename: 'app-arm64-v8a-parent-release.apk',  abi: 'arm64-v8a',   size: 43262329,  sha256: 'a6cd76819231111506171b80e8eccef488202c9af4067810f6ba84205a55c2bb' },
  { filename: 'app-armeabi-v7a-parent-release.apk', abi: 'armeabi-v7a', size: 38771695,  sha256: 'bdeb1f56461e3dfd793a74fa66dd5fccade98396abc94ec7a767dccda81fd086' },
];

function main() {
  const db = JSON.parse(fs.readFileSync(DB, 'utf8'));
  if (!db.releases) db.releases = {};
  if (!db.latest) db.latest = {};
  if (!db.latest[APP_ID]) db.latest[APP_ID] = {};
  if (!db.latest[APP_ID][PLATFORM] || typeof db.latest[APP_ID][PLATFORM] === 'string') {
    const legacy = typeof db.latest[APP_ID][PLATFORM] === 'string' ? db.latest[APP_ID][PLATFORM] : null;
    db.latest[APP_ID][PLATFORM] = legacy ? { universal: legacy } : {};
  }
  const byAbi = db.latest[APP_ID][PLATFORM];

  const created = [];
  for (const art of ARTIFACTS) {
    const abi = art.abi;
    // 归档当前该 abi 轨道的 latest（build 9）
    const prevId = byAbi[abi];
    if (prevId && db.releases[prevId] && db.releases[prevId].status === 'published') {
      const prev = db.releases[prevId];
      prev.status = 'archived';
      prev.archivedAt = nowIso();
      prev.forceUpdate = false;
      console.log(`archived ${prevId} (build ${prev.build}, ${abi})`);
    }
    const relPath = path.posix.join(APP_ID, PLATFORM, String(BUILD), `${VERSION}-${BUILD}-${art.filename}`);
    const releaseId = newReleaseId();
    const release = {
      releaseId,
      appId: APP_ID,
      platform: PLATFORM,
      version: VERSION,
      build: BUILD,
      pubspecBuildConfirmed: true,
      filename: art.filename,
      storedPath: relPath,
      size: art.size,
      sha256: art.sha256,
      distribution: 'file',
      externalUrl: null,
      fileAvailable: true,
      fileDeletedAt: null,
      notes: '家长端 route 2：新增「设置登录名」页面与 claim 账号迁移流程（非强制更新）',
      abi,
      forceUpdate: false,
      status: 'published',
      publishedAt: nowIso(),
      archivedAt: null,
      createdAt: nowIso(),
      downloadCount: 0,
      lastDownloadAt: null,
      uploadedBy: 'honghao',
    };
    db.releases[releaseId] = release;
    byAbi[abi] = releaseId;
    created.push({ abi, releaseId, relPath, sha256: art.sha256 });
    console.log(`created ${releaseId} build=${BUILD} ${abi} -> ${relPath}`);
  }

  const tmp = `${DB}.tmp-${process.pid}-${Date.now()}`;
  fs.writeFileSync(tmp, JSON.stringify(db, null, 2) + '\n', { mode: 0o600 });
  fs.renameSync(tmp, DB);
  console.log('db.json updated atomically.');
  console.log(JSON.stringify(created, null, 2));
}
main();
