# S2 宿主接线（pscreen_home 接入 pscreen_screen）实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 `pscreen_home` 依赖 `pscreen_screen` 共享包，完成配置合并、命名消歧、DI 与启动接线、Android 原生接线，**现有中控台功能完全不变**。

**Architecture:** `pscreen_home` 保留全部 HA 专属代码；屏幕能力全部来自共享包。宿主不持有共享包内部的任何类型定义，只**引用**。为避免同名类型歧义，宿主侧的 HA 专属类型统一加 `Ha` 前缀。

**Tech Stack:** Flutter 3.41.9 / Dart 3.11.5、get_it 9.3、media_kit 1.2、nim_core_v2 10.9

**设计依据：** `docs/superpowers/specs/2026-10-21-screen-capability-shared-package-design.md` §四、§五

**前置条件：** S1 已完成且 G1–G5 全绿（见 `2026-10-21-s1-shared-package-extraction.md`）

---

## 本阶段要解决的 5 个具体障碍

| # | 障碍 | 处理 |
| --- | --- | --- |
| 1 | 共享包与宿主都有 `AppConfig` | 宿主改名 `HaConfig` |
| 2 | 共享包（Dio 语义）与宿主（HA 语义）都有 `NetErrorType` / `NetExceptionX` / `mapErrorToMessage` | 宿主改名 `HaErrorType` / `HaExceptionX` / `mapHaErrorToMessage` |
| 3 | `LogService` 会双重注册（get_it 重复注册直接抛异常） | 宿主删除本地 `LogService`，由共享包的 `NetworkModule` 注册；宿主 `NetworkModule` 只留 `HaWsClient` |
| 4 | `bloc_event.dart` 两边逐字相同 | 宿主删除本地副本，改引用共享包 |
| 5 | 共享包资产在宿主 bundle 内前缀为 `packages/pscreen_screen/` | 启动时 `ScreenAssets.configure(root: 'packages/pscreen_screen/')` + `ScreenAssets.requireHostConfigured()` 自检 |

## 阶段验收门槛

| # | 门槛 |
| --- | --- |
| G6 | `pscreen_home` `flutter analyze` 零错误零警告 |
| G7 | `pscreen_home` `flutter test` 全绿（含现有 30 个测试文件） |
| G8 | `pscreen_home` `flutter build windows --debug` 成功 |
| G9 | `pscreen_home` `flutter build apk --debug` 成功（验证 media_kit / nim 原生链接入） |

---

### Task 1: pubspec 接线

**Files:**
- Modify: `pscreen_home/pubspec.yaml`

- [ ] **Step 1: 加共享包 path 依赖**

在 `dependencies:` 块中追加：

```yaml
  # 屏幕能力共享包（IPTV / 天气 / 时钟 / 消息协议 / 网络基础设施）
  pscreen_screen:
    path: ../packages/pscreen_screen
```

> 路径相对 `pscreen_home/pubspec.yaml`：`pscreen_home` 的父目录是仓库根，共享包在根的 `packages/` 下，故为 `../packages/pscreen_screen`。

- [ ] **Step 2: 加并入 pscreen_control 所需的直接依赖**

在 `dependencies:` 块中追加：

```yaml
  # 遥控端（并入自 pscreen_control）：NIM 收发、扫码、目录
  nim_core_v2: ^10.9.91
  mobile_scanner: ^6.0.0
  equatable: ^2.0.7
  path_provider: ^2.1.6
```

- [ ] **Step 2.1: 对齐 SDK 下限**

共享包 `pscreen_screen` 要求 `environment.sdk: ^3.11.5`，宿主必须同步抬高，
否则 `flutter pub get` 会因 SDK 约束冲突而失败。

把 `pscreen_home/pubspec.yaml` 的

```yaml
environment:
  sdk: ^3.11.0
```

改为

```yaml
environment:
  sdk: ^3.11.5
```

- [ ] **Step 3: 确认没有为共享包资产添加任何声明**

把 `flutter:` 段的 `assets:` 保持为宿主自己的资产即可：

```yaml
  assets:
    - .env
    - assets/icon/
```

