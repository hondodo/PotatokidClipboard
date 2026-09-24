import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:potatokid_screen/core/network/dio_manager.dart';
import 'package:potatokid_screen/core/network/http_method.dart';
import 'package:potatokid_screen/core/network/net_exceptions.dart';

/// 网络访问基类：子类只声明「我要什么」，公共参数/Header 合并与派发由基类完成。
///
/// 用法：
/// ```dart
/// class _GetProfileRequest extends HttpBaseRequest {
///   @override
///   String url() => '/api/profile';
///   @override
///   Map<String, dynamic> params() => {};
/// }
/// ```
abstract class HttpBaseRequest {
  /// 公共参数（可覆盖）
  Map<String, dynamic> commonParams() => <String, dynamic>{};

  /// 公共 Header（设备信息、Token 等，可覆盖）
  Future<Map<String, dynamic>> commonHeaders() async => <String, dynamic>{};

  // ---------------- 以下由子类实现 ----------------

  /// 请求地址（必填）
  String url();

  /// 请求参数（必填）
  Map<String, dynamic> params();

  /// 私有 Header
  Map<String, dynamic> headers() => <String, dynamic>{};

  /// 请求方法
  HttpMethod httpMethod() => HttpMethod.GET;

  /// 原始字符串优先，大 JSON 解析更快
  ResponseType responseType() => ResponseType.plain;

  /// 响应后是否按 JSON 校验
  bool isJson() => true;

  /// 是否自动登录
  bool isAutoLogin() => false;

  CancelToken? cancelToken() => null;

  String? contentType() => null;

  Duration? connectTimeout() => null;

  Duration? receiveTimeout() => null;

  Duration? sendTimeout() => null;

  /// 统一发送：合并 params+commonParams、headers+commonHeaders，再派发给 DioManager
  Future<dynamic> send(
    int? maxRetry, {
    bool tipError = true,
    bool notTipNetError = false,
    String? contentType,
  }) async {
    final mergedParams = <String, dynamic>{...commonParams(), ...params()};
    final mergedHeaders = <String, dynamic>{...await commonHeaders(), ...headers()};

    final raw = await DioManager().send(
      url: url(),
      method: httpMethod(),
      params: mergedParams,
      headers: mergedHeaders,
      cancelToken: cancelToken(),
      maxRetry: maxRetry ?? 2,
      responseType: responseType(),
      tipError: tipError,
      notTipNetError: notTipNetError,
      contentType: contentType ?? this.contentType(),
      connectTimeout: connectTimeout(),
      receiveTimeout: receiveTimeout(),
      sendTimeout: sendTimeout(),
    );

    if (raw is String && isJson()) {
      if (raw.isEmpty) {
        throw ContentNotJsonException(raw);
      }
      try {
        return jsonDecode(raw);
      } catch (_) {
        throw ContentNotJsonException(raw);
      }
    }
    return raw;
  }
}
