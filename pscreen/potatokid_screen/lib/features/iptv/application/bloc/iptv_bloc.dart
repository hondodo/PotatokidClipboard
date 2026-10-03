import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:potatokid_screen/app/config/data_files.dart';
import 'package:potatokid_screen/core/di/injection.dart';
import 'package:potatokid_screen/core/logging/log_service.dart';
import 'package:potatokid_screen/core/network/net_exceptions.dart';
import 'package:potatokid_screen/core/utils/app_settings.dart';
import 'package:potatokid_screen/core/utils/bloc_event.dart';
import 'package:potatokid_screen/core/utils/error_message.dart';
import 'package:potatokid_screen/features/iptv/application/bloc/iptv_event.dart';
import 'package:potatokid_screen/features/iptv/application/bloc/iptv_state.dart';
import 'package:potatokid_screen/features/iptv/application/channel_failure_guard.dart';
import 'package:potatokid_screen/features/iptv/application/channel_list_cache.dart';
import 'package:potatokid_screen/features/iptv/data/datasources/local/iptv_source_rules.dart';
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
///
/// 开启「清理失效源」时，展示列表还会剔除已判定的失效地址（见 [_viewOf]）。
class IptvBloc extends Bloc<IptvEvent, IptvState> {
  IptvBloc({required IptvRepository repository})
      : _repository = repository,
        _cache = ChannelListCache.instance,
        super(IptvState.initial()) {
    on<LoadIptv>(_onLoadIptv);
    on<FilterInvalidChannels>(_onFilterInvalidChannels);
    // 「清理失效源」记录到新的失效地址后，立即重算展示列表（移除对应源/频道）。
    ChannelFailureGuard.instance.addListener(_onInvalidSourcesChanged);
  }

  final IptvRepository _repository;
  final ChannelListCache _cache;

  /// 未经「清理失效源」过滤的完整列表，供开关切换时重新计算（关闭时可完整还原）。
  List<IptvChannel> _fullChannels = const <IptvChannel>[];

  void _onInvalidSourcesChanged() => add(const FilterInvalidChannels(true));

  /// 开关切换 / 记录到新失效地址：按 [FilterInvalidChannels.enabled] 重算展示列表。
  Future<void> _onFilterInvalidChannels(
    FilterInvalidChannels event,
    Emitter<IptvState> emit,
  ) async {
    if (_fullChannels.isEmpty) return;
    final List<IptvChannel> view = await _viewOf(_fullChannels, enabled: event.enabled);
    // 整份列表都被清掉时保持现状，避免播放器直接变黑屏。
    if (view.isEmpty) return;
    emit(state.copyWith(channels: view));
  }

  /// 计算展示列表。
  ///
  /// - `remove_source.txt` 里的源**始终**剔除（整行相等，与开关无关）；
  /// - `remove_source_contains.txt` 里的片段命中的源**始终**剔除（包含即命中）；
  /// - 开启「清理失效源」时，再剔除已判定的失效地址，但 `not_remove_source.txt`
  ///   里的源豁免（永不被自动移除）；
  /// - 某频道的源被剔光则整体移除该频道。
  ///
  /// 同时把 [full] 记为完整列表，供之后开关切换时重算。
  Future<List<IptvChannel>> _viewOf(
    List<IptvChannel> full, {
    bool? enabled,
  }) async {
    _fullChannels = full;
    await AppSettings.instance.ensureLoaded();
    final IptvSourceRules rules = IptvSourceRules.instance;
    await rules.ensureLoaded();

    Set<String>? invalid;
    if (enabled ?? AppSettings.instance.removeInvalidSources) {
      final ChannelFailureGuard guard = ChannelFailureGuard.instance;
      await guard.ensureLoaded();
      invalid = guard.invalidUrls;
    }
    return _applySourceRules(
      full,
      removed: rules.removedUrls,
      removedContains: rules.removedContainsPatterns,
      protected: rules.protectedUrls,
      invalid: invalid,
    );
  }

  /// 按规则计算展示列表：剔除 [removed]（整行相等的强制移除）、
  /// [removedContains]（地址包含即命中的强制移除）与 [invalid]（失效黑名单，
  /// 但 [protected] 内的地址豁免）；某频道源被剔光则整体移除。
  ///
  /// 黑名单只记 URL 不记频道名：接口更新后频道若带来新地址，新地址不在黑名单里，
  /// 频道会自动重新出现。
  static List<IptvChannel> _applySourceRules(
    List<IptvChannel> channels, {
    required Set<String> removed,
    required Set<String> removedContains,
    required Set<String> protected,
    Set<String>? invalid,
  }) {
    if (removed.isEmpty &&
        removedContains.isEmpty &&
        (invalid == null || invalid.isEmpty)) {
      return channels;
    }
    final List<IptvChannel> out = <IptvChannel>[];
    for (final IptvChannel c in channels) {
      final List<String> sources = c.sources
          .where((String url) =>
              !removed.contains(url) &&
              !_containsAny(url, removedContains) &&
              !(invalid != null && invalid.contains(url) && !protected.contains(url)))
          .toList(growable: false);
      if (sources.isEmpty) continue;
      out.add(
        sources.length == c.sources.length
            ? c
            : IptvChannel(name: c.name, sources: sources, logo: c.logo, group: c.group),
      );
    }
    return out;
  }

  /// 地址是否包含任意一条片段。
  static bool _containsAny(String url, Set<String> patterns) {
    for (final String pattern in patterns) {
      if (url.contains(pattern)) return true;
    }
    return false;
  }

  Future<void> _onLoadIptv(LoadIptv event, Emitter<IptvState> emit) async {
    // 0) 手动刷新时顺带重新拉取数据文件最新版（频道顺序 / 隐藏频道），
    //    让「刷新频道」同时刷新配置；失败保留原值，不阻断加载。
    if (event.isRefresh) {
      await DataFiles.instance.refresh();
    }

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
        emit(state.copyWith(channels: await _viewOf(cached)));
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
        channels: await _viewOf(await _repository.buildPlaylist(remote)),
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
            channels: await _viewOf(defaults),
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