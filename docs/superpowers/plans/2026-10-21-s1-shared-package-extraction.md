# S1 共享包抽取（packages/pscreen_screen）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `potatokid_screen` 的屏幕侧能力层（66 个文件）抽成独立 Flutter package `packages/pscreen_screen`，`potatokid_screen` 改为 path 依赖它且**行为完全不变**。

**Architecture:** 新建 `packages/pscreen_screen`（只含 data/domain/application + core 基础设施，不含任何 presentation）。`potatokid_screen` 保留外壳（router / DI 根 / features/app / features/home / features/profile / presentation），改为 `pscreen_screen: {path: ../packages/pscreen_screen}`。共享包**不持有 DI 根**，用 `GetIt.instance`（两个宿主都用全局单例）自行注册。

**Tech Stack:** Flutter 3.41.9 / Dart 3.11.5、get_it 9.3、flutter_bloc 9.1、dio 5.11、nim_core_v2 10.9

**设计依据：** `docs/superpowers/specs/2026-10-21-screen-capability-shared-package-design.md` §二、§五、§九

---

## 本阶段的验收门槛

| # | 门槛 |
| --- | --- |
| G1 | `packages/pscreen_screen` 内 `flutter analyze` 零错误零警告 |
| G2 | `packages/pscreen_screen` 内 `flutter test` 全绿（迁移过来的测试） |
| G3 | `potatokid_screen` 内 `flutter analyze` 零错误零警告 |
| G4 | `potatokid_screen` 内 `flutter test` 全绿 |
| G5 | `potatokid_screen` `flutter build windows --debug` 成功（现有发布产物不受影响） |

G1–G4 全绿之前，不得开始 S2。

## 阶段内新增的两个抽象（spec 未覆盖，实施时必须一并落地）

| 抽象 | 原因 | 落地位置 |
| --- | --- | --- |
| `ScreenAssets` | Flutter **不会**自动把依赖包的资产打进宿主 bundle；包内代码用 `rootBundle.load('assets/...')` 在宿主里必然 404。包内硬编码路径必须可被宿主改写 | `packages/pscreen_screen/lib/app/config/screen_assets.dart` |
| `CurrentSceneProvider` | `ReportingService.positionText()` 直接读宿主级 `AppTabController.branchIndex` / `pageName`，抽包后宿主（电视端）有 Tab、中控屏没有 → 必须改成注入 | `packages/pscreen_screen/lib/features/msg/application/current_scene_provider.dart` |

---

### Task 1: 创建共享包骨架与 `ScreenAssets`

**Files:**
- Create: `packages/pscreen_screen/pubspec.yaml`
- Create: `packages/pscreen_screen/analysis_options.yaml`
- Create: `packages/pscreen_screen/lib/core/di/get_it.dart`
- Create: `packages/pscreen_screen/lib/core/di/screen_injection.dart`
- Create: `packages/pscreen_screen/lib/app/config/screen_assets.dart`
- Create: `packages/pscreen_screen/test/app/config/screen_assets_test.dart`

- [x] **Step 1: 写失败测试**

Create `packages/pscreen_screen/test/app/config/screen_assets_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/app/config/screen_assets.dart';

void main() {
  group('ScreenAssets', () {
    setUp(() => ScreenAssets.configure(root: ''));

    test('默认根路径为空，path 直接拼接相对路径', () {
      expect(ScreenAssets.path('assets/datas/tv_name_order.txt'),
          'assets/datas/tv_name_order.txt');
    });

    test('宿主可改写根路径以命中依赖包前缀', () {
      ScreenAssets.configure(root: 'packages/pscreen_screen/');
      expect(ScreenAssets.path('assets/datas/tv_name_order.txt'),
          'packages/pscreen_screen/assets/datas/tv_name_order.txt');
    });

    test('configure 归一化：去掉首尾斜杠并补上尾部斜杠', () {
      ScreenAssets.configure(root: 'packages/pscreen_screen');
      expect(ScreenAssets.root, 'packages/pscreen_screen/');
      ScreenAssets.configure(root: '/assets');
      expect(ScreenAssets.root, 'assets/');
    });

    test('configure 归一化边界输入', () {
      const Map<String, String> cases = <String, String>{
        '': '',
        '/': '',
        '///': '',
        '   ': '',
        'packages/x': 'packages/x/',
        'packages/x/': 'packages/x/',
        'packages/x///': 'packages/x/',
        '/packages/x/': 'packages/x/',
        '  packages/x  ': 'packages/x/',
      };
      cases.forEach((String input, String expected) {
        ScreenAssets.configure(root: input);
        expect(ScreenAssets.root, expected, reason: 'input: "$input"');
      });
    });

    test('path 去掉 relative 的前导斜杠，不产生双斜杠', () {
      ScreenAssets.configure(root: 'packages/pscreen_screen');
      expect(ScreenAssets.path('/assets/datas/x.txt'),
          'packages/pscreen_screen/assets/datas/x.txt');
    });

    test('isConfigured 表示是否调用过 configure', () {
      expect(ScreenAssets.isConfigured, isTrue);
    });

    test('空根前缀对共享包自身合法，但宿主自检会抛异常', () {
      ScreenAssets.configure(root: '');
      expect(ScreenAssets.root, '');
      expect(() => ScreenAssets.requireHostConfigured(), throwsStateError);

      ScreenAssets.configure(root: 'packages/pscreen_screen/');
      expect(() => ScreenAssets.requireHostConfigured(), returnsNormally);
    });
  });
}
```

- [x] **Step 2: 运行测试确认失败**

Run: `cd packages/pscreen_screen && flutter test test/app/config/screen_assets_test.dart`
Expected: FAIL —— `Target of URI doesn't exist: 'package:pscreen_screen/app/config/screen_assets.dart'`

