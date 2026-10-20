import 'package:flutter/foundation.dart';
import 'package:pscreen_home/features/home/application/metric_history.dart';
import 'package:pscreen_home/features/home/domain/models/history_range.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';
import 'package:pscreen_home/features/home/domain/models/metric_sample.dart';
import 'package:pscreen_home/features/home/domain/models/metric_source.dart';
import 'package:pscreen_home/features/home/domain/repositories/home_repository.dart';

/// 历史曲线服务：按 range 选源（明细 / 统计），叠加内存采样，内存缓存。
class HistoryService {
  HistoryService({required HomeRepository repository, required MetricHistoryStore store})
    : _repository = repository,
      _store = store;

  final HomeRepository _repository;
  final MetricHistoryStore _store;

  static const Duration _gapTolerance = Duration(minutes: 2);

  /// 缓存有效期：过期后重新拉取，避免曲线长期停在旧数据。
  static const Duration _cacheTtl = Duration(seconds: 60);

  final Map<String, ({List<MetricSample> samples, DateTime fetchedAt})> _cache =
      <String, ({List<MetricSample> samples, DateTime fetchedAt})>{};
  final Map<String, Future<List<MetricSample>>> _inFlight = <String, Future<List<MetricSample>>>{};

  /// 明细缺数据时，回退统计的容差（最早点晚于起点即认为被 purge）。
  static bool _coversStart(List<MetricSample> samples, DateTime start) {
    if (samples.isEmpty) return false;
    return !samples.first.at.isAfter(start.add(_gapTolerance));
  }

  Future<List<MetricSample>> load({
    required String deviceId,
    required Metric metric,
    required HistoryRange range,
    required MetricSource source,
    DateTime? now,
  }) {
    // climate 属性在 HA 里没有时间序列，只能用本会话的内存采样。
    if (source.isAttribute) {
      return Future<List<MetricSample>>.value(_store.seriesOf(deviceId, metric));
    }
    final DateTime end = now ?? DateTime.now();
    final DateTime start = end.subtract(range.duration);
    final String key = '$deviceId:${metric.name}:${range.name}';
    final ({List<MetricSample> samples, DateTime fetchedAt})? cached = _cache[key];
    if (cached != null && DateTime.now().difference(cached.fetchedAt) < _cacheTtl) {
      return Future<List<MetricSample>>.value(cached.samples);
    }

    return _inFlight.putIfAbsent(key, () async {
      try {
        final List<MetricSample> out = await _loadDetailOrStats(
          deviceId: deviceId,
          metric: metric,
          entityId: source.entityId,
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

  /// 订阅某指标的内存采样（属性来源的唯一数据源）。
  ValueListenable<List<MetricSample>> watch(String deviceId, Metric metric) => _store.watch(deviceId, metric);

  /// 把内存采样合并进历史结果（按时间去重，内存优先），用于实时刷新。
  List<MetricSample> mergeLive(String deviceId, Metric metric, List<MetricSample> samples) =>
      _mergeWithMemory(deviceId, metric, samples);

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
      if (detail.isNotEmpty && _coversStart(detail, start)) {
        // 明细覆盖完整：叠加本会话内存采样（平滑）。
        return _mergeWithMemory(deviceId, metric, detail);
      }
      final List<MetricSample> stats = await _repository.fetchMetricStats(
        statisticIds: <String>[entityId],
        start: start,
        end: end,
        period: range.statPeriod,
      );
      if (detail.isEmpty) {
        return _mergeWithMemory(deviceId, metric, stats);
      }
      // 明细只覆盖最近一段（更早的被 recorder purge）：统计补齐前半段，
      // 明细保留后半段。不要整体丢弃明细，否则曲线会突然从「现在」重新开始。
      final DateTime detailStart = detail.first.at;
      return _mergeWithMemory(deviceId, metric, <MetricSample>[
        ...stats.where((MetricSample s) => s.at.isBefore(detailStart)),
        ...detail,
      ]);
    }
    return _mergeWithMemory(
      deviceId,
      metric,
      await _repository.fetchMetricStats(
        statisticIds: <String>[entityId],
        start: start,
        end: end,
        period: range.statPeriod,
      ),
    );
  }

  List<MetricSample> _mergeWithMemory(String deviceId, Metric metric, List<MetricSample> history) {
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
