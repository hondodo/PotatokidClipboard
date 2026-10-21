# S3 遥控端并入 pscreen_home 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把废弃的 `pscreen_control`（NIM 遥控端）能力并入 `pscreen_home`，形成「中控屏 + 遥控器」一体；消息入口 = 遥控面板 + 会话列表两 tab。

**Architecture:** `pscreen_control` 的代码迁到 `pscreen_home/lib/features/remote_control/`，协议构造器 (`envelope_builder`) 迁到共享包 `packages/pscreen_screen/lib/features/msg/protocol/`，与解析器同源。NIM SDK **只初始化一次**（由共享包的 `NimManager` 负责），遥控端 `NimClient` 退化为「登录 + 收发」封装。

**Tech Stack:** Flutter 3.41.9 / Dart 3.11.5、nim_core_v2 10.9、flutter_bloc 9.1、mobile_scanner 6.0

**设计依据：** `docs/superpowers/specs/2026-10-21-screen-capability-shared-package-design.md` §三、§八

**前置条件：** S2 已完成且 G6–G9 全绿（见 `2026-10-21-s2-host-wiring.md`）

---

## 本阶段要解决的 3 个具体障碍

| # | 障碍 | 处理 |
| --- | --- | --- |
| 1 | `nim_core_v2` 的 `NimCore.instance` 是**全局单例**，`initialize()` 不可重复调用；共享包的 `NimManager` 与遥控端的 `NimClient` 都会初始化它 | `NimManager.init()` 改为幂等；`NimClient` **删除**自己的 `initialize` 调用，只保留登录与收发 |
| 2 | `pscreen_control` 的 `Injection` 与 `pscreen_home` 的 `Injection` 同名冲突 | 废弃 `pscreen_control` 的 `Injection`，注册项并入宿主 `remote_control_module.dart` |
| 3 | `pscreen_control` 的 `AppConfig` / `AppSettings` / `AppLog` 与宿主及共享包同名 | 分别改名 `ControlConfig` / `ControlSettings` / `ControlLog` |

## 阶段验收门槛

| # | 门槛 |
| --- | --- |
| G10 | `pscreen_home` `flutter analyze` 零错误零警告 |
| G11 | `pscreen_home` `flutter test` 全绿（含迁入的 4 个遥控测试） |
| G12 | `packages/pscreen_screen` `flutter analyze` + `flutter test` 全绿 |
| G13 | `pscreen_home` `flutter build windows --debug` 与 `flutter build apk --debug` 成功 |
| G14 | 端到端：遥控页可发指令，电视端收到并执行（人工验证） |

---

### Task 1: 协议构造器迁入共享包

**Files:**
- Create: `packages/pscreen_screen/lib/features/msg/protocol/envelope_builder.dart`
- Create: `packages/pscreen_screen/test/features/msg/protocol/envelope_builder_test.dart`
- Delete: `pscreen_control/lib/features/protocol/envelope_builder.dart`
- Delete: `pscreen_control/test/protocol/envelope_builder_test.dart`

- [ ] **Step 1: 迁移文件**

```bash
mkdir -p packages/pscreen_screen/lib/features/msg/protocol packages/pscreen_screen/test/features/msg/protocol
git mv pscreen_control/lib/features/protocol/envelope_builder.dart packages/pscreen_screen/lib/features/msg/protocol/envelope_builder.dart
git mv pscreen_control/test/protocol/envelope_builder_test.dart packages/pscreen_screen/test/features/msg/protocol/envelope_builder_test.dart
```

- [ ] **Step 2: 改写测试里的 import**

`packages/pscreen_screen/test/features/msg/protocol/envelope_builder_test.dart` 中：

```dart
import 'package:pscreen_control/features/protocol/envelope_builder.dart';
```

改为：

```dart
import 'package:pscreen_screen/features/msg/protocol/envelope_builder.dart';
```

- [ ] **Step 3: 补一个「构造与解析闭环」测试**

在 `packages/pscreen_screen/test/features/msg/protocol/envelope_builder_test.dart` 末尾追加：