- [x] **Step 3: 建包骨架**

Create `packages/pscreen_screen/pubspec.yaml`:

```yaml
name: pscreen_screen
description: 屏幕能力共享包（IPTV / 天气 / 时钟 / 消息协议 / 网络基础设施），只含能力层，不含 UI。
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.11.5

dependencies:
  flutter:
    sdk: flutter

  flutter_bloc: ^9.1.1
  bloc_concurrency: ^0.3.0
  get_it: ^9.3.0
  dio: ^5.11.1
  dio_cookie_manager: ^3.5.0
  pretty_dio_logger: ^1.4.0
  cookie_jar: ^4.0.9
  connectivity_plus: ^7.3.1
  flutter_dotenv: ^6.0.1
  path_provider: ^2.1.6
  freezed_annotation: ^3.1.0
  json_annotation: ^4.12.0
  intl: ^0.20.2
  shared_preferences: ^2.5.1
  crypto: ^3.0.6
  package_info_plus: ^10.2.1
  nim_core_v2: ^10.9.91

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
  build_runner: ^2.15.1
  freezed: ^3.2.5
  json_serializable: ^6.14.1
  mockito: ^5.6.4
  fake_async: ^1.3.0

flutter:
  # 共享包自己的资产（供本包的 `flutter test` 使用）。
  # 注意：**宿主必须在自己的 pubspec.yaml 里另行声明**
  # `packages/pscreen_screen/assets/datas/`——Flutter 不会把依赖包的资产
  # 自动打进宿主 bundle，宿主不声明就会 404。
  assets:
    - assets/datas/
```

Create `packages/pscreen_screen/analysis_options.yaml`:

```yaml
include: package:flutter_lints/flutter.yaml

linter:
  rules:
    prefer_single_quotes: true
    require_trailing_commas: true
    avoid_print: true
    unawaited_futures: true
```

Create `packages/pscreen_screen/lib/core/di/get_it.dart`（与两个宿主的 `core/di/get_it.dart` 逐字一致）:

```dart
import 'package:get_it/get_it.dart';

/// 全局 get_it 实例
///
/// 注意：宿主**不要**与自己的 `core/di/get_it.dart` 同时 import 本文件
/// —— 两边都有同名的 `getIt` / `GetItConfig`，同时 import 会产生歧义引用错误。
/// 共享包内部只用本文件；宿主侧继续用自己的那份。
final GetIt getIt = GetIt.instance;

/// get_it 的底层封装（初始化 / 重置）
class GetItConfig {
  const GetItConfig._();

  static Future<void> init() async => getIt.reset();

  static Future<void> reset() async => getIt.reset();
}
```

Create `packages/pscreen_screen/lib/core/di/screen_injection.dart`:

```dart
import 'package:pscreen_screen/core/di/get_it.dart';

/// 共享包的依赖解析门面。
///
/// 两个宿主（`pscreen_home` / `potatokid_screen`）都使用 `GetIt.instance`
/// 全局单例，因此共享包无需持有 DI 根，直接复用同一实例即可。
/// 宿主在 `Injection.init()` 中调用 `ScreenModules.register(getIt)` 完成注册。
class ScreenInjection {
  const ScreenInjection._();

  static T get<T extends Object>() => getIt<T>();
}
```

Create `packages/pscreen_screen/lib/app/config/screen_assets.dart`:

```dart
/// 共享包内资产路径的根前缀。
///
/// Flutter 只把**宿主** pubspec 中声明的资产打进 bundle；依赖包的资产必须由
/// 宿主以 `packages/<包名>/...` 形式声明，且包内代码要用同样的前缀读取。
/// 因此这里把前缀做成可配置。
///
/// 两种场景的根前缀不同：
/// - **共享包自身**（跑自己的 `flutter test`）：根前缀为空 `''`，资产键就是
///   `assets/datas/x.txt`（包自己的 pubspec 声明了 `assets/datas/`）。
/// - **宿主 App**：根前缀为 `packages/pscreen_screen/`，资产键是
///   `packages/pscreen_screen/assets/datas/x.txt`。
///
/// **使用约定**：[path] 应在**读取资产的那一刻**调用，不要把结果缓存下来 ——
/// 宿主可能在首次读取之后才调用 [configure]。
class ScreenAssets {
  const ScreenAssets._();

  /// 资产根前缀，末尾恒为 `/`。
  static String _root = '';

  /// 是否已调用过 [configure]（与根前缀是否为空无关）。
  static bool _configured = false;

  /// 当前根前缀。
  static String get root => _root;

  /// 宿主是否已完成接入配置（调用过 [configure]）。
  ///
  /// 宿主**必须**在读取任何共享包资产之前调用 [configure]：忘记配置会让所有
  /// 资产读取 404 且被上层 `catch` 吞掉，表现为「频道规则为空、城市列表为空」
  /// 这类静默故障。宿主用 [requireHostConfigured] 在启动期把它变成显式失败。
  static bool get isConfigured => _configured;

  /// 设置根前缀：自动补尾部 `/`、去掉头部 `/`。
  ///
  /// 传入空串是合法的（共享包自身场景）。
  static void configure({required String root}) {
    var normalized = root.trim();
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    while (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    _root = normalized.isEmpty ? '' : '$normalized/';
    _configured = true;
  }

  /// 宿主接入自检：根前缀为空时抛 [StateError]。
  ///
  /// **只在宿主启动路径调用**（紧接 [configure] 之后）——共享包自身跑测试时
  /// 根前缀为空是合法的。放在启动期的好处是「忘记 configure」立刻失败，
  /// 而不是等到第一次读资产时被 `catch` 吞掉、变成运行期的静默降级。
  static void requireHostConfigured() {
    if (_root.isEmpty) {
      throw StateError(
        'ScreenAssets 未配置：宿主必须先调用 '
        'ScreenAssets.configure(root: "packages/pscreen_screen/")，'
        '并在其后调用 ScreenAssets.requireHostConfigured() 做接入自检；'
        '否则依赖包的资产无法被读取。',
      );
    }
  }

  /// 拼出最终可被 `rootBundle.load` 读取的路径。
  ///
  /// [relative] 里的前导斜杠会被去掉，避免与根前缀拼出双斜杠。
  static String path(String relative) {
    var rel = relative.trim();
    while (rel.startsWith('/')) {
      rel = rel.substring(1);
    }
    return '$_root$rel';
  }
}
```

