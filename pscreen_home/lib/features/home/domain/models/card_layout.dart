import 'package:pscreen_home/features/home/domain/models/device_type_dictionary.dart';
import 'package:pscreen_home/features/home/domain/models/ha_device_group.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/multi_switch_summary.dart';

/// 通用卡片布局树（服务端 deviceTypes.js 下发，字段与之对齐）。
///
/// 节点类型：row / column / wrap / text / icon / button / chip / progress /
/// sparkline / repeat / divider。渲染层见 presentation/components/json_card_renderer.dart。
/// 这里只做「解析 + 占位符求值」，不依赖 Flutter，便于单测。
class CardLayoutNode {
  const CardLayoutNode({
    required this.type,
    this.gap,
    this.crossAlign,
    this.mainAlign,
    this.expand = false,
    this.padding,
    this.value,
    this.size,
    this.weight,
    this.color,
    this.maxLines,
    this.align,
    this.icon,
    this.box,
    this.label,
    this.subLabel,
    this.onClick,
    this.style,
    this.visibleWhen,
    this.confirm,
    this.max,
    this.min,
    this.height,
    this.metric,
    this.window,
    this.showLabels = false,
    this.thickness,
    this.source,
    this.item,
    this.columns,
    this.map,
    this.round = false,
    this.interactive = false,
    this.children = const <CardLayoutNode>[],
    this.template,
  });

  final String type;
  final double? gap;
  final String? crossAlign;
  final String? mainAlign;
  final bool expand;
  final List<double>? padding;
  final String? value;
  final double? size;
  final int? weight;
  final String? color;
  final int? maxLines;
  final String? align;
  final String? icon;
  final CardIconBox? box;
  final String? label;
  final String? subLabel;
  final String? onClick;
  final String? style;
  final String? visibleWhen;
  final String? confirm;
  final String? max;
  final String? min;
  final double? height;
  final String? metric;
  final String? window;
  final bool showLabels;
  final double? thickness;
  final String? source;
  final String? item;
  final int? columns;

  /// 节点级值替换表：写法与 ESP 一致，如 "on=着灯,off=关闭"。
  /// 只作用于本节点 value/label 里占位符求值出来的原始值，不影响条件判断。
  final String? map;
  /// button 节点渲染成圆形（电源键用）。
  final bool round;
  /// progress 节点可拖动/点击调节（亮度条用），松手时发 onAction。
  final bool interactive;
  final List<CardLayoutNode> children;
  final CardLayoutNode? template;

  factory CardLayoutNode.fromJson(Map<String, dynamic> json) {
    final dynamic rawChildren = json['children'];
    final List<CardLayoutNode> children = <CardLayoutNode>[];
    if (rawChildren is List) {
      for (final dynamic c in rawChildren) {
        if (c is Map) {
          children.add(CardLayoutNode.fromJson(
              c.map((dynamic k, dynamic v) => MapEntry<String, dynamic>('$k', v))));
        }
      }
    }
    final dynamic rawBox = json['box'];
    final dynamic rawTpl = json['template'];
    return CardLayoutNode(
      type: '${json['type'] ?? ''}',
      gap: _num(json['gap']),
      crossAlign: json['crossAlign'] as String?,
      mainAlign: json['mainAlign'] as String?,
      expand: json['expand'] == true,
      padding: _padding(json['padding']),
      value: json['value'] == null ? null : '${json['value']}',
      size: _num(json['size']),
      weight: (json['weight'] as num?)?.toInt(),
      color: json['color'] as String?,
      maxLines: (json['maxLines'] as num?)?.toInt(),
      align: json['align'] as String?,
      icon: json['icon'] as String?,
      box: rawBox is Map
          ? CardIconBox.fromJson(
              rawBox.map((dynamic k, dynamic v) => MapEntry<String, dynamic>('$k', v)))
          : null,
      label: json['label'] == null ? null : '${json['label']}',
      subLabel: json['subLabel'] == null ? null : '${json['subLabel']}',
      onClick: json['onClick'] as String?,
      style: json['style'] as String?,
      visibleWhen: json['visibleWhen'] as String?,
      confirm: json['confirm'] as String?,
      max: json['max'] == null ? null : '${json['max']}',
      min: json['min'] == null ? null : '${json['min']}',
      height: _num(json['height']),
      metric: json['metric'] as String?,
      window: json['window'] as String?,
      showLabels: json['showLabels'] == true,
      thickness: _num(json['thickness']),
      source: json['source'] as String?,
      item: json['item'] as String?,
      columns: (json['columns'] as num?)?.toInt(),
      map: json['map'] == null ? null : '${json['map']}',
      round: json['round'] == true,
      interactive: json['interactive'] == true,
      children: children,
      template: rawTpl is Map
          ? CardLayoutNode.fromJson(
              rawTpl.map((dynamic k, dynamic v) => MapEntry<String, dynamic>('$k', v)))
          : null,
    );
  }

