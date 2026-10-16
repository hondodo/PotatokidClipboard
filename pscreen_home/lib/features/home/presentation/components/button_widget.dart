import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';

/// 按钮类开关控件卡片（switch 等可开关域）。
///
/// 展示实体名 + 开关状态，点击发送 turn_on / turn_off；
/// 不可用（unavailable/unknown）时置灰且不可点击，
/// 指令执行中显示 loading 防重复点击。
class ButtonWidget extends StatelessWidget {
  const ButtonWidget({
    super.key,
    required this.entity,
    required this.isToggling,
    required this.onToggle,
    this.areaLabel,
    this.icon,
    this.activeColor,
  });

  final HaEntityStateModel entity;
  final bool isToggling;
  final VoidCallback onToggle;

  /// 所属房间展示名（未分配时由页面兜底为「未分配房间」）
  final String? areaLabel;

  /// 自定义图标（子类如 LightWidget 覆盖）
  final IconData? icon;

  /// 开启时的主题色（子类如 LightWidget 覆盖）
  final Color? activeColor;

  static const Map<String, IconData> _domainIcons = <String, IconData>{
    'switch': Icons.toggle_on_rounded,
    'fan': Icons.air_rounded,
    'light': Icons.lightbulb_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool on = entity.isOn;
    final bool available = entity.isAvailable;
    final Color accent = on
        ? (activeColor ?? theme.colorScheme.primary)
        : theme.colorScheme.onSurfaceVariant;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: available
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.surfaceContainerLowest,
      child: InkWell(
        onTap: available && !isToggling ? onToggle : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
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
                child: isToggling
                    ? Padding(
                        padding: const EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accent,
                        ),
                      )
                    : Icon(
                        icon ?? _domainIcons[entity.domain] ?? Icons.devices_rounded,
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
                      entity.displayName,
                      maxLines: 2,
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
                            text: _statusText(),
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
            ],
          ),
        ),
      ),
    );
  }

  String _statusText() {
    if (!entity.isAvailable) return '不可用';
    return entity.isOn ? '已开启' : '已关闭';
  }
}
