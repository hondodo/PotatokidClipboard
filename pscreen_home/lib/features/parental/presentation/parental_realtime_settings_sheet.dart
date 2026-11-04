import 'package:flutter/material.dart';
import 'package:pscreen_home/features/settings/presentation/widgets/realtime_status_section.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';

/// 家长视图右上角「设置」的只读弹层。
///
/// 家长身份只开放「遥控（实时通道）」这一段：连接状态、网关地址与最近
/// 错误；屏保、壁纸、界面缩放等设置项一律不出现，也不提供任何可编辑入口。
/// [channel] 仅供测试注入，正式运行时由 [RealtimeStatusSection] 从全局
/// 依赖中读取。
class ParentalRealtimeSettingsSheet extends StatelessWidget {
  const ParentalRealtimeSettingsSheet({super.key, this.channel});

  final RealtimeChannel? channel;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('设置', style: theme.textTheme.titleLarge),
            const SizedBox(height: 16),
            Text(
              '遥控（实时通道）',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '家长视图仅展示遥控通道的连接状态与网关地址，其它设置项不对家长开放。',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
            ),
            const SizedBox(height: 12),
            RealtimeStatusSection(channel: channel),
          ],
        ),
      ),
    );
  }
}
