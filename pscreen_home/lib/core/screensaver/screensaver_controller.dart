import 'package:flutter/foundation.dart';
import 'package:pscreen_home/core/storage/settings_store.dart';

/// 屏保空闲时长控制器。
///
/// 设置页修改后立即通知全局 [ScreensaverHost] 重新计时，
/// 同时异步写入 [SettingsStore] 供下次启动恢复。
class ScreensaverController extends ChangeNotifier {
  ScreensaverController(this._store) : _minutes = _store.screensaverMinutes;

  final SettingsStore _store;
  int _minutes;
  bool _active = false;

  /// 当前屏保空闲时长（分钟）。
  int get minutes => _minutes;

  /// 当前是否由空闲计时自动进入了屏保。
  ///
  /// `/clock` 同时被手动时钟入口使用，场景上报必须靠这个标志区分
  /// 「屏保」和「时钟」。
  bool get active => _active;

  set active(bool value) {
    if (_active == value) return;
    _active = value;
    notifyListeners();
  }

  /// 更新屏保时长；非法值或未变化时忽略。
  Future<void> setMinutes(int minutes) async {
    if (!SettingsStore.screensaverOptions.contains(minutes) ||
        minutes == _minutes) {
      return;
    }
    _minutes = minutes;
    notifyListeners();
    await _store.saveScreensaverMinutes(minutes);
  }
}
