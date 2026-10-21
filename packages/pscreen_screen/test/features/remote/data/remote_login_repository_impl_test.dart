import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
// ignore: depend_on_referenced_packages
import 'package:nim_core_v2_platform_interface/nim_core_v2_platform_interface.dart' hide Log;
import 'package:pscreen_screen/app/config/app_config.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';
import 'package:pscreen_screen/core/utils/nim_manager.dart';
import 'package:pscreen_screen/features/remote/data/repositories/remote_login_repository_impl.dart';
import 'package:pscreen_screen/features/remote/domain/repositories/remote_login_repository.dart';
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

  /// logout 返回结果。
  NIMResult<void> logoutResult = NIMResult<void>.success();

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
    return logoutResult;
  }

  @override
  Future<NIMResult<NIMLoginStatus>> getLoginStatus() async => loginStatusResult;
}

void main() {
  late FakeNimManager nim;
  late RemoteLoginRepositoryImpl repository;

  setUp(() async {
    // 先清空（同时使 singleton 加载缓存失效），再注入 mock 存储，最后重新加载。
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

  test('switchAccount 正在登录：同样先登出再登录', () async {
    nim.loginStatusResult = NIMResult<NIMLoginStatus>.success(data: NIMLoginStatus.loginStatusLogining);

    await repository.switchAccount('EFGH');
    expect(nim.calls, <String>['logout', 'login:EFGH:12345678']);
  });

  test('switchAccount 状态查询失败：跳过登出直接登录', () async {
    nim.loginStatusResult = NIMResult<NIMLoginStatus>.failure(code: -1, message: 'query failed');

    await repository.switchAccount('EFGH');
    expect(nim.calls, <String>['login:EFGH:12345678']);
  });

  test('switchAccount 登出失败：忽略并继续登录', () async {
    nim.loginStatusResult = NIMResult<NIMLoginStatus>.success(data: NIMLoginStatus.loginStatusLogined);
    nim.throwOnLogout = true;

    await repository.switchAccount('EFGH');
    expect(nim.calls, <String>['logout', 'login:EFGH:12345678']);
  });

  test('switchAccount 登出返回失败结果：忽略并继续登录', () async {
    nim.loginStatusResult = NIMResult<NIMLoginStatus>.success(data: NIMLoginStatus.loginStatusLogined);
    nim.logoutResult = NIMResult<void>.failure(code: 500, message: 'logout rejected');

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
