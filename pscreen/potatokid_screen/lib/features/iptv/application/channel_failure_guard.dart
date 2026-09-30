import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:potatokid_screen/app/hosts/app_hosts.dart';
import 'package:potatokid_screen/core/di/injection.dart';
import 'package:potatokid_screen/core/logging/log_service.dart';
import 'package:potatokid_screen/features/iptv/data/datasources/local/iptv_source_rules.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 「清理失效源」的判定、确认与持久化（全局单例）。
///
/// 判定流程（仅在开关开启时统计）：
/// 1. 同一频道**连续** [failureThreshold] 次播放失败，且失败原因都是
///    `Failed to open`（media_kit 的 open 失败）；
/// 2. 这一轮失败已覆盖该频道的**全部源**（说明整个频道都打不开）；
/// 3. 进入**确认**环节：逐个探测这些地址，只把能确定失效的记入黑名单。
///
/// 为什么要第 3 步：地址真失效与网络临时不通都会报 `Failed to open`，
/// 直接记录会在网络抖动时把好地址误删。确认时以「能否拿到 HTTP 响应」区分：
/// 拿不到响应一律视为不确定，宁可不记（见 [_confirmInvalid]）。
///
/// 只记 **URL** 不记频道名：接口更新后若频道带来新地址，新地址不在黑名单里，
/// 频道会自动重新显示；旧地址仍被剔除。
///
/// `assets/datas/not_remove_source.txt` 里的源强制保留，永不记入黑名单
/// （`remove_source.txt` 的强制移除由 [IptvBloc] 统一处理）。
///
/// 数据为 JSON 字符串数组，键 `iptv_invalid_sources_v1`；读写失败都不阻断播放。
class ChannelFailureGuard extends ChangeNotifier {
  ChannelFailureGuard._();

  /// 全局单例。
  static final ChannelFailureGuard instance = ChannelFailureGuard._();

  static const String _key = 'iptv_invalid_sources_v1';

  /// 判定失效所需的「同一频道连续 open 失败」次数。
  static const int failureThreshold = 5;

  /// media_kit open 失败的原因关键字。
  static const String _openFailedMarker = 'Failed to open';

  /// 单个地址的探测超时。
  static const Duration _probeTimeout = Duration(seconds: 6);

  /// DNS 相关判定的参照地址：任一能拿到 HTTP 响应即认为「本机网络与 DNS 正常」，
  /// 用于区分「域名真的不存在」与「本机网络/DNS 出了问题」。
  static List<String> get _referenceUrls => <String>[
    AppHosts.ipGeoPrimaryHost,
    AppHosts.weatherHost,
  ];

  final Set<String> _invalidUrls = <String>{};
  bool _loaded = false;

  /// 本轮连续失败统计（同一频道 + 明确 open 失败 + 覆盖全部源）。
  String? _pendingName;
  int _pendingCount = 0;
  final Set<String> _pendingUrls = <String>{};

  /// 已判定的失效地址（只读）。
  Set<String> get invalidUrls => _invalidUrls;

  /// 该地址是否已被判定为失效。
  bool isInvalid(String url) => _invalidUrls.contains(url);

