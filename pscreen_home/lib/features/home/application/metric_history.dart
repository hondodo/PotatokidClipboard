import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';
import 'package:pscreen_home/features/home/domain/models/metric_sample.dart';

/// 指标历史仓库：按 设备 + metric 保存最近一段时间的采样点，仅驻内存。
///
/// - 不持久化：应用退出即丢弃，符合「启动后开始记录」的语义；
/// - 写入时按 [window] 淘汰过期点（滑动窗口）；
/// - 通过 `ValueListenable` 通知图表刷新，避免把历史塞进全局 State 导致整页重建。
class MetricHistoryStore {
  MetricHistoryStore({this.window = defaultWindow});

  /// 默认保留窗口：最近 24 小时。
  static const Duration defaultWindow = Duration(hours: 24);

  final Duration window;

  final Map<String, List<MetricSample>> _series =
      <String, List<MetricSample>>{};
  final Map<String, ValueNotifier<List<MetricSample>>> _notifiers =
      <String, ValueNotifier<List<MetricSample>>>{};

  static String keyOf(String deviceId, Metric metric) =>
      '$deviceId:${metric.name}';

  /// 只读快照（无数据返回空列表）。
  List<MetricSample> seriesOf(String deviceId, Metric metric) =>
      List<MetricSample>.unmodifiable(
        _series[keyOf(deviceId, metric)] ?? const <MetricSample>[],
      );

  /// 订阅某设备某指标的序列；同一 key 复用同一 notifier。
  ValueListenable<List<MetricSample>> watch(String deviceId, Metric metric) =>
      _notifiers.putIfAbsent(
        keyOf(deviceId, metric),
        () => ValueNotifier<List<MetricSample>>(const <MetricSample>[]),
      );

  /// 追加一个采样点并淘汰窗口外的旧点。
  void record(String deviceId, Metric metric, double value, {DateTime? now}) {
    final DateTime at = now ?? DateTime.now();
    final String key = keyOf(deviceId, metric);
    final List<MetricSample> list =
        _series.putIfAbsent(key, () => <MetricSample>[]);
    list.add(MetricSample(at: at, value: value));

    final DateTime cutoff = at.subtract(window);
    int drop = 0;
    while (drop < list.length && !list[drop].at.isAfter(cutoff)) {
      drop += 1;
    }
    if (drop > 0) list.removeRange(0, drop);

    _notifiers[key]?.value = List<MetricSample>.unmodifiable(list);
  }

  void clear(String deviceId, Metric metric) {
    final String key = keyOf(deviceId, metric);
    _series.remove(key);
    _notifiers[key]?.value = const <MetricSample>[];
  }

  void clearAll() {
    for (final String key in _series.keys.toList(growable: false)) {
      _notifiers[key]?.value = const <MetricSample>[];
    }
    _series.clear();
  }
}

/// 指标采样器：按固定间隔读取各设备最新指标值写入 [MetricHistoryStore]。
///
/// - 采样源由 `HomeBloc` 通过 [bind] 注入（返回 device_id → metric → 值）；
/// - 间隔可运行时调整（设置页动态配置）；
/// - 仅使用内存，不产生网络请求（数据来自 HA 推送的实时状态）。
class MetricSampler {
  MetricSampler({
    required this.store,
    required this.log,
    Duration interval = defaultInterval,
  }) : _interval = interval;

  /// 默认采样间隔：5 秒。
  static const Duration defaultInterval = Duration(seconds: 5);

  final MetricHistoryStore store;
  final LogService log;

  /// 采样源：返回 device_id → metric → 值。由 HomeBloc 绑定。
  Map<String, Map<Metric, double?>> Function() readStats =
      () => const <String, Map<Metric, double?>>{};

  Duration _interval;
  Timer? _timer;

  Duration get interval => _interval;
  bool get isRunning => _timer?.isActive ?? false;

  /// 绑定数据源并开始采样（重复调用幂等）。
  void bind(Map<String, Map<Metric, double?>> Function() reader) {
    readStats = reader;
    start();
  }

  void start() {
    if (isRunning) return;
    _timer = Timer.periodic(_interval, (_) => _tick());
    // 立即采一次，避免等待首个周期才出现数据。
    _tick();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// 运行时调整间隔（设置页动态配置），运行中即时生效。
  void setInterval(Duration value) {
    if (value == _interval) return;
    _interval = value;
    if (isRunning) {
      _timer!.cancel();
      _timer = Timer.periodic(_interval, (_) => _tick());
    }
  }

  void _tick() {
    try {
      final Map<String, Map<Metric, double?>> stats = readStats();
      stats.forEach((String deviceId, Map<Metric, double?> metrics) {
        metrics.forEach((Metric metric, double? value) {
          if (value == null) return;
          store.record(deviceId, metric, value);
        });
      });
    } catch (e) {
      log.warn('指标采样失败：$e');
    }
  }

  void dispose() => stop();
}
