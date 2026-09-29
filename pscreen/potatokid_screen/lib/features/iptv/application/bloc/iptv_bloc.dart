import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:potatokid_screen/core/di/injection.dart';
import 'package:potatokid_screen/core/logging/log_service.dart';
import 'package:potatokid_screen/core/network/net_exceptions.dart';
import 'package:potatokid_screen/core/utils/bloc_event.dart';
import 'package:potatokid_screen/core/utils/error_message.dart';
import 'package:potatokid_screen/features/iptv/application/bloc/iptv_event.dart';
import 'package:potatokid_screen/features/iptv/application/bloc/iptv_state.dart';
import 'package:potatokid_screen/features/iptv/application/channel_list_cache.dart';
import 'package:potatokid_screen/features/iptv/domain/models/iptv_channel.dart';
import 'package:potatokid_screen/features/iptv/domain/repositories/iptv_repository.dart';

/// IPTV 状态机：Event → Bloc → State，加载直播频道列表。
///
/// 加载策略（缓存优先 + 后台替换）：
/// - 首次启动（[LoadIptv.useCache]）：先读持久化缓存撑起画面，再网络刷新替换，
///   即便离线/加载失败也能继续用上一次成功的列表播放；
/// - 手动刷新（[LoadIptv.isRefresh]）：保留当前频道后台拉取，失败保持现状。
/// - 加载成功均写回缓存，供下次启动使用。
class IptvBloc extends Bloc<IptvEvent, IptvState> {
  IptvBloc({required IptvRepository repository})
      : _repository = repository,
        _cache = ChannelListCache.instance,
        super(IptvState.initial()) {
    on<LoadIptv>(_onLoadIptv);
  }

  final IptvRepository _repository;
  final ChannelListCache _cache;

  Future<void> _onLoadIptv(LoadIptv event, Emitter<IptvState> emit) async {
    // 1) 初始加载先读持久化缓存，作为加载成功前的兜底列表。
    List<IptvChannel> cached = const <IptvChannel>[];
    if (event.useCache) {
      cached = await _cache.load() ?? const <IptvChannel>[];
    }

    // 2) 已有可显示的频道（含缓存 / 现行）→ 保留画面后台刷新；
    //    否则（无缓存首启 / 从错误页重试）→ 全屏转圈等网络。
    final bool keepCurrent = state.channels.isNotEmpty || cached.isNotEmpty;
    if (keepCurrent) {
      if (state.channels.isEmpty && cached.isNotEmpty) {
        // 先用缓存撑起播放器，避免网络在途时画面被置空。
        emit(state.copyWith(channels: cached));
      }
      emit(state.copyWith(isLoading: false, isRefreshing: true, clearError: true));
    } else {
      emit(state.copyWith(isLoading: true, clearError: true));
    }

    try {
      final List<IptvChannel> fresh = await _repository.fetchChannels();
      // 3) 加载成功：写回缓存（下次启动优先用缓存），并切换到新列表。
      await _cache.save(fresh);
      completeBlocEvent(event.completer, success: true);
      emit(state.copyWith(
        isLoading: false,
        isRefreshing: false,
        channels: fresh,
        clearError: true,
      ));
    } catch (e, s) {
      Injection.get<LogService>().error('加载直播频道失败', error: e, stackTrace: s);
      completeBlocEvent(event.completer, success: false);
      // 4) 失败：有兜底（缓存 / 现行）→ 保留现有频道继续播、不切错误页；
      //    否则（无任何频道）→ 进入错误视图。
      final bool hasFallback = state.channels.isNotEmpty || cached.isNotEmpty;
      emit(state.copyWith(
        isLoading: false,
        isRefreshing: false,
        errorType: e.toNetErrorType(),
        errorMessage: hasFallback ? null : mapErrorToMessage(e),
      ));
    }
  }
}