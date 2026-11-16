import 'dart:convert';

/// 设备类型字典（home 端与 ESP 端共用的「规则源」在服务端）。
///
/// 背景：home 端原来靠 entity_id 后缀猜设备类型，`_status_p_2_2` 同时被
/// 洗衣机 / 空气炸锅 / 净水器使用，改一类规则就串到另一类。现在服务端
/// `pscreen_server/server/deviceTypes.js` 是唯一真源：admin 里每台设备显式
/// 声明类型，服务端经公开接口 `/api/device/device-types` 下发「类型规则 +
/// 设备分类映射」。本模型：
///  - 内置一份 fallback（与服务端默认规则一致），服务端不可达时用；
///  - 提供 [resolveExplicitType] 做显式类型判定，供 Summary 择机消歧；
///  - 提供 [displayLabel] / [step] 供详情页大字标签与步长统一取值。
///
/// 注意：home 仍直连 HA WebSocket 取实时状态（令牌在客户端），这里只替换
/// 「某类设备的主状态取哪个属性 / 怎么拼文案 / 大字标签 / 步长」这类语义规则，
/// 不改变取数通道，实时性不降级。

/// 判定条件（字段 + 操作符 + 值），与服务端 deviceTypes.js 的 cond 对齐。
/// 支持 domain / entity_id / name / state / attr.xxx / device.model|name|manufacturer。
class DeviceRuleCondition {
  const DeviceRuleCondition({
    required this.field,
    required this.op,
    required this.value,
  });

  final String field;
  final String op;
  final String value;

  factory DeviceRuleCondition.fromJson(Map<String, dynamic> json) {
    return DeviceRuleCondition(
      field: '${json['field'] ?? ''}',
      op: '${json['op'] ?? 'eq'}',
      value: '${json['value'] ?? ''}',
    );
  }

  /// 从一条实体记录取值。entity 至少含 id/domain/name/state/attrs/device。
  Object? _actual(Map<String, dynamic> entity) {
    if (field.startsWith('attr.')) {
      final dynamic attrs = entity['attrs'];
      final String k = field.substring(5);
      return attrs is Map ? attrs[k] : null;
    }
    if (field.startsWith('device.')) {
      final dynamic dev = entity['device'];
      final String k = field.substring(7);
      return dev is Map ? dev[k] : null;
    }
    return entity[field == 'entity_id' ? 'id' : field];
  }

  bool matches(Map<String, dynamic> entity) {
    final Object? actual = _actual(entity);
    if (op == 'exists') return actual != null && '$actual'.isNotEmpty;
    if (actual == null) return false;
    final String a = '$actual';
    final String v = value;
    switch (op) {
      case 'eq':
        return a == v;
      case 'neq':
        return a != v;
      case 'contains':
        if (actual is List) return actual.map((dynamic e) => '$e').join('|').contains(v);
        return a.contains(v);
      case 'not_contains':
        return !a.contains(v);
      case 'startsWith':
        // 与服务端一致：忽略 button. / switch. 域前缀。
        final int dot = a.indexOf('.');
        final String bare = dot >= 0 ? a.substring(dot + 1) : a;
        return a.startsWith(v) || bare.startsWith(v);
      case 'not_startsWith':
        final int dot = a.indexOf('.');
        final String bare = dot >= 0 ? a.substring(dot + 1) : a;
        return !a.startsWith(v) && !bare.startsWith(v);
      case 'gt':
        return (num.tryParse(a) ?? double.nan) > (num.tryParse(v) ?? double.infinity);
      case 'lt':
        return (num.tryParse(a) ?? double.nan) < (num.tryParse(v) ?? double.negativeInfinity);
      default:
        return false;
    }
  }
}

/// 一条判定规则：条件之间 AND，条件可由同一设备下不同实体满足。
class DeviceRule {
  const DeviceRule({
    required this.id,
    required this.name,
    required this.enabled,
    required this.conds,
  });

  final String id;
  final String name;
  final bool enabled;
  final List<DeviceRuleCondition> conds;

  factory DeviceRule.fromJson(Map<String, dynamic> json) {
    final dynamic raw = json['conds'];
    final List<DeviceRuleCondition> conds = <DeviceRuleCondition>[];
    if (raw is List) {
      for (final dynamic c in raw) {
        if (c is Map) {
          conds.add(DeviceRuleCondition.fromJson(
              c.map((dynamic k, dynamic v) => MapEntry<String, dynamic>('$k', v))));
        }
      }
    }
    return DeviceRule(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
      enabled: json['enabled'] != false,
      conds: conds,
    );
  }

