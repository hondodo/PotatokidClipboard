import 'package:flutter/material.dart';

import 'package:pscreen_home/features/home/application/history_service.dart';
import 'package:pscreen_home/features/home/domain/models/card_layout.dart';
import 'package:pscreen_home/features/home/domain/models/device_type_dictionary.dart';
import 'package:pscreen_home/features/home/domain/models/ha_device_group.dart';
import 'package:pscreen_home/features/home/domain/models/metric.dart';
import 'package:pscreen_home/features/home/domain/models/metric_sample.dart';
import 'package:pscreen_home/features/home/presentation/components/card_title.dart';
import 'package:pscreen_home/features/home/presentation/components/metric_sparkline.dart';

/// 通用 JSON 卡片渲染器：递归解释服务端下发的布局树，生成原生 Flutter Widget。
///
/// - 只解析数据、不执行脚本；onClick 交给上层 onAction 走白名单派发。
/// - 服务端不可达 / 未配 layout 时，[CardLayoutBuilder.defaultLayout] 按类型生成默认布局。
/// - sparkline 节点接现有 HistoryService.watch()，原生性能、无 WebView。
class JsonCardRenderer extends StatelessWidget {
  const JsonCardRenderer({
    super.key,
    required this.group,
    required this.card,
    required this.typeKey,
    required this.onOpenDetail,
    required this.onAction,
    this.areaLabel,
    this.showAreaInTitle = false,
    this.isToggling = false,
    this.historyService,
  });

  final HaDeviceGroup group;
  final DeviceCardConfig card;
  final String typeKey;
  final VoidCallback onOpenDetail;
  final ValueChanged<String> onAction;
  final String? areaLabel;
  final bool showAreaInTitle;
  final bool isToggling;
  final HistoryService? historyService;

