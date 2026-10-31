# pscreen_control 发送端实现计划（计划 2 / 电视消息遥控）

> Spec: `docs/superpowers/specs/2026-10-15-tv-message-remote-design.md` §3（协议）、§4（发送端）
> 计划 1（TV 端）: `docs/superpowers/plans/2026-10-15-tv-message-remote.md`
> 项目根: `E:\Code\potatokid_clipboard\pscreen_control\`（flutter create 脚手架，当前仅默认 lib/main.dart）
> 分支: `feature/remote_msg`（与 TV 端同分支，发送端为仓库内并列目录；各任务在 pscreen_control 目录下执行 git add/commit）

## 关键决策（已确认）

- 管理员账号 `1000001`；其它账号 = 家人
- token 默认 `12345678`，设置页可编辑
- 协议与 TV 端解析器对齐：普通文本→浮层；`{t:txt|cmd}` JSON 信封；命令名 `volume_up/volume_down/mute/channel/text`
- 登录成功后按账号分叉 UI；未登录强制进设置页
- NIM 集成沿用 TV 端方式：`nim_core_v2: ^10.9.91`、`// ignore: depend_on_referenced_packages` + `hide Log`

## File Structure

```
pscreen_control/
├── assets/
│   └── tvs.json                          # 预设电视列表
├── lib/
│   ├── main.dart                         # 启动：DI + NIM 初始化 + 登录路由
│   ├── app/
│   │   ├── config/app_config.dart        # nimToken 默认 '12345678'
│   │   ├── di/injection.dart             # get_it 门面
│   │   ├── storage/app_settings.dart     # 持久化：账号/token/最近目标
│   │   └── utils/app_log.dart            # 简易 print 包装
│   ├── core/
│   │   └── nim_client.dart               # NIM 初始化/登录/登出/收发（薄封装）
│   └── features/
│       ├── protocol/
│       │   └── envelope_builder.dart     # 下行信封构造（与 TV 解析器对齐）
│       ├── settings/
│       │   └── presentation/settings_page.dart
│       ├── send/
│       │   ├── application/send_cubit.dart
│       │   ├── data/tv_directory.dart    # tvs.json 加载 + 名称查询 + 最近目标
│       │   └── presentation/
│       │           send_page.dart        # 家人单页 / 管理员群发（按账号分叉）
│       │           widgets/command_panel.dart
│       │           widgets/target_picker.dart
│       ├── scan/
│       │   └── presentation/qr_scan_page.dart
│       └── admin/
│           ├── application/conversation_list_cubit.dart
│           └── presentation/
│                   conversation_list_page.dart
│                   chat_page.dart
└── test/
    ├── protocol/envelope_builder_test.dart
    ├── send/tv_directory_test.dart
    ├── send/send_cubit_test.dart
    └── app/app_settings_test.dart
```

---

### Task 1: 脚手架改造 + 依赖 + DI + 配置/存储/日志

**Files:**
- Modify: `pubspec.yaml`
- Create: `assets/tvs.json`
- Create: `lib/app/config/app_config.dart`
- Create: `lib/app/storage/app_settings.dart`
- Create: `lib/app/utils/app_log.dart`
- Create: `lib/app/di/injection.dart`
- Modify: `lib/main.dart`

- [ ] **Step 1: pubspec.yaml**

`environment` 保持 `sdk: ^3.11.5`。`dependencies` 替换为：

```yaml
dependencies:
  flutter:
    sdk: flutter

  cupertino_icons: ^1.0.8
  flutter_bloc: ^9.1.1
  get_it: ^9.3.0
  equatable: ^2.0.7
  shared_preferences: ^2.5.0
  # ignore: depend_on_referenced_packages
  nim_core_v2: ^10.9.91
  mobile_scanner: ^6.0.0
  easy_localization: ^3.0.8
```

`flutter:` 段：

```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/tvs.json
```

（`mobile_scanner` 版本以 `flutter pub get` 成功解析为准；若 6.x 与 SDK 冲突则降 5.x 并在报告注明。）

- [ ] **Step 2: assets/tvs.json**

```json
[
  { "name": "客厅电视", "account": "TV_001" },
  { "name": "卧室电视", "account": "TV_002" }
]
```

- [ ] **Step 3: AppLog / AppConfig / AppSettings**

```dart
// lib/app/utils/app_log.dart
import 'package:flutter/foundation.dart';

/// 简易日志（仅 debugPrint）。
class AppLog {
  const AppLog._();

  static void d(String message) => debugPrint('[AppLog] $message');
  static void i(String message) => debugPrint('[AppLog] $message');
  static void e(String message) => debugPrint('[AppLog][E] $message');
}
```

```dart
// lib/app/config/app_config.dart
/// 环境常量。
class AppConfig {
  const AppConfig._();

  /// 管理员云信账号（TV 上报目标）。
  static const String adminAccount = '1000001';

  /// NIM 登录 token 默认值（设置页可改）。
  static const String defaultNimToken = '12345678';
}
```

```dart
// lib/app/storage/app_settings.dart
import 'package:shared_preferences/shared_preferences.dart';

/// 持久化：登录账号、token、管理员最近勾选的 TV 目标。
class AppSettings {
  AppSettings._();

  static final AppSettings instance = AppSettings._();

  static const String _kAccount = 'nim_account';
  static const String _kToken = 'nim_token';
  static const String _kSelectedTvs = 'selected_tv_accounts';

  late SharedPreferences _prefs;
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _prefs = await SharedPreferences.getInstance();
    _loaded = true;
  }

  String get nimAccount => _prefs.getString(_kAccount) ?? '';
  Future<void> setNimAccount(String value) =>
      _prefs.setString(_kAccount, value);

  String get nimToken =>
      _prefs.getString(_kToken) ?? '12345678';
  Future<void> setNimToken(String value) =>
      _prefs.setString(_kToken, value);

  /// 管理员最近勾选的目标账号列表。
  List<String> get selectedTvAccounts =>
      _prefs.getStringList(_kSelectedTvs) ?? const <String>[];
  Future<void> setSelectedTvAccounts(List<String> value) =>
      _prefs.setStringList(_kSelectedTvs, value);
}
```

- [ ] **Step 4: DI + main.dart**

```dart
// lib/app/di/injection.dart
import 'package:get_it/get_it.dart';
import 'package:pscreen_control/core/nim_client.dart';
import 'package:pscreen_control/features/send/data/tv_directory.dart';

final GetIt getIt = GetIt.instance;

/// 依赖注入门面。
class Injection {
  const Injection._();

  static Future<void> init() async {
    await getIt.allReady();
    if (!getIt.isRegistered<NimClient>()) {
      getIt.registerLazySingleton<NimClient>(() => NimClient());
    }
    if (!getIt.isRegistered<TvDirectory>()) {
      getIt.registerLazySingleton<TvDirectory>(() => TvDirectory());
    }
  }
}
```

