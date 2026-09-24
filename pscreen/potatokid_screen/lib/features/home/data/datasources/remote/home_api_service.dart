import 'package:dio/dio.dart';
import 'package:potatokid_screen/core/network/http_base_request.dart';
import 'package:potatokid_screen/core/network/http_method.dart';

/// 首页接口定义层：每个接口对应一个 [HttpBaseRequest] 子类。
/// 只声明「请求什么」，公共参数/Header/派发由基类完成。
class HomeApiService {
  /// 拉取首页列表
  Future<List<dynamic>> fetchHomeList() async {
    final dynamic result = await _FetchHomeListRequest().send(2);
    if (result is List) return result;
    if (result is Map<String, dynamic> && result['list'] is List) {
      return result['list'] as List<dynamic>;
    }
    return const <dynamic>[];
  }
}

class _FetchHomeListRequest extends HttpBaseRequest {
  @override
  String url() => '/api/home/list';

  @override
  Map<String, dynamic> params() => <String, dynamic>{};

  @override
  HttpMethod httpMethod() => HttpMethod.GET;

  @override
  ResponseType responseType() => ResponseType.plain;
}
