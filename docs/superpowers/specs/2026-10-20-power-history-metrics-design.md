# 功率 / 温湿度历史曲线（HA 数据源）— 设计文档

日期：2026-10-20
状态：待评审

## 背景与目标

现状（`lib/features/home/application/power_history.dart`）：

- `PowerHistoryStore` 仅驻内存、24h 滑动窗口，退出即丢；
- `PowerSampler` 按设置间隔（默认 5s）采样功率，写入内存 store；
- `PowerSparkline` 用 `CustomPainter` 画折线，按逻辑像素分桶降采样（min/max），已支持 `window` 参数；
- `PowerStatsCard` 展示当前功率 + 累计电量 + 24h 趋势。

目标：

1. 历史数据**完全依赖 HA**：近期明细查 `history/history_during_period`，长期查 `recorder/statistics_during_period`；App **不新增本地持久化**。
2. 详情页曲线支持 range 切换：**1 / 6 / 12 / 24 小时、周、月、年**。
3. **平滑曲线**：保留内存 5s 采样作为实时底，HA 历史补全此前部分。
4. 缺数据时段**留空断线**（不跨 gap 连线）。
5. 首页外卡片保持 24h，不改。
6. **温湿度一起做**：同一套机制扩展 power / temperature / humidity 三类 metric。

HA 侧前提（已实测确认）：

- recorder 默认启用（`history` 的依赖），明细默认保留 `purge_keep_days: 10` 天；
- 长期统计（每小时聚合）**永久保留**，与 `purge_keep_days` 无关，仅对有 `state_class`（`measurement` 等）的 sensor 生效；
- 功率 / 温湿度 sensor 均为 `measurement`，有 `mean/min/max`。

## 方案决策

| 备选 | 说明 | 结论 |
|---|---|---|
| A. 本地采样 + 本地持久化（SQLite/文件） | App 自己存，跨重启、可控保留 | 否 — HA 已提供 10 天明细 + 永久小时统计，重复建设、增加依赖与体积 |
| B. 完全依赖 HA（明细 + 统计） | 近期查明细，长期查统计；App 仅内存缓存 | **采用** |
| C. 混合（本地近期 + HA 长期） | 本地存高频平滑曲线 | 否 — 用户确认走 HA；内存采样已满足「实时平滑」 |

## 一、总体架构

```
[实时]  MetricSampler(5s) ──► MetricHistoryStore(内存, 24h, 平滑, ValueNotifier)
                                       │
[历史]  HA ──► history/history_during_period      (≤ purge_keep_days, 明细)
           └► recorder/statistics_during_period    (> purge_keep_days, 聚合)
                                       │
                          HistoryService（选源 + 合并 + 缓存）
                                       │
                       MetricChartCard（range 按钮 + metric 切换 + 曲线）
```

分层（遵循 AGENT.md）：

| 层 | 文件 | 职责 |
|---|---|---|
| Network | `lib/core/network/ha_ws_client.dart` | 新增 `historyDuringPeriod` / `statisticsDuringPeriod`（返回原始 `result`） |
| Domain | `lib/features/home/domain/models/metric_sample.dart`、`metric.dart`、`history_range.dart`、`metric_entity_resolver.dart` | 样本 / metric / range 模型与实体识别 |
| Domain | `lib/features/home/domain/repositories/home_repository.dart` | 新增 `fetchMetricDetail` / `fetchMetricStats` |
| Data | `lib/features/home/data/repositories/home_repository_impl.dart` | 调 WS、解析 HA 返回为 `MetricSample` |
| Application | `lib/features/home/application/metric_history.dart` | `MetricHistoryStore` + `MetricSampler` |
| Application | `lib/features/home/application/history_service.dart` | 选源（含自适应兜底）+ 合并 + 缓存 |
| Presentation | `lib/features/home/presentation/components/metric_chart_card.dart` | range 按钮 + metric 切换 + 曲线 |
| Presentation | `lib/features/home/presentation/pages/device_detail_page.dart` | 用 `MetricChartCard` 替换现有 `PowerStatsCard` 的曲线部分 |

## 二、数据模型

```dart
/// 指标类型。
enum Metric { power, temperature, humidity }

/// 单指标曲线范围。
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
}

/// 一个采样点：时刻 + 值（功率 W / 温度 °C / 湿度 %）。
///
/// 明细曲线只有 [value]；统计聚合曲线用 [value] 存均值，
/// [min] / [max] 存区间最小 / 最大值（用于 y 轴范围，可选）。
class MetricSample {
  const MetricSample({required this.at, required this.value, this.min, this.max});
  final DateTime at;
  final double value;
  final double? min;
  final double? max;
}
```

