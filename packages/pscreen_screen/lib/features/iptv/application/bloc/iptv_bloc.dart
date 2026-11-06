import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:pscreen_screen/app/app_log.dart';
import 'package:pscreen_screen/core/di/screen_injection.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';
import 'package:pscreen_screen/core/network/net_exceptions.dart';
import 'package:pscreen_screen/core/parental/parental_config.dart';
import 'package:pscreen_screen/core/parental/parental_state_controller.dart';
import 'package:pscreen_screen/core/utils/app_settings.dart';
import 'package:pscreen_screen/core/utils/bloc_event.dart';
import 'package:pscreen_screen/core/utils/error_message.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_event.dart';
import 'package:pscreen_screen/features/iptv/application/bloc/iptv_state.dart';
import 'package:pscreen_screen/features/iptv/application/channel_failure_guard.dart';
import 'package:pscreen_screen/features/iptv/application/channel_list_cache.dart';
import 'package:pscreen_screen/features/iptv/data/datasources/remote/final_channels_service.dart';
import 'package:pscreen_screen/features/iptv/domain/channel_name_matcher.dart';
import 'package:pscreen_screen/features/iptv/domain/models/final_channels.dart';
import 'package:pscreen_screen/features/iptv/domain/models/iptv_channel.dart';
import 'package:pscreen_screen/features/iptv/domain/repositories/iptv_repository.dart';

/// IPTV 状态机：Event → Bloc → State，加载直播频道列表。
///
/// 数据来源为服务端已合并好的最终列表（`final_channels.json`）：
/// - 有本地缓存：直接起播，同时拿缓存 `version` 做 ETag 比对；服务端返回
///   304 表示没变化，不重新下载；
/// - 无本地缓存（全新安装）：进入加载态等待服务端返回，超时/失败进入错误态；
/// - 拉取失败但本地有缓存：继续播放旧列表，仅置 `usingCachedList` 供页面轻提示；
/// - 版本变化由服务端 `programsUpdatedAt` 通知触发 [LoadIptv.isRefresh]。
///
/// 客户端只保留「清理失效源」与家长模式两层过滤；合并 / 隐藏 / 排序 /
/// 强制移除源都已由服务端完成。
class IptvBloc extends Bloc<IptvEvent, IptvState> {
  IptvBloc({required IptvRepository repository})
      : _repository = repository,
        _cache = ChannelListCache.instance,
        super(IptvState.initial()) {
    on<LoadIptv>(_onLoadIptv);
    on<FilterInvalidChannels>(_onFilterInvalidChannels);
    // 「清理失效源」记录到新的失效地址后，立即重算展示列表（移除对应源/频道）。
    ChannelFailureGuard.instance.addListener(_onInvalidSourcesChanged);
    // 儿童模式配置 / 选人变化：立即重算展示列表（换档案、判定式失效即时反映）。
    ParentalStateController.instance.addListener(_onParentalChanged);
  }

  final IptvRepository _repository;
  final ChannelListCache _cache;

  /// 服务端下发的「强制保留」源（原 `not_remove_source.txt`）。
  Set<String> _protectedSources = <String>{};

  /// 未经「清理失效源」过滤的完整列表，供开关切换时重新计算（关闭时可完整还原）。
  List<IptvChannel> _fullChannels = const <IptvChannel>[];

  void _onInvalidSourcesChanged() => add(const FilterInvalidChannels(true));

  /// 儿童模式配置 / 选中档案变化：不带开关值重算（[_viewOf] 内回落
  /// AppSettings 当前「清理失效源」设置），过滤结果始终叠加儿童模式判定。
  void _onParentalChanged() => add(const FilterInvalidChannels());

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
  /// - 服务端已完成的合并 / 隐藏 / 排序 / 强制移除源不再重复执行；
  /// - 开启「清理失效源」时，剔除已判定的失效地址，但服务端下发的
  ///   `protectedSources` 里的源豁免（永不被自动移除）；
  /// - 某频道的源被剔光则整体移除该频道；
  /// - 最后叠加儿童模式两档过滤（strict 白名单交集 / mild 黑名单并集，
  ///   多档案取最严，见 [applyParentalFilter]）。
  ///
  /// 同时把 [full] 记为完整列表，供之后开关切换时重算。
  Future<List<IptvChannel>> _viewOf(
    List<IptvChannel> full, {
    bool? enabled,
  }) async {
    _fullChannels = full;
    await AppSettings.instance.ensureLoaded();

    Set<String>? invalid;
    if (enabled ?? AppSettings.instance.removeInvalidSources) {
      final ChannelFailureGuard guard = ChannelFailureGuard.instance;
      await guard.ensureLoaded();
      invalid = guard.invalidUrls;
    }
    final List<IptvChannel> ruled = _applyInvalidSources(full, invalid);
    final ParentalStateController parental = ParentalStateController.instance;
    return applyParentalFilter(
      ruled,
      config: parental.config,
      profiles: parental.activeProfiles,
    );
  }

