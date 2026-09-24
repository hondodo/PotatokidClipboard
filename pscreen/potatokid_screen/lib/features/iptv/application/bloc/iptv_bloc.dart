import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:potatokid_screen/core/di/injection.dart';
import 'package:potatokid_screen/core/logging/log_service.dart';
import 'package:potatokid_screen/core/network/net_exceptions.dart';
import 'package:potatokid_screen/core/utils/bloc_event.dart';
import 'package:potatokid_screen/core/utils/error_message.dart';
import 'package:potatokid_screen/features/iptv/application/bloc/iptv_event.dart';
import 'package:potatokid_screen/features/iptv/application/bloc/iptv_state.dart';
import 'package:potatokid_screen/features/iptv/domain/models/iptv_channel.dart';
import 'package:potatokid_screen/features/iptv/domain/repositories/iptv_repository.dart';

/// IPTV 状态机：Event → Bloc → State，加载直播频道列表。
class IptvBloc extends Bloc<IptvEvent, IptvState> {
  IptvBloc({required IptvRepository repository})
      : _repository = repository,
        super(IptvState.initial()) {
    on<LoadIptv>(_onLoadIptv);
  }

  final IptvRepository _repository;

  Future<void> _onLoadIptv(LoadIptv event, Emitter<IptvState> emit) async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final List<IptvChannel> channels = await _repository.fetchChannels();
      emit(state.copyWith(isLoading: false, channels: channels));
      completeBlocEvent(event.completer, success: true);
    } catch (e, s) {
      Injection.get<LogService>().error('加载直播列表失败', error: e, stackTrace: s);
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