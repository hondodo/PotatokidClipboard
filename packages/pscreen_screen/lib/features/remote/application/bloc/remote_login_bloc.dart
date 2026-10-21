import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
// ignore: depend_on_referenced_packages
import 'package:nim_core_v2_platform_interface/nim_core_v2_platform_interface.dart' hide Log;
import 'package:potatokid_screen/core/di/injection.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';
import 'package:pscreen_screen/features/remote/application/bloc/remote_login_event.dart';
import 'package:pscreen_screen/features/remote/application/bloc/remote_login_state.dart';
import 'package:pscreen_screen/features/remote/domain/repositories/remote_login_repository.dart';

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
      Injection.get<LogService>().error('远程自动登录失败', error: e, stackTrace: s);
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
        state.status == RemoteLoginStatus.syncing ||
        state.status == RemoteLoginStatus.loggedIn;
    if (account == state.account && sessionActive) return;
    final int seq = ++_opSeq;
    _syncFallbackTimer?.cancel();
    emit(state.copyWith(
      account: account,
      status: RemoteLoginStatus.loggingIn,
      clearErrorMessage: true,
    ));
    try {
      await _repository.switchAccount(account);
    } catch (e, s) {
      Injection.get<LogService>().error('切换账号失败: $account', error: e, stackTrace: s);
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
      case NIMLoginStatus.loginStatusLogining:
        if (state.status != RemoteLoginStatus.notConfigured) {
          emit(state.copyWith(status: RemoteLoginStatus.loggingIn));
        }
        break;
      case NIMLoginStatus.loginStatusLogined:
        // 空账号（未设置）不允许被 SDK 残留会话驱动展示，只允许显示「未设置」。
        if (state.status != RemoteLoginStatus.notConfigured) {
          emit(state.copyWith(status: RemoteLoginStatus.syncing));
          _startSyncFallbackTimer();
        }
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
        detail.state == NIMDataSyncState.nimDataSyncStateCompleted &&
        // 守卫：仅登录中/同步中响应主数据完成；阻断迟到事件在
        // error/notConfigured/loggedIn 态造成错误的「已登录」展示。
        // loggingIn 允许是为兼容 completed 先于 logined 到达的竞态。
        (state.status == RemoteLoginStatus.syncing ||
            state.status == RemoteLoginStatus.loggingIn)) {
      _syncFallbackTimer?.cancel();
      emit(state.copyWith(status: RemoteLoginStatus.loggedIn));
    }
  }

  void _onLoginFailed(
    RemoteLoginLoginFailed event,
    Emitter<RemoteLoginState> emit,
  ) {
    _syncFallbackTimer?.cancel();
    Injection.get<LogService>()
        .error('云信登录失败: code=${event.error.code} desc=${event.error.desc}');
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
    Injection.get<LogService>().error('云信被踢下线: ${event.reasonDesc}');
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
