import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

/// 空调快捷开关：米家空调面板上的次级开关实体
/// （喜好 / 节能 / 睡眠 / 辅热 / 不直吹 / 提示音 / 熄屏）。
///
/// 米家空调（Xiaomi MIoT，如巨省电 m9 / h09h00）除 climate 主实体外
/// 还暴露若干 switch 子实体，entity_id 带固定属性后缀（如 `_eco_p_2_7`）。
/// 按后缀匹配出已知开关，按钮化到气候面板内（不再散落在下方原始行）。
class ClimateQuickSwitch {
  const ClimateQuickSwitch({
    required this.entityId,
    required this.label,
    required this.isOn,
  });

  /// MIoT 属性后缀 → 快捷按钮文案（列表顺序即展示顺序）。
  static const List<List<String>> _patterns = <List<String>>[
    <String>['_favorite_on_p_', '喜好'],
    <String>['_eco_p_', '节能'],
    <String>['_sleep_mode_p_', '睡眠'],
    <String>['_heater_p_', '辅热'],
    <String>['_un_straight_blowing_p_', '不直吹'],
    <String>['_alarm_p_', '提示音'],
    <String>['_run_dark_sleep_p_', '熄屏'],
  ];

  /// 从同设备实体中匹配已知快捷开关（仅 switch 域，保持 _patterns 顺序）。
  static List<ClimateQuickSwitch> buildList(
    Iterable<HaEntityStateModel> entities,
  ) {
    final List<ClimateQuickSwitch> result = <ClimateQuickSwitch>[];
    for (final List<String> pattern in _patterns) {
      for (final HaEntityStateModel entity in entities) {
        if (entity.domain == 'switch' &&
            entity.entityId.contains(pattern.first)) {
          result.add(ClimateQuickSwitch(
            entityId: entity.entityId,
            label: pattern.last,
            isOn: entity.isOn,
          ));
          break;
        }
      }
    }
    return result;
  }

  /// 实体 id
  final String entityId;

  /// 按钮文案
  final String label;

  /// 当前开关态
  final bool isOn;
}
