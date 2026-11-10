import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 为整棵 TV 界面提供稳定的设计坐标系。
///
/// 固定尺寸、字号和间距都以 1280x720 为基准统一缩放；非 16:9 设备通过扩展
/// 逻辑宽度或高度利用完整屏幕，不拉伸、不裁切，也不产生黑边。
class TvDesignViewport extends StatelessWidget {
  const TvDesignViewport({super.key, required this.child});

  static const Size designSize = Size(1280, 720);

  final Widget child;

  EdgeInsets _unscale(EdgeInsets value, double scale) => EdgeInsets.fromLTRB(
    value.left / scale,
    value.top / scale,
    value.right / scale,
    value.bottom / scale,
  );

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size actual = constraints.biggest;
        if (!actual.width.isFinite ||
            !actual.height.isFinite ||
            actual.isEmpty) {
          return child;
        }

        final double scale = math.min(
          actual.width / designSize.width,
          actual.height / designSize.height,
        );
        if (!scale.isFinite || scale <= 0) return child;

        // 例如 4:3 屏会得到 1280x960 的逻辑画布；所有固定尺寸仍按 720p
        // 比例显示，多出的高度则交给页面的响应式布局使用。
        final Size logicalSize = Size(
          actual.width / scale,
          actual.height / scale,
        );
        final double textScale = media.textScaler.scale(1).clamp(1.0, 1.2);
        final MediaQueryData logicalMedia = media.copyWith(
          size: logicalSize,
          padding: _unscale(media.padding, scale),
          viewPadding: _unscale(media.viewPadding, scale),
          viewInsets: _unscale(media.viewInsets, scale),
          systemGestureInsets: _unscale(media.systemGestureInsets, scale),
          textScaler: TextScaler.linear(textScale),
        );

        return ClipRect(
          child: FittedBox(
            alignment: Alignment.topLeft,
            fit: BoxFit.fill,
            child: SizedBox.fromSize(
              size: logicalSize,
              child: MediaQuery(data: logicalMedia, child: child),
            ),
          ),
        );
      },
    );
  }
}