```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:pscreen_control/app/di/injection.dart';
import 'package:pscreen_control/app/storage/app_settings.dart';
import 'package:pscreen_control/core/nim_client.dart';
import 'package:pscreen_control/features/settings/presentation/settings_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppSettings.instance.ensureLoaded();
  await Injection.init();
  // NIM 初始化失败不阻断 UI：设置页可见并显示错误。
  await Injection.get<NimClient>().init();
  final String account = AppSettings.instance.nimAccount;
  if (account.isNotEmpty) {
    await Injection.get<NimClient>().autoLogin(account: account);
  }
  runApp(const PscreenControlApp());
}

/// getIt 便捷访问（与 Injection.get 同义，局部使用）。
extension on Injection {
  // 占位：无需实例方法。
}

class PscreenControlApp extends StatelessWidget {
  const PscreenControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PScreen Control',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const SettingsPage(),
    );
  }
}
```

（`Injection.get` 简写为 `getIt<T>()` 即可——main.dart 直接 `getIt<NimClient>()`，删掉无用 extension。最终 main 里用 `getIt` 变量。）

- [ ] **Step 5: 验证**

Run: `flutter pub get`
Run: `flutter analyze`
Expected: No issues found（Task 2 的 NimClient 未建前，Step 4 import 会报错——**本任务 Step 4 先建空壳 `lib/core/nim_client.dart`**：

```dart
// lib/core/nim_client.dart
/// NIM 客户端薄封装（Task 2 填充）。
class NimClient {
  Future<void> init() async {}
  Future<bool> autoLogin({required String account}) async => false;
}
```
`features/send/data/tv_directory.dart` 同理空壳：

```dart
// lib/features/send/data/tv_directory.dart
/// 预设电视列表（Task 2 填充）。
class TvDirectory {}
```
）

- [ ] **Step 6: Commit**

```bash
git add pubspec.yaml pubspec.lock assets/ lib/
git commit -m "feat: control app scaffold deps di settings"
```

---

### Task 2: TvDirectory + NimClient + 设置页登录

**Files:**
- Modify: `lib/features/send/data/tv_directory.dart`
- Modify: `lib/core/nim_client.dart`
- Create: `lib/features/settings/presentation/settings_page.dart`
- Test: `test/send/tv_directory_test.dart`
- 参考: `../pscreen/potatokid_screen/lib/core/utils/nim_manager.dart`（先读，照抄初始化/登录/登出调用序列与 import 约定）

- [ ] **Step 1: 写失败测试（TvDirectory）**

```dart
// test/send/tv_directory_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_control/features/send/data/tv_directory.dart';

void main() {
  test('从 JSON 列表解析设备', () {
    final List<TvDevice> list = TvDirectory.parseJson(
      '[{"name":"客厅电视","account":"TV_001"},{"name":"卧室","account":"TV_002"}]',
    );
    expect(list.length, 2);
    expect(list.first.name, '客厅电视');
    expect(list.first.account, 'TV_001');
  });

  test('坏 JSON 返回空列表', () {
    expect(TvDirectory.parseJson('{oops'), isEmpty);
  });

  test('nameOf：命中返回名称，未命中返回账号本身', () {
    final TvDirectory dir = TvDirectory(
      devices: TvDirectory.parseJson(
        '[{"name":"客厅电视","account":"TV_001"}]',
      ),
    );
    expect(dir.nameOf('TV_001'), '客厅电视');
    expect(dir.nameOf('TV_999'), 'TV_999');
  });
}
```

- [ ] **Step 2: 实现 TvDirectory**

```dart
// lib/features/send/data/tv_directory.dart
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// 预设电视设备。
class TvDevice {
  const TvDevice({required this.name, required this.account});

  final String name;
  final String account;
}

/// 预设电视列表：assets/tvs.json + 名称查询。
class TvDirectory {
  TvDirectory({this.devices = const <TvDevice>[]});

  final List<TvDevice> devices;

  static List<TvDevice> parseJson(String raw) {
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) return const <TvDevice>[];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((m) => TvDevice(
                name: (m['name'] as String?) ?? '',
                account: (m['account'] as String?) ?? '',
              ))
          .where((d) => d.account.isNotEmpty)
          .toList();
    } catch (_) {
      return const <TvDevice>[];
    }
  }

  /// 从 assets 加载（main/DI 注册后调用一次）。
  Future<void> loadFromAssets() async {
    final String raw = await rootBundle.loadString('assets/tvs.json');
    devices = parseJson(raw);
  }

  /// 账号 → 显示名；未命中返回账号。
  String nameOf(String account) {
    for (final TvDevice d in devices) {
      if (d.account == account) return d.name;
    }
    return account;
  }
}
```

（`devices` 改为可变字段：`List<TvDevice> devices = const <TvDevice>[];` 去掉 final。）

- [ ] **Step 3: 跑测试**

Run: `flutter test test/send/tv_directory_test.dart`
Expected: PASS（3 用例）

- [ ] **Step 4: 实现 NimClient**

先读 TV 端 `nim_manager.dart`（相对路径 `../pscreen/potatokid_screen/lib/core/utils/nim_manager.dart`），照抄：NIM 初始化（`NimCore` SDK 初始化入口）、`login(accountId:, token:)`、`logout()`、`onLoginStatus`/`onLoginFailed` 流的接法。骨架（字段名按 TV 端实际调整）：

