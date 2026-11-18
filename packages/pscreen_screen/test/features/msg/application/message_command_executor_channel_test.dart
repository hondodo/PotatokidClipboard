import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/features/iptv/application/channel_info_provider.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/iptv/domain/models/iptv_channel.dart';
import 'package:pscreen_screen/features/msg/application/message_command_executor.dart';

/// 音量 Fake（本组用例不触发音量命令）。
class _FakeVolume implements VolumeControl {
  @override
  Future<void> volumeUp() async {}

  @override
  Future<void> volumeDown() async {}

  @override
  Future<void> toggleMute() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MessageCommandExecutor executor;
  late LiveChannelController live;

  setUp(() {
    live = LiveChannelController.instance;
    live.setCount(4);
    ChannelInfoProvider.instance.setChannels(<IptvChannel>[
      const IptvChannel(name: 'CCTV-1', sources: <String>['http://a/1']),
      const IptvChannel(name: '珠江台', sources: <String>['http://a/2']),
      const IptvChannel(name: 'HBO电影', sources: <String>['http://a/3']),
      const IptvChannel(name: '凤凰卫视', sources: <String>['http://a/4']),
    ]);
    executor = MessageCommandExecutor(
      volume: _FakeVolume(),
      liveChannel: live,
      channelInfo: ChannelInfoProvider.instance,
    );
  });

  tearDown(() {
    live.setCount(0);
    ChannelInfoProvider.instance.setChannels(<IptvChannel>[]);
  });

  test('channel by name：精确匹配跳台', () {
    expect(executor.execute('channel', <String, dynamic>{'name': '珠江台'}), isTrue);
    expect(live.index, 1);
    expect(executor.execute('channel', <String, dynamic>{'name': '凤凰卫视'}), isTrue);
    expect(live.index, 3);
  });

  test('channel by name：忽略大小写（cctv1 / CCTV-1 同源）', () {
    // 频道列表里是 CCTV-1，下发 cctv-1 / cctv1 都应命中（前缀归一 + 忽略大小写）。
    expect(executor.execute('channel', <String, dynamic>{'name': 'cctv-1'}), isTrue);
    expect(live.index, 0);
    expect(executor.execute('channel', <String, dynamic>{'name': 'cctv1'}), isTrue);
    expect(live.index, 0);
    // 中文名大小写无意义，但英文混排名 hbo 电影忽略大小写仍命中。
    expect(executor.execute('channel', <String, dynamic>{'name': 'hbo电影'}), isTrue);
    expect(live.index, 2);
  });

  test('channel by name：找不到或缺参返回 false 且不切台', () {
    live.select(0);
    expect(executor.execute('channel', <String, dynamic>{'name': '不存在的台'}), isFalse);
    expect(executor.execute('channel', <String, dynamic>{}), isFalse);
    expect(executor.execute('channel', null), isFalse);
    expect(live.index, 0);
  });

  test('channel by index：按序号跳台', () {
    expect(executor.execute('channel', <String, dynamic>{'index': 2}), isTrue);
    expect(live.index, 2);
  });
}
