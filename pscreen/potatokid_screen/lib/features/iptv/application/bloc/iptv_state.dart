import 'package:potatokid_screen/core/network/net_exceptions.dart';
import 'package:potatokid_screen/features/iptv/domain/models/iptv_channel.dart';

/// IPTV 状态：不可变，命名工厂 + copyWith。
class IptvState {
  const IptvState._({
    required this.isLoading,
    required this.errorMessage,
    required this.errorType,
    required this.channels,
  });

  /// 是否加载中
  final bool isLoading;

  /// 错误文案（空表示无错误）
  final String? errorMessage;

  /// 错误语义类型
  final NetErrorType? errorType;

  /// 解析出的频道列表
  final List<IptvChannel> channels;

  factory IptvState.initial() => const IptvState._(
        isLoading: false,
        errorMessage: null,
        errorType: null,
        channels: <IptvChannel>[],
      );

  IptvState copyWith({
    bool? isLoading,
    bool clearError = false,
    String? errorMessage,
    NetErrorType? errorType,
    List<IptvChannel>? channels,
  }) {
    return IptvState._(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      errorType: clearError ? null : (errorType ?? this.errorType),
      channels: channels ?? this.channels,
    );
  }
}