  @override
  Widget build(BuildContext context) {
    final CardLayoutNode layout = card.layout ?? CardLayoutBuilder.defaultLayout(typeKey, card);
    final CardEvalContext ctx = CardEvalContext(group: group, card: card);
    final ThemeData theme = Theme.of(context);
    final bool available = !group.isUnavailable;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: available
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.surfaceContainerLowest,
      child: InkWell(
        onTap: available ? onOpenDetail : null,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            layout.padding?[0] ?? 12,
            layout.padding?[1] ?? 10,
            layout.padding?[0] ?? 12,
            layout.padding?[1] ?? 10,
          ),
          child: _buildNode(context, layout, ctx, available),
        ),
      ),
    );
  }

  Widget _buildNode(
    BuildContext context,
    CardLayoutNode node,
    CardEvalContext ctx,
    bool available, {
    Map<String, String>? itemValues,
    String? itemName,
  }) {
    final ThemeData theme = Theme.of(context);
    final CardEvalContext eval = (itemValues != null && itemName != null)
        ? CardEvalContext(group: group, card: card, itemName: itemName, itemValues: itemValues)
        : ctx;

    // 条件显隐：不满足时不生成节点。
    if (node.visibleWhen != null && node.visibleWhen!.isNotEmpty) {
      if (!eval.evalCondition(node.visibleWhen!)) return const SizedBox.shrink();
    }

    final double gap = node.gap ?? 8;
    switch (node.type) {
      case 'row':
        return Flex(
          direction: Axis.horizontal,
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: _mainAlign(node.mainAlign),
          crossAxisAlignment: _crossAlign(node.crossAlign),
          children: _spaced(context, node.children, gap, eval, available),
        );
      case 'column':
        // 垂直列默认 stretch：让子 row 获得有界宽度，否则 row 内的 Expanded
        // 会因无界宽约束崩溃（RenderFlex non-zero flex unbounded width）。
        return Flex(
          direction: Axis.vertical,
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: _mainAlign(node.mainAlign),
          crossAxisAlignment: node.crossAlign == null
              ? CrossAxisAlignment.stretch
              : _crossAlign(node.crossAlign),
          children: _spaced(context, node.children, gap, eval, available, Axis.vertical),
        );
      case 'wrap':
        return Wrap(
          spacing: gap,
          runSpacing: gap > 0 ? gap / 2 : 0,
          children: node.children
              .map((CardLayoutNode c) => _buildNode(context, c, eval, available))
              .toList(growable: false),
        );
      case 'text':
        return _buildText(context, node, eval, available);
      case 'icon':
        return _buildIcon(context, node, eval, available);
      case 'button':
        return _buildButton(context, node, eval, available);
      case 'chip':
        return _buildButton(context, node, eval, available, chip: true);
      case 'progress':
        return _buildProgress(context, node, eval, available);
      case 'sparkline':
        return _buildSparkline(context, node, eval, available);
      case 'divider':
        return Divider(
          height: gap,
          thickness: node.thickness ?? 1,
          color: _color(node.color, theme, eval) ?? theme.dividerColor,
        );
      case 'repeat':
        return _buildRepeat(context, node, eval, available);
      default:
        return const SizedBox.shrink();
    }
  }

  List<Widget> _spaced(
    BuildContext context,
    List<CardLayoutNode> children,
    double gap,
    CardEvalContext eval,
    bool available, [
    Axis axis = Axis.horizontal,
  ]) {
    final List<Widget> out = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      if (i > 0) {
        out.add(axis == Axis.vertical ? SizedBox(height: gap) : SizedBox(width: gap));
      }
      Widget child = _buildNode(context, children[i], eval, available);
      if (children[i].expand) {
        child = Expanded(child: child);
      } else if (axis == Axis.horizontal && children[i].type == 'column') {
        // Row 默认给非 flex 子节点无界宽度，column 的 stretch 会把它传给
        // 内部 Text，导致 "BoxConstraints forces an infinite width"。
        // 后台下发的布局不一定会给 column 写 expand，这里按渲染需要兜底：
        // 用 loose Flexible 提供有界宽度，同时允许 column 按内容收缩。
        child = Flexible(fit: FlexFit.loose, child: child);
      }
      out.add(child);
    }
    return out;
  }

  Widget _buildText(BuildContext context, CardLayoutNode node, CardEvalContext eval, bool available) {
    final ThemeData theme = Theme.of(context);
    final String raw = node.value ?? '';
    final String text = eval.resolve(raw);
    // title 占位符交给 cardTitle 拼房间名；其余直接显示。
    final String shown = raw.trim() == '{title}'
        ? cardTitle(title: text, areaLabel: areaLabel, showArea: showAreaInTitle)
        : text;
    final Color? color = _color(node.color, theme, eval) ??
        (available ? null : theme.colorScheme.outline);
    final TextAlign align = node.align == 'center'
        ? TextAlign.center
        : (node.align == 'right' ? TextAlign.right : TextAlign.left);
    return Text(
      shown,
      maxLines: node.maxLines ?? 1,
      overflow: TextOverflow.ellipsis,
      textAlign: align,
      style: theme.textTheme.bodyMedium?.copyWith(
        fontSize: node.size ?? 14,
        fontWeight: _fontWeight(node.weight),
        color: color,
      ),
    );
  }

  FontWeight? _fontWeight(int? w) {
    if (w == null) return null;
    if (w >= 800) return FontWeight.w800;
    if (w >= 700) return FontWeight.w700;
    if (w >= 600) return FontWeight.w600;
    if (w >= 500) return FontWeight.w500;
    if (w >= 400) return FontWeight.w400;
    if (w >= 300) return FontWeight.w300;
    return FontWeight.w400;
  }

  Widget _buildIcon(BuildContext context, CardLayoutNode node, CardEvalContext eval, bool available) {
    final ThemeData theme = Theme.of(context);
    final IconData iconData = _iconData(eval.resolve(node.value ?? ''));
    final Color accent = _color(node.color, theme, eval) ?? _accent(theme);
    final Widget icon = Icon(iconData, size: node.size ?? 24, color: available ? accent : theme.colorScheme.outline);
    final CardIconBox? box = node.box;
    if (box == null) return icon;
    return Container(
      width: box.size ?? 46,
      height: box.size ?? 46,
      decoration: BoxDecoration(
        color: _color(box.bg, theme, eval) ?? accent.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(box.radius ?? 12),
      ),
      alignment: Alignment.center,
      child: icon,
    );
  }

  Widget _buildButton(
    BuildContext context,
    CardLayoutNode node,
    CardEvalContext eval,
    bool available, {
    bool chip = false,
  }) {
    final ThemeData theme = Theme.of(context);
    final String label = eval.resolve(node.label ?? '');
    final String? sub = node.subLabel == null ? null : eval.resolve(node.subLabel!);
    final String onClick = eval.resolve(node.onClick ?? '');
    final Color accent = _color(node.color, theme, eval) ?? _accent(theme);
    final String resolvedStyle = node.style == null ? '' : eval.resolve(node.style!);
    final bool active = resolvedStyle == 'active';

    final Widget child = sub == null
        ? Text(label, style: TextStyle(fontSize: chip ? 12 : 14))
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(sub, style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          );

    VoidCallback? onPressed;
    if (available && onClick.isNotEmpty) {
      onPressed = () {
        final String? confirm = node.confirm;
        if (confirm != null && confirm.isNotEmpty) {
          // 二次确认交给上层（这里用简单 dialog，onAction 仍在确认后触发）。
          showDialog<bool>(
            context: context,
            builder: (BuildContext ctx) => AlertDialog(
              title: Text(eval.resolve(confirm)),
              actions: <Widget>[
                TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('取消')),
                TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('确定')),
              ],
            ),
          ).then((bool? ok) {
            if (ok == true) onAction(onClick);
          });
        } else {
          onAction(onClick);
        }
      };
    }

    if (chip) {
      return SizedBox(
        height: 30,
        child: OutlinedButton(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: accent.withValues(alpha: 0.5)),
            foregroundColor: accent,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: child,
        ),
      );
    }

    // 大按钮（active 时填充高亮，normal 时描边）——每路一个大按钮用它。
    final bool filled = active || resolvedStyle == 'filled' || resolvedStyle == 'tonal';
    return SizedBox(
      height: 52,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: filled
              ? accent.withValues(alpha: active ? 0.28 : 0.9)
              : Colors.transparent,
          foregroundColor: filled ? (active ? accent : Colors.white) : accent,
          side: filled ? null : BorderSide(color: accent.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ).copyWith(
          shadowColor: WidgetStateProperty.all(Colors.transparent),
        ),
        // 有 label 的大按钮（每路开关）显示圆点+文字；纯图标电源键只显示图标。
        // 不用 Expanded——按钮可能在无界宽上下文里，Expanded 会崩溃。
        child: label.isEmpty
            ? child
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: 12,
                    height: 12,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active ? accent : Colors.transparent,
                      border: Border.all(color: accent, width: 2),
                    ),
                  ),
                  Flexible(child: child),
                ],
              ),
      ),
    );
  }

  Widget _buildProgress(BuildContext context, CardLayoutNode node, CardEvalContext eval, bool available) {
    final ThemeData theme = Theme.of(context);
    final double value = num.tryParse(eval.resolve(node.value ?? '0'))?.toDouble() ?? 0;
    final double max = num.tryParse(eval.resolve(node.max ?? '100'))?.toDouble() ?? 100;
    final double progress = max > 0 ? (value / max).clamp(0.0, 1.0) : 0;
    final Color accent = _color(node.color, theme, eval) ?? _accent(theme);
    return SizedBox(
      height: node.height ?? 6,
      child: ClipRRect(
        borderRadius: BorderRadius.circular((node.height ?? 6) / 2),
        child: LinearProgressIndicator(
          value: progress,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          color: accent,
          minHeight: node.height ?? 6,
        ),
      ),
    );
  }

  Widget _buildSparkline(BuildContext context, CardLayoutNode node, CardEvalContext eval, bool available) {
    final ThemeData theme = Theme.of(context);
    final String metricRaw = eval.resolve(node.metric ?? 'power').toLowerCase();
    final Metric metric = metricRaw == 'temperature'
        ? Metric.temperature
        : (metricRaw == 'humidity' ? Metric.humidity : Metric.power);
    final Color accent = _color(node.color, theme, eval) ?? _accent(theme);
    final HistoryService? svc = historyService ?? _tryHistoryService();
    if (svc == null) {
      return SizedBox(height: node.height ?? 60, child: Center(child: Icon(Icons.show_chart, color: accent)));
    }
    return ValueListenableBuilder<List<MetricSample>>(
      valueListenable: svc.watch(group.orderKey, metric),
      builder: (BuildContext context, List<MetricSample> samples, Widget? _) {
        return MetricSparkline(
          samples: samples,
          window: _window(node.window),
          height: node.height ?? 60,
          accent: accent,
          showLabels: node.showLabels,
          unit: metric.unit,
        );
      },
    );
  }

  HistoryService? _tryHistoryService() {
    // 通过祖先 InheritedWidget 或全局单例获取；这里用可选的全局引用。
    return JsonCardRenderer.historyServiceProvider?.call();
  }

  /// 全局历史服务提供者（由 home 页面在初始化时注入），避免改造所有构造签名。
  static HistoryService Function()? historyServiceProvider;

  Duration _window(String? raw) {
    switch (raw) {
      case '10min':
        return const Duration(minutes: 10);
      case '1h':
        return const Duration(hours: 1);
      case '6h':
        return const Duration(hours: 6);
      case '24h':
        return const Duration(hours: 24);
      case '30min':
      default:
        return const Duration(minutes: 30);
    }
  }

  Widget _buildRepeat(BuildContext context, CardLayoutNode node, CardEvalContext eval, bool available) {
    final CardLayoutNode? tpl = node.template;
    if (tpl == null) return const SizedBox.shrink();
    final List<Map<String, String>> values = gangValues(group);
    final int columns = node.columns ?? 2;
    final double gap = node.gap ?? 8;
    final List<Widget> cells = values.map((Map<String, String> itemValues) {
      return _buildNode(
        context,
        tpl,
        eval,
        available,
        itemValues: itemValues,
        itemName: node.item,
      );
    }).toList(growable: false);
    if (cells.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: gap,
      runSpacing: gap,
      children: cells.map((Widget c) {
        final double cellWidth = columns > 0 ? (620.0 - gap * (columns - 1)) / columns : 200;
        return SizedBox(width: cellWidth.clamp(90.0, 320.0), child: c);
      }).toList(growable: false),
    );
  }

  // ---- helpers ----

  Color _accent(ThemeData theme) => GenericCardColors.parse(card.color);

  Color? _color(String? raw, ThemeData theme, CardEvalContext eval) {
    if (raw == null || raw.isEmpty) return null;
    final String resolved = eval.resolve(raw);
    // 语义色名
    switch (resolved) {
      case 'outline':
        return theme.colorScheme.outline;
      case 'primary':
        return theme.colorScheme.primary;
      case 'error':
        return theme.colorScheme.error;
      case 'surface':
        return theme.colorScheme.surface;
    }
    // {color}26 形式的 alpha 后缀（16 进制两位）
    final RegExp alphaExp = RegExp(r'^#?([0-9a-fA-F]{6})([0-9a-fA-F]{2})$');
    final Match? m = alphaExp.firstMatch(resolved);
    if (m != null) {
      final int? rgb = int.tryParse('FF${m.group(1)}', radix: 16);
      final int? a = int.tryParse(m.group(2)!, radix: 16);
      if (rgb != null && a != null) return Color(rgb).withValues(alpha: a / 255);
    }
    final Color c = GenericCardColors.parse(resolved, fallback: theme.colorScheme.primary);
    return c;
  }

  IconData _iconData(String raw) {
    if (raw.isEmpty) return Icons.circle;
    // 先试 Material 图标名
    final IconData? m = _materialIcons[raw.toLowerCase()];
    if (m != null) return m;
    // 单个 emoji / 字符（如 ♨ ☀ ▦）—— 用 Text 更合适，这里包成 Icon 占位。
    if (raw.length <= 2 && raw.runes.isNotEmpty) {
      return Icons.circle; // 单字符图标由 _buildIcon 分支用 Text 渲染更好，见下。
    }
    return Icons.devices_other;
  }

  MainAxisAlignment _mainAlign(String? raw) {
    switch (raw) {
      case 'center':
        return MainAxisAlignment.center;
      case 'end':
        return MainAxisAlignment.end;
      default:
        return MainAxisAlignment.start;
    }
  }

  CrossAxisAlignment _crossAlign(String? raw) {
    switch (raw) {
      case 'center':
        return CrossAxisAlignment.center;
      case 'end':
        return CrossAxisAlignment.end;
      default:
        return CrossAxisAlignment.start;
    }
  }

  static const Map<String, IconData> _materialIcons = <String, IconData>{
    'power_settings_new': Icons.power_settings_new,
    'power': Icons.power_settings_new,
    'lightbulb': Icons.lightbulb_outline_rounded,
    'thermostat': Icons.thermostat,
    'ac_unit': Icons.ac_unit,
    'device_thermostat': Icons.device_thermostat,
    'water_drop': Icons.water_drop,
    'wind': Icons.wind_power,
    'tv': Icons.tv,
    'local_fire_department': Icons.local_fire_department,
    'microwave': Icons.microwave,
    'washing_machine': Icons.local_laundry_service,
    'electric_bolt': Icons.electric_bolt,
    'lock': Icons.lock,
    'lock_open': Icons.lock_open,
    'grid_view': Icons.grid_view_rounded,
    'show_chart': Icons.show_chart,
    'brightness': Icons.brightness_6,
    'volume_up': Icons.volume_up,
    'cloud': Icons.cloud,
  };
}