- [x] **Step 4: 拉依赖**

Run: `cd packages/pscreen_screen; $env:PUB_HOSTED_URL="https://pub.flutter-io.cn"; flutter pub get`
Expected: `Got dependencies!`

> **全局约定**：本仓库的 `pubspec.lock` 使用 `https://pub.flutter-io.cn` 镜像源。执行 `flutter pub get` 前先设 `$env:PUB_HOSTED_URL="https://pub.flutter-io.cn"`，否则 lock 文件会被整体改写成 `https://pub.dev`，产生上百行无意义 diff。

- [x] **Step 5: 运行测试确认通过**

Run: `cd packages/pscreen_screen && flutter test test/app/config/screen_assets_test.dart`
Expected: PASS —— 7 tests passed

- [x] **Step 6: 提交**

```bash
git add packages/pscreen_screen
git commit -m "feat(screen): 建立 pscreen_screen 共享包骨架与 ScreenAssets 资产路径抽象"
```

---

### Task 2: 执行搬迁（脚本一次搬完 66 个文件）

**Files:**
- Create: `packages/pscreen_screen/lib/**`（66 个文件，由脚本从 `pscreen/potatokid_screen/lib` 迁入）
- Create: `packages/pscreen_screen/assets/datas/**`（9 个数据文件）
- Create: `tool/migrate_shared_package.mjs`
- Delete: `pscreen/potatokid_screen/lib/` 下对应的 66 个文件
- Modify: `pscreen/potatokid_screen/lib/` 下剩余文件（import 前缀改写）

- [ ] **Step 1: 写搬迁脚本**

Create `tool/migrate_shared_package.mjs`:

```javascript
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
    const fromWithSlash = from.endsWith('/') ? from : `${from}.dart`;
    const toWithSlash = to.endsWith('/') ? to : `${to}.dart`;
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
  const dir = path.dirname(file);
  if (fs.existsSync(dir) && fs.readdirSync(dir).length === 0) fs.rmdirSync(dir);
}

console.log(`搬迁完成：${plan.length} 个文件 -> ${path.relative(ROOT, PKG_LIB)}`);
```

- [ ] **Step 2: 试运行脚本并核对文件数**

Run: `node tool/migrate_shared_package.mjs "E:/Code/potatokid_clipboard"`
Expected: 输出 `待搬迁 66 个文件` 与 `搬迁完成：66 个文件`

核对：

```bash
node -e "const fs=require('fs');const p='packages/pscreen_screen/lib';let n=0;(function w(d){for(const e of fs.readdirSync(d,{withFileTypes:true})){const q=d+'/'+e.name;e.isDirectory()?w(q):(e.name.endsWith('.dart')&&n++)}})(p);console.log('包内 dart 文件数:',n)"
```

Expected: `包内 dart 文件数: 66`（不含 Task 1 建的 4 个 → 实际应为 70；用 `>= 66` 判定）

- [ ] **Step 3: 把包内资产复制进共享包**

```bash
mkdir -p packages/pscreen_screen/assets
cp -r pscreen/potatokid_screen/assets/datas packages/pscreen_screen/assets/
```

Run: `ls packages/pscreen_screen/assets/datas`
Expected: 列出 `tv_name_order.txt`、`tv_name_hide.txt`、`weather_cities.txt`、`collect.m3u`、`guovin-api.m3u`、`audio.m3u`、`remove_source.txt`、`remove_source_contains.txt`、`not_remove_source.txt`

```bash
rm -f packages/pscreen_screen/assets/datas/.gitkeep
```

Run: `ls packages/pscreen_screen/assets/datas`
Expected: 只列出 9 个真实数据文件，**没有** `.gitkeep`
（占位文件会跟着被打进两个宿主的 bundle，是多余的）

- [ ] **Step 4: 核对 import 改写结果**

Run: `grep -rn "package:potatokid_screen/core/\|package:potatokid_screen/app/\|package:potatokid_screen/features/iptv/\|package:potatokid_screen/features/msg/\|package:potatokid_screen/features/remote/\|package:potatokid_screen/features/time/\|package:potatokid_screen/features/weather/" packages/pscreen_screen/lib pscreen/potatokid_screen/lib`
Expected: 无输出（所有被迁走的引用都已改为 `package:pscreen_screen/...`）

Run: `grep -rn "package:pscreen_screen/" pscreen/potatokid_screen/lib | head -20`
Expected: 有输出（电视端剩余文件引用共享包的新路径），且每一条对应的目标文件在 `packages/pscreen_screen/lib` 下确实存在

- [ ] **Step 5: 提交（机械搬迁完成，尚未编译通过）**

```bash
git add packages/pscreen_screen tool/migrate_shared_package.mjs
git add -A pscreen/potakid_screen/lib pscreen/potatokid_screen/lib
git commit -m "refactor(screen): 一次性搬迁 66 个能力层文件到 pscreen_screen 共享包"
```

