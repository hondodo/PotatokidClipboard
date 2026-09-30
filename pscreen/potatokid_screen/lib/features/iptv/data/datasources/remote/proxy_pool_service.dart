import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:potatokid_screen/core/di/injection.dart';
import 'package:potatokid_screen/core/logging/log_service.dart';
import 'package:potatokid_screen/core/network/dio_pretty_logger.dart';

/// 免费代理池（`proxy.scdn.io`）访问服务（全局单例）。
///
/// 用途：某些直播源在本机网络下打不开（连接超时/被拒/卡死），换网络或走代理就能用。
/// 「代理重试」开启时，直连失败的源会改用这里取到的 HTTP 代理重新打开。
///
/// 使用站点官方 JSON 接口：
/// `GET /api/get_proxy.php?protocol=http&count=N`
/// → `{"code":200,"data":{"proxies":["1.2.3.4:8080", ...],"count":N}}`。
/// 每次调用返回一批（可能是不同的）代理，因此列表用完就再拉一批；
/// 同一批内按顺序轮换使用。
class ProxyPoolService {
  ProxyPoolService._();

  /// 全局单例。
  static final ProxyPoolService instance = ProxyPoolService._();

  /// 官方接口（返回 JSON，`data.proxies` 为 `ip:port` 列表）。
  static const String endpoint = 'https://proxy.scdn.io/api/get_proxy.php';

  /// 单次请求超时。
  static const Duration _timeout = Duration(seconds: 10);

  /// 列表缓存时长：到期后重新拉取（正常情况下列表用完即拉新）。
  static const Duration _cacheTtl = Duration(minutes: 20);

  /// 每次拉取多少个（接口上限 20）。
  static const int _count = 20;

  /// 单个代理的探测超时。
  static const Duration _probeTimeout = Duration(seconds: 5);

  /// 拉取代理列表用的 Dio（拦截器只挂一次）。
  final Dio _dio = Dio(BaseOptions(connectTimeout: _timeout, receiveTimeout: _timeout, validateStatus: (_) => true))
    ..interceptors.add(DioLogInterceptor());

  List<String> _cache = <String>[];
  DateTime _fetchedAt = DateTime.fromMillisecondsSinceEpoch(0);
  int _cursor = 0;
  bool _fetching = false;

  /// 取下一个可用代理（形如 `http://1.2.3.4:80`）；拿不到返回 null。
  Future<String?> nextProxy() async {
    // 列表用完或过期 → 再拉一批。
    if (_cursor >= _cache.length || DateTime.now().difference(_fetchedAt) > _cacheTtl) {
      await _refresh();
    }
    if (_cache.isEmpty) return null;
    return _cache[_cursor++ % _cache.length];
  }

  /// 拉取一批代理；失败时保留旧列表（旧列表仍可轮换使用）。
  Future<void> _refresh() async {
    if (_fetching) return;
    _fetching = true;
    // 无论成败都记时间，避免失败时被高频重试。
    _fetchedAt = DateTime.now();
    try {
      final Response<dynamic> res = await _dio.get<dynamic>(
        endpoint,
        queryParameters: <String, dynamic>{'protocol': 'http', 'count': _count},
      );
      final List<String> proxies = _parseBody(res.data);
      if (proxies.isEmpty) {
        final String body = res.data?.toString() ?? '';
        final String head = body.length > 200 ? '${body.substring(0, 200)}…' : body;
        Injection.get<LogService>().warn('[ProxyPoolService] 代理列表为空(status=${res.statusCode})，响应: $head');
        return;
      }
      _cache = proxies;
      _cursor = 0;
      Injection.get<LogService>().info('[ProxyPoolService] 已获取 ${proxies.length} 个 HTTP 代理');
    } catch (e) {
      Injection.get<LogService>().warn('[ProxyPoolService] 获取代理列表失败: $e');
    } finally {
      _fetching = false;
    }
  }

