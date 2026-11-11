import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/projector_summary.dart';
import 'package:pscreen_home/features/home/presentation/components/card_title.dart';
import 'package:pscreen_home/features/home/presentation/components/device_type_icon.dart';
import 'package:pscreen_home/features/home/presentation/components/power_toggle_button.dart';

/// 投影仪快捷卡片：开关机 / 当前应用 / 输入源 / 音量 / 亮度。
class ProjectorWidget extends StatelessWidget {
  const ProjectorWidget({
    super.key,
    required this.summary,
    required this.isBusy,
    required this.onPower,
    this.areaLabel,
    this.showAreaInTitle = false,
    this.onOpenDetail,
  });

  final ProjectorSummary summary;
  final bool isBusy;
  final VoidCallback onPower;
  final String? areaLabel;
  final bool showAreaInTitle;
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
                  DeviceTypeIcon(
                    color: _accent,
                    icon: Icons.cast_connected_rounded,
                    on: on,
                    size: 54,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          cardTitle(
                            title: summary.name,
                            areaLabel: areaLabel,
                            showArea: showAreaInTitle,
                          ),
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
                  PowerToggleButton(
                    on: on,
                    isToggling: isBusy,
                    color: _accent,
                    onPressed: isBusy ? null : onPower,
                    tooltip: on ? '关机' : '开机',
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
