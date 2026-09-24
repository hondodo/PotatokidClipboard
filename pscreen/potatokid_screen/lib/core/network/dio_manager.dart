import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:path_provider/path_provider.dart';
import 'package:potatokid_screen/app/config/app_constants.dart';
import 'package:potatokid_screen/app/hosts/app_hosts.dart';
import 'package:potatokid_screen/core/logging/log_service.dart';
import 'package:potatokid_screen/core/network/dio_helper.dart';
import 'package:potatokid_screen/core/network/http_method.dart';
import 'package:potatokid_screen/core/network/net_exceptions.dart';

/// 网络访问入口（单例）：连通性检查、重试、Cookie 持久化、代理适配、会话级取消。
/// 只负责 HTTP 收发，不做业务判断（业务错误交由 Repository / Bloc 处理）。
class DioManager {
  DioManager._internal() {
    _init();
  }

  static final DioManager _instance = DioManager._internal();

  /// 全局单例
  factory DioManager() => _instance;

  /// 允许创建独立实例（测试用）
  factory DioManager.create() => DioManager._internal();

  final Dio _dio = Dio();

  Dio get dio => _dio;

  CancelToken _sessionCancelToken = CancelToken();
  PersistCookieJar? _cookieJar;

  Future<void> _init() async {
    _dio.options
      ..baseUrl = AppHosts.baseHost
      ..connectTimeout = AppConstants.connectTimeout
      ..receiveTimeout = AppConstants.receiveTimeout
      ..sendTimeout = AppConstants.sendTimeout;

    try {
      final dir = await getApplicationDocumentsDirectory();
      _cookieJar = PersistCookieJar(storage: FileStorage(dir.path));
      _dio.interceptors.add(CookieManager(_cookieJar!));
    } catch (e, s) {
      const LogService().error('DioManager cookie 初始化失败', error: e, stackTrace: s);
    }

    await DioHelper.addCharlesAdapter(_dio);
  }

  Future<List<Cookie>> getCookies() async {
    final jar = _cookieJar;
    if (jar == null) return const <Cookie>[];
    return jar.loadForRequest(Uri.parse(AppHosts.baseHost));
  }

  /// 切换域名：登录后切 apiHost，未登录切 baseHost
  static Future<void> changeHost({bool? isLogin}) async {
    _instance._dio.options.baseUrl =
        (isLogin ?? false) ? AppHosts.apiHost : AppHosts.baseHost;
  }

  /// 登出时取消会话内所有进行中的请求
  void cancelSessionRequestsOnLogout() {
    _sessionCancelToken.cancel('logout');
    _sessionCancelToken = CancelToken();
  }

  Future<dynamic> send({
    required String url,
    HttpMethod method = HttpMethod.GET,
    Map<String, dynamic> params = const {},
    Map<String, dynamic> headers = const {},
    CancelToken? cancelToken,
    int maxRetry = AppConstants.defaultMaxRetry,
    int currentRetry = 0,
    ResponseType? responseType,
    bool tipError = true,
    bool notTipNetError = false,
    String? contentType,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    Duration? sendTimeout,
  }) async {
    final connected = await _checkConnectivity();
    if (!connected) {
      if (!notTipNetError) {
        const LogService().warn('网络未连接: $url');
      }
      throw const NetDisconnectException();
    }

    try {
      final response = await _dio.request<dynamic>(
        url,
        data: method == HttpMethod.GET ? null : (params.isEmpty ? null : params),
        queryParameters: method == HttpMethod.GET ? params : null,
        options: Options(
          method: method.name,
          responseType: responseType ?? ResponseType.json,
          contentType: contentType,
          headers: headers.isEmpty ? null : headers,
          connectTimeout: connectTimeout,
          receiveTimeout: receiveTimeout,
          sendTimeout: sendTimeout,
        ),
        cancelToken: cancelToken ?? _sessionCancelToken,
      );

      final statusCode = response.statusCode ?? -1;
      if (statusCode >= 200 && statusCode < 300) {
        return response.data;
      }
      throw HttpCodeException(statusCode, '请求失败');
    } on DioException catch (e, s) {
      if (e.type == DioExceptionType.cancel) rethrow;
      if (currentRetry < maxRetry && _shouldRetry(e)) {
        return send(
          url: url,
          method: method,
          params: params,
          headers: headers,
          cancelToken: cancelToken,
          maxRetry: maxRetry,
          currentRetry: currentRetry + 1,
          responseType: responseType,
          tipError: tipError,
          notTipNetError: notTipNetError,
          contentType: contentType,
          connectTimeout: connectTimeout,
          receiveTimeout: receiveTimeout,
          sendTimeout: sendTimeout,
        );
      }
      const LogService().error('请求异常: $url', error: e, stackTrace: s);
      throw HttpCodeException(e.response?.statusCode, e.message);
    }
  }

  bool _shouldRetry(DioException e) =>
      e.type == DioExceptionType.connectionTimeout ||
      e.type == DioExceptionType.receiveTimeout ||
      e.type == DioExceptionType.sendTimeout ||
      e.type == DioExceptionType.connectionError;

  Future<bool> _checkConnectivity() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return true;
    }
  }
}
