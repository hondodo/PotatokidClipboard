'use strict';

const fs = require('fs');
const net = require('net');
const express = require('express');
const { execFile } = require('child_process');
const { ApiError, ok, wrap, clientIp } = require('./apiutil');

// relay 自 2026-11 起由 systemd 托管：只能通过 systemctl 操作，禁止 pkill / nohup。
const SERVICE = 'potatokid-relay.service';
const SYSTEMCTL = '/usr/bin/systemctl';
const RELAY_PORT = 47291;
const LOG_FILE = '/var/log/potatokid-relay.log';
const DEFAULT_LOG_LINES = 200;
const MAX_LOG_LINES = 1000;
const MAX_LOG_BYTES = 4 * 1024 * 1024;
// relay 侧流量历史：JSONL，只含 host + 源地址短哈希，不含完整 URL/token。
const TRAFFIC_FILE = process.env.RELAY_TRAFFIC_FILE || '/var/log/potatokid-relay-traffic.jsonl';
const TRAFFIC_MAX_BYTES = 12 * 1024 * 1024;
const TRAFFIC_BUCKET_SEC = 300;
const TRAFFIC_TREND_BUCKETS = 12;
const TRAFFIC_WINDOW_SEC = TRAFFIC_BUCKET_SEC * TRAFFIC_TREND_BUCKETS;
const TRAFFIC_SOURCE_LIMIT = 20;
const SAFE_PATH = '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin';

// 固定命令 + 固定参数列表调用，不经过 shell，不拼接任何用户输入。
function run(cmd, args, timeoutMs = 5000) {
  return new Promise((resolve) => {
    execFile(
      cmd,
      args,
      { timeout: timeoutMs, maxBuffer: 2 * 1024 * 1024, env: { PATH: SAFE_PATH, LANG: 'C' } },
      (err, stdout, stderr) => {
        resolve({
          ok: !err,
          code: err ? Number(err.code) || -1 : 0,
          stdout: String(stdout || ''),
          stderr: String(stderr || ''),
          error: err ? String(err.message || err) : '',
        });
      }
    );
  });
}

function parseShow(output) {
  const map = {};
  for (const line of output.split('\n')) {
    const idx = line.indexOf('=');
    if (idx > 0) map[line.slice(0, idx)] = line.slice(idx + 1).trim();
  }
  return map;
}

function probePort(port, host, timeoutMs = 800) {
  return new Promise((resolve) => {
    const socket = net.connect({ port, host });
    let settled = false;
    const finish = (value) => {
      if (settled) return;
      settled = true;
      socket.destroy();
      resolve(value);
    };
    socket.setTimeout(timeoutMs);
    socket.on('connect', () => finish(true));
    socket.on('timeout', () => finish(false));
    socket.on('error', () => finish(false));
  });
}