```dart
// lib/core/nim_client.dart
// ignore: depend_on_referenced_packages
import 'package:nim_core_v2_platform_interface/nim_core_v2_platform_interface.dart'
    hide Log;

import 'package:pscreen_control/app/storage/app_settings.dart';
import 'package:pscreen_control/app/utils/app_log.dart';

/// NIM 客户端薄封装（模式同 TV 端 NimManager）。
class NimClient {
  /// SDK 初始化（幂等；失败记日志并返回 false，UI 层提示）。
  Future<bool> init() async {
    // 照抄 TV NimManager 的初始化调用序列。
    return true;
  }

  /// 自动登录：同账号已在线则跳过。
  Future<bool> autoLogin({required String account}) async {
    final NIMResult<NIMLoginStatus> status =
        await NimCore.instance.loginService.getLoginStatus();
    if (status.data == NIMLoginStatus.loginStatusLogined) {
      return true;
    }
    return _login(account);
  }

  /// 登录并持久化账号。
  Future<bool> login({
    required String account,
    required String token,
  }) async {
    await AppSettings.instance.setNimToken(token);
    return _login(account, token: token);
  }

  Future<bool> _login(String account, {String? token}) async {
    final String useToken = token ?? AppSettings.instance.nimToken;
    final NIMResult<void> result = await NimCore.instance.loginService
        .login(accountId: account, token: useToken);
    if (result.isSuccess) {
      await AppSettings.instance.setNimAccount(account);
      return true;
    }
    AppLog.e('[NimClient] login 失败: ${result.code}');
    return false;
  }

  Future<void> logout() async {
    await NimCore.instance.loginService.logout();
    await AppSettings.instance.setNimAccount('');
  }

  /// 发送 P2P 文本（与 TV 端 sendTextMessage 同构）。
  Future<bool> sendText({
    required String toAccount,
    required String text,
  }) async {
    final NIMResult<String> cid = await NimCore.instance.conversationIdUtil
        .p2pConversationId(toAccount);
    if (cid.data == null) {
      AppLog.e('[NimClient] p2pConversationId 失败: ${cid.code}');
      return false;
    }
    final NIMResult<NIMMessage> msg =
        await MessageCreator.createTextMessage(text);
    if (msg.data == null) {
      AppLog.e('[NimClient] createTextMessage 失败: ${msg.code}');
      return false;
    }
    final NIMResult<NIMSendMessageResult> r =
        await NimCore.instance.messageService.sendMessage(
      message: msg.data!,
      conversationId: cid.data!,
    );
    return r.data != null;
  }

  /// 登录态流 / 登录失败流（透传 SDK，接法照抄 TV NimManager）。
  Stream<NIMLoginStatus> get onLoginStatus =>
      NimCore.instance.loginService.onLoginStatusChanged;
  Stream<NIMError> get onLoginFailed =>
      NimCore.instance.loginService.onLoginFailed;
  Stream<NIMKickedOfflineDetail> get onKickedOffline =>
      NimCore.instance.loginService.onKickedOffline;
}
```

（`loginService` 名称/初始化序列以 TV NimManager 与 SDK 实际为准；若 TV 端用不同路径，字段访问器逐一照改。init() 必须照抄 TV 端成功验证过的调用。）

- [ ] **Step 5: 设置页**

```dart
// lib/features/settings/presentation/settings_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_control/app/config/app_config.dart';
import 'package:pscreen_control/app/di/injection.dart';
import 'package:pscreen_control/app/storage/app_log.dart';
import 'package:pscreen_control/core/nim_client.dart';
import 'package:pscreen_control/features/send/presentation/send_page.dart';
```

（上面 app_log 路径应为 `package:pscreen_control/app/utils/app_log.dart`，import 以此为准。）

设置页逻辑（bloc 略——登录流程简单，用 StatefulWidget + setState 即可，避免过度分层）：

```dart
/// 设置页：账号 + token 登录；成功后进入发送端主页。
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final TextEditingController _account =
      TextEditingController(text: AppSettings.instance.nimAccount);
  late final TextEditingController _token =
      TextEditingController(text: AppSettings.instance.nimToken);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _account.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final bool ok = await getIt<NimClient>().login(
      account: _account.text.trim(),
      token: _token.text.trim().isEmpty
          ? AppConfig.defaultNimToken
          : _token.text.trim(),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = ok ? null : '登录失败，请检查账号/token';
    });
    if (ok) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const SendPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            TextField(
              controller: _account,
              decoration: const InputDecoration(labelText: '云信账号'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _token,
              decoration: InputDecoration(
                labelText: 'Token（默认 ${AppConfig.defaultNimToken}）',
              ),
            ),
            const SizedBox(height: 24),
            if (_error != null)
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _login,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('登录'),
            ),
          ],
        ),
      ),
    );
  }
}
```

（`flutter_bloc` import 在本文件非必需时删除。main.dart 在自动登录成功后应直接 `SendPage`——main 里改为：account 非空且 autoLogin true → home=SendPage，否则 SettingsPage。）

- [ ] **Step 6: 验证 + Commit**

Run: `flutter analyze` / `flutter test`
Expected: No issues found / All tests passed

```bash
git add lib/ test/
git commit -m "feat: nim client login settings and tv directory"
```

---

### Task 3: 信封构造器 + SendCubit

**Files:**
- Create: `lib/features/protocol/envelope_builder.dart`
- Create: `lib/features/send/application/send_cubit.dart`
- Test: `test/protocol/envelope_builder_test.dart`
- Test: `test/send/send_cubit_test.dart`

- [ ] **Step 1: 写失败测试（信封）**

```dart
// test/protocol/envelope_builder_test.dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_control/features/protocol/envelope_builder.dart';

void main() {
  test('纯文本不加信封', () {
    expect(buildPlainText('你好'), '你好');
  });

  test('volume_up 命令生成正确信封', () {
    final String s = buildVolumeCommand('volume_up');
    final Map<String, dynamic> m = jsonDecode(s) as Map<String, dynamic>;
    expect(m['t'], 'cmd');
    expect(m['name'], 'volume_up');
  });

  test('channel 命令带 args', () {
    final String s = buildChannelCommand(name: 'CCTV-1');
    final Map<String, dynamic> m = jsonDecode(s) as Map<String, dynamic>;
    expect(m['t'], 'cmd');
    expect(m['name'], 'channel');
    expect(m['args']['name'], 'CCTV-1');
  });

  test('channel 按序号命令', () {
    final String s = buildChannelCommand(index: 3);
    final Map<String, dynamic> m = jsonDecode(s) as Map<String, dynamic>;
    expect(m['args']['index'], 3);
  });

  test('text 命令带 content', () {
    final String s = buildTextCommand('集合吃饭');
    final Map<String, dynamic> m = jsonDecode(s) as Map<String, dynamic>;
    expect(m['t'], 'cmd');
    expect(m['name'], 'text');
    expect(m['args']['content'], '集合吃饭');
  });
}
```

- [ ] **Step 2: 实现信封构造器**

```dart
// lib/features/protocol/envelope_builder.dart
import 'dart:convert';

/// 下行信封构造（与 TV 端 message_envelope 解析器对齐）。
///
/// 协议：
/// - 普通文本 → 原样发送（TV 端识别为 plainText → 浮层）
/// - `{"t":"txt","content":...}` → TV 端浮层
/// - `{"t":"cmd","name":...,"args":{...}}` → TV 端命令执行
String buildPlainText(String text) => text;

String buildTextCommand(String content) =>
    jsonEncode(<String, dynamic>{
      't': 'cmd',
      'name': 'text',
      'args': <String, dynamic>{'content': content},
    });

String buildVolumeCommand(String name) =>
    jsonEncode(<String, dynamic>{'t': 'cmd', 'name': name});

String buildChannelCommand({String? name, int? index}) =>
    jsonEncode(<String, dynamic>{
      't': 'cmd',
      'name': 'channel',
      'args': <String, dynamic>{
        if (name != null) 'name': name,
        if (index != null) 'index': index,
      },
    });
```

