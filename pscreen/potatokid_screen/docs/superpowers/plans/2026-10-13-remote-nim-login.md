# 远程云信账号登录 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在「我的」设置页第 13 行新增「远程」行，支持输入云信账号（固定 token 来自 .env），实现登出旧号→登录新号、持久化与开机自动登录，并以五态文案实时展示会话状态。

**Architecture:** 独立 BLoC feature（`lib/features/remote/` 四层，无 HTTP 层）：`RemoteLoginRepository`（抽象）/ `RemoteLoginRepositoryImpl`（封装 `NimManager` SDK + `AppSettings` 持久化 + `AppConfig.nimPassword`）/ `RemoteLoginBloc`（五态状态机，订阅 SDK 事件流）；DI 注册 `RemoteModule`，`main.dart` 启动派发自动登录；设置页 `ProfilePage` 第 13 行常态复用 `_SettingRow`，激活后行内 `TextField` 编辑。

**Tech Stack:** Flutter + flutter_bloc 9 + get_it + shared_preferences + flutter_dotenv + nim_core_v2 10.9.91（platform_interface 类型）+ mockito（手动 Mock extends Mock）+ flutter_test（fakeAsync/pumpEventQueue）。

**设计文档:** `docs/superpowers/specs/2026-10-13-remote-nim-login-design.md`

**工作目录:** 所有命令在 `pscreen/potatokid_screen/` 下执行（除非另有说明）。

**NIM 类型导入约定:** `NIMResult`/`NIMLoginStatus`/`NIMDataSyncDetail`/`NIMError`/`NIMKickedOfflineDetail` 均从 platform_interface 导出（`nim_core.dart` 不导出 `NIMError`），统一写法（与 `nim_manager.dart` 一致）：

```dart
// ignore: depend_on_referenced_packages
import 'package:nim_core_v2_platform_interface/nim_core_v2_platform_interface.dart' hide Log;
```

---

### Task 1: .env 与 AppConfig 读取 NIM_PASSWORD

**Files:**
- Modify: `.env`
- Modify: `lib/app/config/app_config.dart:8-11,47-71`

- [ ] **Step 1: 在 `.env` 末尾追加**

```bash

# 云信登录：各账号统一 token（控制台创建账号时设置的固定口令）
NIM_PASSWORD=12345678
```

- [ ] **Step 2: 在 `AppConfig` 静态字段区（`seniverseIpGeoHostB` 之后）新增**

```dart
  /// 网易云信登录 token（各账号统一，即「密码」）。
  static String nimPassword = '';
```

- [ ] **Step 3: 在 `AppConfig.initialize()` 中 `seniverseIpGeoHostB = _readString(...)` 之后新增**

```dart
    nimPassword = _readString('NIM_PASSWORD', nimPassword);
```

- [ ] **Step 4: 静态检查**

Run: `flutter analyze`
Expected: No issues found.

- [ ] **Step 5: Commit**

```bash
git add .env lib/app/config/app_config.dart
git commit -m "feat: nim password config from env"
```

---

### Task 2: AppSettings 持久化 nimAccount

**Files:**
- Modify: `lib/core/utils/app_settings.dart`
- Test: `test/core/utils/app_settings_test.dart`

- [ ] **Step 1: 写失败测试**

新建 `test/core/utils/app_settings_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:potatokid_screen/core/utils/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('nimAccount 默认空串，setNimAccount 内存与持久化同步更新', () async {
    final AppSettings settings = AppSettings.instance;
    await settings.clearAllPersisted();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await settings.ensureLoaded();
    expect(settings.nimAccount, isEmpty);

    await settings.setNimAccount('ABCD');
    expect(settings.nimAccount, 'ABCD');
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_nim_account_v1'), 'ABCD');
  });

  test('clearAllPersisted 复位 nimAccount', () async {
    final AppSettings settings = AppSettings.instance;
    await settings.clearAllPersisted();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await settings.ensureLoaded();
    await settings.setNimAccount('EFGH');

    await settings.clearAllPersisted();
    expect(settings.nimAccount, isEmpty);
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_nim_account_v1'), isNull);
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/core/utils/app_settings_test.dart`
Expected: 编译失败，报 `nimAccount`/`setNimAccount` 未定义。

- [ ] **Step 3: 实现 AppSettings 修改**

三处修改：

① 在 `_keyBackgroundPlayback` 之后新增键常量：

```dart
  static const String _keyNimAccount = 'app_nim_account_v1';
```

② 在 `_backgroundPlayback` 字段之后新增内存字段与 getter：

```dart
  /// 云信「远程」账号；**空串表示未设置**。
  String _nimAccount = '';
```

getter 区（`backgroundPlayback` getter 之后）：

```dart
  /// 云信「远程」账号：空串表示未设置。
  String get nimAccount => _nimAccount;
```

③ `_load()` 中 `// 后台播放` 读取之后新增：

```dart
      // 云信「远程」账号
      _nimAccount = prefs.getString(_keyNimAccount) ?? '';
```

④ `setBackgroundPlayback` 方法之后新增：

```dart
  /// 保存云信「远程」账号（空串表示清除）。
  Future<void> setNimAccount(String account) async {
    _nimAccount = account;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyNimAccount, account);
    } catch (_) {
      // 写入失败不影响运行。
    }
  }
```

⑤ `clearAllPersisted` 末尾复位区（`_backgroundPlayback = false;` 之后）新增：

```dart
    _nimAccount = '';
```

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/core/utils/app_settings_test.dart`
Expected: All tests passed.

- [ ] **Step 5: Commit**

```bash
git add lib/core/utils/app_settings.dart test/core/utils/app_settings_test.dart
git commit -m "feat: persist nim account in app settings"
```

---

### Task 3: NimManager 扩展 logout/getLoginUser/getLoginStatus 与事件流透传

**Files:**
- Modify: `lib/core/utils/nim_manager.dart`

本任务为 SDK 薄透传（依赖平台通道，无单测），以 `flutter analyze` 验证。

- [ ] **Step 1: 重命名现有四个事件处理方法（与新增流 getter 同名冲突）**

在 `nim_manager.dart` 内做全局替换（共 4 处方法定义 + startListen 中 4 处引用）：

| 旧名 | 新名 |
| --- | --- |
| `onLoginStatus` | `_handleLoginStatus` |
| `onLoginFailed` | `_handleLoginFailed` |
| `onKickedOffline` | `_handleKickedOffline` |
| `onLoginClientChanged` | `_handleLoginClientChanged` |

`startListen` 内同步改为：

```dart
      subsriptions.add(NimCore.instance.loginService.onLoginStatus.listen(_handleLoginStatus));
      subsriptions.add(NimCore.instance.loginService.onLoginFailed.listen(_handleLoginFailed));
      subsriptions.add(NimCore.instance.loginService.onKickedOffline.listen(_handleKickedOffline));
      subsriptions.add(NimCore.instance.loginService.onLoginClientChanged.listen(_handleLoginClientChanged));
