/// Home Assistant 实体状态（light.xxx / switch.xxx …）。
///
/// 对应 `get_states` 返回项，也是 `state_changed` 事件里 `new_state` 的结构。
/// 不可变，通过 copyWith 更新；由 data 层反序列化（fromJson），domain 与
/// presentation 统一使用本模型。
///
/// 注：按 AGENT.md 约定复杂模型应使用 freezed 生成，但当前 freezed 3.2.5
/// 在 Dart 3.13 下对「含集合字段的模型」会生成非法的 `final` 构造参数，
/// 故暂按 potatokid_screen 的 weather_models 风格手写，待升级 freezed 后恢复。
class HaEntityStateModel {
  const HaEntityStateModel({
    required this.entityId,
    required this.state,
    required this.attributes,
  });

  factory HaEntityStateModel.fromJson(Map<String, dynamic> json) {
    final Object? rawId = json['entity_id'];
    if (rawId is! String || rawId.isEmpty) {
      throw FormatException('实体状态缺少 entity_id：$json');
    }
    final dynamic rawState = json['state'];
    final dynamic rawAttributes = json['attributes'];
    return HaEntityStateModel(
      entityId: rawId,
      state: rawState is String ? rawState : '$rawState',
      attributes: rawAttributes is Map
          ? Map<String, dynamic>.from(rawAttributes)
          : const <String, dynamic>{},
    );
  }

  /// 支持「一键开关」的实体域
  static const Set<String> switchableDomains = <String>{'light', 'switch'};

  /// 实体 id，如 light.bedroom_light
  final String entityId;

  /// 实体状态值，如 on / off / unavailable
  final String state;

  /// 实体属性（含 friendly_name、brightness 等）
  final Map<String, dynamic> attributes;

  /// 实体域（entity_id 的前缀，如 light）
  String get domain => entityId.split('.').first;

  /// 显示名：优先 friendly_name，其次 entity_id 去掉域前缀
  String get displayName {
    final Object? name = attributes['friendly_name'];
    if (name is String && name.isNotEmpty) return name;
    return entityId.split('.').skip(1).join('.');
  }

  /// 是否为开
  bool get isOn => state == 'on';

  /// 设备是否在线可用（unavailable / unknown 均不可控）
  bool get isAvailable => state != 'unavailable' && state != 'unknown';

  /// 是否为快捷控件可控实体
  bool get isSwitchable => isAvailable && switchableDomains.contains(domain);

  HaEntityStateModel copyWith({
    String? entityId,
    String? state,
    Map<String, dynamic>? attributes,
  }) {
    return HaEntityStateModel(
      entityId: entityId ?? this.entityId,
      state: state ?? this.state,
      attributes: attributes ?? this.attributes,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is HaEntityStateModel &&
      other.entityId == entityId &&
      other.state == state &&
      _mapEquals(other.attributes, attributes);

  @override
  int get hashCode => Object.hash(entityId, state, attributes.length);

  @override
  String toString() => 'HaEntityStateModel($entityId, $state)';

  static bool _mapEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final MapEntry<String, dynamic> entry in a.entries) {
      if (!b.containsKey(entry.key) || b[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }
}