- [ ] **Step 3: 跑信封测试**

Run: `flutter test test/protocol/envelope_builder_test.dart`
Expected: PASS（5 用例）

- [ ] **Step 4: 写失败测试（SendCubit）**

```dart
// test/send/send_cubit_test.dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_control/core/nim_client.dart';
import 'package:pscreen_control/features/send/application/send_cubit.dart';

/// Fake NimClient：记录 sendText 调用，可控失败。
class FakeNimClient implements NimClient {
  final List<(String, String)> sent = <(String, String)>[];
  bool failNext = false;
  int failCount = 0;

  @override
  Future<bool> sendText({
    required String toAccount,
    required String text,
  }) async {
    sent.add((toAccount, text));
    if (failNext && failCount < 999) {
      failCount++;
      // 只让指定次数失败
      failNext = failCount < 2;
      return false;
    }
    return true;
  }

  @override
  Future<bool> init() async => true;
  @override
  Future<bool> autoLogin({required String account}) async => true;
  @override
  Future<bool> login({required String account, required String token}) async =>
      true;
  @override
  Future<void> logout() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakeNimClient nim;
  late SendCubit cubit;

  setUp(() {
    nim = FakeNimClient();
    cubit = SendCubit(nim: nim);
  });

  tearDown(() => cubit.close());

  test('初始状态：目标空、结果空', () {
    expect(cubit.state.targets, isEmpty);
    expect(cubit.state.sendResults, isEmpty);
    expect(cubit.state.isSending, isFalse);
  });

  test('toggleTarget 切换目标', () {
    cubit.toggleTarget('TV_001');
    expect(cubit.state.targets, contains('TV_001'));
    cubit.toggleTarget('TV_001');
    expect(cubit.state.targets, isNot(contains('TV_001')));
  });

  test('发送纯文本到多台，逐台结果', () async {
    cubit
      ..toggleTarget('TV_001')
      ..toggleTarget('TV_002');
    await cubit.sendPlainText('你好');
    expect(nim.sent.length, 2);
    expect(cubit.state.sendResults['TV_001'], isTrue);
    expect(cubit.state.sendResults['TV_002'], isTrue);
    expect(cubit.state.isSending, isFalse);
  });

  test('部分失败不影响其余，结果逐台记录', () async {
    nim.failNext = true; // 仅第一次失败
    nim.failCount = 0;
    cubit
      ..toggleTarget('TV_A')
      ..toggleTarget('TV_B');
    await cubit.sendPlainText('测试');
    expect(cubit.state.sendResults['TV_A'], isFalse);
    expect(cubit.state.sendResults['TV_B'], isTrue);
  });

  test('发送命令（JSON 信封）', () async {
    cubit.toggleTarget('TV_001');
    await cubit.sendCommand('volume_up');
    expect(nim.sent.single.$2, contains('"t":"cmd"'));
    expect(nim.sent.single.$2, contains('volume_up'));
  });

  test('无目标时发送不调用 SDK', () async {
    await cubit.sendPlainText('你好');
    expect(nim.sent, isEmpty);
    expect(cubit.state.sendResults, isEmpty);
  });
}
```

（若 `bloc_test` 未引入且上述用例不需要 blocTest helper，可直接写普通 `test()`；本组用例已按普通 test 写，不需要 bloc_test 依赖——删除顶部 `import 'package:bloc_test/bloc_test.dart';`。）

- [ ] **Step 5: 实现 SendCubit**

```dart
// lib/features/send/application/send_cubit.dart
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_control/core/nim_client.dart';
import 'package:pscreen_control/features/protocol/envelope_builder.dart';

part 'send_state.dart';

/// 发送端 Cubit：管理目标勾选 + 发送（文本/命令）。
class SendCubit extends Cubit<SendState> {
  SendCubit({required this.nim}) : super(const SendState());

  final NimClient nim;

  void toggleTarget(String account) {
    final List<String> next = List<String>.from(state.targets);
    if (next.contains(account)) {
      next.remove(account);
    } else {
      next.add(account);
    }
    emit(state.copyWith(targets: next));
  }

  void clearResults() {
    emit(state.copyWith(sendResults: const <String, bool>{}));
  }

  /// 发送纯文本（不加信封）到所有已勾选目标。
  Future<void> sendPlainText(String text) =>
      _sendToTargets(buildPlainText(text));

  /// 发送命令信封到所有已勾选目标。
  Future<void> sendCommand(String name, {Map<String, dynamic>? args}) =>
      _sendToTargets(buildCommandEnvelope(name, args));

  Future<void> _sendToTargets(String body) async {
    if (state.targets.isEmpty) return;
    emit(state.copyWith(isSending: true));
    final Map<String, bool> results = <String, bool>{};
    for (final String target in state.targets) {
      final bool ok =
          await nim.sendText(toAccount: target, text: body);
      results[target] = ok;
      emit(state.copyWith(sendResults: Map<String, bool>.from(results)));
    }
    emit(state.copyWith(isSending: false));
  }
}
```

信封辅助（加到 `envelope_builder.dart` 末尾）：

```dart
/// 通用命令信封（快捷面板/命令模式统一入口）。
String buildCommandEnvelope(String name, [Map<String, dynamic>? args]) =>
    jsonEncode(<String, dynamic>{
      't': 'cmd',
      'name': name,
      if (args != null) 'args': args,
    });
```

- [ ] **Step 6: 实现 SendState**

```dart
// lib/features/send/application/send_state.dart
part of 'send_cubit.dart';

class SendState extends Equatable {
  const SendState({
    this.targets = const <String>[],
    this.sendResults = const <String, bool>{},
    this.isSending = false,
  });

  /// 已勾选的目标账号。
  final List<String> targets;

  /// 逐台发送结果（最新一次发送）。
  final Map<String, bool> sendResults;

  /// 是否正在发送。
  final bool isSending;

  SendState copyWith({
    List<String>? targets,
    Map<String, bool>? sendResults,
    bool? isSending,
  }) =>
      SendState(
        targets: targets ?? this.targets,
        sendResults: sendResults ?? this.sendResults,
        isSending: isSending ?? this.isSending,
      );

  @override
  List<Object?> get props => <Object?>[targets, sendResults, isSending];
}
```

- [ ] **Step 7: 跑测试确认通过 + analyze**

Run: `flutter test test/send/send_cubit_test.dart test/protocol/envelope_builder_test.dart`
Expected: PASS

