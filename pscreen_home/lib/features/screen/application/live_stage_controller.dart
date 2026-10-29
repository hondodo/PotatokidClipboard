import 'package:flutter/widgets.dart';
import 'package:pscreen_home/core/router/app_router.dart';
import 'package:pscreen_home/core/router/route_names.dart';

/// 直播窗口的三种形态。
enum LiveStageMode {
  /// 未打开直播。
  none,

  /// 直播页铺满整个窗口（当前 `/live` 路由的语义）。
  fullscreen,

  /// 应用内悬浮小窗，盖在当前页面上方，底层页面仍可操作。
  floating,
}

/// 全局直播窗口控制器。
///
/// 直播播放器不再归属 `/live` 路由，而是由 [LiveStageHost] 挂在 Navigator
/// 之上渲染。全屏 / 悬浮只是同一棵 `LivePage` 子树的位置和尺寸变化，
/// 因此切换形态不会重新创建播放器，直播不会中断。
///
/// 路由策略：
/// - 全屏：地址切到 `/live`，保留现有路由语义（遥控端可读到直播场景）；
/// - 悬浮：地址回到 [underlyingRoute]，让底层页面恢复正常导航/上报；
/// - 关闭：全屏时回到 [underlyingRoute]，悬浮时只移除小窗。
class LiveStageController extends ChangeNotifier {
  LiveStageController({required AppRouter Function() router})
    : _router = router;

  final AppRouter Function() _router;

  /// 已绑定的路由变化源；null 表示还没绑定（router 惰性注册，首次打开
  /// 直播时才取得到）。
  Listenable? _routeChanges;

  LiveStageMode _mode = LiveStageMode.none;

  /// 打开直播前所在的页面；悬浮时作为底层页面的路由。
  String _underlyingRoute = RouteNames.home;

  /// 本次会话内记住的小窗位置；重启后为 null，回到默认右下角。
  Offset? _floatingOffset;

  LiveStageMode get mode => _mode;

  bool get isActive => _mode != LiveStageMode.none;

  bool get isFullscreen => _mode == LiveStageMode.fullscreen;

  bool get isFloating => _mode == LiveStageMode.floating;

  String get underlyingRoute => _underlyingRoute;

  Offset? get floatingOffset => _floatingOffset;

  /// 打开直播并进入全屏。
  void openFullscreen() {
    final AppRouter router = _router();
    _bindRoutes();
    final String current = router.currentPath;
    if (_mode == LiveStageMode.none) {
      _underlyingRoute = _liveLikePath(current) ? RouteNames.home : current;
    }
    _mode = LiveStageMode.fullscreen;
    if (current != RouteNames.livePath) {
      router.go(RouteNames.livePath);
    }
    notifyListeners();
  }

  /// 全屏 → 悬浮：地址回到打开直播前的页面，播放器原地缩小。
  void toFloating() {
    if (_mode != LiveStageMode.fullscreen) return;
    final AppRouter router = _router();
    _mode = LiveStageMode.floating;
    if (router.currentPath == RouteNames.livePath) {
      router.go(_underlyingRoute);
    }
    notifyListeners();
  }

  /// 悬浮 → 全屏（单击小窗）。
  void toFullscreen() {
    if (_mode == LiveStageMode.none) {
      openFullscreen();
      return;
    }
    if (_mode == LiveStageMode.fullscreen) return;
    final AppRouter router = _router();
    _mode = LiveStageMode.fullscreen;
    if (router.currentPath != RouteNames.livePath) {
      router.go(RouteNames.livePath);
    }
    notifyListeners();
  }

  /// 关闭直播。
  ///
  /// [goTo] 指定关闭后要去的页面（定时关闭回主页）；不传时全屏回
  /// [underlyingRoute]、悬浮只移除小窗。
  void close({String? goTo}) {
    final AppRouter router = _router();
    final String current = router.currentPath;
    final String target =
        goTo ?? (current == RouteNames.livePath ? _underlyingRoute : current);

    final bool wasActive = isActive;
    _mode = LiveStageMode.none;
    if (goTo != null || current == RouteNames.livePath) {
      if (current != target) router.go(target);
    }
    if (wasActive) notifyListeners();
  }

  /// 拖动结束后记录小窗位置（本次会话有效）。
  void setFloatingOffset(Offset offset) {
    if (_floatingOffset == offset) return;
    _floatingOffset = offset;
    notifyListeners();
  }

  /// `/live` 是直播专用路由，不能作为悬浮时的底层页面。
  bool _liveLikePath(String path) =>
      path == RouteNames.livePath || path.isEmpty;

  /// 绑定路由变化：悬浮时用户仍可切换底层页（点卡片进详情、遥控切天气等），
  /// 同步更新 [_underlyingRoute]，保证上报的 underlyingTitle / underlyingRoute
  /// 始终是当前底层页面，且「全屏 ⇄ 悬浮」来回切换回到最新页面。
  void _bindRoutes() {
    if (_routeChanges != null) return;
    final Listenable changes = _router().routeChanges;
    changes.addListener(_onRouteChanged);
    _routeChanges = changes;
  }

  void _onRouteChanged() {
    // 只有悬浮态才需要跟踪底层页：全屏时路由固定在 /live，关闭后不再关心。
    if (_mode != LiveStageMode.floating) return;
    final String path = _router().currentPath;
    if (_liveLikePath(path) || path == _underlyingRoute) return;
    _underlyingRoute = path;
    notifyListeners();
  }

  @override
  void dispose() {
    final Listenable? changes = _routeChanges;
    if (changes != null) {
      changes.removeListener(_onRouteChanged);
      _routeChanges = null;
    }
    super.dispose();
  }
}
