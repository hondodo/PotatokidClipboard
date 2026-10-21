import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(process.argv[2] ?? '.');
const SRC_LIB = path.join(ROOT, 'pscreen', 'potatokid_screen', 'lib');
const PKG = path.join(ROOT, 'packages', 'pscreen_screen');
const PKG_LIB = path.join(PKG, 'lib');

// 源前缀 -> 包内前缀。顺序敏感：长前缀在前，避免前缀互相覆盖。
const MOVES = [
  ['features/app/application/sleep_timer_controller.dart', 'core/media/sleep_timer_controller.dart'],
  ['features/app/application/video_aspect_mode.dart', 'core/media/video_aspect_mode.dart'],
  ['app/app_log.dart', 'app/app_log.dart'],
  ['app/config/', 'app/config/'],
  ['app/hosts/', 'app/hosts/'],
  ['core/logging/', 'core/logging/'],
  ['core/network/', 'core/network/'],
  ['core/utils/', 'core/utils/'],
  ['features/iptv/application/', 'features/iptv/application/'],
  ['features/iptv/data/', 'features/iptv/data/'],
  ['features/iptv/domain/', 'features/iptv/domain/'],
  ['features/msg/application/', 'features/msg/application/'],
  ['features/msg/protocol/', 'features/msg/protocol/'],
  ['features/remote/application/', 'features/remote/application/'],
  ['features/remote/data/', 'features/remote/data/'],
  ['features/remote/domain/', 'features/remote/domain/'],
  ['features/time/application/', 'features/time/application/'],
  ['features/time/domain/', 'features/time/domain/'],
  ['features/weather/application/', 'features/weather/application/'],
  ['features/weather/data/', 'features/weather/data/'],
  ['features/weather/domain/', 'features/weather/domain/'],
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

function movePlan() {
  const plan = [];
  for (const [from, to] of MOVES) {
    const srcRoot = path.join(SRC_LIB, from);
    if (fs.existsSync(srcRoot) && fs.statSync(srcRoot).isFile()) {
      plan.push({ from, to, file: srcRoot });
      continue;
    }
    for (const f of walk(srcRoot)) {
      const rel = path.relative(srcRoot, f).split(path.sep).join('/');
      plan.push({ from: `${from}${rel}`, to: `${to}${rel}`, file: f });
    }
  }
  return plan;
}

const plan = movePlan();
console.log(`待搬迁 ${plan.length} 个文件`);

const prefixMap = MOVES.map(([from, to]) => [from, to]);

// 改写 import：package:potatokid_screen/<src> -> package:pscreen_screen/<dst>
function rewrite(text) {
  let out = text;
  for (const [from, to] of prefixMap) {
    // MOVES 里的文件级条目已经带 `.dart` 后缀，目录级条目不带——两种都要覆盖到，
    // 否则会拼出 `.../app_log.dart.dart` 这种永远匹配不上的 key。
    const fromWithSlash = from.endsWith('/') ? from : (from.endsWith('.dart') ? from : `${from}.dart`);
    const toWithSlash = to.endsWith('/') ? to : (to.endsWith('.dart') ? to : `${to}.dart`);
    const stem = from.endsWith('/') ? from.slice(0, -1) : from;
    const toStem = to.endsWith('/') ? to.slice(0, -1) : to;
    out = out.replaceAll(
      `package:potatokid_screen/${fromWithSlash}`,
      `package:pscreen_screen/${toWithSlash}`,
    );
    // 目录前缀的 stem 形式（import 'package:x/core/utils/app_settings.dart'）
    if (from.endsWith('/')) {
      out = out.replaceAll(
        `package:potatokid_screen/${stem}`,
        `package:pscreen_screen/${toStem}`,
      );
    }
  }
  return out;
}

for (const { from, to, file } of plan) {
  const dest = path.join(PKG_LIB, to);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest, rewrite(fs.readFileSync(file, 'utf8')));
}

// 宿主侧剩余文件也要改写 import
for (const f of walk(SRC_LIB)) {
  if (plan.some((p) => p.file === f)) continue;
  const text = fs.readFileSync(f, 'utf8');
  const next = rewrite(text);
  if (next !== text) fs.writeFileSync(f, next);
}

// 删除源文件
for (const { file } of plan) {
  if (fs.existsSync(file)) fs.rmSync(file);
  pruneEmptyDirs(path.dirname(file));
}

// 源文件删空后，向上把空目录一并清掉——否则会留下空壳目录
// （例如 features/remote/application/ 迁空后仍留在宿主 app 里）。
function pruneEmptyDirs(dir) {
  let cur = dir;
  while (cur !== SRC_LIB && cur.startsWith(SRC_LIB)) {
    if (!fs.existsSync(cur)) break;
    if (fs.readdirSync(cur).length > 0) break;
    const parent = path.dirname(cur);
    if (parent === cur) break;
    fs.rmdirSync(cur);
    cur = parent;
  }
}

console.log(`搬迁完成：${plan.length} 个文件 -> ${path.relative(ROOT, PKG_LIB)}`);
