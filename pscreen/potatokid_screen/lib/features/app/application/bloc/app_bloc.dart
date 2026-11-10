import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_event.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_state.dart';
import 'package:pscreen_screen/core/media/video_aspect_mode.dart';

/// 内部事件：持久化设置加载完成，用于在 bloc 事件循环内安全 emit。
class _PersistedSettingsLoaded extends AppEvent {
  const _PersistedSettingsLoaded({
    required this.themeMode,
    required this.showFloatingRemote,
    required this.hwdecEnabled,
    required this.aspectMode,
    required this.weatherCity,
    required this.removeInvalidSources,
    required this.backgroundPlayback,
  });

  final ThemeMode themeMode;
  final bool showFloatingRemote;
  final bool hwdecEnabled;
  final VideoAspectMode aspectMode;
  final String weatherCity;
  final bool removeInvalidSources;
  final bool backgroundPlayback;
}

/// 应用级全局状态机：由 main.dart 的 MultiBlocProvider 提供。
///
/// 构造后会异步从 [AppSettings] 加载持久化的设置（主题、悬浮遥控器、硬解、画面等），
/// 加载完成后通过内部事件 emit 新状态；用户修改设置时也会同步写回持久化。
class AppBloc extends Bloc<AppEvent, AppState> {
  AppBloc() : super(AppState.initial()) {
    on<ChangeThemeMode>(_onChangeThemeMode);
    on<SetChrome>(_onSetChrome);
    on<SetChromePeek>(_onSetChromePeek);
    on<SetHomeRemoteLayer>(_onSetHomeRemoteLayer);
    on<SetFloatingRemote>(_onSetFloatingRemote);
    on<SetHardwareDecode>(_onSetHardwareDecode);
    on<ChangeAspectMode>(_onChangeAspectMode);
    on<ChangeWeatherCity>(_onChangeWeatherCity);
    on<SetRemoveInvalidSources>(_onSetRemoveInvalidSources);
    on<SetBackgroundPlayback>(_onSetBackgroundPlayback);
    on<_PersistedSettingsLoaded>(_onPersistedSettingsLoaded);

    // 异步加载持久化设置（不阻塞首帧），加载完通过内部事件更新状态。
    _loadPersistedSettings();
  }

  Future<void> _loadPersistedSettings() async {
    await AppSettings.instance.ensureLoaded();
    // 加载完成时 bloc 可能已随宿主销毁（快速退出/测试卸载）：跳过 add，
    // 否则 bloc 框架会抛「Cannot add new events after calling close」。
    if (isClosed) return;
    final AppSettings s = AppSettings.instance;
    add(
      _PersistedSettingsLoaded(
        themeMode: s.themeMode,
        showFloatingRemote: s.showFloatingRemote,
        hwdecEnabled: s.hwdecEnabled,
        aspectMode: s.aspectMode,
        weatherCity: s.weatherCity,
        removeInvalidSources: s.removeInvalidSources,
        backgroundPlayback: s.backgroundPlayback,
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
        removeInvalidSources: event.removeInvalidSources,
        backgroundPlayback: event.backgroundPlayback,
      ),
    );
  }

  void _onChangeThemeMode(ChangeThemeMode event, Emitter<AppState> emit) {
    emit(state.copyWith(themeMode: event.themeMode));
    AppSettings.instance.setThemeMode(event.themeMode);
  }

  /// 「预览态」计时令牌：新事件/正式显隐会让旧计时失效。
  int _chromePeekToken = 0;

  void _onSetChrome(SetChrome event, Emitter<AppState> emit) {
    _chromePeekToken++;
    emit(
      state.copyWith(
        isChromeVisible: event.visible,
        isChromePeek: false,
        homeRemoteLayer: event.visible
            ? HomeRemoteLayer.appBar
            : state.homeRemoteLayer == HomeRemoteLayer.appBar
            ? HomeRemoteLayer.fullscreen
            : state.homeRemoteLayer,
      ),
    );
  }

  void _onSetChromePeek(SetChromePeek event, Emitter<AppState> emit) {
    // 正式显示时预览无意义；直接忽略，避免盖掉可聚焦状态。
    if (!event.visible || state.isChromeVisible) return;
    final int token = ++_chromePeekToken;
    emit(state.copyWith(isChromePeek: true));
    Timer(const Duration(seconds: 3), () {
      if (isClosed || token != _chromePeekToken) return;
      add(const SetChromePeek(false));
    });
  }

  void _onSetHomeRemoteLayer(
    SetHomeRemoteLayer event,
    Emitter<AppState> emit,
  ) {
    _chromePeekToken++;
    emit(
      state.copyWith(
        homeRemoteLayer: event.layer,
        isChromeVisible: event.layer == HomeRemoteLayer.appBar,
        isChromePeek: false,
      ),
    );
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

  void _onSetRemoveInvalidSources(SetRemoveInvalidSources event, Emitter<AppState> emit) {
    emit(state.copyWith(removeInvalidSources: event.enabled));
    AppSettings.instance.setRemoveInvalidSources(event.enabled);
  }

  void _onSetBackgroundPlayback(
    SetBackgroundPlayback event,
    Emitter<AppState> emit,
  ) {
    emit(state.copyWith(backgroundPlayback: event.enabled));
    AppSettings.instance.setBackgroundPlayback(event.enabled);
  }
}
