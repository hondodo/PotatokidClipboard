import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:potatokid_screen/core/di/injection.dart';
import 'package:potatokid_screen/core/logging/log_service.dart';
import 'package:potatokid_screen/core/network/net_exceptions.dart';
import 'package:potatokid_screen/core/utils/bloc_event.dart';
import 'package:potatokid_screen/core/utils/error_message.dart';
import 'package:potatokid_screen/features/home/application/bloc/home_event.dart';
import 'package:potatokid_screen/features/home/application/bloc/home_state.dart';
import 'package:potatokid_screen/features/home/data/models/home_model.dart';
import 'package:potatokid_screen/features/home/domain/repositories/home_repository.dart';

/// 首页状态机：Event → Bloc → State
class HomeBloc extends Bloc<HomeEvent, HomeState> {
  HomeBloc({required HomeRepository repository})
      : _repository = repository,
        super(HomeState.initial()) {
    on<LoadHomeList>(_onLoadHomeList);
  }

  final HomeRepository _repository;

  Future<void> _onLoadHomeList(LoadHomeList event, Emitter<HomeState> emit) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final List<HomeModel> items = await _repository.fetchHomeList();
      emit(state.copyWith(isLoading: false, items: items));
      completeBlocEvent(event.completer, success: true);
    } catch (e, s) {
      Injection.get<LogService>().error('加载首页列表失败', error: e, stackTrace: s);
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
}
