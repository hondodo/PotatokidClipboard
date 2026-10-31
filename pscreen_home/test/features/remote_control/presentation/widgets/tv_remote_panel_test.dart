import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/remote_panel_registry.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';

void main() {
  RealtimeDeviceState buildDevice(String sceneKind) => RealtimeDeviceState(
    account: 'tv-1',
    kind: 'tv',
    scene: <String, Object?>{'kind': sceneKind, 'title': '标题'},
    channels: const <String>['CH-1', 'CH-2'],
  );

  testWidgets('无论选中哪个页面，页面切换行与直播控制行都可见', (
    WidgetTester tester,
  ) async {
    final List<String> commands = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RemotePanelRegistry.build(
            RemotePanelContext(
              account: 'tv-1',
              device: buildDevice('settings'),
              online: true,
              onCommand: commands.add,
              onSendMessage: () {},
            ),
          ),
        ),
      ),
    );

    // 第一行：页面切换 + 发送消息；第二行：直播控制。
    for (final String label in <String>[
      '直播',
      '时间',
      '屏保',
      '设置',
      '发送消息',
      '音量+',
      '音量-',
      '静音',
      '定时关闭',
    ]) {
      expect(find.text(label), findsOneWidget, reason: '$label 应始终可见');
    }
    expect(find.textContaining('频道列表'), findsOneWidget);
    // 悬浮开关只属于中控端（kind == 'home'），电视端不显示。
    expect(find.text('悬浮'), findsNothing);

    // 点「时间」→ 发 nav weather（电视端 Tab 1 = 时间页）。
    await tester.tap(find.text('时间'));
    expect(commands.single, contains('"page":"weather"'));
  });
}
