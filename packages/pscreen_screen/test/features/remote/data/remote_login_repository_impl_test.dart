import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';
import 'package:pscreen_screen/core/utils/client_info.dart';
import 'package:pscreen_screen/core/utils/device_credentials.dart';
import 'package:pscreen_screen/features/remote/data/repositories/remote_login_repository_impl.dart';
import 'package:pscreen_screen/features/remote/domain/repositories/remote_login_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// RealtimeChannel 手工 Fake：记录调用、可控失败。
class FakeRealtimeChannel implements RealtimeChannel {
  final List<String> calls = <String>[];

  /// connect 抛出的异常（null 表示成功）。
  RealtimeException? connectError;

  final StreamController<RealtimeConnectionState> stateController =
      StreamController<RealtimeConnectionState>.broadcast();
  final StreamController<String> errorController =
      StreamController<String>.broadcast();

  @override
  Stream<RealtimeConnectionState> get connectionState =>
      stateController.stream;

  @override
  Stream<String> get fatalErrors => errorController.stream;

  @override
  Future<void> connect({
    required String account,
    required String token,
    String deviceId = '',
    String role = 'tv',
    String? name,
    String app = '',
    String version = '',
    String build = '',
  }) async {
    calls.add('connect:$account:$token:$deviceId:$role');
    lastApp = app;
    lastVersion = version;
    lastBuild = build;
    final RealtimeException? error = connectError;
    if (error != null) throw error;
  }

  /// 最近一次 connect 上报的客户端标识（包名/版本/构建号）。
  String lastApp = '';
  String lastVersion = '';
  String lastBuild = '';

  @override
  Future<void> disconnect() async => calls.add('disconnect');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<void> dispose() async {
    await stateController.close();
    await errorController.close();
  }
}

void main() {
  late FakeRealtimeChannel channel;
  late RemoteLoginRepositoryImpl repository;
  late List<bool> httpLogins;

  /// 测试环境的固定设备号（`app_device_id_fallback_v1`，16 位 hex 无连字符）。
  const String testDeviceId = 'abcdef0123456789';

  setUp(() async {
    // 先清空（同时使 singleton 加载缓存失效），再注入 mock 存储，最后重新加载。
    // 设备号 fallback 固定，保证 DeviceCredentials.account()/deviceId() 结果确定。
    await AppSettings.instance.clearAllPersisted();
    SharedPreferences.setMockInitialValues(<String, Object>{
      'app_device_id_fallback_v1': testDeviceId,
    });
    channel = FakeRealtimeChannel();
    httpLogins = <bool>[];
    repository = RemoteLoginRepositoryImpl(
      channel: channel,
      httpLogin: () async {
        httpLogins.add(true);
        return true;
      },
    );
    await repository.ensureLoaded();
  });

  tearDown(() => channel.dispose());

  /// 默认口令 123456 的 MD5（ws 握手与 HTTP 登录提交同一个值）。
  const String defaultMd5 = 'e10adc3949ba59abbe56e057f20f883e';

  test('autoLogin 无自定义账号：回落设备号连接，先 HTTP 预登录', () async {
    await repository.autoLogin();
    expect(httpLogins, hasLength(1));
    expect(
      channel.calls,
      <String>['connect:$testDeviceId:$defaultMd5:$testDeviceId:tv'],
    );
  });

  test('autoLogin 有持久化账号：先 HTTP 预登录，再用口令 MD5 连接', () async {
    await AppSettings.instance.clearAllPersisted();
    SharedPreferences.setMockInitialValues(
      <String, Object>{'app_remote_account_v1': 'ABCD'},
    );
    await repository.ensureLoaded();

    await repository.autoLogin();
    expect(httpLogins, hasLength(1));
    expect(channel.calls, <String>['connect:ABCD:$defaultMd5:$testDeviceId:tv']);
  });

  test('switchAccount：先断开再连接，并持久化新账号', () async {
    await repository.switchAccount('EFGH');
    expect(
      channel.calls,
      <String>['disconnect', 'connect:EFGH:$defaultMd5:$testDeviceId:tv'],
    );
    expect(repository.savedAccount, 'EFGH');
  });

  test('switchAccount 鉴权失败：抛 RemoteLoginException 并保留账号', () async {
    channel.connectError = const RealtimeException(401, 'invalid token');

    await expectLater(
      repository.switchAccount('BAD'),
      throwsA(isA<RemoteLoginException>()
          .having((RemoteLoginException e) => e.code, 'code', 401)),
    );
    // 失败也保留新账号配置（重启后仍重试）。
    expect(repository.savedAccount, 'BAD');
  });

  test('自定义口令生效：口令 MD5 随设置变化', () async {
    await AppSettings.instance.setRemotePassword('654321');
    await repository.switchAccount('CUST');
    // md5('654321')
    expect(
      channel.calls.last,
      startsWith('connect:CUST:c33367701511b4f6020ec61ded352059:'),
    );
  });

  test('HTTP 预登录抛错不阻断 ws 连接', () async {
    repository = RemoteLoginRepositoryImpl(
      channel: channel,
      httpLogin: () async => throw Exception('network down'),
    );
    await repository.autoLogin();
    expect(channel.calls, hasLength(1));
  });

  test('DeviceCredentials 口令与 MD5 自洽', () {
    expect(DeviceCredentials.password(), DeviceCredentials.defaultPassword);
    expect(DeviceCredentials.passwordMd5(), defaultMd5);
  });

  test('连接随握手上报 app/version/build（客户端标识）', () async {
    repository = RemoteLoginRepositoryImpl(
      channel: channel,
      httpLogin: () async => true,
      clientInfo: () async =>
          const ClientInfo(app: 'com.test.tv', version: '1.0.0', build: '2'),
    );
    await repository.ensureLoaded();
    await repository.autoLogin();
    expect(channel.lastApp, 'com.test.tv');
    expect(channel.lastVersion, '1.0.0');
    expect(channel.lastBuild, '2');
  });
}
