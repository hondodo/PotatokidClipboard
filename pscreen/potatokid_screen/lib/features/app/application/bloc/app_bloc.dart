import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_event.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_state.dart';

/// 应用级全局状态机：由 main.dart 的 MultiBlocProvider 提供。
class AppBloc extends Bloc<AppEvent, AppState> {
  AppBloc() : super(AppState.initial()) {
    on<ChangeThemeMode>(_onChangeThemeMode);
    on<ToggleChrome>(_onToggleChrome);
    on<SetChrome>(_onSetChrome);
    on<SetChannels>(_onSetChannels);
    on<ToggleChannels>(_onToggleChannels);
    on<SetFloatingRemote>(_onSetFloatingRemote);
  }

  void _onChangeThemeMode(ChangeThemeMode event, Emitter<AppState> emit) {
    emit(state.copyWith(themeMode: event.themeMode));
  }

  void _onToggleChrome(ToggleChrome event, Emitter<AppState> emit) {
    // 顶部 tab 条与频道条同步显隐（OK 键）。
    final bool visible = !state.isChromeVisible;
    emit(state.copyWith(isChromeVisible: visible, showChannels: visible));
  }

  void _onSetChrome(SetChrome event, Emitter<AppState> emit) {
    // 只改顶部 tab 条，频道列表独立控制。
    emit(state.copyWith(isChromeVisible: event.visible));
  }

  void _onSetChannels(SetChannels event, Emitter<AppState> emit) {
    emit(state.copyWith(showChannels: event.show));
  }

  void _onToggleChannels(ToggleChannels event, Emitter<AppState> emit) {
    emit(state.copyWith(showChannels: !state.showChannels));
  }

  void _onSetFloatingRemote(SetFloatingRemote event, Emitter<AppState> emit) {
    emit(state.copyWith(showFloatingRemote: event.show));
  }
}
