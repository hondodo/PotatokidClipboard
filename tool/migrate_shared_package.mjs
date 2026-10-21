import fs from 'node:fs';
import path from 'node:path';
import child_process from 'node:child_process';

const argv = process.argv.slice(2);
const ROOT = path.resolve(argv.find((a) => !a.startsWith('--')) ?? '.');
const DRY_RUN = argv.includes('--dry-run');
const FORCE = argv.includes('--force');

const SRC_LIB = path.join(ROOT, 'pscreen', 'potatokid_screen', 'lib');
const PKG = path.join(ROOT, 'packages', 'pscreen_screen');
const PKG_LIB = path.join(PKG, 'lib');

// 预期搬迁的文件数。数量对不上说明 MOVES 里有前缀写错、或源目录结构变了——
// 宁可报错停下，也不能只搬一半（半搬 = 宿主与包各持一份，import 指向混乱）。
const EXPECTED_COUNT = 66;

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

// 脚本会改写/删除的路径。迁移前工作区必须是干净的，否则脚本的改写会盖掉
// 未提交的修改（或者和未提交的新文件冲突）。
const AFFECTED_PATHS = [
  'pscreen/potatokid_screen/lib',
  'packages/pscreen_screen',
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
  const perPrefix = [];
  for (const [from, to] of MOVES) {
    const srcRoot = path.join(SRC_LIB, from);
    let hits = [];
    if (fs.existsSync(srcRoot) && fs.statSync(srcRoot).isFile()) {
      hits = [srcRoot];
    } else {
      hits = walk(srcRoot);
    }
    perPrefix.push({ from, to, count: hits.length });
    for (const f of hits) {
      const rel = path.relative(srcRoot, f).split(path.sep).join('/');
      plan.push({ from: `${from}${rel}`, to: `${to}${rel}`, file: f });
    }
  }
  return { plan, perPrefix };
}

function fail(msg) {
  console.error(`✗ ${msg}`);
  process.exit(1);
}

function gitStatus(paths) {
  try {
    const out = child_process.execSync(
      `git status --porcelain -- ${paths.map((p) => `"${p}"`).join(' ')}`,
      { cwd: ROOT, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] },
    );
    return out.split('\n').filter((l) => l.trim().length > 0);
  } catch {
    // git 不可用 / 不在仓库里：无法判定脏不脏，交给后面的断言兜底。
    return [];
  }
}

const { plan, perPrefix } = movePlan();
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

// ---------------------------------------------------------------------------
// --dry-run：只打印计划，不写、不改、不删。
// ---------------------------------------------------------------------------
if (DRY_RUN) {
  console.log(`试运行（--dry-run）：待搬迁 ${plan.length} 个文件`);
  for (const { from, to } of plan) {
    console.log(`  ${from} -> ${to}`);
  }
  if (plan.length === 0) {
    console.log('提示：源目录下已无待搬迁文件——这次迁移看起来已经执行过了。');
  } else {
    if (plan.length !== EXPECTED_COUNT) {
      console.log(`⚠ 计划文件数 ${plan.length} 与预期 ${EXPECTED_COUNT} 不符。`);
      console.log('  可能是 MOVES 里有前缀写错了。');
    }
    for (const p of perPrefix.filter((x) => x.count === 0)) {
      console.log(`⚠ 前缀没有匹配到任何文件：${p.from}`);
    }
  }
  console.log('试运行结束：没有写入、没有改写、没有删除任何文件。');
  process.exit(0);
}

// ---------------------------------------------------------------------------
// 以下是破坏性执行路径。
// ---------------------------------------------------------------------------

// 1) 已经不在"待搬迁"状态 → 拒绝破坏性重跑（--force 可跳过）。
if (plan.length === 0) {
  if (!FORCE) {
    console.error('✗ 没有待搬迁的文件：源目录下的目标文件都已不在原处。');
    console.error('  这次迁移看起来已经执行过了（脚本会删除源文件，重跑只会得到空计划）。');
    console.error('  如果确实想重新执行（例如只想重跑宿主侧的 import 改写），请显式加 --force。');
    process.exit(1);
  }
  console.warn('⚠ --force：0 个文件可搬迁，只重跑宿主侧的 import 改写。');
}

// 2) 工作区必须干净（--force 可跳过）——否则脚本的改写会盖掉未提交的修改。
if (!FORCE) {
  const dirty = gitStatus(AFFECTED_PATHS);
  if (dirty.length > 0) {
    console.error('✗ 受影响路径的工作区不干净，已中止（没有搬迁任何文件）：');
    for (const line of dirty) console.error(`  ${line}`);
    console.error('  先提交或 stash 这些改动再重跑；确实要强行执行请加 --force。');
    process.exit(1);
  }
}

// 3) 数量与前缀断言：搬一半比不搬更糟。
if (plan.length !== 0) {
  if (plan.length !== EXPECTED_COUNT) {
    fail(`计划文件数 ${plan.length} 与预期 ${EXPECTED_COUNT} 不符，已中止（没有搬迁任何文件）。`);
  }
  for (const p of perPrefix) {
    if (p.count === 0) {
      fail(`MOVES 前缀没有匹配到任何文件：${p.from} —— 可能是前缀写错了，已中止（没有搬迁任何文件）。`);
    }
  }
}

// 4) 写入包内目标文件。写完立刻复查目标确实落盘——否则后面的删除阶段
//    会把源文件删掉，内容就丢了。
for (const { to, file } of plan) {
  const dest = path.join(PKG_LIB, to);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest, rewrite(fs.readFileSync(file, 'utf8')));
  if (!fs.existsSync(dest)) {
    fail(`写入目标文件失败：${dest} 不存在，源文件保持不动。`);
  }
}

// 宿主侧剩余文件也要改写 import
for (const f of walk(SRC_LIB)) {
  if (plan.some((p) => p.file === f)) continue;
  const text = fs.readFileSync(f, 'utf8');
  const next = rewrite(text);
  if (next !== text) fs.writeFileSync(f, next);
}

// 6) 删除源文件。删除前逐个复查目标文件仍然在——目标丢失就绝不删源。
const missing = plan.filter(({ to }) => !fs.existsSync(path.join(PKG_LIB, to)));
if (missing.length > 0) {
  for (const { from, to } of missing) {
    console.error(`✗ 目标文件缺失，源文件保留：${from} -> ${to}`);
  }
  process.exit(1);
}
for (const { file } of plan) {
  if (fs.existsSync(file)) fs.rmSync(file);
  pruneEmptyDirs(path.dirname(file));
}

console.log(`搬迁完成：${plan.length} 个文件 -> ${path.relative(ROOT, PKG_LIB)}`);
