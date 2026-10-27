import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/core/di/scene/home_scene_provider.dart';
import 'package:pscreen_home/core/router/app_router.dart';
import 'package:pscreen_home/core/router/route_names.dart';
import 'package:pscreen_home/core/screensaver/screensaver_controller.dart';
import 'package:pscreen_home/core/storage/settings_store.dart';
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
    final HomeSceneProvider provider = HomeSceneProvider(
      router: () => router,
      screensaver: () => screensaver,
      homeBloc: () => throw StateError('本用例不读取设备详情分组'),
    );
    addTearDown(() {
      provider.dispose();
      screensaver.dispose();
      router.dispose();
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
    final SceneSnapshot live = provider.snapshot();
    expect(live.kind, SceneKind.live);
    expect(live.title, '直播-CCTV-5');
    expect(live.channelName, 'CCTV-5');

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

  test('路由、屏保、频道变化都会通知场景监听者', () {
    final _FakeAppRouter router = _FakeAppRouter(RouteNames.home);
    final ScreensaverController screensaver = ScreensaverController(
      _FakeSettingsStore(),
    );
    final HomeSceneProvider provider = HomeSceneProvider(
      router: () => router,
      screensaver: () => screensaver,
      homeBloc: () => throw StateError('本用例不读取设备详情分组'),
    );
    addTearDown(() {
      provider.dispose();
      screensaver.dispose();
      router.dispose();
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
  });
}