> **不要**为共享包的 `assets/datas/` 加任何条目。共享包自己的 `pubspec.yaml` 已声明
> `assets: - assets/datas/`，作为依赖被引入时 flutter_tools 会展开该目录并给资产键
> 加上 `packages/pscreen_screen/` 前缀，宿主**不需要**再声明。
>
> 宿主若写 `- packages/pscreen_screen/assets/datas/`，pubspec 的目录通配会相对
> **声明方自己的目录**解析，被解析成
> `<宿主目录>/packages/pscreen_screen/assets/datas/`，构建时报
> `Error: unable to find directory entry in pubspec.yaml`。

> `assets/icon/` 为 pscreen_home 原有目录，实施前先确认实际目录名：
>
> ```bash
> ls pscreen_home/assets
> ```
>
> Expected: `icon`（若为其它名字，按实际填）。

- [ ] **Step 4: 拉依赖**

Run: `cd pscreen_home && flutter pub get`
Expected: `Got dependencies!` 或 `Resolving dependencies...` 成功。若 `mobile_scanner` 与 Flutter 3.41 的 Dart 3.11 有版本冲突，退到 `mobile_scanner: ^5.1.1` 并在提交说明里记录。

- [ ] **Step 5: 提交**

```bash
git add pscreen_home/pubspec.yaml pscreen_home/pubspec.lock
git commit -m "build(home): pscreen_home 接入 pscreen_screen 共享包与遥控依赖"
```

---

### Task 2: `.env` 合并

**Files:**
- Modify: `pscreen_home/.env`

- [ ] **Step 1: 读取电视端的 .env 作为模板**

Run: `cat pscreen/potatokid_screen/.env`
Expected: 输出含 `BASE_URL` / `IS_DEBUG` / `ENABLE_PROXY` / `ENABLE_DEV_TOOLS` / `SENIVERSE_*` / `WEATHER_CITIES` / `NIM_PASSWORD` 的键值对。

- [ ] **Step 2: 把屏幕侧键合并进 `pscreen_home/.env`**

在 `pscreen_home/.env` 现有 `AS_HOST` / `AS_KEY` 之后，追加电视端 `.env` 的全部键值对（**原样复制值**，不要改写）。

合并后的 `.env` 键集合必须包含：

```
AS_HOST  AS_KEY
BASE_URL  IS_DEBUG  ENABLE_PROXY  ENABLE_DEV_TOOLS
SENIVERSE_V3_KEY  SENIVERSE_WEATHER_HOST_V3  SENIVERSE_DEFAULT_LOCATION
SENIVERSE_PUBLIC_KEY  SENIVERSE_SECRET_KEY  SENIVERSE_WEATHER_HOST
SENIVERSE_IP_GEO_HOST  SENIVERSE_IP_GEO_HOST_B  WEATHER_CITIES  NIM_PASSWORD
```

- [ ] **Step 3: 校验 .env 仍在 pubspec 资产里**

Run: `grep -n "\- \.env" pscreen_home/pubspec.yaml`
Expected: 有 `- .env` 一行

- [ ] **Step 4: 提交**

```bash
git add pscreen_home/.env
git commit -m "chore(home): 合并屏幕侧环境变量到 .env"
```

> `.env` 含密钥，**确认仓库的 `.gitignore` 未忽略该文件且历史上已跟踪**：
>
> ```bash
> git ls-files pscreen_home/.env
> ```
>
> Expected: 输出该路径（已被跟踪）。若为空，说明密钥从未入库，改为写入 `pscreen_home/.env.local` 并在 `pubspec.yaml` 里改为 `- .env.local`，同时更新 `.gitignore`。

---

### Task 3: 宿主侧命名消歧

**Files:**
- Create: `pscreen_home/lib/app/config/ha_config.dart`（由 `app_config.dart` 重命名而来）
- Create: `pscreen_home/lib/core/network/ha_net_exceptions.dart`（由 `net_exceptions.dart` 重命名而来）
- Create: `pscreen_home/lib/core/utils/ha_error_message.dart`（由 `error_message.dart` 重命名而来）
- Delete: `pscreen_home/lib/app/config/app_config.dart`
- Delete: `pscreen_home/lib/core/network/net_exceptions.dart`
- Delete: `pscreen_home/lib/core/utils/error_message.dart`
- Modify: 引用上述文件的 8 个源文件 + 2 个测试文件

- [ ] **Step 1: 写消歧脚本**

Create `tool/rename_home_ha_symbols.mjs`:

```javascript
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
```

