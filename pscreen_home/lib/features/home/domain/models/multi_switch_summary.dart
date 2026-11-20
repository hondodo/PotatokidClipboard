import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/device_type_dictionary.dart';

/// 双开开关摘要：同一设备下的左键 / 右键两路开关。
class MultiSwitchSummary {
  const MultiSwitchSummary({
    required this.deviceId,
    required this.name,
    required this.gangs,
  });

  static MultiSwitchSummary? tryBuild({
    required String deviceId,
    required String name,
    required Iterable<HaEntityStateModel> entities,
  }) {
    // H2 显式消歧：admin 已把该设备声明为别的类型时，不再靠后缀误认领。
    if (DeviceTypeDictionary.active.isExplicitlyOtherType(deviceId, 'multi_switch')) {
      return null;
    }
    final HaEntityStateModel? left =
        _byIdEnding(entities, '_on_p_2_1', domain: 'switch');
    final HaEntityStateModel? right =
        _byIdEnding(entities, '_on_p_3_1', domain: 'switch');
    if (left == null || right == null) return null;

    return MultiSwitchSummary(
      deviceId: deviceId,
      name: name,
      gangs: <SwitchGang>[
        SwitchGang(
          label: labelFor(left, name, '左键'),
          entityId: left.entityId,
          isOn: left.isOn,
        ),
        SwitchGang(
          label: labelFor(right, name, '右键'),
          entityId: right.entityId,
          isOn: right.isOn,
        ),
      ],
    );
  }

  final String deviceId;
  final String name;
  final List<SwitchGang> gangs;

  bool get isAnyOn => gangs.any((SwitchGang gang) => gang.isOn);

  String get statusLabel => gangs
      .map((SwitchGang gang) => '${gang.label} ${gang.isOn ? '开' : '关'}')
      .join(' · ');

  /// 由实体显示名生成每路短标签：剥离设备名前缀，识别左键/右键，
  /// 其余取第一段。旧专用卡片与通用 JSON 卡片的 repeat 大按钮共用，
  /// 避免两处逻辑分叉（通用卡片若直接用 displayName 会得到超长文本）。
  static String labelFor(
    HaEntityStateModel entity,
    String deviceName,
    String fallback,
  ) {
    final String relative =
        entity.displayName.replaceFirst(deviceName, '').trim();
    if (relative.contains('右键')) return '右键';
    if (relative.contains('左键')) {
      final String head = relative.split(RegExp(r'\s+')).first;
      if (head.isNotEmpty && head != '左键') return head;
      return '左键';
    }
    return relative.isEmpty ? fallback : relative;
  }

  static HaEntityStateModel? _byIdEnding(
    Iterable<HaEntityStateModel> entities,
    String suffix, {
    required String domain,
  }) {
    for (final HaEntityStateModel entity in entities) {
      if (entity.domain != domain) continue;
      if (entity.entityId.endsWith(suffix)) return entity;
    }
    return null;
  }
}

class SwitchGang {
  const SwitchGang({
    required this.label,
    required this.entityId,
    required this.isOn,
  });

  final String label;
  final String entityId;
  final bool isOn;
}
