import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_screen/core/di/screen_injection.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';
import 'package:pscreen_screen/features/remote/application/bloc/remote_login_event.dart';
import 'package:pscreen_screen/features/remote/application/bloc/remote_login_state.dart';
import 'package:pscreen_screen/features/remote/domain/repositories/remote_login_repository.dart';

/// 远程实时通道连接状态机。
///
/// 展示流转：未设置 → 正在连接 → 已连接；失败/鉴权拒绝 → 连接异常。
/// 断线期间转为「正在连接」，通道自动重连成功后回到「已连接」。
class RemoteLoginBloc extends Bloc<RemoteLoginEvent, RemoteLoginState> {
  RemoteLoginBloc({required RemoteLoginRepository repository})
      : _repository = repository,
        super(RemoteLoginState.fromAccount(repository.savedAccount)) {
    on<RemoteLoginAutoLogin>(_onAutoLogin);
    on<RemoteLoginSubmit>(_onSubmit);
    on<RemoteLoginStatusChanged>(_onStatusChanged);
    on<RemoteLoginLoginFailed>(_onLoginFailed);
    _subscriptions.addAll(<StreamSubscription<Object?>>[
      repository.onConnectionState.listen(
        (RealtimeConnectionState e) => add(RemoteLoginStatusChanged(e)),
      ),
      repository.onFatalError.listen(
        (String e) => add(RemoteLoginLoginFailed(e)),
      ),
    ]);
  }

  final RemoteLoginRepository _repository;
  final List<StreamSubscription<Object?>> _subscriptions =
      <StreamSubscription<Object?>>[];

  /// 操作世代号：仅最新一次 autoLogin/submit 的失败可写入 error 态，
  /// 防止慢操作迟到失败覆盖新操作的结果。
  int _opSeq = 0;

  Future<void> _onAutoLogin(
    RemoteLoginAutoLogin event,
    Emitter<RemoteLoginState> emit,
  ) async {
    if (state.account.isEmpty) return;
    final int seq = ++_opSeq;
    emit(state.copyWith(
      status: RemoteLoginStatus.loggingIn,
      clearErrorMessage: true,
    ));
    try {
      await _repository.autoLogin();
    } catch (e, s) {
      ScreenInjection.get<LogService>().error('远程自动连接失败', error: e, stackTrace: s);
      if (seq == _opSeq) {
        emit(state.copyWith(status: RemoteLoginStatus.error, errorMessage: '$e'));
      }
    }
  }

  Future<void> _onSubmit(
    RemoteLoginSubmit event,
    Emitter<RemoteLoginState> emit,
  ) async {
    final String account = event.account.trim();
    if (account.isEmpty) return;
    final bool sessionActive = state.status == RemoteLoginStatus.loggingIn ||
        state.status == RemoteLoginStatus.loggedIn;
    if (account == state.account && sessionActive) return;
    final int seq = ++_opSeq;
    emit(state.copyWith(
      account: account,
      status: RemoteLoginStatus.loggingIn,
      clearErrorMessage: true,
    ));
    try {
      await _repository.switchAccount(account);
    } catch (e, s) {
      ScreenInjection.get<LogService>().error('切换账号失败: $account', error: e, stackTrace: s);
      if (seq == _opSeq) {
        emit(state.copyWith(status: RemoteLoginStatus.error, errorMessage: '$e'));
      }
    }
  }

  void _onStatusChanged(
    RemoteLoginStatusChanged event,
    Emitter<RemoteLoginState> emit,
  ) {
    switch (event.status) {
      case RealtimeConnectionState.connecting:
        if (state.account.isNotEmpty) {
          emit(state.copyWith(status: RemoteLoginStatus.loggingIn));
        }
        break;
      case RealtimeConnectionState.connected:
        emit(state.copyWith(
          status: RemoteLoginStatus.loggedIn,
          clearErrorMessage: true,
        ));
        break;
      case RealtimeConnectionState.disconnected:
        // 未配置账号时不展示重连；配置过则视为断线重连中。
        emit(state.copyWith(
          status: state.account.isEmpty
              ? RemoteLoginStatus.notConfigured
              : RemoteLoginStatus.loggingIn,
        ));
        break;
      case RealtimeConnectionState.error:
        emit(state.copyWith(status: RemoteLoginStatus.error));
        break;
    }
  }

  void _onLoginFailed(
    RemoteLoginLoginFailed event,
    Emitter<RemoteLoginState> emit,
  ) {
    ScreenInjection.get<LogService>().error('实时通道连接失败: ${event.message}');
    emit(state.copyWith(
      status: RemoteLoginStatus.error,
      errorMessage: event.message,
    ));
  }

  @override
  Future<void> close() async {
    for (final StreamSubscription<Object?> subscription in _subscriptions) {
      await subscription.cancel();
    }
    return super.close();
  }
}