- [ ] **Step 2: 跑消歧脚本**

Run: `node tool/rename_home_ha_symbols.mjs "E:/Code/potatokid_clipboard"`
Expected: 列出改写的文件（应含 `lib/main.dart`、`lib/app/app.dart`、`lib/features/home/application/bloc/home_bloc.dart`、`lib/features/home/application/bloc/home_state.dart`、`lib/features/home/data/repositories/home_repository_impl.dart`、`lib/core/network/ha_ws_client.dart`、`test/app_config_test.dart`、`test/home_bloc_test.dart`）与 3 条重命名记录。

- [ ] **Step 3: 修正 `ha_config.dart` 的文档注释**

`pscreen_home/lib/app/config/ha_config.dart` 顶部注释里的 `AppConfig` 引用已被脚本改成 `HaConfig`，确认措辞通顺：

```dart
/// 环境配置，值来源于根目录 .env（通过 pubspec assets 声明）。
/// 在 main() 中调用 HaConfig.initialize() 后使用。
```

- [ ] **Step 4: 检查是否还有残留的旧名**

Run: `grep -rn "\bAppConfig\b\|\bNetErrorType\b\|\bNetExceptionX\b\|\bmapErrorToMessage\b" pscreen_home/lib pscreen_home/test`
Expected: 无输出（`HaConfig` / `HaErrorType` 等新名不含旧名的完整词匹配）

- [ ] **Step 5: 分析**

Run: `cd pscreen_home && flutter analyze`
Expected: 无 error；可能有 warning（下一任务会清掉）

- [ ] **Step 6: 提交**

```bash
git add -A pscreen_home tool/rename_home_ha_symbols.mjs
git commit -m "refactor(home): HA 专属类型统一加 Ha 前缀以消除与共享包的同名冲突"
```

---

### Task 4: 删除重复的 `LogService` 与 `bloc_event`，改用共享包

**Files:**
- Delete: `pscreen_home/lib/core/logging/log_service.dart`
- Delete: `pscreen_home/lib/core/utils/bloc_event.dart`
- Modify: 13 个 import 了 `log_service.dart` 的文件
- Modify: `pscreen_home/lib/features/home/application/bloc/home_bloc.dart`（import `bloc_event.dart`）
- Modify: `pscreen_home/lib/core/di/modules/network_module.dart`（不再注册 `LogService`）

- [ ] **Step 1: 改写 import**

Run:

```bash
node -e "const fs=require('fs'),path=require('path');const H='pscreen_home';const files=[];(function w(d){for(const e of fs.readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name);e.isDirectory()?w(p):(e.name.endsWith('.dart')&&files.push(p));}})(H+'/lib');(function w(d){for(const e of fs.readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name);e.isDirectory()?w(p):(e.name.endsWith('.dart')&&files.push(p));}})(H+'/test');let n=0;for(const f of files){const t=fs.readFileSync(f,'utf8');const x=t.replaceAll('package:pscreen_home/core/logging/log_service.dart','package:pscreen_screen/core/logging/log_service.dart').replaceAll('package:pscreen_home/core/utils/bloc_event.dart','package:pscreen_screen/core/utils/bloc_event.dart');if(x!==t){fs.writeFileSync(f,x);n++;console.log('  '+f);}}console.log('改写 '+n+' 个文件');"
```

Expected: 列出 14 个文件（含 `home_bloc.dart` 的两处 import 各占一个文件计数）

- [ ] **Step 2: 删除本地副本**

```bash
git rm pscreen_home/lib/core/logging/log_service.dart pscreen_home/lib/core/utils/bloc_event.dart
```

- [ ] **Step 3: `network_module.dart` 不再注册 `LogService`**

`pscreen_home/lib/core/di/modules/network_module.dart` 改为：

```dart
import 'package:pscreen_home/core/di/get_it.dart';
import 'package:pscreen_home/core/network/ha_ws_client.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';

/// 网络模块：注册 Home Assistant WebSocket 客户端（应用唯一网络入口）。
///
/// `LogService` 由共享包的 `ScreenModules.register` 注册（同一个
/// `GetIt.instance`），此处**不可重复注册**——get_it 对重复注册会直接抛异常。
class NetworkModule {
  const NetworkModule._();

  static Future<void> register() async {
    getIt.registerLazySingleton<HaWsClient>(
      () => HaWsClient(log: getIt<LogService>()),
    );
  }

  static Future<void> unregister() async {
    await getIt.unregister<HaWsClient>();
  }
}
```

