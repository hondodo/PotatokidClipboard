import 'dart:async';

import 'package:pscreen_screen/features/iptv/application/recording/recording_controller.dart';

/// 当前播放源的单例桥接（纯逻辑，无 UI / 无 Flutter 依赖）。
///
/// 两端播放器在「打开源」时各上报一次（只报 relay 改写前的原始源）：
/// - TV `LivePlayerWidget._playCurrentSource()`
/// - Home `LivePlayerView._openSource()`
///
/// [report] 串联录制三级策略（方案 D-11/12/13）：
/// 1. 先交给 [RecordingController.onSourceReport] 判定是否拦截（manual 切源）；
///    被拒则返回 false，播放器据此**不换源**，[current] 与监听者都不变。
/// 2. 放行时更新 [current]；signature 变化（切台 / auto 换源）才：
///    - 调 controller.onSourceChanged → 停录保存；
///    - 通知 attach 的 UI 监听者刷新（两端可监听显示当前频道等）。
///
/// reload（原地重载同一 URL）signature 不变，不触发停录，录制可继续跟踪。
class RecordingSourceProvider {
  RecordingSourceProvider({RecordingController? controller})
      : _controller = controller ?? RecordingController.instance;

  /// 全局单例。
  static final RecordingSourceProvider instance = RecordingSourceProvider();

  final RecordingController _controller;
  final List<void Function(RecordingSource source)> _listeners =
      <void Function(RecordingSource source)>[];

  /// 最近一次上报的源（UI 可读取；拦截时保持不变）。
  RecordingSource? current;

  /// 注册源变化监听（UI 用）。返回传入的回调便于 detach。
  void attach(void Function(RecordingSource source) listener) {
    if (!_listeners.contains(listener)) _listeners.add(listener);
  }

  void detach(void Function(RecordingSource source) listener) => _listeners.remove(listener);

  /// 上报源变化。返回 false = 本次切源被录制拦截，播放器不得执行换源。
  bool report(RecordingSource source) {
    final bool allowed = _controller.onSourceReport(source);
    if (!allowed) return false;

    final bool changed = current == null || current!.signature != source.signature;
    current = source;
    if (changed) {
      // 停录是异步收尾，不阻塞播放器切源；调用方可 fire-and-forget。
      unawaited(_controller.onSourceChanged(source));
      // 复制到新列表，避免监听者在回调里 detach 导致并发修改。
      for (final void Function(RecordingSource s) listener in _listeners.toList(growable: false)) {
        listener(source);
      }
    }
    return true;
  }

  /// 测试辅助：清空状态与监听者。
  void reset() {
    current = null;
    _listeners.clear();
  }
}
