import 'package:flutter/material.dart';
import 'package:pscreen_home/core/storage/settings_store.dart';

/// 全局界面缩放控制器。
///
/// 中控屏固定安装、观看距离远，UI 尺寸不能只按手机 dp 设计：
/// 15 寸 1920x1080 面板上 1dp = 1px ≈ 0.17mm，默认字号和卡片会偏小。
/// 这里用一个全局倍数把整块界面等比放大，设置页可实时调整并持久化。
class UiScaleController extends ChangeNotifier {
  UiScaleController(this._store) : _scale = _store.uiScale;

  final SettingsStore _store;
  double _scale;

  /// 当前缩放倍数（1.0 = 原始尺寸）。
  double get scale => _scale;

  /// 立即生效（触发整棵树重新布局）并异步持久化。
  Future<void> update(double value) async {
    final double next = SettingsStore.normalizeUiScale(value);
    if ((next - _scale).abs() < 0.001) return;
    _scale = next;
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