```

四个方法体内的日志文案同步改为 `'[NimManager] _handleLoginStatus: ...'` 等（仅日志前缀，保持可辨识）。

- [ ] **Step 2: 在 `login` 方法之后新增**

```dart
  /// 登出当前账号。
  Future<NIMResult<void>> logout() => NimCore.instance.loginService.logout();

  /// 当前登录账号（未登录返回 null）。
  Future<NIMResult<String?>> getLoginUser() => NimCore.instance.loginService.getLoginUser();

  /// 当前登录状态。
  Future<NIMResult<NIMLoginStatus>> getLoginStatus() => NimCore.instance.loginService.getLoginStatus();

  /// 登录状态事件流（透传 SDK，供上层订阅）。
  Stream<NIMLoginStatus> get onLoginStatus => NimCore.instance.loginService.onLoginStatus;

  /// 数据同步事件流。
  Stream<NIMDataSyncDetail> get onDataSync => NimCore.instance.loginService.onDataSync;

  /// 登录失败事件流。
  Stream<NIMError> get onLoginFailed => NimCore.instance.loginService.onLoginFailed;

  /// 被踢下线事件流。
  Stream<NIMKickedOfflineDetail> get onKickedOffline => NimCore.instance.loginService.onKickedOffline;
```

- [ ] **Step 3: 静态检查**

Run: `flutter analyze`
Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
git add lib/core/utils/nim_manager.dart
git commit -m "feat: nim manager logout and event stream passthrough"
```

---

### Task 4: Domain 接口 RemoteLoginRepository 与异常

**Files:**
- Create: `lib/features/remote/domain/repositories/remote_login_repository.dart`

- [ ] **Step 1: 创建接口文件**

```dart
// ignore: depend_on_referenced_packages
import 'package:nim_core_v2_platform_interface/nim_core_v2_platform_interface.dart' hide Log;

/// 远程登录数据访问接口：账号持久化 + 云信 SDK 登录/登出 + 事件流。
abstract class RemoteLoginRepository {
  /// 已持久化的账号（空串表示未设置）。
  String get savedAccount;

  /// SDK 登录状态事件流。
  Stream<NIMLoginStatus> get onLoginStatus;

  /// SDK 数据同步事件流。
  Stream<NIMDataSyncDetail> get onDataSync;

  /// SDK 登录失败事件流。
  Stream<NIMError> get onLoginFailed;

  /// SDK 被踢下线事件流。
  Stream<NIMKickedOfflineDetail> get onKickedOffline;

  /// 启动自动登录：无账号静默返回；有账号直接登录（无需登出）。
  /// 失败抛异常（token 错误、SDK 未初始化等）。
  Future<void> autoLogin();

  /// 切换账号：先持久化新账号，再（有活跃会话时）登出，最后登录新账号。
  /// 失败抛 [RemoteLoginException] 或 SDK 异常。
  Future<void> switchAccount(String account);
}

/// 云信登录失败异常（服务端/SDK 拒绝，携带错误码与描述）。
class RemoteLoginException implements Exception {
  const RemoteLoginException(this.code, [this.message]);

  /// NIM 错误码。
  final int code;

  /// 错误描述。
  final String? message;

  @override
  String toString() => 'RemoteLoginException(code: $code, message: $message)';
}
```

- [ ] **Step 2: 静态检查**

Run: `flutter analyze`
Expected: No issues found.

- [ ] **Step 3: Commit**

```bash
git add lib/features/remote/domain/repositories/remote_login_repository.dart
git commit -m "feat: remote login repository interface"
```

---

### Task 5: RemoteLoginRepositoryImpl（TDD）

**Files:**
- Create: `lib/features/remote/data/repositories/remote_login_repository_impl.dart`
- Test: `test/features/remote/remote_login_repository_impl_test.dart`

- [ ] **Step 1: 写失败测试**

新建 `test/features/remote/remote_login_repository_impl_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
// ignore: depend_on_referenced_packages
import 'package:nim_core_v2_platform_interface/nim_core_v2_platform_interface.dart' hide Log;
import 'package:potatokid_screen/app/config/app_config.dart';
import 'package:potatokid_screen/core/utils/app_settings.dart';
import 'package:potatokid_screen/core/utils/nim_manager.dart';
import 'package:potatokid_screen/features/remote/data/repositories/remote_login_repository_impl.dart';
import 'package:potatokid_screen/features/remote/domain/repositories/remote_login_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// NimManager 手工 Fake：仅覆写用到的方法，其余走 Mock 的 noSuchMethod。
class FakeNimManager extends Mock implements NimManager {
  final List<String> calls = <String>[];

  /// 登录返回结果。
  NIMResult<void> loginResult = NIMResult<void>.success();

  /// getLoginStatus 返回结果。
  NIMResult<NIMLoginStatus> loginStatusResult =
      NIMResult<NIMLoginStatus>.success(data: NIMLoginStatus.loginStatusLogout);

  /// logout 抛异常开关（验证「登出失败忽略」）。
  bool throwOnLogout = false;

  @override
  Future<NIMResult<void>> login({required String accountId, required String token}) async {
    calls.add('login:$accountId:$token');
    return loginResult;
  }

  @override
  Future<NIMResult<void>> logout() async {
    calls.add('logout');
    if (throwOnLogout) {
      throw Exception('logout failed');
    }
    return NIMResult<void>.success();
  }

  @override
  Future<NIMResult<NIMLoginStatus>> getLoginStatus() async => loginStatusResult;
}

void main() {
  late FakeNimManager nim;
  late RemoteLoginRepositoryImpl repository;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AppSettings.instance.clearAllPersisted();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    nim = FakeNimManager();
    repository = RemoteLoginRepositoryImpl(nim: nim);
    await repository.ensureLoaded();
    AppConfig.nimPassword = '12345678';
  });

  test('autoLogin 无账号：静默返回，不调用登录', () async {
    await repository.autoLogin();
    expect(nim.calls, isEmpty);
  });

  test('autoLogin 有持久化账号：用固定 token 登录', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{'app_nim_account_v1': 'ABCD'});
    await AppSettings.instance.clearAllPersisted();
    SharedPreferences.setMockInitialValues(<String, Object>{'app_nim_account_v1': 'ABCD'});
    await repository.ensureLoaded();

    await repository.autoLogin();
    expect(nim.calls, <String>['login:ABCD:12345678']);
  });

  test('switchAccount 未登录：不登出，直接登录并持久化', () async {
    await repository.switchAccount('EFGH');
    expect(nim.calls, <String>['login:EFGH:12345678']);
    expect(repository.savedAccount, 'EFGH');
  });

  test('switchAccount 已登录：先登出再登录', () async {
    nim.loginStatusResult = NIMResult<NIMLoginStatus>.success(data: NIMLoginStatus.loginStatusLogined);

    await repository.switchAccount('EFGH');
    expect(nim.calls, <String>['logout', 'login:EFGH:12345678']);
  });

  test('switchAccount 登出失败：忽略并继续登录', () async {
    nim.loginStatusResult = NIMResult<NIMLoginStatus>.success(data: NIMLoginStatus.loginStatusLogined);
    nim.throwOnLogout = true;

    await repository.switchAccount('EFGH');
    expect(nim.calls, <String>['logout', 'login:EFGH:12345678']);
  });

  test('switchAccount 登录失败：抛 RemoteLoginException', () async {
    nim.loginResult = NIMResult<void>.failure(code: 302, message: 'token invalid');

    await expectLater(
      repository.switchAccount('BAD'),
      throwsA(isA<RemoteLoginException>()
          .having((RemoteLoginException e) => e.code, 'code', 302)),
    );
    // 失败也保留新账号配置（重启后仍重试）。
    expect(repository.savedAccount, 'BAD');
  });
}
```