  bool matches(List<Map<String, dynamic>> entities) {
    if (!enabled || conds.isEmpty) return false;
    return conds.every((DeviceRuleCondition c) => entities.any(c.matches));
  }

  int get specificity => conds.length;
}

/// 通用卡片上的一个按钮（文案 + 动作 kind）。
class DeviceCardButton {
  const DeviceCardButton({required this.label, required this.action});
  final String label;
  final String action;

  factory DeviceCardButton.fromJson(Map<String, dynamic> json) {
    return DeviceCardButton(
      label: '${json['label'] ?? '按钮'}',
      action: '${json['action'] ?? 'toggle'}',
    );
  }
}

/// 通用卡片配置：字段与服务端 card 对齐。
class DeviceCardConfig {
  const DeviceCardConfig({
    this.label = '当前值',
    this.mainAttr = 'state',
    this.mainFmt = '{v}',
    this.subTpl = '{state}',
    this.icon = '✦',
    this.color = '#4dd4ac',
    this.mainEntity = '',
    this.buttons = const <DeviceCardButton>[],
    this.genericEnabled = false,
  });

  final String label;
  final String mainAttr;
  final String mainFmt;
  final String subTpl;
  final String icon;
  final String color;
  final String mainEntity;
  final List<DeviceCardButton> buttons;
  final bool genericEnabled;

  factory DeviceCardConfig.fromJson(Map<String, dynamic> json) {
    final dynamic rawBtns = json['buttons'];
    final List<DeviceCardButton> buttons = <DeviceCardButton>[];
    if (rawBtns is List) {
      for (final dynamic b in rawBtns) {
        if (b is Map) {
          buttons.add(DeviceCardButton.fromJson(
              b.map((dynamic k, dynamic v) => MapEntry<String, dynamic>('$k', v))));
        }
      }
    }
    return DeviceCardConfig(
      label: '${json['label'] ?? '当前值'}',
      mainAttr: '${json['mainAttr'] ?? 'state'}',
      mainFmt: '${json['mainFmt'] ?? '{v}'}',
      subTpl: '${json['subTpl'] ?? '{state}'}',
      icon: '${json['icon'] ?? '✦'}',
      color: '${json['color'] ?? '#4dd4ac'}',
      mainEntity: '${json['mainEntity'] ?? ''}',
      buttons: buttons,
      genericEnabled: json['genericEnabled'] == true,
    );
  }
}

/// 单条类型规则。字段与服务端 DICT_DEFAULTS 一致，另含判定规则与卡片配置。
class DeviceTypeRule {
  const DeviceTypeRule({
    required this.key,
    required this.label,
    this.mainAttr = 'state',
    this.mainFmt = '{v}',
    this.subTpl = '{s1} · {s2}',
    this.step = '1',
    this.homeLabel = '当前状态',
    this.icon = '✦',
    this.color = '#4dd4ac',
    this.priority = 5,
    this.rules = const <DeviceRule>[],
    this.card,
  });

  final String key;
  final String label;
  final String mainAttr;
  final String mainFmt;
  final String subTpl;
  final String step;
  final String homeLabel;
  final String icon;
  final String color;
  final int priority;
  final List<DeviceRule> rules;
  final DeviceCardConfig? card;

  factory DeviceTypeRule.fromJson(Map<String, dynamic> json) {
    final String key = '${json['key'] ?? ''}';
    final dynamic raw = json['dict'];
    final Map<String, dynamic> dict = raw is Map
        ? raw.map((dynamic k, dynamic v) => MapEntry<String, dynamic>('$k', v))
        : <String, dynamic>{};
    final List<DeviceRule> rules = <DeviceRule>[];
    final dynamic rawRules = json['rules'];
    if (rawRules is List) {
      for (final dynamic r in rawRules) {
        if (r is Map) {
          rules.add(DeviceRule.fromJson(
              r.map((dynamic k, dynamic v) => MapEntry<String, dynamic>('$k', v))));
        }
      }
    }
    final dynamic rawCard = json['card'];
    return DeviceTypeRule(
      key: key,
      label: '${json['label'] ?? key}',
      mainAttr: '${dict['mainAttr'] ?? 'state'}',
      mainFmt: '${dict['mainFmt'] ?? '{v}'}',
      subTpl: '${dict['subTpl'] ?? '{s1} · {s2}'}',
      step: '${dict['step'] ?? '1'}',
      homeLabel: '${dict['homeLabel'] ?? '当前状态'}',
      icon: '${json['icon'] ?? '✦'}',
      color: '${json['color'] ?? '#4dd4ac'}',
      priority: int.tryParse('${json['priority'] ?? 5}') ?? 5,
      rules: rules,
      card: rawCard is Map
          ? DeviceCardConfig.fromJson(
              rawCard.map((dynamic k, dynamic v) => MapEntry<String, dynamic>('$k', v)))
          : null,
    );
  }

