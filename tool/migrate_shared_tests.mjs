import fs from 'node:fs';
import path from 'node:path';
import child_process from 'node:child_process';

const argv = process.argv.slice(2);
const ROOT = path.resolve(argv.find((a) => !a.startsWith('--')) ?? '.');
const DRY_RUN = argv.includes('--dry-run');
const FORCE = argv.includes('--force');

const HOST_TEST = path.join(ROOT, 'pscreen', 'potatokid_screen', 'test');
const PKG_TEST = path.join(ROOT, 'packages', 'pscreen_screen', 'test');

// 预期迁移的测试文件数。数量对不上说明 MOVES 写错了、或源目录结构变了——
// 宁可报错停下，也不能只搬一半（半搬 = 宿主与包各持一份，测试跑两遍）。
const EXPECTED_COUNT = 11;

// 源测试（宿主 test/ 下的相对路径）-> 包内测试（包 test/ 下的相对路径）。
const MOVES = [
  ['core/utils/app_settings_test.dart', 'core/utils/app_settings_test.dart'],
  ['core/utils/wordpress_util_test.dart', 'core/utils/wordpress_util_test.dart'],
  ['core/platform_channel_service_test.dart', 'core/utils/platform_channel_service_test.dart'],
  ['features/msg/message_envelope_test.dart', 'features/msg/protocol/message_envelope_test.dart'],
  ['features/msg/message_overlay_controller_test.dart', 'features/msg/application/message_overlay_controller_test.dart'],
  ['features/msg/message_router_test.dart', 'features/msg/application/message_router_test.dart'],
  ['features/msg/reporting_service_test.dart', 'features/msg/application/reporting_service_test.dart'],
  ['features/remote/remote_login_bloc_test.dart', 'features/remote/application/remote_login_bloc_test.dart'],
  ['features/remote/remote_login_repository_impl_test.dart', 'features/remote/data/remote_login_repository_impl_test.dart'],
  ['channel_name_matcher_test.dart', 'features/iptv/domain/channel_name_matcher_test.dart'],
  ['channel_name_normalizer_test.dart', 'features/iptv/domain/channel_name_normalizer_test.dart'],
];

// 宿主 import 前缀 -> 包内 import 前缀。
//
// 这里**不能**用一刀切的 `package:potatokid_screen/` -> `package:pscreen_screen/`：
// 仍留在电视端的代码（例如 features/app/application/app_tab_controller.dart）
// 会被改写成"包依赖宿主"的非法 import。共享包只认白名单里的这些前缀。
//
// 顺序敏感：长前缀在前，避免前缀互相覆盖。
const PREFIXES = [
  ['core/di/get_it.dart', 'core/di/get_it.dart'],
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
  'pscreen/potatokid_screen/test',
  'packages/pscreen_screen/test',
];

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

