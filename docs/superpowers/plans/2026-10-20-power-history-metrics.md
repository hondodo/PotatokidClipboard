# 功率 / 温湿度历史曲线（HA 数据源）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把功率曲线扩展为「功率 / 温度 / 湿度」三指标，支持 1/6/12/24h + 周/月/年切换，数据完全来自 HA（近期明细 + 长期统计），保留内存 5s 采样做平滑，缺数据留空。

**Architecture:** HA 是唯一长期存储；App 侧新增 `MetricSample` / `HistoryRange` 模型、`HaWsClient` 两个历史方法、`MetricEntityResolver`、`MetricHistoryStore`/`MetricSampler`（泛化并重命名自 `Power*`）、`HistoryService`（选源 + 自适应兜底 + 合并 + 缓存）、`MetricChartCard`（range + metric 切换）。

**Tech Stack:** Flutter 3.41 / Dart 3.11、flutter_bloc、get_it、go_router、`web_socket_channel`（HA WebSocket）。

**前置：** 仓库当前处于「合并进行中」状态，首个提交会一并收尾合并（提交信息用 `Merge branch 'origin/main'`）。

---

## File Structure

**新建**
- `lib/features/home/domain/models/metric.dart` — `Metric` 枚举
- `lib/features/home/domain/models/history_range.dart` — `HistoryRange` 枚举
- `lib/features/home/domain/models/metric_sample.dart` — `MetricSample`
- `lib/features/home/domain/models/metric_entity_resolver.dart` — 实体识别
- `lib/features/home/application/metric_history.dart` — `MetricHistoryStore` + `MetricSampler`
- `lib/features/home/application/history_service.dart` — `HistoryService`
- `lib/features/home/presentation/components/metric_sparkline.dart` — 重命名 + gap
- `lib/features/home/presentation/components/metric_chart_card.dart` — range + metric 曲线卡
- `test/history_range_test.dart`、`test/metric_sample_test.dart`、`test/metric_entity_resolver_test.dart`、`test/metric_history_test.dart`、`test/history_service_test.dart`、`test/metric_sparkline_test.dart`、`test/metric_chart_card_test.dart`

**删除（重命名）**
- `lib/features/home/domain/models/power_sample.dart`
- `lib/features/home/application/power_history.dart`
- `lib/features/home/presentation/components/power_sparkline.dart`

**修改**
- `lib/core/network/ha_ws_client.dart`、`lib/features/home/data/repositories/home_repository_impl.dart`、`lib/features/home/domain/repositories/home_repository.dart`
- `lib/core/di/modules/home_module.dart`、`lib/features/home/application/bloc/home_bloc.dart`
- `lib/features/home/presentation/pages/device_detail_page.dart`、`lib/features/home/presentation/pages/home_controll_board.dart`
- `lib/features/home/presentation/components/power_stats_card.dart`、`socket_widget.dart`、`socket_control_panel.dart`
- `lib/features/settings/presentation/pages/settings_page.dart`
- `test/control_panels_test.dart`、`test/home_bloc_test.dart`、`test/power_history_test.dart`、`test/power_sparkline_test.dart`

---

## Task 1: HistoryRange 枚举

**Files:**
- Create: `lib/features/home/domain/models/history_range.dart`
- Test: `test/history_range_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/history_range_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/history_range.dart';

void main() {
  test('各 range 的标签与时长', () {
    expect(HistoryRange.h1.label, '1h');
    expect(HistoryRange.h1.duration, const Duration(hours: 1));
    expect(HistoryRange.week.label, '周');
    expect(HistoryRange.week.duration, const Duration(days: 7));
    expect(HistoryRange.year.duration, const Duration(days: 365));
  });

  test('≤7 天走明细，>7 天走统计', () {
    expect(HistoryRange.h24.useDetailed, isTrue);
    expect(HistoryRange.week.useDetailed, isTrue);
    expect(HistoryRange.month.useDetailed, isFalse);
    expect(HistoryRange.year.useDetailed, isFalse);
  });

  test('统计周期：≤60 天 hour，否则 day', () {
    expect(HistoryRange.month.statPeriod, 'hour');
    expect(HistoryRange.year.statPeriod, 'day');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/history_range_test.dart`
Expected: FAIL（`history_range.dart` 不存在）

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/features/home/domain/models/history_range.dart
/// 历史曲线时间范围。
enum HistoryRange {
  h1('1h', Duration(hours: 1)),
  h6('6h', Duration(hours: 6)),
  h12('12h', Duration(hours: 12)),
  h24('24h', Duration(hours: 24)),
  week('周', Duration(days: 7)),
  month('月', Duration(days: 30)),
  year('年', Duration(days: 365));

  const HistoryRange(this.label, this.duration);

  final String label;
  final Duration duration;

  /// 是否走明细（≤7 天）；否则走长期统计。
  bool get useDetailed => duration <= const Duration(days: 7);

