// Home Assistant 连接/请求异常体系，供 Repository / Bloc 分层捕获与转换。

/// 与 Home Assistant 断开（网络不可达、连接被关闭）
class HaDisconnectException implements Exception {
  const HaDisconnectException([this.message]);

  final String? message;

  @override
  String toString() => 'ha disconnect${message == null ? '' : ': $message'}';
}

/// 认证失败（访问令牌无效或过期）
class HaAuthException implements Exception {
  const HaAuthException([this.message]);

  final String? message;

  @override
  String toString() => 'ha auth failed${message == null ? '' : ': $message'}';
}

/// 请求失败（HA 返回 success=false 或请求超时）
class HaRequestException implements Exception {
  const HaRequestException([this.code, this.message]);

  final int? code;
  final String? message;

  @override
  String toString() =>
      'ha request error, code: ${code ?? -1}\nmessage: ${message ?? 'none'}';
}

/// 数据解析失败（响应不是合法 JSON / 结构不符）
class HaDataException implements Exception {
  const HaDataException([this.response]);

  final dynamic response;

  @override
  String toString() => 'ha data parse error\nresponse: ${response ?? 'null'}';
}

/// 网络错误语义类型：供 BLoC 状态映射使用
enum NetErrorType {
  disconnect,
  authError,
  requestError,
  dataError,
  unknown,
}

extension NetExceptionX on Object {
  NetErrorType toNetErrorType() {
    final self = this;
    if (self is HaDisconnectException) return NetErrorType.disconnect;
    if (self is HaAuthException) return NetErrorType.authError;
    if (self is HaRequestException) return NetErrorType.requestError;
    if (self is HaDataException) return NetErrorType.dataError;
    return NetErrorType.unknown;
  }
}