> 本次提交处于**中间态**（包内尚有宿主 DI 依赖与资产路径待修，见 Task 3–5），允许 `flutter analyze` 报错。

---

### Task 3: 修包内的宿主 DI 依赖与资产路径

**Files:**
- Modify: `packages/pscreen_screen/lib/core/media/sleep_timer_controller.dart`
- Modify: `packages/pscreen_screen/lib/app/app_log.dart`
- Modify: `packages/pscreen_screen/lib/app/config/data_files.dart`
- Modify: `packages/pscreen_screen/lib/features/iptv/application/bloc/iptv_bloc.dart`
- Modify: `packages/pscreen_screen/lib/features/iptv/application/channel_failure_guard.dart`
- Modify: `packages/pscreen_screen/lib/features/iptv/data/datasources/remote/proxy_pool_service.dart`
- Modify: `packages/pscreen_screen/lib/features/weather/application/bloc/weather_bloc.dart`

- [ ] **Step 1: 列出包内所有残留的宿主 DI 引用**

Run: `grep -rn "Injection.get<" packages/pscreen_screen/lib`
Expected: 列出全部命中（应为 7 个文件：`sleep_timer_controller` / `app_log` / `data_files` / `iptv_bloc` / `channel_failure_guard` / `proxy_pool_service` / `weather_bloc`）

Run: `grep -rn "package:pscreen_screen/core/di/injection.dart" packages/pscreen_screen/lib`
Expected: 无输出（脚本已把 import 路径改成了 `package:pscreen_screen/core/di/injection.dart`，但该文件**尚未存在于共享包**——这正是本任务要消除的依赖）

- [ ] **Step 2: 修 `sleep_timer_controller`**

`packages/pscreen_screen/lib/core/media/sleep_timer_controller.dart`：

import 区删除

```dart
import 'package:pscreen_screen/core/di/injection.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';
```

改为

```dart
import 'package:pscreen_screen/app/app_log.dart';
```

并把方法体内的

```dart
Injection.get<LogService>().info('[SleepTimer] 定时关闭生效，退出应用');
```

替换为

```dart
Log.info('[SleepTimer] 定时关闭生效，退出应用');
```

- [ ] **Step 3: 修 `app_log.dart` 与 `data_files.dart`**

`packages/pscreen_screen/lib/app/app_log.dart`：把 import 改为

```dart
import 'package:pscreen_screen/core/di/screen_injection.dart';
```

并把 `Injection.get<LogService>()` 改为 `ScreenInjection.get<LogService>()`。

`packages/pscreen_screen/lib/app/config/data_files.dart`：import 改为

```dart
import 'package:pscreen_screen/core/di/screen_injection.dart';
```

并把其中所有 `Injection.get<...>()` 改为 `ScreenInjection.get<...>()`。

- [ ] **Step 4: 修 iptv 的三个文件**

以下三个文件的 import 改为 `package:pscreen_screen/core/di/screen_injection.dart`，并把 `Injection.get<X>()` 改为 `ScreenInjection.get<X>()`：

- `packages/pscreen_screen/lib/features/iptv/application/bloc/iptv_bloc.dart`
- `packages/pscreen_screen/lib/features/iptv/application/channel_failure_guard.dart`
- `packages/pscreen_screen/lib/features/iptv/data/datasources/remote/proxy_pool_service.dart`

- [ ] **Step 5: 修 `weather_bloc`**

`packages/pscreen_screen/lib/features/weather/application/bloc/weather_bloc.dart`：import 改为 `package:pscreen_screen/core/di/screen_injection.dart`，`Injection.get<LogService>()` → `ScreenInjection.get<LogService>()`。

- [ ] **Step 6: 资产路径改用 `ScreenAssets`（前缀只在读取点应用）**

`packages/pscreen_screen/lib/app/config/data_files.dart`：

**不要**把前缀写进 `DataFile` 模型（它是 `const` 构造 + `static const` 列表，
写死前缀既破坏 const 又会在首次访问时快照下当时的根前缀）。

只改**唯一的资产读取点**：找到读取包内资产的那个方法（形如 `_readAsset(DataFile file)`，
内部用 `rootBundle.loadString(file.assetPath)`），把读取那一行改成：

```dart
      return await rootBundle.loadString(ScreenAssets.path(file.assetPath));
```

**不要**在这里加任何配置校验：该方法有 `catch` 兜底，任何异常都会被吞成空串，
把校验放进来等于没有校验。宿主接入自检（`ScreenAssets.requireHostConfigured()`）
放在宿主的启动路径里做，见 S2 Task 6。

`DataFile.assetPath` 保持**相对路径**（`'assets/datas/xxx.txt'`）不变，
`DataFile` 类与 `_files` 列表一个字都不动。
另加 import `package:pscreen_screen/app/config/screen_assets.dart`。

- [ ] **Step 7: 复查零残留**

Run: `grep -rn "package:pscreen_screen/core/di/injection.dart\|Injection.get<" packages/pscreen_screen/lib`
Expected: 无输出

- [ ] **Step 8: 包内分析**

Run: `cd packages/pscreen_screen && flutter pub get && flutter analyze`
Expected: 仅剩 Task 4（`ReportingService` 的 `AppTabController` 依赖）与 Task 5（DI 入口尚未搬入）相关报错；其余均为 0。

> `flutter pub get` 请带镜像：`$env:PUB_HOSTED_URL="https://pub.flutter-io.cn"; flutter pub get`，与仓库既有 lock 文件的源保持一致。

- [ ] **Step 9: 提交**

