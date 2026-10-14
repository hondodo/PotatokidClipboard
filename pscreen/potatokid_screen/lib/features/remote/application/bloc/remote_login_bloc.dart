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
