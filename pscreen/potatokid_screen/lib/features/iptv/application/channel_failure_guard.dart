import 'dart:async';
import 'dart:convert';

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
/// 1. 同一频道**连续** [failureThreshold] 次播放失败，且失败原因都属于
///    「地址打不开」类（见 [_unreachableMarkers]，如 `Failed to open`、
///    `Connection timed out`）；
/// 2. 这一轮失败已覆盖该频道的**全部源**（说明整个频道都打不开）；
/// 3. 进入**确认**环节：逐个探测这些地址，只把能确定失效的记入黑名单。
///
/// 为什么要第 3 步：地址真失效与网络临时不通都会报 `Failed to open`，
/// 直接记录会在网络抖动时把好地址误删。确认时逐个探测地址，并对「连接层失败」
/// 用参照地址复核本机网络；只有本机网络正常、目标地址确实不通/返回 4xx 才记录
/// （见 [_confirmInvalid]）。
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

  /// 视为「地址打不开」的失败原因关键字（小写匹配）。
  ///
  /// mpv 在不同场景下的报法不同：域名/无法打开时是 `Failed to open <url>.`，
  /// 服务器不通时是 `tcp: Connection to tcp://host:port failed: Connection timed out`
  /// 之类，这里一并纳入。
  static const List<String> _unreachableMarkers = <String>[
    'failed to open',
    'connection timed out',
    'connection refused',
    'network is unreachable',
    'no route to host',
    'could not resolve',
    'failed to resolve',
  ];

  /// 单个地址的探测超时。
  static const Duration _probeTimeout = Duration(seconds: 6);

  /// DNS 相关判定的参照地址：任一能拿到 HTTP 响应即认为「本机网络与 DNS 正常」，
  /// 用于区分「地址真的不通」与「本机网络/DNS 出了问题」。
  /// 三个都是本应用本来就会访问的第三方域名，尽量保证其中至少一个可用；
  /// 顺序按可达性优先，避免前面的域名不通时白等超时。
  static List<String> get _referenceUrls => <String>[
    AppHosts.weatherHost,
    AppHosts.ipGeoPrimaryHost,
    AppHosts.ipGeoSecondaryHost,
  ];

  final Set<String> _invalidUrls = <String>{};
  bool _loaded = false;

  /// 是否有一轮确认正在进行（避免同时发起多轮探测）。
  bool _confirming = false;

  /// 本轮连续失败统计（同一频道 + 明确 open 失败 + 覆盖全部源）。
  String? _pendingName;
  int _pendingCount = 0;
  final Set<String> _pendingUrls = <String>{};

  /// 每个频道最近一次「播放成功」的计数，用于确认流程复核（见 [recordSuccess]）。
  final Map<String, int> _successTicks = <String, int>{};
  int _tick = 0;

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
    // 非「地址打不开」类失败（黑屏/缓冲卡死/completed 等）视为不确定，重新起算。
    if (!_isUnreachableReason(reason)) {
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
  ///
  /// 同时记录「成功计数」，供确认流程复核：探测期间若该频道又播成功过
  /// （例如换代理后能播），就不再把它的地址记为失效。
  void recordSuccess(String channelName) {
    if (_pendingName == channelName) _resetPending();
    _successTicks[channelName] = ++_tick;
  }

  /// 失败原因是否属于「地址打不开」类（media_kit/mpv 的 open 失败、连接超时、
  /// 连接被拒、网络不可达、DNS 解析失败）。
  ///
  /// 只有这类原因才计入「清理失效源」统计；黑屏、持续缓冲卡死、播放结束等
  /// 属于不确定原因，不计入（且会清零本轮统计）。
  static bool _isUnreachableReason(String reason) {
    final String lower = reason.toLowerCase();
    for (final String marker in _unreachableMarkers) {
      if (lower.contains(marker)) return true;
    }
    return false;
  }

  void _resetPending() {
    _pendingName = null;
    _pendingCount = 0;
    _pendingUrls.clear();
  }

  /// 确认并记录失效地址。
  ///
  /// 同一时刻只允许一轮确认（探测可能较慢），避免卡在同一频道时反复发起探测。
  Future<void> _confirmAndRecord(String channelName, List<String> candidates) async {
    if (_confirming) return;
    _confirming = true;
    final int startTick = _successTicks[channelName] ?? 0;
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
      _confirming = false;
      return;
    }
    _confirming = false;
    // 探测期间该频道又播成功过（例如换代理后能播）→ 说明地址并非真失效，放弃记录。
    if ((_successTicks[channelName] ?? 0) != startTick) {
      Injection.get<LogService>().info(
        '[ChannelFailureGuard] 频道$channelName 在确认期间已恢复播放，取消记录失效地址',
      );
      return;
    }
    if (confirmed.isEmpty) {
      Injection.get<LogService>().info(
        '[ChannelFailureGuard] 频道$channelName 候选地址经确认未判定失效，已忽略',
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
  /// 判定规则（核心是区分「地址真的不通」与「本机网络有问题」）：
  /// - 拿到 HTTP 响应：4xx → 地址失效（记录）；2xx/3xx → 地址可用（不记录）；
  ///   5xx → 服务端临时故障（不确定，不记录）。
  /// - **连接层失败**（DNS 解析失败 / 连接被拒 / TLS 握手失败 / 超时 / 网络不可达）
  ///   → 先探测参照地址确认本机网络与 DNS 正常：参照通 → 该地址确实不通（记录）；
  ///   参照也不通 → 本机网络问题（不记录）。
  /// - 其它异常（非网络类，如地址/参数/解析错误）→ 不确定，不记录。
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
    final LogService log = Injection.get<LogService>();
    final List<String> confirmed = <String>[];
    // 参照地址是否可达：仅在出现连接层失败时才探测一次，结果复用。
    bool? referenceOk;
    try {
      // 并行探测：多源时逐个等待会累加超时（每个最长 6s），并行可显著缩短。
      final List<_ProbeOutcome> outcomes =
          await Future.wait(candidates.map((String url) => _probe(dio, url)));
      for (int i = 0; i < candidates.length; i++) {
        final String url = candidates[i];
        final _ProbeOutcome outcome = outcomes[i];
        final int? status = outcome.statusCode;
        if (status != null) {
          log.info('[ChannelFailureGuard] 探测 $url → HTTP $status');
          if (status >= 400 && status < 500) confirmed.add(url);
          continue;
        }
        if (!outcome.connectionFailed) {
          log.info('[ChannelFailureGuard] 探测 $url → 不确定(${outcome.detail})，跳过');
          continue;
        }
        referenceOk ??= await _referenceReachable(dio);
        log.info(
          '[ChannelFailureGuard] 探测 $url → 连接失败(${outcome.detail})，'
          '参照地址可达=$referenceOk',
        );
        if (referenceOk) confirmed.add(url);
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

  /// 单次探测：拿到响应返回状态码；连接层失败标记 [connectionFailed]。
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
      // 主动取消 / 响应层错误都不是网络不通，不做「失效」判定。
      if (e.type == DioExceptionType.cancel) {
        return const _ProbeOutcome(detail: 'cancel');
      }
      if (e.type == DioExceptionType.badResponse) {
        return _ProbeOutcome(statusCode: e.response?.statusCode, detail: 'badResponse');
      }
      final Object? error = e.error;
      // 明显的非网络类异常（地址/参数/解析问题等）不参与失效判定。
      if (error is FormatException ||
          error is ArgumentError ||
          error is StateError ||
          error is TypeError) {
        return _ProbeOutcome(detail: 'unknown: ${error.runtimeType}: $error');
      }
      // 其余异常（SocketException / HttpException / HandshakeException / 证书错误 /
      // 超时 / unknown 包装的网络异常等）都算连接层失败，交由参照地址复核。
      return _ProbeOutcome(
        connectionFailed: true,
        detail: '${e.type.name}: ${e.message ?? ''}'
            '${error == null ? '' : ' / ${error.runtimeType}: $error'}',
      );
    } on TimeoutException catch (e) {
      return _ProbeOutcome(connectionFailed: true, detail: 'timeout: ${e.message}');
    } catch (e) {
      // 非网络类异常（参数/解析等）：不确定，不记录。
      return _ProbeOutcome(detail: 'unexpected: $e');
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
  const _ProbeOutcome({this.statusCode, this.connectionFailed = false, this.detail = ''});

  /// 非空表示拿到了 HTTP 响应（传输层可达）。
  final int? statusCode;

  /// 连接层失败（DNS 解析失败 / 连接被拒 / 超时 / 网络不可达），
  /// 需结合参照地址判断是否为本机网络问题。
  final bool connectionFailed;

  /// 供日志排查的简要描述。
  final String detail;
}