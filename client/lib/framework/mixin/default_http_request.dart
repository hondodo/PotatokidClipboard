import 'dart:io';

import 'package:dio/dio.dart' hide FormData;
import 'package:flutter/foundation.dart';
import 'package:get/get_connect/http/src/multipart/form_data.dart';
import 'package:potatokid_clipboard/framework/net/http_base_request.dart';
import 'package:potatokid_clipboard/framework/net/mixin/request_mixin.dart';

// 通用的API请求类，便捷使用接口调用
class DefaultHttpRequest extends HttpBaseRequest {
  String apiUrl;
  Map<String, dynamic> map;
  Map<String, dynamic> apiHeaders;
  HttpMethod method;
  bool isAutomaticLogin;
  File? fileSource;
  File? archiveSource;
  FormData? formDataSource;
  String filesTypes;
  String? baseUrl;
  bool tipError;
  int maxRetry;
  CancelToken? inCancelToken;
  String? inContentType;

  DefaultHttpRequest({
    required this.apiUrl,
    this.map = const {},
    this.method = HttpMethod.GET,
    this.fileSource,
    this.archiveSource,
    this.filesTypes = '',
    this.apiHeaders = const {},
    this.formDataSource,
    this.isAutomaticLogin = false,
    this.baseUrl,
    this.tipError = true,
    this.maxRetry = 3,
    this.inCancelToken,
    this.inContentType = Headers.formUrlEncodedContentType,
  });

  @override
  Map<String, dynamic> headers() {
    return super.headers()..addAll(apiHeaders);
  }

  @override
  bool isAutoLogin() => isAutomaticLogin;

  @override
  HttpMethod httpMethod() => method;

  @override
  Map<String, dynamic> params() => map;

  @override
  String url() {
    if (baseUrl == null) {
      return apiUrl;
    }
    var uri = Uri.tryParse(apiUrl);
    if (uri != null && uri.scheme.isNotEmpty) {
      // 已有 http:// https:// ftp:// 等头部，不处理
      return apiUrl;
    }
    String bUrl = baseUrl!;
    if (bUrl.endsWith('/')) {
      bUrl = bUrl.substring(0, bUrl.length - 1);
    }
    bUrl = '$bUrl$apiUrl';
    debugPrint('[modify] http request uri: $bUrl');
    return bUrl;
  }

  @override
  File? file() => fileSource;

  @override
  File? archive() => archiveSource;

  @override
  String filesType() => filesTypes;

  @override
  FormData? formData() => formDataSource;

  @override
  CancelToken? cancelToken() => inCancelToken;

  @override
  String? contentType() => inContentType;

  Future<dynamic> sendDataRequest(RequestMixin miMix) =>
      miMix.sendDataRequest(this, tipError: tipError, maxRetry: maxRetry);
}

extension GetHttpRequest on String {
  /// 获取网络请求
  DefaultHttpRequest getHttpRequestWithApi({
    Map<String, dynamic> params = const {},
    Map<String, dynamic> body = const {},
    Map<String, dynamic> headers = const {},
    HttpMethod httpMethod = HttpMethod.GET,
    File? fileSource,
    File? archiveSource,
    FormData? formData,
    String filesTypes = '',
    String? baseUrl,
    bool tipError = true,
    maxRetry = 3,
    CancelToken? inCancelToken,
    String contentType = Headers.formUrlEncodedContentType,
  }) =>
      DefaultHttpRequest(
          apiUrl: this,
          map: params,
          method: httpMethod,
          formDataSource: formData,
          fileSource: fileSource,
          archiveSource: archiveSource,
          filesTypes: filesTypes,
          apiHeaders: headers,
          baseUrl: baseUrl,
          tipError: tipError,
          maxRetry: maxRetry,
          inCancelToken: inCancelToken,
          inContentType: contentType);
}