```bash
git add -A packages/pscreen_screen
git commit -m "refactor(screen): 共享包解除宿主 DI 依赖，资产路径改用 ScreenAssets"
```

---

### Task 4: `CurrentSceneProvider` 抽象与 `ReportingService` 解耦

**Files:**
- Create: `packages/pscreen_screen/lib/features/msg/application/current_scene_provider.dart`
- Modify: `packages/pscreen_screen/lib/features/msg/application/reporting_service.dart`
- Modify: `packages/pscreen_screen/lib/features/msg/application/message_overlay_controller.dart`

- [ ] **Step 1: 新增 `CurrentSceneProvider` 抽象**

Create `packages/pscreen_screen/lib/features/msg/application/current_scene_provider.dart`:

```dart
/// 当前所在场景的描述（供上行上报使用）。
///
/// 抽象原因：电视端有 4-tab 外壳（页名由 Tab 决定），中控屏没有 Tab
/// （页名恒为「中控台」）。共享包不能依赖任一宿主的导航实现。
abstract class CurrentSceneProvider {
  const CurrentSceneProvider();

  /// 当前场景的可读描述，例：「正在收看 CCTV-1」「停留在中控台」。
  String describe();
}
```

- [ ] **Step 2: 改写 `ReportingService` 去掉 `AppTabController` 依赖**

在 `packages/pscreen_screen/lib/features/msg/application/reporting_service.dart`：

删除 import：

```dart
import 'package:potatokid_screen/features/app/application/app_tab_controller.dart';
```

在 import 区加入：

```dart
import 'package:pscreen_screen/features/msg/application/current_scene_provider.dart';
```

构造器参数列表中新增 `required this.sceneProvider`，字段区新增：

```dart
  /// 当前场景描述提供者（由宿主注入）。
  final CurrentSceneProvider sceneProvider;
```

把 `positionText()` 方法体替换为：

```dart
  /// 当前位置文本：在频道上报频道名，否则报当前场景描述。
  String positionText() {
    final String? name = channelInfo.nameAt(liveChannel.index);
    if (name != null) return name;
    return sceneProvider.describe();
  }
```

> 原实现是「仅当 `AppTabController.branchIndex == 0`（首页）时才报频道名，否则报页名」。新实现改为「有频道名就报频道名，否则报场景描述」—— 对电视端而言 `AppTabController.pageName` 在非首页时返回「时间页 / 屏保 / 设置」，而频道名在首页才有意义，两者语义一致。

- [ ] **Step 3: 改写 `message_overlay_controller.dart` 的文档注释**

该文件仅在注释里提到 `AppTabController`（无 import），把注释改为不指向宿主类：

```dart
  /// 屏保互斥：真值由宿主外壳依自身导航状态填充。
  bool deferActive = false;
```

- [ ] **Step 4: 确认包内不再引用宿主外壳**

Run: `grep -rn "app_tab_controller\|features/app/" packages/pscreen_screen/lib`
Expected: 无输出

- [ ] **Step 5: 提交**

```bash
git add -A packages/pscreen_screen
git commit -m "refactor(screen): 抽出 CurrentSceneProvider 解除 ReportingService 对宿主的依赖"
```

---

### Task 5: 共享包 DI 入口 `ScreenModules`

**Files:**
- Create: `packages/pscreen_screen/lib/core/di/modules/{core_module,network_module,remote_module,msg_module,iptv_module,weather_module}.dart`
- Create: `packages/pscreen_screen/lib/core/di/screen_modules.dart`

- [ ] **Step 1: 把 `potatokid_screen` 的 6 个 Module 搬进共享包并改写**

从 `pscreen/potatokid_screen/lib/core/di/modules/` 取 `core_module` / `network_module` / `remote_module` / `msg_module` / `iptv_module` / `weather_module`，落到 `packages/pscreen_screen/lib/core/di/modules/`。

逐个改写：

- `import 'package:potatokid_screen/core/di/get_it.dart';` → `import 'package:pscreen_screen/core/di/get_it.dart';`
- 其余 `package:potatokid_screen/...` → `package:pscreen_screen/...`（脚本已处理大部分）

- [ ] **Step 2: 把 `getIt` 全局引用改为参数传入**

共享包不持有 DI 根，但 `getIt` 是 `GetIt.instance` 全局单例，**直接沿用**即可，无需改写 —— 共享包的 `core/di/get_it.dart` 已定义同名全局变量 `getIt`，各 Module 内的 `getIt<...>()` 引用会自动指向共享包那份（同一实例）。

确认：共享包 `lib/core/di/get_it.dart` 内容为 `final GetIt getIt = GetIt.instance;`，与宿主同实例。

- [ ] **Step 3: `MsgModule` 里 `NimMessageSender` 的 `NimManager` 解析**

`msg_module.dart` 中 `getIt<NimManager>()` 依赖 `CoreModule` 先注册 `NimManager` —— 顺序由 `ScreenModules.register` 保证（见 Step 4）。

- [ ] **Step 4: 新增统一入口**

Create `packages/pscreen_screen/lib/core/di/screen_modules.dart`:

