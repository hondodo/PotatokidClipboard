import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:potatokid_screen/core/router/route_names.dart';
import 'package:potatokid_screen/core/router/route_params.dart';
import 'package:potatokid_screen/features/app/presentation/pages/main_app.dart';
import 'package:potatokid_screen/features/home/presentation/pages/home_detail_page.dart';
import 'package:potatokid_screen/features/home/presentation/pages/home_page.dart';
import 'package:potatokid_screen/features/profile/presentation/pages/profile_page.dart';
import 'package:potatokid_screen/features/screensaver/presentation/pages/screensaver_page.dart';
import 'package:potatokid_screen/features/settings/presentation/pages/settings_sheet_page.dart';
import 'package:potatokid_screen/features/time/presentation/pages/time_page.dart';

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
    final couldAutoLogin = await _resolveAutoLogin();
    _router = _createRouter(couldAutoLogin);
  }

  GlobalKey<NavigatorState> get navigatorKey => _navigatorKey;

  GoRouter get router {
    if (_router == null) {
      throw StateError('AppRouter 尚未初始化，请先调用 initialize()');
    }
    return _router!;
  }

  /// 预留：读取本地 Token 判断是否自动登录，决定 initialLocation
  Future<bool> _resolveAutoLogin() async => false;

  String get _initialLocation => RouteNames.home;

  GoRouter _createRouter(bool couldAutoLogin) {
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
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainApp(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: RouteNames.home,
                name: RouteNames.home,
                pageBuilder: (context, state) =>
                    _buildShellTabPage(state: state, child: const HomePage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: RouteNames.time,
                name: RouteNames.time,
                pageBuilder: (context, state) =>
                    _buildShellTabPage(state: state, child: const TimePage()),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: RouteNames.screensaver,
                name: RouteNames.screensaver,
                pageBuilder: (context, state) => _buildShellTabPage(
                  state: state,
                  child: const ScreensaverPage(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: RouteNames.profile,
                name: RouteNames.profile,
                pageBuilder: (context, state) => _buildShellTabPage(
                  state: state,
                  child: const ProfilePage(),
                ),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: RouteNames.homeDetail,
        name: RouteNames.homeDetail,
        builder: (context, state) {
          final params = state.extra is HomeDetailParams
              ? state.extra! as HomeDetailParams
              : HomeDetailParams.fromMap(
                  (state.extra as Map<String, dynamic>?) ?? <String, dynamic>{},
                );
          return HomeDetailPage(params: params);
        },
      ),
      GoRoute(
        path: RouteNames.settingsSheet,
        name: RouteNames.settingsSheet,
        pageBuilder: (context, state) {
          final params = state.extra is SettingsSheetParams
              ? state.extra! as SettingsSheetParams
              : SettingsSheetParams.fromMap(
                  (state.extra as Map<String, dynamic>?) ?? <String, dynamic>{},
                );
          return _buildSheetPage(
            state: state,
            child: SettingsSheetPage(params: params),
          );
        },
      ),
    ];
  }

  NoTransitionPage _buildShellTabPage({
    required GoRouterState state,
    required Widget child,
  }) =>
      NoTransitionPage(key: state.pageKey, child: child);

  Page<void> _buildSheetPage({
    required GoRouterState state,
    required Widget child,
  }) {
    return CustomTransitionPage<void>(
      key: state.pageKey,
      fullscreenDialog: true,
      opaque: false,
      barrierColor: Colors.black54,
      child: child,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final offset = Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));
        return SlideTransition(position: offset, child: child);
      },
    );
  }

  Widget _buildErrorPage(BuildContext context, GoRouterState state) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text('页面不存在: ${state.uri}'),
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

  // ---------------- 通用导航封装 ----------------

  void go(String location, {Object? extra}) => router.go(location, extra: extra);

  void goNamed(
    String name, {
    Map<String, String> pathParameters = const <String, String>{},
    Object? extra,
  }) =>
      router.goNamed(name, pathParameters: pathParameters, extra: extra);

  Future<T?> push<T>(String location, {Object? extra}) =>
      router.push<T>(location, extra: extra);

  Future<T?> pushNamed<T>(
    String name, {
    Map<String, String> pathParameters = const <String, String>{},
    Object? extra,
  }) =>
      router.pushNamed<T>(name, pathParameters: pathParameters, extra: extra);

  void pop<T>([T? result]) => router.pop<T>(result);

  bool canPop() => router.canPop();

  bool isCurrentRouteName(String name) {
    final state = router.state;
    return state.matchedLocation == name || state.name == name;
  }

  // ---------------- 类型安全导航 ----------------

  Future<void> pushHomeDetail(HomeDetailParams params) =>
      push(RouteNames.homeDetail, extra: params);

  Future<void> pushSettingsSheet(SettingsSheetParams params) =>
      push(RouteNames.settingsSheet, extra: params);
}