```dart
import 'package:pscreen_screen/features/msg/protocol/message_envelope.dart';

void main() {
  // ... 既有测试 ...

  group('构造与解析闭环', () {
    test('命令信封能被屏幕端解析器识别为 command', () {
      final String body = buildCommandEnvelope(
        'channel',
        <String, dynamic>{'name': 'CCTV-1'},
      );
      final ParsedMessage parsed = parseIncomingText(body);
      expect(parsed.kind, EnvelopeKind.command);
      expect(parsed.commandName, 'channel');
      expect(parsed.args?['name'], 'CCTV-1');
    });

    test('文本命令信封解析出 content', () {
      final ParsedMessage parsed = parseIncomingText(buildTextCommand('你好'));
      expect(parsed.kind, EnvelopeKind.command);
      expect(parsed.commandName, 'text');
      expect(parsed.args?['content'], '你好');
    });

    test('纯文本原样发送时被解析为 plainText', () {
      final ParsedMessage parsed = parseIncomingText(buildPlainText('喝水'));
      expect(parsed.kind, EnvelopeKind.plainText);
      expect(parsed.plainText, '喝水');
    });
  });
}
```

> 若文件已有 `main()`，把上面的 `group` 合并进既有的 `main()` 内，不要出现两个 `main()`。

- [ ] **Step 4: 运行测试**

Run: `cd packages/pscreen_screen && flutter test test/features/msg/protocol/`
Expected: 全部通过

- [ ] **Step 5: 提交**

```bash
git add -A packages/pscreen_screen pscreen_control
git commit -m "refactor(screen): 协议构造器 envelope_builder 迁入共享包与解析器同源"
```

---

### Task 2: pscreen_control 代码迁入 pscreen_home

**Files:**
- Create: `pscreen_home/lib/features/remote_control/**`（16 个文件）
- Delete: `pscreen_control/lib/**`（除 `main.dart` 外全部）
- Create: `tool/migrate_control_into_home.mjs`

- [ ] **Step 1: 写迁移脚本**

Create `tool/migrate_control_into_home.mjs`:

```javascript
import fs from 'node:fs';
import path from 'node:path';

const ROOT = path.resolve(process.argv[2] ?? '.');
const SRC = path.join(ROOT, 'pscreen_control', 'lib');
const DST = path.join(ROOT, 'pscreen_home', 'lib', 'features', 'remote_control');

// 源相对路径 -> 目标相对路径（相对 features/remote_control/）
const MOVES = {
  'app/config/app_config.dart': 'core/control_config.dart',
  'app/storage/app_settings.dart': 'data/control_settings.dart',
  'app/utils/app_log.dart': 'core/control_log.dart',
  'core/nim_client.dart': 'data/nim_client.dart',
  'core/chat_message_item.dart': 'domain/chat_message_item.dart',
  'features/send/application/send_cubit.dart': 'application/send_cubit.dart',
  'features/send/application/send_state.dart': 'application/send_state.dart',
  'features/send/data/tv_directory.dart': 'data/tv_directory.dart',
  'features/send/presentation/send_page.dart': 'presentation/send_page.dart',
  'features/send/presentation/widgets/command_panel.dart': 'presentation/widgets/command_panel.dart',
  'features/send/presentation/widgets/target_picker.dart': 'presentation/widgets/target_picker.dart',
  'features/admin/application/conversation_list_cubit.dart': 'application/conversation_list_cubit.dart',
  'features/admin/application/conversation_list_state.dart': 'application/conversation_list_state.dart',
  'features/admin/application/conversation_source.dart': 'application/conversation_source.dart',
  'features/admin/presentation/conversation_list_page.dart': 'presentation/conversation_list_page.dart',
  'features/admin/presentation/chat_page.dart': 'presentation/chat_page.dart',
  'features/scan/presentation/qr_scan_page.dart': 'presentation/qr_scan_page.dart',
};

// 不迁移：宿主已有同类能力
const DROP = [
  'app/di/injection.dart',
  'features/settings/presentation/settings_page.dart',
  'main.dart',
];

const SYMBOL_RENAMES = [
  ['AppConfig', 'ControlConfig'],
  ['AppSettings', 'ControlSettings'],
  ['AppLog', 'ControlLog'],
];

// pscreen_control 的 import 前缀 -> pscreen_home 内的目标前缀
const IMPORT_MAP = {
  'package:pscreen_control/app/config/app_config.dart':
    'package:pscreen_home/features/remote_control/core/control_config.dart',
  'package:pscreen_control/app/storage/app_settings.dart':
    'package:pscreen_home/features/remote_control/data/control_settings.dart',
  'package:pscreen_control/app/utils/app_log.dart':
    'package:pscreen_home/features/remote_control/core/control_log.dart',
  'package:pscreen_control/core/nim_client.dart':
    'package:pscreen_home/features/remote_control/data/nim_client.dart',
  'package:pscreen_control/core/chat_message_item.dart':
    'package:pscreen_home/features/remote_control/domain/chat_message_item.dart',
  'package:pscreen_control/features/send/application/send_cubit.dart':
    'package:pscreen_home/features/remote_control/application/send_cubit.dart',
  'package:pscreen_control/features/send/data/tv_directory.dart':
    'package:pscreen_home/features/remote_control/data/tv_directory.dart',
  'package:pscreen_control/features/send/presentation/widgets/command_panel.dart':
    'package:pscreen_home/features/remote_control/presentation/widgets/command_panel.dart',
  'package:pscreen_control/features/send/presentation/widgets/target_picker.dart':
    'package:pscreen_home/features/remote_control/presentation/widgets/target_picker.dart',
  'package:pscreen_control/features/scan/presentation/qr_scan_page.dart':
    'package:pscreen_home/features/remote_control/presentation/qr_scan_page.dart',
  'package:pscreen_control/features/admin/presentation/conversation_list_page.dart':
    'package:pscreen_home/features/remote_control/presentation/conversation_list_page.dart',
  'package:pscreen_control/features/admin/presentation/chat_page.dart':
    'package:pscreen_home/features/remote_control/presentation/chat_page.dart',
  'package:pscreen_control/features/protocol/envelope_builder.dart':
    'package:pscreen_screen/features/msg/protocol/envelope_builder.dart',
  // 同目录相对 import（part / export）保持原样
};

function rewrite(text) {
  let out = text;
  for (const [from, to] of Object.entries(IMPORT_MAP)) {
    out = out.replaceAll(from, to);
  }
  for (const [from, to] of SYMBOL_RENAMES) {
    out = out.replace(new RegExp(`\\b${from}\\b`, 'g'), to);
  }
  // 遥控端自带的 Injection 门面统一改用宿主 Injection
  out = out.replaceAll(
    "import 'package:pscreen_control/app/di/injection.dart';",
    "import 'package:pscreen_home/core/di/injection.dart';",
  );
  out = out.replaceAll('getIt<', 'Injection.get<');
  return out;
}

for (const [from, to] of Object.entries(MOVES)) {
  const src = path.join(SRC, from);
  if (!fs.existsSync(src)) {
    console.log(`跳过（不存在）：${from}`);
    continue;
  }
  const dest = path.join(DST, to);
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest, rewrite(fs.readFileSync(src, 'utf8')));
  fs.rmSync(src);
  console.log(`迁移：${from} -> features/remote_control/${to}`);
}

for (const rel of DROP) {
  const p = path.join(SRC, rel);
  if (fs.existsSync(p)) {
    fs.rmSync(p);
    console.log(`删除：${rel}`);
  }
}
```

