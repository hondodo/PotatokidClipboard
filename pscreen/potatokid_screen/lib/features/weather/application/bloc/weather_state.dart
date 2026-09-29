import 'package:potatokid_screen/core/network/net_exceptions.dart';
import 'package:potatokid_screen/features/weather/domain/models/weather_models.dart';

/// 天气状态（不可变，通过 copyWith 更新）。
class WeatherState {
  const WeatherState._({
    required this.isLoading,
    required this.data,
    required this.errorMessage,
    required this.errorType,
  });

  /// 初始状态。
  factory WeatherState.initial() => const WeatherState._(
        isLoading: false,
        data: null,
        errorMessage: null,
        errorType: null,
      );

  final bool isLoading;
  final WeatherData? data;
  final String? errorMessage;
  final NetErrorType? errorType;

  bool get hasData => data != null && !data!.isEmpty;

  WeatherState copyWith({
    bool? isLoading,
    WeatherData? data,
    String? errorMessage,
    NetErrorType? errorType,
    bool clearError = false,
  }) {
    return WeatherState._(
      isLoading: isLoading ?? this.isLoading,
      data: data ?? this.data,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      errorType: clearError ? null : (errorType ?? this.errorType),
    );
  }
}