import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';
import 'package:pscreen_home/core/network/ha_ws_client.dart';
import 'package:pscreen_home/features/connection/application/bloc/connection_event.dart';
import 'package:pscreen_home/features/connection/application/bloc/connection_state.dart';
import 'package:pscreen_home/features/connection/domain/repositories/connection_repository.dart';

/// 连接状态机：维护与 Home Assistant 的连接状态（含自动重连的结果反馈）。
class ConnectionBloc extends Bloc<ConnectionEvent, ConnectionState> {
  ConnectionBloc({required this.repository}) : super(ConnectionState.initial()) {
    on<StartConnection>(_onStartConnection);
    on<RetryConnection>(_onRetryConnection);
    on<Reconnect>(_onReconnect);
    on<ConnectionInfoChanged>(_onConnectionInfoChanged);
    _subscription = repository.watchConnection().listen((info) => add(ConnectionInfoChanged(info)));
  }

  final ConnectionRepository repository;
  StreamSubscription<HaConnectionInfo>? _subscription;

  Future<void> _onStartConnection(StartConnection event, Emitter<ConnectionState> emit) => _connect();

  Future<void> _onRetryConnection(RetryConnection event, Emitter<ConnectionState> emit) => _connect();

  /// 配置变更后重建连接。
  ///
  /// 必须先断开：`HaWsClient.connect` 在已连接时幂等返回，
  /// 不断开的话新地址 / 新令牌不会生效。
  Future<void> _onReconnect(Reconnect event, Emitter<ConnectionState> emit) async {
    try {
      await repository.disconnect();
      await repository.connect();
    } catch (e, s) {
      Injection.get<LogService>().error('应用新配置并重新连接失败', error: e, stackTrace: s);
    }
  }

  Future<void> _connect() async {
    try {
      await repository.connect();
    } catch (e, s) {
      Injection.get<LogService>().error('连接 Home Assistant 失败', error: e, stackTrace: s);
    }
  }

  void _onConnectionInfoChanged(ConnectionInfoChanged event, Emitter<ConnectionState> emit) {
    emit(ConnectionState.fromInfo(event.info));
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}