- [ ] **Step 2: 跑迁移脚本**

Run: `node tool/migrate_control_into_home.mjs "E:/Code/potatokid_clipboard"`
Expected: 16 行 `迁移：...` + 3 行 `删除：...`

- [ ] **Step 3: 修正 `send_cubit.dart` 的 `part` 指令**

`pscreen_home/lib/features/remote_control/application/send_cubit.dart` 里 `part 'send_state.dart';` 保持不变（两个文件同目录）✓。

- [ ] **Step 4: 修正 `conversation_list_cubit.dart` 的 export**

该文件原有：

```dart
export 'conversation_source.dart'
    show ConversationSource, NimConversationSource, peerAccountFromConversationId;
```

两个文件已同目录（`application/`），export 保持相对路径即可 ✓。

- [ ] **Step 5: 分析**

Run: `cd pscreen_home && flutter analyze`
Expected: 剩余 error 集中在「`NimClient` 未注册」「`TvDirectory` 未注册」「`ControlSettings` 未加载」等 DI 相关，运行 Task 5 后清零。先记录当前 error 清单作为对照。

- [ ] **Step 6: 提交**

```bash
git add -A pscreen_home pscreen_control tool/migrate_control_into_home.mjs
git commit -m "refactor(home): pscreen_control 遥控能力迁入 features/remote_control"
```

---

### Task 3: 资产迁移（tvs.json）

**Files:**
- Create: `pscreen_home/assets/tvs.json`
- Delete: `pscreen_control/assets/tvs.json`
- Modify: `pscreen_home/pubspec.yaml`

- [ ] **Step 1: 迁移资产**

```bash
git mv pscreen_control/assets/tvs.json pscreen_home/assets/tvs.json
```

- [ ] **Step 2: pubspec 声明**

`pscreen_home/pubspec.yaml` 的 `flutter: assets:` 段追加：

```yaml
    - assets/tvs.json
```

- [ ] **Step 3: 检查 `tv_directory.dart` 的资产路径**

`pscreen_home/lib/features/remote_control/data/tv_directory.dart` 中：