  /// 把主状态值套进格式模板（{v} 替换为实际值）。
  String formatMain(String value) => mainFmt.replaceAll('{v}', value);

  /// 该类型是否命中给定实体集合（本地兜底判定，规则 OR）。
  DeviceRule? firstMatchingRule(List<Map<String, dynamic>> entities) {
    for (final DeviceRule r in rules) {
      if (r.matches(entities)) return r;
    }
    return null;
  }
}

/// 内置 fallback：与服务端 DICT_DEFAULTS / DICT_DETAIL 的最小子集一致。
/// 只在服务端字典尚未拉到时使用；拉到后整体覆盖。
class DeviceTypeDictionary {
  DeviceTypeDictionary({
    Map<String, DeviceTypeRule>? rules,
    Map<String, String>? classification,
    Map<String, String>? autoClassification,
    Map<String, String>? manualClassification,
    Set<String>? genericCardTypes,
  })  : _rules = rules ?? _fallbackRules(),
        _classification = classification ?? const <String, String>{},
        _autoClassification = autoClassification ?? const <String, String>{},
        _manualClassification = manualClassification ?? const <String, String>{},
        _genericCardTypes = genericCardTypes ?? const <String>{};

  final Map<String, DeviceTypeRule> _rules;
  final Map<String, String> _classification;

  /// 服务端按规则自动判定的结果（device_id → 类型 key）。
  final Map<String, String> _autoClassification;

  /// admin 手动指定的分类，优先级高于自动判定。
  final Map<String, String> _manualClassification;

  /// 灰度：已开启通用卡片渲染的类型 key。
  final Set<String> _genericCardTypes;

  /// 当前生效字典（由 DeviceTypeStore 在 refresh 成功后设置）。
  /// 各 Summary 的 tryBuild 用它做显式类型消歧：admin 已声明类型的设备，
  /// 不再让靠后缀猜的另一类 Summary 误认领。默认 fallback，网络无关。
  static DeviceTypeDictionary active = DeviceTypeDictionary();

  DeviceTypeRule? rule(String key) => _rules[key];

  /// admin 显式分类映射：HA device_id → deviceType。空表示未分类。
  String? explicitTypeOf(String deviceId) => _classification[deviceId];

  /// 显式消歧守卫：设备已被 admin 声明为别的类型时返回 true，
  /// 对应 Summary 的 tryBuild 应据此跳过该设备（根治后缀串类）。
  /// 未声明（null）或声明为自己类型时返回 false，保留原有后缀逻辑。
  bool isExplicitlyOtherType(String deviceId, String myTypeKey) {
    final String? explicit = explicitTypeOf(deviceId);
    return explicit != null && explicit.isNotEmpty && explicit != myTypeKey;
  }

  /// 服务端判定的类型（手动 > 自动）。供通用卡片与详情页按配置渲染。
  String? classifiedTypeOf(String deviceId) =>
      _manualClassification[deviceId] ?? _autoClassification[deviceId];

  /// 灰度开关：该类型是否已开启通用卡片。未开启时继续用 13 个专用 Summary。
  bool useGenericCard(String typeKey) => _genericCardTypes.contains(typeKey);

  /// 本地兜底判定（服务端不可达时）：规则 OR、具体度优先、再按优先级。
  /// entities 为一组实体记录（id/domain/name/state/attrs/device）。
  String? classifyLocally(List<Map<String, dynamic>> entities) {
    String? bestKey;
    int bestSpecificity = -1;
    int bestPriority = -1;
    _rules.forEach((String key, DeviceTypeRule rule) {
      final DeviceRule? hit = rule.firstMatchingRule(entities);
      if (hit == null) return;
      final int specificity = hit.specificity;
      final int priority = rule.priority;
      if (specificity > bestSpecificity
          || (specificity == bestSpecificity && priority > bestPriority)) {
        bestKey = key;
        bestSpecificity = specificity;
        bestPriority = priority;
      }
    });
    return bestKey;
  }

  /// 详情页大字标签：优先取字典 homeLabel，缺失回退给定默认。
  String displayLabel(String key, {String fallback = '当前状态'}) =>
      _rules[key]?.homeLabel ?? fallback;

