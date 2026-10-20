import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/core/logging/log_service.dart';
import 'package:pscreen_home/features/home/application/metric_history.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';
import 'package:pscreen_home/features/home/domain/models/metric_sample.dart';

void main() {
  group('MetricHistoryStore 滑动窗口', () {
    test('默认保留窗口为 24 小时', () {
      expect(MetricHistoryStore.defaultWindow, const Duration(hours: 24));
    });

    test('窗口外的旧点被丢弃，窗口内的保留', () {
      final MetricHistoryStore store = MetricHistoryStore();
      final DateTime base = DateTime(2026, 1, 1, 12);
      store.record('dev', Metric.power, 10, now: base);
      store.record('dev', Metric.power, 20,
          now: base.add(const Duration(hours: 12)));
      store.record('dev', Metric.power, 30,
          now: base.add(const Duration(hours: 24, minutes: 1)));
      final List<MetricSample> series = store.seriesOf('dev', Metric.power);
      expect(series.map((MetricSample s) => s.value).toList(), <double>[20, 30]);
    });

    test('不同 metric 互不干扰', () {
      final MetricHistoryStore store = MetricHistoryStore();
      store.record('dev', Metric.power, 1);
      store.record('dev', Metric.temperature, 20);
      expect(store.seriesOf('dev', Metric.power).single.value, 1);
      expect(store.seriesOf('dev', Metric.temperature).single.value, 20);
    });

    test('watch 在追加后推送最新序列', () {
      final MetricHistoryStore store = MetricHistoryStore();
      final ValueListenable<List<MetricSample>> listenable =
          store.watch('dev', Metric.power);
      store.record('dev', Metric.power, 42, now: DateTime(2026, 1, 1, 12));
      expect(listenable.value.single.value, 42);
    });

    test('clear 清空单设备单指标历史', () {
      final MetricHistoryStore store = MetricHistoryStore();
      store.record('a', Metric.power, 1);
      store.record('a', Metric.temperature, 2);
      store.clear('a', Metric.power);
      expect(store.seriesOf('a', Metric.power), isEmpty);
      expect(store.seriesOf('a', Metric.temperature).length, 1);
    });

    test('clearAll 清空全部', () {
      final MetricHistoryStore store = MetricHistoryStore();
      store.record('a', Metric.power, 1);
      store.record('b', Metric.humidity, 50);
      store.clearAll();
      expect(store.seriesOf('a', Metric.power), isEmpty);
      expect(store.seriesOf('b', Metric.humidity), isEmpty);
    });
  });

  group('MetricSampler 采样', () {
    testWidgets('bind 立即采一次，之后按间隔追加', (WidgetTester tester) async {
      final MetricHistoryStore store = MetricHistoryStore();
      final MetricSampler sampler = MetricSampler(
        store: store,
        log: const LogService(),
        interval: const Duration(seconds: 5),
      );

      double watts = 100;
      sampler.bind(() => <String, Map<Metric, double?>>{
            'dev': <Metric, double?>{Metric.power: watts},
          });

      expect(store.seriesOf('dev', Metric.power).length, 1);
      expect(store.seriesOf('dev', Metric.power).single.value, 100);

      watts = 200;
      await tester.pump(const Duration(seconds: 5));
      expect(store.seriesOf('dev', Metric.power).length, 2);
      expect(store.seriesOf('dev', Metric.power).last.value, 200);

      sampler.dispose();
    });

    testWidgets('null 值跳过，不写入假数据', (WidgetTester tester) async {
      final MetricHistoryStore store = MetricHistoryStore();
      final MetricSampler sampler = MetricSampler(
        store: store,
        log: const LogService(),
      );

      sampler.bind(() => <String, Map<Metric, double?>>{
            'dev': <Metric, double?>{
              Metric.power: 12,
              Metric.temperature: null,
            },
          });

      expect(store.seriesOf('dev', Metric.power).length, 1);
      expect(store.seriesOf('dev', Metric.temperature), isEmpty);

      sampler.dispose();
    });

    testWidgets('setInterval 运行中即时生效', (WidgetTester tester) async {
      final MetricHistoryStore store = MetricHistoryStore();
      final MetricSampler sampler = MetricSampler(
        store: store,
        log: const LogService(),
        interval: const Duration(seconds: 5),
      );

      int value = 0;
      sampler.bind(() => <String, Map<Metric, double?>>{
            'dev': <Metric, double?>{Metric.power: (value++).toDouble()},
          });
      expect(store.seriesOf('dev', Metric.power).length, 1);

      sampler.setInterval(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(store.seriesOf('dev', Metric.power).length, 2);

      sampler.dispose();
    });
  });
}
