import 'package:flutter/foundation.dart';

/// 当前顶部 Tab 状态（MainApp 每次 build 填充；上报/浮层互斥读这里）。
///
/// 通过 [changes] 对外广播 Tab 变化，供场景上报（`TvSceneProvider`）即时推送
/// `state` 帧，无需轮询。
class AppTabController {
  AppTabController._();

  /// 「我的」在 MainApp._tabs 中的序号（与 MainApp._profileBranchIndex 一致）。
  static const int profileIndex = 3;

  /// 「屏保」在 MainApp._tabs 中的序号。
  static const int screensaverIndex = 2;

  static final ValueNotifier<int> _branch = ValueNotifier<int>(0);

  /// 当前分支序号（0 首页 / 1 时间 / 2 屏保 / 3 我的）。
  static int get branchIndex => _branch.value;

  /// 写入当前分支序号；值未变化时不发通知（MainApp 每次 build 都会写）。
  static set branchIndex(int value) => _branch.value = value;

  /// Tab 变更通知。
  static Listenable get changes => _branch;

  /// 屏保是否激活。
  static bool get isScreensaver => branchIndex == screensaverIndex;

  /// 上报用页名（设计 §3.2：不在频道时报当前页面）。
  static String get pageName {
    switch (branchIndex) {
      case 0:
        return '主页';
      case 1:
        return '时间页';
      case 2:
        return '屏保';
      case 3:
        return '设置';
      default:
        return '主页';
    }
  }
}
