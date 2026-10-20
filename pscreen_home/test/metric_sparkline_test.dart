import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/metric_sample.dart';
import 'package:pscreen_home/features/home/presentation/components/metric_sparkline.dart';

void main() {
  group('MetricSparkline 像素桶降采样', () {
    final DateTime now = DateTime(2026, 1, 1, 12);
    const Duration window = Duration(hours: 24);

    test('点数不超过 2×像素宽时原样返回', () {
      final List<MetricSample> samples = List<MetricSample>.generate(
        100,
        (int i) => MetricSample(
          at: now.subtract(Duration(minutes: 100 - i)),
          value: i.toDouble(),
        ),
      );

      final List<MetricSample> out = downsampleMetricSamples(
        samples: samples,
        now: now,
        window: window,
        width: 100,
      );

      expect(out.length, 100);
      expect(out.first.value, 0);
      expect(out.last.value, 99);
    });

    test('大数据量收敛到约 2×像素宽，且保留全局最小 / 最大值', () {
      final List<MetricSample> samples = List<MetricSample>.generate(
        10000,
        (int i) => MetricSample(
          at: now.subtract(Duration(seconds: (10000 - i) * 5)),
          value: i == 5000 ? 9999 : (i % 100).toDouble(),
        ),
      );

      final List<MetricSample> out = downsampleMetricSamples(
        samples: samples,
        now: now,
        window: window,
        width: 200,
      );

      // 200 个桶 × 每桶最多 2 点，再补一个最右端点。
      expect(out.length, lessThanOrEqualTo(401));
      expect(out.any((MetricSample s) => s.value == 9999), isTrue);
      expect(out.any((MetricSample s) => s.value == 0), isTrue);
    });

    test('窗口外的点被过滤', () {
      final List<MetricSample> samples = <MetricSample>[
        MetricSample(at: now.subtract(const Duration(hours: 25)), value: 1),
        MetricSample(at: now.subtract(const Duration(hours: 1)), value: 2),
        MetricSample(at: now, value: 3),
      ];

      final List<MetricSample> out = downsampleMetricSamples(
        samples: samples,
        now: now,
        window: window,
        width: 100,
      );

      expect(out.map((MetricSample s) => s.value).toList(), <double>[2, 3]);
    });

    test('空数据 / 非法宽度返回空列表', () {
      expect(
        downsampleMetricSamples(
          samples: const <MetricSample>[],
          now: now,
          window: window,
          width: 100,
        ),
        isEmpty,
      );
      expect(
        downsampleMetricSamples(
          samples: <MetricSample>[MetricSample(at: now, value: 1)],
          now: now,
          window: window,
          width: 0,
        ),
        isEmpty,
      );
    });
  });

  group('splitByGap', () {
    final DateTime now = DateTime(2026, 1, 1, 12);
    MetricSample m(Duration d, double v) =>
        MetricSample(at: now.add(d), value: v);

    test('gap 为 null 时单段', () {
      final List<List<MetricSample>> out = splitByGap(
        <MetricSample>[m(Duration.zero, 1), m(const Duration(minutes: 5), 2)],
        null,
      );
      expect(out.length, 1);
      expect(out.single.length, 2);
    });

    test('相邻点超过阈值时断开', () {
      final List<List<MetricSample>> out = splitByGap(
        <MetricSample>[
          m(Duration.zero, 1),
          m(const Duration(minutes: 5), 2),
          m(const Duration(minutes: 10), 3),
          m(const Duration(hours: 2), 4),
        ],
        const Duration(minutes: 30),
      );
      expect(out.length, 2);
      expect(out.first.length, 3);
      expect(out.last.single.value, 4);
    });

    test('空列表返回空', () {
      expect(splitByGap(const <MetricSample>[], null), isEmpty);
      expect(
        splitByGap(const <MetricSample>[], const Duration(minutes: 1)),
        isEmpty,
      );
    });
  });

  group('adaptiveGap', () {
    final DateTime now = DateTime(2026, 1, 1, 12);
    MetricSample m(Duration d, double v) =>
        MetricSample(at: now.add(d), value: v);

    test('点太少或基准为 null 时原样返回', () {
      expect(
        adaptiveGap(const Duration(minutes: 2),
            <MetricSample>[m(Duration.zero, 1), m(const Duration(minutes: 1), 2)]),
        const Duration(minutes: 2),
      );
      expect(
        adaptiveGap(null, <MetricSample>[
          m(Duration.zero, 1),
          m(const Duration(minutes: 1), 2),
          m(const Duration(minutes: 2), 3),
        ]),
        isNull,
      );
    });

    test('稀疏序列按中位间隔 5 倍放大阈值', () {
      final Duration? gap = adaptiveGap(
        const Duration(minutes: 2),
        <MetricSample>[
          m(Duration.zero, 1),
          m(const Duration(hours: 2), 1),
          m(const Duration(hours: 4), 1),
        ],
      );
      expect(gap, const Duration(hours: 10));
    });

    test('密集序列保持基准阈值', () {
      final Duration? gap = adaptiveGap(
        const Duration(minutes: 10),
        List<MetricSample>.generate(
          20,
          (int i) => m(Duration(seconds: i * 5), i.toDouble()),
        ),
      );
      expect(gap, const Duration(minutes: 10));
    });
  });
}
