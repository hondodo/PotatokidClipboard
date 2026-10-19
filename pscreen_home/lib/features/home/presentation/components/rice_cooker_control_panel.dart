import 'package:flutter/material.dart';
import 'package:pscreen_home/features/home/domain/models/rice_cooker_summary.dart';

/// 电饭煲详情：状态、剩余时长、开始/停止、保温信息。
class RiceCookerControlPanel extends StatelessWidget {
  const RiceCookerControlPanel({
    super.key,
    required this.summary,
    required this.onStart,
    required this.onStop,
  });

  final RiceCookerSummary summary;
  final VoidCallback? onStart;
  final VoidCallback? onStop;

  static const Color _accent = Color(0xFF4DD0C4);

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool active = summary.isActive;
    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.rice_bowl_rounded,
                    color: _accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        summary.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        summary.statusLabel,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: summary.hasFault
                              ? theme.colorScheme.error
                              : (active
                                  ? _accent
                                  : theme.colorScheme.outline),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (active)
              Center(
                child: Column(
                  children: <Widget>[
                    Text(
                      summary.status,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      summary.remainingMinutes == null
                          ? '—'
                          : '${summary.remainingMinutes} 分钟',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: _accent,
                        height: 1,
                      ),
                    ),
                    Text(
                      '剩余时间',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                '待机中',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.outline,
                ),
              ),
            const SizedBox(height: 20),
            Row(
              children: <Widget>[
                Expanded(
                  child: FilledButton.icon(
                    onPressed: active ? onStop : onStart,
                    icon: Icon(
                      active
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded,
                      size: 18,
                    ),
                    label: Text(active ? '停止烹饪' : '开始烹饪'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Wrap(
              spacing: 18,
              runSpacing: 8,
              children: <Widget>[
                _Info(
                  label: '食谱',
                  value: 'Menu ${summary.menuId}',
                ),
                _Info(
                  label: '总时长',
                  value: summary.totalMinutes == null
                      ? '—'
                      : '${summary.totalMinutes} 分钟',
                ),
                _Info(
                  label: '保温',
                  value: summary.autoKeepWarm ? '自动' : '关闭',
                ),
                _Info(
                  label: '已保温',
                  value: summary.keepWarmMinutes == null
                      ? '—'
                      : '${summary.keepWarmMinutes} 分钟',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Text(
      '$label $value',
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.outline,
      ),
    );
  }
}
