import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/core/router/app_router.dart';
import 'package:pscreen_home/core/router/route_names.dart';
import 'package:pscreen_home/features/screen/application/live_stage_controller.dart';

class _FakeRouter extends AppRouter {
  _FakeRouter(this._path);

  String _path;
  final ChangeNotifier _changes = ChangeNotifier();

  @override
  String get currentPath => _path;

  @override
  Listenable get routeChanges => _changes;

  @override
  void go(String path, {Object? extra}) {
    _path = path;
    _changes.notifyListeners();
  }

  void dispose() => _changes.dispose();
}

void main() {
  test('全屏打开时记录底层页；切悬浮回底层页；关闭回底层页', () {
    final _FakeRouter router = _FakeRouter(RouteNames.weatherPath);
    final LiveStageController controller = LiveStageController(
      router: () => router,
    );
    addTearDown(() {
      controller.dispose();
      router.dispose();
    });

    controller.openFullscreen();
    expect(controller.isFullscreen, isTrue);
    expect(controller.underlyingRoute, RouteNames.weatherPath);
    expect(router.currentPath, RouteNames.livePath);

    controller.toFloating();
    expect(controller.isFloating, isTrue);
    expect(router.currentPath, RouteNames.weatherPath);

    controller.toFullscreen();
    expect(controller.isFullscreen, isTrue);
    expect(router.currentPath, RouteNames.livePath);

    controller.close();
    expect(controller.isActive, isFalse);
    expect(router.currentPath, RouteNames.weatherPath);
  });

  test('悬浮时关闭只移除小窗，不改底层路由', () {
    final _FakeRouter router = _FakeRouter(RouteNames.settingsPath);
    final LiveStageController controller = LiveStageController(
      router: () => router,
    );
    addTearDown(() {
      controller.dispose();
      router.dispose();
    });

    controller.openFullscreen();
    controller.toFloating();
    expect(router.currentPath, RouteNames.settingsPath);

    controller.close();
    expect(controller.isActive, isFalse);
    expect(router.currentPath, RouteNames.settingsPath);
  });

  test('定时关闭指定回主页时，全屏/悬浮都会关闭并回主页', () {
    final _FakeRouter router = _FakeRouter(RouteNames.weatherPath);
    final LiveStageController controller = LiveStageController(
      router: () => router,
    );
    addTearDown(() {
      controller.dispose();
      router.dispose();
    });

    controller.openFullscreen();
    controller.close(goTo: RouteNames.home);
    expect(controller.isActive, isFalse);
    expect(router.currentPath, RouteNames.home);

    controller.openFullscreen();
    controller.toFloating();
    controller.close(goTo: RouteNames.home);
    expect(controller.isActive, isFalse);
    expect(router.currentPath, RouteNames.home);
  });

  test('本次会话记住小窗位置', () {
    final _FakeRouter router = _FakeRouter(RouteNames.home);
    final LiveStageController controller = LiveStageController(
      router: () => router,
    );
    addTearDown(() {
      controller.dispose();
      router.dispose();
    });

    expect(controller.floatingOffset, isNull);
    controller.setFloatingOffset(const Offset(120, 80));
    expect(controller.floatingOffset, const Offset(120, 80));
    controller.close();
    // 关闭直播不清位置；同一进程再次悬浮仍在原位置。
    expect(controller.floatingOffset, const Offset(120, 80));
  });

  test('悬浮时切底层页同步 underlyingRoute，回全屏再悬浮回到最新页', () {
    final _FakeRouter router = _FakeRouter(RouteNames.home);
    final LiveStageController controller = LiveStageController(
      router: () => router,
    );
    addTearDown(() {
      controller.dispose();
      router.dispose();
    });

    controller.openFullscreen();
    controller.toFloating();
    expect(controller.underlyingRoute, RouteNames.home);

    // 悬浮中切底层页（点卡片进详情 / 遥控切设置）→ 底层路由跟着更新。
    router.go(RouteNames.settingsPath);
    expect(controller.underlyingRoute, RouteNames.settingsPath);

    // 全屏时路由是 /live，不能污染 underlyingRoute。
    controller.toFullscreen();
    expect(router.currentPath, RouteNames.livePath);
    expect(controller.underlyingRoute, RouteNames.settingsPath);

    // 再回悬浮：回到最新底层页（设置），而不是打开直播前的主页。
    controller.toFloating();
    expect(router.currentPath, RouteNames.settingsPath);

    // 关闭直播也回最新底层页。
    controller.toFullscreen();
    controller.close();
    expect(router.currentPath, RouteNames.settingsPath);
  });
}
