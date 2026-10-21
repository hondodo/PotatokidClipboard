import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/features/iptv/application/channel_info_provider.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/iptv/domain/models/iptv_channel.dart';
import 'package:pscreen_screen/features/msg/application/message_command_executor.dart';
import 'package:pscreen_screen/features/msg/application/message_overlay_controller.dart';
import 'package:pscreen_screen/features/msg/application/message_router.dart';

/// 记录型音量 Fake（实现 VolumeControl 接口）。
class FakeVolume implements VolumeControl {
  final List<String> calls = <String>[];
  @override
  Future<void> volumeUp() async => calls.add('up');
  @override
  Future<void> volumeDown() async => calls.add('down');
  @override
  Future<void> toggleMute() async => calls.add('mute');
}

void main() {
  late MessageOverlayController overlay;
  late FakeVolume volume;
  late LiveChannelController live;
  late MessageRouter router;

  setUp(() {
    overlay = MessageOverlayController();
    overlay.deferActive = false;
    volume = FakeVolume();
    live = LiveChannelController.instance;
    live.setCount(3);
    ChannelInfoProvider.instance.setChannels(<IptvChannel>[
      const IptvChannel(name: 'CCTV-1', sources: <String>['a']),
      const IptvChannel(name: 'CCTV-5', sources: <String>['b']),
      const IptvChannel(name: '湖南卫视', sources: <String>['c']),
    ]);
    router = MessageRouter(
      overlay: overlay,
      executor: MessageCommandExecutor(
        volume: volume,
        liveChannel: live,
        channelInfo: ChannelInfoProvider.instance,
      ),
    );
  });

  tearDown(() {
    overlay.dispose();
    ChannelInfoProvider.instance.setChannels(<IptvChannel>[]);
    live.setCount(0);
  });

  test('普通文本 → 浮层', () {
    router.handleIncoming('晚饭好了');
    expect(overlay.visible, isTrue);
    expect(overlay.text, '晚饭好了');
    expect(volume.calls, isEmpty);
  });

  test('txt 信封 → 浮层（content）', () {
    router.handleIncoming('{"t":"txt","content":"你好"}');
    expect(overlay.text, '你好');
  });

  test('volume_up/volume_down/mute 命令 → 音量调用，不弹浮层', () {
    router.handleIncoming('{"t":"cmd","name":"volume_up"}');
    router.handleIncoming('{"t":"cmd","name":"volume_down"}');
    router.handleIncoming('{"t":"cmd","name":"mute"}');
    expect(volume.calls, <String>['up', 'down', 'mute']);
    expect(overlay.visible, isFalse);
  });

  test('channel 按 name 命令 → select 对应序号', () {
    router.handleIncoming('{"t":"cmd","name":"channel","args":{"name":"CCTV-5"}}');
    expect(live.index, 1);
  });

  test('channel 按 index 命令 → select（0 基）', () {
    router.handleIncoming('{"t":"cmd","name":"channel","args":{"index":2}}');
    expect(live.index, 2);
  });

  test('channel 名字不存在 → 忽略（序号不变）', () {
    router.handleIncoming('{"t":"cmd","name":"channel","args":{"name":"不存在"}}');
    expect(live.index, 0);
    expect(overlay.visible, isFalse);
  });

  test('channel 越界 index → 不崩溃且序号不变', () {
    router.handleIncoming('{"t":"cmd","name":"channel","args":{"index":99}}');
    expect(live.index, 0);
    expect(overlay.visible, isFalse);
  });

  test('channel 负数 index → 不崩溃且序号不变', () {
    router.handleIncoming('{"t":"cmd","name":"channel","args":{"index":-1}}');
    expect(live.index, 0);
    expect(overlay.visible, isFalse);
  });

  test('channel 无 args → 忽略', () {
    router.handleIncoming('{"t":"cmd","name":"channel"}');
    expect(live.index, 0);
    expect(overlay.visible, isFalse);
  });

  test('未知命令名 → 忽略不弹浮层', () {
    router.handleIncoming('{"t":"cmd","name":"fly"}');
    expect(overlay.visible, isFalse);
    expect(volume.calls, isEmpty);
  });

  test('text 命令 → 浮层', () {
    router.handleIncoming('{"t":"cmd","name":"text","args":{"content":"集合吃饭"}}');
    expect(overlay.text, '集合吃饭');
  });

  test('坏 JSON → 按普通文本弹浮层', () {
    router.handleIncoming('{broken');
    expect(overlay.text, '{broken');
  });
}
