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

  /// 支持控制（开关 / 参数）的实体域
  static const Set<String> switchableDomains = <String>{
    'light',
    'switch',
    'climate',
    'water_heater',
  };

  /// 动作类实体域：执行一次性动作（按一下），无开关态，暂不支持交互
  static const Set<String> actionDomains = <String>{
    'button',
    'event',
    'notify',
    'script',
    'tts',
    'conversation',
    'todo',
    'update',
    'automation',
    'scene',
    'remote',
  };

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

  /// 是否为开（climate / water_heater 的状态是模式，off 以外均视为开启）
  bool get isOn {
    if (!isAvailable) return false;
    if (domain == 'climate' || domain == 'water_heater') {
      return state != 'off';
    }
    return state == 'on';
  }

  /// 设备是否在线可用（unavailable / unknown 均不可控）
  bool get isAvailable => state != 'unavailable' && state != 'unknown';

  /// 是否为快捷控件可控实体
  bool get isSwitchable => isAvailable && switchableDomains.contains(domain);

  /// 是否不可用（unavailable / unknown）
  bool get isUnavailable => !isAvailable;

  /// 是否为动作类实体（无开关态，仅展示不交互）
  bool get isAction => actionDomains.contains(domain);

  /// 数据值 label：数据类实体的展示文案（如 `24.5 °C`、`开`、`55%`）。
  ///
  /// 拼接 state 与单位属性；on/off 中文化（binary_sensor 等）。
  String get valueLabel {
    final String unit = attributes['unit_of_measurement']?.toString() ?? '';
    final String text = switch (state) {
      'on' => '开',
      'off' => '关',
      _ => state,
    };
    return unit.isEmpty ? text : '$text $unit';
  }

  /// 是否为灯光实体
  bool get isLight => domain == 'light';

  /// 是否为空调 / 温控实体
  bool get isClimate => domain == 'climate';

  /// 是否为热水器实体
  bool get isWaterHeater => domain == 'water_heater';

  /// 热水器可选模式（operation_list）
  List<String> get operationModes => _asStrings(attributes['operation_list']);

  /// 热水器当前模式（water_heater 的 state 即 operation_mode）
  String get operationMode => state;

  /// select 实体的可选项（HA 通用 options 属性）
  List<String> get options => _asStrings(attributes['options']);

  /// number 实体的数值（state 本质是字符串）
  double? get numericState => double.tryParse(state);

  // ---------------------------------------------------------------- 灯光参数

  /// 当前亮度原始值（0-255，HA light 规范）
  int? get brightnessValue => _asInt(attributes['brightness']);

  /// 当前亮度百分比（0-100），关闭 / 不支持时为 null
  int? get brightnessPercent {
    final int? value = brightnessValue;
    if (value == null) return null;
    return (value / 255 * 100).round();
  }

  /// 支持的调光模式（onoff / brightness / color_temp / hs / rgb / xy …）
  List<String> get supportedColorModes =>
      _asStrings(attributes['supported_color_modes']);

  /// 是否支持调亮度（非纯开关灯）
  bool get supportsBrightness =>
      isLight && supportedColorModes.any((String m) => m != 'onoff');

  /// 是否支持色温调节（且拿到色温范围）
  bool get supportsColorTemperature =>
      isLight &&
      supportedColorModes.contains('color_temp') &&
      minColorTempKelvin != null &&
      maxColorTempKelvin != null;

  int? get minColorTempKelvin => _asInt(attributes['min_color_temp_kelvin']);
  int? get maxColorTempKelvin => _asInt(attributes['max_color_temp_kelvin']);
  int? get colorTempKelvin => _asInt(attributes['color_temp_kelvin']);

  /// 灯光效果（情景模式）列表，如 明亮模式 / 电视模式
  List<String> get effectList => _asStrings(attributes['effect_list']);

  /// 当前灯光效果，未启用时为 null
  String? get effect {
    final Object? value = attributes['effect'];
    return value is String && value.isNotEmpty ? value : null;
  }

  /// 是否支持灯光效果
  bool get supportsEffect => isLight && effectList.isNotEmpty;

  // ---------------------------------------------------------------- 空调参数

  /// 当前环境温度
  double? get currentTemperature =>
      _asDouble(attributes['current_temperature']);

  /// 目标温度（HA climate 的 temperature 属性）
  double? get targetTemperature => _asDouble(attributes['temperature']);

  /// 温度步进（0.5 / 1.0）
  double get targetTempStep =>
      _asDouble(attributes['target_temp_step']) ?? 0.5;

  /// 可设定最低温度
  double get minTargetTemperature => _asDouble(attributes['min_temp']) ?? 16;

  /// 可设定最高温度
  double get maxTargetTemperature => _asDouble(attributes['max_temp']) ?? 30;

  /// 当前湿度（%）
  int? get currentHumidity => _asInt(attributes['current_humidity']);

  /// 支持的运行模式（cool / heat / dry / fan_only / auto / off）
  List<String> get hvacModes => _asStrings(attributes['hvac_modes']);

  /// 当前运行模式（climate 的 state 即 hvac 模式）
  String get hvacMode => state;

  /// 运行状态（cooling / heating / idle / off …）
  String? get hvacAction {
    final Object? value = attributes['hvac_action'];
    return value is String && value.isNotEmpty ? value : null;
  }

  /// 风速档位列表（如 自动 / 一档 … / Max档）
  List<String> get fanModes => _asStrings(attributes['fan_modes']);

  /// 当前风速档位
  String? get fanMode {
    final Object? value = attributes['fan_mode'];
    return value is String && value.isNotEmpty ? value : null;
  }

  /// 摆风模式列表（off / vertical …）
  List<String> get swingModes => _asStrings(attributes['swing_modes']);

  /// 当前摆风模式
  String? get swingMode {
    final Object? value = attributes['swing_mode'];
    return value is String && value.isNotEmpty ? value : null;
  }

  /// 温度单位（默认摄氏度）
  String get temperatureUnit {
    final Object? value = attributes['temperature_unit'];
    return value is String && value.isNotEmpty ? value : '°C';
  }

  /// 合并属性补丁（乐观更新用）
  HaEntityStateModel mergeAttributes(Map<String, dynamic> patch) =>
      copyWith(attributes: <String, dynamic>{...attributes, ...patch});

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

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static List<String> _asStrings(Object? value) {
    if (value is! List) return const <String>[];
    return value.whereType<String>().toList(growable: false);
  }

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
