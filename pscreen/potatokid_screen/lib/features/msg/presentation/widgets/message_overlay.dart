import 'package:flutter/material.dart';
import 'package:potatokid_screen/features/msg/application/message_overlay_controller.dart';

/// 消息浮层：顶部滑入卡片 + 详情窗（设计 §5.2）。
class MessageOverlay extends StatefulWidget {
  const MessageOverlay({super.key});

  /// 详情窗 D-pad 上下滚动入口（负数向上、正数向下，单位：逻辑像素）。
  ///
  /// 浮层独立于 rootOkHandler 焦点链，MainApp 拦截层（物理键与悬浮遥控器
  /// 的统一入口）在详情模式下把上下键转发到这里；浮层未挂载或未开详情时
  /// 为空操作。
  static void scrollDetail(int direction) {
    _MessageOverlayState._instance?.scrollDetail(direction);
  }

  @override
  State<MessageOverlay> createState() => _MessageOverlayState();
}

class _MessageOverlayState extends State<MessageOverlay> {
  /// 详情窗滚动步长（逻辑像素 / 每次按键；长按由 KeyRepeatController 重复）。
  static const double _detailScrollStep = 80;

  final MessageOverlayController _controller =
      MessageOverlayController.instance;
  final ScrollController _detailScroll = ScrollController();

  static _MessageOverlayState? _instance;

  @override
  void initState() {
    super.initState();
    _instance = this;
    _controller.addListener(_onChange);
  }

  @override
  void dispose() {
    _instance = null;
    _controller.removeListener(_onChange);
    _detailScroll.dispose();
    super.dispose();
  }

  void _onChange() {
    if (!mounted) return;
    setState(() {});
    if (_controller.visible && !_controller.detail) {
      // 抢占焦点（关闭后由页面自行恢复——main_app 拦截层负责全局键）。
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  /// 见 [MessageOverlay.scrollDetail]。
  void scrollDetail(int direction) {
    if (!mounted || !_controller.detail || !_detailScroll.hasClients) return;
    final ScrollPosition position = _detailScroll.position;
    final double target =
        (position.pixels + direction * _detailScrollStep)
            .clamp(position.minScrollExtent, position.maxScrollExtent)
            .toDouble();
    _detailScroll.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    final String text = _controller.text ?? '';
    final ColorScheme scheme = Theme.of(context).colorScheme;
    // 常驻挂载以驱动顶部滑入动画；隐藏时透明并忽略指针，不挡下层操作。
    return IgnorePointer(
      ignoring: !_controller.visible,
      child: Opacity(
        opacity: _controller.visible ? 1 : 0,
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 48),
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 220),
              offset: _controller.visible ? Offset.zero : const Offset(0, -1.5),
              child: Material(
                color: scheme.surfaceContainerHigh,
                elevation: 8,
                borderRadius: BorderRadius.circular(16),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: _controller.detail
                      ? _DetailPane(
                          text: text,
                          scrollController: _detailScroll,
                        )
                      : _PreviewPane(text: text),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 卡片预览：截断单行。
class _PreviewPane extends StatelessWidget {
  const _PreviewPane({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }
}

/// 详情窗：全文可滚动（D-pad 上下，经 [MessageOverlay.scrollDetail] 驱动）。
class _DetailPane extends StatelessWidget {
  const _DetailPane({required this.text, required this.scrollController});

  final String text;
  final ScrollController scrollController;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 720,
      height: 360,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Text(
              '消息详情',
              style: Theme.of(context).textTheme.labelLarge,
            ),
          ),
          Expanded(
            child: Scrollbar(
              controller: scrollController,
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '返回：关闭',
              style: Theme.of(context).textTheme.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}