  /// 依次取代理并探测目标地址，返回第一个**探测通过**的代理；都不行返回 null。
  ///
  /// [targetUrl] 传要播放的源地址，这样探测结果直接说明「这个代理能不能拿到这个源」。
  Future<String?> nextUsableProxy({required String targetUrl, int maxTries = 3}) async {
    for (int i = 0; i < maxTries; i++) {
      final String? proxy = await nextProxy();
      if (proxy == null) return null;
      if (await probeThrough(proxy, targetUrl)) return proxy;
    }
    return null;
  }

  /// 通过指定代理访问目标地址，判断该代理对**这个源**是否真的可用。
  ///
  /// 可用判定（只看响应头，不读 body，省流量）：
  /// - 拿到 2xx/3xx 响应头，且 `Content-Type` 不是 `text/html`
  ///   （HTML 说明代理返回的是自己的错误页，正是 mpv 报
  ///   `Failed to recognize file format` 的来源）；
  /// - 连接失败 / 超时 / 4xx / 5xx 都算不可用。
  Future<bool> probeThrough(String proxy, String targetUrl) async {
    final Uri uri = Uri.parse(proxy);
    final Dio dio =
        Dio(BaseOptions(connectTimeout: _probeTimeout, receiveTimeout: _probeTimeout, validateStatus: (_) => true))
          ..httpClientAdapter = IOHttpClientAdapter(
            createHttpClient: () {
              final HttpClient client = HttpClient();
              client.connectionTimeout = _probeTimeout;
              client.findProxy = (Uri target) => 'PROXY ${uri.host}:${uri.port}';
              return client;
            },
          );
    final CancelToken token = CancelToken();
    try {
      final Response<dynamic> res = await dio.get<dynamic>(
        targetUrl,
        cancelToken: token,
        // 只要响应头：拿到头即说明代理转发成功，随后立刻中断 body。
        options: Options(responseType: ResponseType.stream),
      );
      final int status = res.statusCode ?? 0;
      final String contentType = res.headers.value('content-type')?.toLowerCase() ?? '';
      final bool html = contentType.contains('text/html');
      final bool ok = status >= 200 && status < 400 && !html;
      Injection.get<LogService>().info(
        '[ProxyPoolService] 探测 $proxy → 状态=$status '
        '类型=${contentType.isEmpty ? '-' : contentType} 可用=$ok',
      );
      return ok;
    } catch (e) {
      Injection.get<LogService>().info('[ProxyPoolService] 探测 $proxy 连接失败: $e');
      return false;
    } finally {
      token.cancel('probe done');
      dio.close(force: true);
    }
  }

  /// 解析接口响应，得到 `http://ip:port` 列表。
  static List<String> _parseBody(dynamic data) {
    dynamic decoded = data;
    if (decoded is String) {
      try {
        decoded = jsonDecode(decoded);
      } catch (_) {
        return const <String>[];
      }
    }
    if (decoded is! Map) return const <String>[];
    final dynamic inner = decoded['data'];
    if (inner is! Map) return const <String>[];
    final dynamic proxies = inner['proxies'];
    if (proxies is! List) return const <String>[];

    final List<String> out = <String>[];
    final Set<String> seen = <String>{};
    for (final dynamic item in proxies) {
      if (item is! String) continue;
      final String raw = item.trim();
      final int sep = raw.lastIndexOf(':');
      if (sep <= 0) continue;
      final String ip = raw.substring(0, sep).trim();
      final int? port = int.tryParse(raw.substring(sep + 1).trim());
      if (ip.isEmpty || port == null || port <= 0 || port > 65535) continue;
      // mpv 的 http-proxy 只支持 HTTP 代理。
      final String url = 'http://$ip:$port';
      if (seen.add(url)) out.add(url);
    }
    // out.clear();
    // out.addAll(['SOCKS4://43.199.29.225:31806', 'SOCKS4://18.163.182.106:42428']);
    return out;
  }
}
