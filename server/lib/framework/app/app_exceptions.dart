class RESTResultFormat {
  /// 因不同接口的返回内容不同
  /// 定义了不同接口返回的key及成功标志
  RESTResultFormat(this.codeKey, this.msgKey, this.dataKey, this.successValue);

  String codeKey;
  String msgKey;
  String dataKey;
  dynamic successValue;
}

class NetDisconnectException implements Exception {
  /// 网络未连接（断网）错误
  NetDisconnectException();

  @override
  String toString() {
    return 'network not connect';
  }
}

class HttpCodeException implements Exception {
  /// 访问错误，超时、httpcode 不为 200等
  HttpCodeException([this.httpCode, this.message]);

  final int? httpCode;
  final String? message;

  @override
  String toString() {
    return 'http assect error, code: ${httpCode ?? -1}\nmessage:${message ?? 'none'}';
  }
}

class RESTCodeException implements Exception {
  /// json 数据的code不等于0
  RESTCodeException([this.restCode, this.message, this.data]);

  final int? restCode;
  final String? message;

  final dynamic data;

  @override
  String toString() {
    return 'json result error, code: ${restCode ?? -1}\nmessage:${message ?? 'none'}';
  }
}

class ContentNotJsonException implements Exception {
  /// 数据不是json错误
  ContentNotJsonException([this.response]);

  final dynamic response;

  @override
  String toString() {
    return 'data is not json\nresponse:${response ?? 'null'}';
  }
}
