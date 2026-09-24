import 'dart:async';

/// IPTV 事件基类。
abstract class IptvEvent {
  const IptvEvent();
}

/// 加载直播频道列表。
class LoadIptv extends IptvEvent {
  const LoadIptv({this.completer, this.forceRefresh = false});

  /// 需要用完即弃的异步事件时传递，调用方 `await completer.future` 拿结果。
  final Completer<bool>? completer;

  /// 是否强制刷新（当前未做缓存，占位保留）。
  final bool forceRefresh;
}