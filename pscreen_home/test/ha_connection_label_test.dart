import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/core/network/ha_connection_label.dart';
import 'package:pscreen_home/core/network/ha_ws_client.dart';

void main() {
  test('连接阶段文案覆盖已连接 / 重连中 / 认证 / 未连接', () {
    expect(haConnectionLabel(HaConnectionPhase.ready), '已连接');
    expect(haConnectionLabel(HaConnectionPhase.connecting), '连接中');
    expect(
      haConnectionLabel(HaConnectionPhase.connecting, retryCount: 2),
      '重连中',
    );
    expect(haConnectionLabel(HaConnectionPhase.authenticating), '认证中');
    expect(haConnectionLabel(HaConnectionPhase.authFailed), '认证失败');
    expect(haConnectionLabel(HaConnectionPhase.disconnected), '未连接');
    expect(
      haConnectionLabel(HaConnectionPhase.disconnected, retryCount: 3),
      '重连中',
    );
  });

  test('离线操作提示带当前状态；认证失败引导去设置', () {
    expect(
      haInteractionBlockedMessage(
        HaConnectionPhase.disconnected,
        retryCount: 2,
      ),
      '重连中，请稍后操作',
    );
    expect(
      haInteractionBlockedMessage(HaConnectionPhase.authenticating),
      '认证中，请稍后操作',
    );
    expect(
      haInteractionBlockedMessage(HaConnectionPhase.authFailed),
      '认证失败，请到设置检查地址和令牌',
    );
  });
}