- [ ] **Step 2: 运行确认失败**

Run: `flutter test test/features/remote/remote_login_repository_impl_test.dart`
Expected: 编译失败，`RemoteLoginRepositoryImpl` 未定义。

- [ ] **Step 3: 实现**

新建 `lib/features/remote/data/repositories/remote_login_repository_impl.dart`：

```dart
// ignore: depend_on_referenced_packages
import 'package:nim_core_v2_platform_interface/nim_core_v2_platform_interface.dart' hide Log;
import 'package:potatokid_screen/app/config/app_config.dart';
import 'package:potatokid_screen/core/utils/app_settings.dart';
import 'package:potatokid_screen/core/utils/nim_manager.dart';
import 'package:potatokid_screen/features/remote/domain/repositories/remote_login_repository.dart';

/// [RemoteLoginRepository] 实现：封装 NimManager（云信 SDK）与 AppSettings（账号持久化）。
class RemoteLoginRepositoryImpl implements RemoteLoginRepository {
  RemoteLoginRepositoryImpl({required NimManager nim}) : _nim = nim;

  final NimManager _nim;

  @override
  String get savedAccount => AppSettings.instance.nimAccount;

  @override
  Stream<NIMLoginStatus> get onLoginStatus => _nim.onLoginStatus;

  @override
  Stream<NIMDataSyncDetail> get onDataSync => _nim.onDataSync;

  @override
  Stream<NIMError> get onLoginFailed => _nim.onLoginFailed;

  @override
  Stream<NIMKickedOfflineDetail> get onKickedOffline => _nim.onKickedOffline;

  /// 确保 [AppSettings] 已加载（DI 注册时 await，保证 [savedAccount] 可信）。
  Future<void> ensureLoaded() => AppSettings.instance.ensureLoaded();

  @override
  Future<void> autoLogin() async {
    final String account = savedAccount;
    if (account.isEmpty) return;
    await _login(account);
  }

  @override
  Future<void> switchAccount(String account) async {
    // 先持久化：登录失败时重启后仍重试该账号。
    await AppSettings.instance.setNimAccount(account);
    final NIMResult<NIMLoginStatus> status = await _nim.getLoginStatus();
    final NIMLoginStatus? current = status.data;
    if (current == NIMLoginStatus.loginStatusLogined ||
        current == NIMLoginStatus.loginStatusLogining) {
      try {
        await _nim.logout();
      } catch (_) {
        // 登出失败忽略：随后的新登录会顶掉旧会话。
      }
    }
    await _login(account);
  }

  Future<void> _login(String account) async {
    final NIMResult<void> result =
        await _nim.login(accountId: account, token: AppConfig.nimPassword);
    if (!result.isSuccess) {
      throw RemoteLoginException(result.code, result.errorDetails);
    }
  }
}
```

- [ ] **Step 4: 运行确认通过**

Run: `flutter test test/features/remote/remote_login_repository_impl_test.dart`
Expected: All tests passed.

- [ ] **Step 5: Commit**

```bash
git add lib/features/remote/data/repositories/remote_login_repository_impl.dart test/features/remote/remote_login_repository_impl_test.dart
git commit -m "feat: remote login repository impl"
```

---

### Task 6: RemoteLoginBloc（TDD）

**Files:**
- Create: `lib/features/remote/application/bloc/remote_login_state.dart`
- Create: `lib/features/remote/application/bloc/remote_login_event.dart`
- Create: `lib/features/remote/application/bloc/remote_login_bloc.dart`
- Test: `test/features/remote/remote_login_bloc_test.dart`

- [ ] **Step 1: 定义 State**

新建 `lib/features/remote/application/bloc/remote_login_state.dart`：

```dart
import 'package:flutter/foundation.dart';

/// 远程登录状态（对应「远程」行五种展示文案）。
enum RemoteLoginStatus {
  /// 未设置账号。
  notConfigured,

  /// 正在登录。
  loggingIn,

  /// 登录成功、数据同步中。
  syncing,

  /// 登录成功且主数据同步完成。
  loggedIn,

  /// 登录失败 / 被踢下线。
  error,
}

/// 远程登录状态机的不可变 State。
@immutable
class RemoteLoginState {
  const RemoteLoginState({
    required this.account,
    required this.status,
    this.errorMessage,
  });

  /// 已配置的云信账号（空串表示未设置）。
  final String account;

  /// 当前登录状态。
  final RemoteLoginStatus status;

  /// error 态详情（日志/调试用）。
  final String? errorMessage;

  /// 由持久化账号构造初始态：空 → 未设置；非空 → 正在登录（autoLogin 随即派发）。
  factory RemoteLoginState.fromAccount(String account) => RemoteLoginState(
        account: account,
        status: account.isEmpty
            ? RemoteLoginStatus.notConfigured
            : RemoteLoginStatus.loggingIn,
      );

  RemoteLoginState copyWith({
    String? account,
    RemoteLoginStatus? status,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) =>
      RemoteLoginState(
        account: account ?? this.account,
        status: status ?? this.status,
        errorMessage:
            clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RemoteLoginState &&
          other.account == account &&
          other.status == status &&
          other.errorMessage == errorMessage);

  @override
  int get hashCode => Object.hash(account, status, errorMessage);
}
```

