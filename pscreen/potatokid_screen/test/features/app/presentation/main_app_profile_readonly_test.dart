import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:potatokid_screen/core/di/injection.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_bloc.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_event.dart';
import 'package:potatokid_screen/features/app/presentation/pages/main_app.dart';
import 'package:potatokid_screen/features/profile/presentation/pages/profile_page.dart';
import 'package:potatokid_screen/features/profile/presentation/pages/profile_readonly_page.dart';
import 'package:pscreen_screen/core/media/kid_watch_timer_controller.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';
import 'package:pscreen_screen/core/parental/parental_config.dart';
import 'package:pscreen_screen/core/parental/parental_state_controller.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';
import 'package:pscreen_screen/features/remote/application/bloc/remote_login_bloc.dart';
import 'package:pscreen_screen/features/remote/domain/repositories/remote_login_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

GoRouter? _router;

/// 儿童模式阶段 4：儿童模式生效时「我的」Tab 整页替换为只读页。
///
/// 驱动方式：真实 `GoRouter` 壳 pump 真实 [MainApp]（分支 0-1 用占位页，
/// 分支 2 挂真实 [ProfilePage]），走 `MainApp._profileReadonly` 判定式与
/// `IndexedStack` 翻转；翻译经磁盘 zh-CN JSON 注入（不依赖测试资产 bundle）。
///
/// 断言依据：`IndexedStack` 非选中子树不入 onstage 树（finder 默认
/// `skipOffstage: true`），因此只读态下原页 [ProfilePage] 及其危险行
/// （「重置」「远程」等）不可被 find 到，等价于不可达。
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await EasyLocalization.ensureInitialized();
    _registerAssetMock();
    await Injection.init();
    // 预热 AppSettings：确保 _loading 在建 AppBloc 前完成，否则其
    // _loadPersistedSettings 的 add() 会落在 bloc close 之后（StateError）。
    await AppSettings.instance.ensureLoaded();
    await ParentalStateController.instance
        .saveLocalConfig(const ParentalConfig());
    _resetTimer();
  });

  tearDown(() async {
    _resetTimer();
    await ParentalStateController.instance
        .saveLocalConfig(const ParentalConfig());
    await Injection.reset();
  });

  testWidgets('儿童模式生效：我的整页替换为只读页，原设置行不可达',
      (WidgetTester tester) async {
    await _pumpApp(tester, location: '/profile');

    // 基线（判定式不成立）：原页在场，危险行可滚动到位。
    expect(ParentalStateController.instance.enabled, isFalse);
    expect(find.byType(ProfilePage), findsOneWidget);
    expect(find.byType(ProfileReadonlyPage), findsNothing);
    expect(find.text('主题'), findsOneWidget);

    await tester.drag(find.byType(ProfilePage), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text('重置'), findsOneWidget, reason: '基线：原页「重置」危险行滚动可达');

    // 打开儿童模式 → MainApp._profileReadonly 翻转 → IndexedStack 切到只读页。
    await ParentalStateController.instance.saveLocalConfig(
      const ParentalConfig(
        mode: 'on',
        children: <ChildProfile>[
          ChildProfile(id: 'c1', name: '小宝', sessionLimitMin: 10),
        ],
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byType(ProfileReadonlyPage), findsOneWidget);
    expect(find.text('儿童模式已开启'), findsOneWidget);
    expect(find.text('请求解锁'), findsOneWidget);
    expect(find.byType(ProfilePage), findsNothing, reason: '原页整页被替换');
    expect(find.text('重置'), findsNothing, reason: '原页危险行不可达');
    expect(find.text('远程'), findsNothing, reason: '原页危险行不可达');

    await _unmount(tester);
  });

  testWidgets('判定式不成立：我的渲染原设置页（现状不变）', (WidgetTester tester) async {
    await _pumpApp(tester, location: '/profile');

    expect(ParentalStateController.instance.enabled, isFalse);
    expect(find.byType(ProfileReadonlyPage), findsNothing);
    expect(find.text('儿童模式已开启'), findsNothing);

    expect(find.byType(ProfilePage), findsOneWidget);
    expect(find.text('主题'), findsOneWidget);

    await tester.drag(find.byType(ProfilePage), const Offset(0, -2000));
    await tester.pumpAndSettle();
    expect(find.text('重置'), findsOneWidget, reason: '原页危险行可达');
    expect(find.text('远程'), findsOneWidget, reason: '原页危险行可达');

    await _unmount(tester);
  });

  testWidgets('锁屏期间根按键吞键：不触发 Tab 切换（含未锁对照）',
      (WidgetTester tester) async {
    await _pumpApp(tester, location: '/');
    // 注意：切 Tab 会重建 StatefulShellRoute，shell widget 实例随之更新
    //（MainApp.current 在每次 build 覆写），故断言须动态读取 MainApp.current，
    // 缓存旧实例会读到过期的 currentIndex。
    expect(MainApp.current!.currentIndex, 0);

    // 对照：未锁时左右键经根分发正常切 Tab（证明按键链路本身是通的）。
    // 焦点由 home 分支的 autofocus 节点落位（在 MainApp 子树内），按键
    // 沿 focus 链冒泡到根 Focus 的 _handleRootKey 分发。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.pump();
    expect(MainApp.current!.currentIndex, 1,
        reason: '未锁时左右键应切换 Tab');
    // 切到非「我的」页后导航条自动收起（顶部条不再常显），
    // 需先重新呼出才能继续用左右键切页。
    tester
        .element(find.byType(MainApp))
        .read<AppBloc>()
        .add(const SetChrome(true));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    await tester.pump();
    expect(MainApp.current!.currentIndex, 0);

    // 计到阈值进锁屏（与阶段 2/3 用例同法：逐秒 ticker 累加）。
    final KidWatchTimerController timer = KidWatchTimerController.instance;
    timer.configure(
      enabled: true,
      profiles: <String, ChildProfile>{
        'c1': const ChildProfile(id: 'c1', name: '小宝', sessionLimitMin: 1),
      },
      quietHours: const <QuietHour>[],
      activeChildIds: const <String>['c1'],
    );
    await tester.pump(const Duration(seconds: 61));
    await tester.pump();
    expect(timer.locked, isTrue);

    // 锁屏等待期导航条已自动收起 → 重新呼出，保持与对照组相同的按键条件。
    tester
        .element(find.byType(MainApp))
        .read<AppBloc>()
        .add(const SetChrome(true));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(MainApp.current!.currentIndex, 0,
        reason: '锁屏吞键，不触发 Tab 切换');

    await _unmount(tester);
  });
}

