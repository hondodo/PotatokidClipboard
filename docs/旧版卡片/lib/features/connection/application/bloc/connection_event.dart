import 'package:pscreen_home/core/network/ha_ws_client.dart';

/// 连接状态机事件基类。
abstract class ConnectionEvent {
  const ConnectionEvent();
}

/// 启动连接（应用启动时触发一次）。
class StartConnection extends ConnectionEvent {
  const StartConnection();
}

/// 手动重试连接（页面「重试」按钮）。
class RetryConnection extends ConnectionEvent {
  const RetryConnection();
}

/// 连接配置（地址 / 令牌）变更后重建连接。
///
/// 设置页保存新配置后触发：先断开旧连接再用新配置发起，
/// 连接就绪后由页面监听自动重新加载数据（刷新）。
class Reconnect extends ConnectionEvent {
  const Reconnect();
}

/// 底层连接状态发生变化（由仓库流转发）。
class ConnectionInfoChanged extends ConnectionEvent {
  const ConnectionInfoChanged(this.info);

  final HaConnectionInfo info;
}
