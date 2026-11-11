import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:potatokid_screen/shared/widgets/kid_chrome.dart';
import 'package:pscreen_screen/core/parental/parental_state_controller.dart';
import 'package:pscreen_screen/core/update/app_update_controller.dart';
import 'package:pscreen_screen/features/iptv/domain/models/iptv_channel.dart';

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
    required this.onActivated,
    required this.visible,
    required this.interactive,
  });

  final List<IptvChannel> channels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final ValueChanged<int> onActivated;

  /// 列表是否可见（用于呼出时定位到当前频道）
  final bool visible;

  /// 是否为可操作面板。预览列表虽然可见，但不能获得遥控焦点。
  final bool interactive;

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
        _settleTimer = Timer(const Duration(milliseconds: _settleDelayMs), () => _scrollToSelected(animate: true));
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
    final double centered = widget.selectedIndex * _itemExtent - (position.viewportDimension - _itemExtent) / 2;
    final double target = centered.clamp(0, position.maxScrollExtent);
    if (animate) {
      _scrollController.animateTo(target, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
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
    // 儿童模式：频道列表换成深蓝渐变面板（圆角 + 描边 + 阴影）。
    final bool kid = kidModeOn;
    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: kid
          ? BoxDecoration(
              gradient: KidPalette.dialog,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24),
              boxShadow: const <BoxShadow>[
                BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 6)),
              ],
            )
          : BoxDecoration(
              gradient: AdultPalette.panelGradient,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
              boxShadow: const <BoxShadow>[
                BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 6)),
              ],
            ),
      child: Column(
        children: <Widget>[
          Expanded(
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
                  interactive: widget.interactive,
                  // 首尾循环：第一个再按上跳到最后一个，最后一个再按下跳回第一个。
                  wrapUp: index == 0,
                  wrapDown: index == widget.channels.length - 1,
                  onWrap: (bool toLast) => widget.onChanged(toLast ? widget.channels.length - 1 : 0),
                  onFocused: () => widget.onChanged(index),
                  onTap: () => widget.onActivated(index),
                );
              },
            ),
          ),
          // 纯文案引导：仅可操作的频道列表层显示，不可聚焦、不拦截按键。
          if (widget.interactive) const _KidCapsuleBackHint(),
        ],
      ),
    );
  }
}

/// 儿童模式下有更新可安装时，提示「再按一次返回键」进入快捷胶囊菜单。
///
/// 只读文案，不参与焦点树、不改变频道列表的滚动与切台行为。
class _KidCapsuleBackHint extends StatelessWidget {
  const _KidCapsuleBackHint();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ParentalStateController.instance,
      builder: (BuildContext context, _) {
        if (!kidModeOn) return const SizedBox.shrink();
        return ValueListenableBuilder<AppUpdateState>(
          valueListenable: AppUpdateController.instance,
          builder: (BuildContext context, AppUpdateState update, _) {
            if (!update.showPill || update.forceBlocked) {
              return const SizedBox.shrink();
            }
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(8, 8, 8, 2),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: KidPalette.capsule,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white24),
              ),
              child: Text(
                'kid_capsule_back_hint'.tr(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ChannelTile extends StatefulWidget {
  const _ChannelTile({
    required this.channel,
    required this.number,
    required this.selected,
    required this.interactive,
    required this.wrapUp,
    required this.wrapDown,
    required this.onWrap,
    required this.onFocused,
    required this.onTap,
  });

  final IptvChannel channel;

  /// 已补齐的频道序号（如 `01` / `12`），显示在频道名前，便于数字键直选。
  final String number;

  final bool selected;
  final bool interactive;

  /// 本项是否为第一个 / 最后一个频道（用于首尾循环）。
  final bool wrapUp;
  final bool wrapDown;

  /// 首尾循环回调：`true` 跳到最后一个，`false` 跳到第一个。
  final ValueChanged<bool> onWrap;

  final VoidCallback onFocused;
  final VoidCallback onTap;

  /// 序号列宽（容纳最多 4 位序号）。
  static const double _numberWidth = 34;

  @override
  State<_ChannelTile> createState() => _ChannelTileState();
}

class _ChannelTileState extends State<_ChannelTile> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'channel-tile');

  @override
  void didUpdateWidget(_ChannelTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.interactive && _focusNode.hasFocus) {
      _focusNode.unfocus();
      return;
    }
    // 预览转为正式面板时外观仍然可见，但交互状态发生变化，需重新聚焦。
    if (widget.interactive &&
        widget.selected &&
        (!oldWidget.interactive || !oldWidget.selected)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool focused = _focusNode.hasFocus;
    // 儿童模式：暖黄胶囊 + 深色字；普通模式：淡橙胶囊 + 深色字。
    final bool kid = kidModeOn;
    final double tileRadius = kid ? 14 : 8;
    final Color tileColor = widget.selected
        ? (kid ? KidPalette.accent : AdultPalette.selection)
        : Colors.transparent;
    final Color numberColor = widget.selected
        ? (kid ? KidPalette.accentInk.withValues(alpha: 0.85) : AdultPalette.selectionInk.withValues(alpha: 0.8))
        : (kid ? KidPalette.softBlue : Colors.white.withValues(alpha: 0.54));
    final Color nameColor = widget.selected
        ? (kid ? KidPalette.accentInk : AdultPalette.selectionInk)
        : Colors.white;
    // 首尾循环：焦点停在第一个/最后一个再按上/下时，直接把选中跳到另一端。
    // 只拦截「到头」的这一下，其余方向键照旧交给壳层做焦点移动。
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        if (!widget.interactive) return KeyEventResult.ignored;
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp && widget.wrapUp) {
          widget.onWrap(true);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown && widget.wrapDown) {
          widget.onWrap(false);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedScale(
        scale: focused ? 1.03 : 1,
        duration: const Duration(milliseconds: 120),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          child: Material(
            color: tileColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(tileRadius),
              side: focused ? const BorderSide(color: Colors.white, width: 2) : BorderSide.none,
            ),
            child: InkWell(
              focusNode: _focusNode,
              canRequestFocus: widget.interactive,
              onFocusChange: (bool value) {
                if (value) widget.onFocused();
                if (mounted) setState(() {});
              },
              borderRadius: BorderRadius.circular(tileRadius),
              onTap: widget.onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: _ChannelTile._numberWidth,
                      child: Text(
                        widget.number,
                        maxLines: 1,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: numberColor,
                          fontSize: 13,
                          fontWeight: widget.selected ? FontWeight.bold : FontWeight.normal,
                          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: nameColor,
                          fontSize: 14,
                          fontWeight: widget.selected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
