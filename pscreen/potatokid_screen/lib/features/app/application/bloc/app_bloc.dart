import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:potatokid_screen/core/utils/app_settings.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_event.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_state.dart';
import 'package:potatokid_screen/features/app/application/video_aspect_mode.dart';

/// 内部事件：持久化设置加载完成，用于在 bloc 事件循环内安全 emit。
class _PersistedSettingsLoaded extends AppEvent {
  const _PersistedSettingsLoaded({
    required this.themeMode,
    required this.showFloatingRemote,
    required this.hwdecEnabled,
    required this.aspectMode,
    required this.weatherCity,
  });

  final ThemeMode themeMode;
  final bool showFloatingRemote;
  final bool hwdecEnabled;
  final VideoAspectMode aspectMode;
  final String weatherCity;
}

/// 应用级全局状态机：由 main.dart 的 MultiBlocProvider 提供。
///
/// 构造后会异步从 [AppSettings] 加载持久化的设置（主题、悬浮遥控器、硬解、画面等），
/// 加载完成后通过内部事件 emit 新状态；用户修改设置时也会同步写回持久化。
class AppBloc extends Bloc<AppEvent, AppState> {
  AppBloc() : super(AppState.initial()) {
    on<ChangeThemeMode>(_onChangeThemeMode);
    on<SetChrome>(_onSetChrome);
    on<SetChannels>(_onSetChannels);
    on<SetFloatingRemote>(_onSetFloatingRemote);
    on<SetHardwareDecode>(_onSetHardwareDecode);
    on<ChangeAspectMode>(_onChangeAspectMode);
    on<ChangeWeatherCity>(_onChangeWeatherCity);
    on<_PersistedSettingsLoaded>(_onPersistedSettingsLoaded);

    // 异步加载持久化设置（不阻塞首帧），加载完通过内部事件更新状态。
    _loadPersistedSettings();
  }

  Future<void> _loadPersistedSettings() async {
    await AppSettings.instance.ensureLoaded();
    final AppSettings s = AppSettings.instance;
    add(
      _PersistedSettingsLoaded(
        themeMode: s.themeMode,
        showFloatingRemote: s.showFloatingRemote,
        hwdecEnabled: s.hwdecEnabled,
        aspectMode: s.aspectMode,
        weatherCity: s.weatherCity,
      ),
    );
  }

  void _onPersistedSettingsLoaded(_PersistedSettingsLoaded event, Emitter<AppState> emit) {
    emit(
      state.copyWith(
        themeMode: event.themeMode,
        showFloatingRemote: event.showFloatingRemote,
        hwdecEnabled: event.hwdecEnabled,
        aspectMode: event.aspectMode,
        weatherCity: event.weatherCity,
      ),
    );
  }

  void _onChangeThemeMode(ChangeThemeMode event, Emitter<AppState> emit) {
    emit(state.copyWith(themeMode: event.themeMode));
    AppSettings.instance.setThemeMode(event.themeMode);
  }

  void _onSetChrome(SetChrome event, Emitter<AppState> emit) {
    // 只改顶部 tab 条，频道列表独立控制。
    emit(state.copyWith(isChromeVisible: event.visible));
  }

  void _onSetChannels(SetChannels event, Emitter<AppState> emit) {
    emit(state.copyWith(showChannels: event.show));
  }

  void _onSetFloatingRemote(SetFloatingRemote event, Emitter<AppState> emit) {
    emit(state.copyWith(showFloatingRemote: event.show));
    AppSettings.instance.setShowFloatingRemote(event.show);
  }

  void _onSetHardwareDecode(SetHardwareDecode event, Emitter<AppState> emit) {
    emit(state.copyWith(hwdecEnabled: event.enabled));
    AppSettings.instance.setHwdecEnabled(event.enabled);
  }

  void _onChangeAspectMode(ChangeAspectMode event, Emitter<AppState> emit) {
    emit(state.copyWith(aspectMode: event.mode));
    AppSettings.instance.setAspectMode(event.mode);
  }

  void _onChangeWeatherCity(ChangeWeatherCity event, Emitter<AppState> emit) {
    emit(state.copyWith(weatherCity: event.city));
    AppSettings.instance.setWeatherCity(event.city);
  }
}
