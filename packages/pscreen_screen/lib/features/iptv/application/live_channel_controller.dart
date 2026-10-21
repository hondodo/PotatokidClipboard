import 'dart:async';

import 'package:flutter/foundation.dart';

/// 首页频道控制器：由壳层「上/下」键驱动频道切换，
/// `LivePlayerWidget` 监听其变化并切换播放流。
///
/// **「选中」与「播放」分离**（TV 盒子长按连切会卡的关键）：
/// - 选中（[index]）随按键**立即**变化，驱动频道条高亮和左下角频道名提示，
///   长按时仍与现在一样飞快跟手；
/// - 播放（[onPlayCommit]）在**停止切换 [commitDelay] 之后**才提交一次，
///   长按连切期间不会反复 `player.open()`/停止——
///   否则每 80ms 一次 open 会在盒子上形成播放/停止风暴，直接卡死。
///
/// 显式选择（列表点击 / 数字键直选 / 恢复上次频道）走 [select]：
/// 用户已经明确指定终点，**立即提交播放**，不延迟。
class LiveChannelController extends ChangeNotifier {
  LiveChannelController._();

  /// 全局单例。
  static final LiveChannelController instance = LiveChannelController._();

  /// 停止切换操作后多久提交播放。
  ///
  /// 用「尾部防抖」而不是「等 KeyUp 再延时」：每次选中变化都把定时器重置，
  /// 长按期间不断重置、松手后 [commitDelay] 到期才播。这样不依赖 KeyUp 事件
  /// 可靠到达（有的盒子/遥控器会丢 KeyUp，靠 KeyUp 提交会导致永远不播）。
  static const Duration commitDelay = Duration(milliseconds: 400);

  int _index = 0;
  int _count = 0;

  /// 待提交播放的定时器（长按连切时被不断重置）。
  Timer? _commitTimer;

  /// 播放提交信号。与「选中」的通知分开，避免频道条刷新也触发换源播放。
  final _PlayCommitNotifier _playCommit = _PlayCommitNotifier();

  /// 当前选中频道序号（立即变化，供频道条高亮 / 频道名提示使用）。
  int get index => _index;

  /// 频道总数（由 LivePlayerWidget 在频道加载后设置）。
  int get count => _count;

  /// 播放提交通知：`LivePlayerWidget` 监听它，收到后才真正 open 新源。
  Listenable get onPlayCommit => _playCommit;

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

  /// 下一个频道：立即更新选中，播放延迟提交。
  void next() => _step(1);

  /// 上一个频道：立即更新选中，播放延迟提交。
  void previous() => _step(-1);

  /// 直接切换到指定序号（列表点击 / 数字键直选 / 恢复上次频道）：立即播放。
  void select(int value) {
    if (value < 0 || value >= _count || value == _index) return;
    _index = value;
    notifyListeners();
    _commitNow();
  }

  void _step(int delta) {
    if (_count <= 0) return;
    _index = (_index + delta + _count) % _count;
    notifyListeners();
    // 长按连切时反复重置：只有停手 commitDelay 之后才会真正换源。
    _commitTimer?.cancel();
    _commitTimer = Timer(commitDelay, () {
      _commitTimer = null;
      _playCommit.commit();
    });
  }

  void _commitNow() {
    _commitTimer?.cancel();
    _commitTimer = null;
    _playCommit.commit();
  }

  @override
  void dispose() {
    _commitTimer?.cancel();
    _commitTimer = null;
    _playCommit.dispose();
    super.dispose();
  }
}

/// 播放提交信号（`ChangeNotifier.notifyListeners` 是 protected，包一层供内部调用）。
class _PlayCommitNotifier extends ChangeNotifier {
  void commit() => notifyListeners();
}
