import 'dart:async';
import 'dart:convert';

import 'package:pscreen_screen/app/config/app_constants.dart';
import 'package:pscreen_screen/core/logging/log_service.dart';
import 'package:pscreen_screen/core/network/dio_manager.dart';
import 'package:pscreen_screen/core/network/http_method.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 中转策略：服务端 `/api/allow_reply_host` 下发「走 relay（reply）中转的源域名
/// 白名单」，命中（精确或子域）的源才改写成 relay 地址，未命中的直连播放。
///
/// 取数顺序：
/// 1. 进程内存（同一次运行内命中后不再请求）
/// 2. 本地缓存（上次成功拉取的结果，空表也会缓存；启动即刻可用，不阻塞首播）
/// 3. 都没有时按空表处理 = 全部直连，不再写死兜底域名
///
/// 空表 = 全部直连；裸 `*` 不是有效域名，一律忽略，不会因此变成全部走 relay。
/// 管理端保存白名单后，在线设备会通过节目版本钩子调用 [refreshNow] 强制重拉。
///
/// 电视端与中控端共用；中转前缀由各自 `.env` 的 `REPLY_SOURCE` 提供
/// （[AppConfig.relaySource]）。
class RelayPolicy {
  RelayPolicy._();

  static final RelayPolicy instance = RelayPolicy._();

  static const String _cacheKey = 'relay_allow_hosts_v1';

  List<String>? _hosts;
  Future<void>? _inflight;
  bool _pending = false;

  /// 源地址是否应经 relay 中转；false = 直连播放。
  Future<bool> shouldRelay(String source) async {
    final String host = _hostOf(source);
    if (host.isEmpty) return false;
    final String h = host.toLowerCase().replaceAll(RegExp(r'\.$'), '');
    final List<String> hosts = await _ensureLoaded();
    return hosts.any((String raw) {
      final String d = raw.trim().toLowerCase();
      return d.isNotEmpty && d != '*' && (h == d || h.endsWith('.$d'));
    });
  }

  Future<List<String>> _ensureLoaded() async {
    final List<String>? have = _hosts;
    if (have != null) return have;
    List<String> start = const <String>[];
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String>? cached = _decodeCached(prefs.getString(_cacheKey));
      if (cached != null) start = cached;
    } catch (_) {
      // 本地缓存不可用时按空表处理（全部直连）
    }
    _hosts = start;
    unawaited(refreshNow());
    return start;
  }

  /// 强制拉取服务端最新白名单；成功则更新内存与本地缓存（空表也会覆盖缓存）。
  /// 失败静默保留上次成功值，不影响播放。
  Future<void> refreshNow() async {
    final Future<void>? running = _inflight;
    if (running != null) {
      // 已有请求在途：标记一次补拉，等它结束后再强制刷新，避免漏掉保存后的新名单。
      _pending = true;
      await running;
      return;
    }
    final Future<void> job = _doRefresh();
    _inflight = job;
    try {
      await job;
    } finally {
      _inflight = null;
    }
    if (_pending) {
      _pending = false;
      unawaited(refreshNow());
    }
  }

  Future<void> _doRefresh() async {
    try {
      final dynamic data = await DioManager().send(
        url: '${AppConstants.toolsBaseUrl}/api/allow_reply_host',
        method: HttpMethod.GET,
        maxRetry: 0, // 兜底刷新，失败静默，不重试不弹错
        notTipNetError: true,
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      );
      final List<String>? hosts = _parseHosts(data);
      if (hosts != null) {
        _hosts = hosts;
        try {
          final SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setString(_cacheKey, jsonEncode(hosts));
        } catch (_) {}
        const LogService().info('中转白名单已刷新: $hosts');
      }
    } catch (e) {
      const LogService().warn('中转白名单刷新失败: $e');
    }
  }

  /// 解析接口响应 `{code, msg, data: {allow_reply_host: [...]}}`。
  /// 结构不合法返回 null（保留上次成功值）；合法空表返回空列表（全部直连）。
  static List<String>? _parseHosts(dynamic data) {
    if (data is! Map) return null;
    if (data['code'] != 0) return null;
    final dynamic body = data['data'];
    if (body is! Map) return null;
    final dynamic raw = body['allow_reply_host'];
    if (raw is! List) return null;
    return _decodeHosts(raw);
  }

  static List<String> _decodeHosts(dynamic raw) {
    if (raw is! List) return const <String>[];
    return raw
        .whereType<String>()
        .map((String s) => s.trim().toLowerCase())
        .map((String s) => s.startsWith('*.') ? s.substring(2) : s)
        .where((String s) => s.isNotEmpty && s != '*')
        .toList();
  }

  /// 解析本地缓存（jsonEncode 后的字符串）；无缓存或损坏返回 null。
  static List<String>? _decodeCached(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final dynamic decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return _decodeHosts(decoded);
    } catch (_) {
      return null;
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
