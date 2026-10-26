import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/core/di/get_it.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';
import 'package:pscreen_screen/features/remote/application/bloc/remote_login_bloc.dart';
import 'package:pscreen_screen/features/remote/application/bloc/remote_login_event.dart';
import 'package:pscreen_screen/features/remote/application/bloc/remote_login_state.dart';
import 'package:pscreen_screen/features/remote/domain/repositories/remote_login_repository.dart';

/// RemoteLoginRepository 手工 Fake：流可控、方法可配置。
class FakeRemoteLoginRepository implements RemoteLoginRepository {
  FakeRemoteLoginRepository({this.account = ''});

  String account;
  Object? autoLoginError;
  Object? switchAccountError;
  Completer<void>? autoLoginGate;
  final List<String> calls = <String>[];

  final StreamController<RealtimeConnectionState> connectionController =
      StreamController<RealtimeConnectionState>.broadcast();
  final StreamController<String> fatalErrorController =
      StreamController<String>.broadcast();

  @override
  String get savedAccount => account;

  @override
  Stream<RealtimeConnectionState> get onConnectionState =>
      connectionController.stream;

  @override
  Stream<String> get onFatalError => fatalErrorController.stream;

  @override
  Future<void> autoLogin() async {
    calls.add('autoLogin');
    final Completer<void>? gate = autoLoginGate;
    if (gate != null) {
      await gate.future;
    }
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
    connectionController.close();
    fatalErrorController.close();
  }
}

void main() {
  late FakeRemoteLoginRepository repository;

  RemoteLoginBloc buildBloc() => RemoteLoginBloc(repository: repository);

  setUp(() {
    // Bloc 错误路径经 ScreenInjection.get<LogService>() 记录；测试环境注册真实
    // const LogService（无状态，仅 debugPrint）。
    getIt.registerSingleton<LogService>(const LogService());
    repository = FakeRemoteLoginRepository();
  });

  tearDown(() async {
    repository.dispose();
    await getIt.unregister<LogService>();
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
    repository.autoLoginError = Exception('connect failed');
    final RemoteLoginBloc bloc = buildBloc();
    bloc.add(const RemoteLoginAutoLogin());
    await pumpEventQueue();
    expect(repository.calls, <String>['autoLogin']);
    expect(bloc.state.status, RemoteLoginStatus.error);
    await bloc.close();
  });

  test('AutoLogin 迟到失败不覆盖新提交状态', () async {
    repository.account = 'ABCD';
    repository.autoLoginError = Exception('timeout');
    repository.autoLoginGate = Completer<void>();
    final RemoteLoginBloc bloc = buildBloc();
    bloc.add(const RemoteLoginAutoLogin());
    await pumpEventQueue();

    bloc.add(const RemoteLoginSubmit('NEW'));
    await pumpEventQueue();
    expect(bloc.state.account, 'NEW');
    expect(bloc.state.status, RemoteLoginStatus.loggingIn);

    repository.autoLoginGate!.complete();
    await pumpEventQueue();
    expect(bloc.state.status, RemoteLoginStatus.loggingIn);
    expect(bloc.state.account, 'NEW');
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

  test('Submit 同账号且连接中：跳过', () async {
    repository.account = 'ABCD';
    final RemoteLoginBloc bloc = buildBloc();
    bloc.add(const RemoteLoginSubmit('ABCD'));
    await pumpEventQueue();
    expect(repository.calls, isEmpty);
    await bloc.close();
  });

  test('Submit 同账号但 error：重新连接', () async {
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
    repository.switchAccountError = const RemoteLoginException(401, 'token invalid');
    final RemoteLoginBloc bloc = buildBloc();
    bloc.add(const RemoteLoginSubmit('BAD'));
    await pumpEventQueue();
    expect(bloc.state.status, RemoteLoginStatus.error);
    expect(bloc.state.account, 'BAD');
    await bloc.close();
  });

  test('连接成功事件：转已登录', () async {
    repository.account = 'ABCD';
    final RemoteLoginBloc bloc = buildBloc();
    repository.connectionController.add(RealtimeConnectionState.connected);
    await pumpEventQueue();
    expect(bloc.state.status, RemoteLoginStatus.loggedIn);
    await bloc.close();
  });

  test('断开事件（有账号）：视为重连中', () async {
    repository.account = 'ABCD';
    final RemoteLoginBloc bloc = buildBloc();
    repository.connectionController.add(RealtimeConnectionState.connected);
    await pumpEventQueue();
    repository.connectionController.add(RealtimeConnectionState.disconnected);
    await pumpEventQueue();
    expect(bloc.state.status, RemoteLoginStatus.loggingIn);
    await bloc.close();
  });

  test('断开事件（无账号）：保持未设置', () async {
    final RemoteLoginBloc bloc = buildBloc();
    repository.connectionController.add(RealtimeConnectionState.disconnected);
    await pumpEventQueue();
    expect(bloc.state.status, RemoteLoginStatus.notConfigured);
    await bloc.close();
  });

  test('断线重连成功：回到已登录', () async {
    repository.account = 'ABCD';
    final RemoteLoginBloc bloc = buildBloc();
    repository.connectionController.add(RealtimeConnectionState.disconnected);
    await pumpEventQueue();
    expect(bloc.state.status, RemoteLoginStatus.loggingIn);

    repository.connectionController.add(RealtimeConnectionState.connected);
    await pumpEventQueue();
    expect(bloc.state.status, RemoteLoginStatus.loggedIn);
    await bloc.close();
  });

  test('致命错误事件：转 error 并携带描述', () async {
    final RemoteLoginBloc bloc = buildBloc();
    repository.fatalErrorController.add('token invalid');
    await pumpEventQueue();
    expect(bloc.state.status, RemoteLoginStatus.error);
    expect(bloc.state.errorMessage, 'token invalid');
    await bloc.close();
  });

  test('error 状态事件：转 error', () async {
    repository.account = 'ABCD';
    final RemoteLoginBloc bloc = buildBloc();
    repository.connectionController.add(RealtimeConnectionState.error);
    await pumpEventQueue();
    expect(bloc.state.status, RemoteLoginStatus.error);
    await bloc.close();
  });
}