- `MetricHistoryStore`：按 `deviceId + metric` 存内存序列（24h 滑动窗口），沿用 `ValueNotifier` 通知；提供 `seriesOf` / `watch` / `record` / `clear`。
- `PowerSample` 由 `MetricSample` 取代（`Metric.power`）；旧 `PowerHistoryStore` / `PowerSampler` 重命名为 `MetricHistoryStore` / `MetricSampler`。

## 三、HA 接口层

`HaWsClient` 新增两个方法（`request` 返回完整消息，调用方取 `result`）。**只返回原始 `result`**，不依赖 feature 领域模型；解析在 data 层完成：

```dart
/// 明细历史：HA 只记录状态变化（阶梯），minimal_response 减负载。
Future<Object?> historyDuringPeriod({
  required List<String> entityIds,
  required DateTime start,
  required DateTime end,
});

/// 长期统计：period = hour|day；types = [mean,min,max]。
Future<Object?> statisticsDuringPeriod({
  required List<String> statisticIds,
  required DateTime start,
  required DateTime end,
  required String period, // 'hour' | 'day'
});
```

- 明细请求：`{type:'history/history_during_period', start_time, end_time, entity_ids, include_start_time_state:true, significant_changes_only:true, minimal_response:true, no_attributes:true}`，`HomeRepositoryImpl` 解析 `{entity_id:[{s,lu}]}` → `MetricSample(at: lu, value: double.parse(s))`。
- 统计请求：`{type:'recorder/statistics_during_period', start_time, end_time, statistic_ids, period, types:['mean','min','max']}`，解析 `{statistic_id:[{start,mean,min,max}]}` → `MetricSample(at: start, value: mean, min: min, max: max)`。
- 非数值 state（`unavailable`/`unknown`）跳过；解析失败跳过该点（形成 gap）。

## 四、HistoryService（选源 + 合并 + 缓存）

```dart
class HistoryService {
  /// 取某设备某 metric 某 range 的曲线点（明细或统计）。
  Future<List<MetricSample>> load({
    required String deviceId,
    required Metric metric,
    required HistoryRange range,
    required String entityId,
    DateTime? now,
  });
}
```

选源规则（不依赖 `purge_keep_days` 精确值）：

| range | 首选源 | 粒度 |
|---|---|---|
| h1 / h6 / h12 / h24 | 明细（+ 内存平滑） | 原始 |
| week | 明细（+ 内存平滑） | 原始 |
| month | 统计 `period: hour` | 小时 |
| year | 统计 `period: day` | 日 |

- **自适应兜底**：明细请求返回后，若最早点晚于 `start + 容差`（说明该段已被 purge），则对整个 range 改用统计。这样无需知道 `purge_keep_days` 也能自动适配。
- 统计 `period`：`range ≤ 60 天` 用 `hour`，否则 `day`。
- `purge_keep_days` 是 recorder 集成内部配置，HA **无 WS API 暴露**（`get_config` 只返回核心配置），故不做读取。
- **合并（平滑关键）**：以 HA 明细为底，叠加本会话 `MetricHistoryStore` 采样；同一时刻内存优先，按时间排序去重。
- **缓存**：`Map<(deviceId, metric, range), CachedSeries>`，TTL 60s；切换回同一 range 不重复拉取。缓存仅内存，不落盘。
- 请求去重：同一 key 并发只发一次。

## 五、采样与平滑

- `MetricSampler` 每 N 秒（设置项，默认 5s）遍历所有设备，按 metric 采集：
  - power：`powerStats[deviceId].currentWatts`；
  - temperature / humidity：见第七节实体识别。
- 写入 `MetricHistoryStore`（24h 窗口），驱动首页外卡片与详情页实时刷新。
- 曲线渲染统一用**折线连接**（非阶梯）：内存 5s 底 + HA 历史拼接后按时间排序，`PowerSparkline`（重命名为 `MetricSparkline`）绘制。
- **缺数据留空**：相邻点时间差 > 阈值视为 gap，断线不连。阈值按 range：h1/h6 → 2min，h12/h24 → 10min，week → 1h；统计聚合点等距，不断线。
  - 实现补充：HA 明细用 `significant_changes_only`，恒定值传感器的相邻点可能相隔数小时，故阈值再取 `max(基准阈值, 5 × 中位间隔)`（`adaptiveGap`），避免把恒定值误判成缺数据。

