// test/features/msg/application/device_state_reporter_test.dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';
import 'package:pscreen_screen/features/iptv/application/channel_info_provider.dart';
import 'package:pscreen_screen/features/iptv/domain/models/iptv_channel.dart';
import 'package:pscreen_screen/features/msg/application/current_scene_provider.dart';
import 'package:pscreen_screen/features/msg/application/device_state_reporter.dart';
import 'package:pscreen_screen/features/msg/application/playback_state_provider.dart';

/// 假场景提供者：可随时切换快照。
class _FakeSceneProvider extends CurrentSceneProvider {
  _FakeSceneProvider(this._value);

  SceneSnapshot _value;

  set value(SceneSnapshot next) => _value = next;

  @override
  SceneSnapshot snapshot() => _value;
}

/// 假通道：记录 `sendState` 的 playback 字段，`kind` 可切换（home / tv）。
class _FakeChannel implements RealtimeChannel {
  final List<Map<String, Object?>> frames = <Map<String, Object?>>[];
  final StreamController<RealtimeConnectionState> _stateController =
      StreamController<RealtimeConnectionState>.broadcast();

  /// 本端设备类型：对应握手时声明的 `kind`。
  String kindValue = 'tv';

  @override
  bool get isConnected => true;

  @override
  String get kind => kindValue;

  @override
  Stream<RealtimeConnectionState> get connectionState =>
      _stateController.stream;

  @override
  Future<bool> sendState({
    required Map<String, Object?> scene,
    List<String>? channels,
    String? listVersion,
    Map<String, Object?>? playback,
  }) async {
    frames.add(<String, Object?>{
      'scene': scene,
      'channels': channels,
      'listVersion': listVersion,
      'playback': playback,
    });
    return true;
  }

  @override
  Future<void> dispose() => _stateController.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const SceneSnapshot _screensaver =
    SceneSnapshot(kind: SceneKind.screensaver, route: '/', title: '屏保');
const SceneSnapshot _live = SceneSnapshot(
  kind: SceneKind.live,
  route: '/live',
  title: '直播-CCTV-1',
  channelName: 'CCTV-1',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeChannel channel;
  late _FakeSceneProvider scene;
  late DeviceStateReporter reporter;

  Map<String, Object?>? lastPlayback() => channel.frames.isEmpty
      ? null
      : channel.frames.last['playback'] as Map<String, Object?>?;

  Map<String, Object?> lastSceneJson() =>
      channel.frames.last['scene'] as Map<String, Object?>;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    PlaybackStateProvider.instance.clear();
    channel = _FakeChannel();
    scene = _FakeSceneProvider(_screensaver);
    reporter = DeviceStateReporter(channel: channel, sceneProvider: scene);
    ChannelInfoProvider.instance.setChannels(<IptvChannel>[
      const IptvChannel(name: 'CCTV-1', sources: <String>['a']),
    ]);
  });

  tearDown(() async {
    reporter.stop();
    PlaybackStateProvider.instance.clear();
    ChannelInfoProvider.instance.setChannels(<IptvChannel>[]);
    await channel.dispose();
  });

  group('DeviceStateReporter 按端类型下发 playback', () {
    test('tv：非直播场景仍随 state 上报播放状态', () async {
      channel.kindValue = 'tv';
      scene.value = _screensaver;
      PlaybackStateProvider.instance.update('CCTV-1', 'play_ok');
      reporter.start();
      await pumpEventQueue();

      expect(channel.frames, isNotEmpty);
      expect(lastSceneJson()['kind'], 'screensaver');
      expect(lastPlayback()?['state'], 'play_ok');
      expect(lastPlayback()?['label'], '播放正常');
    });

    test('tv：离开直播（只 clear、无换台信号）仍沿用上次播放快照', () async {
      channel.kindValue = 'tv';
      scene.value = _screensaver;
      PlaybackStateProvider.instance.update('CCTV-1', 'play_retry');
      reporter.start();
      await pumpEventQueue();
      expect(lastPlayback()?['state'], 'play_retry');

      // 离开直播：provider 被清空，电视端不应因此丢掉「上次播放」。
      PlaybackStateProvider.instance.clear();

      expect(lastPlayback()?['state'], 'play_retry');
      expect(lastPlayback()?['channel'], 'CCTV-1');
    });

    test('tv：换台丢弃快照，新频道状态到达前不带旧频道', () async {
      channel.kindValue = 'tv';
      scene.value = _live;
      PlaybackStateProvider.instance.update('CCTV-1', 'play_ok');
      reporter.start();
      await pumpEventQueue();
      expect(lastPlayback()?['channel'], 'CCTV-1');

      // 换台序列与 reporting_service 换台分支一致：
      // 先丢快照 → clear（同步触发 push）→ update 新频道。
      reporter.clearLastPlayback();
      PlaybackStateProvider.instance.clear();
      await pumpEventQueue();
      expect(lastPlayback(), isNull,
          reason: '换台后不应再把上一频道状态当成当前');

      PlaybackStateProvider.instance.update('CCTV-2', 'play_start');
      await pumpEventQueue();
      expect(lastPlayback()?['channel'], 'CCTV-2');
      expect(lastPlayback()?['state'], 'play_start');
    });

    test('tv：从未播放过时 playback 仍为 null', () async {
      channel.kindValue = 'tv';
      scene.value = _screensaver;
      reporter.start();
      await pumpEventQueue();

      expect(channel.frames, isNotEmpty);
      expect(lastPlayback(), isNull);
    });

    test('home：非直播场景发 null，让控制端清空', () async {
      channel.kindValue = 'home';
      scene.value = _screensaver;
      PlaybackStateProvider.instance.update('CCTV-1', 'play_ok');
      reporter.start();
      await pumpEventQueue();

      expect(channel.frames, isNotEmpty);
      expect(lastSceneJson()['kind'], 'screensaver');
      expect(lastPlayback(), isNull);
    });

    test('home：直播场景正常上报播放状态', () async {
      channel.kindValue = 'home';
      scene.value = _live;
      PlaybackStateProvider.instance.update('CCTV-1', 'play_fail');
      reporter.start();
      await pumpEventQueue();

      expect(lastPlayback()?['state'], 'play_fail');
      expect(lastPlayback()?['label'], '播放失败');
    });

    test('home：直播但播放状态已清空时发 null', () async {
      channel.kindValue = 'home';
      scene.value = _live;
      reporter.start();
      await pumpEventQueue();

      expect(channel.frames, isNotEmpty);
      expect(lastPlayback(), isNull);
    });

    test('tv：stop 后重新 start 会丢弃上次快照（不跨会话残留）', () async {
      channel.kindValue = 'tv';
      scene.value = _screensaver;
      PlaybackStateProvider.instance.update('CCTV-1', 'play_ok');
      reporter.start();
      await pumpEventQueue();
      expect(lastPlayback(), isNotNull);

      reporter.stop();
      // stop 之后 provider 也已清空，重连不应再带上旧会话的播放状态。
      PlaybackStateProvider.instance.clear();
      reporter.start();
      await pumpEventQueue();

      expect(channel.frames.last['playback'], isNull);
    });
  });
}