- [ ] **Step 4: 检查 `core/logging/` 与 `core/utils/` 目录是否空了**

```bash
ls pscreen_home/lib/core/logging pscreen_home/lib/core/utils
```

Expected: `core/logging/` 为空目录（用 `git rm` 已随文件删除，Git 不跟踪空目录，磁盘上可能残留空文件夹，可手动删）；`core/utils/` 仅剩 `ha_error_message.dart`。

- [ ] **Step 5: 分析**

Run: `cd pscreen_home && flutter analyze`
Expected: `No issues found!`（`LogService` 已从共享包解析，import 已改）

- [ ] **Step 6: 提交**

```bash
git add -A pscreen_home
git commit -m "refactor(home): 复用共享包的 LogService 与 bloc_event，删除重复实现"
```

---

### Task 5: DI 接线

**Files:**
- Create: `pscreen_home/lib/core/di/modules/screen_module.dart`
- Create: `pscreen_home/lib/core/di/scene/home_scene_provider.dart`
- Modify: `pscreen_home/lib/core/di/injection.dart`
- Modify: `pscreen_home/lib/core/di/modules/router_module.dart`（无需改动，仅确认）

- [ ] **Step 1: 写宿主侧场景描述器**

Create `pscreen_home/lib/core/di/scene/home_scene_provider.dart`:

```dart
import 'package:pscreen_screen/features/msg/application/current_scene_provider.dart';

/// 中控屏场景描述。
///
/// 中控屏没有 Tab 外壳，场景恒为「中控台」；后续若引入可切换的媒体页，
/// 在此按当前路由给出更细的描述即可。
class HomeSceneProvider extends CurrentSceneProvider {
  const HomeSceneProvider();

  @override
  String describe() => '中控台';
}
```

- [ ] **Step 2: 写宿主侧屏幕模块**

Create `pscreen_home/lib/core/di/modules/screen_module.dart`:

```dart
import 'package:pscreen_home/core/di/get_it.dart';
import 'package:pscreen_home/core/di/scene/home_scene_provider.dart';
import 'package:pscreen_screen/features/msg/application/current_scene_provider.dart';

/// 屏幕模块：注册宿主侧的场景描述器。
///
/// 必须在共享包的 `ScreenModules.register` **之前**调用——共享包的
/// `MsgModule` 会立刻读取 `CurrentSceneProvider`。
class ScreenModule {
  const ScreenModule._();

  static Future<void> register() async {
    getIt.registerLazySingleton<CurrentSceneProvider>(
      () => const HomeSceneProvider(),
    );
  }

  static Future<void> unregister() async {
    await getIt.unregister<CurrentSceneProvider>();
  }
}
```

- [ ] **Step 3: 改 `Injection.init()` 顺序**

`pscreen_home/lib/core/di/injection.dart` 改为：

```dart
import 'package:pscreen_home/core/di/get_it.dart';
import 'package:pscreen_home/core/di/modules/connection_module.dart';
import 'package:pscreen_home/core/di/modules/home_module.dart';
import 'package:pscreen_home/core/di/modules/network_module.dart';
import 'package:pscreen_home/core/di/modules/router_module.dart';
import 'package:pscreen_home/core/di/modules/screen_module.dart';
import 'package:pscreen_home/core/di/modules/storage_module.dart';
import 'package:pscreen_screen/core/di/screen_modules.dart';

/// 依赖注入门面：按固定顺序编排各 Module 的注册/注销。
/// 业务代码统一通过 `Injection.get<T>()` 获取实例。
class Injection {
  const Injection._();

  static Future<void> init() async {
    await GetItConfig.init();
    // 1. 宿主场景描述器（共享包 MsgModule 会立即读取，必须最先）
    await ScreenModule.register();
    // 2. 共享包能力层（内含 LogService / DioManager / NimManager /
    //    IptvBloc / WeatherBloc / RemoteLoginBloc 等）
    await ScreenModules.register(getIt);
    // 3. 宿主模块（NetworkModule 依赖共享包注册的 LogService）
    await StorageModule.register();
    await NetworkModule.register();
    await RouterModule.register();
    await ConnectionModule.register();
    await HomeModule.register();
  }

  static Future<void> reset() async {
    await HomeModule.unregister();
    await ConnectionModule.unregister();
    await RouterModule.unregister();
    await NetworkModule.unregister();
    await StorageModule.unregister();
    await ScreenModules.unregister(getIt);
    await ScreenModule.unregister();
    await GetItConfig.reset();
  }

  static T get<T extends Object>() => getIt<T>();
}
```

