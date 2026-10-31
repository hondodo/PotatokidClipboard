import 'dart:io';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/services.dart';

Future<void> configProxy(Dio dio) async {
  if (!Platform.isAndroid && !Platform.isIOS) return;

  var systemProxy = await getSystemProxy();
  if (systemProxy != null) {
    (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.findProxy = (uri) {
        return 'PROXY ${systemProxy.host}:${systemProxy.port}';
      };

      // 如果需要忽略证书验证
      client.badCertificateCallback = (cert, host, port) => true;

      return client;
    };
  }
}

/// 获取系统代理，安卓启动时用第三方的会获取不到
/// 当前只做了安卓的，如果需要支持ios，请在_getProxyHost和_getProxyPort中添加对应的实现，需要在原生部分注册对应的MethodChannel
Future<ProxyConfig?> getSystemProxy() async {
  try {
    if (Platform.isIOS) {
      final host = await _getProxyHost();
      final port = await _getProxyPort();
      if (host != null && port != null) {
        return ProxyConfig(host, port);
      }
    } else if (Platform.isAndroid) {
      final host = await _getProxyHost();
      final port = await _getProxyPort();
      if (host != null && port != null) {
        return ProxyConfig(host, port);
      }
    }
  } catch (e) {
    print('获取系统代理设置失败: $e');
  }
  return null;
}

Future<String?> _getProxyHost() async {
  if (Platform.isIOS) {
    return await const MethodChannel('flutter_proxy')
        .invokeMethod<String>('getProxyHost');
  } else if (Platform.isAndroid) {
    return await const MethodChannel('flutter_proxy')
        .invokeMethod<String>('getProxyHost');
  }
  return null;
}

Future<int?> _getProxyPort() async {
  if (Platform.isIOS) {
    return await const MethodChannel('flutter_proxy')
        .invokeMethod<int>('getProxyPort');
  } else if (Platform.isAndroid) {
    return await const MethodChannel('flutter_proxy')
        .invokeMethod<int>('getProxyPort');
  }
  return null;
}

class ProxyConfig {
  final String host;
  final int port;

  ProxyConfig(this.host, this.port);
}
