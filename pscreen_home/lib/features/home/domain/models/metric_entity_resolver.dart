import 'package:pscreen_home/features/home/domain/models/ha_device_group.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';
import 'package:pscreen_home/features/home/domain/models/metric_source.dart';

/// 按设备解析各 metric 的数据来源。
///
/// 优先级（分数高者胜）：
/// 1. `100`：entity_id 就是 `*_temperature` / `*_humidity` / `*_electric_power`
///    （模板 / 辅助元素最干净的命名）；
/// 2. `80`：HA 标准 `device_class`（temperature / humidity / power）；
/// 3. `40`：entity_id 中间出现该词元（如 `..._electric_power_p_5_1`）。
///
/// 这样 `..._humidity_range_p_10_6`（状态是 `40-70`）不会抢走真正的湿度计。
/// 数值型 sensor 全部落选时，才回退 climate 属性（仅内存曲线）。
abstract final class MetricEntityResolver {
  static const Map<Metric, String> _tokens = <Metric, String>{
    Metric.power: 'electric_power',
    Metric.temperature: 'temperature',
    Metric.humidity: 'humidity',
  };

  static const Map<Metric, String> _deviceClasses = <Metric, String>{
    Metric.power: 'power',
    Metric.temperature: 'temperature',
    Metric.humidity: 'humidity',
  };

  /// 返回该设备的 metric → 数据来源映射（缺失的 metric 不出现）。
  static Map<Metric, MetricSource> resolve(HaDeviceGroup group) =>
      resolveEntities(group.entities);

  /// 多实体版本（采样器按设备聚合全部实体后调用）。
  static Map<Metric, MetricSource> resolveEntities(
    Iterable<HaEntityStateModel> entities,
  ) {
    final Map<Metric, MetricSource> result = <Metric, MetricSource>{};
    final Map<Metric, int> scores = <Metric, int>{};

    void consider(Metric metric, MetricSource source, int score) {
      if (score <= 0) return;
      if (score > (scores[metric] ?? 0)) {
        scores[metric] = score;
        result[metric] = source;
      }
    }

    for (final HaEntityStateModel e in entities) {
      if (e.domain == 'sensor') {
        _tokens.forEach((Metric metric, String token) {
          consider(metric, MetricSource(e.entityId), _nameScore(e.entityId, token));
        });
      }
    }
    for (final HaEntityStateModel e in entities) {
      if (e.domain != 'sensor') continue;
      final Object? deviceClass = e.attributes['device_class'];
      _deviceClasses.forEach((Metric metric, String expected) {
        if (deviceClass == expected) {
          consider(metric, MetricSource(e.entityId), 80);
        }
      });
    }
    for (final HaEntityStateModel e in entities) {
      if (e.domain == 'climate') _addClimate(result, e);
    }
    return result;
  }

  /// entity_id 与词元的匹配质量：结尾（含整体）100，中间出现 40，否则 0。
  static int _nameScore(String entityId, String token) {
    final String id = entityId.toLowerCase();
    if (id == token || id.endsWith('_$token')) return 100;
    if (RegExp('(^|_)${RegExp.escape(token)}(_|\$)').hasMatch(id)) return 40;
    return 0;
  }

  static void _addClimate(
    Map<Metric, MetricSource> result,
    HaEntityStateModel e,
  ) {
    if (!result.containsKey(Metric.temperature) &&
        e.attributes['current_temperature'] != null) {
      result[Metric.temperature] =
          MetricSource(e.entityId, attribute: 'current_temperature');
    }
    if (!result.containsKey(Metric.humidity) &&
        e.attributes['current_humidity'] != null) {
      result[Metric.humidity] =
          MetricSource(e.entityId, attribute: 'current_humidity');
    }
  }
}