> **顺序契约**：`ScreenModule`（场景描述器）→ `ScreenModules`（共享包，内部读场景描述器）→ 宿主其余模块（依赖共享包注册的 `LogService`）。
>
> `StorageModule` 依赖 `LogService`，故必须排在 `ScreenModules.register` 之后。

- [ ] **Step 4: 分析**

Run: `cd pscreen_home && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 5: 提交**

```bash
git add -A pscreen_home
git commit -m "feat(home): 接入共享包依赖注入并注册宿主场景描述器"
```

---

### Task 6: 启动接线

**Files:**
- Modify: `pscreen_home/lib/main.dart`

- [ ] **Step 1: 改写 `main.dart`**

`pscreen_home/lib/main.dart` 改为：

```dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:media_kit/media_kit.dart';
import 'package:pscreen_home/app/app.dart';
import 'package:pscreen_home/app/config/ha_config.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_home/core/router/app_router.dart';
import 'package:pscreen_home/core/storage/settings_store.dart';
import 'package:pscreen_home/features/connection/application/bloc/connection_bloc.dart';
import 'package:pscreen_home/features/connection/application/bloc/connection_event.dart';
import 'package:pscreen_home/features/home/application/bloc/home_bloc.dart';
import 'package:pscreen_screen/app/config/app_config.dart';
import 'package:pscreen_screen/app/config/data_files.dart';
import 'package:pscreen_screen/app/config/screen_assets.dart';

void main() {
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // 0. 媒体播放库（共享包的 IPTV 能力依赖 media_kit）
      MediaKit.ensureInitialized();

      // 0.1 资产根路径：共享包的资产在宿主 bundle 内位于
      //     packages/pscreen_screen/ 前缀下，读取前必须先告知共享包。
      //     紧接一次接入自检：忘记配置就在启动期立刻失败，
      //     而不是等第一次读资产时被 catch 吞成空串。
      ScreenAssets.configure(root: 'packages/pscreen_screen/');
      ScreenAssets.requireHostConfigured();

      // 1. 加载 .env：HA 连接配置（AS_HOST / AS_KEY）与屏幕侧配置共用同一份
      //    .env。flutter_dotenv 的 load() 会覆盖式重载，重复调用安全。
      await HaConfig.initialize();
      await AppConfig.initialize();

      // 1.1 数据文件（频道顺序 / 隐藏列表 / 天气城市）：先用本地值
      //     （持久化缓存 → 包内 assets 默认）保证后续任意时刻都有可用值。
      await DataFiles.instance.loadLocal();

      // 2. 依赖注入（含共享包能力层、本地持久化、路由、业务模块）
      await Injection.init();

      // 3. 应用上次手动设置的连接配置（持久化优先，空则回落 .env）
      HaConfig.applyOverrides(
        host: Injection.get<SettingsStore>().hostOverride,
        token: Injection.get<SettingsStore>().tokenOverride,
      );

      // 4. 初始化路由（异步，决定 initialLocation），必须在 runApp 前
      await Injection.get<AppRouter>().initialize();

      // 5. 启动：连接状态机随应用启动发起连接，
      //    连接就绪后由页面触发 HomeBloc 加载实体
      runApp(
        MultiBlocProvider(
          providers: <BlocProvider<dynamic>>[
            BlocProvider<ConnectionBloc>(create: (_) => Injection.get<ConnectionBloc>()..add(const StartConnection())),
            BlocProvider<HomeBloc>(create: (_) => Injection.get<HomeBloc>()),
          ],
          child: const App(),
        ),
      );
    },
    (Object error, StackTrace stack) {
      FlutterError.presentError(FlutterErrorDetails(exception: error, stack: stack));
    },
  );
}
```

> 本阶段**不**加 `DataFiles.instance.ensureSynced()`（网络同步）与 NIM 初始化 —— 二者属于 S3（遥控并入），避免 S2 阶段引入未验证的异步链路。

- [ ] **Step 2: 分析**

Run: `cd pscreen_home && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 测试**