  static double? _num(dynamic v) => v is num ? v.toDouble() : null;

  static List<double>? _padding(dynamic v) {
    if (v is! List || v.isEmpty) return null;
    final double a = (v[0] as num?)?.toDouble() ?? 12;
    final double b = (v.length > 1 ? v[1] : v[0]) is num
        ? (v.length > 1 ? v[1] : v[0] as num).toDouble()
        : a;
    return <double>[a, b];
  }
}

class CardIconBox {
  const CardIconBox({this.size, this.radius, this.bg, this.color});

  final double? size;
  final double? radius;
  final String? bg;
  final String? color;

  factory CardIconBox.fromJson(Map<String, dynamic> json) => CardIconBox(
        size: (json['size'] as num?)?.toDouble(),
        radius: (json['radius'] as num?)?.toDouble(),
        bg: json['bg'] as String?,
        color: json['color'] as String?,
      );
}

/// 卡片跨格尺寸。
class CardSpan {
  const CardSpan({this.col = 1, this.row = 1});

  final int col;
  final int row;

  factory CardSpan.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const CardSpan();
    final int col = (json['col'] as num?)?.toInt() ?? 1;
    final int row = (json['row'] as num?)?.toInt() ?? 1;
    return CardSpan(
      col: col < 1 ? 1 : (col > 4 ? 4 : col),
      row: row < 1 ? 1 : (row > 4 ? 4 : row),
    );
  }
}

/// 占位符求值上下文：把布局树里的 {xxx} 替换为设备/实体/路 的运行时值。
class CardEvalContext {
  CardEvalContext({
    required this.group,
    required this.card,
    this.itemName,
    this.itemValues = const <String, String>{},
  });

  final HaDeviceGroup group;
  final DeviceCardConfig card;
  final String? itemName;
  final Map<String, String> itemValues;

  late final Map<String, String> _values = _buildValues();

  Map<String, String> _buildValues() {
    final HaEntityStateModel? primary = group.primary;
    final String state = primary?.state ?? '';
    final List<HaEntityStateModel> entities = group.entities;
    final String s1 = entities.length > 1 ? entities[1].state : state;
    final String s2 = entities.length > 2 ? entities[2].state : '';
    // 主数值：mainEntity 匹配的实体属性 → 主实体 state，套 mainFmt。
    String mainValue = _mainValue();
    final String mainFormatted = card.mainFmt.replaceAll('{v}', mainValue);
    // 副文案：subTpl 的 {state}/{s1}/{s2}/{main}。
    final String sub = card.subTpl
        .replaceAll('{main}', mainFormatted)
        .replaceAll('{state}', state)
        .replaceAll('{s1}', s1)
        .replaceAll('{s2}', s2);

    final Map<String, String> v = <String, String>{
      'title': group.title,
      'icon': card.icon,
      'color': card.color,
      'label': card.label,
      'main': mainFormatted,
      'sub': sub,
      'state': state,
      's1': s1,
      's2': s2,
      'status': group.statusLabel,
      'gangCount': '${group.switchableCount}',
      'gangOnCount': '${group.onCount}',
      'primary.entityId': primary?.entityId ?? '',
      'primary.switchable': primary != null ? 'true' : 'false',
      // 灯光亮度：brightnessPercent 0-100（无亮度能力时为 0），brightness 原始 0-255。
      'brightnessPercent': '${primary?.brightnessPercent ?? 0}',
      'brightness': '${primary?.brightnessValue ?? 0}',
    };
    // 组内实体属性：attr.xxx 指向主实体，entity.0.state / entity.1.state 等。
    if (primary != null) {
      primary.attributes.forEach((String k, dynamic value) {
        v['attr.$k'] = '$value';
      });
    }
    for (int i = 0; i < entities.length && i < 16; i++) {
      v['entity.$i.state'] = entities[i].state;
      v['entity.$i.id'] = entities[i].entityId;
      v['entity.$i.name'] = entities[i].displayName;
    }
    // repeat 项的值：{gang.xxx} / {item.xxx}。
    if (itemName != null && itemName!.isNotEmpty) {
      itemValues.forEach((String k, String value) {
        v['$itemName.$k'] = value;
        v['item.$k'] = value;
      });
    }
    return v;
  }

