import 'package:flutter/foundation.dart';

/// 「我的」页遥控器焦点控制器。
///
/// 采用显式选择态而非 Flutter 方向遍历（因 [IndexedStack] 各分支常驻、
/// 与顶部悬浮导航条几何重叠时，`focusInDirection` 不可靠）。
///
/// 状态分两层：
/// - [focused]：焦点是否在正文列表内（区别于位于顶部导航条）。
/// - [row]：正文列表当前选中行（0=主题 / 1=语言 / 2=悬浮遥控器 / 3=启用硬解 / 4=画面 / 5=天气城市 / 6=定时关闭 / 7=后台播放 / 8=刷新频道 / 9=清理失效源 / 10=复制失效源 / 11=代理重试 / 12=重置 / 13=版本 / 14=天气数据来源 / 15=免责声明）。
///
/// 按键语义（由壳层 [MainApp] 路由到这里）：
/// - 上/下：[moveUp]/[moveDown] 在「导航条 ↔ 十六列设置行」间移动；
/// - 左/右：仅当 [focused] 时由 [step] 步进选中行的值（不切顶部 tab）；
/// - OK：[activate] 激活当前行（音频/视频页的按钮动作，如刷新频道），由壳层调用。
class ProfileFocusController extends ChangeNotifier {
  ProfileFocusController._();

  /// 全局单例。
  static final ProfileFocusController instance = ProfileFocusController._();

  /// 正文列表行数。
  static const int rowCount = 16;

  bool _focused = false;
  int _row = 0;

  /// 值步进的回调（由 [ProfilePage] 注册，负责按当前行执行真的改值）。
  void Function(int row, int delta)? onStepRow;

  /// 行激活回调（OK/触摸触发，由 [ProfilePage] 注册，负责执行按钮动作如刷新频道）。
  void Function(int row)? onActivateRow;

  /// 焦点是否在正文列表内。
  bool get focused => _focused;

  /// 当前选中行：0=主题 / 1=语言 / 2=悬浮遥控器 / 3=启用硬解 / 4=画面 / 5=天气城市 / 6=定时关闭 / 7=后台播放 / 8=刷新频道 / 9=清理失效源 / 10=复制失效源 / 11=代理重试 / 12=重置 / 13=版本 / 14=天气数据来源 / 15=免责声明。
  int get row => _row;

  /// 向下：不在正文则进入正文并选中首行，否则下一行。
  void moveDown() {
    if (!_focused) {
      _focused = true;
      _row = 0;
    } else if (_row < rowCount - 1) {
      _row++;
    }
    notifyListeners();
  }

  /// 向上：若已是首行则退出正文（回到导航条），否则上一行。
  void moveUp() {
    if (!_focused) return;
    if (_row > 0) {
      _row--;
    } else {
      _focused = false;
    }
    notifyListeners();
  }

  /// 直接移动到某行（点击/触摸用）。触摸时同时进入正文。
  void select(int row) {
    _focused = true;
    _row = row.clamp(0, rowCount - 1);
    notifyListeners();
  }

  /// 重置到「位于导航条」状态（进入「我的」分支时调用）。
  void reset() {
    if (!_focused && _row == 0) return;
    _focused = false;
    _row = 0;
    notifyListeners();
  }

  /// 左/右步进当前选中行的值（delta 为 -1/+1）。
  void step(int delta) {
    onStepRow?.call(_row, delta);
  }

  /// 激活当前选中行（OK/触摸触发）：交给页面执行按钮动作（如刷新频道）。
  void activate() {
    onActivateRow?.call(_row);
  }
}