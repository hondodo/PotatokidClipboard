import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(process.argv[2] ?? '.');
const HOME = path.join(ROOT, 'pscreen_home');

const FILE_MOVES = [
  ['lib/app/config/app_config.dart', 'lib/app/config/ha_config.dart'],
  ['lib/core/network/net_exceptions.dart', 'lib/core/network/ha_net_exceptions.dart'],
  ['lib/core/utils/error_message.dart', 'lib/core/utils/ha_error_message.dart'],
];

const SYMBOL_RENAMES = [
  ['AppConfig', 'HaConfig'],
  ['NetErrorType', 'HaErrorType'],
  ['NetExceptionX', 'HaExceptionX'],
  ['mapErrorToMessage', 'mapHaErrorToMessage'],
];

const IMPORT_RENAMES = [
  ['package:pscreen_home/app/config/app_config.dart', 'package:pscreen_home/app/config/ha_config.dart'],
  ['package:pscreen_home/core/network/net_exceptions.dart', 'package:pscreen_home/core/network/ha_net_exceptions.dart'],
  ['package:pscreen_home/core/utils/error_message.dart', 'package:pscreen_home/core/utils/ha_error_message.dart'],
];

function walk(dir, out = []) {
  if (!fs.existsSync(dir)) return out;
  for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (e.name.endsWith('.dart')) out.push(p);
  }
  return out;
}

const targets = walk(path.join(HOME, 'lib')).concat(walk(path.join(HOME, 'test')));

let changed = 0;
for (const file of targets) {
  let text = fs.readFileSync(file, 'utf8');
  const before = text;
  for (const [from, to] of IMPORT_RENAMES) {
    text = text.replaceAll(from, to);
  }
  for (const [from, to] of SYMBOL_RENAMES) {
    text = text.replace(new RegExp(`\\b${from}\\b`, 'g'), to);
  }
  if (text !== before) {
    fs.writeFileSync(file, text);
    changed++;
    console.log(`改写：${path.relative(HOME, file).split(path.sep).join('/')}`);
  }
}

for (const [from, to] of FILE_MOVES) {
  const src = path.join(HOME, from);
  const dest = path.join(HOME, to);
  if (!fs.existsSync(src)) {
    console.log(`跳过（不存在）：${from}`);
    continue;
  }
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest, fs.readFileSync(src, 'utf8'));
  fs.rmSync(src);
  console.log(`重命名：${from} -> ${to}`);
}

console.log(`共改写 ${changed} 个文件`);
