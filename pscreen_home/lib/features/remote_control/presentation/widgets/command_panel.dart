import 'package:flutter/material.dart';
import 'package:pscreen_screen/features/msg/protocol/envelope_builder.dart';

/// 命令快捷面板：音量±/静音/频道。
class CommandPanel extends StatelessWidget {
  const CommandPanel({
    super.key,
    required this.onCommand,
  });

  /// 回调：已构造好的信封字符串。
  final ValueChanged<String> onCommand;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: <Widget>[
        _CmdButton(label: '音量+', onTap: () => onCommand(buildCommandEnvelope('volume_up'))),
        _CmdButton(label: '音量-', onTap: () => onCommand(buildCommandEnvelope('volume_down'))),
        _CmdButton(label: '静音', onTap: () => onCommand(buildCommandEnvelope('mute'))),
        _CmdButton(
          label: '频道 CCTV-1',
          onTap: () => onCommand(buildChannelCommand(name: 'CCTV-1')),
        ),
        _CmdButton(
          label: '频道 CCTV-5',
          onTap: () => onCommand(buildChannelCommand(name: 'CCTV-5')),
        ),
      ],
    );
  }
}

class _CmdButton extends StatelessWidget {
  const _CmdButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(onPressed: onTap, child: Text(label));
  }
}
