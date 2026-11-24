import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

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
    this.fill = false,
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
    this.enabledWhen,
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
    this.replace,
    this.colorMap,
    this.labelMap,
    this.iconMap,
    this.labelColor,
    this.stackAlign,
    this.position,
    this.round = false,
    this.interactive = false,
    this.marquee = false,
    this.marqueeMode,
    this.marqueeDirection,
    this.marqueePause = 2,
    this.marqueeSpeed = 40,
    this.children = const <CardLayoutNode>[],
    this.template,
  });

  final String type;
  final double? gap;
  final String? crossAlign;
  final String? mainAlign;
  final bool expand;
  /// column 填满可用高度（配合 mainAlign:spaceBetween 做上下分布，中间留白）。
  final bool fill;
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
  /// 按钮可点条件：不满足时按钮仍显示但禁用（onPressed=null），配合 colorMap 做暗色。
  /// 与 visibleWhen（整个节点不显示）互补，写法相同（如 "{s:_on_p_2_2}=on"）。
  final String? enabledWhen;
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
  /// 节点级子串替换表：写法 "旧串=新串,旧串2=新串2"，对占位符求值结果做
  /// replaceAll（与 map 的整体精确匹配互补）。新串留空即删除该子串；
  /// 支持任意字符（含中文/空格/标点），旧串可用引号包裹以包含逗号或等号。
  /// 只作用于本节点 value/label 里占位符求值出来的原始值，不影响条件判断。
  final String? replace;
  /// 条件属性映射：对单个属性里占位符求值结果做整值替换（写法同 map）。
  /// 与通用 map 分开，方便「同一状态驱动多属性」：如按钮 label 用 on=关闭/off=开启，
  /// color 用 on=#FF7043/off=#4dd4ac，icon 用 on=power_off/off=power_on。
  /// 只作用于各自属性的占位符求值结果，不影响条件判断。
  final String? colorMap;
  final String? labelMap;
  final String? iconMap;
  /// sparkline 标签（max/min/时间）颜色，null 时随主题。
  final String? labelColor;
  /// stack 节点：子节点的对齐（topLeft/topCenter/topRight/center/.../bottomRight）。
  final String? stackAlign;
  /// stack 节点：子节点的绝对定位（left/top/right/bottom，像素）。
  final CardPosition? position;
  /// button 节点渲染成圆形（电源键用）。
  final bool round;
  /// progress 节点可拖动/点击调节（亮度条用），松手时发 onAction。
  final bool interactive;
  /// text 节点：单行文字超宽时启用跑马灯，不再显示省略号。
  final bool marquee;
  /// loop=单向连续无缝滚动；pingpong=往返并在两端停留（默认 loop）。
  final String? marqueeMode;
  /// left/right：loop 表示滚动方向，pingpong 表示先往哪边跑（默认 left）。
  final String? marqueeDirection;
  /// pingpong 在两端各停留的秒数（默认 2）。
  final double marqueePause;
  /// 滚动速度，逻辑像素/秒（默认 40）。
  final double marqueeSpeed;
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
    final dynamic rawPos = json['position'];
    return CardLayoutNode(
      type: '${json['type'] ?? ''}',
      gap: _num(json['gap']),
      crossAlign: json['crossAlign'] as String?,
      mainAlign: json['mainAlign'] as String?,
      expand: json['expand'] == true,
      fill: json['fill'] == true,
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
      enabledWhen: json['enabledWhen'] as String?,
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
      replace: json['replace'] == null ? null : '${json['replace']}',
      colorMap: json['colorMap'] == null ? null : '${json['colorMap']}',
      labelMap: json['labelMap'] == null ? null : '${json['labelMap']}',
      iconMap: json['iconMap'] == null ? null : '${json['iconMap']}',
      labelColor: json['labelColor'] as String?,
      stackAlign: json['stackAlign'] == null ? null : '${json['stackAlign']}',
      position: rawPos is Map
          ? CardPosition.fromJson(
              rawPos.map((dynamic k, dynamic v) => MapEntry<String, dynamic>('$k', v)))
          : null,
      round: json['round'] == true,
      interactive: json['interactive'] == true,
      marquee: json['marquee'] == true,
      marqueeMode: json['marqueeMode'] as String?,
      marqueeDirection: json['marqueeDirection'] as String?,
      marqueePause: _num(json['marqueePause']) ?? 2,
      marqueeSpeed: _num(json['marqueeSpeed']) ?? 40,
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

/// stack 子节点的绝对定位（像素，null 表示不约束该边）。
class CardPosition {
  const CardPosition({this.left, this.top, this.right, this.bottom, this.width, this.height});

  final double? left;
  final double? top;
  final double? right;
  final double? bottom;
  final double? width;
  final double? height;

  factory CardPosition.fromJson(Map<String, dynamic> json) => CardPosition(
        left: _pos(json['left']),
        top: _pos(json['top']),
        right: _pos(json['right']),
        bottom: _pos(json['bottom']),
        width: _pos(json['width']),
        height: _pos(json['height']),
      );

  static double? _pos(dynamic v) => v is num ? v.toDouble() : null;
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
    this.areaLabel = '',
  });

  final HaDeviceGroup group;
  final DeviceCardConfig card;
  final String? itemName;
  final Map<String, String> itemValues;
  final String areaLabel;

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
      'room': areaLabel,
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
  /// [valueMap] 传入时对「占位符求值出来的原始值」做整体精确替换（如 off→关闭）；
  /// [replaceMap] 传入时先做子串替换（如去掉 friendly_name 里的设备型号前缀）。
  /// 两者都只作用于占位符求值结果，条件判断（visibleWhen / 三元）不传它们，
  /// 始终基于原始值比较。
  String resolve(String raw, [Map<String, String>? valueMap, Map<String, String>? replaceMap]) {
    return raw.replaceAllMapped(RegExp(r'\{([^}]+)\}'), (Match m) {
      final String full = m.group(1)!.trim();
      // 内联规则：{s:后缀|on=已开机,off=待机中}、{a:后缀.brightness|pct}。
      // 竖线后是本占位符专属的转换/映射，先于节点级 replace/map 生效，
      // 让一行文本里不同实体各用各的 on/off 文案、亮度单独转百分比。
      final int bar = full.indexOf('|');
      final String key = (bar > 0 ? full.substring(0, bar) : full).trim();
      final String rules = bar > 0 ? full.substring(bar + 1).trim() : '';
      String value = _resolveToken(key);
      if (rules.isNotEmpty) value = _applyInlineRules(value, rules);
      return _applyMaps(value, replaceMap, valueMap);
    });
  }

  /// 求值单个占位符 token（不含节点级 replace/map）。
  String _resolveToken(String key) {
    // 支持简单三元：{gang.isOn ? '开' : '关'}（渲染层更常用预求值字段，这里兜底）。
    final String? direct = _values[key];
    if (direct != null) return direct;
    // 按实体 id 后缀取值：{s:<后缀>}=state、{a:<后缀>.<属性>}=attribute、
    // {s:<后缀>.<属性>} 等价于 a:、{id:<后缀>}=完整 entity_id。用于同类实体很多、
    // 下标不稳定的设备（如热水瓶：保温开关 / 工作状态 / 模式 / 设定温度）。
    final String? entityValue = _resolveEntityToken(key);
    if (entityValue != null) return entityValue;
    if (key.contains('?')) return _resolveTernary(key);
    return '';
  }

  /// 占位符内联规则：
  /// - pct：HA light 的 0-255 → 0-100 百分比；
  /// - date / date:<pattern>：把 ISO 时间串按 Flutter DateFormat 格式化；
  ///   pattern 省略时默认 'yMd'；支持 'zh'/'en_US' 等 locale 前缀 `zh:yMd`；
  ///   也支持 DateFormat 简写名（yMd/Hms/yMEd/yMMM…），见 [_dateFormat]。
  /// - key=val：整值映射。
  /// 逗号分隔多条；值可用单/双引号包住以保护逗号。
  String _applyInlineRules(String value, String rules) {
    String out = value;
    final List<String> segments = _splitRuleSegments(rules);
    for (final String seg in segments) {
      final String s = seg.trim();
      if (s.isEmpty) continue;
      final String low = s.toLowerCase();
      if (low == 'pct') {
        final num? n = num.tryParse(out);
        if (n != null) {
          // HA light.brightness 规范为 0-255；若已是 0-100 则不再换算。
          out = '${n > 255 ? n.round() : (n / 255 * 100).round()}';
        }
        continue;
      }
      if (low == 'date' || low.startsWith('date:') || low.startsWith('date=')) {
        final String spec = s.length > 5 ? s.substring(5).trim() : '';
        out = _formatInlineDate(out, spec);
        continue;
      }
      final int eq = s.indexOf('=');
      if (eq <= 0) continue;
      final String rk = s.substring(0, eq).trim();
      String rv = s.substring(eq + 1).trim();
      if (rv.length >= 2 &&
          ((rv.startsWith("'") && rv.endsWith("'")) ||
              (rv.startsWith('"') && rv.endsWith('"')))) {
        rv = rv.substring(1, rv.length - 1);
      }
      if (rk == out || rk.toLowerCase() == out.toLowerCase()) out = rv;
    }
    return out;
  }

  /// 规则分段：逗号/中文逗号/分号分隔，引号内的分隔符不切（与 parseReplaceMap 一致）。
  static List<String> _splitRuleSegments(String raw) {
    final List<String> segments = <String>[];
    final StringBuffer cur = StringBuffer();
    String? quote;
    for (int i = 0; i < raw.length; i++) {
      final String ch = raw[i];
      if (quote != null) {
        cur.write(ch);
        if (ch == quote) quote = null;
        continue;
      }
      if (ch == "'" || ch == '"') {
        quote = ch;
        cur.write(ch);
        continue;
      }
      if (RegExp(r'[,，;；\n]').hasMatch(ch)) {
        segments.add(cur.toString());
        cur.clear();
        continue;
      }
      cur.write(ch);
    }
    segments.add(cur.toString());
    return segments;
  }

  /// ISO 时间 → DateFormat。spec 形如 `yMd`、`zh:yMd`、`yyyy-MM-dd HH:mm`。
  /// 无法解析成时间时原样返回（如 off 时的 'unknown'/空串）。
  static String _formatInlineDate(String raw, String spec) {
    final DateTime? dt = DateTime.tryParse(raw.trim());
    if (dt == null) return raw;
    String pattern = 'yMd';
    String locale = 'zh';
    final String trimmed = spec.trim();
    if (trimmed.isNotEmpty) {
      // locale 前缀形如 `zh:` / `en_US:`；避免把 `yyyy-MM-dd HH:mm` 里的冒号误判。
      final RegExp localePrefix = RegExp(r'^([a-z]{2,3}(?:_[A-Za-z]{2,4})?):(.+)$');
      final RegExpMatch? lm = localePrefix.firstMatch(trimmed);
      if (lm != null) {
        locale = lm.group(1)!;
        pattern = lm.group(2)!.trim();
      } else {
        pattern = trimmed;
      }
    }
    if (pattern.isEmpty) pattern = 'yMd';
    try {
      return _dateFormat(pattern, locale).format(dt);
    } catch (_) {
      // locale 数据未加载时回退到内建的 yMd。
      try {
        return DateFormat.yMd().format(dt);
      } catch (_) {
        return raw;
      }
    }
  }

  /// 把 pattern 映射为 DateFormat：优先使用构造函数简写（与 Flutter `DateFormat.yMd('zh')` 一致），
  /// 否则当作自定义 pattern 交给 DateFormat(pattern, locale)。
  static DateFormat _dateFormat(String pattern, String locale) {
    // en_US 数据内建，其它 locale 需按需初始化（重复调用无副作用）。
    if (locale != 'en_US' && locale != 'en') {
      initializeDateFormatting(locale, null);
    }
    switch (pattern) {
      case 'y':
        return DateFormat.y(locale);
      case 'M':
        return DateFormat.M(locale);
      case 'd':
        return DateFormat.d(locale);
      case 'E':
        return DateFormat.E(locale);
      case 'EEEE':
        return DateFormat.EEEE(locale);
      case 'yM':
        return DateFormat.yM(locale);
      case 'yMd':
        return DateFormat.yMd(locale);
      case 'yMEd':
        return DateFormat.yMEd(locale);
      case 'yMMM':
        return DateFormat.yMMM(locale);
      case 'yMMMd':
        return DateFormat.yMMMd(locale);
      case 'yMMMEd':
        return DateFormat.yMMMEd(locale);
      case 'yMMMM':
        return DateFormat.yMMMM(locale);
      case 'Hm':
        return DateFormat.Hm(locale);
      case 'Hms':
        return DateFormat.Hms(locale);
      case 'jm':
        return DateFormat.jm(locale);
      case 'jms':
        return DateFormat.jms(locale);
      default:
        return DateFormat(pattern, locale);
    }
  }

  /// 按 entity_id 后缀查找组内实体，返回指定 token。
  /// - `id:<后缀>` → 完整 entity_id（用于 toggle@ / press@）
  /// - `s:<后缀>` → 实体 state
  /// - `a:<后缀>.<属性>` → 实体 attribute
  String? _resolveEntityToken(String key) {
    final int colon = key.indexOf(':');
    if (colon <= 0) return null;
    final String kind = key.substring(0, colon).toLowerCase();
    final String rest = key.substring(colon + 1).trim();
    if (rest.isEmpty) return null;
    // s: 也支持点号读属性：{s:_s_3_ambient_light.brightness} 与 a: 等价，
    // 便于后台统一用后缀写法（用户常把亮度写成 s:后缀.brightness）。
    final int attrDot = (kind == 'a' || kind == 's') ? rest.lastIndexOf('.') : -1;
    if (kind == 'a' && attrDot <= 0) return null;
    final String pattern = (attrDot > 0 ? rest.substring(0, attrDot) : rest).toLowerCase();
    for (final HaEntityStateModel e in group.entities) {
      if (!e.entityId.toLowerCase().contains(pattern)) continue;
      switch (kind) {
        case 'id':
          return e.entityId;
        case 's':
          if (attrDot > 0) {
            final String attr = rest.substring(attrDot + 1);
            final Object? value = e.attributes[attr];
            return value == null ? '' : '$value';
          }
          return e.state;
        case 'a':
          final String attr = rest.substring(attrDot + 1);
          final Object? value = e.attributes[attr];
          return value == null ? '' : '$value';
      }
    }
    return null;
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

  /// 子串替换表："旧串=新串,…"。与 map 的区别：map 是整值精确匹配，
  /// replace 是 raw.replaceAll(旧, 新)，可删子串（新串留空）、可替换任意字符。
  /// 规则按逗号/中文逗号/分号/换行分隔；某一段用单/双引号整体包裹时，
  /// 引号内的分隔符不当作分隔（如 "旧,串=新,串"），并剥去外层引号。
  /// 等号用第一个 = 或 ＝；旧串/新串各自也可用引号包裹以保护首尾空格。
  static Map<String, String>? parseReplaceMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final Map<String, String> out = <String, String>{};
    // 逐字符切段：引号内遇到分隔符不切。
    final List<String> segments = <String>[];
    final StringBuffer cur = StringBuffer();
    String? quote;
    for (int i = 0; i < raw.length; i++) {
      final String ch = raw[i];
      if (quote != null) {
        cur.write(ch);
        if (ch == quote) quote = null;
        continue;
      }
      if (ch == "'" || ch == '"') {
        quote = ch;
        cur.write(ch);
        continue;
      }
      if (RegExp(r'[,，;；\n]').hasMatch(ch)) {
        segments.add(cur.toString());
        cur.clear();
        continue;
      }
      cur.write(ch);
    }
    segments.add(cur.toString());

    for (final String part in segments) {
      final String seg = part.trim();
      if (seg.isEmpty) continue;
      final int eq = seg.indexOf(RegExp(r'[=＝]'));
      if (eq <= 0) continue;
      String key = seg.substring(0, eq).trim();
      String val = seg.substring(eq + 1).trim();
      if (key.length >= 2 &&
          ((key.startsWith("'") && key.endsWith("'")) ||
              (key.startsWith('"') && key.endsWith('"')))) {
        key = key.substring(1, key.length - 1);
      }
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

  /// 先子串替换（replace），再整值精确替换（map）。
  String _applyMaps(String raw, Map<String, String>? replaceMap, Map<String, String>? valueMap) {
    String out = raw;
    if (replaceMap != null && replaceMap.isNotEmpty) {
      replaceMap.forEach((String old, String replacement) {
        if (old.isNotEmpty) out = out.replaceAll(old, replacement);
      });
    }
    return _applyValueMap(out, valueMap);
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
