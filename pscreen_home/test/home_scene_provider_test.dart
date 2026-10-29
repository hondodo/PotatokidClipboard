import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/core/di/scene/home_scene_provider.dart';
import 'package:pscreen_home/core/router/app_router.dart';
import 'package:pscreen_home/core/router/route_names.dart';
import 'package:pscreen_home/core/screensaver/screensaver_controller.dart';
import 'package:pscreen_home/core/storage/settings_store.dart';
import 'package:pscreen_home/features/screen/application/live_stage_controller.dart';
import 'package:pscreen_screen/features/iptv/application/channel_info_provider.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/iptv/domain/models/iptv_channel.dart';
import 'package:pscreen_screen/features/msg/application/current_scene_provider.dart';

class _FakeSettingsStore extends SettingsStore {
  @override
  int get screensaverMinutes => 10;

  @override
  Future<void> saveScreensaverMinutes(int value) async {}
}

class _Notifier extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// 场景上报只关心这三个 getter，避免测试里初始化真实 AppRouter。
class _FakeLiveStage extends LiveStageController {
  _FakeLiveStage() : super(router: () => throw StateError('测试不导航'));

  bool active = false;
  bool floating = false;
  String underlying = RouteNames.home;

  @override
  bool get isActive => active;

  @override
  bool get isFloating => floating;

  @override
  String get underlyingRoute => underlying;

  void notify() => notifyListeners();
}

class _FakeAppRouter extends AppRouter {
  _FakeAppRouter(this._path);

  String _path;
  final _Notifier _changes = _Notifier();

  @override
  String get currentPath => _path;

  @override
  Listenable get routeChanges => _changes;

  void setPath(String path) {
    _path = path;
    _changes.notify();
  }

  void dispose() => _changes.dispose();
}

void main() {
  test('按路由映射场景，并用 active 区分屏保与手动时钟', () {
    final _FakeAppRouter router = _FakeAppRouter(RouteNames.home);
    final ScreensaverController screensaver = ScreensaverController(
      _FakeSettingsStore(),
    );
    final _FakeLiveStage live = _FakeLiveStage();
    final HomeSceneProvider provider = HomeSceneProvider(
      router: () => router,
      screensaver: () => screensaver,
      homeBloc: () => throw StateError('本用例不读取设备详情分组'),
      live: () => live,
    );
    addTearDown(() {
      provider.dispose();
      screensaver.dispose();
      router.dispose();
      live.dispose();
      ChannelInfoProvider.instance.setChannels(<IptvChannel>[]);
      LiveChannelController.instance.setCount(0);
    });

    expect(provider.snapshot().kind, SceneKind.home);
    expect(provider.snapshot().title, '主页');

    ChannelInfoProvider.instance.setChannels(<IptvChannel>[
      const IptvChannel(name: 'CCTV-1', sources: <String>['a']),
      const IptvChannel(name: 'CCTV-5', sources: <String>['b']),
    ]);
    LiveChannelController.instance.setCount(2);
    LiveChannelController.instance.select(1);
    router.setPath(RouteNames.livePath);
    final SceneSnapshot liveSnapshot = provider.snapshot();
    expect(liveSnapshot.kind, SceneKind.live);
    expect(liveSnapshot.title, '直播-CCTV-5');
    expect(liveSnapshot.channelName, 'CCTV-5');

    router.setPath(RouteNames.clockPath);
    expect(provider.snapshot().kind, SceneKind.clock);
    expect(provider.snapshot().title, '时钟');

    screensaver.active = true;
    expect(provider.snapshot().kind, SceneKind.screensaver);
    expect(provider.snapshot().title, '屏保');

    router.setPath(RouteNames.settingsPath);
    expect(provider.snapshot().kind, SceneKind.settings);
    expect(provider.snapshot().title, '设置');

    router.setPath(RouteNames.weatherPath);
    expect(provider.snapshot().kind, SceneKind.weather);
    expect(provider.snapshot().title, '天气');

    router.setPath(RouteNames.deviceDetailPath('light.1'));
    final SceneSnapshot detail = provider.snapshot();
    expect(detail.kind, SceneKind.deviceDetail);
    expect(detail.deviceId, 'light.1');
    expect(detail.title, '设备详情');
  });

  test('悬浮直播仍报 live，并带 underlyingTitle / underlyingRoute', () {
    final _FakeAppRouter router = _FakeAppRouter(RouteNames.home);
    final ScreensaverController screensaver = ScreensaverController(
      _FakeSettingsStore(),
    );
    final _FakeLiveStage live = _FakeLiveStage();
    final HomeSceneProvider provider = HomeSceneProvider(
      router: () => router,
      screensaver: () => screensaver,
      homeBloc: () => throw StateError('本用例不读取设备详情分组'),
      live: () => live,
    );
    addTearDown(() {
      provider.dispose();
      screensaver.dispose();
      router.dispose();
      live.dispose();
      ChannelInfoProvider.instance.setChannels(<IptvChannel>[]);
      LiveChannelController.instance.setCount(0);
    });

    ChannelInfoProvider.instance.setChannels(<IptvChannel>[
      const IptvChannel(name: 'CCTV-1', sources: <String>['a']),
      const IptvChannel(name: 'CCTV-5', sources: <String>['b']),
    ]);
    LiveChannelController.instance.setCount(2);
    LiveChannelController.instance.select(1);

    // 悬浮在天气页上方：route 报底层页面，kind/title 仍是直播。
    live
      ..active = true
      ..floating = true
      ..underlying = RouteNames.weatherPath;
    router.setPath(RouteNames.weatherPath);
    final SceneSnapshot floating = provider.snapshot();
    expect(floating.kind, SceneKind.live);
    expect(floating.title, '直播-CCTV-5');
    expect(floating.route, RouteNames.weatherPath);
    expect(floating.extra['floating'], isTrue);
    expect(floating.extra['underlyingRoute'], RouteNames.weatherPath);
    expect(floating.extra['underlyingTitle'], '天气');

    // 回到全屏：route 回到 /live，不再带底层页信息。
    live.floating = false;
    router.setPath(RouteNames.livePath);
    final SceneSnapshot fullscreen = provider.snapshot();
    expect(fullscreen.kind, SceneKind.live);
    expect(fullscreen.route, RouteNames.livePath);
    expect(fullscreen.extra['floating'], isFalse);
    expect(fullscreen.extra['underlyingRoute'], RouteNames.weatherPath);
    expect(fullscreen.extra['underlyingTitle'], '天气');
  });

  test('路由、屏保、频道变化都会通知场景监听者', () {
    final _FakeAppRouter router = _FakeAppRouter(RouteNames.home);
    final ScreensaverController screensaver = ScreensaverController(
      _FakeSettingsStore(),
    );
    final _FakeLiveStage live = _FakeLiveStage();
    final HomeSceneProvider provider = HomeSceneProvider(
      router: () => router,
      screensaver: () => screensaver,
      homeBloc: () => throw StateError('本用例不读取设备详情分组'),
      live: () => live,
    );
    addTearDown(() {
      provider.dispose();
      screensaver.dispose();
      router.dispose();
      live.dispose();
      ChannelInfoProvider.instance.setChannels(<IptvChannel>[]);
      LiveChannelController.instance.setCount(0);
    });

    int changes = 0;
    provider.changes.addListener(() => changes++);

    router.setPath(RouteNames.weatherPath);
    expect(changes, 1);

    screensaver.active = true;
    expect(changes, 2);

    LiveChannelController.instance.setCount(2);
    expect(changes, 3);

    live.notify();
    expect(changes, 4);
  });
}
