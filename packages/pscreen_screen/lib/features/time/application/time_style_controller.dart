import 'package:flutter/foundation.dart';

/// 时间页显示样式。
enum TimeStyle {
  /// 完整：时间 + 日期 + 农历 + 星期（与效果图一致）
  full,

  /// 仅显示时间
  timeOnly,

  /// 转盘（模拟）时钟
  dial,
}

/// 全局时间样式控制器：由壳层根按键（上/下）驱动，
/// 「时间」Tab 通过 [ListenableBuilder] 监听渲染。
class TimeStyleController extends ChangeNotifier {
  TimeStyleController._();

  /// 全局单例。
  static final TimeStyleController instance = TimeStyleController._();

  int _index = 0;

  static int get count => TimeStyle.values.length;

  /// 当前样式。
  TimeStyle get style => TimeStyle.values[_index];

  /// 切换到下一屏。
  void next() {
    _index = (_index + 1) % count;
    notifyListeners();
  }

  /// 切换到上一屏。
  void previous() {
    _index = (_index - 1 + count) % count;
    notifyListeners();
  }
}