import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

/// 插座快捷开关：米家智能插座（cuco v3 等）的次级开关实体
/// （童锁 / 定时 / 指示灯）。
///
/// 米家插座除主开关 `_on_p_2_1` 外还暴露若干子开关，entity_id 带固定
/// 属性后缀。按后缀匹配出已知开关，按钮化到插座面板内
/// （不再散落在下方原始行）。
///
/// 指示灯是 light 域（`_indicator_light`），其余为 switch 域。
/// 米家插座无「提示音」实体（与洗衣机 mibx2 不同），故不列。
class SocketQuickSwitch {
  const SocketQuickSwitch({
    required this.entityId,
    required this.label,
    required this.isOn,
  });

  /// 属性后缀 → 快捷按钮文案（列表顺序即展示顺序）。
  /// 仅 switch 域；light 域指示灯单独在 [indicatorLight] 处理。
  static const List<List<String>> _patterns = <List<String>>[
    <String>['_physical_controls_locked_p_', '童锁'],
    <String>['_mode_p_3_', '定时'],
  ];

  /// 从同设备实体中匹配已知快捷开关（仅 switch 域，保持 _patterns 顺序）。
  static List<SocketQuickSwitch> buildList(
    Iterable<HaEntityStateModel> entities,
  ) {
    final List<SocketQuickSwitch> result = <SocketQuickSwitch>[];
    for (final List<String> pattern in _patterns) {
      for (final HaEntityStateModel entity in entities) {
        if (entity.domain == 'switch' &&
            entity.entityId.contains(pattern.first)) {
          result.add(SocketQuickSwitch(
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

  /// 指示灯实体（light 域，`_indicator_light`），无则 null。
  ///
  /// 返回其实体 id，便于面板以灯泡图标单列一个开关。
  static String? indicatorLightEntityId(
    Iterable<HaEntityStateModel> entities,
  ) {
    for (final HaEntityStateModel entity in entities) {
      if (entity.domain == 'light' &&
          entity.entityId.contains('_indicator_light')) {
        return entity.entityId;
      }
    }
    return null;
  }

  /// 指示灯当前是否开（实体不存在则视为关）。
  static bool indicatorLightOn(
    Iterable<HaEntityStateModel> entities,
  ) {
    for (final HaEntityStateModel entity in entities) {
      if (entity.domain == 'light' &&
          entity.entityId.contains('_indicator_light')) {
        return entity.isOn;
      }
    }
    return false;
  }

  /// 实体 id
  final String entityId;

  /// 按钮文案
  final String label;

  /// 当前开关态
  final bool isOn;
}