/// 用真实 [GoRouter] 壳 pump [MainApp]：分支 0-1 占位页，分支 2 真实 [ProfilePage]。
Future<void> _pumpApp(WidgetTester tester, {required String location}) async {
  _router = GoRouter(
    initialLocation: location,
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder:
            (BuildContext context, GoRouterState state,
                    StatefulNavigationShell shell) =>
                MainApp(navigationShell: shell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/',
                builder: (BuildContext context, GoRouterState state) =>
                    // 模拟真机内容区的可聚焦节点：焦点经路由 ModalScope 下穿
                    // 落位到分支内，按键才能沿 focus 链冒泡到 MainApp 根分发。
                    Focus(
                      autofocus: true,
                      child: const SizedBox(key: Key('home-branch')),
                    ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/time',
                builder: (BuildContext context, GoRouterState state) =>
                    const SizedBox(key: Key('time-branch')),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/profile',
                builder: (BuildContext context, GoRouterState state) =>
                    const ProfilePage(),
              ),
            ],
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const <Locale>[
        Locale('zh', 'CN'),
        Locale('zh', 'TW'),
        Locale('en', 'US'),
        Locale('ja', 'JP'),
      ],
      path: 'assets/translations',
      fallbackLocale: const Locale('zh', 'CN'),
      startLocale: const Locale('zh', 'CN'),
      saveLocale: false,
      assetLoader: const _DiskAssetLoader(),
      child: _TestApp(router: _router!),
    ),
  );
  // 等本地化委托加载与路由首帧就绪（GoRouter initialLocation 匹配经
  // microtask 完成，两次 pump + settle 足以 build 出 shell）。
  await tester.pump();
  await tester.pump();
  await tester.pumpAndSettle();
}