- [ ] **Step 2: 定义 Event**

新建 `lib/features/remote/application/bloc/remote_login_event.dart`：

```dart
// ignore: depend_on_referenced_packages
import 'package:nim_core_v2_platform_interface/nim_core_v2_platform_interface.dart' hide Log;

/// 远程登录事件。
abstract class RemoteLoginEvent {
  const RemoteLoginEvent();
}

/// 启动自动登录（main 在 NIM 初始化收尾后派发，无论初始化成败）。
class RemoteLoginAutoLogin extends RemoteLoginEvent {
  const RemoteLoginAutoLogin();
}

/// 用户提交账号（设置页输入完成）。
class RemoteLoginSubmit extends RemoteLoginEvent {
  const RemoteLoginSubmit(this.account);

  final String account;
}

/// SDK 登录状态变更。
class RemoteLoginStatusChanged extends RemoteLoginEvent {
  const RemoteLoginStatusChanged(this.status);

  final NIMLoginStatus status;
}

/// SDK 数据同步变更。
class RemoteLoginDataSyncChanged extends RemoteLoginEvent {
  const RemoteLoginDataSyncChanged(this.detail);

  final NIMDataSyncDetail detail;
}

/// SDK 登录失败。
class RemoteLoginLoginFailed extends RemoteLoginEvent {
  const RemoteLoginLoginFailed(this.error);

  final NIMError error;
}

/// SDK 被踢下线。
class RemoteLoginKickedOffline extends RemoteLoginEvent {
  const RemoteLoginKickedOffline(this.reasonDesc);

  final String reasonDesc;
}

/// 同步兜底：进入「同步数据」后超时未见主数据完成，视为已登录。
class RemoteLoginSyncFallbackElapsed extends RemoteLoginEvent {
  const RemoteLoginSyncFallbackElapsed();
}
```

- [ ] **Step 3: 写失败测试**

新建 `test/features/remote/remote_login_bloc_test.dart`：

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
// ignore: depend_on_referenced_packages
import 'package:nim_core_v2_platform_interface/nim_core_v2_platform_interface.dart' hide Log;
import 'package:potatokid_screen/features/remote/application/bloc/remote_login_bloc.dart';
import 'package:potatokid_screen/features/remote/application/bloc/remote_login_event.dart';
import 'package:potatokid_screen/features/remote/application/bloc/remote_login_state.dart';
import 'package:potatokid_screen/features/remote/domain/repositories/remote_login_repository.dart';

/// RemoteLoginRepository 手工 Fake：流可控、方法可配置。
class FakeRemoteLoginRepository extends Mock implements RemoteLoginRepository {
  FakeRemoteLoginRepository({this.account = ''});

  String account;
  Object? autoLoginError;
  Object? switchAccountError;
  final List<String> calls = <String>[];

  final StreamController<NIMLoginStatus> loginStatusController =
      StreamController<NIMLoginStatus>.broadcast();
  final StreamController<NIMDataSyncDetail> dataSyncController =
      StreamController<NIMDataSyncDetail>.broadcast();
  final StreamController<NIMError> loginFailedController =
      StreamController<NIMError>.broadcast();
  final StreamController<NIMKickedOfflineDetail> kickedController =
      StreamController<NIMKickedOfflineDetail>.broadcast();

  @override
  String get savedAccount => account;

  @override
  Stream<NIMLoginStatus> get onLoginStatus => loginStatusController.stream;

  @override
  Stream<NIMDataSyncDetail> get onDataSync => dataSyncController.stream;

  @override
  Stream<NIMError> get onLoginFailed => loginFailedController.stream;

  @override
  Stream<NIMKickedOfflineDetail> get onKickedOffline => kickedController.stream;

  @override
  Future<void> autoLogin() async {
    calls.add('autoLogin');
    if (autoLoginError != null) {
      throw autoLoginError!;
    }
  }

  @override
  Future<void> switchAccount(String account) async {
    calls.add('switchAccount:$account');
    this.account = account;
    if (switchAccountError != null) {
      throw switchAccountError!;
    }
  }

  void dispose() {
    loginStatusController.close();
    dataSyncController.close();
    loginFailedController.close();
    kickedController.close();
  }
}

