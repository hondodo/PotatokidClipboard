import 'package:flutter/material.dart';
import 'package:potatokid_screen/features/iptv/domain/models/iptv_channel.dart';

/// 横向频道条：底部半透明叠加层，D-pad 左右移动焦点即切换频道。
///
/// 频道项使用可聚焦组件但**不注册 ActivateIntent**，因此 OK 键会继续冒泡到
/// 壳层，用于显示/隐藏顶部导航栏（与「OK 管显隐」约定一致）。
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
      height: 108,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[Colors.transparent, Colors.black87],
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: <Widget>[
            for (int i = 0; i < channels.length; i++)
              _ChannelTile(
                channel: channels[i],
                index: i,
                selected: i == selectedIndex,
                onFocus: onChanged,
              ),
          ],
        ),
      ),
    );
  }
}

class _ChannelTile extends StatefulWidget {
  const _ChannelTile({
    required this.channel,
    required this.index,
    required this.selected,
    required this.onFocus,
  });

  final IptvChannel channel;
  final int index;
  final bool selected;

  /// 获得焦点时的回调，用于「焦点即切台」。
  final ValueChanged<int> onFocus;

  @override
  State<_ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<_ChannelTile> {
  late final FocusNode _focusNode;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode()..addListener(_onFocusChanged);
  }

  void _onFocusChanged() {
    final bool focused = _focusNode.hasFocus;
    setState(() => _focused = focused);
    if (focused) {
      widget.onFocus(widget.index);
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool active = widget.selected || _focused;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Focus(
        focusNode: _focusNode,
        autofocus: widget.selected,
        // 触摸降级：手机直接点频道也切换（requestFocus 走焦点监听→切台+高亮）
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _focusNode.requestFocus(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: active
                  ? scheme.primary.withValues(alpha: 0.85)
                  : Colors.white24,
              borderRadius: BorderRadius.circular(10),
              border: _focused
                  ? Border.all(color: Colors.white, width: 2)
                  : null,
            ),
            child: Text(
              widget.channel.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontWeight: widget.selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ),
      ),
    );
  }
}