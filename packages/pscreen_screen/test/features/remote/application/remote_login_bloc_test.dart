import 'dart:async';

// ignore: depend_on_referenced_packages
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:nim_core_v2_platform_interface/nim_core_v2_platform_interface.dart' hide Log;
import 'package:pscreen_screen/core/di/get_it.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';
import 'package:pscreen_screen/features/remote/application/bloc/remote_login_bloc.dart';
import 'package:pscreen_screen/features/remote/application/bloc/remote_login_event.dart';
import 'package:pscreen_screen/features/remote/application/bloc/remote_login_state.dart';
import 'package:pscreen_screen/features/remote/domain/repositories/remote_login_repository.dart';

/// RemoteLoginRepository 手工 Fake：流可控、方法可配置。
class FakeRemoteLoginRepository extends Mock implements RemoteLoginRepository {
  FakeRemoteLoginRepository({this.account = ''});

  String account;
  Object? autoLoginError;
  Object? switchAccountError;
  Completer<void>? autoLoginGate;
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
    // Bloc 错误路径经 Injection.get<LogService>() 记录；测试环境注册真实
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
    repository.autoLoginError = Exception('sdk not initialized');
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
    repository.account = 'ABCD';
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
      repository.account = 'ABCD';
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

  test('被踢下线后兜底不生效：仍为 error', () {
    fakeAsync((FakeAsync async) {
      repository.account = 'ABCD';
      final RemoteLoginBloc bloc = buildBloc();
      repository.loginStatusController.add(NIMLoginStatus.loginStatusLogined);
      async.flushMicrotasks();
      expect(bloc.state.status, RemoteLoginStatus.syncing);

      repository.kickedController
          .add(NIMKickedOfflineDetail(reasonDesc: 'kicked by other'));
      async.flushMicrotasks();
      expect(bloc.state.status, RemoteLoginStatus.error);

      async.elapse(const Duration(seconds: 15));
      async.flushMicrotasks();
      expect(bloc.state.status, RemoteLoginStatus.error);
      bloc.close();
      async.flushMicrotasks();
    });
  });

  test('未设置时 logined 事件被忽略', () async {
    final RemoteLoginBloc bloc = buildBloc();
    repository.loginStatusController.add(NIMLoginStatus.loginStatusLogined);
    await pumpEventQueue();
    expect(bloc.state.status, RemoteLoginStatus.notConfigured);
    await bloc.close();
  });

  test('logout 事件为无操作', () async {
    final RemoteLoginBloc bloc = buildBloc();
    final RemoteLoginState initialState = bloc.state;
    repository.loginStatusController.add(NIMLoginStatus.loginStatusLogout);
    await pumpEventQueue();
    expect(bloc.state, initialState);
    await bloc.close();
  });
}
