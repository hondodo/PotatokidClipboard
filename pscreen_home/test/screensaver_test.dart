import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pscreen_home/app/screensaver_host.dart';
import 'package:pscreen_home/core/router/app_router.dart';
import 'package:pscreen_home/core/router/route_names.dart';
import 'package:pscreen_home/core/screensaver/screensaver_controller.dart';
import 'package:pscreen_home/core/storage/settings_store.dart';

class _FakeSettingsStore extends SettingsStore {
  _FakeSettingsStore(this.minutes);

  int minutes;

  @override
  int get screensaverMinutes => minutes;

  @override
  Future<void> saveScreensaverMinutes(int value) async {
    minutes = value;
  }
}

class _FakeAppRouter extends AppRouter {
  _FakeAppRouter(this._path);

  String _path;
  final ChangeNotifier _changes = ChangeNotifier();
  final List<String> pushed = <String>[];

  @override
  String get currentPath => _path;

  @override
  Listenable get routeChanges => _changes;

  @override
  void push(String path, {Object? extra}) {
    pushed.add(path);
    _path = path;
    _changes.notifyListeners();
  }

  void setPath(String path) {
    _path = path;
    _changes.notifyListeners();
  }

  void dispose() => _changes.dispose();
}

Future<void> _pumpHost(
  WidgetTester tester,
  _FakeAppRouter router,
  ScreensaverController controller,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ScreensaverHost(
        router: router,
        controller: controller,
        child: const Scaffold(body: SizedBox.expand()),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _disposeHost(WidgetTester tester, _FakeAppRouter router) async {
  await tester.pumpWidget(const SizedBox.shrink());
  router.dispose();
}

void main() {
  test('AppRouter.currentPath 使用 push 后的顶部路由', () async {
    final AppRouter router = AppRouter();
    await router.initialize();
    addTearDown(router.router.dispose);

    expect(router.currentPath, RouteNames.home);

    router.push(RouteNames.clockPath);
    expect(router.currentPath, RouteNames.clockPath);

    router.push(RouteNames.settingsPath);
    expect(router.currentPath, RouteNames.settingsPath);
  });

  testWidgets('顶部路由路径在 Navigator.pop 后回退', (WidgetTester tester) async {
    final GoRouter router = GoRouter(
      initialLocation: '/',
      routes: <RouteBase>[
        GoRoute(
          path: '/',
          builder: (BuildContext context, GoRouterState state) =>
              const Text('home'),
          routes: <RouteBase>[
            GoRoute(
              path: 'clock',
              builder: (BuildContext context, GoRouterState state) =>
                  const Text('clock'),
            ),
          ],
        ),
      ],
    );

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    router.push('/clock');
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.last.matchedLocation,
      '/clock',
    );

    Navigator.of(tester.element(find.text('clock'))).maybePop();
    await tester.pumpAndSettle();
    expect(
      router.routerDelegate.currentConfiguration.last.matchedLocation,
      '/',
    );

    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
  });

  test('ScreensaverController 更新分钟数并通知', () async {
    final _FakeSettingsStore store = _FakeSettingsStore(10);
    final ScreensaverController controller = ScreensaverController(store);
    int notifications = 0;
    controller.addListener(() => notifications++);

    await controller.setMinutes(15);
    expect(controller.minutes, 15);
    expect(store.minutes, 15);
    expect(notifications, 1);

    await controller.setMinutes(7);
    expect(controller.minutes, 15);
    expect(store.minutes, 15);
    expect(notifications, 1);

    await controller.setMinutes(SettingsStore.screensaverNeverMinutes);
    expect(controller.minutes, SettingsStore.screensaverNeverMinutes);
    expect(store.minutes, SettingsStore.screensaverNeverMinutes);
    expect(notifications, 2);

    await controller.setMinutes(15);
    expect(notifications, 3);
  });

  testWidgets('屏保选择「从不」后不进入时钟页', (WidgetTester tester) async {
    final _FakeAppRouter router = _FakeAppRouter(RouteNames.home);
    final ScreensaverController controller = ScreensaverController(
      _FakeSettingsStore(SettingsStore.screensaverNeverMinutes),
    );

    await _pumpHost(tester, router, controller);
    await tester.pump(const Duration(hours: 2));
    expect(router.pushed, isEmpty);

    await _disposeHost(tester, router);
  });

  testWidgets('非直播页空闲后进入时钟屏保', (WidgetTester tester) async {
    final _FakeAppRouter router = _FakeAppRouter(RouteNames.home);
    final ScreensaverController controller = ScreensaverController(
      _FakeSettingsStore(1),
    );

    await _pumpHost(tester, router, controller);
    await tester.pump(const Duration(seconds: 30));
    expect(router.pushed, isEmpty);

    await tester.pump(const Duration(seconds: 31));
    expect(router.pushed, <String>[RouteNames.clockPath]);

    await _disposeHost(tester, router);
  });

  testWidgets('直播页与时钟页不触发屏保', (WidgetTester tester) async {
    final _FakeAppRouter live = _FakeAppRouter(RouteNames.livePath);
    final ScreensaverController liveController = ScreensaverController(
      _FakeSettingsStore(1),
    );
    await _pumpHost(tester, live, liveController);
    await tester.pump(const Duration(minutes: 2));
    expect(live.pushed, isEmpty);
    await _disposeHost(tester, live);

    final _FakeAppRouter clock = _FakeAppRouter(RouteNames.clockPath);
    final ScreensaverController clockController = ScreensaverController(
      _FakeSettingsStore(1),
    );
    await _pumpHost(tester, clock, clockController);
    await tester.pump(const Duration(minutes: 2));
    expect(clock.pushed, isEmpty);
    await _disposeHost(tester, clock);
  });

  testWidgets('触摸会重置屏保计时', (WidgetTester tester) async {
    final _FakeAppRouter router = _FakeAppRouter(RouteNames.home);
    final ScreensaverController controller = ScreensaverController(
      _FakeSettingsStore(1),
    );
    await _pumpHost(tester, router, controller);

    await tester.pump(const Duration(seconds: 30));
    await tester.tapAt(const Offset(400, 300));
    await tester.pump();
    await tester.pump(const Duration(seconds: 30));
    expect(router.pushed, isEmpty);

    await tester.pump(const Duration(seconds: 31));
    expect(router.pushed, <String>[RouteNames.clockPath]);

    await _disposeHost(tester, router);
  });

  testWidgets('离开直播页后重新开始计时', (WidgetTester tester) async {
    final _FakeAppRouter router = _FakeAppRouter(RouteNames.livePath);
    final ScreensaverController controller = ScreensaverController(
      _FakeSettingsStore(1),
    );
    await _pumpHost(tester, router, controller);

    await tester.pump(const Duration(minutes: 2));
    expect(router.pushed, isEmpty);

    router.setPath(RouteNames.home);
    await tester.pump();
    await tester.pump(const Duration(seconds: 61));
    expect(router.pushed, <String>[RouteNames.clockPath]);

    await _disposeHost(tester, router);
  });

  testWidgets('修改屏保时长后按新时长重新计时', (WidgetTester tester) async {
    final _FakeAppRouter router = _FakeAppRouter(RouteNames.home);
    final ScreensaverController controller = ScreensaverController(
      _FakeSettingsStore(10),
    );
    await _pumpHost(tester, router, controller);

    await tester.pump(const Duration(minutes: 5));
    await controller.setMinutes(1);
    await tester.pump(const Duration(seconds: 30));
    expect(router.pushed, isEmpty);

    await tester.pump(const Duration(seconds: 31));
    expect(router.pushed, <String>[RouteNames.clockPath]);

    await _disposeHost(tester, router);
  });
}