void main() {
  late FakeRemoteLoginRepository repository;

  RemoteLoginBloc buildBloc() => RemoteLoginBloc(repository: repository);

  setUp(() {
    repository = FakeRemoteLoginRepository();
  });

  tearDown(() {
    repository.dispose();
  });

  test('初始无账号：未设置', () {
    final RemoteLoginBloc bloc = buildBloc();
    expect(bloc.state.status, RemoteLoginStatus.notConfigured);
    expect(bloc.state.account, isEmpty);
    bloc.close();
  });

  test('初始有账号：正在登录', () {
    repository.account = 'ABCD';
    final RemoteLoginBloc bloc = buildBloc();
    expect(bloc.state.status, RemoteLoginStatus.loggingIn);
    expect(bloc.state.account, 'ABCD');
    bloc.close();
  });

  test('AutoLogin 无账号：不调用 repository', () async {
    final RemoteLoginBloc bloc = buildBloc();
    bloc.add(const RemoteLoginAutoLogin());
    await pumpEventQueue();
    expect(repository.calls, isEmpty);
    await bloc.close();
  });

  test('AutoLogin 有账号：调用 repository，失败转 error', () async {
    repository.account = 'ABCD';
    repository.autoLoginError = Exception('sdk not initialized');
    final RemoteLoginBloc bloc = buildBloc();
    bloc.add(const RemoteLoginAutoLogin());
    await pumpEventQueue();
    expect(repository.calls, <String>['autoLogin']);
    expect(bloc.state.status, RemoteLoginStatus.error);
    await bloc.close();
  });

  test('Submit 空串：状态不变', () async {
    final RemoteLoginBloc bloc = buildBloc();
    bloc.add(const RemoteLoginSubmit('   '));
    await pumpEventQueue();
    expect(repository.calls, isEmpty);
    expect(bloc.state.status, RemoteLoginStatus.notConfigured);
    await bloc.close();
  });

  test('Submit 同账号且已登录：跳过', () async {
    repository.account = 'ABCD';
    final RemoteLoginBloc bloc = buildBloc();
    repository.loginStatusController.add(NIMLoginStatus.loginStatusLogined);
    await pumpEventQueue();
    expect(bloc.state.status, RemoteLoginStatus.syncing);

    bloc.add(const RemoteLoginSubmit('ABCD'));
    await pumpEventQueue();
    expect(repository.calls, isEmpty);
    await bloc.close();
  });

  test('Submit 同账号但 error：重新登录', () async {
    repository.account = 'ABCD';
    repository.autoLoginError = Exception('fail');
    final RemoteLoginBloc bloc = buildBloc();
    bloc.add(const RemoteLoginAutoLogin());
    await pumpEventQueue();
    expect(bloc.state.status, RemoteLoginStatus.error);

    bloc.add(const RemoteLoginSubmit('ABCD'));
    await pumpEventQueue();
    expect(repository.calls, <String>['autoLogin', 'switchAccount:ABCD']);
    await bloc.close();
  });

  test('Submit 新账号：进入正在登录并调用 switchAccount', () async {
    final RemoteLoginBloc bloc = buildBloc();
    bloc.add(const RemoteLoginSubmit(' NEW '));
    await pumpEventQueue();
    expect(bloc.state.account, 'NEW');
    expect(bloc.state.status, RemoteLoginStatus.loggingIn);
    expect(repository.calls, <String>['switchAccount:NEW']);
    await bloc.close();
  });

  test('Submit 失败：转 error 并保留账号', () async {
    repository.switchAccountError = RemoteLoginException(302, 'token invalid');
    final RemoteLoginBloc bloc = buildBloc();
    bloc.add(const RemoteLoginSubmit('BAD'));
    await pumpEventQueue();
    expect(bloc.state.status, RemoteLoginStatus.error);
    expect(bloc.state.account, 'BAD');
    await bloc.close();
  });

  test('登录成功：同步数据 → 主数据同步完成转已登录', () async {
    final RemoteLoginBloc bloc = buildBloc();
    repository.loginStatusController.add(NIMLoginStatus.loginStatusLogined);
    await pumpEventQueue();
    expect(bloc.state.status, RemoteLoginStatus.syncing);

    repository.dataSyncController.add(NIMDataSyncDetail(
      type: NIMDataSyncType.nimDataSyncMain,
      state: NIMDataSyncState.nimDataSyncStateCompleted,
    ));
    await pumpEventQueue();
    expect(bloc.state.status, RemoteLoginStatus.loggedIn);
    await bloc.close();
  });

  test('登录失败事件：转 error', () async {
    final RemoteLoginBloc bloc = buildBloc();
    repository.loginFailedController.add(NIMError(code: 302, desc: 'bad token'));
    await pumpEventQueue();
    expect(bloc.state.status, RemoteLoginStatus.error);
    await bloc.close();
  });

  test('被踢下线：转 error 并携带描述', () async {
    final RemoteLoginBloc bloc = buildBloc();
    repository.kickedController.add(NIMKickedOfflineDetail(reasonDesc: 'kicked by other'));
    await pumpEventQueue();
    expect(bloc.state.status, RemoteLoginStatus.error);
    expect(bloc.state.errorMessage, 'kicked by other');
    await bloc.close();
  });

  test('同步兜底：15 秒未见主数据完成转已登录', () {
    fakeAsync((FakeAsync async) {
      final RemoteLoginBloc bloc = buildBloc();
      repository.loginStatusController.add(NIMLoginStatus.loginStatusLogined);
      async.flushMicrotasks();
      expect(bloc.state.status, RemoteLoginStatus.syncing);

      async.elapse(const Duration(seconds: 15));
      async.flushMicrotasks();
      expect(bloc.state.status, RemoteLoginStatus.loggedIn);
      bloc.close();
      async.flushMicrotasks();
    });
  });
}
```

- [ ] **Step 4: 运行确认失败**

Run: `flutter test test/features/remote/remote_login_bloc_test.dart`
Expected: 编译失败，`RemoteLoginBloc` 未定义。

- [ ] **Step 5: 实现 Bloc**

新建 `lib/features/remote/application/bloc/remote_login_bloc.dart`：

```dart
import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
// ignore: depend_on_referenced_packages
import 'package:nim_core_v2_platform_interface/nim_core_v2_platform_interface.dart' hide Log;
import 'package:potatokid_screen/features/remote/application/bloc/remote_login_event.dart';
import 'package:potatokid_screen/features/remote/application/bloc/remote_login_state.dart';
import 'package:potatokid_screen/features/remote/domain/repositories/remote_login_repository.dart';

/// 远程云信登录状态机。
///
/// 展示流转：未设置 → 正在登录 → 同步数据 → 已登录；登录失败/被踢 → 登录异常。
/// - 提交同账号且会话正常（正在登录/同步数据/已登录）时跳过；
/// - error 态下同账号可重新提交触发重试；
/// - 进入「同步数据」后 15 秒未见主数据同步完成则兜底转「已登录」。
class RemoteLoginBloc extends Bloc<RemoteLoginEvent, RemoteLoginState> {
  RemoteLoginBloc({required RemoteLoginRepository repository})
      : _repository = repository,
        super(RemoteLoginState.fromAccount(repository.savedAccount)) {
    on<RemoteLoginAutoLogin>(_onAutoLogin);
    on<RemoteLoginSubmit>(_onSubmit);
    on<RemoteLoginStatusChanged>(_onStatusChanged);
    on<RemoteLoginDataSyncChanged>(_onDataSyncChanged);
    on<RemoteLoginLoginFailed>(_onLoginFailed);
    on<RemoteLoginKickedOffline>(_onKickedOffline);
    on<RemoteLoginSyncFallbackElapsed>(_onSyncFallbackElapsed);
    _subscriptions.addAll(<StreamSubscription<Object?>>[
      repository.onLoginStatus.listen(
        (NIMLoginStatus e) => add(RemoteLoginStatusChanged(e)),
      ),
      repository.onDataSync.listen(
        (NIMDataSyncDetail e) => add(RemoteLoginDataSyncChanged(e)),
      ),
      repository.onLoginFailed.listen(
        (NIMError e) => add(RemoteLoginLoginFailed(e)),
      ),
      repository.onKickedOffline.listen(
        (NIMKickedOfflineDetail e) =>
            add(RemoteLoginKickedOffline(e.reasonDesc ?? '')),
      ),
    ]);
  }

