import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio/dio.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:potatokid_clipboard/app/apis.dart';
import 'package:potatokid_clipboard/framework/app/app_exceptions.dart';
import 'package:potatokid_clipboard/framework/net/dio/dio_helper.dart';
import 'package:potatokid_clipboard/framework/net/dio/dio_pretty_logger.dart';
import 'package:potatokid_clipboard/framework/net/dio/dio_request_interceptor.dart';
import 'package:potatokid_clipboard/framework/net/http_base_request.dart';
import 'package:potatokid_clipboard/framework/net/net_config.dart';
import 'package:potatokid_clipboard/framework/utils/app_log.dart';

/// 网络访问统一入口
class DioManager {
  final Dio _dio = Dio();

  static final DioManager _instance = DioManager._internal();

  factory DioManager() {
    return _instance;
  }

  /// 创建一个新的实例，新的dio，目前只用来测试
  /// 实际应用时请使用全局的单例 DioManager()
  factory DioManager.create() {
    return DioManager._internal();
  }

  DioManager._internal() {
    _init();
  }

  Dio get dio => _dio;

  late PersistCookieJar cookieJar;
  String cookieHeader = '';

  Future<void> _init() async {
    _dio.options
      ..baseUrl = Hosts.baseHost
      ..connectTimeout =
          const Duration(seconds: NetConfig.connectTimeout) // 设置超时时间
      ..receiveTimeout =
          const Duration(seconds: NetConfig.receiveTimeout) // 设置接收超时时间为预先定义的常量值
      ..sendTimeout =
          const Duration(seconds: NetConfig.sendTimeout); // 设置发送超时时间为预先定义的常量值

    cookieJar = PersistCookieJar(
        storage: FileStorage((await getApplicationDocumentsDirectory()).path));

    // 添加拦截器
    _dio.interceptors
      ..add(CookieManager(cookieJar))
      ..add(DioRequestInterceptor())
      ..add(DioLogInterceptor());

    // ..add(DioErrorInterceptor());  // 在 send 处理 ErrorUtils.showErrorToast(e);
    // charles抓包
    await DioHelper.addCharlesAdapter(_dio);

    // 配置代理
    // await configProxy(dio);  // test only
  }

  /// 获取当前域名的所有cookies
  Future<String> getCookies() async {
    final cookies =
        await cookieJar.loadForRequest(Uri.parse(_dio.options.baseUrl));
    return cookies.map((c) => '${c.name}=${c.value}').join(';');
  }

  Future<void> clearCookie() async {
    await cookieJar.deleteAll();
  }

  /// 注：网络访问的报错统一由状态管理处理，此处只抛出异常；异常由页面处理
  /// 可继承 BaseNetGetVm 或参考 BaseNetGetVm 的 loadUrl().responseWithStatus(this);
  /// class SettingsFQAController extends BaseNetGetVm
  /// 如果独立访问，请处理
  Future send({
    required String url,
    HttpMethod method = HttpMethod.GET,
    Map<String, dynamic> params = const {},
    Map<String, dynamic> headers = const {},
    CancelToken? cancelToken,
    int maxRetry = 3,
    int currentRetry = 0,
    ResponseType? responseType,
    bool tipError = true,
    String? contentType,
  }) async {
    Log.d(
        '[network][${DateTime.now()}] [${Hosts.baseHost}] $url, params: $params, headers: $headers');
    final List<ConnectivityResult> connectivityResult =
        await (Connectivity().checkConnectivity());
    if (connectivityResult.contains(ConnectivityResult.none)) {
      throw NetDisconnectException();
    }
    Response? response;
    try {
      // 适配代理, 每次访问前适配
      await DioHelper.addCharlesAdapter(_dio);
      // 请求
      if (method == HttpMethod.GET) {
        response = await _dio.get(url,
            queryParameters: params,
            options: Options(headers: headers, responseType: responseType),
            cancelToken: cancelToken);
      } else if (method == HttpMethod.POST) {
        response = await _dio.post(url,
            data: params,
            options: Options(
                headers: headers,
                contentType: contentType ?? Headers.formUrlEncodedContentType,
                responseType: responseType),
            cancelToken: cancelToken);
      } else {
        throw Exception('Invalid HTTP method');
      }
    } catch (e) {
      Log.e('assect network error: $e');

      if (currentRetry < maxRetry) {
        Log.i(
            'retry send: $url, currentRetry: $currentRetry, maxRetry: $maxRetry');
        currentRetry++;
        return send(
            url: url,
            method: method,
            params: params,
            headers: headers,
            cancelToken: cancelToken,
            maxRetry: maxRetry,
            currentRetry: currentRetry,
            responseType: responseType);
      }

      debugPrint(
          '[http access] send large than max retry: $url, currentRetry: $currentRetry, maxRetry: $maxRetry');
      rethrow;
    }

    // 返回
    if (response.statusCode == 200) {
      return response.data;
    }

    // return null;
    throw HttpCodeException(response.statusCode);
  }

  Future<Uint8List?> downloadToMemory(String url) async {
    Log.d('download file to memory: $url');
    try {
      // 适配代理, 每次访问前适配
      await DioHelper.addCharlesAdapter(_dio);

      // 发送 GET 请求并获取响应
      Response response = await _dio.get(
        url,
        options: Options(responseType: ResponseType.bytes), // 设置响应类型为字节流
      );

      // 检查响应状态码
      if (response.statusCode == 200) {
        // 获取字节数据
        Uint8List bytes = response.data;
        return bytes;
      } else {
        Log.e('Failed to download: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      Log.e('Error downloading: $e');
      return null;
    }
  }

  Future<File> renameFile(String src, String dst) async {
    return File(src).renameSync(dst);
  }

  /// 下载文件
  /// 如果下载失败后会抛出异常，需要自行处理
  /// 返回是否下载成功（文件是否存在）
  Future<bool> download({
    required String url,
    required String filename,
    ProgressCallback? onReceiveProgress,
  }) async {
    Log.d('download file: $url => $filename');
    // 适配代理, 每次访问前适配
    await DioHelper.addCharlesAdapter(_dio);
    await _dio.download(url, '$filename.downloading',
        options: Options(headers: {
          'cookie': DioManager().cookieHeader,
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Credentials': 'true',
        }),
        onReceiveProgress: onReceiveProgress);
    var file = await renameFile('$filename.downloading', filename);
    return file.existsSync();
  }

  Future<Response> dioDownload(
    String urlPath,
    dynamic savePath, {
    ProgressCallback? onReceiveProgress,
    Map<String, dynamic>? queryParameters,
    CancelToken? cancelToken,
    bool deleteOnError = true,
    String lengthHeader = Headers.contentLengthHeader,
    Object? data,
    Options? options,
  }) async {
// 适配代理, 每次访问前适配
    await DioHelper.addCharlesAdapter(_dio);
    return _dio.download(urlPath, savePath,
        onReceiveProgress: onReceiveProgress,
        queryParameters: queryParameters,
        cancelToken: cancelToken,
        deleteOnError: deleteOnError,
        lengthHeader: lengthHeader,
        data: data,
        options: options);
  }
}
