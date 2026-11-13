// 上传 parent flavor 三个 APK 到 yuntu 应用分发服务（appId=potatokid-home-parent）。
//
// 用法：
//   YUNTU_ADMIN_USER=<用户名> YUNTU_ADMIN_PASS=<密码> node upload_parent_apks.mjs
//
// 说明：
// - 本地 pscreen_server 只是查询代理；真正的安装包与发布在 yuntu（app_server）。
// - 三个 APK 按 (appId, platform=apk, abi) 轨道分别发布：
//     app-parent-release.apk            -> universal
//     app-arm64-v8a-parent-release.apk  -> arm64-v8a
//     app-armeabi-v7a-parent-release.apk-> armeabi-v7a
// - 同一 build=9；默认非强制更新（forceUpdate=false）。
// - 分片上传（8MiB/片），自动处理 init/chunk/complete/publish。
// - 写操作带 X-Admin-Request:1 + Origin 过 CSRF；cookie jar 复用登录会话。

import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import os from 'node:os';

const execFileP = promisify(execFile);

const ADMIN_USER = process.env.YUNTU_ADMIN_USER;
const ADMIN_PASS = process.env.YUNTU_ADMIN_PASS;
const FORCE = process.env.YUNTU_FORCE_UPDATE === '1';
if (!ADMIN_USER || !ADMIN_PASS) {
  console.error('需要提供环境变量 YUNTU_ADMIN_USER 和 YUNTU_ADMIN_PASS');
  process.exit(2);
}

const YUNTU_IP = '143.203.52.132';
const ADMIN_BASE = `http://${YUNTU_IP}:47293`;
const API_BASE = `http://${YUNTU_IP}:47292`;

const APP_ID = process.env.YUNTU_APP_ID || 'potatokid-home-parent';
const PLATFORM = 'apk';
const VERSION = process.env.YUNTU_VERSION || '1.0.6';
const BUILD = Number(process.env.YUNTU_BUILD || 10);
const CHUNK = 8 * 1024 * 1024;

// 支持发布家长端（parent flavor）与电视端（tv flavor）；按 appId 推导产物名。
const IS_TV = APP_ID.includes('screen-tv');
const FLAVOR = IS_TV ? 'tv' : 'parent';
const APK_DIR = process.env.YUNTU_APK_DIR
  || `/home/honghao/codes/PotatokidClipboard/${IS_TV ? 'pscreen/potatokid_screen' : 'pscreen_home'}/build/app/outputs/flutter-apk`;
const ARTIFACTS = [
  { file: `app-${FLAVOR}-release.apk`, abi: 'universal' },
  { file: `app-arm64-v8a-${FLAVOR}-release.apk`, abi: 'arm64-v8a' },
  { file: `app-armeabi-v7a-${FLAVOR}-release.apk`, abi: 'armeabi-v7a' },
];
const NOTES = process.env.YUNTU_NOTES
  || (IS_TV
    ? '电视端：选人页暂停播放与计时；题库变更即时刷新；D-01 冲突保护。'
    : '家长端：D-01 冲突三选一与埋点；解绑/切号确认；解锁中心拒绝重试；导航灰度开关。');

const cookieJar = path.join(os.tmpdir(), `yuntu_cookies_${Date.now()}.txt`);

function tryParse(s) {
  try { return JSON.parse(s); } catch (_) { return null; }
}

