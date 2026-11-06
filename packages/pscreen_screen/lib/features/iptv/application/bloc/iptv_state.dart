import 'package:pscreen_screen/core/network/net_exceptions.dart';
import 'package:pscreen_screen/features/iptv/domain/models/iptv_channel.dart';

/// IPTV 状态：不可变，命名工厂 + copyWith。
class IptvState {
  const IptvState._({
    required this.isLoading,
    required this.isRefreshing,
    required this.errorMessage,
    required this.errorType,
    required this.channels,
    required this.usingCachedList,
  });

  /// 是否加载中（全屏转圈，通常发生在无缓存的首启）。
  final bool isLoading;

  /// 是否后台刷新中（已有频道在播放，刷新完成后替换）。
  final bool isRefreshing;

  /// 错误文案（空表示无错误）
  final String? errorMessage;

  /// 错误语义类型
  final NetErrorType? errorType;

  /// 解析出的频道列表
  final List<IptvChannel> channels;

  /// 本次拉取失败、正在使用上次的频道列表（页面可做轻提示，不打断播放）。
  final bool usingCachedList;

  factory IptvState.initial() => const IptvState._(
        isLoading: false,
        isRefreshing: false,
        errorMessage: null,
        errorType: null,
        channels: <IptvChannel>[],
        usingCachedList: false,
      );

  IptvState copyWith({
    bool? isLoading,
    bool? isRefreshing,
    bool clearError = false,
    String? errorMessage,
    NetErrorType? errorType,
    List<IptvChannel>? channels,
    bool? usingCachedList,
  }) {
    return IptvState._(
      isLoading: isLoading ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      errorType: clearError ? null : (errorType ?? this.errorType),
      channels: channels ?? this.channels,
      usingCachedList: usingCachedList ?? this.usingCachedList,
    );
  }
}