/// 与 GenericRuleCard.parseColor 一致的取色（避免循环依赖，独立实现）。
class GenericCardColors {
  static Color parse(String raw, {Color fallback = Colors.teal}) {
    String hex = raw.trim().replaceAll('#', '');
    if (hex.length == 6) {
      final int? value = int.tryParse('FF$hex', radix: 16);
      if (value != null) return Color(value);
    }
    return fallback;
  }
}

/// 服务端不可达 / 未配 layout 时的默认布局生成器（与 deviceTypes.js defaultLayoutFor 对齐）。
class CardLayoutBuilder {
  static CardLayoutNode defaultLayout(String typeKey, DeviceCardConfig card) {
    final CardLayoutNode header = CardLayoutNode(
      type: 'row',
      gap: 10,
      crossAlign: 'center',
      children: <CardLayoutNode>[
        CardLayoutNode(
          type: 'icon',
          value: card.icon,
          size: 24,
          box: CardIconBox(size: 46, radius: 12, bg: '{color}26', color: '{color}'),
        ),
        CardLayoutNode(
          type: 'column',
          expand: true,
          gap: 2,
          children: <CardLayoutNode>[
            const CardLayoutNode(type: 'text', value: '{title}', size: 14, weight: 600, maxLines: 1),
            const CardLayoutNode(type: 'text', value: '{sub}', size: 12, color: '{color}', maxLines: 1),
          ],
        ),
      ],
    );

    if (typeKey == 'multi_switch') {
      return CardLayoutNode(
        type: 'column',
        gap: 8,
        padding: <double>[12, 10],
        children: <CardLayoutNode>[
          header,
          CardLayoutNode(
            type: 'repeat',
            source: 'gangs',
            item: 'gang',
            columns: 2,
            gap: 8,
            template: const CardLayoutNode(
              type: 'button',
              label: '{gang.label}',
              subLabel: '{gang.stateLabel}',
              style: '{gang.style}',
              onClick: 'toggle@{gang.entityId}',
            ),
          ),
        ],
      );
    }

    final List<CardLayoutNode> mainChildren = <CardLayoutNode>[
      CardLayoutNode(
        type: 'column',
        expand: true,
        gap: 1,
        children: <CardLayoutNode>[
          const CardLayoutNode(type: 'text', value: '{label}', size: 11, color: 'outline', maxLines: 1),
          const CardLayoutNode(type: 'text', value: '{main}', size: 24, weight: 700, color: '{color}', maxLines: 1),
        ],
      ),
      const CardLayoutNode(
        type: 'button',
        icon: 'power_settings_new',
        style: 'filled',
        onClick: 'toggle',
        visibleWhen: '{primary.switchable}',
      ),
    ];
    final List<CardLayoutNode> children = <CardLayoutNode>[
      header,
      CardLayoutNode(type: 'row', crossAlign: 'end', gap: 8, children: mainChildren),
    ];
    if (card.buttons.isNotEmpty) {
      children.add(CardLayoutNode(
        type: 'wrap',
        gap: 6,
        children: card.buttons.take(4).map((DeviceCardButton b) {
          return CardLayoutNode(type: 'chip', label: b.label, onClick: b.action, style: 'outlined');
        }).toList(growable: false),
      ));
    }
    return CardLayoutNode(type: 'column', gap: 8, padding: <double>[12, 10], children: children);
  }
}
