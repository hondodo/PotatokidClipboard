import 'package:flutter/foundation.dart';
import 'package:potatokid_screen/shared/widgets/floating_remote.dart';

/// 屏幕模拟遥控的按键分发入口（进程内单例）。
///
/// [FloatingRemote] 被提升到 `MaterialApp.router` 的 builder 层后位于
/// Navigator 之上，拿不到 [MainApp] 的 context，因此由 MainApp 在 build 时
/// 把既有的 `_onRemoteButton` 注册到这里，遥控器只经本单例回调。
///
/// 真实遥控走的是 Flutter 焦点链 → `MainApp._handleRootKey`，与本单例完全
/// 无关；这里只搬运模拟遥控的回调，不改动任何按键处理逻辑。
class RemoteKeyDispatcher {
  RemoteKeyDispatcher._();

  /// 全局唯一实例。
  static final RemoteKeyDispatcher instance = RemoteKeyDispatcher._();

  ValueChanged<RemoteButton>? _handler;

  /// 注册（或替换）宿主处理函数；MainApp 每次 build 都会调用，重复注册幂等。
  void attach(ValueChanged<RemoteButton> handler) => _handler = handler;

  /// 清理宿主处理函数（宿主卸载时调用，避免持有已失效的 context）。
  void detach() => _handler = null;

  /// 屏幕模拟遥控按键入口；宿主尚未挂载时静默丢弃。
  void dispatch(RemoteButton button) => _handler?.call(button);
}
