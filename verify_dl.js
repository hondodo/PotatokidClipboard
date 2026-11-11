'use strict';
const fs = require('fs');
const crypto = require('crypto');
const http = require('http');
const hex = fs.readFileSync('/home/honghao/services/app_server/datas/app_update/secret.key', 'utf8').trim();
const secret = Buffer.from(hex, 'hex');
const ids = {
  universal: 'rel_20261111092848_4e9a81',
  'arm64-v8a': 'rel_20261111092848_2978d9',
  'armeabi-v7a': 'rel_20261111092848_f7925f',
};
function head(id) {
  const exp = Math.floor(Date.now() / 1000) + 600;
  const sig = crypto.createHmac('sha256', secret).update(id + '.' + exp).digest('base64url');
  const url = '/api/download/' + id + '?exp=' + exp + '&sig=' + encodeURIComponent(sig);
  return new Promise((res) => {
    const req = http.request({ host: '127.0.0.1', port: 47292, path: url, method: 'HEAD' }, (r) => {
      console.log(id, '->', r.statusCode, 'content-length:', r.headers['content-length'], 'content-type:', r.headers['content-type']);
      r.resume();
      res();
    });
    req.on('error', (e) => { console.log(id, 'ERR', e.message); res(); });
    req.end();
  });
}
(async () => { for (const id of Object.values(ids)) { await head(id); } })();
