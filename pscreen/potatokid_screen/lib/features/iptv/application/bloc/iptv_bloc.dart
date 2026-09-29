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
/// - 无缓存首启（全新安装）：直接用包内默认频道列表立即显示，后台拉取线上，
///   成功后替换，失败则保留默认列表继续可用；
/// - 手动刷新（[LoadIptv.isRefresh]）：保留当前频道后台拉取，失败保持现状。
/// - 加载成功写回缓存，供下次启动使用。
///
/// 持久化缓存**只存接口数据**；展示列表 = 包内 `collect.m3u` + 接口数据
/// （含排序/剔除），每次加载/刷新都重新拼接（见 [IptvRepository.buildPlaylist]）。
/// 接口失败且无缓存也无默认时才进入错误视图。
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
    // 1) 初始加载先读持久化缓存（仅接口数据），补上 collect 后作为加载成功前的兜底列表。
    List<IptvChannel> cached = const <IptvChannel>[];
    if (event.useCache) {
      final List<IptvChannel>? raw = await _cache.load();
      if (raw != null && raw.isNotEmpty) {
        cached = await _repository.buildPlaylist(raw);
      }
    }

    // 1b) 无缓存（全新安装）时，直接用包内默认频道列表撑起画面，
    //     避免首启全屏 loading；后台继续拉取线上，成功后替换。
    if (cached.isEmpty && state.channels.isEmpty) {
      final List<IptvChannel> defaults = await _repository.buildPlaylist(
        await _repository.loadDefaultRemoteChannels(),
      );
      if (defaults.isNotEmpty) {
        cached = defaults;
      }
    }

    // 2) 已有可显示的频道（含缓存 / 现行 / 包内默认）→ 保留画面后台刷新；
    //    否则（无缓存且无默认 / 从错误页重试）→ 全屏转圈等网络。
    final bool keepCurrent = state.channels.isNotEmpty || cached.isNotEmpty;
    if (keepCurrent) {
      if (state.channels.isEmpty && cached.isNotEmpty) {
        // 先用缓存/默认列表撑起播放器，避免网络在途时画面被置空。
        emit(state.copyWith(channels: cached));
      }
      emit(state.copyWith(isLoading: false, isRefreshing: true, clearError: true));
    } else {
      emit(state.copyWith(isLoading: true, clearError: true));
    }

    try {
      final List<IptvChannel> remote = await _repository.fetchRemoteChannels();
      // 3) 加载成功：只把接口数据写回缓存（collect 不进缓存），
      //    展示列表再动态拼接 collect 并排序/剔除。
      await _cache.save(remote);
      completeBlocEvent(event.completer, success: true);
      emit(state.copyWith(
        isLoading: false,
        isRefreshing: false,
        channels: await _repository.buildPlaylist(remote),
        clearError: true,
      ));
    } catch (e, s) {
      Injection.get<LogService>().error('加载直播频道失败', error: e, stackTrace: s);
      completeBlocEvent(event.completer, success: false);
      // 4) 失败：有兜底（缓存 / 现行）→ 保留现有频道继续播、不切错误页；
      //    否则 → 用包内默认列表兜底；再不行才进入错误视图。
      final bool hasFallback = state.channels.isNotEmpty || cached.isNotEmpty;
      if (!hasFallback) {
        final List<IptvChannel> defaults = await _repository.buildPlaylist(
          await _repository.loadDefaultRemoteChannels(),
        );
        if (defaults.isNotEmpty) {
          Injection.get<LogService>().info('[IptvBloc] 接口不可用，已用包内默认频道列表兜底');
          emit(state.copyWith(
            isLoading: false,
            isRefreshing: false,
            channels: defaults,
            clearError: true,
          ));
          return;
        }
      }
      emit(state.copyWith(
        isLoading: false,
        isRefreshing: false,
        errorType: e.toNetErrorType(),
        errorMessage: hasFallback ? null : mapErrorToMessage(e),
      ));
    }
  }
}