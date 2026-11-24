import 'package:flutter/material.dart';

/// 跑马灯滚动方式（由后台 JSON 的 marqueeMode 决定）。
enum MarqueeMode {
  /// 单向连续无缝滚动：文字走出视口的同时从另一侧接上，永不停止。
  loop,
  /// 往返滚动：跑到端点停留 pause 秒，再反向跑回起点停留 pause 秒，循环。
  pingpong,
}

/// 跑马灯起始运动方向。loop 表示滚动方向；pingpong 表示先往哪边跑。
enum MarqueeDirection { left, right }

/// 单行文本跑马灯。文字不超过容器宽度时静止并显示全文，不显示省略号。
///
/// 由 JsonCardRenderer 在 text 节点 marquee=true 时使用；不依赖 WebView，
/// 只用 AnimationController + TextPainter 测量，维度由父级约束给出。
class MarqueeText extends StatefulWidget {
  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.mode = MarqueeMode.loop,
    this.direction = MarqueeDirection.left,
    this.pause = 2,
    this.speed = 40,
    this.textAlign = TextAlign.left,
  });

  final String text;
  final TextStyle style;
  final MarqueeMode mode;
  final MarqueeDirection direction;

  /// pingpong 模式在两端各停留的秒数（loop 忽略）。
  final double pause;

  /// 滚动速度，逻辑像素/秒。
  final double speed;
  final TextAlign textAlign;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> with SingleTickerProviderStateMixin {
  /// 只作为逐帧 tick 的驱动；周期由实际文字宽度/速度算出，避免动态改 duration。
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat();

  DateTime _startedAt = DateTime.now();

  static const double _gap = 32;

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.mode != widget.mode ||
        oldWidget.direction != widget.direction ||
        oldWidget.pause != widget.pause ||
        oldWidget.speed != widget.speed) {
      _startedAt = DateTime.now();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextStyle style = widget.style;
    final TextPainter painter = TextPainter(
      text: TextSpan(text: widget.text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final double textWidth = painter.width;
    final double lineHeight = painter.preferredLineHeight > 0
        ? painter.preferredLineHeight
        : (style.fontSize ?? 14) * 1.35;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double viewport = constraints.maxWidth;
        // 无界宽度（如 Row 里没写 expand）或文字没超宽：退化为普通单行文本。
        if (!viewport.isFinite || textWidth <= viewport + 1) {
          return Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: widget.textAlign,
            style: style,
          );
        }

        return RepaintBoundary(
          child: ClipRect(
            child: SizedBox(
              width: viewport,
              height: lineHeight + 2,
              child: AnimatedBuilder(
                animation: _controller,
                builder: (BuildContext context, Widget? _) {
                  final double elapsed =
                      DateTime.now().difference(_startedAt).inMicroseconds / 1000000.0;
                  final List<double> xs = _positions(elapsed, textWidth, viewport);
                  return Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      for (final double x in xs)
                        Positioned(
                          left: x,
                          top: 0,
                          child: SizedBox(
                            width: textWidth + 2,
                            child: Text(
                              widget.text,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.visible,
                              style: style,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// 返回每一份文字副本的横坐标。loop 用两份副本做无缝衔接；
  /// pingpong 只有一份，在起点和尽头之间往返（端点停留由时间轴切分实现）。
  List<double> _positions(double elapsed, double textWidth, double viewport) {
    final double speed = widget.speed > 0 ? widget.speed : 40;
    final double pause = widget.pause > 0 ? widget.pause : 0;
    final bool toRight = widget.direction == MarqueeDirection.right;

    if (widget.mode == MarqueeMode.pingpong) {
      final double travelDist = textWidth - viewport;
      final double travel = travelDist / speed;
      final double total = 2 * travel + 2 * pause;
      final double t = total > 0 ? elapsed % total : 0;
      double p; // 0=起点（左对齐），1=尽头（尾部对齐）
      if (toRight) {
        // 从尽头出发向右跑到开头 → 停留 → 向左跑回尽头 → 停留。
        if (t < travel) {
          p = 1 - t / travel;
        } else if (t < travel + pause) {
          p = 0;
        } else if (t < 2 * travel + pause) {
          p = (t - travel - pause) / travel;
        } else {
          p = 1;
        }
      } else {
        // 从开头向左跑到尽头 → 停留 → 向右跑回开头 → 停留。
        if (t < travel) {
          p = t / travel;
        } else if (t < travel + pause) {
          p = 1;
        } else if (t < 2 * travel + pause) {
          p = 1 - (t - travel - pause) / travel;
        } else {
          p = 0;
        }
      }
      return <double>[-travelDist * p];
    }

    final double distance = textWidth + _gap;
    final double period = distance / speed;
    final double t = period > 0 ? elapsed % period : 0;
    final double p = period > 0 ? t / period : 0;
    return toRight
        ? <double>[p * distance, p * distance - distance]
        : <double>[-p * distance, -p * distance + distance];
  }
}
