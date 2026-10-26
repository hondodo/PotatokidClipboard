import 'package:pscreen_screen/core/network/realtime_channel.dart';

/// 远程登录数据访问接口：账号持久化 + 实时通道连接/断开 + 事件流。
abstract class RemoteLoginRepository {
  /// 已持久化的账号（空串表示未设置；实现保证持久化已加载后可信）。
  String get savedAccount;

  /// 连接状态事件流。
  Stream<RealtimeConnectionState> get onConnectionState;

  /// 致命错误（鉴权失败等）事件流。
  Stream<String> get onFatalError;

  /// 启动自动连接：无账号静默返回；有账号直接连接。
  /// 失败抛 [RemoteLoginException]。
  Future<void> autoLogin();

  /// 切换账号：先持久化新账号，再断开旧连接并连接新账号。
  /// 失败抛 [RemoteLoginException]。
  Future<void> switchAccount(String account);
}

/// 实时通道连接失败异常（服务端拒绝，携带错误码与描述）。
class RemoteLoginException implements Exception {
  const RemoteLoginException(this.code, [this.message]);

  /// 错误码（0 表示网络/握手失败）。
  final int code;

  /// 错误描述。
  final String? message;

  @override
  String toString() => 'RemoteLoginException(code: $code, message: $message)';
}
