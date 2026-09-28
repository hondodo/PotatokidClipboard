import 'package:flutter/material.dart';
import 'package:potatokid_screen/features/iptv/domain/models/iptv_channel.dart';

/// 右侧垂直频道条：由 [LiveChannelController.index] 驱动，永远与当前播放频道同步。
///
/// - 当前频道高亮显示，并用 [ScrollController] 滚动到可视区（「跟随」），
///   收起后又呼出时也自动定位到当前频道，避免像两个无关控件。
/// - 「上/下」切台由壳层驱动 controller，「点按」直接选中。
class ChannelBar extends StatefulWidget {
  const ChannelBar({
    super.key,
    required this.channels,
    required this.selectedIndex,
    required this.onChanged,
    required this.visible,
  });

  final List<IptvChannel> channels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  /// 列表是否可见（用于呼出时定位到当前频道）
  final bool visible;

  @override
  State<ChannelBar> createState() => _ChannelBarState();
}

class _ChannelBarState extends State<ChannelBar> {
  static const double _itemExtent = 42;
  final ScrollController _scrollController = ScrollController();

  @override
  void didUpdateWidget(covariant ChannelBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 频道切换时跟随高亮；从收起变成显示时定位到当前频道。
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      _scrollToSelected(animate: true);
    } else if (!oldWidget.visible && widget.visible) {
      _scrollToSelected(animate: false);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToSelected({required bool animate}) {
    if (!_scrollController.hasClients) return;
    final double target =
        (widget.selectedIndex * _itemExtent).clamp(
          0,
          _scrollController.position.maxScrollExtent,
        );
    if (animate) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

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
        controller: _scrollController,
        itemExtent: _itemExtent,
        itemCount: widget.channels.length,
        itemBuilder: (context, index) {
          return _ChannelTile(
            channel: widget.channels[index],
            selected: index == widget.selectedIndex,
            onTap: () => widget.onChanged(index),
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
  });

  final IptvChannel channel;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.85)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                channel.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}