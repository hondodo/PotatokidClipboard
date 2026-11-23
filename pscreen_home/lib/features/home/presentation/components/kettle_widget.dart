import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/kettle_summary.dart';
import 'package:pscreen_home/features/home/presentation/components/card_title.dart';

/// 电热水瓶快捷卡片：当前水温 + 状态 + 模式 + 目标温度。
///
/// 右上角文字按钮：未运行时「加热」，运行中按阶段显示「停止加热 / 停止保温」；
/// 点卡片其余区域进入详情。
class KettleWidget extends StatelessWidget {
  const KettleWidget({
    super.key,
    required this.summary,
    this.areaLabel,
    this.showAreaInTitle = false,
    this.onStart,
    this.onStop,
    this.onOpenDetail,
  });

  final KettleSummary summary;
  final String? areaLabel;
  final bool showAreaInTitle;
  final VoidCallback? onStart;
  final VoidCallback? onStop;
  final VoidCallback? onOpenDetail;

  static const Color _accent = Color(0xFF4DD0C4);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool active = summary.isActive;
    final bool offline = summary.isOffline;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surfaceContainerHighest,
      child: InkWell(
        onTap: onOpenDetail,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          // 保留 Spacer 做上下分布；底部文字/按钮按触屏尺寸放大。
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: _accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.water_drop_rounded,
                      size: 24,
                      color: _accent,
                    ),
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
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          offline
                              ? summary.offlineLabel()
                              : '${areaLabel ?? '未分配房间'} · '
                                  '${summary.status} · ${summary.mode}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 12,
                            color: active
                                ? _accent
                                : theme.colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              // 保留 Spacer：中间留白，底部读数贴近卡片下沿（与旧版一致）。
              const Spacer(),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        '当前温度',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 13,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text.rich(
                        TextSpan(
                          children: <InlineSpan>[
                            TextSpan(
                              text: summary.temperatureLabel,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontSize: 38,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (!offline)
                              TextSpan(
                                text: '°C',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontSize: 15,
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        offline
                            ? '目标 --'
                            : '目标 ${_format(summary.effectiveTargetTemperature)}°C',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontSize: 14,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 4),
                      // 触屏点击区放大：高度 42 + 宽 padding，字号 15，
                      // 不用 shrinkWrap，保证手指容易点中。
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: 42,
                          minWidth: 92,
                        ),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _accent,
                            side: BorderSide(color: _accent, width: 1.5),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          onPressed:
                              offline ? null : (active ? onStop : onStart),
                          child: Text(
                            offline ? '离线' : summary.cardActionLabel,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _format(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}
