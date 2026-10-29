import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/core/router/app_router.dart';
import 'package:pscreen_home/core/router/route_names.dart';
import 'package:pscreen_home/features/screen/application/live_stage_controller.dart';
import 'package:pscreen_home/features/screen/presentation/components/live_stage_host.dart';
import 'package:pscreen_home/features/screen/presentation/pages/live_page.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_bloc.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_event.dart';
import 'package:pscreen_screen/features/iptv/application/live_channel_controller.dart';
import 'package:pscreen_screen/features/iptv/domain/models/iptv_channel.dart';
import 'package:pscreen_screen/features/iptv/domain/repositories/iptv_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeIptvRepository implements IptvRepository {
  @override
  Future<List<IptvChannel>> fetchRemoteChannels() async => const <IptvChannel>[
    IptvChannel(name: 'CCTV-1', sources: <String>['http://example.com/1.m3u8']),
    IptvChannel(name: 'CCTV-5', sources: <String>['http://example.com/5.m3u8']),
  ];

  @override
  Future<List<IptvChannel>> loadDefaultRemoteChannels() async =>
      const <IptvChannel>[];

  @override
  Future<List<IptvChannel>> buildPlaylist(List<IptvChannel> remote) async =>
      remote;
}

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
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AppSettings.instance.clearAllPersisted();
    LiveChannelController.instance.setCount(0);
  });

  testWidgets('全屏 ⇄ 悬浮不重建播放器，小窗可拖动/单击回全屏，底层仍可点', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final _FakeRouter router = _FakeRouter(RouteNames.home);
    final LiveStageController controller = LiveStageController(
      router: () => router,
    );
    addTearDown(() {
      controller.dispose();
      router.dispose();
    });
    final IptvBloc bloc = IptvBloc(repository: _FakeIptvRepository());
    addTearDown(bloc.close);

    int underlyingTaps = 0;
    await tester.pumpWidget(
      BlocProvider<IptvBloc>.value(
        value: bloc,
        child: MaterialApp(
          home: LiveStageHost(
            controller: controller,
            enablePlayer: false,
            child: Scaffold(
              body: Center(
                child: ElevatedButton(
                  key: const Key('underlying'),
                  onPressed: () => underlyingTaps++,
                  child: const Text('底层页面'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // 先打开直播（LivePage 才会挂载），再加载频道，
    // 让底部浮层出现「悬浮」按钮。
    controller.openFullscreen();
    await tester.pump();
    expect(controller.isFullscreen, isTrue);
    bloc.add(const LoadIptv());
    for (int i = 0; i < 30 && find.byType(ListTile).evaluate().isEmpty; i++) {
      await tester.pump();
    }
    expect(find.byType(ListTile), findsWidgets);
    expect(find.byTooltip('悬浮'), findsOneWidget);
    final State liveState = tester.state(find.byType(LivePage));

    // 全屏 → 悬浮：仍是同一个 State，播放器不重建。
    await tester.tap(find.byTooltip('悬浮'));
    await tester.pump();
    expect(controller.isFloating, isTrue);
    expect(identical(tester.state(find.byType(LivePage)), liveState), isTrue);
    expect(find.byTooltip('悬浮'), findsNothing);

    // 默认右下角、16:9、400x225（1200 / 3）。
    final Rect floating = tester.getRect(find.byType(LivePage));
    expect(floating.width, closeTo(400, 0.01));
    expect(floating.height, closeTo(225, 0.01));
    expect(floating.right, closeTo(1200 - 24, 0.01));
    expect(floating.bottom, closeTo(900 - 24, 0.01));

    // 小窗不挡住主页中间：底层按钮仍可点击。
    await tester.tap(find.byKey(const Key('underlying')));
    expect(underlyingTaps, 1);

    // 单击小窗回全屏。
    await tester.tapAt(floating.center);
    await tester.pump();
    expect(controller.isFullscreen, isTrue);
    expect(identical(tester.state(find.byType(LivePage)), liveState), isTrue);

    // 再次悬浮后拖动，位置被记住（本次会话）。
    await tester.tap(find.byTooltip('悬浮'));
    await tester.pump();
    final Rect beforeDrag = tester.getRect(find.byType(LivePage));
    await tester.dragFrom(beforeDrag.center, const Offset(-120, -80));
    await tester.pump();
    final Rect afterDrag = tester.getRect(find.byType(LivePage));
    expect(afterDrag.left, lessThan(beforeDrag.left));
    expect(afterDrag.top, lessThan(beforeDrag.top));
    expect(controller.floatingOffset, isNotNull);
    expect(identical(tester.state(find.byType(LivePage)), liveState), isTrue);

    // 悬浮时系统返回：只关小窗，底层页面继续保留。
    await WidgetsBinding.instance.handlePopRoute();
    await tester.pump();
    expect(controller.isActive, isFalse);
    expect(find.byType(LivePage), findsNothing);
    expect(find.byKey(const Key('underlying')), findsOneWidget);
  });

  testWidgets('小窗默认位置与拖动都收在屏幕安全区内', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final _FakeRouter router = _FakeRouter(RouteNames.home);
    final LiveStageController controller = LiveStageController(
      router: () => router,
    );
    addTearDown(() {
      controller.dispose();
      router.dispose();
    });
    final IptvBloc bloc = IptvBloc(repository: _FakeIptvRepository());
    addTearDown(bloc.close);

    // 模拟带安全区（刘海/圆角/系统栏）的屏幕：左 30、上 20、右 40、下 60。
    const EdgeInsets safe = EdgeInsets.fromLTRB(30, 20, 40, 60);
    await tester.pumpWidget(
      BlocProvider<IptvBloc>.value(
        value: bloc,
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(size: Size(1200, 900), padding: safe),
            child: LiveStageHost(
              controller: controller,
              enablePlayer: false,
              child: const Scaffold(body: SizedBox.shrink()),
            ),
          ),
        ),
      ),
    );

    controller.openFullscreen();
    await tester.pump();
    controller.toFloating();
    await tester.pump();

    // 默认右下角：贴着安全区右下角再留 24 边距。
    final Rect rect = tester.getRect(find.byType(LivePage));
    expect(rect.right, closeTo(1200 - safe.right - 24, 0.01));
    expect(rect.bottom, closeTo(900 - safe.bottom - 24, 0.01));

    // 拖出安全区：夹紧到安全区左上角，不压到刘海/系统栏。
    await tester.dragFrom(rect.center, const Offset(-3000, -3000));
    await tester.pump();
    final Rect clamped = tester.getRect(find.byType(LivePage));
    expect(clamped.left, closeTo(safe.left, 0.01));
    expect(clamped.top, closeTo(safe.top, 0.01));

    // 反方向拖出右下角：同样被夹回安全区边界。
    await tester.dragFrom(clamped.center, const Offset(3000, 3000));
    await tester.pump();
    final Rect clamped2 = tester.getRect(find.byType(LivePage));
    expect(clamped2.right, closeTo(1200 - safe.right, 0.01));
    expect(clamped2.bottom, closeTo(900 - safe.bottom, 0.01));
  });
}