Run: `flutter analyze`
Expected: No issues found

- [ ] **Step 8: Commit**

```bash
git add lib/features/protocol/ lib/features/send/application/ test/
git commit -m "feat: envelope builder and send cubit"
```

---

### Task 4: 发送页 UI（分叉：管理员群发 / 家人单页）

**Files:**
- Create: `lib/features/send/presentation/send_page.dart`
- Create: `lib/features/send/presentation/widgets/command_panel.dart`
- Create: `lib/features/send/presentation/widgets/target_picker.dart`
- Modify: `lib/main.dart`（登录成功后进 SendPage）

- [ ] **Step 1: 命令面板（共享组件）**

```dart
// lib/features/send/presentation/widgets/command_panel.dart
import 'package:flutter/material.dart';
import 'package:pscreen_control/features/protocol/envelope_builder.dart';

/// 命令快捷面板：音量±/静音/频道/text。
class CommandPanel extends StatelessWidget {
  const CommandPanel({
    super.key,
    required this.onCommand,
  });

  /// 回调：已构造好的信封字符串。
  final ValueChanged<String> onCommand;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        _CmdButton(label: '音量+', onTap: () => onCommand(buildCommandEnvelope('volume_up'))),
        _CmdButton(label: '音量-', onTap: () => onCommand(buildCommandEnvelope('volume_down'))),
        _CmdButton(label: '静音', onTap: () => onCommand(buildCommandEnvelope('mute'))),
        _CmdButton(
          label: '频道 CCTV-1',
          onTap: () => onCommand(buildChannelCommand(name: 'CCTV-1')),
        ),
        _CmdButton(
          label: '频道 CCTV-5',
          onTap: () => onCommand(buildChannelCommand(name: 'CCTV-5')),
        ),
        _CmdButton(
          label: '频道下一台',
          onTap: () => onCommand(buildCommandEnvelope('channel_next')),
        ),
      ],
    );
  }
}

class _CmdButton extends StatelessWidget {
  const _CmdButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(onPressed: onTap, child: Text(label));
  }
}
```

（`channel_next` 不在 TV 端协议里——删掉此按钮；频道下一台如需保留，用 index+1 逻辑在 Cubit 里组装，或直接不放。保留前两个频道预设按钮即可。）

- [ ] **Step 2: 目标选择器（管理员群发用）**

```dart
// lib/features/send/presentation/widgets/target_picker.dart
import 'package:flutter/material.dart';
import 'package:pscreen_control/features/send/data/tv_directory.dart';

/// 目标选择器：预设列表多选 + 手动输入 + 扫码。
class TargetPicker extends StatelessWidget {
  const TargetPicker({
    super.key,
    required this.devices,
    required this.selected,
    required this.onToggle,
    required this.onScan,
    required this.manualController,
    required this.onManualAdd,
  });

  final List<TvDevice> devices;
  final Set<String> selected;
  final ValueChanged<String> onToggle;
  final VoidCallback onScan;
  final TextEditingController manualController;
  final VoidCallback onManualAdd;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('目标（已选 ${selected.length}）',
                style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: '扫码添加',
              onPressed: onScan,
            ),
          ],
        ),
        SizedBox(
          height: 180,
          child: ListView(
            children: devices
                .map((TvDevice d) => CheckboxListTile(
                      title: Text(d.name),
                      subtitle: Text(d.account),
                      value: selected.contains(d.account),
                      onChanged: (_) => onToggle(d.account),
                    ))
                .toList(),
          ),
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: manualController,
                decoration: const InputDecoration(
                  hintText: '手动输入账号',
                  isDense: true,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: onManualAdd,
            ),
          ],
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: SendPage（分叉渲染）**

```dart
// lib/features/send/presentation/send_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_control/app/config/app_config.dart';
import 'package:pscreen_control/app/di/injection.dart';
import 'package:pscreen_control/app/storage/app_settings.dart';
import 'package:pscreen_control/core/nim_client.dart';
import 'package:pscreen_control/features/protocol/envelope_builder.dart';
import 'package:pscreen_control/features/send/application/send_cubit.dart';
import 'package:pscreen_control/features/send/data/tv_directory.dart';
import 'package:pscreen_control/features/send/presentation/widgets/command_panel.dart';
import 'package:pscreen_control/features/send/presentation/widgets/target_picker.dart';
import 'package:pscreen_control/features/scan/presentation/qr_scan_page.dart';
import 'package:pscreen_control/features/admin/presentation/conversation_list_page.dart';

/// 发送端主页：按账号分叉。
class SendPage extends StatelessWidget {
  const SendPage({super.key});

  @override
  Widget build(BuildContext context) {
    final String account = AppSettings.instance.nimAccount;
    final bool isAdmin = account == AppConfig.adminAccount;
    return BlocProvider<SendCubit>(
      create: (_) => SendCubit(nim: getIt<NimClient>()),
      child: isAdmin ? const _AdminSendShell() : const _FamilySendPage(),
    );
  }
}

/// 家人单页「发指令」：文本框 + 命令面板 + 手动/扫码选一台。
class _FamilySendPage extends StatefulWidget {
  const _FamilySendPage();

  @override
  State<_FamilySendPage> createState() => _FamilySendPageState();
}