  /// 统计周期：≤60 天用 hour，否则 day。
  String get statPeriod => duration <= const Duration(days: 60) ? 'hour' : 'day';
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/history_range_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/home/domain/models/history_range.dart test/history_range_test.dart
git commit -m "feat(history): add HistoryRange enum"
```

---

## Task 2: Metric 枚举 + MetricSample

**Files:**
- Create: `lib/features/home/domain/models/metric.dart`
- Create: `lib/features/home/domain/models/metric_sample.dart`
- Test: `test/metric_sample_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/metric_sample_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';
import 'package:pscreen_home/features/home/domain/models/metric_sample.dart';

void main() {
  test('Metric 三指标', () {
    expect(Metric.values, <Metric>[Metric.power, Metric.temperature, Metric.humidity]);
  });

  test('MetricSample 承载 value 与可选 min/max', () {
    final DateTime at = DateTime(2026, 1, 1, 12);
    final MetricSample point = MetricSample(at: DateTime(2026, 1, 1, 12), value: 123.5);
    expect(point.at, at);
    expect(point.value, 123.5);
    expect(point.min, isNull);
    expect(point.max, isNull);

    final MetricSample stat = MetricSample(at: DateTime(2026, 1, 1, 12), value: 20, min: 10, max: 30);
    expect(stat.min, 10);
    expect(stat.max, 30);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/metric_sample_test.dart`
Expected: FAIL（文件不存在）

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/features/home/domain/models/metric.dart
/// 指标类型。
enum Metric { power, temperature, humidity }

/// 指标展示信息。
extension MetricInfo on Metric {
  String get label => switch (this) {
        Metric.power => '功率',
        Metric.temperature => '温度',
        Metric.humidity => '湿度',
      };

  String get unit => switch (this) {
        Metric.power => 'W',
        Metric.temperature => '°C',
        Metric.humidity => '%',
      };
}
```

```dart
// lib/features/home/domain/models/metric_sample.dart
/// 一个采样点：时刻 + 值（功率 W / 温度 °C / 湿度 %）。
///
/// 明细曲线只有 [value]；统计聚合曲线用 [value] 存均值，
/// [min] / [max] 存区间最小 / 最大值（可选）。
class MetricSample {
  const MetricSample({required this.at, required this.value, this.min, this.max});

  final DateTime at;
  final double value;
  final double? min;
  final double? max;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/metric_sample_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/home/domain/models/metric.dart lib/features/home/domain/models/metric_sample.dart test/metric_sample_test.dart
git commit -m "feat(history): add Metric enum and MetricSample model"
```

---

## Task 3: HA 接口层（明细 + 统计）

**Files:**
- Modify: `lib/core/network/ha_ws_client.dart`

- [ ] **Step 1: 在 `HaWsClient` 增加两个方法**

在 `callService` 方法之后插入：

```dart
  /// 明细历史（HA 只记录状态变化）。返回原始 `result`，由 data 层解析。
  ///
  /// `minimal_response` 返回紧凑结构 `{s, lu}`；`lu` 为 Unix 秒（浮点）。
  Future<Object?> historyDuringPeriod({
    required List<String> entityIds,
    required DateTime start,
    required DateTime end,
  }) async {
    final Map<String, dynamic> msg =
        await request('history/history_during_period', <String, dynamic>{
      'start_time': start.toUtc().toIso8601String(),
      'end_time': end.toUtc().toIso8601String(),
      'entity_ids': entityIds,
      'include_start_time_state': true,
      'significant_changes_only': true,
      'minimal_response': true,
      'no_attributes': true,
    });
    return msg['result'];
  }

  /// 长期统计（聚合）。返回原始 `result`，由 data 层解析。
  ///
  /// 返回 `start` 为 Unix 毫秒（整数），`mean/min/max` 为聚合值。
  Future<Object?> statisticsDuringPeriod({
    required List<String> statisticIds,
    required DateTime start,
    required DateTime end,
    required String period,
  }) async {
    final Map<String, dynamic> msg =
        await request('recorder/statistics_during_period', <String, dynamic>{
      'start_time': start.toUtc().toIso8601String(),
      'end_time': end.toUtc().toIso8601String(),
      'statistic_ids': statisticIds,
      'period': period,
      'types': <String>['mean', 'min', 'max'],
    });
    return msg['result'];
  }
```

- [ ] **Step 2: 静态检查**

Run: `flutter analyze lib/core/network/ha_ws_client.dart`
Expected: No issues

- [ ] **Step 3: Commit**

```bash
git add lib/core/network/ha_ws_client.dart
git commit -m "feat(history): add HA history/statistics WS methods"
```

> **验证注意**：`lu`（明细）为 Unix 秒、`start`（统计）为 Unix 毫秒，需对照真实 HA 返回核对（Task 12 手动验证）。

---

## Task 4: Repository（明细 + 统计）

**Files:**
- Modify: `lib/features/home/domain/repositories/home_repository.dart`
- Modify: `lib/features/home/data/repositories/home_repository_impl.dart`

- [ ] **Step 1: 接口增加方法**

在 `HomeRepository` 中新增：

```dart
  /// 拉取指标明细历史（HA states 表，只记状态变化）。
  Future<List<MetricSample>> fetchMetricDetail({
    required List<String> entityIds,
    required DateTime start,
    required DateTime end,
  });

  /// 拉取指标长期统计（聚合）。
  Future<List<MetricSample>> fetchMetricStats({
    required List<String> statisticIds,
    required DateTime start,
    required DateTime end,
    required String period,
  });
```

接口文件 import 增加：

```dart
import 'package:pscreen_home/features/home/domain/models/metric_sample.dart';
```

- [ ] **Step 2: 实现**

在 `HomeRepositoryImpl` 中新增：

```dart
  @override
  Future<List<MetricSample>> fetchMetricDetail({
    required List<String> entityIds,
    required DateTime start,
    required DateTime end,
  }) async {
    final Object? result = await client.historyDuringPeriod(
      entityIds: entityIds,
      start: start,
      end: end,
    );
    return _parseMetricHistory(result);
  }

  @override
  Future<List<MetricSample>> fetchMetricStats({
    required List<String> statisticIds,
    required DateTime start,
    required DateTime end,
    required String period,
  }) async {
    final Object? result = await client.statisticsDuringPeriod(
      statisticIds: statisticIds,
      start: start,
      end: end,
      period: period,
    );
    return _parseMetricStatistics(result);
  }

  /// 明细：紧凑项 `{s, lu}`，`lu` 为 Unix 秒（浮点）。
  List<MetricSample> _parseMetricHistory(Object? result) {
    if (result is! Map) return const <MetricSample>[];
    final List<MetricSample> out = <MetricSample>[];
    for (final Object? rawList in result.values) {
      if (rawList is! List) continue;
      for (final Object? item in rawList) {
        if (item is! Map) continue;
        final Object? s = item['s'];
        final Object? lu = item['lu'];
        if (s is! String || lu is! num) continue;
        final double? value = double.tryParse(s);
        if (value == null) continue;
        out.add(MetricSample(
          at: DateTime.fromMillisecondsSinceEpoch(
            (lu * 1000).round(),
            isUtc: true,
          ).toLocal(),
          value: value,
        ));
      }
    }
    out.sort((MetricSample a, MetricSample b) => a.at.compareTo(b.at));
    return out;
  }

  /// 统计：`start` 为 Unix 毫秒，`mean/min/max` 为聚合值。
  List<MetricSample> _parseMetricStatistics(Object? result) {
    if (result is! Map) return const <MetricSample>[];
    final List<MetricSample> out = <MetricSample>[];
    for (final Object? rawList in result.values) {
      if (rawList is! List) continue;
      for (final Object? item in rawList) {
        if (item is! Map) continue;
        final Object? startTs = item['start'];
        if (startTs is! num) continue;
        final double? mean = _asDouble(item['mean']);
        if (mean == null) continue;
        out.add(MetricSample(
          at: DateTime.fromMillisecondsSinceEpoch(
            startTs.round(),
            isUtc: true,
          ).toLocal(),
          value: mean,
          min: _asDouble(item['min']),
          max: _asDouble(item['max']),
        ));
      }
    }
    out.sort((MetricSample a, MetricSample b) => a.at.compareTo(b.at));
    return out;
  }

  static double? _asDouble(Object? value) =>
      value is num ? value.toDouble() : null;
```

实现文件 import 增加：

```dart
import 'package:pscreen_home/features/home/domain/models/metric_sample.dart';
```

- [ ] **Step 3: 静态检查**

Run: `flutter analyze`
Expected: No issues

- [ ] **Step 4: Commit**

```bash
git add lib/features/home/domain/repositories/home_repository.dart lib/features/home/data/repositories/home_repository_impl.dart
git commit -m "feat(history): add repository fetchMetricDetail/fetchMetricStats"
```

---

## Task 5: MetricEntityResolver

**Files:**
- Create: `lib/features/home/domain/models/metric_entity_resolver.dart`
- Test: `test/metric_entity_resolver_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/metric_entity_resolver_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/ha_device_group.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';
import 'package:pscreen_home/features/home/domain/models/metric_entity_resolver.dart';

HaEntityStateModel e(String id, {Map<String, dynamic>? attributes}) =>
    HaEntityStateModel(
      entityId: id,
      state: '1',
      attributes: attributes ?? const <String, dynamic>{},
    );

void main() {
  test('功率取 _electric_power_ sensor', () {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'd1',
      title: '插座',
      entities: <HaEntityStateModel>[e('sensor.d1_electric_power_p_5_1')],
    );
    expect(MetricEntityResolver.resolve(group)[Metric.power],
        'sensor.d1_electric_power_p_5_1');
  });

  test('温度取 sensor._temperature_ 实体，湿度取 _humidity_ 实体', () {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'd2',
      title: '冰箱',
      entities: <HaEntityStateModel>[
        e('sensor.midjd_temperature_p_3_1'),
        e('sensor.midjd_environment_humidity_p_10_10'),
      ],
    );
    final Map<Metric, String> resolved = MetricEntityResolver.resolve(group);
    expect(resolved[Metric.temperature], 'sensor.midjd_temperature_p_3_1');
    expect(resolved[Metric.humidity],
        'sensor.midjd_environment_humidity_p_10_10');
  });

  test('number.* 目标温度与 climate 属性不参与（无时间序列可查）', () {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'd2b',
      title: '空调',
      entities: <HaEntityStateModel>[
        e('number.d2b_target_temperature_p_2_5'),
        e('climate.d2b', attributes: <String, dynamic>{
          'current_temperature': 26.0,
          'current_humidity': 55,
        }),
      ],
    );
    expect(MetricEntityResolver.resolve(group), isEmpty);
  });

  test('无对应实体时该 metric 缺失', () {
    final HaDeviceGroup group = HaDeviceGroup(
      deviceId: 'd3',
      title: '灯',
      entities: <HaEntityStateModel>[e('light.d3')],
    );
    expect(MetricEntityResolver.resolve(group).containsKey(Metric.power), isFalse);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/metric_entity_resolver_test.dart`
Expected: FAIL（文件不存在）

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/features/home/domain/models/metric_entity_resolver.dart
import 'package:pscreen_home/features/home/domain/models/ha_device_group.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';

/// 按设备解析各 metric 对应的实体 id。
///
/// 仅接受 **数值型 sensor**：只有它们具备可查询的时间序列
/// （明细 `history_during_period` + 长期统计 `statistics_during_period`）。
/// `climate` 的温度/湿度是属性、状态为 `cool`/`heat` 等字符串，无法作为
/// 统计曲线数据源，故不参与。
abstract final class MetricEntityResolver {
  /// 返回该设备的 metric → entityId 映射（无对应实体则该 metric 缺失）。
  static Map<Metric, String> resolve(HaDeviceGroup group) {
    final Map<Metric, String> result = <Metric, String>{};
    for (final HaEntityStateModel e in group.entities) {
      if (e.domain != 'sensor') continue;
      if (e.entityId.contains('_electric_power_') &&
          !result.containsKey(Metric.power)) {
        result[Metric.power] = e.entityId;
      }
      if (e.entityId.contains('_temperature_') &&
          !result.containsKey(Metric.temperature)) {
        result[Metric.temperature] = e.entityId;
      }
      if (e.entityId.contains('_humidity_') &&
          !result.containsKey(Metric.humidity)) {
        result[Metric.humidity] = e.entityId;
      }
    }
    return result;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/metric_entity_resolver_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/home/domain/models/metric_entity_resolver.dart test/metric_entity_resolver_test.dart
git commit -m "feat(history): add MetricEntityResolver"
```

---

## Task 6: MetricHistoryStore + MetricSampler（重命名 + 泛化）

**Files:**
- Create: `lib/features/home/application/metric_history.dart`
- Delete: `lib/features/home/application/power_history.dart`
- Delete: `lib/features/home/domain/models/power_sample.dart`
- Test: `test/metric_history_test.dart`（由 `power_history_test.dart` 迁移）

- [ ] **Step 1: 新建测试**

```dart
// test/metric_history_test.dart
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
      store.record('dev', Metric.power, 20, now: base.add(const Duration(hours: 12)));
      store.record('dev', Metric.power, 30, now: base.add(const Duration(hours: 24, minutes: 1)));
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
      final ValueListenable<List<MetricSample>> listenable = store.watch('dev', Metric.power);
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/metric_history_test.dart`
Expected: FAIL（`metric_history.dart` 不存在）

- [ ] **Step 3: 实现 `metric_history.dart`**

```dart
// lib/features/home/application/metric_history.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pscreen_home/core/logging/log_service.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';
import 'package:pscreen_home/features/home/domain/models/metric_sample.dart';

/// 指标历史仓库：按 设备 + metric 保存最近一段时间的采样点，仅驻内存。
class MetricHistoryStore {
  MetricHistoryStore({this.window = defaultWindow});

  /// 默认保留窗口：最近 24 小时。
  static const Duration defaultWindow = Duration(hours: 24);

  final Duration window;

  final Map<String, List<MetricSample>> _series = <String, List<MetricSample>>{};
  final Map<String, ValueNotifier<List<MetricSample>>> _notifiers =
      <String, ValueNotifier<List<MetricSample>>>{};

  static String keyOf(String deviceId, Metric metric) => '$deviceId:${metric.name}';

  List<MetricSample> seriesOf(String deviceId, Metric metric) =>
      List<MetricSample>.unmodifiable(_series[keyOf(deviceId, metric)] ?? const <MetricSample>[]);

  ValueListenable<List<MetricSample>> watch(String deviceId, Metric metric) =>
      _notifiers.putIfAbsent(
        keyOf(deviceId, metric),
        () => ValueNotifier<List<MetricSample>>(const <MetricSample>[]),
      );

  void record(String deviceId, Metric metric, double value, {DateTime? now}) {
    final DateTime at = now ?? DateTime.now();
    final String key = keyOf(deviceId, metric);
    final List<MetricSample> list = _series.putIfAbsent(key, () => <MetricSample>[]);
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
}

/// 指标采样器：按固定间隔读取各设备最新指标值写入 [MetricHistoryStore]。
///
/// 采样源由 `bind` 注入（返回 device_id → metric → 值）。
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
```

- [ ] **Step 4: Run test**

旧 `power_history.dart` 暂不删除（仍有引用），在 Task 10 全部迁移后再删。

Run: `flutter test test/metric_history_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/home/application/metric_history.dart test/metric_history_test.dart
git commit -m "refactor(history): rename Power* to Metric*, generalize store/sampler"
```

---

## Task 7: HistoryService（选源 + 合并 + 缓存）

**Files:**
- Create: `lib/features/home/application/history_service.dart`
- Test: `test/history_service_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/history_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/application/history_service.dart';
import 'package:pscreen_home/features/home/application/metric_history.dart';
import 'package:pscreen_home/features/home/domain/models/history_range.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';
import 'package:pscreen_home/features/home/domain/models/metric_sample.dart';
import 'package:pscreen_home/features/home/domain/repositories/home_repository.dart';

class _FakeRepo implements HomeRepository {
  _FakeRepo({this.detail = const <MetricSample>[], this.stats = const <MetricSample>[]});

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

  test('≤周走明细', () async {
    final _FakeRepo repo = _FakeRepo(
      detail: <MetricSample>[at(now.subtract(const Duration(hours: 20)), 10)],
    );
    final HistoryService service = HistoryService(repository: repo, store: MetricHistoryStore());

    await service.load(
      deviceId: 'd',
      metric: Metric.power,
      range: HistoryRange.week,
      entityId: 'sensor.d',
      now: now,
    );

    expect(repo.detailCalls, 1);
    expect(repo.statsCalls, 0);
  });

  test('月/年走统计', () async {
    final _FakeRepo repo = _FakeRepo(
      stats: <MetricSample>[at(now.subtract(const Duration(days: 10)), 20)],
    );
    final HistoryService service = HistoryService(repository: repo, store: MetricHistoryStore());

    await service.load(
      deviceId: 'd',
      metric: Metric.power,
      range: HistoryRange.month,
      entityId: 'sensor.d',
      now: now,
    );

    expect(repo.statsCalls, 1);
    expect(repo.detailCalls, 0);
  });

  test('明细起点缺失时回退统计（自适应兜底）', () async {
    // 明细只覆盖最近 2 小时（更早被 purge）→ 整个 range 改用统计。
    final _FakeRepo repo = _FakeRepo(
      detail: <MetricSample>[at(now.subtract(const Duration(hours: 2)), 10)],
      stats: <MetricSample>[at(now.subtract(const Duration(days: 6)), 30)],
    );
    final HistoryService service = HistoryService(repository: repo, store: MetricHistoryStore());

    final List<MetricSample> out = await service.load(
      deviceId: 'd',
      metric: Metric.power,
      range: HistoryRange.week,
      entityId: 'sensor.d',
      now: now,
    );

    expect(repo.statsCalls, 1);
    expect(out.single.value, 30);
  });

  test('同 key 并发只请求一次（缓存）', () async {
    final _FakeRepo repo = _FakeRepo(
      stats: <MetricSample>[at(now, 5)],
    );
    final HistoryService service = HistoryService(repository: repo, store: MetricHistoryStore());

    final List<Future<List<MetricSample>>> futures = <Future<List<MetricSample>>>[
      service.load(deviceId: 'd', metric: Metric.power, range: HistoryRange.month, entityId: 'sensor.d', now: now),
      service.load(deviceId: 'd', metric: Metric.power, range: HistoryRange.month, entityId: 'sensor.d', now: now),
    ];
    await Future.wait(futures);
    expect(repo.statsCalls, 1);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/history_service_test.dart`
Expected: FAIL（文件不存在）

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/features/home/application/history_service.dart
import 'dart:async';

import 'package:pscreen_home/features/home/application/metric_history.dart';
import 'package:pscreen_home/features/home/domain/models/history_range.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';
import 'package:pscreen_home/features/home/domain/models/metric_sample.dart';
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

  /// 连接就绪 / 跨天时清缓存。
  void invalidate() {
    _cache.clear();
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/history_service_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/home/application/history_service.dart test/history_service_test.dart
git commit -m "feat(history): add HistoryService source selection and cache"
```

---

## Task 8: MetricSparkline（重命名 + gap）

**Files:**
- Create: `lib/features/home/presentation/components/metric_sparkline.dart`
- Delete: `lib/features/home/presentation/components/power_sparkline.dart`
- Test: `test/metric_sparkline_test.dart`（由 `power_sparkline_test.dart` 迁移 + gap）

- [ ] **Step 1: 新建测试**

```dart
// test/metric_sparkline_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/domain/models/metric_sample.dart';
import 'package:pscreen_home/features/home/presentation/components/metric_sparkline.dart';

void main() {
  group('MetricSparkline 像素桶降采样', () {
    final DateTime now = DateTime(2026, 1, 1, 12);
    const Duration window = Duration(hours: 24);

    MetricSample m(DateTime at, double v) => MetricSample(at: at, value: v);

    test('点数不超过 2×像素宽时原样返回', () {
      final List<MetricSample> samples = List<MetricSample>.generate(
        100,
        (int i) => m(now.subtract(Duration(minutes: 100 - i)), i.toDouble()),
      );
      final List<MetricSample> out = downsampleMetricSamples(
        samples: samples, now: now, window: window, width: 100,
      );
      expect(out.length, 100);
      expect(out.first.value, 0);
      expect(out.last.value, 99);
    });

    test('大数据量收敛到约 2×像素宽，且保留全局最小 / 最大值', () {
      final List<MetricSample> samples = List<MetricSample>.generate(
        10000,
        (int i) => m(now.subtract(Duration(seconds: (10000 - i) * 5)),
            i == 5000 ? 9999 : (i % 100).toDouble()),
      );
      final List<MetricSample> out = downsampleMetricSamples(
        samples: samples, now: now, window: window, width: 200,
      );
      expect(out.length, lessThanOrEqualTo(401));
      expect(out.any((MetricSample s) => s.value == 9999), isTrue);
      expect(out.any((MetricSample s) => s.value == 0), isTrue);
    });

    test('窗口外的点被过滤', () {
      final List<MetricSample> samples = <MetricSample>[
        m(now.subtract(const Duration(hours: 25)), 1),
        m(now.subtract(const Duration(hours: 1)), 2),
        m(now, 3),
      ];
      final List<MetricSample> out = downsampleMetricSamples(
        samples: samples, now: now, window: window, width: 100,
      );
      expect(out.map((MetricSample s) => s.value).toList(), <double>[2, 3]);
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
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/metric_sparkline_test.dart`
Expected: FAIL

- [ ] **Step 3: 由 `power_sparkline.dart` 迁移并改类型 + gap 支持**

复制 `power_sparkline.dart` 到 `metric_sparkline.dart`，做如下修改：
1. 类名 `PowerSparkline` → `MetricSparkline`，`_SparklinePainter` 保留原名。
2. `List<PowerSample>` → `List<MetricSample>`，所有 `s.watts` → `s.value`。
3. `downsamplePowerSamples` → `downsampleMetricSamples`；`_Plotted` 内 `sample.watts` → `sample.value`。
4. Widget 与 Painter 均新增 `final String unit;`（默认 `'W'`）与 `final Duration? gapThreshold;`。
5. 新增顶层纯函数（供测试与绘制共用）：

```dart
/// 按相邻点时间差切段：超过 [gap] 处断开（null 时整条为一段）。
@visibleForTesting
List<List<MetricSample>> splitByGap(
  List<MetricSample> samples,
  Duration? gap,
) {
  if (samples.isEmpty) return const <List<MetricSample>>[];
  if (gap == null) return <List<MetricSample>>[samples];
  final List<List<MetricSample>> out = <List<MetricSample>>[];
  List<MetricSample> current = <MetricSample>[samples.first];
  for (int i = 1; i < samples.length; i++) {
    if (samples[i].at.difference(samples[i - 1].at) > gap) {
      out.add(current);
      current = <MetricSample>[];
    }
    current.add(samples[i]);
  }
  out.add(current);
  return out;
}
```

6. `paint` 改为按段绘制：

```dart
  @override
  void paint(Canvas canvas, Size size) {
    _drawGrid(canvas, size);
    for (final List<Offset> segment in _segments(size)) {
      if (segment.length < 2) continue;
      _drawFill(canvas, size, segment);
      _drawLine(canvas, segment);
    }
    if (showLabels) {
      _drawLabels(canvas, size);
    }
  }
```

7. 用 `_segments` 取代 `_points`（支持负值，如零下温度）：

```dart
  ({double min, double max}) _valueRange(List<MetricSample> plotted) {
    double lo = plotted.first.value;
    double hi = plotted.first.value;
    for (final MetricSample s in plotted) {
      final double pointLo = math.min(s.value, s.min ?? s.value);
      final double pointHi = math.max(s.value, s.max ?? s.value);
      if (pointLo < lo) lo = pointLo;
      if (pointHi > hi) hi = pointHi;
    }
    if (hi - lo < 0.001) {
      lo = lo > 0 ? lo * 0.85 : lo * 1.15;
      hi = hi > 0 ? hi * 1.15 : hi * 0.85;
      if (hi - lo < 0.001) return (min: 0, max: 1);
    } else {
      final double pad = (hi - lo) * 0.15;
      lo -= pad;
      hi += pad;
    }
    return (min: lo, max: hi);
  }

  List<List<Offset>> _segments(Size size) {
    if (samples.isEmpty || size.width <= 0 || size.height <= 0) {
      return const <List<Offset>>[];
    }
    final DateTime now = DateTime.now();
    final int windowStartMs = now.subtract(window).millisecondsSinceEpoch;
    final int windowMs = window.inMilliseconds;
    if (windowMs <= 0) return const <List<Offset>>[];

    final List<MetricSample> plotted = downsampleMetricSamples(
      samples: samples,
      now: now,
      window: window,
      width: size.width,
    );
    if (plotted.isEmpty) return const <List<Offset>>[];

    final ({double min, double max}) range = _valueRange(plotted);
    final double span = range.max - range.min;

    return splitByGap(plotted, gapThreshold).map((List<MetricSample> part) {
      return part.map((MetricSample s) {
        final double t =
            (s.at.millisecondsSinceEpoch - windowStartMs).toDouble();
        final double x = (t / windowMs) * size.width;
        final double y =
            size.height - ((s.value - range.min) / span) * size.height;
        return Offset(
          x.clamp(0.0, size.width),
          y.clamp(0.0, size.height),
        );
      }).toList(growable: false);
    }).toList(growable: false);
  }
```

8. `_drawLabels` 使用 `unit` 与动态下界：

```dart
  void _drawLabels(Canvas canvas, Size size) {
    if (samples.isEmpty) return;
    final ({double min, double max}) range = _valueRange(samples);
    _text(canvas, '${_fmt(range.max)} $unit', Offset(size.width, 0),
        alignRight: true);
    _text(canvas, _fmt(range.min), Offset(size.width, size.height),
        alignRight: true, bottom: true);
    _text(canvas, _windowLabel(), Offset(0, size.height), bottom: true);
  }

  static String _fmt(double v) =>
      v.abs() >= 100 ? '${v.round()}' : v.toStringAsFixed(1);
```

9. 文件顶部补 `import 'dart:math' as math;`，`shouldRepaint` 增加 `unit` 与 `gapThreshold` 比较。

- [ ] **Step 4: 删除旧文件并跑测试**

```bash
git rm lib/features/home/presentation/components/power_sparkline.dart test/power_sparkline_test.dart
```

Run: `flutter test test/metric_sparkline_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/home/presentation/components/metric_sparkline.dart test/metric_sparkline_test.dart
git commit -m "refactor(history): rename PowerSparkline to MetricSparkline, add gap splitting"
```

---

## Task 9: MetricChartCard

**Files:**
- Create: `lib/features/home/presentation/components/metric_chart_card.dart`
- Test: `test/metric_chart_card_test.dart`

- [ ] **Step 1: Write the failing test**

```dart
// test/metric_chart_card_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/home/application/history_service.dart';
import 'package:pscreen_home/features/home/application/metric_history.dart';
import 'package:pscreen_home/features/home/domain/models/history_range.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';
import 'package:pscreen_home/features/home/domain/models/metric_sample.dart';
import 'package:pscreen_home/features/home/domain/repositories/home_repository.dart';
import 'package:pscreen_home/features/home/presentation/components/metric_chart_card.dart';

void main() {
  testWidgets('渲染 range 按钮与 metric 切换，默认 24h', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MetricChartCard(
            service: HistoryService(repository: _NoopRepo(), store: MetricHistoryStore()),
            deviceId: 'd',
            entityIds: const <Metric, String>{Metric.power: 'sensor.d'},
          ),
        ),
      ),
    );

    expect(find.text('1h'), findsOneWidget);
    expect(find.text('24h'), findsOneWidget);
    expect(find.text('周'), findsOneWidget);
    expect(find.text('月'), findsOneWidget);
    expect(find.text('年'), findsOneWidget);
    expect(find.text('功率'), findsOneWidget);
  });
}

class _NoopRepo implements HomeRepository {
  @override
  Future<List<MetricSample>> fetchMetricDetail({
    required List<String> entityIds,
    required DateTime start,
    required DateTime end,
  }) async => const <MetricSample>[];

  @override
  Future<List<MetricSample>> fetchMetricStats({
    required List<String> statisticIds,
    required DateTime start,
    required DateTime end,
    required String period,
  }) async => const <MetricSample>[];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/metric_chart_card_test.dart`
Expected: FAIL

- [ ] **Step 3: Write minimal implementation**

```dart
// lib/features/home/presentation/components/metric_chart_card.dart
import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/application/history_service.dart';
import 'package:pscreen_home/features/home/domain/models/history_range.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';
import 'package:pscreen_home/features/home/domain/models/metric_sample.dart';
import 'package:pscreen_home/features/home/presentation/components/metric_sparkline.dart';

/// 指标曲线卡：range 切换 + metric 切换 + 曲线。
class MetricChartCard extends StatefulWidget {
  const MetricChartCard({
    super.key,
    required this.service,
    required this.deviceId,
    required this.entityIds,
    this.initialMetric = Metric.power,
    this.initialRange = HistoryRange.h24,
  }) : assert(entityIds.length > 0, 'entityIds 不能为空');

  final HistoryService service;
  final String deviceId;
  final Map<Metric, String> entityIds;
  final Metric initialMetric;
  final HistoryRange initialRange;

  List<Metric> get availableMetrics => entityIds.keys.toList(growable: false);

  @override
  State<MetricChartCard> createState() => _MetricChartCardState();
}

class _MetricChartCardState extends State<MetricChartCard> {
  late Metric _metric = widget.availableMetrics.contains(widget.initialMetric)
      ? widget.initialMetric
      : widget.availableMetrics.first;
  late HistoryRange _range = widget.initialRange;
  List<MetricSample>? _samples;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final String? entityId = widget.entityIds[_metric];
    if (entityId == null) {
      if (mounted) setState(() => _samples = const <MetricSample>[]);
      return;
    }
    final List<MetricSample> samples = await widget.service.load(
      deviceId: widget.deviceId,
      metric: _metric,
      range: _range,
      entityId: entityId,
    );
    if (!mounted) return;
    setState(() => _samples = samples);
  }

  /// 明细段的断线阈值：采样越密、窗口越长，允许的间隔越大。
  static Duration? _gapFor(HistoryRange range) {
    switch (range) {
      case HistoryRange.h1:
      case HistoryRange.h6:
        return const Duration(minutes: 2);
      case HistoryRange.h12:
      case HistoryRange.h24:
        return const Duration(minutes: 10);
      case HistoryRange.week:
        return const Duration(hours: 1);
      case HistoryRange.month:
      case HistoryRange.year:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: <Widget>[
                  for (final HistoryRange r in HistoryRange.values)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(r.label),
                        selected: r == _range,
                        showCheckmark: false,
                        onSelected: (_) {
                          setState(() => _range = r);
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: <Widget>[
                  for (final Metric m in widget.availableMetrics)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(m.label),
                        selected: m == _metric,
                        showCheckmark: false,
                        onSelected: (_) {
                          setState(() => _metric = m);
                          _load();
                        },
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_samples != null)
              MetricSparkline(
                samples: _samples!,
                window: _range.duration,
                height: 120,
                unit: _metric.unit,
                gapThreshold: _gapFor(_range),
              ),
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/metric_chart_card_test.dart`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/home/presentation/components/metric_chart_card.dart test/metric_chart_card_test.dart
git commit -m "feat(history): add MetricChartCard with range and metric switching"
```

---

## Task 10: 接线与重命名引用

**Files:**
- Modify: `lib/core/di/modules/home_module.dart`
- Modify: `lib/features/home/application/bloc/home_bloc.dart`
- Modify: `lib/features/home/presentation/pages/device_detail_page.dart`
- Modify: `lib/features/home/presentation/pages/home_controll_board.dart`
- Modify: `lib/features/home/presentation/components/power_stats_card.dart`
- Modify: `lib/features/home/presentation/components/socket_widget.dart`
- Modify: `lib/features/home/presentation/components/socket_control_panel.dart`
- Modify: `lib/features/settings/presentation/pages/settings_page.dart`
- Modify: `test/control_panels_test.dart`、`test/home_bloc_test.dart`

- [ ] **Step 1: DI 注册**

`home_module.dart` 中把：
```dart
import 'package:pscreen_home/features/home/application/power_history.dart';
...
getIt.registerLazySingleton<PowerHistoryStore>(() => PowerHistoryStore());
getIt.registerLazySingleton<PowerSampler>(
  () => PowerSampler(
    store: getIt<PowerHistoryStore>(),
    log: getIt<LogService>(),
    interval: Duration(seconds: getIt<SettingsStore>().powerSampleSeconds),
  ),
);
```
改为：
```dart
import 'package:pscreen_home/features/home/application/history_service.dart';
import 'package:pscreen_home/features/home/application/metric_history.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';
...
getIt.registerLazySingleton<MetricHistoryStore>(() => MetricHistoryStore());
getIt.registerLazySingleton<MetricSampler>(
  () => MetricSampler(
    store: getIt<MetricHistoryStore>(),
    log: getIt<LogService>(),
    interval: Duration(seconds: getIt<SettingsStore>().powerSampleSeconds),
  ),
);
getIt.registerLazySingleton<HistoryService>(
  () => HistoryService(
    repository: getIt<HomeRepository>(),
    store: getIt<MetricHistoryStore>(),
  ),
);
```
`unregister()` 中把 `PowerSampler` / `PowerHistoryStore` 改为 `MetricSampler` / `MetricHistoryStore`。

- [ ] **Step 2: HomeBloc 类型与采样源（先接功率，温湿度在 Task 11 扩展）**

`home_bloc.dart`：
- import 改为 `metric_history.dart`，并补 `metric.dart`、`power_stats.dart`。
- `HomeBloc({required this.repository, required MetricSampler sampler})`。
- `final MetricSampler _sampler;`。
- reader 改为返回 `Map<String, Map<Metric, double?>>`：

```dart
_sampler.bind(() {
  final Map<String, Map<Metric, double?>> out = <String, Map<Metric, double?>>{};
  for (final MapEntry<String, PowerStats> entry in state.powerStats.entries) {
    if (entry.value.currentEntityId == null) continue;
    out[entry.key] = <Metric, double?>{Metric.power: entry.value.currentWatts};
  }
  return out;
});
```

- [ ] **Step 3: 重命名引用（批量）**

在以下文件中把 `PowerHistoryStore`→`MetricHistoryStore`、`PowerSampler`→`MetricSampler`、`PowerSample`→`MetricSample`、`PowerSparkline`→`MetricSparkline`、`power_history.dart`→`metric_history.dart`、`power_sparkline.dart`→`metric_sparkline.dart`、`power_sample.dart`→`metric_sample.dart`、`seriesOf('dev')`→`seriesOf('dev', Metric.power)`、`watch('dev')`→`watch('dev', Metric.power)`、`.watts`→`.value`：

- `home_controll_board.dart`：`historyStore.watch(socket.deviceId)` → `historyStore.watch(socket.deviceId, Metric.power)`。
- `device_detail_page.dart`：同上网格处 + 详情处。
- `power_stats_card.dart`：`ValueListenable<List<MetricSample>>? history`、`MetricSparkline`。
- `socket_widget.dart`、`socket_control_panel.dart`：同上。
- `settings_page.dart`：`Injection.get<MetricSampler>()`。
- `test/control_panels_test.dart`：`PowerSample`→`MetricSample`、`watts:`→`value:`、`PowerSparkline`→`MetricSparkline`。
- `test/home_bloc_test.dart`：import + `_powerSampler()` 用 `MetricSampler`。

- [ ] **Step 4: 静态检查**

删除已无引用的旧文件：

```bash
git rm lib/features/home/application/power_history.dart \
  lib/features/home/domain/models/power_sample.dart \
  test/power_history_test.dart \
  lib/features/home/presentation/components/power_sparkline.dart \
  test/power_sparkline_test.dart
```

Run: `flutter analyze`
Expected: No issues

- [ ] **Step 5: Commit**

```bash
git add lib/core/di/modules/home_module.dart \
  lib/features/home/application/bloc/home_bloc.dart \
  lib/features/home/presentation/pages/device_detail_page.dart \
  lib/features/home/presentation/pages/home_controll_board.dart \
  lib/features/home/presentation/components/power_stats_card.dart \
  lib/features/home/presentation/components/socket_widget.dart \
  lib/features/home/presentation/components/socket_control_panel.dart \
  lib/features/settings/presentation/pages/settings_page.dart \
  test/control_panels_test.dart test/home_bloc_test.dart
git commit -m "refactor(history): wire MetricHistoryStore/MetricSampler/HistoryService"
```

---

## Task 11: 温湿度采样接线

**Files:**
- Modify: `lib/features/home/application/bloc/home_bloc.dart`

- [ ] **Step 1: reader 采集三类指标**

把 `_sampler.bind(...)` 的 reader 改为：

```dart
_sampler.bind(() {
  final Map<String, Map<Metric, double?>> out = <String, Map<Metric, double?>>{};
  for (final HaDeviceGroup group in state.deviceGroups) {
    final Map<Metric, String> entities = MetricEntityResolver.resolve(group);
    if (entities.isEmpty) continue;
    final PowerStats? stats = state.powerStats[group.deviceId];
    final Map<Metric, double?> values = <Metric, double?>{};
    for (final MapEntry<Metric, String> e in entities.entries) {
      values[e.key] = e.key == Metric.power
          ? stats?.currentWatts
          : _entityValue(state, e.value);
    }
    if (values.isNotEmpty) out[group.deviceId] = values;
  }
  return out;
});
```

`_entityValue` 从实体的 state 解析（温度取 `double.tryParse(state)`；湿度同理）：

```dart
double? _entityValue(HomeState state, String entityId) {
  final HaEntityStateModel? entity = state.entities[entityId];
  if (entity == null || !entity.isAvailable) return null;
  return double.tryParse(entity.state);
}
```

并在 `home_bloc.dart` 顶部补 import：

```dart
import 'package:pscreen_home/features/home/domain/models/ha_device_group.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';
import 'package:pscreen_home/features/home/domain/models/metric_entity_resolver.dart';
import 'package:pscreen_home/features/home/domain/models/power_stats.dart';
```

- [ ] **Step 2: 详情页接线**

`device_detail_page.dart` 中把「用电信息」卡内的曲线去掉、在卡片下方接指标曲线卡（`group` 已在 build 顶部声明为 `HaDeviceGroup?`）：

```dart
                      if (devicePower != null) ...<Widget>[
                        const SizedBox(height: 12),
                        PowerStatsCard(stats: devicePower),
                        if (group != null &&
                            MetricEntityResolver.resolve(group).isNotEmpty) ...<Widget>[
                          const SizedBox(height: 12),
                          MetricChartCard(
                            service: Injection.get<HistoryService>(),
                            deviceId: deviceId,
                            entityIds: MetricEntityResolver.resolve(group),
                          ),
                        ],
                      ],
```

> 注意：`PowerStatsCard` 仍保留可选 `history` 参数（首页 `SocketWidget` 用），详情页不再传。

顶部补 import：

```dart
import 'package:pscreen_home/features/home/application/history_service.dart';
import 'package:pscreen_home/features/home/domain/models/metric_entity_resolver.dart';
import 'package:pscreen_home/features/home/presentation/components/metric_chart_card.dart';
```

- [ ] **Step 3: 静态检查**

Run: `flutter analyze`
Expected: No issues

- [ ] **Step 4: Commit**

```bash
git add lib/features/home/application/bloc/home_bloc.dart lib/features/home/presentation/pages/device_detail_page.dart
git commit -m "feat(history): sample power/temperature/humidity and wire chart card"
```

---

## Task 12: 验证

- [ ] **Step 1: 静态检查**

Run: `flutter analyze`
Expected: No issues

- [ ] **Step 2: 全量测试**

Run: `flutter test`
Expected: All tests passed

- [ ] **Step 3: 手动验证（需 HA）**

- `flutter run -d windows`，进详情页，切换 1/6/12/24h/周/月/年，确认：
  - ≤周出明细（阶梯/折线），月/年出聚合（更粗）；
  - 切换流畅、不重复请求（日志确认）；
  - 缺数据时段断线留空；
  - 温湿度 tab 显示正确实体；
  - 核对 HA 返回的 `lu`（明细）/`start`（统计）时间单位是否与 Task 3 假设一致，若不一致修正解析。
- 首页外卡片 24h 不受影响。

- [ ] **Step 4: Commit（仅当验证中做了修复）**

```bash
git add -A
git commit -m "fix(history): address verification findings"
```
