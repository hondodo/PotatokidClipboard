import 'package:flutter/material.dart';
import 'package:pscreen_screen/features/iptv/application/recording/recording_controller.dart';

/// 播放器上的「录制中 ● mm:ss」角标。
///
/// 纯展示：IgnorePointer 不拦指针、自身无可聚焦节点，不影响遥控焦点链与
/// 触屏手势（与 `_TouchHintBanner` 同一约定）。状态来自共享包单例 controller，
/// 两端各自实现 UI，这里只服务 TV 端。
class RecordingIndicator extends StatelessWidget {
  const RecordingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<RecordingState>(
      valueListenable: RecordingController.instance.state,
      builder: (context, state, _) {
        if (!state.isRecording) return const SizedBox.shrink();
        final int totalSeconds = state.elapsed.inSeconds;
        final String mmss =
            '${(totalSeconds ~/ 60).toString().padLeft(2, '0')}:'
            '${(totalSeconds % 60).toString().padLeft(2, '0')}';
        return IgnorePointer(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xCC1A1A1A),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0x66FF5252)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.fiber_manual_record, color: Color(0xFFFF5252), size: 14),
                const SizedBox(width: 7),
                Text(
                  '录制中 $mmss',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
