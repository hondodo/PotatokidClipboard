import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/screen/presentation/pages/clock_page.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_bloc.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_event.dart';
import 'package:pscreen_screen/features/weather/data/weather_data_convert.dart';
import 'package:pscreen_screen/features/weather/domain/models/weather_models.dart';
import 'package:pscreen_screen/features/weather/domain/repositories/weather_repository.dart';

class _FakeWeatherRepository implements WeatherRepository {
  _FakeWeatherRepository(this.data);

  final WeatherData data;

  @override
  Future<String?> resolveLocation() async => '测试市';

  @override
  Future<WeatherData> fetchWeather(String location) async => data;
}

/// 与时钟页内部一致的日期键，供测试计算「今天 / 周X」。
String _dateKey(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

void main() {
  // WeatherBloc 内部有一个 5 分钟的定时刷新 Timer。若在 widget 测试的
  // fake-async 区间内创建，测试体结束时 flutter_test 会抛 pending timer
  // 断言（addTearDown 晚于该断言）。故在 setUp（真实事件循环）中创建，
  // 在 tearDown 中关闭。
  late WeatherBloc bloc;
  late String todayKey;
  late String tomorrowKey;
  late String dayAfterKey;

  setUp(() async {
    final DateTime now = DateTime.now();
    todayKey = _dateKey(now);
    tomorrowKey = _dateKey(now.add(const Duration(days: 1)));
    dayAfterKey = _dateKey(now.add(const Duration(days: 2)));

    bloc = WeatherBloc(
      repository: _FakeWeatherRepository(
        WeatherData(
          now: const WeatherNow(
            temperature: 25,
            skycon: '18',
            text: '雾',
            city: '测试市',
          ),
          daily: <WeatherDay>[
            WeatherDay(
              date: todayKey,
              skycon: '1',
              text: '多云',
              tempMax: 33,
              tempMin: 24,
            ),
            WeatherDay(
              date: tomorrowKey,
              skycon: '7',
              text: '小雨',
              tempMax: 31,
              tempMin: 24,
            ),
            WeatherDay(
              date: dayAfterKey,
              skycon: '0',
              text: '晴',
              tempMax: 32,
              tempMin: 23,
            ),
          ],
        ),
      ),
    );

    final Completer<bool> done = Completer<bool>();
    bloc.add(LoadWeather(completer: done));
    await done.future;
  });

  tearDown(() async {
    await bloc.close();
  });

  testWidgets('时钟页渲染时间、日期与农历行', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<WeatherBloc>.value(
          value: bloc,
          child: const ClockPage(),
        ),
      ),
    );
    await tester.pump();

    // 时间主显示（正则匹配当前小时，避免跨秒导致的偶发失败）
    expect(find.textContaining(RegExp(r'^\d{2}:\d{2}')), findsOneWidget);
    // 日期行
    expect(find.textContaining('年'), findsWidgets);
    // 农历行
    expect(find.textContaining('月'), findsWidgets);
  });

  testWidgets('时间数字使用等宽字形', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<WeatherBloc>.value(
          value: bloc,
          child: const ClockPage(),
        ),
      ),
    );
    await tester.pump();

    final Text clock = tester.widget<Text>(
      find.textContaining(RegExp(r'^\d{2}:\d{2}:\d{2}$')),
    );
    expect(
      clock.style?.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
  });

  testWidgets('时钟页展示实时天气、今日预报与未来两天预报', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<WeatherBloc>.value(
          value: bloc,
          child: const ClockPage(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('测试市'), findsOneWidget);
    expect(find.textContaining('雾'), findsOneWidget);
    expect(find.textContaining('多云'), findsOneWidget);
    expect(find.textContaining('小雨'), findsOneWidget);
    expect(find.textContaining('晴'), findsOneWidget);
    expect(
      find.text(WeatherDataConvert.dayLabel(tomorrowKey, todayKey)),
      findsOneWidget,
    );
    expect(
      find.text(WeatherDataConvert.dayLabel(dayAfterKey, todayKey)),
      findsOneWidget,
    );
    // 今日预报不带「今天」标签，直接跟在实时天气后面。
    expect(find.text('今天'), findsNothing);
    // 今日 + 未来两天的温度区间。
    expect(find.textContaining('° ~'), findsNWidgets(3));
    // 当前天气图标 + 今日预报图标 + 未来两天图标。
    expect(find.byType(Image), findsNWidgets(4));
  });

  testWidgets('时钟页在墙板尺寸下一屏展示且不滚动', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.5;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<WeatherBloc>.value(
          value: bloc,
          child: const ClockPage(),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsNothing);
    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  testWidgets('时钟页在窄屏下等比缩小而不是滚动', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<WeatherBloc>.value(
          value: bloc,
          child: const ClockPage(),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(Scrollable), findsNothing);
    expect(find.byType(SingleChildScrollView), findsNothing);
  });

  testWidgets('时钟页无返回按钮，点击画面返回上一页', (WidgetTester tester) async {
    await tester.pumpWidget(
      BlocProvider<WeatherBloc>.value(
        value: bloc,
        child: MaterialApp(
          home: Builder(
            builder: (BuildContext context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext context) => const ClockPage(),
                    ),
                  ),
                  child: const Text('打开时钟'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开时钟'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(ClockPage), findsOneWidget);
    expect(find.byIcon(Icons.arrow_back_rounded), findsNothing);
    expect(find.textContaining(RegExp(r'^\d{2}:\d{2}:\d{2}$')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('clock-surface')));
    await tester.pumpAndSettle();

    expect(find.byType(ClockPage), findsNothing);
    expect(find.text('打开时钟'), findsOneWidget);
  });
}