  final RemoteLoginRepository _repository;
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];
  Timer? _syncFallbackTimer;

  /// 同步兜底时长：登录成功后超过该时长未见主数据同步完成即视为已登录。
  static const Duration _syncFallbackDelay = Duration(seconds: 15);

  Future<void> _onAutoLogin(
    RemoteLoginAutoLogin event,
    Emitter<RemoteLoginState> emit,
  ) async {
    if (state.account.isEmpty) return;
    emit(state.copyWith(
      status: RemoteLoginStatus.loggingIn,
      clearErrorMessage: true,
    ));
    try {
      await _repository.autoLogin();
    } catch (e) {
      emit(state.copyWith(status: RemoteLoginStatus.error, errorMessage: '$e'));
    }
  }

  Future<void> _onSubmit(
    RemoteLoginSubmit event,
    Emitter<RemoteLoginState> emit,
  ) async {
    final String account = event.account.trim();
    if (account.isEmpty) return;
    final bool sessionActive = state.status == RemoteLoginStatus.loggingIn ||
        state.status == RemoteLoginStatus.syncing ||
        state.status == RemoteLoginStatus.loggedIn;
    if (account == state.account && sessionActive) return;
    _syncFallbackTimer?.cancel();
    emit(state.copyWith(
      account: account,
      status: RemoteLoginStatus.loggingIn,
      clearErrorMessage: true,
    ));
    try {
      await _repository.switchAccount(account);
    } catch (e) {
      emit(state.copyWith(status: RemoteLoginStatus.error, errorMessage: '$e'));
    }
  }

  void _onStatusChanged(
    RemoteLoginStatusChanged event,
    Emitter<RemoteLoginState> emit,
  ) {
    switch (event.status) {
      case NIMLoginStatus.loginStatusLogining:
        if (state.status != RemoteLoginStatus.notConfigured) {
          emit(state.copyWith(status: RemoteLoginStatus.loggingIn));
        }
        break;
      case NIMLoginStatus.loginStatusLogined:
        emit(state.copyWith(status: RemoteLoginStatus.syncing));
        _startSyncFallbackTimer();
        break;
      case NIMLoginStatus.loginStatusLogout:
      case NIMLoginStatus.loginStatusUnlogin:
        // 登出/未登录事件不直接驱动展示：状态由主动提交、失败与被踢事件决定。
        break;
    }
  }

  void _onDataSyncChanged(
    RemoteLoginDataSyncChanged event,
    Emitter<RemoteLoginState> emit,
  ) {
    final NIMDataSyncDetail detail = event.detail;
    if (detail.type == NIMDataSyncType.nimDataSyncMain &&
        detail.state == NIMDataSyncState.nimDataSyncStateCompleted) {
      _syncFallbackTimer?.cancel();
      emit(state.copyWith(status: RemoteLoginStatus.loggedIn));
    }
  }

  void _onLoginFailed(
    RemoteLoginLoginFailed event,
    Emitter<RemoteLoginState> emit,
  ) {
    _syncFallbackTimer?.cancel();
    emit(state.copyWith(
      status: RemoteLoginStatus.error,
      errorMessage: 'code=${event.error.code} desc=${event.error.desc}',
    ));
  }

  void _onKickedOffline(
    RemoteLoginKickedOffline event,
    Emitter<RemoteLoginState> emit,
  ) {
    _syncFallbackTimer?.cancel();
    emit(state.copyWith(
      status: RemoteLoginStatus.error,
      errorMessage: event.reasonDesc,
    ));
  }

  void _onSyncFallbackElapsed(
    RemoteLoginSyncFallbackElapsed event,
    Emitter<RemoteLoginState> emit,
  ) {
    if (state.status == RemoteLoginStatus.syncing) {
      emit(state.copyWith(status: RemoteLoginStatus.loggedIn));
    }
  }

  void _startSyncFallbackTimer() {
    _syncFallbackTimer?.cancel();
    _syncFallbackTimer = Timer(_syncFallbackDelay, () {
      if (!isClosed) add(const RemoteLoginSyncFallbackElapsed());
    });
  }

  @override
  Future<void> close() async {
    _syncFallbackTimer?.cancel();
    for (final StreamSubscription<Object?> subscription in _subscriptions) {
      await subscription.cancel();
    }
    return super.close();
  }
}
```

- [ ] **Step 6: 运行确认通过**

Run: `flutter test test/features/remote/remote_login_bloc_test.dart`
Expected: All tests passed（13 个用例）。

- [ ] **Step 7: Commit**

```bash
git add lib/features/remote/application/bloc/ test/features/remote/remote_login_bloc_test.dart
git commit -m "feat: remote login bloc state machine"
```

---

### Task 7: DI 注册 RemoteModule

**Files:**
- Create: `lib/core/di/modules/remote_module.dart`
- Modify: `lib/core/di/injection.dart`

- [ ] **Step 1: 创建 Module**

新建 `lib/core/di/modules/remote_module.dart`：

```dart
import 'package:potatokid_screen/core/di/get_it.dart';
import 'package:potatokid_screen/core/utils/nim_manager.dart';
import 'package:potatokid_screen/features/remote/application/bloc/remote_login_bloc.dart';
import 'package:potatokid_screen/features/remote/data/repositories/remote_login_repository_impl.dart';
import 'package:potatokid_screen/features/remote/domain/repositories/remote_login_repository.dart';

/// 远程登录模块：云信账号登录（Repository + Bloc）。
///
/// 依赖 CoreModule 的 [NimManager]，必须在其之后注册；
/// 注册时先 await 账号持久化加载，保证 Bloc 初始 State 读到已存账号。
class RemoteModule {
  const RemoteModule._();

  static Future<void> register() async {
    final RemoteLoginRepositoryImpl repository =
        RemoteLoginRepositoryImpl(nim: getIt<NimManager>());
    await repository.ensureLoaded();
    getIt.registerLazySingleton<RemoteLoginRepository>(() => repository);
    getIt.registerLazySingleton<RemoteLoginBloc>(
      () => RemoteLoginBloc(repository: getIt<RemoteLoginRepository>()),
    );
  }

  static Future<void> unregister() async {
    await getIt.unregister<RemoteLoginBloc>();
    await getIt.unregister<RemoteLoginRepository>();
  }
}
```

- [ ] **Step 2: 挂载到 Injection**

`lib/core/di/injection.dart` 两处修改：

① import 区（`router_module` import 之后）新增：

```dart
import 'package:potatokid_screen/core/di/modules/remote_module.dart';
```

② `init()` 中 `await CoreModule.register();` 之后新增：

```dart
    await RemoteModule.register();
```

③ `reset()` 中 `await RouterModule.unregister();` 之前新增：

```dart
    await RemoteModule.unregister();
```

- [ ] **Step 3: 静态检查**

Run: `flutter analyze`
Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
git add lib/core/di/modules/remote_module.dart lib/core/di/injection.dart
git commit -m "feat: register remote module in DI"
```

---

### Task 8: main.dart 接线（自动登录 + 全局 BlocProvider）

**Files:**
- Modify: `lib/main.dart`

- [ ] **Step 1: 新增 import**（`iptv_event` import 之后）：

