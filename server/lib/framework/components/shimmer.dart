import 'package:flutter/material.dart';

class Shimmer extends StatefulWidget {
  static ShimmerState? of(BuildContext context) {
    return context.findAncestorStateOfType<ShimmerState>();
  }

  const Shimmer({
    super.key,
    this.linearGradient,
    this.child,
    this.duration,
    this.pauseDuration,
  });

  final LinearGradient? linearGradient;
  final Widget? child;

  /// 闪动周期，默认1000ms
  final Duration? duration;

  /// 闪动停顿时间，默认0ms
  final Duration? pauseDuration;

  @override
  ShimmerState createState() => ShimmerState();
}

class ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late AnimationController _shimmerController;
  late LinearGradient _linearGradient;

  @override
  void initState() {
    super.initState();

    _linearGradient = widget.linearGradient ??
        LinearGradient(
          colors: [
            Colors.black.withAlpha(10),
            Colors.white.withAlpha(10),
          ],
          stops: const [
            0.1,
            0.3,
            0.4,
          ],
          begin: const Alignment(-1.0, -0.3),
          end: const Alignment(1.0, 0.3),
          tileMode: TileMode.clamp,
        );
    _shimmerController = AnimationController(
      vsync: this,
      duration: widget.duration ?? const Duration(milliseconds: 1000),
      lowerBound: -0.5,
      upperBound: 1.5,
    ); //.unbounded(vsync: this);
    _shimmerController.addStatusListener(onAnimationStatusChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      afterFirstBuild();
    });
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  void afterFirstBuild() {
    _shimmerController.reset();
    _shimmerController.forward();
  }

  void onAnimationStatusChanged(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      if (widget.pauseDuration != null) {
        Future.delayed(widget.pauseDuration!, () {
          if (mounted) {
            _shimmerController.reset();
            _shimmerController.forward();
          }
        });
      } else {
        _shimmerController.reset();
        _shimmerController.forward();
      }
    }
  }

  LinearGradient get gradient => LinearGradient(
        colors: _linearGradient.colors,
        stops: _linearGradient.stops,
        begin: _linearGradient.begin,
        end: _linearGradient.end,
        transform:
            _SlidingGradientTransform(slidePercent: _shimmerController.value),
      );

  bool get isSized =>
      (context.findRenderObject() as RenderBox?)?.hasSize ?? false;

  Size get size => (context.findRenderObject() as RenderBox).size;

  Offset getDescendantOffset({
    required RenderBox descendant,
    Offset offset = Offset.zero,
  }) {
    final shimmerBox = context.findRenderObject() as RenderBox?;
    return descendant.localToGlobal(offset, ancestor: shimmerBox);
  }

  Listenable get shimmerChanges => _shimmerController;

  @override
  Widget build(BuildContext context) {
    return widget.child ?? const SizedBox.shrink();
  }
}

class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform({
    required this.slidePercent,
  });

  final double slidePercent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * slidePercent, 0.0, 0.0);
  }
}