```dart
    final String raw = await rootBundle.loadString('assets/tvs.json');
```

路径正确（宿主自己的资产，无前缀问题）✓。

- [ ] **Step 4: 提交**

```bash
git add -A pscreen_home/assets pscreen_control/assets pscreen_home/pubspec.yaml
git commit -m "chore(home): 遥控目标电视列表资产迁入宿主"
```

---

### Task 4: NIM 单一初始化

**Files:**
- Modify: `packages/pscreen_screen/lib/core/utils/nim_manager.dart`
- Modify: `pscreen_home/lib/features/remote_control/data/nim_client.dart`

- [ ] **Step 1: `NimManager.init()` 改为幂等**

`packages/pscreen_screen/lib/core/utils/nim_manager.dart`：

在 `class NimManager {` 内新增静态字段：

```dart
  /// SDK 是否已初始化（`NimCore.instance` 是全局单例，不可重复 initialize）。
  static bool _sdkInitialized = false;
```

把 `init` 方法改为：

```dart
  Future init({required String appKey}) async {
    // NimCore.instance 是全局单例，重复 initialize 会失败。
    // 同一进程内可能有多个封装（如宿主既当发送端又当接收端），因此幂等处理。
    if (_sdkInitialized) {
      Log.i('[NimManager] SDK 已初始化，跳过');
      return;
    }
    if (kIsWeb) {
      var base = NIMInitializeOptions(appkey: appKey, apiVersion: 'v2', debugLevel: 'debug');
      options = NIMWebSDKOptions(appKey: appKey, initializeOptions: base);
    } else if (Platform.isAndroid) {
      final directory = await getExternalStorageDirectory();
      options = NIMAndroidSDKOptions(
        appKey: appKey,
        shouldSyncStickTopSessionInfos: true,
        //若需要使用云端会话，请提前开启云端会话
        enableV2CloudConversation: true,
        sdkRootDir: directory != null ? '${directory.path}/NIMFlutter' : null,
      );
    } else if (Platform.isIOS) {
      final directory = await getApplicationDocumentsDirectory();
      options = NIMIOSSDKOptions(
        appKey: appKey,
        shouldSyncStickTopSessionInfos: true,
        //若需要使用云端会话，请提前开启云端会话
        enableV2CloudConversation: true,
        sdkRootDir: '${directory.path}/NIMFlutter',
        apnsCername: 'your apnsCername',
        pkCername: 'your pkCername',
      );
    } else if (Platform.isMacOS || Platform.isWindows) {
      NIMBasicOption basicOption = NIMBasicOption();
      options = NIMPCSDKOptions(basicOption: basicOption, appKey: appKey);
    }

    var value = await NimCore.instance.initialize(options);
    _sdkInitialized = true;
    Log.i('[NimManager] initialize result: $value');
  }
```

- [ ] **Step 2: `NimClient` 删除自己的 SDK 初始化**

`pscreen_home/lib/features/remote_control/data/nim_client.dart`：

删除整个 `init()` 方法：

```dart
  /// SDK 初始化（幂等；失败记日志并返回 false，UI 层提示）。
  Future<bool> init() async {
    try {
      final NIMSDKOptions options = await _buildOptions(AppConfig.nimAppKey);
      final NIMResult<void> value = await NimCore.instance.initialize(options);
      AppLog.i('[NimClient] initialize result: $value');
      return value.isSuccess;
    } catch (e) {
      AppLog.e('[NimClient] initialize 失败: $e');
      return false;
    }
  }
```

删除整个 `_buildOptions` 方法：

```dart
  /// 照抄 TV NimManager 的平台分支与选项构造。
  Future<NIMSDKOptions> _buildOptions(String appKey) async {
    ...
  }
```

同时删除随之失效的 import：

```dart
import 'package:nim_core_v2_platform_interface/nim_core_v2_platform_interface.dart'
    hide Log;
```

> SDK 初始化统一由宿主的 `NimManager.init(appKey: ...)` 触发（见 Task 5）。`NimClient` 只负责账号登录与消息收发。

- [ ] **Step 3: 检查 `NimClient` 里 `AppConfig.nimAppKey` 的残留引用**

Run: `grep -n "nimAppKey\|AppConfig" pscreen_home/lib/features/remote_control/data/nim_client.dart`
Expected: 无输出（`ControlConfig` 里虽然仍有 `nimAppKey` 常量，但本文件不再引用）

- [ ] **Step 4: 提交**

```bash
git add -A packages/pscreen_screen pscreen_home
git commit -m "fix(screen): NIM SDK 单一初始化，遥控端不再重复 initialize"
```

