// ignore: depend_on_referenced_packages
import 'package:nim_core_v2_platform_interface/nim_core_v2_platform_interface.dart' hide Log;

/// 远程登录事件。
abstract class RemoteLoginEvent {
  const RemoteLoginEvent();
}

/// 启动自动登录（main 在 NIM 初始化收尾后派发，无论初始化成败）。
class RemoteLoginAutoLogin extends RemoteLoginEvent {
  const RemoteLoginAutoLogin();
}

/// 用户提交账号（设置页输入完成）。
class RemoteLoginSubmit extends RemoteLoginEvent {
  const RemoteLoginSubmit(this.account);

  final String account;
}

/// SDK 登录状态变更。
class RemoteLoginStatusChanged extends RemoteLoginEvent {
  const RemoteLoginStatusChanged(this.status);

  final NIMLoginStatus status;
}

/// SDK 数据同步变更。
class RemoteLoginDataSyncChanged extends RemoteLoginEvent {
  const RemoteLoginDataSyncChanged(this.detail);

  final NIMDataSyncDetail detail;
}

/// SDK 登录失败。
class RemoteLoginLoginFailed extends RemoteLoginEvent {
  const RemoteLoginLoginFailed(this.error);

  final NIMError error;
}

/// SDK 被踢下线。
class RemoteLoginKickedOffline extends RemoteLoginEvent {
  const RemoteLoginKickedOffline(this.reasonDesc);

  final String reasonDesc;
}

/// 同步兜底：进入「同步数据」后超时未见主数据完成，视为已登录。
class RemoteLoginSyncFallbackElapsed extends RemoteLoginEvent {
  const RemoteLoginSyncFallbackElapsed();
}
