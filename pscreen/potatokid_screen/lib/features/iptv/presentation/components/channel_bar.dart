import 'dart:async';

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

  /// 快速滚动判定阈值：两次选中变化间隔小于此值视为快速滚动，用 jumpTo 即时跟上。
  static const int _rapidScrollThresholdMs = 150;

  /// 松手后（停止快速滚动）延迟多久做最终平滑归位。
  static const int _settleDelayMs = 120;

  final ScrollController _scrollController = ScrollController();
  Timer? _settleTimer;
  int _lastIndexChangeAt = 0;

  @override
  void didUpdateWidget(covariant ChannelBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 频道切换时跟随高亮；从收起变成显示时定位到当前频道。
    if (oldWidget.selectedIndex != widget.selectedIndex) {
      final int now = DateTime.now().millisecondsSinceEpoch;
      final bool rapid = (now - _lastIndexChangeAt) < _rapidScrollThresholdMs;
      _lastIndexChangeAt = now;

      if (rapid) {
        // 快速滚动：jumpTo 即时跟上，避免动画队列滞后。
        _scrollToSelected(animate: false);
        _settleTimer?.cancel();
        _settleTimer = Timer(
          const Duration(milliseconds: _settleDelayMs),
          () => _scrollToSelected(animate: true),
        );
      } else {
        // 单步切换：正常平滑动画。
        _settleTimer?.cancel();
        _scrollToSelected(animate: true);
      }
    } else if (!oldWidget.visible && widget.visible) {
      _scrollToSelected(animate: false);
    }
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
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
    // 频道列表项不参与 Flutter 焦点系统：
    // 导航完全由 LiveChannelController（上下键切台）驱动，
    // 避免出现「高亮选中项」和「焦点项」不一致导致按 OK 切错台的问题。
    return ExcludeFocus(
      child: Padding(
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
      ),
    );
  }
}