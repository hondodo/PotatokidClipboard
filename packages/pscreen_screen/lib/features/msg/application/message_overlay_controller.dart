import 'dart:async';
import 'package:flutter/foundation.dart';

/// 消息浮层状态机（全局单例式，但构造器开放供测试；生产用 [instance]）。
///
/// 交互（设计 §5.2）：从上滑入卡片；OK 开详情；两级返回；无操作 1 分钟关闭；
/// 任意按键由外部调 [onAnyKey] 重置计时；新消息直接替换并重置计时；
/// 屏保期间缓存（[deferActive]），退出时调 [onDeferEnd] 弹出。
class MessageOverlayController extends ChangeNotifier {
  MessageOverlayController();

  /// 生产环境全局单例。
  static final MessageOverlayController instance = MessageOverlayController();

  /// 无操作自动关闭时长。
  static const Duration idleTimeout = Duration(minutes: 1);

  String? _text;
  String? _pending;
  bool _visible = false;
  bool _detail = false;
  Timer? _idleTimer;

  /// 屏保互斥：真值由宿主外壳依自身导航状态填充。
  bool deferActive = false;

  /// 屏保期间缓存的最新消息（未弹出）。
  String? get pending => _pending;

  /// 当前展示文本。
  String? get text => _text;

  /// 浮层是否可见。
  bool get visible => _visible;

  /// 详情窗是否打开。
  bool get detail => _detail;

  /// 新消息到达：defer 时缓存；否则直接替换内容（详情中保持详情，spec §5.2）。
  void show(String text) {
    _pending = text;
    if (deferActive) return;
    _display(text);
  }

  /// 退出屏保（宿主在 deferActive 转 false 时调用）。
  void onDeferEnd() {
    final String? pendingText = _pending;
    if (deferActive || pendingText == null) return;
    _display(pendingText);
  }

  /// 替换内容并显示；已开详情时保持详情不关、不重置计时（详情期间暂停计时）。
  void _display(String text) {
    _text = text;
    _visible = true;
    _pending = null;
    if (!_detail) {
      _resetIdleTimer();
    }
    notifyListeners();
  }

  /// 关闭浮层。
  void close() {
    if (!_visible) return;
    _idleTimer?.cancel();
    _idleTimer = null;
    _visible = false;
    _detail = false;
    notifyListeners();
  }

  /// 打开详情（仅可见且未在详情中）。
  void openDetail() {
    if (!_visible || _detail) return;
    _detail = true;
    _idleTimer?.cancel();
    _idleTimer = null;
    notifyListeners();
  }

  /// 关闭详情回浮层卡片，重开计时。
  void closeDetail() {
    if (!_visible || !_detail) return;
    _detail = false;
    _resetIdleTimer();
    notifyListeners();
  }

  /// 返回键：详情→回卡片；卡片→关闭。返回是否消费。
  bool handleBack() {
    if (!_visible) return false;
    if (_detail) {
      closeDetail();
      return true;
    }
    close();
    return true;
  }

  /// OK 键：卡片→开详情。返回是否消费。
  bool handleOk() {
    if (!_visible || _detail) return false;
    openDetail();
    return true;
  }

  /// 浮层可见期间任意按键（由 MainApp 拦截层调用）：重置自动关闭计时。
  void onAnyKey() {
    if (!_visible || _detail) return;
    _resetIdleTimer();
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(idleTimeout, close);
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }
}
