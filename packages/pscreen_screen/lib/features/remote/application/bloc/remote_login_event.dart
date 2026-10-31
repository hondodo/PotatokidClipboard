import 'package:pscreen_screen/core/network/realtime_channel.dart';

/// 远程登录事件。
abstract class RemoteLoginEvent {
  const RemoteLoginEvent();
}

/// 启动自动连接（main 在 DI 完成后派发）。
class RemoteLoginAutoLogin extends RemoteLoginEvent {
  const RemoteLoginAutoLogin();
}

/// 用户提交账号（设置页输入完成）。
class RemoteLoginSubmit extends RemoteLoginEvent {
  const RemoteLoginSubmit(this.account);

  final String account;
}

/// 实时通道连接状态变更。
class RemoteLoginStatusChanged extends RemoteLoginEvent {
  const RemoteLoginStatusChanged(this.status);

  final RealtimeConnectionState status;
}

/// 致命错误（鉴权失败等）。
class RemoteLoginLoginFailed extends RemoteLoginEvent {
  const RemoteLoginLoginFailed(this.message);

  final String message;
}
