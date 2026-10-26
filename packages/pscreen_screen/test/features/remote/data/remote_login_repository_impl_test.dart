import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/app/config/app_config.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';
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
    String role = 'tv',
    String? name,
  }) async {
    calls.add('connect:$account:$token:$role');
    final RealtimeException? error = connectError;
    if (error != null) throw error;
  }

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

  setUp(() async {
    // 先清空（同时使 singleton 加载缓存失效），再注入 mock 存储，最后重新加载。
    await AppSettings.instance.clearAllPersisted();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    channel = FakeRealtimeChannel();
    repository = RemoteLoginRepositoryImpl(channel: channel);
    await repository.ensureLoaded();
    AppConfig.realtimeToken = '12345678';
  });

  tearDown(() => channel.dispose());

  test('autoLogin 无账号：静默返回，不发起连接', () async {
    await repository.autoLogin();
    expect(channel.calls, isEmpty);
  });

  test('autoLogin 有持久化账号：用固定口令连接 TV 角色', () async {
    await AppSettings.instance.clearAllPersisted();
    SharedPreferences.setMockInitialValues(
      <String, Object>{'app_remote_account_v1': 'ABCD'},
    );
    await repository.ensureLoaded();

    await repository.autoLogin();
    expect(channel.calls, <String>['connect:ABCD:12345678:tv']);
  });

  test('switchAccount：先断开再连接，并持久化新账号', () async {
    await repository.switchAccount('EFGH');
    expect(channel.calls, <String>['disconnect', 'connect:EFGH:12345678:tv']);
    expect(repository.savedAccount, 'EFGH');
  });

  test('switchAccount 鉴权失败：抛 RemoteLoginException 并保留账号', () async {
    channel.connectError = const RealtimeException(401, 'token invalid');

    await expectLater(
      repository.switchAccount('BAD'),
      throwsA(isA<RemoteLoginException>()
          .having((RemoteLoginException e) => e.code, 'code', 401)),
    );
    // 失败也保留新账号配置（重启后仍重试）。
    expect(repository.savedAccount, 'BAD');
  });
}
