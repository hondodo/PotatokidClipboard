import 'package:flutter/widgets.dart';

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
