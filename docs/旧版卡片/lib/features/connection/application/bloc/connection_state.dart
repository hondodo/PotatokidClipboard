import 'package:pscreen_home/core/network/ha_ws_client.dart';

/// 连接状态（不可变，通过 copyWith 更新）。
class ConnectionState {
  const ConnectionState._({
    required this.phase,
    this.message,
    this.retryCount,
  });

  /// 初始状态（未连接）。
  factory ConnectionState.initial() => const ConnectionState._(
        phase: HaConnectionPhase.disconnected,
        message: null,
        retryCount: 0,
      );

  /// 由底层连接信息映射。
  factory ConnectionState.fromInfo(HaConnectionInfo info) => ConnectionState._(
        phase: info.phase,
        message: info.message,
        retryCount: info.retryCount,
      );

  final HaConnectionPhase phase;
  final String? message;
  final int? retryCount;

  /// 是否已就绪（可加载数据）
  bool get isReady => phase == HaConnectionPhase.ready;

  /// 是否处于自动重连流程
  bool get isRetrying => (retryCount ?? 0) > 0;

  /// 是否可点击「重试」
  bool get canRetry =>
      phase == HaConnectionPhase.disconnected ||
      phase == HaConnectionPhase.authFailed;

  ConnectionState copyWith({
    HaConnectionPhase? phase,
    String? message,
    int? retryCount,
  }) {
    return ConnectionState._(
      phase: phase ?? this.phase,
      message: message,
      retryCount: retryCount ?? this.retryCount,
    );
  }
}