```dart
import 'package:potatokid_screen/features/remote/application/bloc/remote_login_bloc.dart';
import 'package:potatokid_screen/features/remote/application/bloc/remote_login_event.dart';
```

- [ ] **Step 2: 替换 NIM 初始化段**

将现有：

```dart
      // 4.1 初始化网易云信 NIM（DI 单例；不阻塞启动，失败仅记录日志）
      unawaited(
        Injection.get<NimManager>()
            .init(appKey: AppConstants.nimAppKey)
            .then((_) {
              Injection.get<NimManager>().startListen();
            })
            .catchError((Object e, StackTrace s) {
              Log.error('NIM initialize failed: $e');
            }),
      );
```

替换为：

```dart
      // 4.1 初始化网易云信 NIM（DI 单例；不阻塞启动，失败仅记录日志）。
      //     初始化收尾后（无论成败）派发自动登录：初始化失败时 login 会抛异常，
      //     由 RemoteLoginBloc 捕获转「登录异常」态。
      unawaited(
        Injection.get<NimManager>()
            .init(appKey: AppConstants.nimAppKey)
            .then((_) {
              Injection.get<NimManager>().startListen();
            })
            .whenComplete(() {
              Injection.get<RemoteLoginBloc>()
                  .add(const RemoteLoginAutoLogin());
            })
            .catchError((Object e, StackTrace s) {
              Log.error('NIM initialize failed: $e');
            }),
      );
```

- [ ] **Step 3: MultiBlocProvider 新增**

在 `BlocProvider<WeatherBloc>(...)` 之后新增：

```dart
              // 远程云信登录状态机：全局共享（设置页「远程」行消费），
              // 自动登录已在 4.1 派发，这里只负责 provide。
              BlocProvider<RemoteLoginBloc>(
                create: (_) => Injection.get<RemoteLoginBloc>(),
              ),
```

- [ ] **Step 4: 静态检查**

Run: `flutter analyze`
Expected: No issues found.

- [ ] **Step 5: Commit**

```bash
git add lib/main.dart
git commit -m "feat: wire remote login auto startup"
```

---

### Task 9: 四语言翻译键

**Files:**
- Modify: `assets/translations/zh-CN.json`
- Modify: `assets/translations/zh-TW.json`
- Modify: `assets/translations/en-US.json`
- Modify: `assets/translations/ja-JP.json`

- [ ] **Step 1: zh-CN.json 在 `"settings_reset_ok"` 行之后插入**

```json
  "settings_remote": "远程",
  "remote_not_set": "未设置",
  "remote_logging_in": "正在登录",
  "remote_syncing": "同步数据",
  "remote_logged_in": "已登录",
  "remote_error": "登录异常",
  "remote_input_hint": "输入云信账号",
```

- [ ] **Step 2: zh-TW.json 同位置插入**

```json
  "settings_remote": "遠程",
  "remote_not_set": "未設定",
  "remote_logging_in": "正在登入",
  "remote_syncing": "同步資料",
  "remote_logged_in": "已登入",
  "remote_error": "登入異常",
  "remote_input_hint": "輸入雲信帳號",
```

- [ ] **Step 3: en-US.json 同位置插入**

```json
  "settings_remote": "Remote",
  "remote_not_set": "Not set",
  "remote_logging_in": "Logging in",
  "remote_syncing": "Syncing data",
  "remote_logged_in": "Logged in",
  "remote_error": "Login error",
  "remote_input_hint": "Enter Yunxin account",
```

- [ ] **Step 4: ja-JP.json 同位置插入**

```json
  "settings_remote": "リモート",
  "remote_not_set": "未設定",
  "remote_logging_in": "ログイン中",
  "remote_syncing": "データ同期中",
  "remote_logged_in": "ログイン済み",
  "remote_error": "ログインエラー",
  "remote_input_hint": "雲信アカウントを入力",
```

- [ ] **Step 5: 校验 JSON 合法**

Run: `powershell -Command "foreach ($f in 'zh-CN','zh-TW','en-US','ja-JP') { Get-Content -Raw \"assets/translations/$f.json\" | ConvertFrom-Json | Out-Null; Write-Output \"$f ok\" }"`
Expected: 四行 `ok`（任一文件语法错误会直接抛异常）。

- [ ] **Step 6: Commit**

```bash
git add assets/translations/
git commit -m "feat: remote login translations"
```

---

### Task 10: ProfileFocusController 行数 16 → 17

**Files:**
- Modify: `lib/features/profile/application/profile_focus_controller.dart`

- [ ] **Step 1: 修改 rowCount**

```dart
  /// 正文列表行数。
  static const int rowCount = 17;
```

- [ ] **Step 2: 更新两处文档注释中的行号列表**

类文档注释与 `row` getter 注释里的列表统一改为：

`0=主题 / 1=语言 / 2=悬浮遥控器 / 3=启用硬解 / 4=画面 / 5=天气城市 / 6=定时关闭 / 7=后台播放 / 8=刷新频道 / 9=清理失效源 / 10=复制失效源 / 11=代理重试 / 12=重置 / 13=远程 / 14=版本 / 15=天气数据来源 / 16=免责声明`

- [ ] **Step 3: 静态检查**

Run: `flutter analyze`
Expected: No issues found.

- [ ] **Step 4: Commit**

```bash
git add lib/features/profile/application/profile_focus_controller.dart
git commit -m "feat: profile row count for remote login row"
```

---

### Task 11: ProfilePage「远程」行 UI（常态 + 行内编辑）

**Files:**
- Modify: `lib/features/profile/presentation/pages/profile_page.dart`

- [ ] **Step 1: 新增 import**（`weather_event` import 之后、`confirm_dialog` 之前）：

```dart
import 'package:potatokid_screen/features/remote/application/bloc/remote_login_bloc.dart';
import 'package:potatokid_screen/features/remote/application/bloc/remote_login_event.dart';
import 'package:potatokid_screen/features/remote/application/bloc/remote_login_state.dart';
```

- [ ] **Step 2: 新增行号常量**（`_resetRow` 常量之后）：

```dart
  /// 「远程」行（云信账号登录：常态展示账号+状态，激活后行内输入框）的序号。
  static const int _remoteRow = 13;
```

- [ ] **Step 3: 新增编辑态字段**（`_resetting` 字段之后）：

```dart
  /// 「远程」行是否处于输入编辑态。
  bool _editingRemote = false;

  /// 「远程」行输入框的控制器与焦点节点。
  final TextEditingController _remoteInputController =
      TextEditingController();
  final FocusNode _remoteInputFocusNode = FocusNode();
```

- [ ] **Step 4: dispose 补充释放**（`_copyMsg.dispose();` 之后）：

