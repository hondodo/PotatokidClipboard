import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/application/history_service.dart';
import 'package:pscreen_home/features/home/application/metric_history.dart';
import 'package:pscreen_home/features/home/domain/models/history_range.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';
import 'package:pscreen_home/features/home/domain/models/metric_sample.dart';
import 'package:pscreen_home/features/home/domain/models/metric_source.dart';
import 'package:pscreen_home/features/home/domain/repositories/home_repository.dart';

class _FakeRepo implements HomeRepository {
  _FakeRepo({
    this.detail = const <MetricSample>[],
    this.stats = const <MetricSample>[],
  });

  List<MetricSample> detail;
  List<MetricSample> stats;
  int detailCalls = 0;
  int statsCalls = 0;

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
    statsCalls += 1;
    return stats;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MetricSample at(DateTime t, double v) => MetricSample(at: t, value: v);

void main() {
  final DateTime now = DateTime(2026, 1, 1, 12);

  test('≤周且明细覆盖起点时走明细', () async {
    final _FakeRepo repo = _FakeRepo(
      detail: <MetricSample>[
        at(now.subtract(const Duration(days: 7)).add(const Duration(minutes: 1)),
            10),
        at(now, 12),
      ],
    );
    final HistoryService service =
        HistoryService(repository: repo, store: MetricHistoryStore());

    final List<MetricSample> out = await service.load(
      deviceId: 'd',
      metric: Metric.power,
      range: HistoryRange.week,
      source: const MetricSource('sensor.d'),
      now: now,
    );

    expect(repo.detailCalls, 1);
    expect(repo.statsCalls, 0);
    expect(out.length, 2);
  });

  test('月/年走统计', () async {
    final _FakeRepo repo = _FakeRepo(
      stats: <MetricSample>[at(now.subtract(const Duration(days: 10)), 20)],
    );
    final HistoryService service =
        HistoryService(repository: repo, store: MetricHistoryStore());

    await service.load(
      deviceId: 'd',
      metric: Metric.power,
      range: HistoryRange.month,
      source: const MetricSource('sensor.d'),
      now: now,
    );

    expect(repo.statsCalls, 1);
    expect(repo.detailCalls, 0);
  });

  test('明细只覆盖最近一段时，与统计拼接而不是丢弃明细', () async {
    // 明细只覆盖最近 2 小时（更早被 purge）→ 统计补齐前半段，明细保留后半段。
    final _FakeRepo repo = _FakeRepo(
      detail: <MetricSample>[at(now.subtract(const Duration(hours: 2)), 10)],
      stats: <MetricSample>[at(now.subtract(const Duration(days: 6)), 30)],
    );
    final HistoryService service =
        HistoryService(repository: repo, store: MetricHistoryStore());

    final List<MetricSample> out = await service.load(
      deviceId: 'd',
      metric: Metric.power,
      range: HistoryRange.week,
      source: const MetricSource('sensor.d'),
      now: now,
    );

    expect(repo.detailCalls, 1);
    expect(repo.statsCalls, 1);
    expect(out.length, 2);
    expect(out.first.value, 30);
    expect(out.last.value, 10);
  });

  test('明细为空时回退统计', () async {
    final _FakeRepo repo = _FakeRepo(
      stats: <MetricSample>[at(now, 7)],
    );
    final HistoryService service =
        HistoryService(repository: repo, store: MetricHistoryStore());

    final List<MetricSample> out = await service.load(
      deviceId: 'd',
      metric: Metric.humidity,
      range: HistoryRange.h24,
      source: const MetricSource('sensor.h'),
      now: now,
    );

    expect(repo.statsCalls, 1);
    expect(out.single.value, 7);
  });

  test('同 key 并发只请求一次（缓存/去重）', () async {
    final _FakeRepo repo = _FakeRepo(stats: <MetricSample>[at(now, 5)]);
    final HistoryService service =
        HistoryService(repository: repo, store: MetricHistoryStore());

    final List<Future<List<MetricSample>>> futures =
        <Future<List<MetricSample>>>[
      service.load(
          deviceId: 'd',
          metric: Metric.power,
          range: HistoryRange.month,
          source: const MetricSource('sensor.d'),
          now: now),
      service.load(
          deviceId: 'd',
          metric: Metric.power,
          range: HistoryRange.month,
          source: const MetricSource('sensor.d'),
          now: now),
    ];
    await Future.wait(futures);
    expect(repo.statsCalls, 1);
  });

  test('invalidate 后重新请求', () async {
    final _FakeRepo repo = _FakeRepo(stats: <MetricSample>[at(now, 5)]);
    final HistoryService service =
        HistoryService(repository: repo, store: MetricHistoryStore());

    await service.load(
      deviceId: 'd',
      metric: Metric.power,
      range: HistoryRange.month,
      source: const MetricSource('sensor.d'),
      now: now,
    );
    service.invalidate();
    await service.load(
      deviceId: 'd',
      metric: Metric.power,
      range: HistoryRange.month,
      source: const MetricSource('sensor.d'),
      now: now,
    );

    expect(repo.statsCalls, 2);
  });

  test('明细结果叠加内存采样并去重', () async {
    final MetricHistoryStore store = MetricHistoryStore();
    final DateTime start = now.subtract(const Duration(hours: 1));
    store.record('d', Metric.power, 99, now: start);

    final _FakeRepo repo = _FakeRepo(
      detail: <MetricSample>[
        at(start, 10),
        at(now, 12),
      ],
    );
    final HistoryService service =
        HistoryService(repository: repo, store: store);

    final List<MetricSample> out = await service.load(
      deviceId: 'd',
      metric: Metric.power,
      range: HistoryRange.h1,
      source: const MetricSource('sensor.d'),
      now: now,
    );

    expect(out.length, 2);
    expect(out.first.value, 99);
    expect(out.last.value, 12);
  });

  test('climate 属性只取内存采样，不请求 HA', () async {
    final MetricHistoryStore store = MetricHistoryStore();
    store.record('d', Metric.temperature, 26.5, now: now);

    final _FakeRepo repo = _FakeRepo(
      detail: <MetricSample>[at(now, 10)],
      stats: <MetricSample>[at(now, 20)],
    );
    final HistoryService service =
        HistoryService(repository: repo, store: store);

    final List<MetricSample> out = await service.load(
      deviceId: 'd',
      metric: Metric.temperature,
      range: HistoryRange.month,
      source: const MetricSource(
        'climate.ac',
        attribute: 'current_temperature',
      ),
      now: now,
    );

    expect(repo.detailCalls, 0);
    expect(repo.statsCalls, 0);
    expect(out.single.value, 26.5);
  });
}
