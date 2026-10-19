import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/projector_summary.dart';

/// 投影仪快捷卡片：开关机 / 当前应用 / 输入源 / 音量 / 亮度。
class ProjectorWidget extends StatelessWidget {
  const ProjectorWidget({
    super.key,
    required this.summary,
    required this.isBusy,
    required this.onPower,
    this.areaLabel,
    this.onOpenDetail,
  });

  final ProjectorSummary summary;
  final bool isBusy;
  final VoidCallback onPower;
  final String? areaLabel;
  final VoidCallback? onOpenDetail;

  static const Color _accent = Color(0xFF8E9BFF);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool on = summary.isOn;
    final String source = summary.currentAppName ??
        summary.currentAppPackage ??
        summary.input ??
        (on ? '已开启' : '已关闭');

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: onOpenDetail,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 6, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: on ? 0.18 : 0.08),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      Icons.cast_connected_rounded,
                      size: 21,
                      color: on ? _accent : theme.colorScheme.outline,
                    ),
                  ),
                  const SizedBox(width: 10),
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
                        const SizedBox(height: 3),
                        Text(
                          '${areaLabel ?? '未分配房间'} · ${on ? summary.statusLabel : '已关闭'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: on
                                ? _accent
                                : theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: on ? '关机' : '开机',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints.tightFor(
                      width: 32,
                      height: 32,
                    ),
                    onPressed: isBusy ? null : onPower,
                    icon: Icon(
                      Icons.power_settings_new_rounded,
                      size: 19,
                      color: on ? _accent : theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      on ? source : '已关闭',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: on
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.outline,
                      ),
                    ),
                  ),
                  Text(
                    '音量 ${summary.volumeLabel} · 亮度 ${summary.brightnessLabel}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.outline,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