```dart
import 'package:get_it/get_it.dart';
import 'package:pscreen_screen/core/di/modules/core_module.dart';
import 'package:pscreen_screen/core/di/modules/iptv_module.dart';
import 'package:pscreen_screen/core/di/modules/msg_module.dart';
import 'package:pscreen_screen/core/di/modules/network_module.dart';
import 'package:pscreen_screen/core/di/modules/remote_module.dart';
import 'package:pscreen_screen/core/di/modules/weather_module.dart';

/// 共享包的依赖注册入口。
///
/// 宿主在自己的 `Injection.init()` 中调用一次即可。注册顺序不可调换：
/// CoreModule（NimManager / AppVersion）→ NetworkModule（LogService / DioManager）
/// → RemoteModule（NIM 登录）→ MsgModule（收发消息）→ IptvModule → WeatherModule。
class ScreenModules {
  const ScreenModules._();

  static Future<void> register(GetIt it) async {
    await CoreModule.register();
    await NetworkModule.register();
    await RemoteModule.register();
    await MsgModule.register();
    await IptvModule.register();
    await WeatherModule.register();
  }

  static Future<void> unregister(GetIt it) async {
    await WeatherModule.unregister();
    await IptvModule.unregister();
    await MsgModule.unregister();
    await RemoteModule.unregister();
    await NetworkModule.unregister();
    await CoreModule.unregister();
  }
}
```

> 各 Module 内部使用共享包的 `getIt`（= `GetIt.instance`），与传入的 `it` 是同一实例，因此 `register(GetIt it)` 的参数当前仅用于表达调用契约；若后续宿主改用非全局实例，需要把 Module 内的 `getIt` 改为参数。

- [ ] **Step 5: 包内分析**

Run: `cd packages/pscreen_screen && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: 提交**

```bash
git add -A packages/pscreen_screen
git commit -m "feat(screen): 共享包新增 ScreenModules 依赖注册入口"
```

---

### Task 6: `potatokid_screen` 接入共享包

**Files:**
- Modify: `pscreen/potatokid_screen/pubspec.yaml`
- Modify: `pscreen/potatokid_screen/lib/core/di/injection.dart`
- Modify: `pscreen/potatokid_screen/lib/core/di/modules/{app_module,home_module,router_module}.dart`（若引用了已迁走的类型）
- Modify: `pscreen/potatokid_screen/lib/features/app/presentation/pages/main_app.dart`（`CurrentSceneProvider` 注入）
- Modify: `pscreen/potatokid_screen/lib/main.dart`
- Modify: `pscreen/potatokid_screen/lib/app/app.dart`（若引用已迁走的类型）
- Delete: `pscreen/potatokid_screen/assets/datas/`（改由共享包提供）

- [ ] **Step 1: pubspec 增加 path 依赖与资产声明**

在 `pscreen/potatokid_screen/pubspec.yaml` 的 `dependencies:` 下追加：

```yaml
  # 屏幕能力共享包（IPTV / 天气 / 时钟 / 消息协议 / 网络基础设施）
  pscreen_screen:
    path: ../../packages/pscreen_screen
```

在 `flutter:` 段的 `assets:` 下把

```yaml
    - assets/datas/
```

替换为

```yaml
    - packages/pscreen_screen/assets/datas/
```

- [ ] **Step 2: 删除宿主自己的 assets/datas**

```bash
git rm -r pscreen/potatokid_screen/assets/datas
```

- [ ] **Step 3: `Injection` 改为调用 `ScreenModules`**

`pscreen/potatokid_screen/lib/core/di/injection.dart` 改为：

```dart
import 'package:potatokid_screen/core/di/get_it.dart';
import 'package:potatokid_screen/core/di/modules/app_module.dart';
import 'package:potatokid_screen/core/di/modules/home_module.dart';
import 'package:potatokid_screen/core/di/modules/router_module.dart';
import 'package:pscreen_screen/core/di/screen_modules.dart';

/// 依赖注入门面：按固定顺序编排各 Module 的注册/注销。
/// 业务代码统一通过 `Injection.get<T>()` 获取实例。
class Injection {
  const Injection._();

  static Future<void> init() async {
    await GetItConfig.init();
    await ScreenModules.register(getIt);
    await RouterModule.register();
    await AppModule.register();
    await HomeModule.register();
  }

  static Future<void> reset() async {
    await HomeModule.unregister();
    await AppModule.unregister();
    await RouterModule.unregister();
    await ScreenModules.unregister(getIt);
    await GetItConfig.reset();
  }

  static T get<T extends Object>() => getIt<T>();
}
```

- [ ] **Step 4: 宿主 `main.dart` 注入 `ScreenAssets` 根路径**

在 `pscreen/potatokid_screen/lib/main.dart` 的 import 区加入：

```dart
import 'package:pscreen_screen/app/config/screen_assets.dart';
```

在 `// 2. 加载 .env 与环境配置` 之前加入：

```dart
      // 1.9 资产根路径：共享包的资产在宿主 bundle 内位于
      //     packages/pscreen_screen/ 前缀下，读取前必须先告知共享包。
      //     紧接一次接入自检：忘记配置就在启动期立刻失败，
      //     而不是等第一次读资产时被 catch 吞成空串。
      ScreenAssets.configure(root: 'packages/pscreen_screen/');
      ScreenAssets.requireHostConfigured();
```

- [ ] **Step 5: 为电视端实现并注册 `CurrentSceneProvider`**

Create `pscreen/potatokid_screen/lib/features/app/application/tv_scene_provider.dart`:

```dart
import 'package:potatokid_screen/features/app/application/app_tab_controller.dart';
import 'package:pscreen_screen/features/msg/application/current_scene_provider.dart';

/// 电视端场景描述：当前 Tab 页名（主页 / 时间页 / 屏保 / 设置）。
class TvSceneProvider extends CurrentSceneProvider {
  const TvSceneProvider();

  @override
  String describe() => AppTabController.pageName;
}
```

在 `pscreen/potatokid_screen/lib/core/di/modules/app_module.dart` 的 `register()` 中，注册 `CurrentSceneProvider`：

```dart
import 'package:pscreen_screen/features/msg/application/current_scene_provider.dart';
```