---

### Task 5: 遥控端 DI 模块

**Files:**
- Create: `pscreen_home/lib/core/di/modules/remote_control_module.dart`
- Modify: `pscreen_home/lib/core/di/injection.dart`

- [ ] **Step 1: 写 DI 模块**

Create `pscreen_home/lib/core/di/modules/remote_control_module.dart`:

```dart
import 'package:pscreen_home/core/di/get_it.dart';
import 'package:pscreen_home/features/remote_control/data/control_settings.dart';
import 'package:pscreen_home/features/remote_control/data/nim_client.dart';
import 'package:pscreen_home/features/remote_control/data/tv_directory.dart';

/// 遥控模块：注册 NIM 发送端客户端、目标电视目录。
///
/// 依赖共享包 `ScreenModules.register` 已注册的 `NimManager`
/// （NIM SDK 由宿主统一初始化，此处不重复 initialize）。
class RemoteControlModule {
  const RemoteControlModule._();

  static Future<void> register() async {
    // 持久化（账号 / token / 已勾选目标）需先加载完成，
    // 否则 SendCubit 构造时读不到已存目标。
    await ControlSettings.instance.ensureLoaded();

    getIt.registerLazySingleton<NimClient>(() => NimClient());
    getIt.registerLazySingleton<TvDirectory>(() => TvDirectory());
  }

  static Future<void> unregister() async {
    await getIt.unregister<TvDirectory>();
    await getIt.unregister<NimClient>();
  }
}
```

- [ ] **Step 2: `Injection.init()` 加入遥控模块**

`pscreen_home/lib/core/di/injection.dart`：

import 区追加：

```dart
import 'package:pscreen_home/core/di/modules/remote_control_module.dart';
```

`init()` 中，在 `await ScreenModules.register(getIt);` 之后、`await StorageModule.register();` 之前插入：

```dart
    // 2.1 遥控模块（NimClient 依赖共享包注册的 NimManager）
    await RemoteControlModule.register();
```

`reset()` 中在 `await ScreenModules.unregister(getIt);` 之前插入：

```dart
    await RemoteControlModule.unregister();
```

- [ ] **Step 3: `ControlSettings` 改为可注入的实例**

`pscreen_home/lib/features/remote_control/data/control_settings.dart` 保留 `static final ControlSettings instance = ControlSettings._();` 单例（与原 `AppSettings` 一致），无需改造。

- [ ] **Step 4: `TvDirectory` 加载资产**

`TvDirectory.loadFromAssets()` 需要在启动时调用一次。在 `pscreen_home/lib/main.dart` 的 `await Injection.init();` 之后加入：

```dart
      // 2.2 遥控目标电视目录（assets/tvs.json）
      await Injection.get<TvDirectory>().loadFromAssets();
```

并在 import 区追加：

```dart
import 'package:pscreen_home/features/remote_control/data/tv_directory.dart';
```

- [ ] **Step 5: 分析**

Run: `cd pscreen_home && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 6: 提交**

```bash
git add -A pscreen_home
git commit -m "feat(home): 注册遥控端依赖注入模块"
```

---

### Task 6: 遥控页面（两 tab）与路由

**Files:**
- Create: `pscreen_home/lib/features/remote_control/presentation/remote_control_page.dart`
- Modify: `pscreen_home/lib/core/router/route_names.dart`
- Modify: `pscreen_home/lib/core/router/app_router.dart`

- [ ] **Step 1: 写遥控页面**

Create `pscreen_home/lib/features/remote_control/presentation/remote_control_page.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:pscreen_home/features/remote_control/presentation/conversation_list_page.dart';
import 'package:pscreen_home/features/remote_control/presentation/send_page.dart';

