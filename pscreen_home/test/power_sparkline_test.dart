import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/power_sample.dart';
import 'package:pscreen_home/features/home/presentation/components/power_sparkline.dart';

void main() {
  group('PowerSparkline 像素桶降采样', () {
    final DateTime now = DateTime(2026, 1, 1, 12);
    const Duration window = Duration(hours: 24);

    test('点数不超过 2×像素宽时原样返回', () {
      final List<PowerSample> samples = List<PowerSample>.generate(
        100,
        (int i) => PowerSample(
          at: now.subtract(Duration(minutes: 100 - i)),
          watts: i.toDouble(),
        ),
      );

      final List<PowerSample> out = downsamplePowerSamples(
        samples: samples,
        now: now,
        window: window,
        width: 100,
      );

      expect(out.length, 100);
      expect(out.first.watts, 0);
      expect(out.last.watts, 99);
    });

    test('大数据量收敛到约 2×像素宽，且保留全局最小 / 最大值', () {
      final List<PowerSample> samples = List<PowerSample>.generate(
        10000,
        (int i) => PowerSample(
          at: now.subtract(Duration(seconds: (10000 - i) * 5)),
          watts: i == 5000 ? 9999 : (i % 100).toDouble(),
        ),
      );

      final List<PowerSample> out = downsamplePowerSamples(
        samples: samples,
        now: now,
        window: window,
        width: 200,
      );

      // 200 个桶 × 每桶最多 2 点，再补一个最右端点。
      expect(out.length, lessThanOrEqualTo(401));
      expect(out.any((PowerSample s) => s.watts == 9999), isTrue);
      expect(out.any((PowerSample s) => s.watts == 0), isTrue);
    });

    test('窗口外的点被过滤', () {
      final List<PowerSample> samples = <PowerSample>[
        PowerSample(
          at: now.subtract(const Duration(hours: 25)),
          watts: 1,
        ),
        PowerSample(
          at: now.subtract(const Duration(hours: 1)),
          watts: 2,
        ),
        PowerSample(at: now, watts: 3),
      ];

      final List<PowerSample> out = downsamplePowerSamples(
        samples: samples,
        now: now,
        window: window,
        width: 100,
      );

      expect(out.map((PowerSample s) => s.watts).toList(), <double>[2, 3]);
    });

    test('空数据 / 非法宽度返回空列表', () {
      expect(
        downsamplePowerSamples(
          samples: const <PowerSample>[],
          now: now,
          window: window,
          width: 100,
        ),
        isEmpty,
      );
      expect(
        downsamplePowerSamples(
          samples: <PowerSample>[PowerSample(at: now, watts: 1)],
          now: now,
          window: window,
          width: 0,
        ),
        isEmpty,
      );
    });
  });
}