class _FamilySendPageState extends State<_FamilySendPage> {
  final TextEditingController _text = TextEditingController();
  final TextEditingController _manual = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    _manual.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final String? account = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const QrScanPage()),
    );
    if (account != null && account.isNotEmpty) {
      context.read<SendCubit>().toggleTarget(account);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('发指令')),
      body: BlocBuilder<SendCubit, SendState>(
        builder: (BuildContext context, SendState state) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('目标: ${state.targets.join(", ")}'),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _manual,
                        decoration:
                            const InputDecoration(hintText: '手动输入 TV 账号'),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: () {
                        final String v = _manual.text.trim();
                        if (v.isNotEmpty) {
                          context.read<SendCubit>().toggleTarget(v);
                          _manual.clear();
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.qr_code_scanner),
                      onPressed: _scan,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CommandPanel(
                  onCommand: (String body) =>
                      context.read<SendCubit>().sendRaw(body),
                ),
                const Spacer(),
                TextField(
                  controller: _text,
                  decoration: const InputDecoration(hintText: '输入消息'),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: state.isSending
                        ? null
                        : () {
                            context
                                .read<SendCubit>()
                                .sendPlainText(_text.text.trim());
                            _text.clear();
                          },
                    child: const Text('发送'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 管理员群发 shell：Tab（群发 / 会话）。
class _AdminSendShell extends StatelessWidget {
  const _AdminSendShell();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('PScreen 控制'),
          bottom: const TabBar(
            tabs: <Widget>[
              Tab(text: '群发'),
              Tab(text: '会话'),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[
            _BroadcastTab(),
            ConversationListPage(),
          ],
        ),
      ),
    );
  }
}

/// 群发 tab。
class _BroadcastTab extends StatefulWidget {
  const _BroadcastTab();

  @override
  State<_BroadcastTab> createState() => _BroadcastTabState();
}

class _BroadcastTabState extends State<_BroadcastTab>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _text = TextEditingController();
  final TextEditingController _manual = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    getIt<TvDirectory>().loadFromAssets();
  }

  @override
  void dispose() {
    _text.dispose();
    _manual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return BlocBuilder<SendCubit, SendState>(
      builder: (BuildContext context, SendState state) {
        final TvDirectory dir = getIt<TvDirectory>();
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: <Widget>[
              TargetPicker(
                devices: dir.devices,
                selected: state.targets.toSet(),
                onToggle: context.read<SendCubit>().toggleTarget,
                onScan: () async {
                  final String? account = await Navigator.of(context).push<
                      String>(
                    MaterialPageRoute(builder: (_) => const QrScanPage()),
                  );
                  if (account != null && account.isNotEmpty) {
                    context.read<SendCubit>().toggleTarget(account);
                  }
                },
                manualController: _manual,
                onManualAdd: () {
                  final String v = _manual.text.trim();
                  if (v.isNotEmpty) {
                    context.read<SendCubit>().toggleTarget(v);
                    _manual.clear();
                  }
                },
              ),
              const Divider(),
              CommandPanel(
                onCommand: (String body) =>
                    context.read<SendCubit>().sendRaw(body),
              ),
              const Spacer(),
              _SendResultBanner(results: state.sendResults, directory: dir),
              TextField(
                controller: _text,
                decoration: const InputDecoration(hintText: '群发文本'),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: state.isSending
                      ? null
                      : () {
                          context
                              .read<SendCubit>()
                              .sendPlainText(_text.text.trim());
                          _text.clear();
                        },
                  child: Text(
                    state.isSending ? '发送中…' : '群发（${state.targets.length} 台）',
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 发送结果横幅：「已发 x/y 台」，失败目标可点重试。
class _SendResultBanner extends StatelessWidget {
  const _SendResultBanner({required this.results, required this.directory});

  final Map<String, bool> results;
  final TvDirectory directory;

  @override
  Widget build(BuildContext context) {
    if (results.isEmpty) return const SizedBox.shrink();
    final int total = results.length;
    final int success = results.values.where((bool v) => v).length;
    final List<String> failed =
        results.entries.where((e) => !e.value).map((e) => e.key).toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Text('已发 $success/$total 台'),
          if (failed.isNotEmpty) ...<Widget>[
            const SizedBox(width: 12),
            Text(
              '失败: ${failed.map(directory.nameOf).join(", ")}',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(
              onPressed: () => context.read<SendCubit>().retryFailed(failed),
              child: const Text('重试'),
            ),
          ],
        ],
      ),
    );
  }
}
```

`SendCubit` 补两个方法：

```dart
  /// 发送已构造好的信封字符串到所有目标（命令面板/快捷入口用）。
  Future<void> sendRaw(String body) => _sendToTargets(body);

  /// 重试指定失败目标。
  Future<void> retryFailed(List<String> accounts) async {
    // 复用最后一次 body：暂存在 state 里更干净；简化版——不重发 body，
    // 仅把失败目标勾选回来供用户手动重发。真正重发需保存 lastBody，
    // 加到 SendState: final String? lastBody; 在 _sendToTargets 里 emit。
  }
```

**必须实现完整重发**：`SendState` 增加 `lastBody` 字段（`String?`），`_sendToTargets` 里 `emit(state.copyWith(lastBody: body))`；`retryFailed` 实现为：

```dart
  Future<void> retryFailed(List<String> accounts) async {
    final String? body = state.lastBody;
    if (body == null) return;
    emit(state.copyWith(isSending: true));
    final Map<String, bool> results = Map<String, bool>.from(state.sendResults);
    for (final String account in accounts) {
      final bool ok = await nim.sendText(toAccount: account, text: body);
      results[account] = ok;
      emit(state.copyWith(sendResults: results));
    }
    emit(state.copyWith(isSending: false));
  }
```

- [ ] **Step 4: main.dart 导航接线**

登录/自动登录成功后 push `SendPage`（Task 2 已处理）；`SendPage` 内管理员 Tab 切换到会话页（Task 5 实现）。

- [ ] **Step 5: 验证 + Commit**

Run: `flutter analyze` / `flutter test`
Expected: No issues found / All tests passed

```bash
git add lib/features/send/presentation/ lib/features/send/application/ lib/main.dart
git commit -m "feat: send page with admin broadcast and family fork"
```

（`send_command` Cubit 测试需覆盖 `sendRaw`/`retryFailed`/`lastBody`——补充到 send_cubit_test.dart 后再 commit。）

---

### Task 5: 扫码页 + 会话列表 + 聊天页（管理员）

**Files:**
- Create: `lib/features/scan/presentation/qr_scan_page.dart`
- Create: `lib/features/admin/application/conversation_list_cubit.dart`
- Create: `lib/features/admin/presentation/conversation_list_page.dart`
- Create: `lib/features/admin/presentation/chat_page.dart`
- Test: `test/admin/conversation_list_cubit_test.dart`

- [ ] **Step 1: 扫码页**

```dart
// lib/features/scan/presentation/qr_scan_page.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// 扫码页：扫 TV 端「远程」行二维码，返回账号字符串。
class QrScanPage extends StatefulWidget {
  const QrScanPage({super.key});

  @override
  State<QrScanPage> createState() => _QrScanPageState();
}

class _QrScanPageState extends State<QrScanPage> {
  bool _done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('扫码')),
      body: MobileScanner(
        onDetect: (BarcodeCapture capture) {
          if (_done) return;
          final String? value = capture.barcodes.firstOrNull?.rawValue;
          if (value == null || value.isEmpty) return;
          _done = true;
          Navigator.of(context).pop(value);
        },
      ),
    );
  }
}
```

（`firstOrNull` 需 Dart 3 collection；若 analyze 报错改为 `capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue`。Android 权限：mobile_scanner 插件自动声明 camera 权限，无需额外 manifest。）

- [ ] **Step 2: 会话 Cubit（读 NIM 本地会话）**

先读 TV 端 NimManager / nim SDK 的 `conversation_service` API（`getConversationList` 等），照实际签名写：

```dart
// lib/features/admin/application/conversation_list_cubit.dart
import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:nim_core_v2_platform_interface/nim_core_v2_platform_interface.dart'
    // ignore: depend_on_referenced_packages
    hide Log;

part 'conversation_list_state.dart';

/// 会话条目（UI 用）。
class ConversationItem {
  const ConversationItem({
    required this.account,
    required this.title,
    required this.lastMessage,
    required this.unread,
  });

  final String account;
  final String title;
  final String lastMessage;
  final int unread;
}

/// 会话列表 Cubit：NIM 本地会话驱动，title 查 tvs.json 映射。
class ConversationListCubit extends Cubit<ConversationListState> {
  ConversationListCubit({
    required this.conversationService,
    required this.nameOf,
  }) : super(const ConversationListState()) {
    _sub = conversationService.onConversationChanged.listen((_) => refresh());
  }

  final NIMConversationService conversationService;
  final String Function(String account) nameOf;

  StreamSubscription<dynamic>? _sub;

  Future<void> refresh() async {
    final NIMResult<List<NIMConversation>> result =
        await conversationService.getConversationList();
    final List<NIMConversation> list = result.data ?? <NIMConversation>[];
    final List<ConversationItem> items = list
        .map((NIMConversation c) {
          final String? peer = c.conversationId; // P2P 会话 conversationId 即对方账号
          if (peer == null || peer.isEmpty) return null;
          return ConversationItem(
            account: peer,
            title: nameOf(peer),
            lastMessage: _previewOf(c),
            unread: c.unreadCount ?? 0,
          );
        })
        .whereType<ConversationItem>()
        .toList();
    emit(ConversationListState(items: items));
  }

  String _previewOf(NIMConversation c) {
    final NIMMessage? last = c.lastMessage;
    if (last == null) return '';
    final dynamic attachment = last.attachment;
    if (attachment is NIMTextAttachment) return attachment.text ?? '';
    return '[非文本消息]';
  }

  @override
  Future<void> close() {
    _sub?.cancel();
    return super.close();
  }
}
```

（`conversationId`/`unreadCount`/`onConversationChanged`/`getConversationList` 的真实字段以 SDK platform_interface 为准——先 Glob 搜 `D:\env\pub\pub-cache\hosted\pub.dev\nim_core_v2_platform_interface-10.9.91\lib` 下 conversation 相关文件，按真实模型调整。P2P 会话对方账号的提取字段若非 `conversationId`，用实际字段（常见 `conversationId` 去掉前缀，或 `recentContact` API 直接给 accountId）。）

- [ ] **Step 3: 写失败测试（ConversationListCubit）**

Fake conversationService 过重——抽一个 `ConversationSource` 抽象：

```dart
/// 会话数据源抽象（生产为 NIM SDK；测试 Fake）。
abstract class ConversationSource {
  Future<List<ConversationItem>> fetch();
  Stream<void> get onChange;
}
```

Cubit 改依赖 `ConversationSource`（实现类 `NimConversationSource` 包 SDK 调用），测试用内存 Fake：

```dart
// test/admin/conversation_list_cubit_test.dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_control/features/admin/application/conversation_list_cubit.dart';

class FakeSource implements ConversationSource {
  List<ConversationItem> data = <ConversationItem>[];
  final StreamController<void> _ctrl = StreamController<void>.broadcast();

  @override
  Future<List<ConversationItem>> fetch() async => data;

  @override
  Stream<void> get onChange => _ctrl.stream;

  void notify() => _ctrl.add(null);
}

void main() {
  test('refresh 发射列表', () async {
    final FakeSource source = FakeSource()
      ..data = <ConversationItem>[
        const ConversationItem(
            account: 'TV_001',
            title: '客厅电视',
            lastMessage: '你好',
            unread: 2),
      ];
    final ConversationListCubit cubit = ConversationListCubit(
      source: source,
      nameOf: (String a) => a == 'TV_001' ? '客厅电视' : a,
    );
    await cubit.refresh();
    expect(cubit.state.items.single.title, '客厅电视');
    expect(cubit.state.items.single.unread, 2);
    await cubit.close();
  });

  test('source 变更触发 refresh', () async {
    final FakeSource source = FakeSource();
    final ConversationListCubit cubit = ConversationListCubit(
      source: source,
      nameOf: (String a) => a,
    );
    source.data = <ConversationItem>[
      const ConversationItem(
          account: 'TV_002', title: 'TV_002', lastMessage: '', unread: 0),
    ];
    source.notify();
    await pumpEventQueue();
    expect(cubit.state.items.single.account, 'TV_002');
    await cubit.close();
  });
}
```

（`ConversationItem` 需要 `==`/const 构造——加 Equatable 或手写 ==。）

- [ ] **Step 4: 会话列表页 + 聊天页**

```dart
// lib/features/admin/presentation/conversation_list_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_control/app/di/injection.dart';
import 'package:pscreen_control/core/nim_client.dart';
import 'package:pscreen_control/features/admin/application/conversation_list_cubit.dart';
import 'package:pscreen_control/features/admin/presentation/chat_page.dart';
import 'package:pscreen_control/features/send/data/tv_directory.dart';

/// 会话列表（管理员 Tab 2）。
class ConversationListPage extends StatelessWidget {
  const ConversationListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ConversationListCubit>(
      create: (_) => ConversationListCubit(
        source: NimConversationSource(nim: getIt<NimClient>()),
        nameOf: getIt<TvDirectory>().nameOf,
      )..refresh(),
      child: const _ConversationListView(),
    );
  }
}

class _ConversationListView extends StatelessWidget {
  const _ConversationListView();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConversationListCubit, ConversationListState>(
      builder: (BuildContext context, ConversationListState state) {
        if (state.items.isEmpty) {
          return const Center(child: Text('暂无会话'));
        }
        return ListView.builder(
          itemCount: state.items.length,
          itemBuilder: (BuildContext context, int i) {
            final ConversationItem item = state.items[i];
            return ListTile(
              title: Text(item.title),
              subtitle: Text(
                item.lastMessage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: item.unread > 0
                  ? CircleAvatar(
                      radius: 12,
                      child: Text('${item.unread}',
                          style: const TextStyle(fontSize: 12)),
                    )
                  : null,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ChatPage(
                    account: item.account,
                    title: item.title,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
```

```dart
// lib/features/admin/presentation/chat_page.dart
import 'package:flutter/material.dart';
import 'package:pscreen_control/app/di/injection.dart';
import 'package:pscreen_control/core/nim_client.dart';
import 'package:pscreen_control/features/protocol/envelope_builder.dart';
import 'package:pscreen_control/features/send/data/tv_directory.dart';

/// 聊天页：消息流（NIM 本地）+ 底部输入（文本/命令）。
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.account, required this.title});

  final String account;
  final String title;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send(String body) async {
    if (body.isEmpty) return;
    final bool ok =
        await getIt<NimClient>().sendText(toAccount: widget.account, text: body);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? '已发送' : '发送失败')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: <Widget>[
          Expanded(
            child: StreamBuilder<List<ChatMessageItem>>(
              // 消息流：NimClient 暴露 per-account 历史+实时（见 Step 5）。
              stream: getIt<NimClient>().watchMessages(widget.account),
              builder: (BuildContext context, AsyncSnapshot snapshot) {
                final List<ChatMessageItem> items =
                    snapshot.data as List<ChatMessageItem>? ?? <ChatMessageItem>[];
                return ListView.builder(
                  reverse: true,
                  itemCount: items.length,
                  itemBuilder: (BuildContext context, int i) {
                    final ChatMessageItem m = items[i];
                    return Align(
                      alignment: m.isOutgoing
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(m.text),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          CommandPanel(
            onCommand: (String body) => _send(body),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _text,
                    decoration: const InputDecoration(hintText: '输入消息'),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: () {
                    _send(_text.text.trim());
                    _text.clear();
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 聊天消息条目（UI 用）。
class ChatMessageItem {
  const ChatMessageItem({required this.text, required this.isOutgoing});

  final String text;
  final bool isOutgoing;
}
```

`CommandPanel` import 补进 chat_page（`widgets/command_panel.dart`）。

- [ ] **Step 5: NimClient 补 watchMessages**

```dart
  /// 某账号的消息流：历史 + 实时（简化：SDK 本地消息库拉一页 + onReceiveMessages 合流）。
  Stream<List<ChatMessageItem>> watchMessages(String account) async* {
    // 1) 先拉历史（照 SDK message_service 历史接口，字段以实际为准）
    // 2) 再 yield 实时增量（onReceiveMessages 过滤 conversationId 匹配）
    // 简化版：仅实时流，历史后续再补——在报告已知限制中注明。
    yield const <ChatMessageItem>[];
    yield* NimCore.instance.messageService.onReceiveMessages
        .map((List<NIMMessage> messages) => messages
            .where((NIMMessage m) => true /* conversation 匹配 account */)
            .map((NIMMessage m) => ChatMessageItem(
                  text: m.attachment is NIMTextAttachment
                      ? (m.attachment as NIMTextAttachment).text ?? ''
                      : '[非文本]',
                  isOutgoing: false,
                ))
            .toList());
  }
```

**简化声明**：Task 5 只实现「实时消息流」；历史消息拉取放入已知限制（spec §8 补充），不在本计划范围。`watchMessages` 用真实 SDK 字段实现实时部分（conversation 过滤字段按 SDK 实际）。

- [ ] **Step 6: 跑测试 + analyze + Commit**

Run: `flutter test test/admin/conversation_list_cubit_test.dart`
Expected: PASS

Run: `flutter analyze` / `flutter test`
Expected: No issues found / All tests passed

```bash
git add lib/features/scan/ lib/features/admin/ lib/core/nim_client.dart test/admin/
git commit -m "feat: qr scan conversation list and chat page"
```

---

### Task 6: 断线提示 + 持久化最近目标 + 全量验证

**Files:**
- Modify: `lib/features/send/presentation/send_page.dart`（断线 SnackBar 监听）
- Modify: `lib/features/send/application/send_cubit.dart`（发送时持久化最近目标）
- Modify: `docs/superpowers/specs/2026-10-15-tv-message-remote-design.md`（已知限制补充）

- [ ] **Step 1: 断线监听**

`SendPage` 根（`SendPage` widget build 里，BlocProvider 外层包 StreamBuilder 或在 `_AdminSendShell`/`_FamilySendPage` initState 订阅）：

```dart
  StreamSubscription<dynamic>? _kickSub;

  @override
  void initState() {
    super.initState();
    _kickSub = getIt<NimClient>().onKickedOffline.listen((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('连接断开，正在重连…')),
      );
    });
  }

  @override
  void dispose() {
    _kickSub?.cancel();
    super.dispose();
  }
```

- [ ] **Step 2: 最近目标持久化**

`SendCubit` 构造读 `AppSettings.instance.selectedTvAccounts` 初始化 `state.targets`；`_sendToTargets` 成功循环后 `AppSettings.instance.setSelectedTvAccounts(state.targets)`。

- [ ] **Step 3: 已知限制补充**

spec §8 追加：

```markdown
- pscreen_control 聊天页仅显示实时消息流，历史消息本地拉取待后续
- pscreen_control 断线仅提示，自动重连依赖 SDK 默认行为，无手动重试按钮
```

- [ ] **Step 4: 全量验证**

Run: `flutter analyze`
Expected: No issues found

Run: `flutter test`
Expected: All tests passed（约 20 用例：信封 5 + 目录 3 + cubit 8 + 会话 2 + 其它）

- [ ] **Step 5: 真机手动验证清单**

1. 设置页登录管理员 `1000001` + token → 进入群发 Tab
2. 群发页勾选多台 + 发纯文本 → TV 端逐台弹浮层；结果「已发 2/2 台」
3. 命令面板音量+/静音 → TV 系统音量变化（无浮层）
4. 频道命令 → TV 切台
5. 扫码：TV 打开远程行编辑浮层 → 手机扫码 → 账号自动填入目标
6. 会话 Tab → 点开客厅电视 → 发文本 → TV 弹浮层；TV 上报（登录/切台/心跳）出现在聊天流
7. 家人账号登录 → 单页「发指令」，无预设列表，手动/扫码单台发送
8. 杀掉 App 重启 → 自动登录进入发送页；最近勾选目标还在
9. 断网 → 提示「连接断开」

- [ ] **Step 6: Commit**

```bash
git add lib/ docs/
git commit -m "feat: offline hint selected targets persistence"
```

---

## Self-Review 记录（计划作者已跑）

1. **Spec coverage:** §4.1 结构→Task 1-2；§4.2 分叉 UI→Task 4；§4.2 管理员群发/会话→Task 4/5；§4.2 家人单页→Task 4；§4.3 持久化/断线→Task 2/6；§3 协议（下行信封）→Task 3。
2. **Placeholder scan:** Task 2 NimClient init() 需照抄 TV 端（已注明先读）；Task 5 conversation SDK 字段需现场读（已注明 Glob 搜索）；Task 5 watchMessages 简化为仅实时流（已声明，不隐瞒）。
3. **Type consistency:** `SendCubit.sendRaw`/`retryFailed`/`lastBody` 在 Task 4 补充定义后被 Task 4 UI 使用；`ConversationSource` 抽象在 Task 5 Step 2 定义、Step 3 测试使用；`CommandPanel.onCommand` 参数统一为已构造信封字符串。


