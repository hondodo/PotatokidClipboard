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