/// 收尾：停表 + 卸载整树（取消导航条自动收起计时器）+ 释放路由。
Future<void> _unmount(WidgetTester tester) async {
  _resetTimer();
  await tester.pumpWidget(const SizedBox());
  _router?.dispose();
  _router = null;
  // 清静态壳引用，避免残留到下一个测试（MainApp.current 为静态字段）。
  MainApp.current = null;
}

/// 停掉儿童观看计时器（周期 ticker）并清空会话/锁屏残留。
void _resetTimer() {
  final KidWatchTimerController timer = KidWatchTimerController.instance;
  timer.configure(
    enabled: false,
    profiles: const <String, ChildProfile>{},
    quietHours: const <QuietHour>[],
    activeChildIds: const <String>[],
  );
  timer.clearAll();
}

/// 按测试重新注册 `flutter/assets` 同步读取处理器。
///
/// flutter_test 只在 binding 初始化时注册一次该 mock（`mockFlutterAssets`），
/// 且注册的回调在每个测试结束后被清掉——第二个测试起 `rootBundle.loadString`
/// 落到真实 messenger，在 FakeAsync 内永不完成，WidgetsApp 的
/// `Localizations._locale` 停在 null、整棵应用子树渲染成 `SizedBox`
/// （Router/Navigator/页面全都不 build）。故每个 setUp 补注册等价处理器。
void _registerAssetMock() {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (ByteData? message) {
    final String key = utf8.decode(message!.buffer.asUint8List());
    final List<String> candidates = <String>[
      if (Platform.environment.containsKey('UNIT_TEST_ASSETS'))
        '${Platform.environment['UNIT_TEST_ASSETS']}/$key',
      key,
      if (key.startsWith('packages/')) key.split('/').skip(2).join('/'),
    ];
    for (final String candidate in candidates) {
      final File file = File(candidate);
      if (file.existsSync()) {
        final bytes = file.readAsBytesSync();
        return SynchronousFuture<ByteData>(
          bytes.buffer.asByteData(bytes.offsetInBytes, bytes.lengthInBytes),
        );
      }
    }
    return null;
  });
}

/// 测试宿主：补齐 MainApp 所需的 AppBloc / RemoteLoginBloc 与本地化接线。
class _TestApp extends StatelessWidget {
  const _TestApp({required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: <BlocProvider<dynamic>>[
        BlocProvider<AppBloc>(create: (BuildContext _) => AppBloc()),
        BlocProvider<RemoteLoginBloc>(
          create: (BuildContext _) =>
              RemoteLoginBloc(repository: const _FakeRemoteLoginRepository()),
        ),
      ],
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
      ),
    );
  }
}

/// 无副作用的远程账号仓储：ProfilePage 远程行只读它当前状态。
class _FakeRemoteLoginRepository implements RemoteLoginRepository {
  const _FakeRemoteLoginRepository();

  @override
  String get savedAccount => '';

  @override
  Stream<RealtimeConnectionState> get onConnectionState =>
      const Stream<RealtimeConnectionState>.empty();

  @override
  Stream<String> get onFatalError => const Stream<String>.empty();

  @override
  Future<void> autoLogin() async {}

  @override
  Future<void> switchAccount(String account) async {}
}

/// 从磁盘同步读取 zh-CN 等翻译 JSON（测试环境不依赖资产 bundle 打包）。
///
/// 不走 rootBundle：其字符串缓存是跨测试共享的单例，前序测试残留的挂起
/// Future 会让后续测试的 loadString 永不完成（FakeAsync 内也等不到真实
/// I/O 回调），导致 Localizations._locale 停在 null、整棵子树渲染成
/// SizedBox。同步读文件不依赖事件循环，整跑稳定。
class _DiskAssetLoader extends AssetLoader {
  const _DiskAssetLoader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final String assetKey = '$path/${locale.toLanguageTag()}.json';
    final List<String> candidates = <String>[
      if (Platform.environment.containsKey('UNIT_TEST_ASSETS'))
        '${Platform.environment['UNIT_TEST_ASSETS']}/$assetKey',
      assetKey,
      if (assetKey.startsWith('packages/'))
        assetKey.split('/').skip(2).join('/'),
    ];
    for (final String candidate in candidates) {
      final File file = File(candidate);
      if (file.existsSync()) {
        return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      }
    }
    throw FlutterError('translation asset not found: $assetKey');
  }
}