  /// 儿童模式两档过滤（方案 §2.3；多档案合并 = 每个选中档案都放行）：
  /// - strict（加法白名单）：频道须**命中分组且命中频道名**
  ///   （`allowGroups` ∩ `allowChannels`，分组按 [IptvChannel.group] 原文比对，
  ///   频道名走 [ChannelNameMatcher] 精确 + `*` 通配）；
  /// - mild（减法黑名单）：`hideGroups` ∪ `hideChannels` 任一命中即隐藏；
  /// - 空值字段 = 不限制该维度；判定式不成立（未启用 / 未选档案）原样返回；
  /// - **防黑屏**：过滤结果为空 → 不应用 + 日志（方案 L59 保护）。
  ///
  /// 入口在 [_viewOf]（唯一计算点）末尾；保持为纯函数公开，便于直接单测。
  static List<IptvChannel> applyParentalFilter(
    List<IptvChannel> channels, {
    required ParentalConfig config,
    required List<ChildProfile> profiles,
  }) {
    if (!config.enabled || profiles.isEmpty || channels.isEmpty) {
      return channels;
    }
    // 匹配器构建含归一化开销：逐档案预构建一次，循环内只做判定。
    final List<_ParentalRule> rules =
        profiles.map<_ParentalRule>(_ParentalRule.new).toList(growable: false);
    final List<IptvChannel> out = <IptvChannel>[];
    for (final IptvChannel c in channels) {
      if (rules.every((_ParentalRule r) => r.allows(c))) out.add(c);
    }
    if (out.isEmpty) {
      Log.i('[IptvBloc] 儿童模式过滤后无任何频道，本次不应用（防黑屏）');
      return channels;
    }
    return out;
  }

