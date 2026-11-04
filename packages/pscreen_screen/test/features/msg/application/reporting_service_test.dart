// test/features/msg/reporting_service_test.dart
import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_screen/features/iptv/application/channel_info_provider.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/iptv/domain/models/iptv_channel.dart';
import 'package:pscreen_screen/core/parental/parental_config.dart';
import 'package:pscreen_screen/core/parental/parental_state_controller.dart';
import 'package:pscreen_screen/features/msg/application/current_scene_provider.dart';
import 'package:pscreen_screen/features/msg/application/reporting_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 假发送器：记录目标与文本。
class FakeSender implements MessageSender {
  final List<(String, String)> sent = <(String, String)>[];
  final List<(String, String, Map<String, Object?>?)> events =
      <(String, String, Map<String, Object?>?)>[];
  bool ok = true;

  @override
  Future<bool> sendText({
    required String toAccount,
    required String text,
  }) async {
    sent.add((toAccount, text));
    return ok;
  }

  @override
  Future<bool> sendEvent({
    required String toAccount,
    required String event,
    Map<String, Object?>? data,
  }) async {
    events.add((toAccount, event, data));
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

/// 可手动触发场景变化的结构化场景提供者。
class _MutableSceneProvider extends CurrentSceneProvider {
  _MutableSceneProvider(this._value);

  SceneSnapshot _value;
  final _TestNotifier _notifier = _TestNotifier();

  @override
  SceneSnapshot snapshot() => _value;

  @override
  Listenable get changes => _notifier;

  void update(SceneSnapshot value) {
    _value = value;
    _notifier.notify();
  }

  void dispose() => _notifier.dispose();
}

class _TestNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

void main() {
  late FakeSender sender;
  late ReportingService service;

  /// 开启儿童模式并选中孩子（空列表 = 明确「无人在看」）。
  Future<void> enableParental(List<String> childIds) async {
    final ParentalStateController parental = ParentalStateController.instance;
    await parental.applyConfig(
      const ParentalConfig(
        mode: 'on',
        children: <ChildProfile>[
          ChildProfile(id: 'c1', name: '甲'),
          ChildProfile(id: 'c2', name: '乙'),
        ],
      ),
    );
    await parental.setActiveChildren(childIds);
  }

  Future<void> resetParental() async {
    final ParentalStateController parental = ParentalStateController.instance;
    parental.onActiveChildrenChanged = null;
    parental.timer.onLockStateChanged = null;
    await parental.applyConfig(const ParentalConfig());
    parental.timer.configure(
      enabled: false,
      profiles: const <String, ChildProfile>{},
      quietHours: const <QuietHour>[],
      activeChildIds: const <String>[],
    );
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await resetParental();
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

  tearDown(() async {
    service.dispose();
    await resetParental();
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
      ReportingService.channelDebounce + const Duration(milliseconds: 100),
    );
    expect(sender.sent.length, 1);
    expect(sender.sent[0].$2, '切换频道：CCTV-1');
    service.stop();
  });

  test('结构化场景变化：上报 scene_changed，切台补 channel_changed', () {
    fakeAsync((FakeAsync async) {
      service.dispose();
      final _MutableSceneProvider provider = _MutableSceneProvider(
        const SceneSnapshot(kind: SceneKind.home, route: '/', title: '主页'),
      );
      service = ReportingService(
        sender: sender,
        deviceModel: () async => 'MiBOX 4',
        channelInfo: ChannelInfoProvider.instance,
        liveChannel: LiveChannelController.instance,
        sceneProvider: provider,
        now: () => DateTime(2026, 10, 15, 20, 30),
      );

      service.start('TV_001');
      async.flushMicrotasks();
      sender.sent.clear();
      sender.events.clear();

      provider.update(
        const SceneSnapshot(
          kind: SceneKind.live,
          route: '/live',
          title: '直播-CCTV-1',
          channelName: 'CCTV-1',
        ),
      );
      async.elapse(
        ReportingService.sceneDebounce + const Duration(milliseconds: 20),
      );
      async.flushMicrotasks();
      expect(sender.sent.single.$2, '场景切换：直播-CCTV-1');
      expect(sender.events.single.$2, 'scene_changed');
      expect(sender.events.single.$3?['kind'], 'live');
      expect(sender.events.single.$3?['channelName'], 'CCTV-1');

      provider.update(
        const SceneSnapshot(
          kind: SceneKind.live,
          route: '/live',
          title: '直播-CCTV-5',
          channelName: 'CCTV-5',
        ),
      );
      async.elapse(
        ReportingService.sceneDebounce + const Duration(milliseconds: 20),
      );
      async.flushMicrotasks();
      expect(sender.sent.last.$2, '场景切换：直播-CCTV-5');
      expect(sender.events[sender.events.length - 2].$2, 'scene_changed');
      expect(sender.events.last.$2, 'channel_changed');
      expect(sender.events.last.$3?['channelName'], 'CCTV-5');

      service.stop();
      provider.dispose();
    });
  });

  test('换台回调 onChannelSwitch：仅频道变化触发，离开直播场景不触发', () {
    fakeAsync((FakeAsync async) {
      service.dispose();
      int switchCalls = 0;
      final _MutableSceneProvider provider = _MutableSceneProvider(
        const SceneSnapshot(
          kind: SceneKind.live,
          route: '/live',
          title: '直播-CCTV-1',
          channelName: 'CCTV-1',
        ),
      );
      service = ReportingService(
        sender: sender,
        deviceModel: () async => 'MiBOX 4',
        channelInfo: ChannelInfoProvider.instance,
        liveChannel: LiveChannelController.instance,
        sceneProvider: provider,
        now: () => DateTime(2026, 10, 15, 20, 30),
        onChannelSwitch: () => switchCalls++,
      );

      service.start('TV_001');
      async.flushMicrotasks();

      // 首次上报（null → 频道）也走换台分支：清一次本就为空的快照，无害。
      service.notifyPlayback(
        'play_start',
        channel: 'CCTV-1',
        sourceIndex: 1,
        sourceTotal: 2,
        sourceUrl: 'a',
      );
      expect(switchCalls, 1);

      // 真正换台：频道变化再触发一次。
      service.notifyPlayback(
        'play_start',
        channel: 'CCTV-5',
        sourceIndex: 1,
        sourceTotal: 2,
        sourceUrl: 'b',
      );
      expect(switchCalls, 2);

      // 同频道状态上报不触发。
      service.notifyPlayback(
        'play_retry',
        channel: 'CCTV-5',
        sourceIndex: 1,
        sourceTotal: 2,
        sourceUrl: 'b',
        round: 1,
        reason: 'error: timeout',
      );
      expect(switchCalls, 2);

      // 离开直播（场景切到屏保，只走 provider.clear 路径）：不触发换台回调。
      provider.update(
        const SceneSnapshot(
          kind: SceneKind.screensaver,
          route: '/',
          title: '屏保',
        ),
      );
      async.elapse(
        ReportingService.sceneDebounce + const Duration(milliseconds: 20),
      );
      async.flushMicrotasks();
      expect(switchCalls, 2);

      service.stop();
      provider.dispose();
    });
  });

  test('stop 后不再发送', () async {
    service.start('TV_001');
    await pumpEventQueue();
    sender.sent.clear();
    service.stop();
    service.notifyChannelCommitted();
    await Future<void>.delayed(
      ReportingService.channelDebounce + const Duration(milliseconds: 100),
    );
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
    DateTime Function() now,
    Duration interval,
  ) {
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

  group('播放状态上报（notifyPlayback）', () {
    /// 可拨动的时钟：retry 限流窗口测试用。
    late DateTime nowValue;

    ReportingService buildPlaybackService() => ReportingService(
      sender: sender,
      deviceModel: () async => 'MiBOX 4',
      channelInfo: ChannelInfoProvider.instance,
      liveChannel: LiveChannelController.instance,
      sceneProvider: const _FakeSceneProvider('测试场景'),
      now: () => nowValue,
    );

    /// 重建并登录，清空历史事件，返回可直接调 notifyPlayback 的服务。
    Future<ReportingService> startedService() async {
      service.dispose();
      nowValue = DateTime(2026, 10, 15, 20, 30);
      service = buildPlaybackService();
      service.start('TV_001');
      await pumpEventQueue();
      sender.events.clear();
      return service;
    }

    test('play_start：同频道同源只报一次，不同源与换频道可再报', () async {
      final ReportingService svc = await startedService();

      svc.notifyPlayback(
        'play_start',
        channel: 'CCTV-5',
        sourceIndex: 1,
        sourceTotal: 2,
        sourceUrl: 'http://a.com/1.m3u8?token=secret',
      );
      svc.notifyPlayback(
        'play_start',
        channel: 'CCTV-5',
        sourceIndex: 1,
        sourceTotal: 2,
        sourceUrl: 'http://a.com/1.m3u8?token=secret',
      ); // 同源重复 → 丢弃
      svc.notifyPlayback(
        'play_start',
        channel: 'CCTV-5',
        sourceIndex: 2,
        sourceTotal: 2,
        sourceUrl: 'http://b.com/2.m3u8',
        round: 1,
      ); // 新源 → 放行
      expect(sender.events.length, 2);

      // 源地址脱敏：只留 scheme://host/path，query 里的 token 不上报。
      final Map<String, Object?> data = sender.events.last.$3!;
      expect(data['source'], 'http://b.com/2.m3u8');
      expect(data['channelName'], 'CCTV-5');
      expect(data['sourceIndex'], 2);
      expect(data['sourceTotal'], 2);
      expect(data['round'], 1);

      // 换频道 = 新上下文：同源可再次上报。
      svc.notifyPlayback(
        'play_start',
        channel: 'CCTV-1',
        sourceIndex: 1,
        sourceTotal: 2,
        sourceUrl: 'http://a.com/1.m3u8?token=secret',
      );
      expect(sender.events.length, 3);
    });

    test('play_retry：首条立即，窗口内限流，超窗再发，恢复后立刻可发', () async {
      final ReportingService svc = await startedService();

      svc.notifyPlayback(
        'play_retry',
        channel: 'CCTV-5',
        round: 1,
        reason: 'error: timeout',
        elapsed: const Duration(seconds: 2),
      );
      expect(sender.events.length, 1);
      final Map<String, Object?> first = sender.events.last.$3!;
      expect(first['reason'], 'error: timeout');
      expect(first['round'], 1);
      expect(first['elapsedMs'], 2000);

      // 窗口内（10s 后）的连续重试 → 丢弃。
      nowValue = nowValue.add(const Duration(seconds: 10));
      svc.notifyPlayback(
        'play_retry',
        channel: 'CCTV-5',
        round: 2,
        reason: 'error: timeout',
      );
      expect(sender.events.length, 1);

      // 超过 30s 限流窗口 → 再发一条（带上最新轮次）。
      nowValue = nowValue.add(const Duration(seconds: 21));
      svc.notifyPlayback(
        'play_retry',
        channel: 'CCTV-5',
        round: 5,
        reason: 'error: timeout',
      );
      expect(sender.events.length, 2);
      expect((sender.events.last.$3!)['round'], 5);

      // 恢复（play_ok）后，下一次失败首条不受旧窗口限制。
      svc.notifyPlayback(
        'play_ok',
        channel: 'CCTV-5',
        sourceIndex: 2,
        sourceTotal: 2,
      );
      expect(sender.events.length, 3);
      nowValue = nowValue.add(const Duration(seconds: 1));
      svc.notifyPlayback(
        'play_retry',
        channel: 'CCTV-5',
        round: 6,
        reason: 'error: reset',
      );
      expect(sender.events.length, 4);
    });

    test('play_ok：连续重复只报一次，失败后恢复可再报', () async {
      final ReportingService svc = await startedService();

      svc.notifyPlayback(
        'play_ok',
        channel: 'CCTV-5',
        sourceIndex: 1,
        sourceTotal: 2,
        elapsed: const Duration(seconds: 3),
      );
      expect(sender.events.length, 1);

      // 视频帧与 playing 先后各触发一次成功 → 第二条丢弃。
      svc.notifyPlayback(
        'play_ok',
        channel: 'CCTV-5',
        sourceIndex: 1,
        sourceTotal: 2,
      );
      expect(sender.events.length, 1);

      // 失败后恢复 → 作为新的状态变化放行。
      svc.notifyPlayback(
        'play_retry',
        channel: 'CCTV-5',
        round: 2,
        reason: 'error: network',
      );
      svc.notifyPlayback(
        'play_ok',
        channel: 'CCTV-5',
        sourceIndex: 2,
        sourceTotal: 2,
      );
      expect(sender.events.length, 3);
      expect(sender.events.last.$2, 'play_ok');
    });

    test('未 start（未登录）时静默不发', () {
      service.dispose();
      nowValue = DateTime(2026, 10, 15, 20, 30);
      service = buildPlaybackService();
      sender.events.clear();
      service.notifyPlayback(
        'play_start',
        channel: 'CCTV-5',
        sourceIndex: 1,
        sourceTotal: 1,
      );
      expect(sender.events, isEmpty);
    });
  });
  group('parental_watch 上报节奏', () {
    int watchCount() =>
        sender.events.where((record) => record.$2 == 'parental_watch').length;

    ReportingService buildWatchService(Duration interval) => ReportingService(
      sender: sender,
      deviceModel: () async => 'MiBOX 4',
      channelInfo: ChannelInfoProvider.instance,
      liveChannel: LiveChannelController.instance,
      sceneProvider: const _FakeSceneProvider('测试场景'),
      now: () => DateTime(2026, 10, 15, 20, 30),
      heartbeatInterval: const Duration(minutes: 5),
      parentalWatchInterval: interval,
    );

    test('登录立即报一帧，之后按 25 秒采样（与 5 分钟心跳解耦）', () async {
      await enableParental(<String>['c1']);
      fakeAsync((FakeAsync async) {
        service.dispose();
        service = buildWatchService(const Duration(milliseconds: 100));
        service.start('TV_001');
        async.flushMicrotasks();
        expect(watchCount(), 1);

        async.elapse(const Duration(milliseconds: 100));
        async.flushMicrotasks();
        expect(watchCount(), 2);

        async.elapse(const Duration(milliseconds: 400));
        async.flushMicrotasks();
        expect(watchCount(), 6); // 100/200/300/400/500ms 共 5 帧 + 登录帧
      });
    });

    test('已启用但未选孩子：仍上报 childIds: []', () async {
      await enableParental(const <String>[]);
      fakeAsync((FakeAsync async) {
        service.dispose();
        service = buildWatchService(const Duration(milliseconds: 100));
        service.start('TV_001');
        async.flushMicrotasks();
        final List<(String, String, Map<String, Object?>?)> watch = sender
            .events
            .where((record) => record.$2 == 'parental_watch')
            .toList();
        expect(watch, isNotEmpty);
        expect(watch.last.$3!['childIds'], isEmpty);
      });
    });

    test('状态变化补报去抖：连续触发只发一帧', () async {
      await enableParental(<String>['c1']);
      fakeAsync((FakeAsync async) {
        service.dispose();
        service = buildWatchService(const Duration(minutes: 5)); // 周期不干扰
        service.start('TV_001');
        async.flushMicrotasks();
        final int before = watchCount();

        service.notifyParentalStateChanged();
        service.notifyParentalStateChanged();
        service.notifyParentalStateChanged();
        async.elapse(ReportingService.parentalWatchDebounce);
        async.flushMicrotasks();
        expect(watchCount(), before + 1);
      });
    });

    test('场景变化触发立即补报', () async {
      await enableParental(<String>['c1']);
      final _MutableSceneProvider scene = _MutableSceneProvider(
        const SceneSnapshot(kind: SceneKind.live, title: '直播'),
      );
      fakeAsync((FakeAsync async) {
        service.dispose();
        service = ReportingService(
          sender: sender,
          deviceModel: () async => 'MiBOX 4',
          channelInfo: ChannelInfoProvider.instance,
          liveChannel: LiveChannelController.instance,
          sceneProvider: scene,
          now: () => DateTime(2026, 10, 15, 20, 30),
          heartbeatInterval: const Duration(minutes: 5),
          parentalWatchInterval: const Duration(minutes: 5),
        );
        service.start('TV_001');
        async.flushMicrotasks();
        final int before = watchCount();

        scene.update(
          const SceneSnapshot(kind: SceneKind.settings, title: '设置'),
        );
        async.elapse(const Duration(milliseconds: 250));
        async.elapse(ReportingService.parentalWatchDebounce);
        async.flushMicrotasks();
        expect(watchCount(), before + 1);
      });
      scene.dispose();
    });
  });
}
