// ignore_for_file: constant_identifier_names

import 'dart:io';

import 'package:dio/dio.dart' hide FormData;
import 'package:get/get_connect/http/src/multipart/form_data.dart';
import './dio/dio_manager.dart';

enum HttpMethod {
  GET,
  POST,
}

// MARK: - 抽象类，请勿在此类实行具体的逻辑
abstract class HttpBaseRequest {
  // 公共参数写在这里
  Map<String, dynamic> commonParams() {
    return {};
  }

  Future<Map<String, dynamic>> commonHeaders() async {
    Map<String, dynamic> header = {};
    return header;
  }

  //设置请求地址
  String url();

  //设置请求头
  Map<String, dynamic> headers() {
    return {};
  }

  //是否自动登录
  bool isAutoLogin() {
    return false;
  }

  //请求参数
  Map<String, dynamic> params();

  //请求类型
  HttpMethod httpMethod() {
    return HttpMethod.GET;
  }

  //文件源
  File? file() {
    return null;
  }

  //压缩包
  File? archive() {
    return null;
  }

  String? filesType() {
    return '';
  }

  FormData? formData() {
    return null;
  }

  /// 默认返回的是原始字符串，（即使返回的头部加了application/json，也会返回原始字符串）
  /// 如果希望返回json，则请重写此方法，并返回 ResponseType.json,
  /// 但如果交由dio处理json则比较慢，特别在json内容比较大时
  ResponseType responseType() {
    return ResponseType.plain;
  }

  /// 默认返回的是json对象，跟responseType()无关，这里是在resopnse后处理后端并校验用
  bool isJson() {
    return true;
  }

  CancelToken? cancelToken() {
    return null;
  }

  String? contentType() {
    return null;
  }

  /// 发送请求
  Future send(
    int? maxRetry, {
    bool tipError = true,
    String? contentType,
  }) async {
    // 合并参数
    Map<String, dynamic> mergedParams = Map.from(params())
      ..addAll(commonParams());
    Map<String, dynamic> sendHeaders = Map.from(headers())
      ..addAll(await commonHeaders());

    switch (httpMethod()) {
      case HttpMethod.GET:
        return DioManager().send(
            url: url(),
            params: mergedParams,
            headers: sendHeaders,
            maxRetry: maxRetry ?? 3,
            responseType: responseType(),
            tipError: tipError,
            cancelToken: cancelToken());
      case HttpMethod.POST:
        return DioManager().send(
            url: url(),
            params: mergedParams,
            method: HttpMethod.POST,
            headers: sendHeaders,
            maxRetry: maxRetry ?? 3,
            responseType: responseType(),
            tipError: tipError,
            cancelToken: cancelToken(),
            contentType: contentType);
      default:
        return null;
    }
  }
}
