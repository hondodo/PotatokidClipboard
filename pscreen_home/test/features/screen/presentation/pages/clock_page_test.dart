import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/screen/presentation/pages/clock_page.dart';
import 'package:pscreen_screen/features/weather/application/bloc/weather_bloc.dart';
import 'package:pscreen_screen/features/weather/domain/models/weather_models.dart';
import 'package:pscreen_screen/features/weather/domain/repositories/weather_repository.dart';

class _FakeWeatherRepository implements WeatherRepository {
  @override
  Future<String?> resolveLocation() async => '测试市';

  @override
  Future<WeatherData> fetchWeather(String location) async => const WeatherData(
    now: WeatherNow(temperature: 21, text: '晴', city: '测试市'),
  );
}

void main() {
  // WeatherBloc 内部有一个 5 分钟的定时刷新 Timer。若在 widget 测试的
  // fake-async 区间内创建，测试体结束时 flutter_test 会抛 pending timer
  // 断言（addTearDown 晚于该断言）。故在 setUp（真实事件循环）中创建，
  // 在 tearDown 中关闭。
  late WeatherBloc bloc;

  setUp(() {
    bloc = WeatherBloc(repository: _FakeWeatherRepository());
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