## 六、UI：MetricChartCard

- 顶部两行控件：
  - range 按钮行：`1h / 6h / 12h / 24h / 周 / 月 / 年`（`SegmentedButton` 或等宽 `ToggleButtons`，窄屏可横向滚动）；
  - metric 切换：`功率 / 温度 / 湿度`（无对应实体的 metric 不显示）。
- 下方曲线：`MetricSparkline`，高度固定（如 120），右上角最大/最新值，左下角 range 标签。
- 曲线下的统计行（可选）：当前值 / 区间最大 / 区间均值。
- **详情页接线**：把现有 `PowerStatsCard` 的**曲线部分**替换为 `MetricChartCard`；其数值区（当前功率 / 累计电量 / 设备温度 / 开关次数）保留。
- **首页外卡片**（`socket_widget` / `power_stats_card`）保持 24h 内存曲线，不改。

### 重命名与影响面

| 旧 | 新 |
|---|---|
| `PowerSample` | `MetricSample` |
| `PowerHistoryStore` | `MetricHistoryStore` |
| `PowerSampler` | `MetricSampler` |
| `PowerSparkline` | `MetricSparkline` |

影响：首页外卡片、详情页、设置页（采样间隔）、`home_module.dart`、相关测试。保留旧名 `Power*` 会与新 `Metric*` 语义重叠，故统一重命名。

## 七、温湿度实体识别

`MetricEntityResolver`（domain 层）按设备解析各 metric 的 entity id：

| metric | 识别规则 |
|---|---|
| power | `sensor` 域且 id 含 `_electric_power_`（现有 `PowerStats` 逻辑） |
| temperature | `sensor` 域且 id 含 `_temperature_` |
| humidity | `sensor` 域且 id 含 `_humidity_` |

- **只接受数值型 `sensor`**：只有它们具备可查询的时间序列（明细 + 长期统计）。
  `climate` 的温度/湿度是属性、状态是 `cool`/`heat` 等字符串，无法作为统计曲线数据源，故不参与。
- 解析结果随 `HaDeviceGroup` 缓存，注册表刷新时重算。
- 无对应实体的 metric 在 UI 隐藏；HA 统计查询只传已解析的 entity id。

## 八、性能与存储

- 明细：`minimal_response: true` + `no_attributes: true` + `significant_changes_only: true`，显著减负载；客户端按像素降采样（已有）。
- 统计：HA 端预聚合，月 ≈ 720 点、年 ≈ 365 点，极小。
- 内存缓存 + 请求去重，避免切换 range 重复拉取。
- **App 零本地存储**；HA 侧 `purge_keep_days` 建议 10（明细），长期统计永久保留。

## 九、验证与测试

1. **单测**（新增 `test/metric_history_test.dart`、`test/history_service_test.dart`）：
   - 选源规则：各 range → 明细 / 统计；≤周范围内明细首点晚于起点（被 purge）时整体回退统计（自适应兜底，不读 `purge_keep_days`）；
   - HA 明细 / 统计返回解析（含 `unavailable`、非数值、空结果）；
   - 合并去重：内存优先、按时间排序；
   - 缺数据留空：gap 判定阈值；
   - `MetricSparkline` 降采样（沿用现有测试）+ `splitByGap` 切段；
2. **静态检查**：`flutter analyze` 零问题。
3. **手动验证**（需 HA）：
   - 详情页切换 1/6/12/24h/周/月/年，曲线粒度正确、无重复请求；
   - 缺数据时段断线留空；
   - 温湿度 metric 显示正确实体；
   - 首页外卡片 24h 不受影响。

## 十、范围外

- 本地持久化 / 导出 CSV；
- 多设备对比曲线；
- 曲线缩放 / 拖拽查看具体时刻数值；
- 利用 HA `history/stream` 做增量订阅（当前按需拉取）。

## 里程碑

- **M1** 模型 + HA 接口层 + Repository（明细 / 统计解析，单测）。
- **M2** `MetricHistoryStore` / `MetricSampler` + `HistoryService`（选源 + 合并 + 缓存，单测）。
- **M3** `MetricChartCard`（range + metric 切换 + 缺数据留空）+ 详情页接线。
- **M4** 温湿度实体识别 + 采样接线。
- **M5** 手动验证 + `flutter analyze` / `flutter test` 全绿。
