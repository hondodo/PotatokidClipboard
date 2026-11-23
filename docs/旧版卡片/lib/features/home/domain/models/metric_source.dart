import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

/// 一个指标的数据来源。
///
/// - 数值型 sensor：直接取实体 `state`，可查 HA 明细 / 长期统计；
/// - climate 属性（`current_temperature` / `current_humidity`）：HA 没有对应
///   时间序列，只能依赖本会话内存采样。
class MetricSource {
  const MetricSource(this.entityId, {this.attribute});

  /// HA 实体 id。
  final String entityId;

  /// 属性名；null 表示取实体 `state`。
  final String? attribute;

  /// 属性来源没有历史 / 统计可查（仅内存曲线）。
  bool get isAttribute => attribute != null;

  /// 从实体当前状态解析数值（不可用 / 非数值时返回 null）。
  double? valueOf(HaEntityStateModel entity) {
    final Object? raw =
        attribute == null ? entity.state : entity.attributes[attribute!];
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw);
    return null;
  }

  @override
  String toString() =>
      attribute == null ? entityId : '$entityId.$attribute';
}