/// 遥控页：两个 tab —— 遥控面板（发指令）与会话列表（聊天记录）。
///
/// 遥控面板直接复用迁移过来的 `SendPage`（内部按登录账号分叉：
/// 管理员看到多选广播页，家人看到单选页）。
class RemoteControlPage extends StatelessWidget {
  const RemoteControlPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('遥控'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: '遥控面板'),
              Tab(text: '会话'),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[
            SendPage(),
            ConversationListPage(),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: `_AdminSendShell` 剥离 Scaffold 与内层 TabBar**

`pscreen_home/lib/features/remote_control/presentation/send_page.dart` 中，原 `_AdminSendShell.build` 自带 `Scaffold` + 内层 `TabBar`（群发 / 会话）。外层 `RemoteControlPage` 已提供 TabBar（遥控面板 / 会话），因此这里只保留「群发」内容。

把整个 `_AdminSendShell` 类替换为：

```dart
/// 管理员外壳：外层 TabBar（遥控面板 / 会话）由 RemoteControlPage 提供，
/// 这里只负责「群发」内容，不再自带 Scaffold 与 TabBar。
class _AdminSendShell extends StatelessWidget {
  const _AdminSendShell();

  @override
  Widget build(BuildContext context) {
    return const _BroadcastTab();
  }
}
```

- [ ] **Step 3: `_FamilySendPage` 剥离 Scaffold**

同文件中 `_FamilySendPage.build` 原为：

```dart
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('发指令')),
      body: BlocBuilder<SendCubit, SendState>(
        builder: (BuildContext context, SendState state) {
          return SingleChildScrollView(
```

改为（去掉 `Scaffold` 与 `AppBar` 外壳，只保留内容；`SingleChildScrollView` 的缩进整体左移两格）：

```dart
  @override
  Widget build(BuildContext context) {
    return BlocBuilder<SendCubit, SendState>(
      builder: (BuildContext context, SendState state) {
        return SingleChildScrollView(
```

方法体其余部分（`child:` / `children:` / 结尾括号）保持原有，只删掉最外层的 `Scaffold(appBar: ..., body: ...)` 两层包裹。

- [ ] **Step 4: `ConversationListPage` 无需改动**

`pscreen_home/lib/features/remote_control/presentation/conversation_list_page.dart` 的 `ConversationListPage.build` 返回的是 `BlocProvider` + `_ConversationListView`（**没有 Scaffold**），可直接作为 `TabBarView` 的子项。

- [ ] **Step 5: 去掉重复的资产加载**

同文件 `_BroadcastTabState.initState` 中原有：

```dart
    getIt<TvDirectory>().loadFromAssets();
```

迁移脚本已把它改写为 `Injection.get<TvDirectory>().loadFromAssets();`。但 S3 Task 5 Step 4 已在 `main.dart` 统一加载过，此处属重复读取，**删掉这一行**：

```dart
  @override
  void initState() {
    super.initState();
  }
```


- [ ] **Step 6: 路由常量**

`pscreen_home/lib/core/router/route_names.dart` 追加：

```dart
  // 遥控页（遥控面板 + 会话列表两 tab）
  static const String remoteControl = 'remote';

  /// 遥控页完整路径
  static String get remoteControlPath => '/$remoteControl';
```

- [ ] **Step 7: 路由注册**

`pscreen_home/lib/core/router/app_router.dart`：import 区追加：

```dart
import 'package:pscreen_home/features/remote_control/presentation/remote_control_page.dart';
```

在 `_buildRoutes()` 的 `GoRoute` 列表里，`RouteNames.settings` 之前插入：

```dart
      GoRoute(
        path: RouteNames.remoteControl,
        name: RouteNames.remoteControl,
        builder: (context, state) => const RemoteControlPage(),
      ),
```

> 注意：该路由挂在 `RouteNames.home` 的**子路由**列表里（`home` 的 `GoRoute` 内有 `routes:`），因此 `path` 用相对路径 `'remote'`，完整路径为 `/remote`。

- [ ] **Step 8: 分析**

Run: `cd pscreen_home && flutter analyze`
Expected: `No issues found!`

- [ ] **Step 9: 提交**

```bash
git add -A pscreen_home
git commit -m "feat(home): 新增遥控页（遥控面板 + 会话列表两 tab）与路由"
```

---

### Task 7: 中控板 AppBar 增加「遥控」入口

**Files:**
- Modify: `pscreen_home/lib/features/home/presentation/pages/home_controll_board.dart`

- [ ] **Step 1: 增加 action**

`pscreen_home/lib/features/home/presentation/pages/home_controll_board.dart` 的 `AppBar.actions` 中，在「刷新」按钮之前插入：

```dart
            IconButton(
              tooltip: '遥控',
              icon: const Icon(Icons.cast_rounded),
              onPressed: () =>
                  Injection.get<AppRouter>().push(RouteNames.remoteControlPath),
            ),
```

- [ ] **Step 2: 分析 + 提交**

Run: `cd pscreen_home && flutter analyze`
Expected: `No issues found!`

```bash
git add -A pscreen_home
git commit -m "feat(home): 中控板 AppBar 增加遥控入口"
```

---

### Task 8: 设置页扩展「遥控」分组

**Files:**
- Modify: `pscreen_home/lib/features/settings/presentation/pages/settings_page.dart`

- [ ] **Step 1: 加 NIM 账号 / 令牌输入**

在 `_SettingsPageState` 中新增两个控制器：

```dart
  late final TextEditingController _nimAccountController;
  late final TextEditingController _nimTokenController;
```

在 `initState()` 中初始化（紧跟 `_uiScale = store.uiScale;` 之后）：

```dart
    _nimAccountController =
        TextEditingController(text: ControlSettings.instance.nimAccount);
    _nimTokenController =
        TextEditingController(text: ControlSettings.instance.nimToken);
```

在 `dispose()` 中追加：

```dart
    _nimAccountController.dispose();
    _nimTokenController.dispose();
```

import 区追加：

```dart
import 'package:pscreen_home/features/remote_control/core/control_config.dart';
import 'package:pscreen_home/features/remote_control/data/control_settings.dart';
```

- [ ] **Step 2: 加「遥控」分组 UI**

在 `build()` 的 `children` 列表中，`const SizedBox(height: 24),` + `const _ConnectionStatusLine(),` **之前**插入：

```dart
          const SizedBox(height: 24),
          Text(
            '遥控（云信）',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            '用于向电视端下发音量 / 切台 / 文本指令。账号与 Token 与电视端共用同一套云信应用。',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _nimAccountController,
            decoration: const InputDecoration(
              labelText: '云信账号',
              helperText: '管理员账号见遥控面板（默认 1000001）',
              border: OutlineInputBorder(),
            ),
            maxLines: 1,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nimTokenController,
            decoration: InputDecoration(
              labelText: '云信 Token',
              helperText: '默认 ${ControlConfig.defaultNimToken}',
              border: const OutlineInputBorder(),
            ),
            maxLines: 1,
          ),
          const SizedBox(height: 10),
          FilledButton.tonalIcon(
            onPressed: _saveNimCredentials,
            icon: const Icon(Icons.save_rounded),
            label: const Text('保存遥控配置'),
          ),
```

- [ ] **Step 3: 加保存方法**

在 `_SettingsPageState` 中新增：

```dart
  /// 保存云信账号 / Token，并立即尝试登录（失败仅提示，不阻断中控台）。
  Future<void> _saveNimCredentials() async {
    final String account = _nimAccountController.text.trim();
    final String token = _nimTokenController.text.trim().isEmpty
        ? ControlConfig.defaultNimToken
        : _nimTokenController.text.trim();
    await ControlSettings.instance.setNimAccount(account);
    await ControlSettings.instance.setNimToken(token);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('已保存遥控配置'),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }
```

- [ ] **Step 4: 分析 + 提交**

Run: `cd pscreen_home && flutter analyze`
Expected: `No issues found!`

```bash
git add -A pscreen_home
git commit -m "feat(home): 设置页新增遥控（云信账号 / Token）配置分组"
```

---

### Task 9: 测试迁移与验收

**Files:**
- Create: `pscreen_home/test/features/remote_control/application/send_cubit_test.dart`
- Create: `pscreen_home/test/features/remote_control/application/conversation_list_cubit_test.dart`
- Create: `pscreen_home/test/features/remote_control/application/conversation_id_parser_test.dart`
- Create: `pscreen_home/test/features/remote_control/data/tv_directory_test.dart`
- Delete: `pscreen_control/test/**`

- [ ] **Step 1: 迁移测试**

```bash
mkdir -p pscreen_home/test/features/remote_control/application pscreen_home/test/features/remote_control/data
git mv pscreen_control/test/send/send_cubit_test.dart pscreen_home/test/features/remote_control/application/send_cubit_test.dart
git mv pscreen_control/test/admin/conversation_list_cubit_test.dart pscreen_home/test/features/remote_control/application/conversation_list_cubit_test.dart
git mv pscreen_control/test/admin/conversation_id_parser_test.dart pscreen_home/test/features/remote_control/application/conversation_id_parser_test.dart
git mv pscreen_control/test/send/tv_directory_test.dart pscreen_home/test/features/remote_control/data/tv_directory_test.dart
git rm pscreen_control/test/widget_test.dart
```

- [ ] **Step 2: 改写测试里的 import 与符号**

在迁入的 4 个测试文件中，把

```dart
import 'package:pscreen_control/...';
```

按 Task 2 脚本的 `IMPORT_MAP` 改写为 `package:pscreen_home/features/remote_control/...`；把 `AppSettings` → `ControlSettings`、`AppConfig` → `ControlConfig`、`AppLog` → `ControlLog`。

统一用一条命令完成：

```bash
node -e "const fs=require('fs'),path=require('path');const H='pscreen_home/test/features/remote_control';const files=[];(function w(d){for(const e of fs.readdirSync(d,{withFileTypes:true})){const p=path.join(d,e.name);e.isDirectory()?w(p):(e.name.endsWith('.dart')&&files.push(p));}})(H);const M={'package:pscreen_control/app/config/app_config.dart':'package:pscreen_home/features/remote_control/core/control_config.dart','package:pscreen_control/app/storage/app_settings.dart':'package:pscreen_home/features/remote_control/data/control_settings.dart','package:pscreen_control/app/utils/app_log.dart':'package:pscreen_home/features/remote_control/core/control_log.dart','package:pscreen_control/core/nim_client.dart':'package:pscreen_home/features/remote_control/data/nim_client.dart','package:pscreen_control/features/send/application/send_cubit.dart':'package:pscreen_home/features/remote_control/application/send_cubit.dart','package:pscreen_control/features/send/data/tv_directory.dart':'package:pscreen_home/features/remote_control/data/tv_directory.dart','package:pscreen_control/features/protocol/envelope_builder.dart':'package:pscreen_screen/features/msg/protocol/envelope_builder.dart'};for(const f of files){let t=fs.readFileSync(f,'utf8');for(const [a,b] of Object.entries(M))t=t.replaceAll(a,b);t=t.replace(/\bAppSettings\b/g,'ControlSettings').replace(/\bAppConfig\b/g,'ControlConfig').replace(/\bAppLog\b/g,'ControlLog');fs.writeFileSync(f,t);console.log('  '+f);}"
```

- [ ] **Step 3: 遥控测试全绿**

Run: `cd pscreen_home && flutter test test/features/remote_control/`
Expected: 全部通过

若 `send_cubit_test` 因 `NimClient` 变化失败（`NimClient.init()` 已删除），把测试里的 `NimClient` 替身改为实现 `sendText` 的 Fake —— 原测试若已用 Fake 则无需改。

- [ ] **Step 4: 宿主全量测试**

Run: `cd pscreen_home && flutter test`
Expected: 全部通过

- [ ] **Step 5: 共享包全量测试**

Run: `cd packages/pscreen_screen && flutter test && flutter analyze`
Expected: 全部通过 + `No issues found!`

- [ ] **Step 6: 构建**

Run: `cd pscreen_home && flutter build windows --debug; if ($?) { flutter build apk --debug }`
Expected: 两个都 `Built ...`

- [ ] **Step 7: 标注 pscreen_control 已废弃**

Create `pscreen_control/README.md`（覆盖原文件）：

```markdown
# pscreen_control（已废弃）

本项目的遥控端能力已并入 `pscreen_home`：

- 遥控面板 / 会话列表 / 扫码 → `pscreen_home/lib/features/remote_control/`
- 协议构造器 → `packages/pscreen_screen/lib/features/msg/protocol/envelope_builder.dart`
- 目标电视列表资产 → `pscreen_home/assets/tvs.json`

本目录**不再维护、不再单独发布**，仅保留作为迁移参考与回退路径。
```

- [ ] **Step 8: 端到端人工验证（G14）**

1. 启动电视端 `pscreen/potatokid_screen`（`flutter run -d windows`），确认已登录云信
2. 启动中控屏 `pscreen_home`，进入「遥控」页
3. 在「遥控面板」tab 勾选目标电视 → 点「音量+」→ 电视端音量应上升，电视端浮层显示上报文本
4. 点「文本」发送一条消息 → 电视端浮层应显示该文本
5. 切到「会话」tab → 应能看到与电视端的会话记录，点击可进入聊天页发送消息

> 若电视端无反应：检查两端 `.env` 的 `NIM_PASSWORD` 与账号是否一致；检查 `ControlConfig.nimAppKey` 与共享包 `AppConstants.nimAppKey` 是否一致（均为 `8e3cb3b1cf5f8ae073c269ad461a69b5`）。

- [ ] **Step 9: 提交**

```bash
git add -A pscreen_home pscreen_control packages/pscreen_screen
git commit -m "test(home): 遥控端测试迁入并标注 pscreen_control 废弃"
```

---

## S3 完成定义

- [ ] G10 `pscreen_home` analyze 零问题
- [ ] G11 `pscreen_home` test 全绿
- [ ] G12 共享包 analyze + test 全绿
- [ ] G13 windows + apk 构建成功
- [ ] G14 端到端遥控验证通过
- [ ] `pscreen_control` 目录已标注废弃，代码已全部并入

**下一步**：执行 `docs/superpowers/plans/2026-10-21-s4-screen-pages.md`（屏幕页面）。