  /// 加载持久化的失效地址（仅首次真正读取）。
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_key);
      if (raw == null || raw.isEmpty) return;
      final dynamic decoded = jsonDecode(raw);
      if (decoded is List) {
        _invalidUrls.addAll(decoded.whereType<String>());
      }
    } catch (_) {
      // 解析失败视为无记录。
    }
  }

  /// 记录一次播放失败（同步返回，不阻塞播放回退）。
  ///
  /// 只有「同一频道 + `Failed to open` + 覆盖该频道全部源」的连续失败达到
  /// [failureThreshold] 次时，才异步进入确认流程；确认通过后写入黑名单并
  /// 通知监听者（[IptvBloc]）重新过滤频道列表。
  void recordFailure({
    required String channelName,
    required String sourceUrl,
    required String reason,
    required List<String> channelSources,
  }) {
    // 非「明确失效」的失败（超时/黑屏/completed 等）视为不确定，重新起算。
    if (!reason.contains(_openFailedMarker)) {
      _resetPending();
      return;
    }
    if (_pendingName != channelName) {
      _pendingName = channelName;
      _pendingCount = 0;
      _pendingUrls.clear();
    }
    _pendingCount++;
    if (sourceUrl.isNotEmpty) _pendingUrls.add(sourceUrl);
    if (_pendingCount < failureThreshold) return;
    // 本轮失败必须覆盖该频道的全部源，避免「只坏了一个源」就动整个频道。
    if (channelSources.isEmpty || !_pendingUrls.containsAll(channelSources)) return;

    final List<String> candidates = _pendingUrls.toList(growable: false);
    _resetPending();
    unawaited(_confirmAndRecord(channelName, candidates));
  }

  /// 播放成功（出画面）：该频道本轮连续失败清零。
  void recordSuccess(String channelName) {
    if (_pendingName == channelName) _resetPending();
  }

  void _resetPending() {
    _pendingName = null;
    _pendingCount = 0;
    _pendingUrls.clear();
  }

  /// 确认并记录失效地址。
  Future<void> _confirmAndRecord(String channelName, List<String> candidates) async {
    List<String> confirmed;
    try {
      confirmed = await _confirmInvalid(candidates);
      // `not_remove_source.txt` 里的源强制保留：永不记入黑名单。
      final IptvSourceRules rules = IptvSourceRules.instance;
      await rules.ensureLoaded();
      if (rules.protectedUrls.isNotEmpty) {
        confirmed = confirmed
            .where((String url) => !rules.protectedUrls.contains(url))
            .toList(growable: false);
      }
    } catch (_) {
      return;
    }
    if (confirmed.isEmpty) {
      Injection.get<LogService>().info(
        '[ChannelFailureGuard] 频道$channelName 候选地址经确认未判定失效(疑似网络原因)，已忽略',
      );
      return;
    }
    await ensureLoaded();
    final int before = _invalidUrls.length;
    _invalidUrls.addAll(confirmed);
    if (_invalidUrls.length == before) return;
    await _persist();
    Injection.get<LogService>().info(
      '[ChannelFailureGuard] 频道$channelName 已记录 ${confirmed.length} 个失效地址',
    );
    notifyListeners();
  }

  /// 逐个探测候选地址，返回**可确定失效**的地址。
  ///
  /// 判定规则：
  /// - 拿到 HTTP 响应：4xx → 地址失效（记录）；2xx/3xx → 地址可用（不记录）；
  ///   5xx → 服务端临时故障（不确定，不记录）。
  /// - DNS 解析失败：再探测参照地址，参照通 → 域名确实不存在（记录）；
  ///   参照也不通 → 本机网络/DNS 问题（不记录）。
  /// - 其它网络错误（超时/连接被拒等）→ 不确定，不记录。
  Future<List<String>> _confirmInvalid(List<String> candidates) async {
    final Dio dio = Dio(
      BaseOptions(
        connectTimeout: _probeTimeout,
        receiveTimeout: _probeTimeout,
        sendTimeout: _probeTimeout,
        responseType: ResponseType.bytes,
        validateStatus: (_) => true,
      ),
    );
    final List<String> confirmed = <String>[];
    // 参照地址是否可达：仅在出现 DNS 失败时才探测一次，结果复用。
    bool? referenceOk;
    try {
      for (final String url in candidates) {
        final _ProbeOutcome outcome = await _probe(dio, url);
        final int? status = outcome.statusCode;
        if (status != null) {
          if (status >= 400 && status < 500) confirmed.add(url);
          continue;
        }
        if (outcome.hostNotFound) {
          referenceOk ??= await _referenceReachable(dio);
          if (referenceOk) confirmed.add(url);
        }
      }
    } finally {
      dio.close(force: true);
    }
    return confirmed;
  }

  /// 探测参照地址：任一拿到 HTTP 响应即认为本机网络与 DNS 正常。
  Future<bool> _referenceReachable(Dio dio) async {
    for (final String url in _referenceUrls) {
      if (url.isEmpty) continue;
      if ((await _probe(dio, url)).statusCode != null) return true;
    }
    return false;
  }

  /// 单次探测：拿到响应返回状态码；DNS 失败标记 [hostNotFound]；其余视为不确定。
  Future<_ProbeOutcome> _probe(Dio dio, String url) async {
    final CancelToken token = CancelToken();
    try {
      final Response<dynamic> res = await dio
          .get<dynamic>(url, cancelToken: token)
          .timeout(
            _probeTimeout,
            onTimeout: () {
              token.cancel('probe timeout');
              throw TimeoutException('probe timeout');
            },
          );
      return _ProbeOutcome(statusCode: res.statusCode);
    } on DioException catch (e) {
      final Object? error = e.error;
      if (error is SocketException && error.message.toLowerCase().contains('host lookup')) {
        return const _ProbeOutcome(hostNotFound: true);
      }
      return const _ProbeOutcome();
    } catch (_) {
      return const _ProbeOutcome();
    }
  }

  Future<void> _persist() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(_invalidUrls.toList(growable: false)));
    } catch (_) {
      // 写入失败不阻断播放。
    }
  }
}

/// 单个地址的探测结果。
class _ProbeOutcome {
  const _ProbeOutcome({this.statusCode, this.hostNotFound = false});

  /// 非空表示拿到了 HTTP 响应（传输层可达）。
  final int? statusCode;

  /// DNS 解析失败（域名不存在，或本机 DNS 不可用，需再对照参照地址判断）。
  final bool hostNotFound;
}