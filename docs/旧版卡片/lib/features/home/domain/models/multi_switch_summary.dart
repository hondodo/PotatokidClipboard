import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

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
          label: _label(left, name, '左键'),
          entityId: left.entityId,
          isOn: left.isOn,
        ),
        SwitchGang(
          label: _label(right, name, '右键'),
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

  static String _label(
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
