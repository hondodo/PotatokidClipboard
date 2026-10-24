import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/screen/presentation/pages/weather_page.dart';
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

/// 与天气页内部一致的日期键，供测试计算「今天 / 周X」。
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

  setUp(() async {
    final DateTime now = DateTime.now();
    todayKey = _dateKey(now);
    tomorrowKey = _dateKey(now.add(const Duration(days: 1)));

    bloc = WeatherBloc(
      repository: _FakeWeatherRepository(
        WeatherData(
          now: const WeatherNow(
            temperature: 21.5,
            text: '多云',
            humidity: 60,
            city: '测试市',
          ),
          daily: <WeatherDay>[
            WeatherDay(date: todayKey, text: '晴', tempMax: 26, tempMin: 15),
            WeatherDay(date: tomorrowKey, text: '雨', tempMax: 23, tempMin: 14),
          ],
        ),
      ),
    );
    // WeatherBloc 构造时**不会**自动派发 LoadWeather，首次加载必须显式触发。
    // 放在 setUp（真实事件循环）里派发并 await 完成：bloc 的事件处理器运行在
    // 真实 zone，若在 widget 测试的 fake-async 区间内 await 其结果会一直等不到。
    final Completer<bool> done = Completer<bool>();
    bloc.add(LoadWeather(completer: done));
    await done.future;
  });

  tearDown(() async {
    await bloc.close();
  });

  testWidgets('天气页展示实时天气与多日预报', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<WeatherBloc>.value(
          value: bloc,
          child: const WeatherPage(),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('测试市'), findsOneWidget);
    expect(find.textContaining('多云'), findsOneWidget);
    expect(find.text('今天'), findsOneWidget);
    expect(
      find.text(WeatherDataConvert.dayLabel(tomorrowKey, todayKey)),
      findsOneWidget,
    );
    expect(find.text('晴'), findsOneWidget);
    expect(find.text('雨'), findsOneWidget);
    expect(find.textContaining('° ~'), findsWidgets);
  });

  testWidgets('宽屏天气页一屏显示当前天气与预报', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<WeatherBloc>.value(
          value: bloc,
          child: const WeatherPage(),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('未来 2 天'), findsOneWidget);
    expect(find.text('今天'), findsOneWidget);
    expect(find.text('晴'), findsOneWidget);
    expect(find.text('雨'), findsOneWidget);
  });
}
