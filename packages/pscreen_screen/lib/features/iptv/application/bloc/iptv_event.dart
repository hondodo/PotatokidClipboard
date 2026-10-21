import 'dart:async';

/// IPTV 事件基类。
abstract class IptvEvent {
  const IptvEvent();
}

/// 加载直播频道列表。
class LoadIptv extends IptvEvent {
  const LoadIptv({this.completer, this.useCache = false, this.isRefresh = false});

  /// 需要用完即弃的异步事件时传递，调用方 `await completer.future` 拿结果。
  final Completer<bool>? completer;

  /// 初始加载是否先读取持久化缓存：有缓存则先展示、再后台刷新替换；
  /// 无缓存则全屏转圈等网络。手动刷新请用 [isRefresh]。
  final bool useCache;

  /// 是否手动/后台刷新：保留当前频道，加载失败保持现状（不切错误页）。
  final bool isRefresh;
}

/// 按「清理失效源」重新计算展示列表。
///
/// [enabled] 为开关当前值：开启时剔除失效地址（源被剔光的频道整体移除），
/// 关闭时用完整列表还原。开关切换、以及刚记录到新的失效地址时都会派发。
class FilterInvalidChannels extends IptvEvent {
  const FilterInvalidChannels(this.enabled);

  final bool enabled;
}