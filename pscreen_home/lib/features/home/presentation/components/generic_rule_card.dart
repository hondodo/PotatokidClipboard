import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/device_type_dictionary.dart';
import 'package:pscreen_home/features/home/domain/models/ha_device_group.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/presentation/components/card_title.dart';

/// 通用规则卡片：按服务端下发的「设备类型规则 + card 配置」渲染。
///
/// 灰度开关由 [DeviceTypeDictionary.useGenericCard] 控制：只有 admin 在
/// 「设备判定规则」里把该类型的「通用卡片」开关打开，home 才用本卡片替换
/// 原来的专用 widget。这样切一个验一个，13 个专用 Summary 继续兜底。
///
/// 取值规则：
/// - 主数值：mainEntity 指定实体（按 entity_id 模糊匹配）里的 mainAttr 属性，
///   没配就取主实体的 state；再套 mainFmt 的 {v} 模板。
/// - 副文案：subTpl 里的 {state}/{s1}/{s2}/{main} 用组内实体状态填充。
/// - 按钮：actions 走 onAction 回调，由上层派发到 HomeBloc 的对应事件。
class GenericRuleCard extends StatelessWidget {
  const GenericRuleCard({
    super.key,
    required this.group,
    required this.rule,
    required this.card,
    required this.onOpenDetail,
    required this.onAction,
    this.onTogglePrimary,
    this.areaLabel,
    this.showAreaInTitle = false,
    this.isToggling = false,
  });

  final HaDeviceGroup group;
  final DeviceTypeRule rule;
  final DeviceCardConfig card;
  final VoidCallback onOpenDetail;

  /// 按钮动作回调：action 为服务端动作 kind（toggle/press/set_temperature(...) 等）。
  final ValueChanged<String> onAction;

  /// 电源快捷键（主实体可开关时提供）。
  final VoidCallback? onTogglePrimary;
  final String? areaLabel;
  final bool showAreaInTitle;
  final bool isToggling;

  static Color parseColor(String raw, {Color fallback = Colors.teal}) {
    String hex = raw.trim().replaceAll('#', '');
    if (hex.length == 6) {
      final int? value = int.tryParse('FF$hex', radix: 16);
      if (value != null) return Color(value);
    }
    return fallback;
  }

  /// 主数值取值：优先 mainEntity 匹配实体的 mainAttr 属性，退化到主实体 state。
  String _mainValue() {
    final List<HaEntityStateModel> entities = group.entities;
    HaEntityStateModel? target;
    final String want = card.mainEntity.trim();
    if (want.isNotEmpty && want != '主实体' && !want.startsWith('（')) {
      for (final HaEntityStateModel e in entities) {
        if (e.entityId.contains(want) || e.displayName.contains(want)) {
          target = e;
          break;
        }
      }
    }
    target ??= group.primary ?? (entities.isNotEmpty ? entities.first : null);
    if (target == null) return '--';
    final Object? attr = target.attributes[card.mainAttr];
    if (attr != null && '$attr'.isNotEmpty) return '$attr';
    return target.state;
  }

  /// 副文案：替换 {state}/{s1}/{s2}/{main} 占位符。
  String _subText(String mainFormatted) {
    final List<HaEntityStateModel> entities = group.entities;
    final String state = group.primary?.state ?? (entities.isNotEmpty ? entities.first.state : '');
    final String s1 = entities.length > 1 ? entities[1].state : state;
    final String s2 = entities.length > 2 ? entities[2].state : '';
    return card.subTpl
        .replaceAll('{main}', mainFormatted)
        .replaceAll('{state}', state)
        .replaceAll('{s1}', s1)
        .replaceAll('{s2}', s2);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = parseColor(card.color);
    final bool available = !group.isUnavailable;
    final String mainFormatted = card.mainFmt.replaceAll('{v}', _mainValue());
    final String sub = _subText(mainFormatted);

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
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: available ? 0.16 : 0.06),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(card.icon,
                        style: TextStyle(fontSize: 24, color: available ? accent : theme.colorScheme.outline)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          cardTitle(
                            title: group.title,
                            areaLabel: areaLabel,
                            showArea: showAreaInTitle,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: available ? theme.colorScheme.onSurface : theme.colorScheme.outline,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(color: accent),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(card.label,
                            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline)),
                        const SizedBox(height: 1),
                        Text(
                          mainFormatted,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            color: available ? accent : theme.colorScheme.outline,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onTogglePrimary != null)
                    SizedBox(
                      width: 34,
                      height: 34,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(Icons.power_settings_new, size: 26),
                        color: accent,
                        onPressed: available && !isToggling ? onTogglePrimary : null,
                        tooltip: '开关',
                      ),
                    ),
                ],
              ),
              if (card.buttons.isNotEmpty) ...<Widget>[
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: card.buttons.map((DeviceCardButton b) {
                      return SizedBox(
                        height: 28,
                        child: OutlinedButton(
                          onPressed: available ? () => onAction(b.action) : null,
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: accent.withValues(alpha: 0.5)),
                            foregroundColor: accent,
                            padding: const EdgeInsets.symmetric(horizontal: 9),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text(b.label, style: const TextStyle(fontSize: 11)),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
