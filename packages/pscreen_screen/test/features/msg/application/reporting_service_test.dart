// test/features/msg/reporting_service_test.dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/features/iptv/application/channel_info_provider.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/iptv/domain/models/iptv_channel.dart';
import 'package:pscreen_screen/features/msg/application/current_scene_provider.dart';
import 'package:pscreen_screen/features/msg/application/reporting_service.dart';

/// 假发送器：记录目标与文本。
class FakeSender implements MessageSender {
  final List<(String, String)> sent = <(String, String)>[];
  bool ok = true;

  @override
  Future<bool> sendText({required String toAccount, required String text}) async {
    sent.add((toAccount, text));
    return ok;
  }
}

/// 假场景提供者：返回固定文案。
///
/// 共享包不持有 Tab / 页名这套宿主语义（首屏报频道名、其余 Tab 报页名，由宿主的
/// TvSceneProvider 决定），因此这里只验证一件事：注入的场景描述被**如实上报**。
class _FakeSceneProvider extends CurrentSceneProvider {
  const _FakeSceneProvider(this.text);

  final String text;

  @override
  String describe() => text;
}

void main() {
  late FakeSender sender;
  late ReportingService service;

  setUp(() {
    sender = FakeSender();
    ChannelInfoProvider.instance.setChannels(<IptvChannel>[
      const IptvChannel(name: 'CCTV-1', sources: <String>['a']),
      const IptvChannel(name: 'CCTV-5', sources: <String>['b']),
    ]);
    LiveChannelController.instance.setCount(2);
    service = ReportingService(
      sender: sender,
      deviceModel: () async => 'MiBOX 4',
      channelInfo: ChannelInfoProvider.instance,
      liveChannel: LiveChannelController.instance,
      sceneProvider: const _FakeSceneProvider('测试场景'),
      now: () => DateTime(2026, 10, 15, 20, 30),
    );
  });

  tearDown(() {
    service.dispose();
    ChannelInfoProvider.instance.setChannels(<IptvChannel>[]);
    LiveChannelController.instance.setCount(0);
  });

  test('登录：发两条给 1000001（账号时间型号 + 正在收看）', () async {
    service.start('TV_001');
    await pumpEventQueue();
    expect(sender.sent.length, 2);
    expect(sender.sent[0].$1, '1000001');
    expect(sender.sent[0].$2, 'TV_001于2026-10-15 20:30使用MiBOX 4登录成功。');
    expect(sender.sent[1].$2, '正在收看测试场景');
    service.stop();
  });

  test('非频道场景使用注入的场景描述', () {
    expect(service.positionText(), '测试场景');
  });

  test('切台确认（防抖后）发切换频道消息', () async {
    service.start('TV_001');
    await pumpEventQueue();
    sender.sent.clear();

    LiveChannelController.instance.select(1);
    // 防抖窗口内再次触发 → 只发一条（全程依赖构造器注册的 onPlayCommit 监听）
    await Future<void>.delayed(const Duration(milliseconds: 300));
    LiveChannelController.instance.select(0);
    await Future<void>.delayed(
        ReportingService.channelDebounce + const Duration(milliseconds: 100));
    expect(sender.sent.length, 1);
    expect(sender.sent[0].$2, '切换频道：CCTV-1');
    service.stop();
  });

  test('stop 后不再发送', () async {
    service.start('TV_001');
    await pumpEventQueue();
    sender.sent.clear();
    service.stop();
    service.notifyChannelCommitted();
    await Future<void>.delayed(
        ReportingService.channelDebounce + const Duration(milliseconds: 100));
    expect(sender.sent, isEmpty);
  });

  test('重复 start 不重发登录消息', () async {
    service.start('TV_001');
    await pumpEventQueue();
    final int n = sender.sent.length;
    service.start('TV_001');
    await pumpEventQueue();
    expect(sender.sent.length, n);
    service.stop();
  });

  test('发送失败不抛出', () async {
    sender.ok = false;
    service.start('TV_001');
    await pumpEventQueue();
    service.stop();
  });

  /// 构造一个可注入心跳间隔与可控时钟的实例（并替换 [service] 供 tearDown 清理）。
  ReportingService buildHeartbeatService(
      DateTime Function() now, Duration interval) {
    service.dispose();
    return service = ReportingService(
      sender: sender,
      deviceModel: () async => 'MiBOX 4',
      channelInfo: ChannelInfoProvider.instance,
      liveChannel: LiveChannelController.instance,
      sceneProvider: const _FakeSceneProvider('测试场景'),
      now: now,
      heartbeatInterval: interval,
    );
  }

  test('心跳：按间隔发送「已收看 N 分钟」（spec §6）', () {
    fakeAsync((FakeAsync async) {
      DateTime nowValue = DateTime(2026, 10, 15, 20, 30);
      buildHeartbeatService(() => nowValue, const Duration(milliseconds: 100));

      service.start('TV_001');
      async.flushMicrotasks();
      expect(sender.sent.length, 2);
      sender.sent.clear();

      async.elapse(const Duration(milliseconds: 100));
      async.flushMicrotasks();
      expect(sender.sent.length, 1);
      expect(sender.sent[0].$2, '已收看0分钟，当前频道是测试场景');

      nowValue = nowValue.add(const Duration(minutes: 6));
      async.elapse(const Duration(milliseconds: 100));
      async.flushMicrotasks();
      expect(sender.sent.length, 2);
      expect(sender.sent[1].$2, '已收看6分钟，当前频道是测试场景');
    });
  });

  test('stop 后心跳停止', () {
    fakeAsync((FakeAsync async) {
      final DateTime nowValue = DateTime(2026, 10, 15, 20, 30);
      buildHeartbeatService(() => nowValue, const Duration(milliseconds: 100));

      service.start('TV_001');
      async.flushMicrotasks();
      sender.sent.clear();

      service.stop();
      async.elapse(const Duration(milliseconds: 500));
      async.flushMicrotasks();
      expect(sender.sent, isEmpty);
    });
  });

  test('stop→start 后心跳按新登录时间重新计数', () {
    fakeAsync((FakeAsync async) {
      DateTime nowValue = DateTime(2026, 10, 15, 20, 30);
      buildHeartbeatService(() => nowValue, const Duration(milliseconds: 100));

      service.start('TV_001');
      async.flushMicrotasks();

      // 收看 3 分钟后登出
      nowValue = nowValue.add(const Duration(minutes: 3));
      service.stop();

      // 重新登录（心跳计时应从 20:33 起算）
      service.start('TV_002');
      async.flushMicrotasks();
      expect(sender.sent[2].$2, 'TV_002于2026-10-15 20:33使用MiBOX 4登录成功。');
      sender.sent.clear();

      async.elapse(const Duration(milliseconds: 100));
      async.flushMicrotasks();
      expect(sender.sent, isNotEmpty);
      expect(sender.sent.first.$2, '已收看0分钟，当前频道是测试场景');

      nowValue = nowValue.add(const Duration(minutes: 4));
      async.elapse(const Duration(milliseconds: 100));
      async.flushMicrotasks();
      expect(sender.sent.last.$2, '已收看4分钟，当前频道是测试场景');
    });
  });
}
