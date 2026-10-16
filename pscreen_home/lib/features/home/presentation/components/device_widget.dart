import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/ha_device_group.dart';

/// 设备合并卡片：同一物理设备的多个可控实体聚合为一张卡。
///
/// 外层只展示必要详情（设备名 + 聚合状态 + 房间）与必要快捷操作
/// （右侧电源键，只切换主实体）；点击卡片其余区域进入设备详情页，
/// 在那里逐实体控制。
///
/// 仅用于多实体设备（[HaDeviceGroup.isMerged]）；
/// 单实体设备继续用 [LightWidget] / [ButtonWidget]，点击即开关。
class DeviceWidget extends StatelessWidget {
  const DeviceWidget({
    super.key,
    required this.group,
    required this.isToggling,
    required this.onTogglePrimary,
    required this.onOpenDetail,
    this.areaLabel,
  });

  final HaDeviceGroup group;

  /// 主实体指令执行中
  final bool isToggling;

  /// 快捷电源键：切换主实体开关
  final VoidCallback onTogglePrimary;

  /// 点击卡片：进入设备详情页
  final VoidCallback onOpenDetail;

  /// 所属房间展示名
  final String? areaLabel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool on = group.primary.isOn;
    final bool available = group.primary.isAvailable;
    final Color accent = on
        ? (group.primary.domain == 'light'
            ? Colors.amber
            : theme.colorScheme.primary)
        : theme.colorScheme.onSurfaceVariant;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: available
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.surfaceContainerLowest,
      child: InkWell(
        onTap: onOpenDetail,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
          child: Row(
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: on ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  group.primary.domain == 'light'
                      ? Icons.lightbulb_rounded
                      : Icons.devices_rounded,
                  color: accent,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      group.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: available
                            ? theme.colorScheme.onSurface
                            : theme.colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        style: theme.textTheme.bodySmall,
                        children: <InlineSpan>[
                          TextSpan(
                            text: group.statusLabel,
                            style: TextStyle(color: accent),
                          ),
                          TextSpan(
                            text: ' · ${areaLabel ?? '未分配房间'}',
                            style:
                                TextStyle(color: theme.colorScheme.outline),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              // 快捷电源键：只切主实体；卡片其余区域进详情页
              IconButton(
                tooltip: '开关主控',
                visualDensity: VisualDensity.compact,
                onPressed: available && !isToggling ? onTogglePrimary : null,
                icon: isToggling
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accent,
                        ),
                      )
                    : Icon(Icons.power_settings_new_rounded, color: accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
