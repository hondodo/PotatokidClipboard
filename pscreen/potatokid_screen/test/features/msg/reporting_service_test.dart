// test/features/msg/reporting_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:potatokid_screen/features/app/application/app_tab_controller.dart';
import 'package:potatokid_screen/features/iptv/application/channel_info_provider.dart';
import 'package:potatokid_screen/features/iptv/application/live_channel_controller.dart';
import 'package:potatokid_screen/features/iptv/domain/models/iptv_channel.dart';
import 'package:potatokid_screen/features/msg/application/reporting_service.dart';

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
    AppTabController.branchIndex = 0;
    service = ReportingService(
      sender: sender,
      deviceModel: () async => 'MiBOX 4',
      channelInfo: ChannelInfoProvider.instance,
      liveChannel: LiveChannelController.instance,
      now: () => DateTime(2026, 10, 15, 20, 30),
    );
  });

  tearDown(() {
    service.stop();
    ChannelInfoProvider.instance.setChannels(<IptvChannel>[]);
    LiveChannelController.instance.setCount(0);
    AppTabController.branchIndex = 0;
  });

  test('登录：发两条给 1000001（账号时间型号 + 正在收看）', () async {
    service.start('TV_001');
    await pumpEventQueue();
    expect(sender.sent.length, 2);
    expect(sender.sent[0].$1, '1000001');
    expect(sender.sent[0].$2, 'TV_001于2026-10-15 20:30使用MiBOX 4登录成功。');
    expect(sender.sent[1].$2, '正在收看CCTV-1');
    service.stop();
  });

  test('不在频道页（时间页）→ 正在收看时间页', () async {
    AppTabController.branchIndex = 1;
    service.start('TV_001');
    await pumpEventQueue();
    expect(sender.sent[1].$2, '正在收看时间页');
    service.stop();
  });

  test('切台确认（防抖后）发切换频道消息', () async {
    service.start('TV_001');
    await pumpEventQueue();
    sender.sent.clear();

    LiveChannelController.instance.select(1);
    service.notifyChannelCommitted();
    // 防抖窗口内再次触发 → 只发一条
    await Future<void>.delayed(const Duration(milliseconds: 300));
    LiveChannelController.instance.select(0);
    service.notifyChannelCommitted();
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
}
