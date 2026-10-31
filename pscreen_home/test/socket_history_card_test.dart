import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/application/history_service.dart';
import 'package:pscreen_home/features/home/application/metric_history.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';
import 'package:pscreen_home/features/home/domain/models/metric_sample.dart';
import 'package:pscreen_home/features/home/domain/models/metric_source.dart';
import 'package:pscreen_home/features/home/domain/models/power_stats.dart';
import 'package:pscreen_home/features/home/domain/models/socket_summary.dart';
import 'package:pscreen_home/features/home/domain/repositories/home_repository.dart';
import 'package:pscreen_home/features/home/presentation/components/metric_sparkline.dart';
import 'package:pscreen_home/features/home/presentation/components/socket_widget.dart';

class _HistoryRepo implements HomeRepository {
  _HistoryRepo(this.detail);

  final List<MetricSample> detail;
  int detailCalls = 0;

  @override
  Future<List<MetricSample>> fetchMetricDetail({
    required List<String> entityIds,
    required DateTime start,
    required DateTime end,
  }) async {
    detailCalls += 1;
    return detail;
  }

  @override
  Future<List<MetricSample>> fetchMetricStats({
    required List<String> statisticIds,
    required DateTime start,
    required DateTime end,
    required String period,
  }) async {
    return const <MetricSample>[];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SocketSummary _socket() => const SocketSummary(
      deviceId: 'dev_socket',
      name: '米家智能插座3',
      isOn: false,
      powerEntityId: 'switch.socket_power',
      stats: PowerStats(
        currentWatts: 0,
        totalKwh: 0.01,
        currentEntityId: 'sensor.socket_power',
      ),
      fault: '0',
    );

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 240, height: 112, child: child),
        ),
      ),
    );

void main() {
  testWidgets('插座卡片：启动时用 HA 历史补全曲线，并叠加实时采样',
      (WidgetTester tester) async {
    final DateTime now = DateTime.now();
    final _HistoryRepo repo = _HistoryRepo(<MetricSample>[
      MetricSample(
        at: now.subtract(const Duration(hours: 24)).add(
              const Duration(minutes: 1),
            ),
        value: 50,
      ),
      MetricSample(
        at: now.subtract(const Duration(hours: 2)),
        value: 0,
      ),
    ]);
    final MetricHistoryStore store = MetricHistoryStore();
    final HistoryService service =
        HistoryService(repository: repo, store: store);

    await tester.pumpWidget(_host(SocketWidget(
      summary: _socket(),
      isToggling: false,
      onToggle: () {},
      onOpenDetail: () {},
      historyService: service,
      deviceId: 'dev_socket',
      powerSource: const MetricSource('sensor.socket_power'),
    )));
    await tester.pumpAndSettle();

    MetricSparkline sparkline =
        tester.widget<MetricSparkline>(find.byType(MetricSparkline));
    expect(repo.detailCalls, 1);
    expect(sparkline.samples.length, 2);
    expect(sparkline.samples.first.value, 50);

    store.record('dev_socket', Metric.power, 42);
    await tester.pump();

    sparkline = tester.widget<MetricSparkline>(find.byType(MetricSparkline));
    expect(sparkline.samples.length, 3);
    expect(sparkline.samples.last.value, 42);
    expect(tester.takeException(), isNull);
  });

  testWidgets('插座卡片：全部房间时标题前置房间名', (WidgetTester tester) async {
    await tester.pumpWidget(_host(SocketWidget(
      summary: _socket(),
      isToggling: false,
      onToggle: () {},
      areaLabel: '客厅',
      showAreaInTitle: true,
    )));

    expect(find.text('客厅 米家智能插座3'), findsOneWidget);
  });

  testWidgets('插座卡片：选中房间时标题不重复房间名', (WidgetTester tester) async {
    await tester.pumpWidget(_host(SocketWidget(
      summary: _socket(),
      isToggling: false,
      onToggle: () {},
      areaLabel: '客厅',
    )));

    expect(find.text('米家智能插座3'), findsOneWidget);
    expect(find.text('客厅 米家智能插座3'), findsNothing);
  });
}
