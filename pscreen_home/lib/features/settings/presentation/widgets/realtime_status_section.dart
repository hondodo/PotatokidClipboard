import 'package:flutter/material.dart';
import 'package:pscreen_home/core/di/injection.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';

/// 遥控实时通道状态：连接状态、网关地址与最近错误。
///
/// 设置页（admin）与家长视图的设置弹层共用这一段，避免维护两份 UI。
/// [channel] 仅供测试注入；正式运行时从 [Injection] 取全局单例。
class RealtimeStatusSection extends StatelessWidget {
  const RealtimeStatusSection({super.key, this.channel});

  final RealtimeChannel? channel;

  @override
  Widget build(BuildContext context) {
    final RealtimeChannel channel = this.channel ?? Injection.get<RealtimeChannel>();
    return StreamBuilder<RealtimeConnectionState>(
      stream: channel.connectionState,
      initialData: channel.state,
      builder: (BuildContext context, AsyncSnapshot<RealtimeConnectionState> snapshot) {
        final RealtimeConnectionState state = snapshot.data ?? RealtimeConnectionState.disconnected;
        final (String label, Color color) = switch (state) {
          RealtimeConnectionState.connected => ('已连接\n${channel.account}', Colors.greenAccent),
          RealtimeConnectionState.connecting => ('连接中…', Colors.orangeAccent),
          RealtimeConnectionState.disconnected => ('未连接', Colors.redAccent),
          RealtimeConnectionState.error => ('连接错误', Colors.redAccent),
        };
        final TextStyle? hint = Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text('遥控通道：$label', style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            if (channel.lastError != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('最近错误：${channel.lastError}', style: hint),
              ),
            // 不用开放给用户看到，只有本地排查时再用
            // Padding(
            //   padding: const EdgeInsets.only(top: 2),
            //   child: Text('网关：${AppConstants.realtimeWsUrl}', style: hint),
            // ),
          ],
        );
      },
    );
  }
}
