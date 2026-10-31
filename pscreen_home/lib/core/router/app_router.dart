import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pscreen_home/core/router/route_names.dart';
import 'package:pscreen_home/features/home/presentation/pages/device_detail_page.dart';
import 'package:pscreen_home/features/home/presentation/pages/home_controll_board.dart';
import 'package:pscreen_home/features/remote_control/presentation/remote_control_page.dart';
import 'package:pscreen_home/features/screen/presentation/components/live_stage_host.dart';
import 'package:pscreen_home/features/screen/presentation/pages/clock_page.dart';
import 'package:pscreen_home/features/screen/presentation/pages/weather_page.dart';
import 'package:pscreen_home/features/settings/presentation/pages/settings_page.dart';

/// 路由核心：封装 GoRouter。
///
/// 使用方式：
/// 1. `await Injection.get<AppRouter>().initialize();`（必须在 runApp 前）
/// 2. `MaterialApp.router(routerConfig: appRouter.router)`
class AppRouter {
  AppRouter();

  GoRouter? _router;

  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final RouteObserver<ModalRoute<void>> routeObserver =
      RouteObserver<ModalRoute<void>>();

  Future<void> initialize() async {
    if (_router != null) return;
    _router = _createRouter();
  }

  GlobalKey<NavigatorState> get navigatorKey => _navigatorKey;

  /// 当前路由路径（不含 query / fragment），供屏保等全局逻辑判断页面。
  ///
  /// 不能用 `currentConfiguration.uri`：它保存的是基础路由（`go` 的地址），
  /// `push` 后仍是旧路径；也不能只看 `routeInformationProvider`，因为通过
  /// `Navigator.pop` 返回时它不会同步。`currentConfiguration.last` 同时涵盖
  /// 普通路由和 push 出来的顶部路由，push / pop 后都会更新。
  String get currentPath {
    final RouteMatchList config = router.routerDelegate.currentConfiguration;
    if (config.isEmpty) {
      return router.routeInformationProvider.value.uri.path;
    }
    return config.last.matchedLocation;
  }

  /// 路由变化通知（push / pop / replace）。
  Listenable get routeChanges => router.routerDelegate;

  GoRouter get router {
    if (_router == null) {
      throw StateError('AppRouter 尚未初始化，请先调用 initialize()');
    }
    return _router!;
  }

  String get _initialLocation => RouteNames.home;

  GoRouter _createRouter() {
    return GoRouter(
      navigatorKey: _navigatorKey,
      initialLocation: _initialLocation,
      observers: <NavigatorObserver>[routeObserver],
      routes: _buildRoutes(),
      errorBuilder: _buildErrorPage,
    );
  }

  List<RouteBase> _buildRoutes() {
    return <RouteBase>[
      GoRoute(
        path: RouteNames.home,
        name: RouteNames.home,
        builder: (context, state) => const HomeControllBoard(),
        routes: <RouteBase>[
          GoRoute(
            path: RouteNames.deviceDetailRelative,
            name: RouteNames.deviceDetail,
            builder: (context, state) => DeviceDetailPage(
              deviceId: state.pathParameters['deviceId'] ?? '',
            ),
          ),
          GoRoute(
            path: RouteNames.remoteControl,
            name: RouteNames.remoteControl,
            builder: (context, state) => const RemoteControlPage(),
          ),
          GoRoute(
            path: RouteNames.clock,
            name: RouteNames.clock,
            builder: (context, state) => const ClockPage(),
          ),
          GoRoute(
            path: RouteNames.live,
            name: RouteNames.live,
            // 播放器由全局 LiveStageHost 渲染；这里只是路由占位，
            // 避免 Navigator 里再创建第二个播放器。
            builder: (context, state) => const LiveRouteEntry(),
          ),
          GoRoute(
            path: RouteNames.weather,
            name: RouteNames.weather,
            builder: (context, state) => const WeatherPage(),
          ),
          GoRoute(
            path: RouteNames.settings,
            name: RouteNames.settings,
            builder: (context, state) => const SettingsPage(),
          ),
        ],
      ),
    ];
  }

  Widget _buildErrorPage(BuildContext context, GoRouterState state) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Text('页面不存在'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () => go(RouteNames.home),
              child: const Text('返回首页'),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------- 导航封装

  void go(String path, {Object? extra}) => router.go(path, extra: extra);

  void goNamed(String name, {Object? extra}) =>
      router.goNamed(name, extra: extra);

  void push(String path, {Object? extra}) => router.push(path, extra: extra);

  void pop() => router.pop();

  bool canPop() => router.canPop();
}
