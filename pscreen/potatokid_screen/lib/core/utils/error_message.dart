import 'package:potatokid_screen/core/network/net_exceptions.dart';

/// 把网络/业务异常映射为可展示文案，供 BLoC 写入 State，由页面渲染。
String mapErrorToMessage(Object error) {
  switch (error.toNetErrorType()) {
    case NetErrorType.cancelled:
      return '请求已取消';
    case NetErrorType.disconnect:
      return '网络未连接，请检查网络后重试';
    case NetErrorType.httpError:
      return '服务异常，请稍后重试';
    case NetErrorType.businessError:
      if (error is RESTCodeException && (error.message?.isNotEmpty ?? false)) {
        return error.message!;
      }
      return '请求失败';
    case NetErrorType.dataError:
      return '数据解析失败';
    case NetErrorType.unknown:
      return '未知错误，请稍后重试';
  }
}
