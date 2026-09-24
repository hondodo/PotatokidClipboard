import 'package:flutter/foundation.dart';

/// 首页频道控制器：由壳层「上/下」键驱动频道切换，
/// `LivePlayerWidget` 监听其变化并切换播放流。
class LiveChannelController extends ChangeNotifier {
  LiveChannelController._();

  /// 全局单例。
  static final LiveChannelController instance = LiveChannelController._();

  int _index = 0;
  int _count = 0;

  /// 当前选中频道序号。
  int get index => _index;

  /// 频道总数（由 LivePlayerWidget 在频道加载后设置）。
  int get count => _count;

  /// 设置频道总数，并在越界时校正选中值。
  void setCount(int value) {
    if (value == _count) return;
    _count = value;
    if (_count == 0) {
      _index = 0;
    } else if (_index >= _count) {
      _index = _count - 1;
    }
    notifyListeners();
  }

  /// 下一个频道。
  void next() {
    if (_count <= 0) return;
    _index = (_index + 1) % _count;
    notifyListeners();
  }

  /// 上一个频道。
  void previous() {
    if (_count <= 0) return;
    _index = (_index - 1 + _count) % _count;
    notifyListeners();
  }

  /// 直接切换到指定序号。
  void select(int value) {
    if (value < 0 || value >= _count || value == _index) return;
    _index = value;
    notifyListeners();
  }
}