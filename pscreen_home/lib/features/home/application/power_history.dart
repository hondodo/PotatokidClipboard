import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pscreen_home/core/logging/log_service.dart';
import 'package:pscreen_home/features/home/domain/models/power_sample.dart';
import 'package:pscreen_home/features/home/domain/models/power_stats.dart';

/// 功率历史仓库：按设备保存最近一段时间的功率采样点，**仅驻内存**。
///
/// - 不持久化：应用退出即丢弃，符合「启动后开始记录」的语义；
/// - 每个设备一条时间序列，写入时按 [window] 淘汰过期点（滑动窗口）；
/// - 通过 `ValueListenable` 通知图表刷新，避免把历史塞进全局 State 导致整页重建。
class PowerHistoryStore {
  PowerHistoryStore({this.window = defaultWindow});

  /// 默认保留窗口：最近 24 小时。
  static const Duration defaultWindow = Duration(hours: 24);

  final Duration window;

  final Map<String, List<PowerSample>> _series = <String, List<PowerSample>>{};
  final Map<String, ValueNotifier<List<PowerSample>>> _notifiers =
      <String, ValueNotifier<List<PowerSample>>>{};

  /// 只读快照（无数据返回空列表）。
  List<PowerSample> seriesOf(String key) =>
      List<PowerSample>.unmodifiable(_series[key] ?? const <PowerSample>[]);

  /// 订阅某设备的功率序列；同一 key 复用同一 notifier。
  ValueListenable<List<PowerSample>> watch(String key) => _notifiers.putIfAbsent(
        key,
        () => ValueNotifier<List<PowerSample>>(const <PowerSample>[]),
      );

  /// 追加一个采样点并淘汰窗口外的旧点。
  void record(String key, double watts, {DateTime? now}) {
    final DateTime at = now ?? DateTime.now();
    final List<PowerSample> list = _series.putIfAbsent(
      key,
      () => <PowerSample>[],
    );
    list.add(PowerSample(at: at, watts: watts));

    final DateTime cutoff = at.subtract(window);
    int drop = 0;
    while (drop < list.length && !list[drop].at.isAfter(cutoff)) {
      drop += 1;
    }
    if (drop > 0) list.removeRange(0, drop);

    _notifiers[key]?.value = List<PowerSample>.unmodifiable(list);
  }

  void clear(String key) {
    _series.remove(key);
    _notifiers[key]?.value = const <PowerSample>[];
  }

  void clearAll() {
    for (final String key in _series.keys.toList(growable: false)) {
      clear(key);
    }
  }
}

/// 功率采样器：按固定间隔读取各设备最新功率值写入 [PowerHistoryStore]。
///
/// - 采样源由 `HomeBloc` 通过 [bind] 注入（读取 bloc 最新 State）；
/// - 间隔可运行时调整（设置页动态配置）；
/// - 仅使用内存，不产生网络请求（数据来自 HA 推送的实时状态）。
class PowerSampler {
  PowerSampler({
    required this.store,
    required this.log,
    this._interval = defaultInterval,
  });

  /// 默认采样间隔：5 秒。
  static const Duration defaultInterval = Duration(seconds: 5);

  final PowerHistoryStore store;
  final LogService log;

  /// 采样源：返回 device_id → 用电信息。由 HomeBloc 绑定。
  Map<String, PowerStats> Function() readStats =
      () => const <String, PowerStats>{};

  Duration _interval;
  Timer? _timer;

  Duration get interval => _interval;
  bool get isRunning => _timer?.isActive ?? false;

  /// 绑定数据源并开始采样（重复调用幂等）。
  void bind(Map<String, PowerStats> Function() reader) {
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
      final Map<String, PowerStats> stats = readStats();
      stats.forEach((String deviceId, PowerStats s) {
        if (s.currentEntityId == null) return;
        store.record(deviceId, s.currentWatts ?? 0);
      });
    } catch (e) {
      log.warn('功率采样失败：$e');
    }
  }

  void dispose() => stop();
}