// 改写 import：package:potatokid_screen/<src 前缀> -> package:pscreen_screen/<dst 前缀>
function rewrite(text) {
  let out = text;
  for (const [from, to] of PREFIXES) {
    // PREFIXES 里的文件级条目已经带 `.dart` 后缀，目录级条目不带——两种都要覆盖到，
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

// 源文件删空后，向上把空目录一并清掉——否则宿主 test/ 下会留下空壳目录。
function pruneEmptyDirs(dir) {
  let cur = dir;
  while (cur !== HOST_TEST && cur.startsWith(HOST_TEST)) {
    if (!fs.existsSync(cur)) break;
    if (fs.readdirSync(cur).length > 0) break;
    const parent = path.dirname(cur);
    if (parent === cur) break;
    fs.rmdirSync(cur);
    cur = parent;
  }
}

// ---------------------------------------------------------------------------
// 计划：逐个 MOVES 解析成 源绝对路径 -> 目标绝对路径
// ---------------------------------------------------------------------------
const plan = [];
const missing = [];
for (const [from, to] of MOVES) {
  const src = path.join(HOST_TEST, from);
  const dest = path.join(PKG_TEST, to);
  if (!fs.existsSync(src)) {
    missing.push(from);
    continue;
  }
  plan.push({ from, to, src, dest });
}

// ---------------------------------------------------------------------------
// --dry-run：只打印计划，不写、不改、不删。
// ---------------------------------------------------------------------------
if (DRY_RUN) {
  console.log(`试运行（--dry-run）：待迁移 ${plan.length} 个测试文件`);
  for (const { from, to } of plan) {
    console.log(`  ${from} -> ${to}`);
  }
  if (plan.length === 0) {
    console.log('提示：源目录下已无待迁移文件——这次迁移看起来已经执行过了。');
  }
  if (missing.length > 0) {
    console.log('⚠ 以下源文件不存在（迁移会中止）：');
    for (const m of missing) console.log(`  ${m}`);
  }
  if (plan.length !== EXPECTED_COUNT) {
    console.log(`⚠ 计划文件数 ${plan.length} 与预期 ${EXPECTED_COUNT} 不符。`);
  }
  console.log('试运行结束：没有写入、没有改写、没有删除任何文件。');
  process.exit(0);
}

// ---------------------------------------------------------------------------
// 以下是破坏性执行路径。
// ---------------------------------------------------------------------------

// 1) 已经不在"待迁移"状态 → 拒绝破坏性重跑（--force 可跳过）。
if (plan.length === 0) {
  if (!FORCE) {
    console.error('✗ 没有待迁移的测试文件：源目录下的目标文件都已不在原处。');
    console.error('  这次迁移看起来已经执行过了（脚本会删除源文件，重跑只会得到空计划）。');
    console.error('  如果确实想重新执行，请显式加 --force。');
    process.exit(1);
  }
  console.warn('⚠ --force：0 个文件可迁移，只重跑宿主侧的 import 改写。');
}

// 2) 工作区必须干净（--force 可跳过）——否则脚本的改写会盖掉未提交的修改。
if (!FORCE) {
  const dirty = gitStatus(AFFECTED_PATHS);
  if (dirty.length > 0) {
    console.error('✗ 受影响路径的工作区不干净，已中止（没有迁移任何文件）：');
    for (const line of dirty) console.error(`  ${line}`);
    console.error('  先提交或 stash 这些改动再重跑；确实要强行执行请加 --force。');
    process.exit(1);
  }
}

// 3) 数量与源文件断言：搬一半比不搬更糟。--force 也不能跳过这两条。
if (plan.length !== EXPECTED_COUNT) {
  fail(`计划文件数 ${plan.length} 与预期 ${EXPECTED_COUNT} 不符，已中止（没有迁移任何文件）。`);
}
if (missing.length > 0) {
  for (const m of missing) console.error(`✗ 源文件缺失：${m}`);
  fail(`有 ${missing.length} 个源文件不存在，已中止（没有迁移任何文件）。`);
}

// 4) 写入包内目标文件。写完立刻复查目标确实落盘——否则后面的删除阶段
//    会把源文件删掉，内容就丢了。
for (const { to, src, dest } of plan) {
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest, rewrite(fs.readFileSync(src, 'utf8')));
  if (!fs.existsSync(dest)) {
    fail(`写入目标文件失败：${to} 不存在，源文件保持不动。`);
  }
}

// 5) 复查：所有目标文件都存在，才允许删除源文件。
const lost = plan.filter(({ dest }) => !fs.existsSync(dest));
if (lost.length > 0) {
  for (const { from, to } of lost) {
    console.error(`✗ 目标文件缺失，源文件保留：${from} -> ${to}`);
  }
  process.exit(1);
}

// 6) 删除源文件，并清掉空目录。
for (const { src } of plan) {
  if (fs.existsSync(src)) fs.rmSync(src);
  pruneEmptyDirs(path.dirname(src));
}

console.log(`迁移完成：${plan.length} 个测试文件 -> ${path.relative(ROOT, PKG_TEST)}`);
for (const { from, to } of plan) {
  console.log(`  ${from} -> ${to}`);
}
