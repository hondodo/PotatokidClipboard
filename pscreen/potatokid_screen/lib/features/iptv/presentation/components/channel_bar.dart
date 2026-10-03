import 'dart:async';

import 'package:flutter/material.dart';
import 'package:potatokid_screen/features/iptv/domain/models/iptv_channel.dart';

/// 右侧垂直频道条：由 [LiveChannelController.index] 驱动，永远与当前播放频道同步。
///
/// - 当前频道高亮显示，并用 [ScrollController] 滚动到可视区**垂直居中**（「跟随」），
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

  /// 把选中项滚到列表**垂直居中**处。
  ///
  /// 首尾各半屏的项因为滚不到负偏移 / 超出底部而自动贴边（要真居中得给列表
  /// 加等高的上下留白，代价是首尾露出半屏空白，故不做）。
  void _scrollToSelected({required bool animate}) {
    if (!_scrollController.hasClients) return;
    final ScrollPosition position = _scrollController.position;
    // 选中项中心对准可视区中心：index*项高 - (视口高 - 项高)/2。
    final double centered =
        widget.selectedIndex * _itemExtent - (position.viewportDimension - _itemExtent) / 2;
    final double target = centered.clamp(0, position.maxScrollExtent);
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

  /// 序号显示位数：按频道总数的位数决定（0-9 显示 1 位，10-99 显示 2 位……）。
  int get _numberWidth {
    final int total = widget.channels.length;
    return total <= 1 ? 1 : total.toString().length;
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
            // 序号从 1 开始，按频道总数的位数左侧补零（8 个频道→`1`，120 个→`001`）。
            number: (index + 1).toString().padLeft(_numberWidth, '0'),
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
    required this.number,
    required this.selected,
    required this.onTap,
  });

  final IptvChannel channel;

  /// 已补齐的频道序号（如 `01` / `12`），显示在频道名前，便于数字键直选。
  final String number;

  final bool selected;
  final VoidCallback onTap;

  /// 序号列宽（容纳最多 4 位序号）。
  static const double _numberWidth = 34;

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
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: _numberWidth,
                    child: Text(
                      number,
                      maxLines: 1,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: selected ? 0.95 : 0.6),
                        fontSize: 13,
                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}