import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/application/history_service.dart';
import 'package:pscreen_home/features/home/application/metric_history.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';
import 'package:pscreen_home/features/home/domain/models/metric_sample.dart';
import 'package:pscreen_home/features/home/domain/repositories/home_repository.dart';
import 'package:pscreen_home/features/home/presentation/components/metric_chart_card.dart';
import 'package:pscreen_home/features/home/presentation/components/metric_sparkline.dart';

void main() {
  testWidgets('渲染 range 按钮与 metric 切换，默认 24h', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MetricChartCard(
            service: HistoryService(
              repository: _NoopRepo(),
              store: MetricHistoryStore(),
            ),
            deviceId: 'd',
            entityIds: const <Metric, String>{Metric.power: 'sensor.d'},
          ),
        ),
      ),
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

  testWidgets('只显示可用的 metric', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MetricChartCard(
            service: HistoryService(
              repository: _NoopRepo(),
              store: MetricHistoryStore(),
            ),
            deviceId: 'd',
            entityIds: const <Metric, String>{
              Metric.temperature: 'sensor.t',
              Metric.humidity: 'sensor.h',
            },
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('温度'), findsOneWidget);
    expect(find.text('湿度'), findsOneWidget);
    expect(find.text('功率'), findsNothing);
  });

  testWidgets('切换 metric 后曲线单位跟随', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MetricChartCard(
            service: HistoryService(
              repository: _NoopRepo(),
              store: MetricHistoryStore(),
            ),
            deviceId: 'd',
            entityIds: const <Metric, String>{
              Metric.power: 'sensor.p',
              Metric.temperature: 'sensor.t',
            },
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('温度'));
    await tester.pump();

    final MetricSparkline chart =
        tester.widget<MetricSparkline>(find.byType(MetricSparkline));
    expect(chart.unit, '°C');
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