Run: `cd pscreen_home && flutter test`
Expected: 全部通过。若 `app_config_test.dart` 因改名失败，改用 `HaConfig`：

```bash
node -e "const fs=require('fs');const p='pscreen_home/test/app_config_test.dart';let t=fs.readFileSync(p,'utf8');t=t.replaceAll('package:pscreen_home/app/config/app_config.dart','package:pscreen_home/app/config/ha_config.dart').replace(/\bAppConfig\b/g,'HaConfig');fs.writeFileSync(p,t);console.log('已更新');"
```

- [ ] **Step 4: 提交**

```bash
git add -A pscreen_home
git commit -m "feat(home): 启动流程接入共享包配置、资产与媒体库"
```

---

### Task 7: Android 原生接线

**Files:**
- Modify: `pscreen_home/android/app/src/main/kotlin/potatokid/tools/homecontroller/MainActivity.kt`
- Modify: `pscreen_home/android/app/src/main/AndroidManifest.xml`
- Modify: `pscreen_home/android/app/build.gradle.kts`
- Modify: `pscreen_home/android/build.gradle.kts`

- [ ] **Step 1: `MainActivity` 增加音量 MethodChannel**

`pscreen_home/android/app/src/main/kotlin/potatokid/tools/homecontroller/MainActivity.kt` 改为：

```kotlin
package potatokid.tools.homecontroller

import android.media.AudioManager
import android.os.Build
import android.os.Bundle
import android.view.View
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * 中控屏宿主 Activity。
 *
 * 除了承载 Flutter 界面，还负责把系统状态栏 / 底部导航栏彻底隐藏：
 * 15 寸壁挂面板上系统栏会压住底部卡片，而且开机或弹窗后系统会把导航栏
 * 重新显示出来，所以除了 onCreate，还要在 onResume 和每次重新获得焦点时
 * 重新进入沉浸式（IMMERSIVE_STICKY：从边缘上滑可临时唤出，随后自动隐藏）。
 *
 * 同时实现共享包 `PlatformChannelService` 使用的
 * `potatokid/volume` 通道：遥控端下发的 volume_up / volume_down / mute
 * 命令经由该通道落到系统音量。
 */
class MainActivity : FlutterActivity() {

    private val CHANNEL = "potatokid/volume"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                val audio = getSystemService(AUDIO_SERVICE) as AudioManager
                when (call.method) {
                    "volumeUp" -> {
                        audio.adjustStreamVolume(
                            AudioManager.STREAM_MUSIC,
                            AudioManager.ADJUST_RAISE,
                            AudioManager.FLAG_SHOW_UI
                        )
                        result.success(null)
                    }
                    "volumeDown" -> {
                        audio.adjustStreamVolume(
                            AudioManager.STREAM_MUSIC,
                            AudioManager.ADJUST_LOWER,
                            AudioManager.FLAG_SHOW_UI
                        )
                        result.success(null)
                    }
                    "toggleMute" -> {
                        val muted = audio.isStreamMute(AudioManager.STREAM_MUSIC)
                        audio.setStreamMute(AudioManager.STREAM_MUSIC, !muted)
                        result.success(null)
                    }
                    "getDeviceModel" -> {
                        result.success(Build.MODEL ?: "Android TV")
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyImmersiveMode()
    }

    override fun onResume() {
        super.onResume()
        applyImmersiveMode()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        // 系统弹窗、通知栏、软键盘收起后系统会恢复系统栏，这里再次强制全屏。
        if (hasFocus) applyImmersiveMode()
    }

    @Suppress("DEPRECATION")
    private fun applyImmersiveMode() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
            window.decorView.systemUiVisibility =
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE or
                View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or
                View.SYSTEM_UI_FLAG_FULLSCREEN or
                View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
        }
    }
}
```

- [ ] **Step 2: `AndroidManifest.xml` 增加相机权限**

在 `pscreen_home/android/app/src/main/AndroidManifest.xml` 的 `<manifest>` 标签内、`<application>` 之前加入：

```xml
    <!-- 遥控端：扫码绑定目标电视 -->
    <uses-permission android:name="android.permission.CAMERA"/>
    <!-- 扫码需要前置摄像头 -->
    <uses-feature android:name="android.hardware.camera" android:required="false"/>
```

