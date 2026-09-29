import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:potatokid_screen/core/di/injection.dart';
import 'package:potatokid_screen/core/logging/log_service.dart';
import 'package:potatokid_screen/core/network/net_exceptions.dart';
import 'package:potatokid_screen/core/utils/bloc_event.dart';
import 'package:potatokid_screen/core/utils/error_message.dart';
import 'package:potatokid_screen/features/weather/application/bloc/weather_event.dart';
import 'package:potatokid_screen/features/weather/application/bloc/weather_state.dart';
import 'package:potatokid_screen/features/weather/domain/models/weather_models.dart';
import 'package:potatokid_screen/features/weather/domain/repositories/weather_repository.dart';

/// 天气状态机：定位 → 拉取 → State。
class WeatherBloc extends Bloc<WeatherEvent, WeatherState> {
  WeatherBloc({required WeatherRepository repository})
      : _repository = repository,
        super(WeatherState.initial()) {
    on<LoadWeather>(_onLoadWeather);
    on<ClearWeather>(_onClearWeather);
  }

  final WeatherRepository _repository;

  Future<void> _onLoadWeather(
    LoadWeather event,
    Emitter<WeatherState> emit,
  ) async {
    // 已加载且非强刷时直接返回，避免重复请求。
    if (state.hasData && !event.force) {
      completeBlocEvent(event.completer, success: true);
      return;
    }
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final String? location = await _repository.resolveLocation();
      if (location == null) {
        throw StateError('无法获取设备位置');
      }
      final WeatherData data = await _repository.fetchWeather(location);
      emit(state.copyWith(isLoading: false, data: data));
      completeBlocEvent(event.completer, success: true);
    } catch (e, s) {
      Injection.get<LogService>().error('加载天气失败', error: e, stackTrace: s);
      emit(
        state.copyWith(
          isLoading: false,
          errorMessage: mapErrorToMessage(e),
          errorType: e.toNetErrorType(),
        ),
      );
      completeBlocEvent(event.completer, success: false);
    }
  }

  Future<void> _onClearWeather(
    ClearWeather event,
    Emitter<WeatherState> emit,
  ) async {
    emit(WeatherState.initial());
  }
}