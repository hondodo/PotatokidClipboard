import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pscreen_home/core/storage/settings_store.dart';

/// home 端的整屏设计坐标系，机制与 TV 端 `TvDesignViewport` 完全一致：
/// 先按设计画布算出统一 scale，再让整棵 UI 树在「实际尺寸 / scale」的
/// 逻辑画布里布局，最后用 [FittedBox] 整体等比放大绘制。
///
/// 因此任意分辨率下字号、间距、卡片比例恒定，既不拉伸也不裁切；
/// 非 16:9 屏通过扩展另一维逻辑画布利用完整屏幕。
class HomeDesign {
  /// 横屏设计画布（TV 同款 960×540）：对外统一的缩放基准。
  ///
  /// 在 1920×1080 上 scale = 2，但 home 的卡片/字号常量是按 1280×720 写的，
  /// 所以再乘 [landscapeContentScale] 得到实际内容画布 1280×720，
  /// 4 列 × 320 宽 × 188 高，物理观感与历史版本完全一致。
  static const Size landscapeDesignSize = Size(960, 540);

  /// 竖屏设计画布：常用手机竖屏尺寸（如 iPhone 14/15 的 390×844）。
  /// 手机常量本来就按这个密度写，不需要换算。
  static const Size portraitDesignSize = Size(390, 844);

  /// 横屏内容密度因子：把 1280×720 的内容常量映射到 960×540 设计画布。
  ///
  /// scale = min(w/960, h/540) × 0.75 = min(w/1280, h/720)，
  /// 即横屏逻辑画布恒为 [landscapeCanvas]，内容不再溢出。
  static const double landscapeContentScale = 0.75;

  /// 横屏逻辑画布：所有横屏内容常量（4 列 × 320 宽、行高 188）按此编写。
  static const Size landscapeCanvas = Size(1280, 720);

  /// 竖屏内容密度因子：手机常量按竖屏画布写，无需换算。
  static const double portraitContentScale = 1.0;

  /// 竖屏逻辑画布：常用手机竖屏尺寸，2 列布局。
  static const Size portraitCanvas = portraitDesignSize;

  /// 横屏首页一行 4 个；竖屏一行 2 个。
  static const int landscapeColumns = 4;
  static const int portraitColumns = 2;

  /// 横屏 row=1 行高（与历史 1280×720 画布一致）。
  static const double landscapeCellExtent = 188;

  /// 竖屏 row=1 行高：390 宽 2 列约 180，chip 换行更多，留足高度。
  static const double portraitCellExtent = 228;

  static const double baseSpacing = 14;
  static const double basePadding = 16;

  /// 竖屏判定：高明显大于宽（手机竖屏、竖屏平板）。
  static bool isPortrait(Size size) => size.height > size.width * 1.2;

  /// 当前屏幕对应的逻辑画布尺寸。
  static Size canvasFor(Size size) =>
      isPortrait(size) ? portraitCanvas : landscapeCanvas;
}

/// 未手动设置缩放时的自动适配值。
///
/// - 竖屏：以 [HomeDesign.portraitDesignSize] 为基准，手机 1.0 不放大；
/// - 横屏：以 [HomeDesign.landscapeDesignSize] 为基准连续推导，再乘内容密度
///   因子得到 home 自己的逻辑画布；非 16:9 屏扩展另一维，不拉伸、不裁切。
double defaultUiScaleFor(Size size) {
  if (HomeDesign.isPortrait(size)) {
    final double scale = math.min(
      size.width / HomeDesign.portraitDesignSize.width,
      size.height / HomeDesign.portraitDesignSize.height,
    );
    return SettingsStore.normalizeUiScale(
      scale * HomeDesign.portraitContentScale,
    );
  }

  final double scale = math.min(
    size.width / HomeDesign.landscapeDesignSize.width,
    size.height / HomeDesign.landscapeDesignSize.height,
  );
  return SettingsStore.normalizeUiScale(
    scale * HomeDesign.landscapeContentScale,
  );
}