  /// 剔除 [invalid]（失效黑名单），但 [_protectedSources] 内的地址豁免；
  /// 某频道源被剔光则整体移除。
  ///
  /// 黑名单只记 URL 不记频道名：接口更新后频道若带来新地址，新地址不在黑名单里，
  /// 频道会自动重新出现。
  List<IptvChannel> _applyInvalidSources(
    List<IptvChannel> channels,
    Set<String>? invalid,
  ) {
    if (invalid == null || invalid.isEmpty) return channels;
    final List<IptvChannel> out = <IptvChannel>[];
    for (final IptvChannel c in channels) {
      final List<String> sources = c.sources
          .where((String url) =>
              !(invalid.contains(url) && !_protectedSources.contains(url)))
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

  /// 记录服务端下发的强制保留源，并同步给失效源守卫（避免其记入黑名单）。
  void _useProtectedSources(List<String> urls) {
    _protectedSources = urls.toSet();
    ChannelFailureGuard.instance.protectedUrls = _protectedSources;
  }

  Future<void> _onLoadIptv(LoadIptv event, Emitter<IptvState> emit) async {
    final FinalChannelsPayload? cached = await _cache.load();
    final bool hasCache = cached != null && cached.channels.isNotEmpty;
    if (hasCache) _useProtectedSources(cached.protectedSources);

    // 1) 有缓存/正在播放：先让画面可用，版本比对在后台静默完成；
    //    无缓存的首启：进入明确的加载态（页面显示进度与文案）。
    final bool hasCurrent = state.channels.isNotEmpty;
    if (event.useCache && hasCache && !hasCurrent) {
      emit(state.copyWith(
        channels: await _viewOf(cached.channels),
        isLoading: false,
        isRefreshing: false,
        usingCachedList: false,
        clearError: true,
      ));
    } else if (hasCurrent) {
      emit(state.copyWith(
        isLoading: false,
        isRefreshing: true,
        usingCachedList: false,
        clearError: true,
      ));
    } else {
      emit(state.copyWith(
        isLoading: true,
        isRefreshing: false,
        usingCachedList: false,
        clearError: true,
      ));
    }

    try {
      // 2) 带本地版本做条件请求：内容未变时服务端返回 304，不下载列表。
      final FinalChannelsPayload? payload = await _repository
          .fetchFinalChannels(version: cached?.version)
          .timeout(FinalChannelsService.timeout);
      if (payload == null) {
        completeBlocEvent(event.completer, success: true);
        if (state.channels.isEmpty && cached != null) {
          emit(state.copyWith(
            channels: await _viewOf(cached.channels),
            isLoading: false,
            isRefreshing: false,
            usingCachedList: false,
            clearError: true,
          ));
        } else {
          emit(state.copyWith(
            isLoading: false,
            isRefreshing: false,
            usingCachedList: false,
            clearError: true,
          ));
        }
        return;
      }

      _useProtectedSources(payload.protectedSources);
      completeBlocEvent(event.completer, success: true);
      emit(state.copyWith(
        isLoading: false,
        isRefreshing: false,
        channels: await _viewOf(payload.channels),
        usingCachedList: false,
        clearError: true,
      ));
    } catch (e, s) {
      ScreenInjection.get<LogService>().error('加载直播频道失败', error: e, stackTrace: s);
      completeBlocEvent(event.completer, success: false);

      // 3) 有缓存/正在播放：继续用旧列表，页面只做轻提示；
      //    完全没有缓存：错误页 + 重试。
      final bool hasFallback = state.channels.isNotEmpty || hasCache;
      if (hasFallback) {
        if (state.channels.isEmpty && cached != null) {
          emit(state.copyWith(channels: await _viewOf(cached.channels)));
        }
        emit(state.copyWith(
          isLoading: false,
          isRefreshing: false,
          usingCachedList: true,
          clearError: true,
        ));
        return;
      }
      emit(state.copyWith(
        isLoading: false,
        isRefreshing: false,
        errorType: e.toNetErrorType(),
        errorMessage: e is TimeoutException
            ? '获取频道列表超时，请检查网络后重试'
            : mapErrorToMessage(e),
        usingCachedList: false,
      ));
    }
  }
}

/// 单个档案的儿童模式判定规则（[IptvBloc.applyParentalFilter] 逐档案预构建）。
///
/// 频道名匹配复用 [ChannelNameMatcher]（精确 + `*` 通配、不引正则）；
/// 分组按 [IptvChannel.group] 原文整串比对（管理端写什么就是什么）。
class _ParentalRule {
  _ParentalRule(ChildProfile profile)
      : _strict = profile.isStrict,
        _hideGroups = profile.hideGroups.toSet(),
        _hideChannels = ChannelNameMatcher(profile.hideChannels),
        _allowGroups = profile.allowGroups.toSet(),
        _allowChannels = ChannelNameMatcher(profile.allowChannels);

  /// true = strict（加法白名单），false = mild（减法黑名单）。
  final bool _strict;

  final Set<String> _hideGroups;
  final ChannelNameMatcher _hideChannels;
  final Set<String> _allowGroups;
  final ChannelNameMatcher _allowChannels;

  /// 该频道是否被本档案放行（空值字段 = 不限制该维度）。
  bool allows(IptvChannel c) {
    if (_strict) {
      // 加法：命中分组且命中频道名；任一维度配置为空则该维度不限制。
      if (_allowGroups.isNotEmpty &&
          (c.group == null || !_allowGroups.contains(c.group))) {
        return false;
      }
      if (!_allowChannels.isEmpty && !_allowChannels.matches(c.name)) {
        return false;
      }
      return true;
    }
    // 减法：分组黑名单 / 频道名黑名单任一命中即隐藏。
    if (_hideGroups.isNotEmpty &&
        c.group != null &&
        _hideGroups.contains(c.group)) {
      return false;
    }
    if (_hideChannels.matches(c.name)) return false;
    return true;
  }
}