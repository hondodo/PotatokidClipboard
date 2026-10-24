import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
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
  Future<List<IptvChannel>> fetchRemoteChannels() async =>
      const <IptvChannel>[
        IptvChannel(
          name: 'CCTV-1',
          sources: <String>['http://example.com/1.m3u8'],
        ),
        IptvChannel(
          name: 'CCTV-5',
          sources: <String>['http://example.com/5.m3u8'],
        ),
      ];

  @override
  Future<List<IptvChannel>> loadDefaultRemoteChannels() async =>
      const <IptvChannel>[];

  @override
  Future<List<IptvChannel>> buildPlaylist(List<IptvChannel> remote) async =>
      remote;
}

/// 搭起 [LivePage] 并加载频道，直到首个频道出现在右侧浮层列表里。
Future<void> _pumpLivePage(WidgetTester tester, {required Size size}) async {
  // IptvBloc 落缓存要读写 SharedPreferences：flutter test 里平台通道不会
  // 回调，必须用内存实现替身，否则频道加载会卡在 await 上。
  SharedPreferences.setMockInitialValues(<String, Object>{});

  // 放大测试画布：1200x900 / 1920x1080 触屏面板的逻辑分辨率。
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final IptvBloc bloc = IptvBloc(repository: _FakeIptvRepository());
  // widget 测试体内是 fake-async 区间，await bloc.close() 会死锁
  // （事件控制器的 close 只能被 pump 推进），故放到 teardown（真实事件循环）。
  addTearDown(bloc.close);

  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider<IptvBloc>.value(
        value: bloc,
        child: const LivePage(enablePlayer: false),
      ),
    ),
  );
  bloc.add(const LoadIptv());
  // 频道加载是异步的（默认兜底 + 假仓库返回 + 规则/设置读取），逐步 pump 直到
  // 右侧列表出现频道条目；不用 pumpAndSettle——列表出现后若有后台刷新会一直无法 settle。
  // 注意：左下角频道名徽标也会显示当前频道名（index=0 时同为「CCTV-1」），
  // 故用 ListTile 而非裸文本判断「频道已加载」。
  for (int i = 0; i < 30 && find.byType(ListTile).evaluate().isEmpty; i++) {
    await tester.pump();
  }
  expect(
    find.byType(ListTile),
    findsWidgets,
    reason: '频道应在有限次 pump 内加载完成并渲染到右侧列表',
  );
}

/// 右侧列表里某个频道的条目（避开左下角同名徽标）。
Finder _tile(String name) => find.widgetWithText(ListTile, name);

