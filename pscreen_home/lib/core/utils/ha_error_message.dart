import 'package:pscreen_home/core/network/ha_net_exceptions.dart';

/// 把网络/业务异常映射为可展示文案，供 BLoC 写入 State，由页面渲染。
String mapHaErrorToMessage(Object error) {
  switch (error.toNetErrorType()) {
    case HaErrorType.disconnect:
      return '与 Home Assistant 的连接已断开';
    case HaErrorType.authError:
      return '认证失败，请检查访问令牌';
    case HaErrorType.requestError:
      if (error is HaRequestException &&
          (error.message?.isNotEmpty ?? false)) {
        return error.message!;
      }
      return '指令执行失败';
    case HaErrorType.dataError:
      return '数据解析失败';
    case HaErrorType.unknown:
      return '未知错误，请稍后重试';
  }
}
