import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// 服务端接口异常（网络 / 业务 code 非 0）。
class ServerApiException implements Exception {
  const ServerApiException(this.message, {this.code = -1});

  final String message;
  final int code;

  @override
  String toString() => message;
}

/// 服务端下发的设备配置。
///
/// [homes] 的三态与后端一致：
/// - `null`：未配置（App 回落 .env 的 HONE_MANE）；
/// - `[]`：不限制（全部家庭）；
/// - 非空：只允许这些家庭。
class ServerDeviceConfig {
  const ServerDeviceConfig({
    required this.homes,
    required this.source,
    required this.owner,
    required this.ownerName,
    required this.layoutKey,
    required this.layoutUpdatedAt,
  });

  final List<String>? homes;
  final String source;
  final String owner;
  final String ownerName;
  final String layoutKey;
  final int layoutUpdatedAt;

  factory ServerDeviceConfig.fromJson(Map<String, dynamic> json) {
    final dynamic rawHomes = json['homes'];
    List<String>? homes;
    if (rawHomes is List) {
      homes = rawHomes
          .whereType<String>()
          .map((String item) => item.trim())
          .where((String item) => item.isNotEmpty)
          .toList(growable: false);
    }
    return ServerDeviceConfig(
      homes: homes,
      source: '${json['source'] ?? 'none'}',
      owner: '${json['owner'] ?? ''}',
      ownerName: '${json['ownerName'] ?? ''}',
      layoutKey: '${json['layoutKey'] ?? ''}',
      layoutUpdatedAt: (json['layoutUpdatedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 服务端保存的首页布局。
class ServerLayout {
  const ServerLayout({
    required this.all,
    required this.byHome,
    required this.updatedAt,
  });

  final List<String> all;
  final Map<String, List<String>> byHome;
  final int updatedAt;

  static const ServerLayout empty = ServerLayout(
    all: <String>[],
    byHome: <String, List<String>>{},
    updatedAt: 0,
  );

  factory ServerLayout.fromJson(Map<String, dynamic> json) {
    final dynamic rawAll = json['all'];
    final List<String> all = rawAll is List
        ? rawAll.whereType<String>().toList(growable: false)
        : const <String>[];
    final Map<String, List<String>> byHome = <String, List<String>>{};
    final dynamic rawByHome = json['byHome'];
    if (rawByHome is Map) {
      rawByHome.forEach((dynamic key, dynamic value) {
        if (key is String && value is List) {
          byHome[key] = value.whereType<String>().toList(growable: false);
        }
      });
    }
    return ServerLayout(
      all: all,
      byHome: byHome,
      updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 管理服务端（与 Admin 页同一个 Node 服务）的轻量 HTTP 客户端。
///
/// 只走 `/api/device/*`，不带管理员凭证；设备身份由 `deviceId` 标识。
class ServerApiClient {
  ServerApiClient({
    required String baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 6),
  }) : _baseUrl = _normalizeBaseUrl(baseUrl),
       _client = client ?? http.Client();

  final String _baseUrl;
  final http.Client _client;
  final Duration timeout;

  bool get isConfigured => _baseUrl.isNotEmpty;

  static String _normalizeBaseUrl(String value) {
    String base = value.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    return base;
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final Uri base = Uri.parse('$_baseUrl$path');
    if (query == null || query.isEmpty) return base;
    return base.replace(queryParameters: <String, String>{
      ...base.queryParameters,
      ...query,
    });
  }

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
  }) async {
    if (_baseUrl.isEmpty) {
      throw const ServerApiException('未配置服务端地址');
    }
    final Uri uri = _uri(path, query);
    final Map<String, String> headers = <String, String>{
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
    };
    final String? payload = body == null ? null : jsonEncode(body);

    http.Response response;
    try {
      switch (method) {
        case 'GET':
          response = await _client.get(uri, headers: headers).timeout(timeout);
          break;
        case 'PUT':
          response = await _client
              .put(uri, headers: headers, body: payload)
              .timeout(timeout);
          break;
        case 'POST':
        default:
          response = await _client
              .post(uri, headers: headers, body: payload)
              .timeout(timeout);
          break;
      }
    } on TimeoutException {
      throw const ServerApiException('服务端请求超时');
    } catch (error) {
      throw ServerApiException('服务端连接失败：$error');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw ServerApiException('服务端返回格式错误 (HTTP ${response.statusCode})');
    }
    if (decoded is! Map) {
      throw const ServerApiException('服务端返回格式错误');
    }
    final int code = (decoded['code'] as num?)?.toInt() ?? -1;
    if (code != 0) {
      throw ServerApiException(
        '${decoded['msg'] ?? '请求失败'}',
        code: code,
      );
    }
    final dynamic data = decoded['data'];
    return data is Map<String, dynamic>
        ? data
        : <String, dynamic>{};
  }

  Future<ServerDeviceConfig> registerDevice({
    required String deviceId,
    required String name,
    required String platform,
    required String model,
    required String appVersion,
    List<String> knownHomes = const <String>[],
    String currentHome = '',
    bool haConnected = false,
  }) async {
    final Map<String, dynamic> data = await _send(
      'POST',
      '/api/device/register',
      body: <String, dynamic>{
        'deviceId': deviceId,
        'name': name,
        'platform': platform,
        'model': model,
        'appVersion': appVersion,
        'knownHomes': knownHomes,
        'currentHome': currentHome,
        'haConnected': haConnected,
      },
    );
    return _configFrom(data);
  }

  Future<ServerDeviceConfig> heartbeat({
    required String deviceId,
    required String appVersion,
    List<String> knownHomes = const <String>[],
    String currentHome = '',
    bool haConnected = false,
  }) async {
    final Map<String, dynamic> data = await _send(
      'POST',
      '/api/device/heartbeat',
      body: <String, dynamic>{
        'deviceId': deviceId,
        'appVersion': appVersion,
        'knownHomes': knownHomes,
        'currentHome': currentHome,
        'haConnected': haConnected,
      },
    );
    return _configFrom(data);
  }

  ServerDeviceConfig _configFrom(Map<String, dynamic> data) {
    final dynamic raw = data['config'];
    final Map<String, dynamic> config = raw is Map<String, dynamic>
        ? raw
        : <String, dynamic>{};
    return ServerDeviceConfig.fromJson(config);
  }

  Future<ServerLayout> fetchLayout(String deviceId) async {
    final Map<String, dynamic> data = await _send(
      'GET',
      '/api/device/layout',
      query: <String, String>{'deviceId': deviceId},
    );
    final dynamic raw = data['layout'];
    return raw is Map<String, dynamic>
        ? ServerLayout.fromJson(raw)
        : ServerLayout.empty;
  }

  /// 上传布局；服务端若已有更新的版本会返回 `conflict: true` 和最新布局。
  Future<({ServerLayout layout, bool conflict})> putLayout({
    required String deviceId,
    required List<String> all,
    required Map<String, List<String>> byHome,
    required int updatedAt,
  }) async {
    final Map<String, dynamic> data = await _send(
      'PUT',
      '/api/device/layout',
      body: <String, dynamic>{
        'deviceId': deviceId,
        'all': all,
        'byHome': byHome,
        'updatedAt': updatedAt,
      },
    );
    final dynamic raw = data['layout'];
    return (
      layout: raw is Map<String, dynamic>
          ? ServerLayout.fromJson(raw)
          : ServerLayout.empty,
      conflict: data['conflict'] == true,
    );
  }

  void dispose() => _client.close();
}
