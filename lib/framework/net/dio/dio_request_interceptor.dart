import 'package:dio/dio.dart';

class DioRequestInterceptor extends Interceptor {
  //MARK: - 请求前拦截触发
  // @override
  // void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
  //   super.onRequest(options, handler);
  // LoggerUtil.d("请求前拦截触发");
  // 打印请求的地址
  // LoggerUtil.d('Request Url: ${options.uri}');
  // }

  //MARK: - 请求后拦截触发
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // super.onResponse(response, handler);
    // LoggerUtil.d("结束请求拦截触发,uri: ${response.requestOptions.uri}");
    // 在请求后的拦截器中可以执行一些操作，例如日志记录
    // LoggerUtil.f('Response: $response');

    return handler.next(response); // 继续后续操作
  }
}