async function curl(method, url, opts = {}) {
  const args = ['-sS', '-m', String(opts.timeout || 300), '-w', '\n%{http_code}'];
  const env = { ...process.env };
  env.NO_PROXY = `${YUNTU_IP},${env.NO_PROXY || ''}`;
  env.no_proxy = `${YUNTU_IP},${env.no_proxy || ''}`;
  if (opts.useCookie !== false) {
    args.push('--cookie-jar', cookieJar, '--cookie', cookieJar);
  }
  const headers = [];
  if (opts.json !== undefined) headers.push('Content-Type: application/json');
  if (['POST', 'PUT', 'PATCH', 'DELETE'].includes(method)) {
    headers.push('X-Admin-Request: 1');
    headers.push(`Origin: ${ADMIN_BASE}`);
  }
  for (const h of headers) args.push('-H', h);
  args.push('-X', method);
  if (opts.json !== undefined) {
    const tmp = path.join(os.tmpdir(), `yuntu_req_${Date.now()}_${Math.random().toString(36).slice(2)}.json`);
    fs.writeFileSync(tmp, JSON.stringify(opts.json));
    args.push('--data', `@${tmp}`);
    opts._tmp = tmp;
  } else if (opts.binary) {
    headers.push('Content-Type: application/octet-stream');
    args.push('--data-binary', `@${opts.binary}`);
  }
  args.push(url);
  let stdout;
  try {
    const r = await execFileP('curl', args, { env, maxBuffer: 300 * 1024 * 1024 });
    stdout = r.stdout;
  } finally {
    if (opts._tmp) { try { fs.unlinkSync(opts._tmp); } catch (_) { /* ignore */ } }
  }
  const idx = stdout.lastIndexOf('\n');
  if (idx < 0) return { code: 0, body: stdout, json: tryParse(stdout) };
  const body = stdout.slice(0, idx);
  const code = parseInt(stdout.slice(idx + 1).trim(), 10);
  return { code, body, json: tryParse(body) };
}

function requireOk(resp, label) {
  const c = resp.code;
  const code = resp.json && resp.json.code;
  if (c >= 200 && c < 300 && (code === 0 || code === undefined)) return;
  throw new Error(`${label} 失败：HTTP ${c} body=${resp.body}`);
}

function sha256File(filePath) {
  return new Promise((resolve, reject) => {
    const hash = crypto.createHash('sha256');
    const rs = fs.createReadStream(filePath);
    rs.on('data', (d) => hash.update(d));
    rs.on('end', () => resolve(hash.digest('hex')));
    rs.on('error', reject);
  });
}

