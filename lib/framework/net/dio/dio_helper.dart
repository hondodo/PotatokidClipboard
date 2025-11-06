// ignore_for_file: constant_identifier_names, deprecated_member_use

import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'package:native_flutter_proxy/native_flutter_proxy.dart';

import '../../utils/app_log.dart';

class DioHelper {
  static bool onceOpenProxy = false;

  /// 所有请求前添加代理（暂不做是否手动开启，是否为调试这些处理）
  static addCharlesAdapter(Dio dio) async {
    if (Platform.isIOS || Platform.isAndroid) {
    } else {
      debugPrint('[add Charles Adapter] skip: not ios or android');
      return;
    }

    String? host;
    int? port;

    if (Platform.isIOS && await checkIfEmulator()) {
      host ??= '127.0.0.1';
      port ??= 8888;
    } else {
      // 跟随系统代理时
      debugPrint('cannot get proxy, try get system proxy by channel method');

      ProxySetting settings = await NativeProxyReader.proxySetting;
      if (settings.enabled) {
        host = settings.host;
        port = settings.port;
      }
    }

    dio.httpClientAdapter = DefaultHttpClientAdapter();
    (dio.httpClientAdapter as DefaultHttpClientAdapter).onHttpClientCreate =
        (client) {
      client.findProxy = (uri) {
        var proxyStr =
            host == null || port == null ? 'DIRECT' : 'PROXY $host:$port';
        Log.i('proxy on, dio proxy: $proxyStr');
        return proxyStr;
      };
      client.badCertificateCallback = (cert, host, port) => true;
      return null;
    };
  }

  static void clearProxy(Dio dio) {
    dio.httpClientAdapter = DefaultHttpClientAdapter();
    (dio.httpClientAdapter as DefaultHttpClientAdapter).onHttpClientCreate =
        (client) {
      client.findProxy = (uri) {
        var proxyStr = 'DIRECT';
        Log.i('proxy off, dio proxy: $proxyStr');
        return proxyStr;
      };
      return null;
    };
  }

  static Future<bool> checkIfEmulator() async {
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      // Android 还是需要代理，不然无法看到接口返回的数据
      return kReleaseMode;
    } else {
      IosDeviceInfo iosInfo = await deviceInfo.iosInfo;
      return !iosInfo.isPhysicalDevice;
    }
  }
}