void main() {
  setUp(() async {
    // AppSettings 单例把「首次加载 Future」缓存下来；该 Future 在上一个
    // testWidgets 的 fake-async zone 里创建，本测试里再 await 它会永久卡住
    // （其完成微任务不会被本测试的 pump 推进）。clearAllPersisted 会把缓存
    // 置空，让本次测试在当前 zone 重新加载。setUp 在 fake-async 之前（真实
    // 事件循环）执行，故可安全 await。
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AppSettings.instance.clearAllPersisted();

    // LiveChannelController 是全局单例、跨测试共享：把 index/count 归零，
    // 避免上一个测试残留的选中序号影响后续用例。
    LiveChannelController.instance.setCount(0);
  });

  testWidgets('进入后右侧频道列表与底部切台按钮自动显示，点选切台后列表保持显示',
      (WidgetTester tester) async {
    await _pumpLivePage(tester, size: const Size(1200, 900));

    // 浮层自动显示：右侧列表 + 底部「上一台/下一台」按钮都在。
    expect(_tile('CCTV-1'), findsOneWidget);
    expect(_tile('CCTV-5'), findsOneWidget);
    expect(find.byTooltip('上一台'), findsOneWidget);
    expect(find.byTooltip('下一台'), findsOneWidget);

    // 点选切台：index 立即变化，列表保持显示。
    await tester.tap(_tile('CCTV-5'));
    await tester.pump();
    expect(LiveChannelController.instance.index, 1);
    expect(_tile('CCTV-5'), findsOneWidget, reason: '切台后列表应保持显示');
    expect(find.byTooltip('下一台'), findsOneWidget);
  });

  testWidgets('10 秒无操作自动隐藏浮层，点播放器空白处可切换显隐', (WidgetTester tester) async {
    await _pumpLivePage(tester, size: const Size(1200, 900));
    expect(find.byType(ListView), findsOneWidget);

    // 10 秒无操作 → 浮层隐藏（列表与底部按钮都消失，播放器仍在）。
    await tester.pump(const Duration(seconds: 11));
    expect(find.byType(ListView), findsNothing);
    expect(find.byTooltip('上一台'), findsNothing);

    // 点播放器空白处（左上角，远离右侧列表与底部按钮）→ 重新显示。
    await tester.tapAt(const Offset(150, 150));
    await tester.pump();
    expect(find.byType(ListView), findsOneWidget);

    // 再点空白处 → 切换为隐藏。
    await tester.tapAt(const Offset(150, 150));
    await tester.pump();
    expect(find.byType(ListView), findsNothing);
  });

  testWidgets('显示期间点频道会重置 10 秒计时', (WidgetTester tester) async {
    await _pumpLivePage(tester, size: const Size(1200, 900));

    // 走过 8 秒（未到 10 秒），浮层仍在显示。
    await tester.pump(const Duration(seconds: 8));
    expect(find.byType(ListView), findsOneWidget);

    // 点频道切台 → 计时重置（新的 10 秒从现在起算）。
    await tester.tap(_tile('CCTV-5'));
    await tester.pump();
    expect(LiveChannelController.instance.index, 1);

    // 再走 8 秒：若没重置，此刻累计 16 秒（>10 秒）应已隐藏；
    // 重置后距上次操作只过了 8 秒，浮层仍在显示。
    await tester.pump(const Duration(seconds: 8));
    expect(find.byType(ListView), findsOneWidget, reason: '点频道后 10 秒计时应重置');

    // 再走 3 秒（距点频道 11 秒 > 10 秒）→ 自动隐藏。
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(ListView), findsNothing);
  });

  testWidgets('点全屏隐藏 AppBar 并在左上角保留返回按钮，点恢复重新显示 AppBar', (WidgetTester tester) async {
    await _pumpLivePage(tester, size: const Size(1200, 900));

    // 初始：AppBar 在，底部有「全屏」，没有额外的返回按钮（AppBar 自带）。
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byTooltip('全屏'), findsOneWidget);
    expect(find.byTooltip('返回'), findsNothing);

    // 点全屏 → 隐藏 AppBar，视频区域变大；左上角出现返回按钮。
    await tester.tap(find.byTooltip('全屏'));
    await tester.pump();
    expect(find.byType(AppBar), findsNothing);
    expect(find.byTooltip('恢复'), findsOneWidget);
    expect(find.byTooltip('返回'), findsOneWidget);

    // 点恢复 → 重新显示 AppBar，返回按钮交还给 AppBar。
    await tester.tap(find.byTooltip('恢复'));
    await tester.pump();
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.byTooltip('全屏'), findsOneWidget);
    expect(find.byTooltip('返回'), findsNothing);
  });

  testWidgets('16:9 面板上右侧频道列表浮层完整可见（回归：列表不再被播放器挤成 0 高度）',
      (WidgetTester tester) async {
    // 15 寸触屏面板的 1920x1080（16:9）逻辑分辨率。
    // 旧布局（Column + Expanded 列表）在全宽播放器下会把列表挤成 0 高度；
    // 新布局列表是 Stack 浮层，纵向不参与空间分配，结构上不可能被挤没。
    await _pumpLivePage(tester, size: const Size(1920, 1080));

    expect(_tile('CCTV-1'), findsOneWidget);

    final Size listSize = tester.getSize(find.byType(ListView));
    expect(listSize.height, greaterThan(0));
    expect(listSize.width, greaterThan(0));

    // 列表停靠右侧：其左边界应在屏幕右半边。
    final Rect listRect = tester.getRect(find.byType(ListView));
    expect(listRect.left, greaterThan(1920 / 2));
  });
}