async function main() {
  console.log(`目标：yuntu ${ADMIN_BASE} / 应用 ${APP_ID} / build=${BUILD} / 强制更新=${FORCE}`);
  console.log(`cookieJar=${cookieJar}`);

  // 1. 登录
  const login = await curl('POST', `${ADMIN_BASE}/api/admin/login`, {
    json: { username: ADMIN_USER, password: ADMIN_PASS },
  });
  requireOk(login, '登录');
  console.log('✓ 登录成功');

  // 2. 应用是否存在
  const apps = await curl('GET', `${ADMIN_BASE}/api/admin/apps`);
  requireOk(apps, '获取应用列表');
  const list = (apps.json && apps.json.data && apps.json.data.items) || [];
  let app = list.find((a) => a.appId === APP_ID);
  if (!app) {
    console.log(`应用 ${APP_ID} 不存在，创建中...`);
    const created = await curl('POST', `${ADMIN_BASE}/api/admin/apps`, {
      json: {
        appId: APP_ID,
        name: IS_TV ? '薯仔 Screen 电视端' : '薯仔 Home 家长端',
        description: IS_TV ? '电视端 App（tv flavor）' : '家长端 App（parent flavor）',
        platforms: ['apk'],
        enabled: true,
      },
    });
    requireOk(created, '创建应用');
    console.log('✓ 应用已创建');
  } else {
    console.log(`✓ 应用 ${APP_ID} 已存在，platforms=${(app.platforms || []).join(',')}`);
    if (!(app.platforms || []).includes('apk')) throw new Error('应用未包含 apk 平台');
  }

  // 3. 检查 build 冲突
  const rel = await curl('GET', `${ADMIN_BASE}/api/admin/apps/${APP_ID}/releases?platform=${PLATFORM}`);
  requireOk(rel, '获取版本列表');
  const items = (rel.json && rel.json.data && rel.json.data.items) || [];
  const conflicts = items.filter((r) => r.build === BUILD);
  if (conflicts.length) {
    console.log(`已存在 build=${BUILD} 的版本：${conflicts.map((r) => `${r.abi || 'universal'}(${r.status})`).join(', ')}`);
  }

  // 4. 上传每个 ABI 轨
  for (const art of ARTIFACTS) {
    const filePath = path.join(APK_DIR, art.file);
    if (!fs.existsSync(filePath)) throw new Error(`文件不存在：${filePath}`);
    if (conflicts.some((r) => (r.abi || 'universal') === art.abi)) {
      console.log(`⊘ ${art.abi}: build=${BUILD} 已存在，跳过`);
      continue;
    }
    const size = fs.statSync(filePath).size;
    const sha = await sha256File(filePath);
    console.log(`\n→ ${art.abi} (${art.file}) size=${(size / 1024 / 1024).toFixed(1)}MB sha256=${sha.slice(0, 12)}...`);

    const init = await curl('POST', `${ADMIN_BASE}/api/admin/uploads/init`, {
      json: {
        appId: APP_ID,
        platform: PLATFORM,
        abi: art.abi,
        filename: art.file,
        size,
        sha256: sha,
        version: VERSION,
        build: BUILD,
        pubspecBuildConfirmed: true,
        notes: NOTES,
      },
    });
    requireOk(init, `${art.abi} init`);
    const uploadId = init.json.data.uploadId;
    const totalChunks = init.json.data.totalChunks;
    console.log(`  init OK uploadId=${uploadId} chunks=${totalChunks}`);

    const fd = fs.openSync(filePath, 'r');
    try {
      for (let i = 0; i < totalChunks; i++) {
        const start = i * CHUNK;
        const end = Math.min(start + CHUNK, size);
        const len = end - start;
        const buf = Buffer.alloc(len);
        fs.readSync(fd, buf, 0, len, start);
        const part = path.join(os.tmpdir(), `yuntu_chunk_${uploadId}_${i}.part`);
        fs.writeFileSync(part, buf);
        let up = null;
        let lastErr = null;
        for (let attempt = 1; attempt <= 3; attempt++) {
          up = await curl('PUT', `${ADMIN_BASE}/api/admin/uploads/${uploadId}/chunks/${i}`, {
            binary: part,
            timeout: 300,
          });
          if (up.json && up.json.code === 0) { lastErr = null; break; }
          lastErr = `${art.abi} 分片 ${i} 失败(${up.code})：${up.body}`;
          console.log(`    ⚠ 分片 ${i} 第 ${attempt} 次失败，2s 后重试…`);
          await new Promise((r) => setTimeout(r, 2000 * attempt));
        }
        fs.unlinkSync(part);
        if (lastErr) throw new Error(lastErr);
        process.stdout.write(`  chunk ${i + 1}/${totalChunks}\r`);
      }
    } finally {
      fs.closeSync(fd);
    }
    console.log('  分片上传完成');

    const complete = await curl('POST', `${ADMIN_BASE}/api/admin/uploads/${uploadId}/complete`, {
      json: { sha256: sha },
      timeout: 120,
    });
    requireOk(complete, `${art.abi} complete`);
    const releaseId = complete.json.data.releaseId;
    console.log(`  complete OK releaseId=${releaseId}`);

    const publish = await curl('POST', `${ADMIN_BASE}/api/admin/releases/${releaseId}/publish`, {
      json: { forceUpdate: FORCE },
      timeout: 60,
    });
    requireOk(publish, `${art.abi} publish`);
    console.log(`  ✓ 已发布 ${art.abi} build=${BUILD} forceUpdate=${FORCE}`);
  }

  console.log('\n✅ 上传发布完成。请到 100.83.142.107 上验证查询接口：');
  console.log(`   curl -s "http://127.0.0.1:3000/api/app_update/check?app=${APP_ID}&platform=${PLATFORM}&build=8"`);
  console.log(`   curl -s "http://127.0.0.1:3000/api/app_update/check?app=${APP_ID}&platform=${PLATFORM}&build=8&abi=arm64-v8a"`);
}

main().catch((err) => {
  console.error('\n❌', err.message);
  process.exit(1);
});
