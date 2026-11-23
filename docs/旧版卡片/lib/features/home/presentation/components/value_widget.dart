import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/ha_entity_state_model.dart';
import 'package:pscreen_home/features/home/presentation/components/card_title.dart';
import 'package:pscreen_home/features/home/presentation/components/ha_domain_icons.dart';

/// 数据 / 动作 / 不可用实体卡片：展示值 label，**不做交互**。
///
/// 首页不按 domain 过滤，非开关类实体也上卡：
/// - 数据类（sensor / binary_sensor / number…）：副标题显示值 label
///   （如 `24.5 °C`、`开`、`55%`）；
/// - 动作类（button / event / notify…）与暂未支持的控制域
///   （climate / media_player…）：副标题提示「暂不支持操作」；
/// - 不可用（unavailable / unknown）：整体置灰显示「不可用」。
class ValueWidget extends StatelessWidget {
  const ValueWidget({
    super.key,
    required this.entity,
    this.areaLabel,
    this.showAreaInTitle = false,
    this.blockedReason,
    this.onBlockedTap,
  });

  final HaEntityStateModel entity;

  /// 所属房间展示名（未分配时由页面兜底为「未分配房间」）
  final String? areaLabel;

  /// 显示全部房间时，标题前置房间名。
  final bool showAreaInTitle;

  /// 非空表示安全锁定：整体置灰，点击只提示 [blockedReason]。
  final String? blockedReason;

  /// 安全锁定时的点击回调（通常用于弹出提示）。
  final VoidCallback? onBlockedTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool blocked = blockedReason != null;
    final bool available = entity.isAvailable && !blocked;
    final Color accent = available
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.outline;
    final String status = blocked
        ? blockedReason!
        : !entity.isAvailable
            ? '不可用'
            : entity.isAction
                ? '暂不支持操作'
                : entity.valueLabel;

    final Widget content = Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(HaDomainIcons.of(entity.domain), color: accent, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  cardTitle(
                    title: entity.displayName,
                    areaLabel: areaLabel,
                    showArea: showAreaInTitle,
                  ),
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
                        text: status,
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
    );

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: available
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.surfaceContainerLowest,
      // 普通数据实体不可交互；安全锁定时仍可点击以提示原因。
      child: blocked
          ? InkWell(onTap: onBlockedTap, child: content)
          : content,
    );
  }
}
