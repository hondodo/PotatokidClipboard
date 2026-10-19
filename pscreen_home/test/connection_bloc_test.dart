import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/core/di/get_it.dart';
import 'package:pscreen_home/core/logging/log_service.dart';
import 'package:pscreen_home/core/network/ha_ws_client.dart';
import 'package:pscreen_home/features/connection/application/bloc/connection_bloc.dart';
import 'package:pscreen_home/features/connection/application/bloc/connection_event.dart';
import 'package:pscreen_home/features/connection/application/bloc/connection_state.dart';
import 'package:pscreen_home/features/connection/domain/repositories/connection_repository.dart';

/// 内存版 ConnectionRepository：记录调用顺序，并把状态变化推给 Bloc。
class _FakeConnectionRepository implements ConnectionRepository {
  final List<String> calls = <String>[];
  final StreamController<HaConnectionInfo> _controller =
      StreamController<HaConnectionInfo>.broadcast();

  @override
  Stream<HaConnectionInfo> watchConnection() => _controller.stream;

  @override
  HaConnectionInfo get current =>
      const HaConnectionInfo(phase: HaConnectionPhase.disconnected);

  @override
  Future<void> connect() async {
    calls.add('connect');
    _controller.add(const HaConnectionInfo(phase: HaConnectionPhase.connecting));
  }

  @override
  Future<void> disconnect() async {
    calls.add('disconnect');
    _controller
        .add(const HaConnectionInfo(phase: HaConnectionPhase.disconnected));
  }
}

void main() {
  setUp(() {
    getIt.registerLazySingleton<LogService>(() => const LogService());
  });

  tearDown(() async {
    await getIt.reset();
  });

  group('ConnectionBloc 配置变更重建连接', () {
    late _FakeConnectionRepository repo;
    late ConnectionBloc bloc;

    setUp(() {
      repo = _FakeConnectionRepository();
      bloc = ConnectionBloc(repository: repo);
      addTearDown(bloc.close);
    });

    test('StartConnection / RetryConnection 只发起连接', () async {
      bloc.add(const StartConnection());
      await bloc.stream
          .firstWhere((ConnectionState s) => s.phase == HaConnectionPhase.connecting);
      expect(repo.calls, <String>['connect']);

      bloc.add(const RetryConnection());
      await bloc.stream
          .firstWhere((ConnectionState s) => s.phase == HaConnectionPhase.connecting);
      expect(repo.calls, <String>['connect', 'connect']);
    });

    test('Reconnect 先断开旧连接再连接（新地址才能生效）', () async {
      bloc.add(const Reconnect());
      await bloc.stream
          .firstWhere((ConnectionState s) => s.phase == HaConnectionPhase.connecting);

      expect(
        repo.calls,
        <String>['disconnect', 'connect'],
        reason: 'HaWsClient.connect 在已连接时幂等，必须先 disconnect',
      );
    });
  });
}
