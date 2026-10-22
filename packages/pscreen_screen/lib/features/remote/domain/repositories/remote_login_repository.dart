import 'package:nim_core_v2_platform_interface/nim_core_v2_platform_interface.dart' hide Log;

/// 远程登录数据访问接口：账号持久化 + 云信 SDK 登录/登出 + 事件流。
abstract class RemoteLoginRepository {
  /// 已持久化的账号（空串表示未设置；实现保证持久化已加载后可信）。
  String get savedAccount;

  /// SDK 登录状态事件流。
  Stream<NIMLoginStatus> get onLoginStatus;

  /// SDK 数据同步事件流。
  Stream<NIMDataSyncDetail> get onDataSync;

  /// SDK 登录失败事件流。
  Stream<NIMError> get onLoginFailed;

  /// SDK 被踢下线事件流。
  Stream<NIMKickedOfflineDetail> get onKickedOffline;

  /// 启动自动登录：无账号静默返回；有账号直接登录（无需登出）。
  /// 失败抛异常（token 错误、SDK 未初始化等）。
  Future<void> autoLogin();

  /// 切换账号：先持久化新账号，再（有活跃会话时）登出，最后登录新账号。
  /// 失败抛 [RemoteLoginException] 或 SDK 异常。
  Future<void> switchAccount(String account);
}

/// 云信登录失败异常（服务端/SDK 拒绝，携带错误码与描述）。
class RemoteLoginException implements Exception {
  const RemoteLoginException(this.code, [this.message]);

  /// NIM 错误码。
  final int code;

  /// 错误描述。
  final String? message;

  @override
  String toString() => 'RemoteLoginException(code: $code, message: $message)';
}
