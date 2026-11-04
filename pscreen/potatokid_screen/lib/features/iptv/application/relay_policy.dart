import 'dart:async';
import 'dart:convert';

import 'package:pscreen_screen/app/config/app_constants.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';
import 'package:pscreen_screen/core/network/dio_manager.dart';
import 'package:pscreen_screen/core/network/http_method.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 中转策略：服务端 `/api/allow_reply_host` 下发「走 relay（reply）中转的源域名
/// 白名单」，命中（精确或子域）的源才改写成 relay 地址，未命中的直连播放，
/// 不再全部走转发。
///
/// 取数顺序：
/// 1. 进程内存（同一次运行内命中后不再请求）
/// 2. 本地缓存（上次成功拉取的结果，启动即刻可用，不阻塞首播）
/// 3. 兜底名单（与 relay 的 ACCEPT_HOST 默认值一致）
///
/// 首次加载后**后台**向服务端刷新一次，成功则更新内存与本地缓存
/// （下一次切台即生效）；失败静默保留旧名单，不影响播放。
class RelayPolicy {
  RelayPolicy._();

  static final RelayPolicy instance = RelayPolicy._();

  static const String _cacheKey = 'relay_allow_hosts_v1';

  /// 服务端不可达且无缓存时的兜底名单，与 relay 的 ACCEPT_HOST 保持一致。
  static const List<String> _fallback = <String>['jdshipin.com'];

  List<String>? _hosts;
  bool _refreshing = false;

  /// 源地址是否应经 relay 中转；false = 直连播放。
  Future<bool> shouldRelay(String source) async {
    final String host = _hostOf(source);
    if (host.isEmpty) return false;
    final String h = host.toLowerCase().replaceAll(RegExp(r'\.$'), '');
    final List<String> hosts = await _ensureLoaded();
    return hosts.any((String raw) {
      final String d = raw.trim().toLowerCase();
      return d.isNotEmpty && (h == d || h.endsWith('.$d'));
    });
  }

  Future<List<String>> _ensureLoaded() async {
    final List<String>? have = _hosts;
    if (have != null) return have;
    List<String> start = _fallback;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> cached = _decodeCached(prefs.getString(_cacheKey));
      if (cached.isNotEmpty) start = cached;
    } catch (_) {
      // 本地缓存不可用时退回兜底名单
    }
    _hosts = start;
    _refresh();
    return start;
  }

  /// 后台拉取服务端最新白名单；成功则更新内存与本地缓存。
  void _refresh() {
    if (_refreshing) return;
    _refreshing = true;
    () async {
      try {
        final dynamic data = await DioManager().send(
          url: '${AppConstants.toolsBaseUrl}/api/allow_reply_host',
          method: HttpMethod.GET,
          maxRetry: 0, // 兜底刷新，失败静默，不重试不弹错
          notTipNetError: true,
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        );
        final List<String> hosts = _parseHosts(data);
        if (hosts.isNotEmpty) {
          _hosts = hosts;
          try {
            final SharedPreferences prefs = await SharedPreferences.getInstance();
            await prefs.setString(_cacheKey, jsonEncode(hosts));
          } catch (_) {}
          const LogService().info('中转白名单已刷新: $hosts');
        }
      } catch (e) {
        const LogService().warn('中转白名单刷新失败: $e');
      } finally {
        _refreshing = false;
      }
    }();
  }

  /// 解析接口响应 `{code, msg, data: {allow_reply_host: [...]}}`；不合规返回空表。
  static List<String> _parseHosts(dynamic data) {
    if (data is! Map) return const <String>[];
    if (data['code'] != 0) return const <String>[];
    final dynamic body = data['data'];
    if (body is! Map) return const <String>[];
    return _decodeHosts(body['allow_reply_host']);
  }

  static List<String> _decodeHosts(dynamic raw) {
    if (raw is! List) return const <String>[];
    return raw
        .whereType<String>()
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList();
  }

  /// 解析本地缓存（jsonEncode 后的字符串）；空值或损坏返回空表。
  static List<String> _decodeCached(String? raw) {
    if (raw == null || raw.isEmpty) return const <String>[];
    try {
      return _decodeHosts(jsonDecode(raw));
    } catch (_) {
      return const <String>[];
    }
  }

  static String _hostOf(String url) {
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return '';
    }
  }
}
