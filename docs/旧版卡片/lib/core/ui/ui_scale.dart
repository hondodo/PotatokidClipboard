import 'package:flutter/material.dart';
import 'package:pscreen_home/core/storage/settings_store.dart';

/// 未手动设置缩放时的自动适配值。
///
/// [defaultUiScale] 是为 15 寸 1920x1080（逻辑尺寸约 1920x1080、密度 1x）
/// 选定的；手机尤其是竖屏的逻辑短边只有 320~430dp，直接套 1.5 会把可用
/// 逻辑宽度压到 240dp 左右，首页 AppBar 的标题和操作按钮放不下。
/// 因此按逻辑短边分档：
/// - ≥ 1000dp：大屏，保持 1.5；
/// - 600~999dp：平板 / 小尺寸横屏，1.25；
/// - < 600dp：手机（含竖屏），保持 1.0。
double defaultUiScaleFor(Size size) {
  final double shortest = size.shortestSide;
  if (shortest >= 1000) return SettingsStore.defaultUiScale;
  if (shortest >= 600) return 1.25;
  return SettingsStore.minUiScale;
}

/// 全局界面缩放控制器。
///
/// 中控屏固定安装、观看距离远，UI 尺寸不能只按手机 dp 设计：
/// 15 寸 1920x1080 面板上 1dp = 1px ≈ 0.17mm，默认字号和卡片会偏小。
/// 这里用一个全局倍数把整块界面等比放大，设置页可实时调整并持久化；
/// 未手动设置时由 [resolve] 按当前屏幕尺寸选择自动适配值。
class UiScaleController extends ChangeNotifier {
  UiScaleController(this._store) : _override = _store.uiScaleOverride;

  final SettingsStore _store;

  /// 显式设置的内存副本（null = 自动适配），保存完成前也能立即生效。
  double? _override;

  /// 当前生效的缩放倍数：显式设置优先，否则按 [size] 自动适配。
  double resolve(Size size) => _override ?? defaultUiScaleFor(size);

  /// 立即生效（触发整棵树重新布局）并异步持久化。
  Future<void> update(double value) async {
    final double next = SettingsStore.normalizeUiScale(value);
    if (_override == next) return;
    _override = next;
    notifyListeners();
    await _store.saveUiScale(next);
  }
}

/// 把整个应用按 [scale] 等比放大。
///
/// 实现方式：先让子树按「物理尺寸 ÷ scale」的逻辑尺寸布局，再用
/// [FittedBox] 整体放大绘制。好处是不必改动各页面里散落的尺寸常量，
/// 卡片、字号、间距、点击热区一起变大。
///
/// 触控不会偏：`RenderFittedBox` 在命中测试时会用绘制变换的逆矩阵把
/// 触点坐标换算回逻辑坐标系，所以放大后点击位置与视觉位置始终一致。
class UiScaleScope extends StatelessWidget {
  const UiScaleScope({super.key, required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if ((scale - 1).abs() < 0.001) return child;
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final Size logical = Size(
          constraints.maxWidth / scale,
          constraints.maxHeight / scale,
        );
        final MediaQueryData mq = MediaQuery.of(context);
        return FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: logical.width,
            height: logical.height,
            child: MediaQuery(
              data: mq.copyWith(
                size: logical,
                padding: mq.padding / scale,
                viewPadding: mq.viewPadding / scale,
                viewInsets: mq.viewInsets / scale,
                // 逻辑像素被放大了 scale 倍，等效设备像素比同步放大，
                // 保证图片按正确的物理分辨率取样（不会糊）。
                devicePixelRatio: mq.devicePixelRatio * scale,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
