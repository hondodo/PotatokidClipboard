import 'package:potatokid_screen/core/network/net_exceptions.dart';
import 'package:potatokid_screen/features/home/data/models/home_model.dart';

/// 首页状态（不可变，通过 copyWith 更新）
class HomeState {
  const HomeState._({
    required this.isLoading,
    required this.items,
    required this.errorMessage,
    required this.errorType,
  });

  /// 初始状态
  factory HomeState.initial() => const HomeState._(
        isLoading: false,
        items: <HomeModel>[],
        errorMessage: null,
        errorType: null,
      );

  final bool isLoading;
  final List<HomeModel> items;
  final String? errorMessage;
  final NetErrorType? errorType;

  HomeState copyWith({
    bool? isLoading,
    List<HomeModel>? items,
    String? errorMessage,
    NetErrorType? errorType,
    bool clearError = false,
  }) {
    return HomeState._(
      isLoading: isLoading ?? this.isLoading,
      items: items ?? this.items,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      errorType: clearError ? null : (errorType ?? this.errorType),
    );
  }
}
