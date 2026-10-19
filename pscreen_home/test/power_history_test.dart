import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/core/logging/log_service.dart';
import 'package:pscreen_home/features/home/application/power_history.dart';
import 'package:pscreen_home/features/home/domain/models/power_sample.dart';
import 'package:pscreen_home/features/home/domain/models/power_stats.dart';

void main() {
  group('PowerHistoryStore 滑动窗口', () {
    test('默认保留窗口为 24 小时', () {
      expect(PowerHistoryStore.defaultWindow, const Duration(hours: 24));
    });

    test('窗口外的旧点被丢弃，窗口内的保留', () {
      final PowerHistoryStore store = PowerHistoryStore();
      final DateTime base = DateTime(2026, 1, 1, 12);

      store.record('dev', 10, now: base);
      store.record('dev', 20, now: base.add(const Duration(hours: 12)));
      store.record(
        'dev',
        30,
        now: base.add(const Duration(hours: 24, minutes: 1)),
      );

      final List<PowerSample> series = store.seriesOf('dev');
      expect(series.map((PowerSample s) => s.watts).toList(), <double>[20, 30]);
    });

    test('watch 在追加后推送最新序列', () {
      final PowerHistoryStore store = PowerHistoryStore();
      final List<PowerSample> first = store.seriesOf('dev');
      expect(first, isEmpty);

      final ValueListenable<List<PowerSample>> listenable = store.watch('dev');
      expect(listenable.value, isEmpty);

      store.record('dev', 42, now: DateTime(2026, 1, 1, 12));
      expect(listenable.value.single.watts, 42);
    });

    test('clear 清空单设备历史', () {
      final PowerHistoryStore store = PowerHistoryStore();
      store.record('a', 1);
      store.record('b', 2);
      store.clear('a');

      expect(store.seriesOf('a'), isEmpty);
      expect(store.seriesOf('b').length, 1);
    });
  });

  group('PowerSampler 采样', () {
    testWidgets('bind 立即采一次，之后按间隔追加', (WidgetTester tester) async {
      final PowerHistoryStore store = PowerHistoryStore();
      final PowerSampler sampler = PowerSampler(
        store: store,
        log: const LogService(),
        interval: const Duration(seconds: 5),
      );

      double watts = 100;
      sampler.bind(
        () => <String, PowerStats>{
          'dev': PowerStats(
            currentWatts: watts,
            currentEntityId: 'sensor.dev_power',
          ),
        },
      );

      expect(store.seriesOf('dev').length, 1);
      expect(store.seriesOf('dev').single.watts, 100);

      watts = 200;
      await tester.pump(const Duration(seconds: 5));
      expect(store.seriesOf('dev').length, 2);
      expect(store.seriesOf('dev').last.watts, 200);

      watts = 300;
      await tester.pump(const Duration(seconds: 5));
      expect(store.seriesOf('dev').length, 3);
      expect(store.seriesOf('dev').last.watts, 300);

      sampler.dispose();
    });

    testWidgets('没有功率实体的设备不记录', (WidgetTester tester) async {
      final PowerHistoryStore store = PowerHistoryStore();
      final PowerSampler sampler = PowerSampler(
        store: store,
        log: const LogService(),
        interval: const Duration(seconds: 5),
      );

      sampler.bind(
        () => <String, PowerStats>{
          'dev': const PowerStats(currentWatts: 10),
        },
      );
      await tester.pump(const Duration(seconds: 5));

      expect(store.seriesOf('dev'), isEmpty);
      sampler.dispose();
    });

    testWidgets('setInterval 运行中即时生效', (WidgetTester tester) async {
      final PowerHistoryStore store = PowerHistoryStore();
      final PowerSampler sampler = PowerSampler(
        store: store,
        log: const LogService(),
        interval: const Duration(seconds: 5),
      );

      int value = 0;
      sampler.bind(
        () => <String, PowerStats>{
          'dev': PowerStats(
            currentWatts: (value++).toDouble(),
            currentEntityId: 'sensor.dev_power',
          ),
        },
      );
      expect(store.seriesOf('dev').length, 1);

      sampler.setInterval(const Duration(seconds: 1));
      expect(sampler.interval, const Duration(seconds: 1));

      await tester.pump(const Duration(seconds: 1));
      expect(store.seriesOf('dev').length, 2);

      sampler.dispose();
    });
  });
}
