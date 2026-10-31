import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/application/history_service.dart';
import 'package:pscreen_home/features/home/application/metric_history.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';
import 'package:pscreen_home/features/home/domain/models/metric_sample.dart';
import 'package:pscreen_home/features/home/domain/models/metric_source.dart';
import 'package:pscreen_home/features/home/domain/repositories/home_repository.dart';
import 'package:pscreen_home/features/home/presentation/components/metric_chart_card.dart';
import 'package:pscreen_home/features/home/presentation/components/metric_sparkline.dart';

Widget _card(Map<Metric, MetricSource> sources) => MaterialApp(
      home: Scaffold(
        body: MetricChartCard(
          service: HistoryService(
            repository: _NoopRepo(),
            store: MetricHistoryStore(),
          ),
          deviceId: 'd',
          sources: sources,
        ),
      ),
    );

void main() {
  testWidgets('渲染 range 按钮，默认 24h', (WidgetTester tester) async {
    await tester.pumpWidget(
      _card(const <Metric, MetricSource>{Metric.power: MetricSource('sensor.d')}),
    );
    await tester.pump();

    expect(find.text('1h'), findsOneWidget);
    expect(find.text('24h'), findsOneWidget);
    expect(find.text('周'), findsOneWidget);
    expect(find.text('月'), findsOneWidget);
    expect(find.text('年'), findsOneWidget);
    expect(find.text('功率'), findsOneWidget);
    expect(find.byType(MetricSparkline), findsOneWidget);
  });

  testWidgets('温度与湿度分区同时展示，无需切换', (WidgetTester tester) async {
    await tester.pumpWidget(
      _card(const <Metric, MetricSource>{
        Metric.temperature: MetricSource('sensor.t'),
        Metric.humidity: MetricSource('sensor.h'),
      }),
    );
    await tester.pump();

    expect(find.text('温度'), findsOneWidget);
    expect(find.text('湿度'), findsOneWidget);
    expect(find.text('功率'), findsNothing);
    expect(find.byType(MetricSparkline), findsNWidgets(2));

    final List<MetricSparkline> charts =
        tester.widgetList<MetricSparkline>(find.byType(MetricSparkline)).toList();
    expect(charts[0].unit, '°C');
    expect(charts[1].unit, '%');
  });

  testWidgets('功率 / 温度 / 湿度同时可见', (WidgetTester tester) async {
    await tester.pumpWidget(
      _card(const <Metric, MetricSource>{
        Metric.power: MetricSource('sensor.p'),
        Metric.temperature: MetricSource('sensor.t'),
        Metric.humidity: MetricSource('sensor.h'),
      }),
    );
    await tester.pump();

    expect(find.text('功率'), findsOneWidget);
    expect(find.text('温度'), findsOneWidget);
    expect(find.text('湿度'), findsOneWidget);
    expect(find.byType(MetricSparkline), findsNWidgets(3));
  });
}

class _NoopRepo implements HomeRepository {
  @override
  Future<List<MetricSample>> fetchMetricDetail({
    required List<String> entityIds,
    required DateTime start,
    required DateTime end,
  }) async =>
      const <MetricSample>[];

  @override
  Future<List<MetricSample>> fetchMetricStats({
    required List<String> statisticIds,
    required DateTime start,
    required DateTime end,
    required String period,
  }) async =>
      const <MetricSample>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
