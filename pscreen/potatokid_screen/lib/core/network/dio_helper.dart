import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:potatokid_screen/core/network/dot_env_util.dart';

/// Dio 辅助：代理 / Charles 抓包适配（来自 myStar 方案）
class DioHelper {
  const DioHelper._();

  /// Charles 所在电脑的 IP（真机调试时替换为电脑局域网 IP，Android 模拟器为 10.0.2.2）
  static const String proxyHost = '10.0.2.2';
  static const int proxyPort = 8888;

  static Future<void> addCharlesAdapter(Dio dio) async {
    if (!DotEnvUtil.isForceOpenProxy) return;
    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.findProxy = (uri) => 'PROXY $proxyHost:$proxyPort';
        client.badCertificateCallback = (cert, host, port) => true;
        return client;
      },
    );
  }
}
