import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pscreen_home/core/server/server_api.dart';
import 'package:pscreen_home/features/parental/data/parental_admin_api.dart';
import 'package:pscreen_screen/core/network/dio_manager.dart';

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.responseBody);

  final String responseBody;
  RequestOptions? last;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    last = options;
    return ResponseBody.fromString(
      responseBody,
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

  void useAdapter(_RecordingAdapter adapter) {
    final DioManager manager = DioManager();
    final HttpClientAdapter original = manager.dio.httpClientAdapter;
    manager.dio.httpClientAdapter = adapter;
    addTearDown(() => manager.dio.httpClientAdapter = original);
  }

  test('requestClaimTicket 命中 ticket 端点并解析凭证', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      '{"code":0,"msg":"ok","data":{"claimToken":"clm.abc","expiresIn":600}}',
    );
    useAdapter(adapter);

    final String token = await const ParentalAdminApi().requestClaimTicket();

    expect(token, 'clm.abc');
    expect(adapter.last!.uri.path, '/api/admin/claim/ticket');
    expect(adapter.last!.method, 'POST');
  });

  test('claimAccount 提交登录名与凭证，并返回服务端确认的新名', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      '{"code":0,"msg":"ok","data":{"account":"mama_01","password":"r4nd0m-token","changed":["machines.json"]}}',
    );
    useAdapter(adapter);

    final ClaimAccountResult result = await const ParentalAdminApi().claimAccount(
      account: '  mama_01  ',
      claimToken: 'clm.abc',
    );

    expect(result.account, 'mama_01');
    expect(result.password, 'r4nd0m-token');
    expect(adapter.last!.uri.path, '/api/admin/claim');
    expect(adapter.last!.method, 'POST');
    final String payload = adapter.last!.data.toString();
    expect(payload, contains('mama_01'));
    expect(payload, contains('clm.abc'));
  });

  test('服务端业务失败抛出带 msg 的异常', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      '{"code":1,"msg":"凭证无效或已过期，请重新获取"}',
    );
    useAdapter(adapter);

    expect(
      () => const ParentalAdminApi().claimAccount(
        account: 'mama_01',
        claimToken: 'expired',
      ),
      throwsA(isA<ServerApiException>().having(
        (ServerApiException e) => e.message,
        'message',
        contains('凭证'),
      )),
    );
  });

  test('服务端未返回凭证时明确报错', () async {
    final _RecordingAdapter adapter =
        _RecordingAdapter('{"code":0,"msg":"ok","data":{}}');
    useAdapter(adapter);

    expect(
      () => const ParentalAdminApi().requestClaimTicket(),
      throwsA(isA<ServerApiException>()),
    );
  });

  test('服务端未返回新口令时明确报错', () async {
    final _RecordingAdapter adapter = _RecordingAdapter(
      '{"code":0,"msg":"ok","data":{"account":"mama_01"}}',
    );
    useAdapter(adapter);

    expect(
      () => const ParentalAdminApi().claimAccount(
        account: 'mama_01',
        claimToken: 'clm.abc',
      ),
      throwsA(isA<ServerApiException>().having(
        (ServerApiException e) => e.message,
        'message',
        contains('口令'),
      )),
    );
  });
}