  /// 步长（如 0.5 / 1 / 25）：优先取字典 step，非数值返回 null。
  num? step(String key) {
    final String raw = _rules[key]?.step ?? '';
    return num.tryParse(raw);
  }

  /// 把某状态值按该类型的显示格式渲染（如 42.5 → 42.5°C）。
  String formatMain(String key, String value, {String fallback = '{v}'}) {
    final DeviceTypeRule? r = _rules[key];
    if (r == null) return fallback.replaceAll('{v}', value);
    return r.formatMain(value);
  }

  /// 从 `/api/device/device-types` 响应解析。返回新实例，失败抛 FormatException。
  factory DeviceTypeDictionary.fromApiJson(Map<String, dynamic> data) {
    final dynamic rawTypes = data['types'];
    final Map<String, DeviceTypeRule> rules = <String, DeviceTypeRule>{};
    if (rawTypes is List) {
      for (final dynamic item in rawTypes) {
        if (item is Map) {
          final Map<String, dynamic> m =
              item.map((dynamic k, dynamic v) => MapEntry<String, dynamic>('$k', v));
          final String key = '${m['key'] ?? ''}';
          if (key.isNotEmpty) rules[key] = DeviceTypeRule.fromJson(m);
        }
      }
    }
    final dynamic rawClass = data['classification'];
    final Map<String, String> classification = <String, String>{};
    if (rawClass is Map) {
      rawClass.forEach((dynamic k, dynamic v) {
        if (k is String && v is String && v.isNotEmpty) classification[k] = v;
      });
    }
    Map<String, String> parseMap(String key) {
      final Map<String, String> out = <String, String>{};
      final dynamic raw = data[key];
      if (raw is Map) {
        raw.forEach((dynamic k, dynamic v) {
          if (k is String && v is String && v.isNotEmpty) out[k] = v;
        });
      }
      return out;
    }

    final Set<String> generic = <String>{};
    final dynamic rawGeneric = data['genericCardTypes'];
    if (rawGeneric is List) {
      for (final dynamic g in rawGeneric) {
        if (g is String && g.isNotEmpty) generic.add(g);
      }
    }
    return DeviceTypeDictionary(
      rules: rules,
      classification: classification,
      autoClassification: parseMap('autoClassification'),
      manualClassification: parseMap('manualClassification'),
      genericCardTypes: generic,
    );
  }

  /// 解析 {"code":0,"data":{...}} 包装。
  factory DeviceTypeDictionary.fromEnvelope(String body) {
    final dynamic decoded = jsonDecode(body);
    if (decoded is! Map) throw const FormatException('字典响应不是对象');
    final dynamic data = decoded['data'];
    if (data is! Map) throw const FormatException('字典响应缺 data');
    return DeviceTypeDictionary.fromApiJson(
        data.map((dynamic k, dynamic v) => MapEntry<String, dynamic>('$k', v)));
  }

  static Map<String, DeviceTypeRule> _fallbackRules() {
    // 只列 home 端需要展示格式 / 标签 / 步长的常见类型；其余走通用默认。
    const Map<String, List<String>> seed = <String, List<String>>{
      // key, homeLabel, mainFmt, step
      'water_heater': <String>['当前水温', '{v}°C', '0.5'],
      'kettle': <String>['当前温度', '{v}°C', '1'],
      'fan': <String>['当前风速', '风速 {v}%', '25'],
      'climate': <String>['当前室温', '{v}°C', '0.5'],
      'light': <String>['灯光状态', '{v}', '10'],
      'air_fryer': <String>['工作状态', '{v}', '5'],
      'washer': <String>['运行状态', '{v}', '1'],
      'fridge': <String>['冷藏温度', '{v}°C', '1'],
      'rice_cooker': <String>['工作状态', '{v}', '1'],
      'socket': <String>['开关状态', '{v}', '1'],
      'purifier': <String>['运行状态', '{v}', '1'],
      'range_hood': <String>['运行状态', '{v}', '1'],
      'projector': <String>['播放状态', '{v}', '1'],
      'lock': <String>['门锁状态', '{v}', '1'],
      'home_climate': <String>['室内温度', '{v}°C', '1'],
    };
    final Map<String, DeviceTypeRule> out = <String, DeviceTypeRule>{};
    seed.forEach((String key, List<String> v) {
      out[key] = DeviceTypeRule(
          key: key, label: key, homeLabel: v[0], mainFmt: v[1], step: v[2]);
    });
    return out;
  }
}
