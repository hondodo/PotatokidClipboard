'use strict';

const fs = require('fs');
const net = require('net');
const express = require('express');
const { execFile } = require('child_process');
const { ApiError, ok, wrap } = require('./apiutil');

// relay 自 2026-11 起由 systemd 托管：只能通过 systemctl 操作，禁止 pkill / nohup。
const SERVICE = 'potatokid-relay.service';
const SYSTEMCTL = '/usr/bin/systemctl';
const RELAY_PORT = 47291;
const LOG_FILE = '/var/log/potatokid-relay.log';
const DEFAULT_LOG_LINES = 200;
const MAX_LOG_LINES = 1000;
const MAX_LOG_BYTES = 4 * 1024 * 1024;
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

function readTail(file, lineCount) {
  const stat = fs.statSync(file);
  const size = stat.size;
  if (size === 0) return { lines: [], size: 0, mtime: stat.mtime.toISOString() };
  const start = Math.max(0, size - MAX_LOG_BYTES);
  const length = size - start;
  const fd = fs.openSync(file, 'r');
  try {
    const buffer = Buffer.alloc(length);
    fs.readSync(fd, buffer, 0, length, start);
    let text = buffer.toString('utf8');
    if (start > 0) {
      const firstBreak = text.indexOf('\n');
      text = firstBreak === -1 ? '' : text.slice(firstBreak + 1);
    }
    const lines = text.split('\n');
    if (lines.length && lines[lines.length - 1] === '') lines.pop();
    return {
      lines: lines.slice(-lineCount),
      size,
      mtime: stat.mtime.toISOString(),
      truncated: start > 0,
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

function createRelayRouter() {
  const router = express.Router();

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
      let data;
      try {
        data = readTail(LOG_FILE, lines);
      } catch (err) {
        if (err && err.code === 'ENOENT') {
          throw new ApiError(404, 400004, `日志文件不存在：${LOG_FILE}`);
        }
        throw new ApiError(500, 500000, `读取日志失败：${err.message}`);
      }
      const content = redact(data.lines.join('\n'));
      ok(res, {
        file: LOG_FILE,
        source: 'file',
        requestedLines: lines,
        count: data.lines.length,
        sizeBytes: data.size,
        mtime: data.mtime,
        truncated: Boolean(data.truncated),
        lines: content ? content.split('\n') : [],
      });
    })
  );

  return router;
}

module.exports = { createRelayRouter, SERVICE, LOG_FILE, RELAY_PORT, MAX_LOG_LINES, DEFAULT_LOG_LINES, redact };
