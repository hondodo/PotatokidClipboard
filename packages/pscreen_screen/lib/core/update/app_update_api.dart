import 'package:dio/dio.dart';
import 'package:pscreen_screen/core/update/app_update_models.dart';

/// 更新查询失败（本地代理返回 `100100/100101/400002` 或网络不可达）。
///
/// 调用方按 `failMode=open` 处理：只记录日志，放行进入主页。
class AppUpdateException implements Exception {
  const AppUpdateException(this.code, this.message);

  /// 业务码：本地代理/上游的 `{code}`；网络异常时为 -1。
  final int code;
  final String message;

  bool get notConfigured => code == 100100;
  bool get upstreamUnavailable => code == 100101;
  bool get rateLimited => code == 400002;

  @override
  String toString() => 'AppUpdateException($code, $message)';
}

/// 查询本地 `pscreen_server` 的更新代理（App 不直接访问 yuntu）。
///
/// - 只查元数据，下载地址由服务端返回（客户端直连 yuntu 签名链接）。
/// - 不复用 DioManager：需要 3~5s 短超时、不挂 Cookie/重试拦截器，
///   且失败必须快速返回，避免拖慢启动。
class AppUpdateApi {
  AppUpdateApi({
    required String baseUrl,
    Dio? dio,
    Duration timeout = const Duration(seconds: 5),
  })  : _baseUrl = _normalizeBaseUrl(baseUrl),
        _dio = dio ?? Dio(),
        _timeout = timeout;

  final String _baseUrl;
  final Dio _dio;
  final Duration _timeout;

  static String _normalizeBaseUrl(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    return trimmed.endsWith('/') ? trimmed.substring(0, trimmed.length - 1) : trimmed;
  }

  bool get configured => _baseUrl.isNotEmpty;

  Future<AppUpdateCheckResult> check({
    required String appId,
    required String platform,
    required String version,
    required int build,
    String deviceId = '',
  }) async {
    if (!configured) {
      throw const AppUpdateException(100100, '本地服务器未配置应用分发地址');
    }
    final Uri uri = Uri.parse('$_baseUrl/api/app_update/check').replace(
      queryParameters: <String, String>{
        'app': appId,
        'platform': platform,
        if (version.isNotEmpty) 'version': version,
        'build': '$build',
        if (deviceId.isNotEmpty) 'deviceId': deviceId,
      },
    );
    Response<dynamic> response;
    try {
      response = await _dio.getUri<dynamic>(
        uri,
        options: Options(
          // 业务错误用 HTTP 200 + code 返回；本地代理在上游故障时也可能回 4xx/5xx，
          // 全部按「读取 body 后判定」处理，不让 Dio 抛异常。
          validateStatus: (int? status) => status != null && status < 600,
          receiveTimeout: _timeout,
          sendTimeout: _timeout,
          headers: <String, dynamic>{'Accept': 'application/json'},
        ),
      );
    } on DioException catch (error) {
      throw AppUpdateException(-1, error.message ?? '更新查询失败');
    }

    final dynamic body = response.data;
    if (body is! Map) {
      throw AppUpdateException(-1, '更新查询响应格式非法');
    }
    final Map<String, dynamic> json = Map<String, dynamic>.from(body);
    final int code = _asInt(json['code']);
    if (code != 0) {
      throw AppUpdateException(code, json['msg']?.toString() ?? '更新查询失败');
    }
    return AppUpdateCheckResult.fromJson(json, appId: appId, platform: platform);
  }

  /// 重新取链（签名过期/被清理时使用）。
  Future<AppUpdateCheckResult> renew({
    required AppUpdateCheckResult previous,
    required String version,
    required int build,
    String deviceId = '',
  }) =>
      check(
        appId: previous.appId,
        platform: previous.platform,
        version: version,
        build: build,
        deviceId: deviceId,
      );

  static int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