```dart
  static Future<void> register() async {
    getIt.registerLazySingleton<AppBloc>(() => AppBloc());
    // 电视端有 4-tab 外壳，场景描述 = 当前 Tab 页名。
    // 必须在 ScreenModules.register（内部会用到）之前完成注册。
    getIt.registerLazySingleton<CurrentSceneProvider>(() => const TvSceneProvider());
  }
```

```dart
  static Future<void> unregister() async {
    await getIt.unregister<CurrentSceneProvider>();
    await getIt.unregister<AppBloc>();
  }
```

在 `packages/pscreen_screen/lib/core/di/modules/msg_module.dart` 中，把 `ReportingService(...)` 的构造补上参数（`CurrentSceneProvider` 由宿主注册，共享包通过 DI 取得）：

```dart
      sceneProvider: getIt<CurrentSceneProvider>(),
```

并在 `packages/pscreen_screen/lib/core/di/screen_modules.dart` 的 `register` 中，把 `MsgModule.register()` 之前插入一行，确保宿主有机会先注册 provider：

```dart
  static Future<void> register(GetIt it) async {
    await CoreModule.register();
    await NetworkModule.register();
    await RemoteModule.register();
    await MsgModule.register();
    await IptvModule.register();
    await WeatherModule.register();
  }
```

> 注册顺序契约：`CurrentSceneProvider` 由宿主在调用 `ScreenModules.register` **之前**注册（电视端在 `AppModule.register`，中控屏在 S2 的宿主模块），共享包只在 `MsgModule.register` 内部读取它。
>
> 若宿主忘记注册，`getIt<CurrentSceneProvider>()` 会抛异常导致启动失败——这比静默降级更安全，S2 的中控屏接线必须注册它。

`potatokid_screen` 的 `Injection.init()` 顺序相应调整为：

```dart
  static Future<void> init() async {
    await GetItConfig.init();
    await AppModule.register();
    await ScreenModules.register(getIt);
    await RouterModule.register();
    await HomeModule.register();
  }
```

- [ ] **Step 6: 宿主分析**

Run: `cd pscreen/potatokid_screen && flutter pub get && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 7: 宿主测试**

Run: `cd pscreen/potatokid_screen && flutter test`
Expected: 全部通过。若 `reporting_service_test.dart` 因新增构造参数失败，按下述改测试：

```dart
    ReportingService(
      sender: sender,
      deviceModel: () => 'Test TV',
      channelInfo: channelInfo,
      liveChannel: liveChannel,
      sceneProvider: const StaticSceneProvider('测试场景'),
    );
```

并新增断言：

```dart
    test('非频道场景使用注入的场景描述', () {
      expect(service.positionText(), '测试场景');
    });
