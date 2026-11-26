import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:pscreen_home/features/home/domain/models/device_type_dictionary.dart';
import 'package:pscreen_home/features/home/domain/models/ha_device_group.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/domain/models/multi_switch_summary.dart';

/// 通用卡片布局树（服务端 deviceTypes.js 下发，字段与之对齐）。
///
/// 节点类型：row / column / wrap / text / icon / button / chip / progress /
/// sparkline / repeat / divider / spacer / sizedBox。
/// 渲染层见 presentation/components/json_card_renderer.dart。
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
    // 设备不可用（state=unavailable/unknown）时专用前景色；留空回退主题禁用色。
    // 与 color 职责严格分离：color 只管可用态，unavailableColor 只管不可用态，互不顶替。
    this.unavailableColor,
    // 节点背景：bg 是颜色规范（可含占位符），bgMap 按同一求值结果选区间颜色。
    this.bg,
    this.bgMap,
    this.bgRadius,
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
    // progress 滑条配色：trackColor=未填充底轨/槽色，thumbColor=拖动拇指（白条）色。
    // 留空保持现状（在线白拇指/主题槽色、离线灰拇指）；配了即覆盖，支持占位符/颜色规范。
    this.trackColor,
    this.thumbColor,
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
    this.flex,
    this.width,
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
  /// 设备不可用时的前景色（颜色规范/占位符/阈值规则结果）。
  /// 未配置时沿用主题禁用色 outline。支持 {color}/#RRGGBB/#RRGGBBAA/语义色名。
  final String? unavailableColor;
  /// 节点背景色（颜色规范/占位符/阈值规则结果），由 bgMap 命中后覆盖。
  final String? bg;
  /// 背景色阈值映射，如 ">=30=#FF5252,>=20=#FFB74D,default=#4CAF50"。
  final String? bgMap;
  /// 背景圆角，默认 12。
  final double? bgRadius;
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
  /// progress 未填充底轨/槽色（颜色规范/占位符/阈值结果）；留空保持主题默认。
  final String? trackColor;
  /// progress 拖动拇指（白条）颜色；留空在线白/离线主题灰。
  final String? thumbColor;
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
  /// spacer 节点：权重（默认 1）。多个 spacer 按 flex 比例分配剩余空间。
  final double? flex;
  /// sizedBox 节点：固定宽度（像素，null 表示不约束）。
  final double? width;
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
      unavailableColor: json['unavailableColor'] == null ? null : '${json['unavailableColor']}',
      bg: json['bg'] as String?,
      bgMap: json['bgMap'] == null ? null : '${json['bgMap']}',
      bgRadius: _num(json['bgRadius']),
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
      trackColor: json['trackColor'] == null ? null : '${json['trackColor']}',
      thumbColor: json['thumbColor'] == null ? null : '${json['thumbColor']}',
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
      flex: _num(json['flex']),
      width: _num(json['width']),
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
  /// - date / date:`pattern`：把 ISO 时间串按 Flutter DateFormat 格式化；
  ///   带时区偏移（如 `+00:00`/`Z`）的时间会先转成本地时间再显示；
  ///   pattern 省略时默认 'yMd'；支持 'zh'/'en_US' 等 locale 前缀 `zh:yMd`；
  ///   也支持 DateFormat 简写名（yMd/Hms/yMEd/yMMM…），见 [_dateFormat]。
  /// - maxWith=<占位符 key>：当前值与另一个占位符都是 ISO 时间时取较晚者。
  /// - ago：ISO 时间 → 相对时间（刚刚 / N分钟前 / N小时前 / N天前）。
  /// - when=<占位符 key>:<期望值>=<文案>：另一个占位符当前值等于期望值时，把本占位符输出替换为文案
  ///   （如充电中覆盖开机文案；key 内含冒号，从右侧起第二个冒号分隔期望值）。
  /// - key=val：整值映射。
  /// 逗号分隔多条；值可用单/双引号包住以保护逗号。
  String _applyInlineRules(String value, String rules) {
    String out = value;
    // default 是兜底：只有前面没有任何规则/when 命中时才生效，且不受规则出现顺序影响。
    String? deferredDefault;
    bool matched = false;
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
      // maxWith=<占位符 key>：当前值与另一个占位符都是 ISO 时间时取较晚的一个。
      // 用于「最后接入/最后断开」这类二选一展示；非时间值以可解析的一方为准。
      if (low == 'maxwith' || low.startsWith('maxwith=')) {
        final int eqAt = s.indexOf('=');
        final String otherKey = eqAt > 0 ? s.substring(eqAt + 1).trim() : '';
        if (otherKey.isNotEmpty) {
          final String other = _resolveToken(otherKey);
          final DateTime? a = DateTime.tryParse(out.trim());
          final DateTime? b = DateTime.tryParse(other.trim());
          if (a != null && b != null) {
            out = a.toUtc().isAfter(b.toUtc()) ? out : other;
          } else if (a == null && b != null) {
            out = other;
          }
        }
        continue;
      }
      // ago：ISO 时间 → 相对时间（刚刚 / N分钟前 / N小时前 / N天前）。
      // 非时间值原样返回，后面可再接映射把 unknown/unavailable 转成 —。
      if (low == 'ago') {
        out = _formatAgo(out);
        continue;
      }
      // when=<key>:<期望值>=<文案>：另一个占位符当前值等于期望值时覆盖本占位符输出。
      // 从右往左找冒号分隔期望值（key 形如 s:_charging_state_p_5_2 自带冒号）；
      // 等号取最后一个，文案里可含等号。
      if (low.startsWith('when=')) {
        final String spec = s.substring(5).trim();
        final int eqAt = spec.lastIndexOf('=');
        final int colonAt = spec.lastIndexOf(':', eqAt > 0 ? eqAt : spec.length);
        if (eqAt > 0 && colonAt > 0 && colonAt < eqAt) {
          final String otherKey = spec.substring(0, colonAt).trim();
          final String expected = spec.substring(colonAt + 1, eqAt).trim();
          String replacement = spec.substring(eqAt + 1).trim();
          if (replacement.length >= 2 &&
              ((replacement.startsWith("'") && replacement.endsWith("'")) ||
                  (replacement.startsWith('"') && replacement.endsWith('"')))) {
            replacement = replacement.substring(1, replacement.length - 1);
          }
          final String other = _resolveToken(otherKey);
          if (other == expected || other.toLowerCase() == expected.toLowerCase()) {
            out = replacement;
          }
        }
        continue;
      }
      final MapEntry<String, String>? rule = _parseRuleSegment(s);
      if (rule == null) continue;
      final String ruleLow = rule.key.toLowerCase();
      if (ruleLow == 'default' || ruleLow == 'else') {
        deferredDefault ??= rule.value;
        continue;
      }
      final String? hit = applyRulesOrNull(out, <String, String>{rule.key: rule.value});
      if (hit != null) {
        out = hit;
        matched = true;
      }
    }
    // 前面的转换规则（pct/date/ago/when）也算「已命中」，不再套 default 兜底。
    if (!matched && deferredDefault != null && out == value) out = deferredDefault;
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
  /// HA 的 last_updated 等字段常带 `+00:00`，DateTime.parse 会得到 UTC 时间；
  /// 直接格式化会少 8 小时，所以统一 toLocal() 再显示。无时区的裸时间串解析出来
  /// 已是本地时间，toLocal() 不会改变它。无法解析时原样返回（如 off 时的 'unknown'）。
  static String _formatInlineDate(String raw, String spec) {
    final DateTime? parsed = DateTime.tryParse(raw.trim());
    if (parsed == null) return raw;
    final DateTime dt = parsed.toLocal();
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

  /// ISO 时间 → 相对时间文案，对齐 HA 前端的「52分钟前」展示。
  /// 非时间值原样返回，便于串接 `unknown=—` 等映射。
  static String _formatAgo(String raw) {
    final DateTime? dt = DateTime.tryParse(raw.trim());
    if (dt == null) return raw;
    final Duration diff = DateTime.now().difference(dt.toLocal());
    if (diff.inSeconds <= 0 || diff.inMinutes < 1) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
    if (diff.inHours < 24) return '${diff.inHours}小时前';
    if (diff.inDays < 30) return '${diff.inDays}天前';
    try {
      return DateFormat('yyyy-MM-dd').format(dt.toLocal());
    } catch (_) {
      return raw;
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
  /// 键可带比较符（">=30=高温"），此时由 [applyRules] 按有序阈值匹配。
  static Map<String, String>? parseValueMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final Map<String, String> out = <String, String>{};
    // 逗号 / 中文逗号 / 分号 / 换行分隔；引号内的分隔符不切。
    for (final String seg in _splitRuleSegments(raw)) {
      final MapEntry<String, String>? rule = _parseRuleSegment(seg);
      if (rule != null) out[rule.key] = rule.value;
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

  String _applyValueMap(String raw, Map<String, String>? valueMap) =>
      applyRules(raw, valueMap);

  /// 有序规则匹配（阈值区间 + 整值精确，兼容旧 map 写法）。
  /// 规则按出现顺序检查，第一条命中的数值比较胜出；`default` 作兜底，
  /// 与位置无关。支持 `>=` `<=` `!=` `==` `>` `<` `=`；非数值输入只走精确匹配。
  static String applyRules(String raw, Map<String, String>? rules) =>
      applyRulesOrNull(raw, rules) ?? raw;

  /// 同 [applyRules]，但没有任何规则命中（也没有 default）时返回 null，
  /// 供动态背景等场景区分「未命中」与「命中了空串」。
  static String? applyRulesOrNull(String raw, Map<String, String>? rules) {
    if (rules == null || rules.isEmpty) return null;
    // 整值精确匹配优先，保持旧写法（on=开,off=关）行为不变。
    final String? exact = rules[raw] ?? rules[raw.toLowerCase()];
    if (exact != null) return exact;
    final num? n = num.tryParse(raw.trim());
    String? fallback;
    for (final MapEntry<String, String> e in rules.entries) {
      final String key = e.key;
      final String low = key.toLowerCase();
      if (low == 'default' || low == 'else') {
        fallback ??= e.value;
        continue;
      }
      final String? op = _ruleOperator(key);
      if (op == null) continue;
      final num? threshold = num.tryParse(key.substring(op.length).trim());
      if (threshold == null || n == null) continue;
      final bool hit;
      switch (op) {
        case '>=':
          hit = n >= threshold;
          break;
        case '<=':
          hit = n <= threshold;
          break;
        case '>':
          hit = n > threshold;
          break;
        case '<':
          hit = n < threshold;
          break;
        case '!=':
          hit = n != threshold;
          break;
        case '==':
        case '=':
          hit = n == threshold;
          break;
        default:
          hit = false;
      }
      if (hit) return e.value;
    }
    return fallback;
  }

  /// 取规则键的比较操作符前缀；没有则返回 null（即普通精确键）。
  static String? _ruleOperator(String key) {
    for (final String op in const <String>['>=', '<=', '!=', '==', '>', '<', '=']) {
      if (key.startsWith(op)) return op;
    }
    return null;
  }

  /// 解析单条 `key=value` 规则，支持 key 自带比较符（如 `>=30=高温`）。
  /// 值可用单/双引号包裹以保护首尾空格。
  static MapEntry<String, String>? _parseRuleSegment(String seg) {
    final String s = seg.trim();
    if (s.isEmpty) return null;
    final String? op = _ruleOperator(s);
    final int eq = s.indexOf('=', op == null ? 0 : op.length);
    if (eq <= (op == null ? 0 : op.length)) return null;
    final String key = s.substring(0, eq).trim();
    if (key.isEmpty) return null;
    String val = s.substring(eq + 1).trim();
    if (val.length >= 2 &&
        ((val.startsWith("'") && val.endsWith("'")) ||
            (val.startsWith('"') && val.endsWith('"')))) {
      val = val.substring(1, val.length - 1);
    }
    return MapEntry<String, String>(key, val);
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

  /// 求值 visibleWhen / enabledWhen / 三元条件。
  /// 支持 `= != == > >= < <=` 与真值占位符；比较时两边若能解析为数值则按数值比较，
  /// 否则按字符串比较（如 `{attr.battery_level}>=20`）。
  bool evalCondition(String expr) => _evalCondition(expr.trim());

  bool _evalCondition(String raw) {
    if (raw.isEmpty) return true;
    // 长操作符优先，避免 ">=" 被当成 ">" 或 "=" 提前截断。
    for (final String op in <String>['>=', '<=', '!=', '==', '>', '<', '=']) {
      final int idx = raw.indexOf(op);
      if (idx <= 0) continue;
      final String left = resolve(raw.substring(0, idx).trim());
      final String right = _unquote(resolve(raw.substring(idx + op.length).trim()));
      final num? ln = num.tryParse(left.trim());
      final num? rn = num.tryParse(right.trim());
      if (ln != null && rn != null) {
        switch (op) {
          case '>=':
            return ln >= rn;
          case '<=':
            return ln <= rn;
          case '>':
            return ln > rn;
          case '<':
            return ln < rn;
          case '!=':
            return ln != rn;
          default:
            return ln == rn;
        }
      }
      switch (op) {
        case '!=':
          return left != right;
        case '>=':
        case '<=':
        case '>':
        case '<':
          // 非数值无法比较大小，按字符串字典序兜底，行为可预期。
          final int cmp = left.compareTo(right);
          if (op == '>=') return cmp >= 0;
          if (op == '<=') return cmp <= 0;
          if (op == '>') return cmp > 0;
          return cmp < 0;
        default:
          return left == right;
      }
    }
    final String v = resolve(raw);
    return v.isNotEmpty && v != 'false' && v != '0';
  }
}

/// 空调风速档位步进目标。
///
/// - `modes` 来自实体 attributes.fan_modes（如 自动/一档…七档/Max档），不硬编码档位顺序；
/// - `delta == null`（旧写法 `climateFan@<实体>`）：循环到下一档，保持原「风速」chip 行为；
/// - `delta` 为 +1/-1：按索引步进并钳制在两端（− 到自动、+ 到最大都不会回绕）。
///
/// 列表为空时返回 null，调用方应拒绝下发指令。
String? climateFanStepTarget(List<String> modes, String current, {int? delta}) {
  if (modes.isEmpty) return null;
  final int idx = modes.indexOf(current);
  if (delta == null) return modes[(idx + 1) % modes.length];
  if (delta == 0) return current.isEmpty ? modes.first : current;
  int next = (idx < 0 ? (delta > 0 ? -1 : 0) : idx) + delta;
  if (next < 0) next = 0;
  if (next >= modes.length) next = modes.length - 1;
  return modes[next];
}

/// 解析 `selectOption@<entityId>[:<option>]` 动作。
///
/// 实体 id 里不会有冒号，按第一个冒号拆分，选项本身可含冒号
/// （如假日模式的 `23:00-06:00`）。不带选项（无冒号）时 option 为 null，
/// 表示按实体 options 循环到下一项（菜单只有一个大按钮时用）。
/// 返回 null 表示动作格式非法，调用方应拒绝下发。
({String entityId, String? option})? parseSelectOptionAction(String action) {
  const String prefix = 'selectOption@';
  if (!action.startsWith(prefix)) return null;
  final String rest = action.substring(prefix.length).trim();
  final int sep = rest.indexOf(':');
  if (sep < 0) {
    if (rest.isEmpty) return null;
    return (entityId: rest, option: null);
  }
  if (sep == 0) return null;
  final String entityId = rest.substring(0, sep).trim();
  final String option = rest.substring(sep + 1).trim();
  if (entityId.isEmpty || option.isEmpty) return null;
  return (entityId: entityId, option: option);
}

/// 解析 `fanOscillate@<entityId>[:<on|off>]` 动作。
///
/// 不带参数：由调用方按实体当前 `oscillating` 取反；带参数直接设定。
/// 返回 null 表示格式非法，调用方应拒绝下发。
({String entityId, bool? oscillating})? parseFanOscillateAction(String action) {
  const String prefix = 'fanOscillate@';
  if (!action.startsWith(prefix)) return null;
  final String rest = action.substring(prefix.length).trim();
  final int sep = rest.indexOf(':');
  final String entityId = (sep > 0 ? rest.substring(0, sep) : rest).trim();
  if (entityId.isEmpty) return null;
  if (sep <= 0) return (entityId: entityId, oscillating: null);
  final String arg = rest.substring(sep + 1).trim().toLowerCase();
  if (arg == 'on' || arg == 'true' || arg == '1') {
    return (entityId: entityId, oscillating: true);
  }
  if (arg == 'off' || arg == 'false' || arg == '0') {
    return (entityId: entityId, oscillating: false);
  }
  return null;
}

/// 解析 `fanMode@<entityId>[:<mode>]` 动作。
///
/// 不带 mode：由调用方在实体 `preset_modes` 里循环到下一个；
/// 带 mode：直接设为指定模式（bloc 会校验该值在列表里）。
({String entityId, String? mode})? parseFanModeAction(String action) {
  const String prefix = 'fanMode@';
  if (!action.startsWith(prefix)) return null;
  final String rest = action.substring(prefix.length).trim();
  final int sep = rest.indexOf(':');
  final String entityId = (sep > 0 ? rest.substring(0, sep) : rest).trim();
  if (entityId.isEmpty) return null;
  if (sep <= 0) return (entityId: entityId, mode: null);
  final String mode = rest.substring(sep + 1).trim();
  if (mode.isEmpty) return null;
  return (entityId: entityId, mode: mode);
}

/// 解析 `waterHeaterTemp@<entityId>:<delta>` 动作。
///
/// delta 为带符号的温度增量（如 `+1` / `-1` / `0.5`），实体 id 里不会有冒号，
/// 按最后一个冒号拆分。返回 null 表示格式非法，调用方应拒绝下发。
/// 真正的 step 对齐与 min/max 钳制由 bloc 完成，这里只负责解析。
({String entityId, double delta})? parseWaterHeaterTempAction(String action) {
  const String prefix = 'waterHeaterTemp@';
  if (!action.startsWith(prefix)) return null;
  final String rest = action.substring(prefix.length).trim();
  final int sep = rest.lastIndexOf(':');
  if (sep <= 0) return null;
  final String entityId = rest.substring(0, sep).trim();
  final double? delta = double.tryParse(rest.substring(sep + 1).trim());
  if (entityId.isEmpty || delta == null || delta == 0) return null;
  return (entityId: entityId, delta: delta);
}

/// 解析 `number@<entityId>:<delta>` 动作。
///
/// delta 为带符号增量（如 `+5` / `-5` / `+1`），实体 id 里不会有冒号，
/// 按最后一个冒号拆分。返回 null 表示格式非法，调用方应拒绝下发。
({String entityId, double delta})? parseNumberAction(String action) {
  const String prefix = 'number@';
  if (!action.startsWith(prefix)) return null;
  final String rest = action.substring(prefix.length).trim();
  final int sep = rest.lastIndexOf(':');
  if (sep <= 0) return null;
  final String entityId = rest.substring(0, sep).trim();
  final double? delta = double.tryParse(rest.substring(sep + 1).trim());
  if (entityId.isEmpty || delta == null || delta == 0) return null;
  return (entityId: entityId, delta: delta);
}

/// 按 number 实体的 min/max/step 计算 ± 后的目标值：先钳制到 [min, max]，
/// 再按 step 对齐（以 min 为基准）。min/max/step 缺失时用宽松兜底。
double numberStepTarget({
  required double current,
  required double delta,
  Object? min,
  Object? max,
  Object? step,
}) {
  double? asDouble(Object? v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  final double lo = asDouble(min) ?? 0;
  final double hi = asDouble(max) ?? double.maxFinite;
  final double st = asDouble(step) ?? 1;
  double target = current + delta;
  if (target < lo) target = lo;
  if (target > hi) target = hi;
  if (st > 0 && hi < double.maxFinite) {
    final double aligned = lo + ((target - lo) / st).round() * st;
    target = aligned < lo ? lo : (aligned > hi ? hi : aligned);
  }
  return target;
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