  String _mainValue() {
    final String want = card.mainEntity.trim();
    HaEntityStateModel? target;
    if (want.isNotEmpty && want != '主实体' && !want.startsWith('（')) {
      for (final HaEntityStateModel e in group.entities) {
        if (e.entityId.contains(want) || e.displayName.contains(want)) {
          target = e;
          break;
        }
      }
    }
    target ??= group.primary ?? (group.entities.isNotEmpty ? group.entities.first : null);
    if (target == null) return '--';
    final Object? attr = target.attributes[card.mainAttr];
    if (attr != null && '$attr'.isNotEmpty) return '$attr';
    return target.state;
  }

  /// 替换字符串里的 {占位符}。未知占位符替换为空串。
  /// [valueMap] 传入时对「占位符求值出来的原始值」做替换（如 off→关闭）；
  /// 条件判断（visibleWhen / 三元）不传它，始终基于原始值比较。
  String resolve(String raw, [Map<String, String>? valueMap]) {
    return raw.replaceAllMapped(RegExp(r'\{([^}]+)\}'), (Match m) {
      final String key = m.group(1)!.trim();
      // 支持简单三元：{gang.isOn ? '开' : '关'}（渲染层更常用预求值字段，这里兜底）。
      final String? direct = _values[key];
      if (direct != null) return _applyValueMap(direct, valueMap);
      if (key.contains('?')) return _applyValueMap(_resolveTernary(key), valueMap);
      return '';
    });
  }

  /// 把原始值按 map（"on=着灯,off=关闭"）替换；解析规则与 ESP 一致。
  static Map<String, String>? parseValueMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final Map<String, String> out = <String, String>{};
    // 逗号 / 中文逗号 / 分号 / 换行分隔；等号支持 = 与 ＝。
    for (final String part in raw.split(RegExp(r'[,，;；\n]+'))) {
      final String seg = part.trim();
      if (seg.isEmpty) continue;
      final int eq = seg.indexOf('=');
      if (eq <= 0) continue;
      final String key = seg.substring(0, eq).trim();
      String val = seg.substring(eq + 1).trim();
      if (val.length >= 2 &&
          ((val.startsWith("'") && val.endsWith("'")) ||
              (val.startsWith('"') && val.endsWith('"')))) {
        val = val.substring(1, val.length - 1);
      }
      if (key.isNotEmpty) out[key] = val;
    }
    return out.isEmpty ? null : out;
  }

  String _applyValueMap(String raw, Map<String, String>? valueMap) {
    if (valueMap == null || valueMap.isEmpty) return raw;
    return valueMap[raw] ?? valueMap[raw.toLowerCase()] ?? raw;
  }

  String _resolveTernary(String expr) {
    final int q = expr.indexOf('?');
    final int colon = expr.indexOf(':', q + 1);
    if (q < 0 || colon < 0) return '';
    final String condRaw = expr.substring(0, q).trim();
    final String truthy = _unquote(expr.substring(q + 1, colon).trim());
    final String falsy = _unquote(expr.substring(colon + 1).trim());
    final bool cond = _evalCondition(condRaw);
    return cond ? truthy : falsy;
  }

  String _unquote(String s) {
    if (s.length >= 2 && ((s.startsWith("'") && s.endsWith("'")) || (s.startsWith('"') && s.endsWith('"')))) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }

  /// 求值 visibleWhen / 三元条件：支持 = / != / 真值占位符。
  bool evalCondition(String expr) => _evalCondition(expr.trim());

  bool _evalCondition(String raw) {
    if (raw.isEmpty) return true;
    // a != b / a = b / a == b
    for (final String op in <String>['!=', '==', '=']) {
      final int idx = raw.indexOf(op);
      if (idx > 0) {
        final String left = resolve(raw.substring(0, idx).trim());
        final String right = _unquote(resolve(raw.substring(idx + op.length).trim()));
        return op == '!=' ? left != right : left == right;
      }
    }
    final String v = resolve(raw);
    return v.isNotEmpty && v != 'false' && v != '0';
  }
}

/// 由分组生成 repeat 的 gangs 列表值（每路一组占位符）。
List<Map<String, String>> gangValues(HaDeviceGroup group) {
  final List<Map<String, String>> out = <Map<String, String>>[];
  int idx = 0;
  for (final HaEntityStateModel e in group.switchableEntities) {
    // 复用旧专用卡片的短名逻辑：剥离设备名前缀、识别左键/右键，避免
    // repeat 大按钮上出现「设备名 右键-设备名-右键」这种超长文本。
    final String label = MultiSwitchSummary.labelFor(e, group.title, '${idx + 1} 路');
    final bool on = e.isOn;
    out.add(<String, String>{
      'label': label,
      'state': e.state,
      'stateLabel': on ? '已开启 · 点击关闭' : '已关闭 · 点击开启',
      'style': on ? 'active' : 'normal',
      'entityId': e.entityId,
      'index': '$idx',
    });
    idx++;
  }
  return out;
}
