'use strict';

const fs = require('fs');
const path = require('path');
const { ensureDir, writeFilePrivate } = require('./config');

// 审计文件 datas/app_update/audit.jsonl：ts / actor / ip / action / target / before / after。
function createAudit(dataDir) {
  ensureDir(dataDir);
  const file = path.join(dataDir, 'audit.jsonl');
  if (!fs.existsSync(file)) writeFilePrivate(file, '');
  try {
    fs.chmodSync(file, 0o600);
  } catch (_) {
    /* ignore */
  }

  let queue = Promise.resolve();

  function log(entry) {
    const record = {
      ts: new Date().toISOString(),
      actor: entry.actor || 'system',
      ip: entry.ip || '',
      action: entry.action,
      target: entry.target || '',
      before: entry.before === undefined ? null : entry.before,
      after: entry.after === undefined ? null : entry.after,
    };
    queue = queue.then(
      () =>
        new Promise((resolve) => {
          fs.appendFile(file, JSON.stringify(record) + '\n', { mode: 0o600 }, () => resolve());
        })
    );
    return queue;
  }

  return { log, file };
}

module.exports = { createAudit };