/// 全局界面缩放控制器（纯自动，与 TV 端一致）。
///
/// 中控屏固定安装、观看距离远，UI 尺寸不能只按手机 dp 设计：
/// 15 寸 1920x1080 面板上 1dp = 1px ≈ 0.17mm，默认字号和卡片会偏小。
/// 缩放完全由 [defaultUiScaleFor] 按屏幕尺寸推导，不再允许手动覆盖：
/// 历史版本可通过设置页把倍数固化（如 ui_scale=1.0），覆盖了自动适配，
/// 导致窗口变小时内容不缩放而被裁切；去掉手动覆盖后内容与 TV 一样
/// 在任何分辨率下保持同一设计比例。窗口 resize 时 scale 随屏幕连续变化，
/// 由 [UiScaleScope] 的 LayoutBuilder 自动重建，无需手动拖动。
class UiScaleController {
  /// 当前屏幕对应的自动缩放倍数。
  double resolve(Size size) => defaultUiScaleFor(size);
}

/// 把整个应用按 [scale] 等比放大，机制与 TV 端 `TvDesignViewport` 一致。
///
/// 先让子树按「物理尺寸 ÷ scale」的逻辑尺寸布局，再用 [FittedBox] 整体
/// 放大绘制。好处是不必改动各页面里散落的尺寸常量，卡片、字号、间距、
/// 点击热区一起变大；同一设计画布下不同分辨率看到的布局完全一致。
///
/// 触控不会偏：`RenderFittedBox` 在命中测试时会用绘制变换的逆矩阵把
/// 触点坐标换算回逻辑坐标系，所以放大后点击位置与视觉位置始终一致。
class UiScaleScope extends StatelessWidget {
  const UiScaleScope({super.key, required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // 与 TV 端一致：异常约束下直接返回子树，避免除零/无限画布。
        if (!constraints.maxWidth.isFinite ||
            !constraints.maxHeight.isFinite ||
            constraints.maxWidth <= 0 ||
            constraints.maxHeight <= 0) {
          return child;
        }
        double effective = scale;
        if (!effective.isFinite || effective <= 0) effective = 1;

        final Size logical = Size(
          constraints.maxWidth / effective,
          constraints.maxHeight / effective,
        );
        final MediaQueryData mq = MediaQuery.of(context);
        // 与 TV 端一致：系统字体缩放只做小范围跟随，避免大屏上
        // 辅助功能字体被全局放大后撑破卡片。
        final double textScale = mq.textScaler.scale(1).clamp(1.0, 1.2);
        return ClipRect(
          child: FittedBox(
            alignment: Alignment.topLeft,
            fit: BoxFit.fill,
            child: SizedBox(
              width: logical.width,
              height: logical.height,
              child: MediaQuery(
                data: mq.copyWith(
                  size: logical,
                  padding: EdgeInsets.fromLTRB(
                    mq.padding.left / effective,
                    mq.padding.top / effective,
                    mq.padding.right / effective,
                    mq.padding.bottom / effective,
                  ),
                  viewPadding: EdgeInsets.fromLTRB(
                    mq.viewPadding.left / effective,
                    mq.viewPadding.top / effective,
                    mq.viewPadding.right / effective,
                    mq.viewPadding.bottom / effective,
                  ),
                  viewInsets: EdgeInsets.fromLTRB(
                    mq.viewInsets.left / effective,
                    mq.viewInsets.top / effective,
                    mq.viewInsets.right / effective,
                    mq.viewInsets.bottom / effective,
                  ),
                  textScaler: TextScaler.linear(textScale),
                  // 逻辑像素被放大了 scale 倍，等效设备像素比同步放大，
                  // 保证图片按正确的物理分辨率取样（不会糊）。
                  devicePixelRatio: mq.devicePixelRatio * effective,
                ),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}
