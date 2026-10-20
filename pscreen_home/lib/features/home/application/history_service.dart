import 'package:pscreen_home/features/home/application/metric_history.dart';
import 'package:pscreen_home/features/home/domain/models/history_range.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';
import 'package:pscreen_home/features/home/domain/models/metric_sample.dart';
import 'package:pscreen_home/features/home/domain/repositories/home_repository.dart';

/// 历史曲线服务：按 range 选源（明细 / 统计），叠加内存采样，内存缓存。
class HistoryService {
  HistoryService({
    required HomeRepository repository,
    required MetricHistoryStore store,
  })  : _repository = repository,
        _store = store;

  final HomeRepository _repository;
  final MetricHistoryStore _store;

  static const Duration _gapTolerance = Duration(minutes: 2);

  /// 缓存有效期：过期后重新拉取，避免曲线长期停在旧数据。
  static const Duration _cacheTtl = Duration(seconds: 60);

  final Map<String, ({List<MetricSample> samples, DateTime fetchedAt})> _cache =
      <String, ({List<MetricSample> samples, DateTime fetchedAt})>{};
  final Map<String, Future<List<MetricSample>>> _inFlight =
      <String, Future<List<MetricSample>>>{};

  /// 明细缺数据时，回退统计的容差（最早点晚于起点即认为被 purge）。
  static bool _coversStart(List<MetricSample> samples, DateTime start) {
    if (samples.isEmpty) return false;
    return !samples.first.at.isAfter(start.add(_gapTolerance));
  }

  Future<List<MetricSample>> load({
    required String deviceId,
    required Metric metric,
    required HistoryRange range,
    required String entityId,
    DateTime? now,
  }) {
    final DateTime end = now ?? DateTime.now();
    final DateTime start = end.subtract(range.duration);
    final String key = '$deviceId:${metric.name}:${range.name}';
    final ({List<MetricSample> samples, DateTime fetchedAt})? cached =
        _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < _cacheTtl) {
      return Future<List<MetricSample>>.value(cached.samples);
    }

    return _inFlight.putIfAbsent(key, () async {
      try {
        final List<MetricSample> out = await _loadDetailOrStats(
          deviceId: deviceId,
          metric: metric,
          entityId: entityId,
          range: range,
          start: start,
          end: end,
        );
        _cache[key] = (samples: out, fetchedAt: DateTime.now());
        return out;
      } finally {
        _inFlight.remove(key);
      }
    });
  }

  Future<List<MetricSample>> _loadDetailOrStats({
    required String deviceId,
    required Metric metric,
    required String entityId,
    required HistoryRange range,
    required DateTime start,
    required DateTime end,
  }) async {
    if (range.useDetailed) {
      final List<MetricSample> detail = await _repository.fetchMetricDetail(
        entityIds: <String>[entityId],
        start: start,
        end: end,
      );
      if (_coversStart(detail, start)) {
        // 明细覆盖完整：叠加本会话内存采样（平滑）。
        return _mergeWithMemory(deviceId, metric, detail);
      }
      // 明细被 purge：整个 range 改用统计。
      return _repository.fetchMetricStats(
        statisticIds: <String>[entityId],
        start: start,
        end: end,
        period: range.statPeriod,
      );
    }
    return _repository.fetchMetricStats(
      statisticIds: <String>[entityId],
      start: start,
      end: end,
      period: range.statPeriod,
    );
  }

  List<MetricSample> _mergeWithMemory(
    String deviceId,
    Metric metric,
    List<MetricSample> history,
  ) {
    final List<MetricSample> live = _store.seriesOf(deviceId, metric);
    if (live.isEmpty) return history;
    final Map<DateTime, MetricSample> byTime = <DateTime, MetricSample>{};
    for (final MetricSample s in history) {
      byTime[s.at] = s;
    }
    for (final MetricSample s in live) {
      byTime[s.at] = s; // 内存优先
    }
    final List<MetricSample> merged = byTime.values.toList(growable: false)
      ..sort((MetricSample a, MetricSample b) => a.at.compareTo(b.at));
    return merged;
  }

  /// 连接就绪 / 跨天 / 手动刷新时清缓存。
  void invalidate() {
    _cache.clear();
  }
}