```

- [ ] **Step 8: 提交**

```bash
git add -A pscreen/potatokid_screen packages/pscreen_screen
git commit -m "refactor(screen): potatokid_screen 接入 pscreen_screen 共享包"
```

---

### Task 7: 迁移测试到共享包

**Files:**
- Create: `packages/pscreen_screen/test/**`（自 `pscreen/potatokid_screen/test/` 迁入）
- Delete: `pscreen/potatokid_screen/test/` 中对应的测试

- [ ] **Step 1: 确定要迁移的测试**

| 源测试 | 归属 |
| --- | --- |
| `test/core/utils/app_settings_test.dart` | 共享包（`core/utils/app_settings.dart`） |
| `test/core/utils/wordpress_util_test.dart` | 共享包（`core/utils/wordpress_util.dart`） |
| `test/core/platform_channel_service_test.dart` | 共享包（`core/utils/platform_channel_service.dart`） |
| `test/features/msg/message_envelope_test.dart` | 共享包（`features/msg/protocol/`） |
| `test/features/msg/message_overlay_controller_test.dart` | 共享包（`features/msg/application/`） |
| `test/features/msg/message_router_test.dart` | 共享包（`features/msg/application/`） |
| `test/features/msg/reporting_service_test.dart` | 共享包（`features/msg/application/`） |
| `test/features/remote/remote_login_bloc_test.dart` | 共享包（`features/remote/application/`） |
| `test/features/remote/remote_login_repository_impl_test.dart` | 共享包（`features/remote/data/`） |
| `test/channel_name_matcher_test.dart` | 共享包（`features/iptv/domain/`） |
| `test/channel_name_normalizer_test.dart` | 共享包（`features/iptv/domain/`） |

- [ ] **Step 2: 写迁移脚本**

Create `tool/migrate_shared_tests.mjs`:

```javascript
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(process.argv[2] ?? '.');
const SRC_TEST = path.join(ROOT, 'pscreen', 'potatokid_screen', 'test');
const PKG_TEST = path.join(ROOT, 'packages', 'pscreen_screen', 'test');

// 测试文件 -> 包内测试路径
const MAP = {
  'core/utils/app_settings_test.dart': 'core/utils/app_settings_test.dart',
  'core/utils/wordpress_util_test.dart': 'core/utils/wordpress_util_test.dart',
  'core/platform_channel_service_test.dart': 'core/utils/platform_channel_service_test.dart',
  'features/msg/message_envelope_test.dart': 'features/msg/protocol/message_envelope_test.dart',
  'features/msg/message_overlay_controller_test.dart': 'features/msg/application/message_overlay_controller_test.dart',
  'features/msg/message_router_test.dart': 'features/msg/application/message_router_test.dart',
  'features/msg/reporting_service_test.dart': 'features/msg/application/reporting_service_test.dart',
  'features/remote/remote_login_bloc_test.dart': 'features/remote/application/remote_login_bloc_test.dart',
  'features/remote/remote_login_repository_impl_test.dart': 'features/remote/data/remote_login_repository_impl_test.dart',
  'channel_name_matcher_test.dart': 'features/iptv/domain/channel_name_matcher_test.dart',
  'channel_name_normalizer_test.dart': 'features/iptv/domain/channel_name_normalizer_test.dart',
};

function rewrite(text) {
  return text.replaceAll('package:potatokid_screen/', 'package:pscreen_screen/');
}

for (const [from, to] of Object.entries(MAP)) {
  const src = path.join(SRC_TEST, from);
  if (!fs.existsSync(src)) {
    console.log(`跳过（不存在）：${from}`);
    continue;
  }
  const dest = path.join(PKG_TEST, to);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest, rewrite(fs.readFileSync(src, 'utf8')));
  fs.rmSync(src);
  console.log(`迁移：${from} -> ${to}`);
}
```

- [ ] **Step 3: 跑迁移脚本**

Run: `node tool/migrate_shared_tests.mjs "E:/Code/potatokid_clipboard"`
Expected: 11 行 `迁移：...`

- [ ] **Step 4: 修 `reporting_service_test.dart` 的新构造参数**

按 Task 6 Step 5 的说明给 `ReportingService(...)` 补 `sceneProvider:`，并补一条 `positionText()` 断言。

- [ ] **Step 5: 共享包测试全绿**

Run: `cd packages/pscreen_screen && flutter test`
Expected: 全部通过。若 `app_settings_test` / `wordpress_util_test` 依赖宿主 `.env` 而失败，在测试内显式设置需要的静态字段，而不是依赖 `.env`。

- [ ] **Step 6: 宿主测试全绿**

Run: `cd pscreen/potatokid_screen && flutter test`
Expected: 全部通过（剩余 `widget_test.dart` 等）

- [ ] **Step 7: 提交**

```bash
git add -A packages/pscreen_screen pscreen/potatokid_screen tool/migrate_shared_tests.mjs
git commit -m "test(screen): 能力层测试迁移到 pscreen_screen 共享包"
```

---

### Task 8: S1 门槛验收

**Files:**
- Modify: `packages/pscreen_screen/README.md`（新建）

- [ ] **Step 1: 共享包分析零问题**

Run: `cd packages/pscreen_screen && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: 共享包测试全绿**

Run: `cd packages/pscreen_screen && flutter test`
Expected: 全部通过

- [ ] **Step 3: 宿主分析零问题**

Run: `cd pscreen/potatokid_screen && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: 宿主测试全绿**

Run: `cd pscreen/potatokid_screen && flutter test`
Expected: 全部通过

- [ ] **Step 5: 宿主 Windows 构建**

Run: `cd pscreen/potatokid_screen && flutter build windows --debug`
Expected: `Built build\windows\x64\runner\Debug\potatokid_screen.exe`

- [ ] **Step 6: 宿主 Android 构建（验证 NIM 原生插件仍可编译）**

Run: `cd pscreen/potatokid_screen && flutter build apk --debug`
Expected: `Built build\app\outputs\flutter-apk\app-debug.apk`

- [ ] **Step 7: 写共享包 README**

Create `packages/pscreen_screen/README.md`:

```markdown
# pscreen_screen

屏幕能力共享包：IPTV / 天气 / 时钟 / 消息协议 / 网络基础设施。

## 边界

- **包含**：`data` / `domain` / `application` 三层 + `core` 基础设施。
- **不包含**：任何 `presentation`（UI）。UI 由各宿主按自己的交互范式实现
  （电视端用遥控焦点，中控屏用触屏）。
- **不包含**：路由树、DI 根、主题、本地化资源。

## 依赖方向

宿主 App → `pscreen_screen`。共享包不依赖任何宿主。

## 宿主接入清单（漏任何一条都会静默出错）

1. **加 path 依赖**

   ```yaml
   dependencies:
     pscreen_screen:
       path: ../packages/pscreen_screen
   ```

2. **在宿主自己的 pubspec 里声明共享包的资产**
   （Flutter **不会**把依赖包的资产自动打进宿主 bundle）

   ```yaml
   flutter:
     assets:
       - packages/pscreen_screen/assets/datas/
   ```

3. **启动时配置根前缀并做接入自检**

   ```dart
   ScreenAssets.configure(root: 'packages/pscreen_screen/');
   ScreenAssets.requireHostConfigured();   // 未配置就抛异常
   ```

   忘记这一步 → 资产读取 404 且被上层 `catch` 吞掉，表现为「频道规则为空、
   城市列表为空」这类**静默故障**。自检放在启动期，让它立刻失败而不是等到
   第一次读资产。

   注意：共享包自己跑测试时根前缀是空串（资产就在包内 `assets/datas/`），
   这是合法的；`requireHostConfigured()` 只用于宿主。

4. **不要与宿主自己的 `core/di/get_it.dart` 同时 import 包的同名文件**
   —— 两边都有 `getIt` / `GetItConfig`，同时 import 会产生歧义引用错误。
   共享包内部只用包内那份；宿主侧继续用自己的那份。

5. **注册依赖**

   ```dart
   await ScreenModules.register(getIt);
   ```
```

- [ ] **Step 8: 提交**

```bash
git add -A packages/pscreen_screen
git commit -m "docs(screen): 补充共享包 README 与边界说明"
```

---

## S1 完成定义

- [ ] G1 `packages/pscreen_screen` analyze 零问题
- [ ] G2 `packages/pscreen_screen` test 全绿
- [ ] G3 `potatokid_screen` analyze 零问题
- [ ] G4 `potatokid_screen` test 全绿
- [ ] G5 `potatokid_screen` windows + apk 构建成功

**下一步**：执行 `docs/superpowers/plans/2026-10-21-s2-host-wiring.md`（宿主接线）。