function redact(text) {
  return String(text === undefined || text === null ? '' : text)
    .replace(/([?&]t=)[^&\s"'\]]+/gi, '$1***')
    .replace(/(token=)[^&\s"'\]]+/gi, '$1***')
    .replace(/(authorization\s*:\s*bearer\s+)\S+/gi, '$1***');
}

function truncate(text, max) {
  const value = String(text === undefined || text === null ? '' : text);
  return value.length > max ? value.slice(0, max) + '…' : value;
}

function extractSource(args) {
  const afterI = args.match(/(?:^|\s)-i\s+(\S+)/);
  if (afterI) return afterI[1];
  const url = args.match(/https?:\/\/[^\s'"]+/);
  return url ? url[0] : '';
}

async function readServiceInfo() {
  const shown = await run(SYSTEMCTL, [
    'show',
    SERVICE,
    '-p',
    'LoadState',
    '-p',
    'ActiveState',
    '-p',
    'SubState',
    '-p',
    'MainPID',
    '-p',
    'NRestarts',
    '-p',
    'FragmentPath',
  ]);
  if (!shown.ok) {
    return {
      unitKnown: false,
      active: false,
      state: 'unknown',
      subState: 'unknown',
      mainPid: 0,
      restarts: 0,
      uptimeSec: 0,
      startedAt: null,
      error: 'systemctl show 执行失败：' + (shown.stderr || shown.error || '未知错误'),
    };
  }

  const info = parseShow(shown.stdout);
  const mainPid = Number(info.MainPID) || 0;
  let uptimeSec = 0;
  if (mainPid > 0) {
    const ps = await run('ps', ['-o', 'etimes=', '-p', String(mainPid)]);
    if (ps.ok) uptimeSec = Number(ps.stdout.trim()) || 0;
  }

  return {
    unitKnown: info.LoadState === 'loaded',
    active: info.ActiveState === 'active',
    state: info.ActiveState || 'unknown',
    subState: info.SubState || 'unknown',
    mainPid,
    restarts: Number(info.NRestarts) || 0,
    uptimeSec,
    startedAt: uptimeSec > 0 ? new Date(Date.now() - uptimeSec * 1000).toISOString() : null,
    fragmentPath: info.FragmentPath || '',
  };
}

async function collectFfmpeg() {
  const ps = await run('ps', ['-eo', 'pid=,etime=,args=']);
  if (!ps.ok) {
    return { count: 0, items: [], error: '读取进程列表失败：' + (ps.stderr || ps.error) };
  }
  const items = [];
  for (const line of ps.stdout.split('\n')) {
    const match = line.match(/^\s*(\d+)\s+([^\s]+)\s+(.+)$/);
    if (!match) continue;
    const args = match[3];
    if (!/\bffmpeg\b/.test(args)) continue;
    const source = extractSource(args);
    items.push({
      pid: Number(match[1]),
      runtime: match[2],
      source: truncate(redact(source), 240) || '（未识别到源地址）',
    });
  }
  return { count: items.length, items };
}

// 从 pos 处向前找最近一个换行之后的位置（用于 4MB 窗口内完全没有换行的极端长行）
function findLineStart(fd, pos) {
  const block = 64 * 1024;
  let end = pos;
  while (end > 0) {
    const start = Math.max(0, end - block);
    const buf = Buffer.alloc(end - start);
    fs.readSync(fd, buf, 0, buf.length, start);
    const idx = buf.lastIndexOf(0x0a);
    if (idx !== -1) return start + idx + 1;
    end = start;
  }
  return 0;
}

// 尾部模式：返回最后 lineCount 条完整行，nextOffset 指向最后一条完整行之后的字节位置。
// 未以换行结尾的半行不返回，也不把 nextOffset 推过它。
function readTail(file, lineCount) {
  const fd = fs.openSync(file, 'r');
  try {
    const stat = fs.fstatSync(fd);
    const size = stat.size;
    const inode = String(stat.ino);
    const mtime = stat.mtime.toISOString();
    if (size === 0) {
      return { lines: [], size, inode, mtime, nextOffset: 0, truncated: false };
    }
    const start = Math.max(0, size - MAX_LOG_BYTES);
    const buffer = Buffer.alloc(size - start);
    fs.readSync(fd, buffer, 0, buffer.length, start);
    let body = buffer;
    let base = start;
    if (start > 0) {
      const firstBreak = buffer.indexOf(0x0a);
      if (firstBreak === -1) {
        return { lines: [], size, inode, mtime, nextOffset: findLineStart(fd, start), truncated: true };
      }
      body = buffer.subarray(firstBreak + 1);
      base = start + firstBreak + 1;
    }
    const lastBreak = body.lastIndexOf(0x0a);
    if (lastBreak === -1) {
      return { lines: [], size, inode, mtime, nextOffset: base, truncated: start > 0 };
    }
    const complete = body.subarray(0, lastBreak + 1);
    const text = complete.toString('utf8');
    const lines = text.split('\n');
    if (lines.length && lines[lines.length - 1] === '') lines.pop();
    return {
      lines: lines.slice(-lineCount),
      size,
      inode,
      mtime,
      nextOffset: base + complete.length,
      truncated: start > 0,
    };
  } finally {
    fs.closeSync(fd);
  }
}

// 增量模式：从 offset（必须是上次 nextOffset，即完整行边界）读到 EOF，
// 只返回完整行；nextOffset 与返回内容严格对齐，半行留在原地等下次。
function readLogChunk(file, offset, lineCount, expectInode, expectSize) {
  const fd = fs.openSync(file, 'r');
  try {
    const stat = fs.fstatSync(fd);
    const size = stat.size;
    const inode = String(stat.ino);
    const mtime = stat.mtime.toISOString();
    let reason = '';
    if (expectInode && expectInode !== inode) reason = 'rotated';
    else if (expectSize !== null && size < expectSize) reason = 'truncated';
    else if (size < offset) reason = 'truncated';
    else if (offset > 0) {
      const probe = Buffer.alloc(1);
      fs.readSync(fd, probe, 0, 1, offset - 1);
      if (probe[0] !== 0x0a) reason = 'offset_misaligned';
    }
    if (reason) {
      return { reset: true, reason, size, inode, mtime, lines: [], nextOffset: offset };
    }
    if (size <= offset) {
      return {
        reset: false, lines: [], size, inode, mtime, nextOffset: offset,
        hasMore: false, truncated: false,
      };
    }
    const end = Math.min(size, offset + MAX_LOG_BYTES);
    const buffer = Buffer.alloc(end - offset);
    fs.readSync(fd, buffer, 0, buffer.length, offset);
    const lastBreak = buffer.lastIndexOf(0x0a);
    if (lastBreak === -1) {
      return {
        reset: false, lines: [], size, inode, mtime, nextOffset: offset,
        hasMore: end < size, truncated: true,
      };
    }
    const usable = buffer.subarray(0, lastBreak + 1);
    const text = usable.toString('utf8');
    const all = text.split('\n');
    if (all.length && all[all.length - 1] === '') all.pop();
    let picked = all;
    let nextOffset = offset + usable.length;
    if (all.length > lineCount) {
      picked = all.slice(0, lineCount);
      nextOffset = offset + Buffer.byteLength(picked.join('\n') + '\n', 'utf8');
    }
    return {
      reset: false, lines: picked, size, inode, mtime, nextOffset,
      hasMore: nextOffset < size, truncated: end < size,
    };
  } finally {
    fs.closeSync(fd);
  }
}

function parseLines(value) {
  const num = Number(value);
  if (!Number.isFinite(num) || num <= 0) return DEFAULT_LOG_LINES;
  return Math.min(MAX_LOG_LINES, Math.max(10, Math.floor(num)));
}

// 增量游标参数：缺省/非法一律回退到尾部模式，避免拿错值读错位内容。
function parseOffset(value) {
  if (value === undefined || value === '') return null;
  const num = Number(value);
  if (!Number.isFinite(num) || num < 0) return null;
  return Math.floor(num);
}

// ---- 转换流量历史（relay 写入的 JSONL，只读）----
let trafficCache = { key: '', at: 0, value: null };

function emptyTrafficTrend(nowSec) {
  const start = nowSec - TRAFFIC_WINDOW_SEC;
  return {
    bucketSec: TRAFFIC_BUCKET_SEC,
    windowSec: TRAFFIC_WINDOW_SEC,
    hasData: false,
    points: Array.from({ length: TRAFFIC_TREND_BUCKETS }, (_, i) => ({
      t: new Date((start + i * TRAFFIC_BUCKET_SEC) * 1000).toISOString(),
      inKbps: 0,
      outKbps: 0,
    })),
  };
}

function loadTrafficRecords() {
  const stat = fs.statSync(TRAFFIC_FILE);
  const size = stat.size;
  const key = `${size}:${stat.mtimeMs}`;
  if (trafficCache.value && trafficCache.key === key && Date.now() - trafficCache.at < 4000) {
    return trafficCache.value;
  }
  const start = Math.max(0, size - TRAFFIC_MAX_BYTES);
  const length = size - start;
  let text = '';
  const fd = fs.openSync(TRAFFIC_FILE, 'r');
  try {
    const buffer = Buffer.alloc(length);
    fs.readSync(fd, buffer, 0, length, start);
    text = buffer.toString('utf8');
  } finally {
    fs.closeSync(fd);
  }
  if (start > 0) {
    const firstBreak = text.indexOf('\n');
    text = firstBreak === -1 ? '' : text.slice(firstBreak + 1);
  }
  const records = [];
  for (const line of text.split('\n')) {
    if (!line) continue;
    let row;
    try {
      row = JSON.parse(line);
    } catch (_) {
      continue;
    }
    const t = Number(row.t);
    const din = Number(row.din);
    const dout = Number(row.dout);
    if (!Number.isFinite(t) || !Number.isFinite(din) || !Number.isFinite(dout)) continue;
    const host = typeof row.host === 'string'
      ? row.host.replace(/[^\w.-]/g, '').slice(0, 253) || '-'
      : '-';
    const sid = typeof row.sid === 'string'
      ? row.sid.replace(/[^0-9a-f]/gi, '').toLowerCase().slice(0, 16)
      : '';
    const dt = Number(row.dt);
    const iv = Number(row.iv);
    const ret = Number(row.ret);
    const isrc = row.isrc === 'rchar' ? 'rchar' : 'ss';
    records.push({
      t,
      host,
      sid,
      din: Math.max(0, din),
      dout: Math.max(0, dout),
      dt: Number.isFinite(dt) && dt > 0 ? dt : 0,
      iv: Number.isFinite(iv) && iv > 0 ? iv : 0,
      ret: Number.isFinite(ret) && ret > 0 ? ret : 0,
      isrc,
    });
  }
  const value = {
    available: true,
    sizeBytes: size,
    mtime: stat.mtime.toISOString(),
    truncated: start > 0,
    records,
  };
  trafficCache = { key, at: Date.now(), value };
  return value;
}

function collectTraffic() {
  const nowSec = Date.now() / 1000;
  let loaded;
  try {
    loaded = loadTrafficRecords();
  } catch (err) {
    if (err && err.code === 'ENOENT') {
      return {
        available: false,
        file: TRAFFIC_FILE,
        empty: 'no_file',
        intervalSec: 10,
        retentionSec: 86400,
        inboundSource: 'ss',
        sampleCount: 0,
        sourceCount: 0,
        lastSampleAt: null,
        totals: { in1h: 0, out1h: 0, in24h: 0, out24h: 0 },
        current: [],
        sources: [],
        trend: emptyTrafficTrend(nowSec),
        checkedAt: new Date().toISOString(),
      };
    }
    throw err;
  }

  const oneHourAgo = nowSec - TRAFFIC_WINDOW_SEC;
  const oneDayAgo = nowSec - 86400;
  const map = new Map();
  const buckets = Array.from({ length: TRAFFIC_TREND_BUCKETS }, () => ({
    in: 0,
    out: 0,
  }));
  let totalIn1h = 0;
  let totalOut1h = 0;
  let totalIn24h = 0;
  let totalOut24h = 0;
  let lastT = 0;
  let intervalSec = 10;
  let retentionSec = 86400;
  let inboundSource = 'ss';

  for (const r of loaded.records) {
    if (r.t > lastT) {
      lastT = r.t;
      inboundSource = r.isrc;
    }
    if (r.iv) intervalSec = r.iv;
    if (r.ret) retentionSec = r.ret;
    const key = r.sid || r.host;
    let s = map.get(key);
    if (!s) {
      s = {
        id: key,
        host: r.host,
        sid: r.sid,
        in1h: 0,
        out1h: 0,
        in24h: 0,
        out24h: 0,
        lastAt: 0,
        lastIn: 0,
        lastOut: 0,
        lastDt: 0,
      };
      map.set(key, s);
    }
    if (r.host && s.host === '-') s.host = r.host;
    if (r.t >= oneDayAgo) {
      s.in24h += r.din;
      s.out24h += r.dout;
      totalIn24h += r.din;
      totalOut24h += r.dout;
    }
    if (r.t >= oneHourAgo) {
      s.in1h += r.din;
      s.out1h += r.dout;
      totalIn1h += r.din;
      totalOut1h += r.dout;
      let idx = Math.floor((r.t - oneHourAgo) / TRAFFIC_BUCKET_SEC);
      if (idx < 0) idx = 0;
      if (idx >= TRAFFIC_TREND_BUCKETS) idx = TRAFFIC_TREND_BUCKETS - 1;
      buckets[idx].in += r.din;
      buckets[idx].out += r.dout;
    }
    if (r.t >= s.lastAt) {
      s.lastAt = r.t;
      s.lastIn = r.din;
      s.lastOut = r.dout;
      s.lastDt = r.dt;
    }
  }

  const activeWindow = Math.max(intervalSec * 3, 30);
  const allSources = Array.from(map.values())
    .map((s) => {
      const dt = s.lastDt || intervalSec;
      return {
        id: s.id,
        host: s.host,
        sid: s.sid,
        in1h: s.in1h,
        out1h: s.out1h,
        in24h: s.in24h,
        out24h: s.out24h,
        lastAt: s.lastAt ? new Date(s.lastAt * 1000).toISOString() : null,
        inKbps: dt > 0 ? (s.lastIn * 8) / 1000 / dt : 0,
        outKbps: dt > 0 ? (s.lastOut * 8) / 1000 / dt : 0,
        active: nowSec - s.lastAt <= activeWindow,
      };
    })
    .sort((a, b) => (b.in1h + b.out1h) - (a.in1h + a.out1h)
      || (b.in24h + b.out24h) - (a.in24h + a.out24h));
  const current = allSources.filter((s) => s.active);
  const sources = allSources.slice(0, TRAFFIC_SOURCE_LIMIT);
  const hasTraffic = totalIn24h + totalOut24h > 0;
  const empty = !loaded.records.length ? 'no_records' : (hasTraffic ? '' : 'no_traffic');
  const trend = {
    bucketSec: TRAFFIC_BUCKET_SEC,
    windowSec: TRAFFIC_WINDOW_SEC,
    hasData: totalIn1h + totalOut1h > 0,
    points: buckets.map((b, i) => ({
      t: new Date((oneHourAgo + i * TRAFFIC_BUCKET_SEC) * 1000).toISOString(),
      inKbps: (b.in * 8) / 1000 / TRAFFIC_BUCKET_SEC,
      outKbps: (b.out * 8) / 1000 / TRAFFIC_BUCKET_SEC,
    })),
  };

  return {
    available: true,
    file: TRAFFIC_FILE,
    sizeBytes: loaded.sizeBytes,
    mtime: loaded.mtime,
    truncated: Boolean(loaded.truncated),
    intervalSec,
    retentionSec,
    inboundSource,
    sampleCount: loaded.records.length,
    sourceCount: allSources.length,
    lastSampleAt: lastT ? new Date(lastT * 1000).toISOString() : null,
    empty,
    totals: { in1h: totalIn1h, out1h: totalOut1h, in24h: totalIn24h, out24h: totalOut24h },
    current,
    sources,
    trend,
    checkedAt: new Date().toISOString(),
  };
}


// 动作白名单：命令与参数全部写死，不接受任何用户输入拼接。
const ACTIONS = {
  start: { arg: 'start', expectActive: true },
  stop: { arg: 'stop', expectActive: false },
  restart: { arg: 'restart', expectActive: true },
};
const READ_RATE = { limit: 120, windowMs: 60 * 1000 };
const ACTION_RATE = { limit: 5, windowMs: 60 * 1000 };

function createRateLimiter({ limit, windowMs }) {
  const buckets = new Map();
  return function take(key) {
    const now = Date.now();
    let hits = buckets.get(key);
    if (!hits) {
      hits = [];
      buckets.set(key, hits);
    }
    while (hits.length && now - hits[0] >= windowMs) hits.shift();
    if (hits.length >= limit) {
      return Math.ceil((windowMs - (now - hits[0])) / 1000);
    }
    hits.push(now);
    if (buckets.size > 4096) {
      for (const [k, v] of buckets) {
        if (!v.length || now - v[v.length - 1] >= windowMs) buckets.delete(k);
      }
    }
    return 0;
  };
}

function principalKey(req) {
  const principal = req.principal || {};
  return principal.type === 'viewer' ? `token:${principal.tokenId}` : String(principal.username || 'unknown');
}

async function waitForService(expectedActive, timeoutMs = 4000) {
  const deadline = Date.now() + timeoutMs;
  let last = await readServiceInfo();
  while (Date.now() < deadline && last.active !== expectedActive) {
    await new Promise((resolve) => setTimeout(resolve, 200));
    last = await readServiceInfo();
  }
  return last;
}

function createRelayRouter({ audit } = {}) {
  const router = express.Router();
  const readLimit = createRateLimiter(READ_RATE);
  const actionLimit = createRateLimiter(ACTION_RATE);

  router.use((req, res, next) => {
    const retry = readLimit(principalKey(req));
    if (retry) return next(new ApiError(429, 400002, `刷新过于频繁，请 ${retry} 秒后再试`));
    return next();
  });

  router.get(
    '/relay/status',
    wrap(async (req, res) => {
      const [service, ffmpeg, listening] = await Promise.all([
        readServiceInfo(),
        collectFfmpeg(),
        probePort(RELAY_PORT, '127.0.0.1'),
      ]);
      ok(res, {
        service: { unit: SERVICE, port: RELAY_PORT, ...service },
        portListening: listening,
        ffmpeg,
        checkedAt: new Date().toISOString(),
      });
    })
  );

  router.get(
    '/relay/logs',
    wrap(async (req, res) => {
      const lines = parseLines(req.query.lines);
      const offset = parseOffset(req.query.offset);
      const expectInode = req.query.inode === undefined ? '' : String(req.query.inode);
      const expectSize = parseOffset(req.query.size);
      let data;
      try {
        if (offset === null) {
          data = readTail(LOG_FILE, lines);
        } else {
          data = readLogChunk(LOG_FILE, offset, lines, expectInode, expectSize);
          if (data.reset) {
            const reason = data.reason || 'changed';
            data = readTail(LOG_FILE, lines);
            data.reset = true;
            data.reason = reason;
          }
        }
      } catch (err) {
        if (err && err.code === 'ENOENT') {
          throw new ApiError(404, 400004, `日志文件不存在：${LOG_FILE}`);
        }
        throw new ApiError(500, 500000, `读取日志失败：${err.message}`);
      }
      const content = redact(data.lines.join('\n'));
      const outLines = content ? content.split('\n') : [];
      ok(res, {
        file: LOG_FILE,
        source: 'file',
        requestedLines: lines,
        count: outLines.length,
        sizeBytes: data.size,
        size: data.size,
        inode: String(data.inode),
        mtime: data.mtime,
        nextOffset: data.nextOffset,
        reset: Boolean(data.reset),
        resetReason: data.reason || '',
        hasMore: Boolean(data.hasMore),
        truncated: Boolean(data.truncated),
        lines: outLines,
      });
    })
  );

  router.get(
    '/relay/traffic',
    wrap(async (req, res) => {
      let data;
      try {
        data = collectTraffic();
      } catch (err) {
        throw new ApiError(500, 500000, `读取流量历史失败：${err.message}`);
      }
      ok(res, data);
    })
  );

  router.post(
    '/relay/action',
    wrap(async (req, res) => {
      const body = req.body || {};
      const requested = typeof body.action === 'string' ? body.action : '';
      const spec = ACTIONS[requested];
      const principal = req.principal || {};
      const actor = principal.type === 'viewer' ? `token:${principal.tokenId}` : String(principal.username || 'unknown');
      const ip = req.clientIp || clientIp(req);

      if (!spec) {
        await audit.log({
          actor,
          ip,
          action: 'relay_action_rejected',
          target: SERVICE,
          before: null,
          after: { requested: truncate(requested, 40), result: 'invalid_action' },
        });
        throw new ApiError(400, 400005, '不支持的操作，仅允许 start / stop / restart');
      }

      const retry = actionLimit(`${actor}:${spec.arg}`);
      if (retry) {
        await audit.log({
          actor,
          ip,
          action: `relay_${spec.arg}`,
          target: SERVICE,
          before: null,
          after: { result: 'rate_limited', retryAfterSec: retry },
        });
        throw new ApiError(429, 400002, `操作过于频繁，请 ${retry} 秒后再试`);
      }

      const before = await readServiceInfo();
      const result = await run('/usr/bin/sudo', ['-n', SYSTEMCTL, spec.arg, SERVICE], 15000);
      const after = await waitForService(spec.expectActive, 4000);
      const portListening = await probePort(RELAY_PORT, '127.0.0.1');

      await audit.log({
        actor,
        ip,
        action: `relay_${spec.arg}`,
        target: SERVICE,
        before: { active: before.active, state: before.state, mainPid: before.mainPid },
        after: {
          result: result.ok ? 'success' : 'failure',
          exitCode: result.code,
          active: after.active,
          state: after.state,
          mainPid: after.mainPid,
          portListening,
          message: result.ok ? '' : truncate(result.stderr || result.error, 300),
        },
      });

      if (!result.ok) {
        throw new ApiError(
          503,
          500001,
          `systemctl ${spec.arg} ${SERVICE} 执行失败：${truncate(result.stderr || result.error || '未知错误', 200)}`
        );
      }

      ok(res, {
        action: requested,
        result: 'success',
        message: `systemctl ${spec.arg} ${SERVICE} 执行成功`,
        service: after,
        portListening,
        at: new Date().toISOString(),
      });
    })
  );

  return router;
}

module.exports = {
  createRelayRouter,
  SERVICE,
  LOG_FILE,
  TRAFFIC_FILE,
  RELAY_PORT,
  MAX_LOG_LINES,
  DEFAULT_LOG_LINES,
  redact,
  readTail,
  readLogChunk,
  collectTraffic,
};
