import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/multi_switch_summary.dart';

/// 双开开关卡片：两路按键状态。
class MultiSwitchWidget extends StatelessWidget {
  const MultiSwitchWidget({
    super.key,
    required this.summary,
    this.areaLabel,
    this.onOpenDetail,
  });

  final MultiSwitchSummary summary;
  final String? areaLabel;
  final VoidCallback? onOpenDetail;

  static const Color _accent = Color(0xFF64B5F6);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: onOpenDetail,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.toggle_on_rounded,
                      size: 19,
                      color: _accent,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          summary.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          areaLabel ?? '未分配房间',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: summary.gangs
                    .map((SwitchGang gang) => Expanded(
                          child: Row(
                            children: <Widget>[
                              Icon(
                                Icons.circle,
                                size: 7,
                                color: gang.isOn
                                    ? _accent
                                    : theme.colorScheme.outline,
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  '${gang.label} ${gang.isOn ? '开' : '关'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: gang.isOn
                                        ? _accent
                                        : theme.colorScheme.outline,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(growable: false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
