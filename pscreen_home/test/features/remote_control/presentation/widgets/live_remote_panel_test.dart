import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/core/di/get_it.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/live_remote_panel.dart';
import 'package:pscreen_home/features/remote_control/presentation/widgets/remote_panel_registry.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';

void main() {
  /// 造一台「正在看 CH-700」的电视端状态（1000 个频道）。
  RealtimeDeviceState buildDevice({String? current}) {
    final Map<String, Object?> scene = <String, Object?>{
      'kind': 'live',
      'title': '直播',
    };
    if (current != null) scene['channelName'] = current;
    return RealtimeDeviceState(
      account: 'tv-1',
      kind: 'tv',
      scene: scene,
      channels: List<String>.generate(1000, (int i) => 'CH-${i + 1}'),
    );
  }

  RemotePanelContext buildPanel(RealtimeDeviceState device) {
    return RemotePanelContext(
      account: 'tv-1',
      device: device,
      online: true,
      onCommand: (_) {},
    );
  }

  testWidgets('打开列表后自动滚动到当前播放频道（视口内可见）', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: LiveRemotePanel(
              panel: buildPanel(buildDevice(current: 'CH-700')),
            ),
          ),
        ),
      ),
    );
    // 首帧排程 reveal → 粗跳 → 下一帧构建目标行 → ensureVisible 动画。
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('正在播放'), findsOneWidget, reason: '当前频道应有高亮行');
    expect(
      find.text('CH-700'),
      findsOneWidget,
      reason: '当前行应已被构建（粗跳生效）',
    );
    final Rect rowRect = tester.getRect(find.text('CH-700'));
    final Rect listRect = tester.getRect(find.byType(ListView));
    expect(
      listRect.contains(rowRect.center),
      isTrue,
      reason: '当前播放频道应被滚动到列表视口内（actual=$rowRect, list=$listRect）',
    );
  });

  testWidgets('无 channelName（不在直播页）时不滚动、不高亮', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 400,
            child: LiveRemotePanel(panel: buildPanel(buildDevice())),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('正在播放'), findsNothing);
    final Rect listRect = tester.getRect(find.byType(ListView));
    expect(
      listRect.top,
      lessThanOrEqualTo(listRect.bottom),
      reason: '列表存在（此时应停留在顶部）',
    );
  });

  testWidgets('经由「频道列表」按钮打开底部弹窗后也自动定位', (
    WidgetTester tester,
  ) async {
    // 弹窗内部通过 Injection 取 RealtimeChannel 查设备缓存。
    getIt.registerSingleton<RealtimeChannel>(
      _FakeRealtimeChannel(buildDevice(current: 'CH-700')),
    );
    addTearDown(() async => getIt.unregister<RealtimeChannel>());

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiveControlsPanel(
            panel: buildPanel(buildDevice(current: 'CH-700')),
            channelsLabel: '频道列表',
          ),
        ),
      ),
    );

    await tester.tap(find.textContaining('频道列表'));
    await tester.pumpAndSettle();

    expect(find.text('正在播放'), findsOneWidget, reason: '弹窗应有高亮行');
    final Rect rowRect = tester.getRect(find.text('CH-700'));
    final Rect listRect = tester.getRect(find.byType(ListView));
    expect(
      listRect.contains(rowRect.center),
      isTrue,
      reason: '弹窗中的列表也应滚动到当前频道（row=$rowRect, list=$listRect）',
    );
  });
}

/// 只提供设备缓存的假通道：不连网，仅满足弹窗的 deviceInfoOf / deviceStates。
class _FakeRealtimeChannel extends RealtimeChannel {
  _FakeRealtimeChannel(this.device) : super(url: 'ws://test');

  final RealtimeDeviceState device;

  @override
  Stream<RealtimeDeviceState> get deviceStates =>
      const Stream<RealtimeDeviceState>.empty();

  @override
  RealtimeDeviceState? deviceInfoOf(String account) => device;
}
