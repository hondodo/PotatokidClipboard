import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_screen/core/network/dio_manager.dart';

/// 记录最后一次请求的适配器：不发真实网络请求，直接返回成功 JSON。
class _RecordingAdapter implements HttpClientAdapter {
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    return ResponseBody.fromString(
      '{"code":0,"msg":"ok","data":{"sessions":[]}}',
      200,
      headers: <String, List<String>>{
        Headers.contentTypeHeader: <String>[Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fetchParentalSessions 查询参数与 path 分离，请求行不含 %3F', () async {
    final DioManager manager = DioManager();
    final _RecordingAdapter adapter = _RecordingAdapter();
    final HttpClientAdapter original = manager.dio.httpClientAdapter;
    manager.dio.httpClientAdapter = adapter;
    addTearDown(() => manager.dio.httpClientAdapter = original);

    await const ParentalAdminApi().fetchParentalSessions();

    final RequestOptions? request = adapter.last;
    expect(request, isNotNull, reason: '未捕获到请求');
    final Uri uri = request!.uri;

    // path 必须是纯 API 路径，问号只能出现在 query 中
    expect(uri.path, '/api/admin/parental/records');
    expect(uri.queryParameters, <String, String>{'limit': '200'});
    expect(uri.toString(), contains('/api/admin/parental/records?limit=200'));
    expect(uri.toString(), isNot(contains('%3F')));
  });
}
