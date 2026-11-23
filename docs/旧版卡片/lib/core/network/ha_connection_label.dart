import 'package:pscreen_home/core/network/ha_ws_client.dart';

/// 连接阶段的中文文案（AppBar 状态与离线操作提示共用同一份）。
String haConnectionLabel(HaConnectionPhase phase, {int retryCount = 0}) =>
    switch (phase) {
      HaConnectionPhase.ready => '已连接',
      HaConnectionPhase.connecting => retryCount > 0 ? '重连中' : '连接中',
      HaConnectionPhase.authenticating => '认证中',
      HaConnectionPhase.authFailed => '认证失败',
      HaConnectionPhase.disconnected => retryCount > 0 ? '重连中' : '未连接',
    };

/// 非「已连接」时尝试操作 HA 的统一提示。
///
/// 认证失败不会自动恢复，提示直接引导去设置检查配置，而不是让用户干等。
String haInteractionBlockedMessage(
  HaConnectionPhase phase, {
  int retryCount = 0,
}) {
  if (phase == HaConnectionPhase.authFailed) {
    return '认证失败，请到设置检查地址和令牌';
  }
  return '${haConnectionLabel(phase, retryCount: retryCount)}，请稍后操作';
}
