import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/screen/presentation/pages/live_page.dart';
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

void main() {
  testWidgets('直播页展示频道列表并可点击切台', (WidgetTester tester) async {
    // IptvBloc 落缓存要读写 SharedPreferences：flutter test 里平台通道不会
    // 回调，必须用内存实现替身，否则频道加载会卡在 await 上。
    SharedPreferences.setMockInitialValues(<String, Object>{});

    // 放大测试画布：播放器占 16:9，默认 800x600 画布下频道列表会被挤到屏外。
    tester.view.physicalSize = const Size(1200, 900);
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
    await tester.pump();
    await tester.pump();

    expect(find.text('CCTV-1'), findsOneWidget);
    expect(find.text('CCTV-5'), findsOneWidget);

    // 触屏点选切台：立即提交播放（走共享包的 LiveChannelController）。
    await tester.tap(find.text('CCTV-5'));
    await tester.pump();
    expect(LiveChannelController.instance.index, 1);
  });
}