- [ ] **Step 3: `build.gradle.kts` 增加 jniLibs pickFirsts**

media_kit 与 nim 都携带 `libc++_shared.so`，不处理会在打包时报重复库错误。在 `pscreen_home/android/app/build.gradle.kts` 的 `android { }` 块内、`buildTypes` 之后加入：

```kotlin
    // SDK 集成要求：多个依赖都带 libc++_shared.so，打包时保留首个，避免重复冲突。
    packaging {
        jniLibs {
            pickFirsts += listOf(
                "lib/x86/libc++_shared.so",
                "lib/x86_64/libc++_shared.so",
                "lib/armeabi-v7a/libc++_shared.so",
                "lib/arm64-v8a/libc++_shared.so",
            )
        }
    }
```

- [ ] **Step 4: `android/build.gradle.kts` 增加国内镜像**

`media_kit_libs_video` 与 `nim_core_v2` 需要从 Maven 拉原生产物。把 `pscreen_home/android/build.gradle.kts` 的 `repositories` 块改为与电视端一致（国内镜像优先、失败回退官方源）：

```kotlin
allprojects {
    repositories {
        // 国内镜像优先，失败时自动回退到官方源
        maven("https://maven.aliyun.com/repository/google")
        maven("https://maven.aliyun.com/repository/public")
        google()
        mavenCentral()
    }
}
```

其余内容（`newBuildDir` / `subprojects` / `clean` 任务）保持不变。

- [ ] **Step 5: 提交**

```bash
git add -A pscreen_home/android
git commit -m "feat(home): Android 接入音量通道、相机权限与 media_kit/nim 原生依赖配置"
```

---

### Task 8: S2 门槛验收

**Files:**
- 无（纯验证）

- [ ] **Step 1: 分析零问题**

Run: `cd pscreen_home && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: 测试全绿**

Run: `cd pscreen_home && flutter test`
Expected: 全部通过（30 个测试文件一个不少）

- [ ] **Step 3: Windows 构建**

Run: `cd pscreen_home && flutter build windows --debug`
Expected: `Built build\windows\x64\runner\Debug\pscreen_home.exe`

- [ ] **Step 4: Android 构建**

Run: `cd pscreen_home && flutter build apk --debug`
Expected: `Built build\app\outputs\flutter-apk\app-debug.apk`

> 若报 `Duplicate class libc++_shared.so` → Task 7 Step 3 未生效，检查 `packaging` 块位置。
> 若报 media_kit 原生库下载失败 → 检查 `android/build.gradle.kts` 的镜像配置（Task 7 Step 4）。

- [ ] **Step 5: 资产打包核对**

Run: `Get-ChildItem pscreen_home/build/flutter_assets/packages/pscreen_screen/assets/datas`
Expected: 列出 `tv_name_order.txt` 等 10 个数据文件。**为空则说明共享包的 path 依赖没生效**——回到 Task 1 确认 `pscreen_screen` 依赖已写进 `pubspec.yaml` 且 `flutter pub get` 成功。**不要**因此在宿主 pubspec 里补 `- packages/pscreen_screen/assets/datas/`（那样会让构建直接报 `unable to find directory entry in pubspec.yaml`）。

- [ ] **Step 6: 现有中控台回归（人工）**

启动 `pscreen_home`（`flutter run -d windows`），确认：

1. 中控台正常显示设备网格（HA 连接成功）
2. 设备卡片可点击控制（灯 / 空调 / 插座等）
3. 设置页可改 HA 地址 / 令牌 / 界面缩放并持久化
4. App 无异常日志（`flutter run` 控制台无未捕获异常）

- [ ] **Step 7: 提交（仅当本任务改了文件）**

```bash
git status --short
```

若为空则无需提交。

---

## S2 完成定义

- [ ] G6 `pscreen_home` analyze 零问题
- [ ] G7 `pscreen_home` test 全绿
- [ ] G8 `pscreen_home` windows 构建成功
- [ ] G9 `pscreen_home` apk 构建成功
- [ ] 共享包资产在宿主 bundle 内可读
- [ ] 现有中控台功能人工回归通过

**下一步**：执行 `docs/superpowers/plans/2026-10-21-s3-remote-control-merge.md`（遥控并入）。
