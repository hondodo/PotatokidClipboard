import 'package:dio/dio.dart';

/// 断网 / 无连通性
class NetDisconnectException implements Exception {
  const NetDisconnectException();

  @override
  String toString() => 'network not connect';
}

/// HTTP 层错误（超时、状态码非 2xx 等）
class HttpCodeException implements Exception {
  const HttpCodeException([this.httpCode, this.message]);

  final int? httpCode;
  final String? message;

  @override
  String toString() =>
      'http assect error, code: ${httpCode ?? -1}\nmessage:${message ?? 'none'}';
}

/// 业务层错误（响应体 code != 成功值）
class RESTCodeException implements Exception {
  const RESTCodeException([this.restCode, this.message, this.data]);

  final int? restCode;
  final String? message;
  final dynamic data;

  @override
  String toString() =>
      'json result error, code: ${restCode ?? -1}\nmessage:${message ?? 'none'}';
}

/// 响应不是合法 JSON
class ContentNotJsonException implements Exception {
  const ContentNotJsonException([this.response]);

  final dynamic response;

  @override
  String toString() => 'data is not json\nresponse:${response ?? 'null'}';
}

/// 网络错误语义类型：供 BLoC 状态映射使用
enum NetErrorType { cancelled, disconnect, httpError, businessError, dataError, unknown }

/// 页面/UI 状态码：由 NetErrorType 映射得到
enum StatusErrorCode { cancelled, disconnect, assectError, dataError, unknown }

extension NetExceptionX on Object {
  NetErrorType toNetErrorType() {
    final self = this;
    if (self is NetDisconnectException) return NetErrorType.disconnect;
    if (self is HttpCodeException) return NetErrorType.httpError;
    if (self is RESTCodeException) return NetErrorType.businessError;
    if (self is ContentNotJsonException) return NetErrorType.dataError;
    if (self is DioException && self.type == DioExceptionType.cancel) {
      return NetErrorType.cancelled;
    }
    return NetErrorType.unknown;
  }
}

extension NetErrorTypeX on NetErrorType {
  StatusErrorCode toStatusErrorCode() {
    switch (this) {
      case NetErrorType.cancelled:
        return StatusErrorCode.cancelled;
      case NetErrorType.disconnect:
        return StatusErrorCode.disconnect;
      case NetErrorType.httpError:
        return StatusErrorCode.assectError;
      case NetErrorType.businessError:
        return StatusErrorCode.assectError;
      case NetErrorType.dataError:
        return StatusErrorCode.dataError;
      case NetErrorType.unknown:
        return StatusErrorCode.unknown;
    }
  }
}
