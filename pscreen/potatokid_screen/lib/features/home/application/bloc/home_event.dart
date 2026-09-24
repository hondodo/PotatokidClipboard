import 'dart:async';

/// 首页事件基类
abstract class HomeEvent {
  const HomeEvent();
}

/// 加载首页列表
class LoadHomeList extends HomeEvent {
  const LoadHomeList({this.completer, this.forceRefresh = false});

  /// 供调用方 await 事件完成
  final Completer<bool>? completer;

  /// 是否强制刷新
  final bool forceRefresh;
}
