// ignore_for_file: constant_identifier_names

class NetConfig {
  static const String DEFAULT_BASE_HOST = 'http://ptool.w1.luyouxia.net/';
  String baseHost;
  static const int connectTimeout = 10;
  static const int receiveTimeout = 10;
  static const int sendTimeout = 10;
  static const String CODE = 'code';
  static const String MSG = 'msg';
  static const String DATA = 'data';

  static NetConfig get instance => _instance;
  static final NetConfig _instance = NetConfig._internal();
  NetConfig._internal() : baseHost = DEFAULT_BASE_HOST;
}
