import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_event.dart';
import 'package:potatokid_screen/features/app/application/bloc/app_state.dart';

/// 应用级全局状态机：由 main.dart 的 MultiBlocProvider 提供。
class AppBloc extends Bloc<AppEvent, AppState> {
  AppBloc() : super(AppState.initial()) {
    on<ChangeThemeMode>(_onChangeThemeMode);
    on<ToggleChrome>(_onToggleChrome);
  }

  void _onChangeThemeMode(ChangeThemeMode event, Emitter<AppState> emit) {
    emit(state.copyWith(themeMode: event.themeMode));
  }

  void _onToggleChrome(ToggleChrome event, Emitter<AppState> emit) {
    emit(state.copyWith(isChromeVisible: !state.isChromeVisible));
  }
}