```dart
    _remoteInputController.dispose();
    _remoteInputFocusNode.dispose();
```

- [ ] **Step 5: 焦点变化时取消编辑**

`_onFocusChanged` 方法开头（`final ProfileFocusController c = ...` 之后、`if (!c.focused) return;` 之前）插入：

```dart
    // 焦点离开「远程」行时取消输入编辑态（不提交）。
    if (_editingRemote && c.row != _remoteRow) {
      _endRemoteEdit();
    }
```

- [ ] **Step 6: OK 激活支持**

`_onActivateRow` 中 `if (row == _resetRow ...)` 之后新增：

```dart
    if (row == _remoteRow && mounted) _beginRemoteEdit();
```

- [ ] **Step 7: 左右键打开编辑**

`_stepRow` 的 switch 中 `case _resetRow` 分支之后新增：

```dart
      case _remoteRow: // 远程：左/右键打开行内输入框
        _beginRemoteEdit();
        break;
```

- [ ] **Step 8: 列表插入行**

在 build 的 ListView 中，找到 reset 与 version 之间已有的间距行：

```dart
              KeyedSubtree(
                key: _rowKeys[_resetRow],
                child: _buildResetRow(inContent, c),
              ),
              const SizedBox(height: 12),
              KeyedSubtree(
                key: _rowKeys[_versionRow],
                child: _buildVersionRow(inContent, c),
              ),
```

将其替换为（保持相邻行间一个 12 间距）：

```dart
              KeyedSubtree(
                key: _rowKeys[_resetRow],
                child: _buildResetRow(inContent, c),
              ),
              const SizedBox(height: 12),
              KeyedSubtree(
                key: _rowKeys[_remoteRow],
                child: _buildRemoteLoginRow(inContent, c),
              ),
              const SizedBox(height: 12),
              KeyedSubtree(
                key: _rowKeys[_versionRow],
                child: _buildVersionRow(inContent, c),
              ),
```

- [ ] **Step 9: 新增行构建与编辑方法**

在 `_buildResetRow` 方法之后新增：

```dart
  /// 「远程」行：常态展示账号与登录状态（`ABCD 正在登录`），点击 `>` / OK /
  /// 左右键进入行内输入；编辑态替换为输入框（见 [_buildRemoteEditRow]）。
  Widget _buildRemoteLoginRow(bool inContent, ProfileFocusController c) {
    return BlocBuilder<RemoteLoginBloc, RemoteLoginState>(
      builder: (context, state) {
        if (_editingRemote) {
          return _buildRemoteEditRow();
        }
        final String value =
            state.status == RemoteLoginStatus.notConfigured
                ? 'remote_not_set'.tr()
                : '${state.account} ${_remoteStatusLabel(state.status)}';
        return _SettingRow(
          highlighted: inContent && c.row == _remoteRow,
          label: 'settings_remote'.tr(),
          value: value,
          canStepLeft: false,
          canStepRight: true,
          onTap: () {
            c.select(_remoteRow);
            _beginRemoteEdit();
          },
          onStepLeft: () => c.select(_remoteRow),
          onStepRight: () {
            c.select(_remoteRow);
            _beginRemoteEdit();
          },
        );
      },
    );
  }

  /// 「远程」行的登录状态文案。
  String _remoteStatusLabel(RemoteLoginStatus status) {
    switch (status) {
      case RemoteLoginStatus.notConfigured:
        return 'remote_not_set'.tr();
      case RemoteLoginStatus.loggingIn:
        return 'remote_logging_in'.tr();
      case RemoteLoginStatus.syncing:
        return 'remote_syncing'.tr();
      case RemoteLoginStatus.loggedIn:
        return 'remote_logged_in'.tr();
      case RemoteLoginStatus.error:
        return 'remote_error'.tr();
    }
  }

  /// 进入「远程」行输入编辑态：预填当前账号，下一帧聚焦弹出输入法。
  void _beginRemoteEdit() {
    if (_editingRemote || !mounted) return;
    _remoteInputController.text =
        context.read<RemoteLoginBloc>().state.account;
    _editingRemote = true;
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _remoteInputFocusNode.requestFocus();
    });
  }

  /// 提交输入：空串等价取消；有值则 trim 后派发 [RemoteLoginSubmit]。
  void _submitRemoteEdit() {
    if (!_editingRemote) return;
    final String account = _remoteInputController.text.trim();
    _endRemoteEdit();
    if (account.isEmpty || !mounted) return;
    context.read<RemoteLoginBloc>().add(RemoteLoginSubmit(account));
  }

  /// 退出输入编辑态（取消，不提交）。
  void _endRemoteEdit() {
    if (!_editingRemote) return;
    _editingRemote = false;
    _remoteInputFocusNode.unfocus();
    if (mounted) setState(() {});
  }

  /// 「远程」行编辑态：行内输入框 + ✕ 取消 + ✓ 提交。
  Widget _buildRemoteEditRow() {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextTheme textTheme = Theme.of(context).textTheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary, width: 2),
      ),
      child: Row(
        children: <Widget>[
          Text(
            'settings_remote'.tr(),
            style: textTheme.titleMedium?.copyWith(color: scheme.onSurface),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: TextField(
              controller: _remoteInputController,
              focusNode: _remoteInputFocusNode,
              textInputAction: TextInputAction.done,
              textCapitalization: TextCapitalization.none,
              autocorrect: false,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: scheme.primary,
              ),
              decoration: InputDecoration(
                hintText: 'remote_input_hint'.tr(),
                isDense: true,
                border: InputBorder.none,
              ),
              onSubmitted: (_) => _submitRemoteEdit(),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.close, color: scheme.onSurfaceVariant),
            onPressed: _endRemoteEdit,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.check, color: scheme.primary),
            onPressed: _submitRemoteEdit,
          ),
        ],
      ),
    );
  }
```

- [ ] **Step 10: 静态检查**

Run: `flutter analyze`
Expected: No issues found.

- [ ] **Step 11: Commit**

```bash
git add lib/features/profile/presentation/pages/profile_page.dart
git commit -m "feat: profile remote login row with inline editor"
```

---

### Task 12: 全量验证

**Files:** 无新增修改（仅验证；发现问题则修复后提交）

- [ ] **Step 1: 全量静态检查**

Run: `flutter analyze`
Expected: No issues found.

- [ ] **Step 2: 全量测试**

Run: `flutter test`
Expected: All tests passed（含既有 channel matcher / HomeState 测试与新增 remote 测试）。

- [ ] **Step 3: 若 Step 1/2 有修复则提交**

```bash
git add -A
git commit -m "fix: remote login review fixes"
```

（无问题则跳过提交。）
