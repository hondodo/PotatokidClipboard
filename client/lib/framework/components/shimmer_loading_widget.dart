import 'package:flutter/material.dart';
import '../../../framework/components/shimmer.dart';
import '../../../framework/components/shimmer_loading.dart';

enum ShimmerLoadingColorStyle {
  /// 浅色-以白色(页面等)为背景，闪烁主题色（紫色），默认
  light,

  /// 深色-以深色（紫色按钮等）为背景，闪烁白色，用于深色背景
  dark,
}

enum ShimmerLoadingPreset {
  /// 默认
  none,

  /// chat now 按钮
  chatNow,
}

class ShimmerLoadingWidget extends StatefulWidget {
  const ShimmerLoadingWidget(
      {super.key,
      this.shimmerEmptyMaskColor,
      required this.child,
      this.colorStyle = ShimmerLoadingColorStyle.light,
      this.duration,
      this.pauseDuration,
      this.preset = ShimmerLoadingPreset.none});
  final Color? shimmerEmptyMaskColor;
  final Widget child;
  final ShimmerLoadingColorStyle colorStyle;
  final Duration? duration;
  final Duration? pauseDuration;

  /// 预设方案，用于快速设置预设的闪烁效果, 默认ShimmerLoadingPreset.none
  /// 当preset不为none时，colorStyle会被忽略
  final ShimmerLoadingPreset preset;

  @override
  State<ShimmerLoadingWidget> createState() => _ShimmerLoadingWidgetState();
}

class _ShimmerLoadingWidgetState extends State<ShimmerLoadingWidget> {
  late LinearGradient _linearGradient;
  late Duration _duration;
  late Duration _pauseDuration;
  late Color? shimmerEmptyMaskColor;

  @override
  void initState() {
    super.initState();

    _duration = widget.duration ?? const Duration(milliseconds: 1000);
    _pauseDuration = widget.pauseDuration ?? const Duration(milliseconds: 1000);
    shimmerEmptyMaskColor = null;
    ShimmerLoadingColorStyle colorStyle = widget.colorStyle;
    if (widget.preset == ShimmerLoadingPreset.chatNow) {
      colorStyle = ShimmerLoadingColorStyle.dark;
      _duration = const Duration(milliseconds: 1000);
      _pauseDuration = const Duration(milliseconds: 1000);
      shimmerEmptyMaskColor = Colors.transparent;
    }
    _linearGradient = colorStyle == ShimmerLoadingColorStyle.light
        ? LinearGradient(
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
          )
        : LinearGradient(
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
  }

  @override
  Widget build(BuildContext context) {
    var shimmerLoading = ShimmerLoading(
        isLoading: true,
        emptyMaskColor: shimmerEmptyMaskColor,
        child: widget.child);
    return Shimmer(
      duration: _duration,
      pauseDuration: _pauseDuration,
      linearGradient: _linearGradient,
      child: shimmerLoading,
    );
  }
}
