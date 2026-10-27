import 'package:flutter/foundation.dart';
import 'package:pscreen_home/core/router/app_router.dart';
import 'package:pscreen_home/core/router/route_names.dart';
import 'package:pscreen_home/core/screensaver/screensaver_controller.dart';
import 'package:pscreen_home/features/home/application/bloc/home_bloc.dart';
import 'package:pscreen_home/features/home/domain/models/ha_device_group.dart';
import 'package:pscreen_screen/features/iptv/application/channel_info_provider.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/msg/application/current_scene_provider.dart';

/// 中控屏场景快照。
///
/// 中控屏没有 Tab 外壳，场景由 [AppRouter.currentPath] 决定；屏保和手动时钟
/// 共用 `/clock`，用 [ScreensaverController.active] 区分。直播频道只在
/// `/live` 场景读取，避免离开直播页后仍把旧频道写进场景。
class HomeSceneProvider extends CurrentSceneProvider {
  HomeSceneProvider({
    required AppRouter Function() router,
    required ScreensaverController Function() screensaver,
    required HomeBloc Function() homeBloc,
  })  : _router = router,
        _screensaver = screensaver,
        _homeBloc = homeBloc;

  final AppRouter Function() _router;
  final ScreensaverController Function() _screensaver;
  final HomeBloc Function() _homeBloc;

  final _SceneNotifier _notifier = _SceneNotifier();
  bool _bound = false;
  bool _disposed = false;

  @override
  Listenable get changes {
    _bind();
    return _notifier;
  }

  @override
  SceneSnapshot snapshot() {
    final String path = _router().currentPath;
    final bool screensaverActive = _screensaver().active;

    if (path == RouteNames.clockPath) {
      return SceneSnapshot(
        kind: screensaverActive ? SceneKind.screensaver : SceneKind.clock,
        route: path,
        title: screensaverActive ? '屏保' : '时钟',
        extra: <String, Object?>{'screensaverActive': screensaverActive},
      );
    }

    if (path == RouteNames.livePath) {
      final int index = LiveChannelController.instance.index;
      final String? name = ChannelInfoProvider.instance.nameAt(index);
      final String title =
          name == null || name.isEmpty ? '直播' : '直播-$name';
      return SceneSnapshot(
        kind: SceneKind.live,
        route: path,
        title: title,
        channelName: name,
        extra: <String, Object?>{'channelIndex': index},
      );
    }

    if (path == RouteNames.settingsPath) {
      return SceneSnapshot(
        kind: SceneKind.settings,
        route: path,
        title: '设置',
      );
    }

    if (path == RouteNames.weatherPath) {
      return SceneSnapshot(
        kind: SceneKind.weather,
        route: path,
        title: '天气',
      );
    }

    if (path == RouteNames.remoteControlPath) {
      return SceneSnapshot(
        kind: SceneKind.other,
        route: path,
        title: '遥控',
      );
    }

    if (path.startsWith('/${RouteNames.deviceDetail}/')) {
      final String deviceId = path.split('/').last;
      HaDeviceGroup? group;
      String? areaId;
      String? areaName;
      try {
        group = _homeBloc().state.deviceGroupOf(deviceId);
        final String entityId =
            group?.primary?.entityId ?? group?.entities.first.entityId ?? '';
        if (entityId.isNotEmpty) {
          areaId = _homeBloc().state.registry.areaIdOf(entityId);
          areaName = _homeBloc().state.registry.areaNameOf(entityId);
        }
      } catch (_) {
        // 上报不能影响页面；拿不到分组时只报设备 id。
      }
      return SceneSnapshot(
        kind: SceneKind.deviceDetail,
        route: path,
        title: group?.title ?? '设备详情',
        deviceId: deviceId,
        deviceName: group?.title,
        areaId: areaId,
        areaName: areaName,
        extra: <String, Object?>{'deviceId': deviceId},
      );
    }

    if (path == RouteNames.home) {
      return SceneSnapshot(
        kind: SceneKind.home,
        route: path,
        title: '主页',
      );
    }

    return SceneSnapshot(
      kind: SceneKind.other,
      route: path,
      title: '中控台',
    );
  }

  void _bind() {
    if (_bound || _disposed) return;
    try {
      _router().routeChanges.addListener(_notify);
      _screensaver().addListener(_notify);
      LiveChannelController.instance.addListener(_notify);
      LiveChannelController.instance.onPlayCommit.addListener(_notify);
      _bound = true;
    } catch (_) {
      // 依赖尚未注册时降级：下次取 changes 再重试，不能阻塞上报启动。
      _safe(() => _router().routeChanges.removeListener(_notify));
      _safe(() => _screensaver().removeListener(_notify));
      _safe(() => LiveChannelController.instance.removeListener(_notify));
      _safe(
        () => LiveChannelController.instance.onPlayCommit.removeListener(_notify),
      );
      _bound = false;
    }
  }

  void _notify() {
    if (_disposed) return;
    _notifier.notify();
  }

  /// 注销时释放监听；路由/屏保控制器均为全局单例，正常退出前调用即可。
  ///
  /// reset 时宿主模块可能已经先注销，取值失败不能阻断退出流程。
  void dispose() {
    if (_disposed) return;
    if (_bound) {
      _safe(() => _router().routeChanges.removeListener(_notify));
      _safe(() => _screensaver().removeListener(_notify));
      _safe(() => LiveChannelController.instance.removeListener(_notify));
      _safe(
        () => LiveChannelController.instance.onPlayCommit.removeListener(_notify),
      );
      _bound = false;
    }
    _disposed = true;
    _notifier.dispose();
  }

  void _safe(VoidCallback action) {
    try {
      action();
    } catch (_) {
      // 依赖已注销时忽略。
    }
  }
}

class _SceneNotifier extends ChangeNotifier {
  void notify() => notifyListeners();
}
