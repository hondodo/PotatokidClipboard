import 'package:flutter/material.dart';
import 'package:potatokid_screen/features/msg/application/message_overlay_controller.dart';

/// 消息浮层：顶部滑入卡片 + 详情窗（设计 §5.2）。
class MessageOverlay extends StatefulWidget {
  const MessageOverlay({super.key});

  @override
  State<MessageOverlay> createState() => _MessageOverlayState();
}

class _MessageOverlayState extends State<MessageOverlay> {
  final MessageOverlayController _controller = MessageOverlayController.instance;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChange);
  }

  @override
  void dispose() {
    _controller.removeListener(_onChange);
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

  @override
  Widget build(BuildContext context) {
    if (!_controller.visible) return const SizedBox.shrink();
    final String text = _controller.text ?? '';
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: const EdgeInsets.only(top: 48),
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 220),
          offset: Offset.zero,
          child: Material(
            color: scheme.surfaceContainerHigh,
            elevation: 8,
            borderRadius: BorderRadius.circular(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: _controller.detail
                  ? _DetailPane(text: text)
                  : _PreviewPane(text: text),
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

/// 详情窗：全文可滚动（D-pad 上下）。
class _DetailPane extends StatelessWidget {
  const _DetailPane({required this.text});

  final String text;

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
              child: SingleChildScrollView(
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
