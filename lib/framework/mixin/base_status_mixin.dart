import 'package:get/get.dart';

/// 页面状态混入
mixin class BaseStatusMixin {
  var status = StatusContent().obs;

  onRetry() {}
  onCancel() {}
}

/// empty 合并到error
enum Status { loading, success, error, unknown }

enum StatusErrorCode {
  /// 未定义
  unknown,

  /// 正常访问
  none,

  /// 访问错误
  assectError,

  /// 未连接到网络
  disconnect,

  /// 用户取消
  cancelled,

  /// 数据解析错误(已返回数据，但数据里的内容空白 如： {'code': } 错误json数据)
  dataError,

  /// 返回空白数据（已返回数据，但数据里的内容空白 如： {'code': 0, 'data': [], 'message': '没有数据'}）
  dataEmpty,
}

class StatusContent {
  final StatusErrorCode code;
  final String message;
  final Status status;
  StatusContent(
      {this.code = StatusErrorCode.none,
      this.message = "",
      this.status = Status.success});

  /// 加载中
  factory StatusContent.loading() => StatusContent(
      code: StatusErrorCode.none, message: "", status: Status.loading);

  /// 取消；访问网络出错、404、503，超时，未连接、解析数据错误等
  factory StatusContent.error(
    StatusErrorCode code, {
    String message = "",
  }) =>
      StatusContent(code: code, message: message, status: Status.error);

  /// 加载完成、显示正文
  factory StatusContent.success() => StatusContent(
      code: StatusErrorCode.none, message: "", status: Status.success);
}
