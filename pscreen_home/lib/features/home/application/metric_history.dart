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
  MetricHistoryStore({this.window = defaultWindow, this.rawWindow = defaultRawWindow});

  /// 默认保留窗口：最近 24 小时。
  static const Duration defaultWindow = Duration(hours: 24);

  /// 折叠阈值：超过该时长的采样点按分钟折叠为 min/max 两点。
  static const Duration defaultRawWindow = Duration(hours: 1);

  final Duration window;

  /// 近细远粗的「细」区间长度，见 [foldSamples]。
  final Duration rawWindow;

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
    // 时钟回拨保护：新点早于末尾时重新排序，保证序列始终按时间升序
    //（下游的折叠与有序归并都依赖这一不变量）。
    if (list.length > 1 &&
        list[list.length - 2].at.isAfter(list[list.length - 1].at)) {
      list.sort((MetricSample a, MetricSample b) => a.at.compareTo(b.at));
    }

    final DateTime cutoff = at.subtract(window);
    int drop = 0;
    while (drop < list.length && !list[drop].at.isAfter(cutoff)) {
      drop += 1;
    }
    if (drop > 0) list.removeRange(0, drop);

    // 近细远粗：折叠后用结果替换内部序列。原先内部保留 24 小时全量
    // 原始点（5s 采样 = 17,280 点/序列），每 5 秒都要全量遍历 + 复制；
    // 折叠后只剩「1 分钟粒度的折叠段 + 最近 1 小时原始点」（约 3,500 点），
    // 下个采样周期的遍历与快照成本随之下降一个量级。
    final List<MetricSample> folded =
        foldSamples(list, now: at, rawWindow: rawWindow);
    _series[key] = folded;

    _notifiers[key]?.value = List<MetricSample>.unmodifiable(folded);
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

/// 近细远粗折叠：[rawWindow] 以内的点原样保留，更早的点按 [bucket] 分桶，
/// 每桶只保留「最小值 / 最大值」两个真实采样点（尖峰不丢，绘制层的
/// 像素桶降采样同样按 min/max 保留尖峰，视觉一致）。
///
/// 幂等：已折叠的点重新归桶结果不变，因此可对同一序列反复调用，
/// 内部序列用折叠结果替换后，下个采样周期只需遍历折叠后的小序列。
/// 要求 [samples] 按时间升序（[MetricHistoryStore.record] 保证）。
List<MetricSample> foldSamples(
  List<MetricSample> samples, {
  required DateTime now,
  Duration rawWindow = MetricHistoryStore.defaultRawWindow,
  Duration bucket = const Duration(minutes: 1),
}) {
  if (samples.isEmpty) return const <MetricSample>[];
  final int cutoffMs = now.subtract(rawWindow).millisecondsSinceEpoch;
  final int bucketMs = bucket.inMilliseconds;
  if (bucketMs <= 0) return List<MetricSample>.of(samples);

  final List<MetricSample> out = <MetricSample>[];
  int i = 0;
  while (i < samples.length &&
      samples[i].at.millisecondsSinceEpoch < cutoffMs) {
    // 跟踪同一时间桶内的最小 / 最大值。
    final int bucketStart =
        samples[i].at.millisecondsSinceEpoch -
        samples[i].at.millisecondsSinceEpoch.remainder(bucketMs);
    final int bucketEnd = bucketStart + bucketMs;
    MetricSample? lo;
    MetricSample? hi;
    while (i < samples.length) {
      final MetricSample s = samples[i];
      final int ms = s.at.millisecondsSinceEpoch;
      if (ms >= cutoffMs || ms >= bucketEnd) break;
      if (lo == null || s.value < lo.value) lo = s;
      if (hi == null || s.value > hi.value) hi = s;
      i += 1;
    }
    if (lo == null) break; // 防御：不可达，避免死循环
    if (identical(lo, hi)) {
      out.add(lo);
    } else if (lo.at.isBefore(hi!.at)) {
      out..add(lo)..add(hi);
    } else {
      out..add(hi)..add(lo);
    }
  }
  // 窗口内原始点原样保留。
  for (; i < samples.length; i += 1) {
    out.add(samples[i]);
  }
  return out;
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
