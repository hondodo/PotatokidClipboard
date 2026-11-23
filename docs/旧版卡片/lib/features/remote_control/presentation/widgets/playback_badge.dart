import 'package:flutter/widgets.dart';
import 'package:pscreen_screen/core/network/realtime_channel.dart';

/// 播放状态徽标：正常绿 / 起播蓝 / 重试橙 / 失败红。
class PlaybackBadge extends StatelessWidget {
  const PlaybackBadge({super.key, required this.label, required this.state});

  final String label;
  final String state;

  Color get _color => switch (state) {
    'play_ok' => const Color(0xFF34C759),
    'play_start' => const Color(0xFF4F8CFF),
    'play_retry' => const Color(0xFFFFB020),
    'play_fail' => const Color(0xFFFF5A5F),
    _ => const Color(0xFF9AA4B2),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _color.withValues(alpha: 0.5)),
      ),
      child: Text(label, style: TextStyle(fontSize: 11, color: _color, height: 1.4)),
    );
  }
}

/// 计算播放徽标文案（两处调用点共用，避免判断再次分叉）。
///
/// 离线或没有播放状态时返回空串（不显示徽标）。电视端（`kind == 'tv'`）
/// 任何页面都可能在播放，非直播场景也展示「上次播放」；中控屏只有直播
/// 场景才真正播放，其余场景维持不显示（未知端按中控屏处理，从严不放宽）。
String playbackLabelOf({
  required bool online,
  required RealtimeDeviceState? device,
}) {
  if (!online) return '';
  final String label = device?.playbackLabel ?? '';
  if (label.isEmpty) return '';
  if (device?.kind == 'tv') return label;
  return device?.sceneKind == 'live' ? label : '';
}
