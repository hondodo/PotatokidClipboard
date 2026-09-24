import 'package:flutter/material.dart';
import 'package:potatokid_screen/features/iptv/domain/models/iptv_channel.dart';

/// 右侧垂直频道条：半透明，上下（键盘由壳层驱动）或点按切换频道。
///
/// 这里只负责展示与点按；「上/下」切换由壳层 MainApp 经由
/// `LiveChannelController` 驱动，避免焦点把方向键截走。
class ChannelBar extends StatelessWidget {
  const ChannelBar({
    super.key,
    required this.channels,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<IptvChannel> channels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: channels.length,
        itemBuilder: (context, index) {
          return _ChannelTile(
            channel: channels[index],
            selected: index == selectedIndex,
            onTap: () => onChanged(index),
            earnFocus: index == selectedIndex && (index - selectedIndex).abs() <= 1,
          );
        },
      ),
    );
  }
}

class _ChannelTile extends StatelessWidget {
  const _ChannelTile({
    required this.channel,
    required this.selected,
    required this.onTap,
    required this.earnFocus,
  });

  final IptvChannel channel;
  final bool selected;
  final VoidCallback onTap;

  /// 让选中项附近可聚焦，便于遥控器方向键垂直滚动；选中项默认聚焦。
  final bool earnFocus;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Focus(
      canRequestFocus: earnFocus,
      autofocus: selected,
      child: ListTile(
        dense: true,
        selected: selected,
        selectedTileColor: scheme.primary.withValues(alpha: 0.85),
        title: Text(
          channel.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        onTap: onTap,
      ),
    );
  }
}